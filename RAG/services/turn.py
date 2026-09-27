"""
One chat turn.

The backend forwards each patient message to `/chat`; the agent call, server-side
urgency recalculation, and session bookkeeping stay in this single path.
"""
import asyncio
import json
import re
from datetime import datetime, timezone

from pydantic import ValidationError

import services.database as db
import services.report as report
from schemas.triage import AgentTurn
from services.chat_agent import get_agent
from services.knowledge import check_symptoms
from services.vector_db import query_symptoms


class TurnError(RuntimeError):
    """The agent could not be called, or answered with something unusable."""


class PoisonedHistory(TurnError):
    """The stored history has a function_call with no response after it.

    Nothing in this session can succeed again: every turn replays the same broken
    history and Gemini rejects it before the model is even reached. Recoverable
    only by discarding that history and replaying the transcript onto a clean one
    The chat client can retry after starting a new session.
    """


# Gemini's wording for the dangling function_call. Matched on text because agno
# surfaces it as a plain provider error with no code to switch on -- and mangles
# the body it attaches (an uncalled ClientResponse.text bound method), so the
# message is the only reliable signal left.
_POISON_MARKER = "function call turn comes immediately after"


def _is_poisoned(error: BaseException) -> bool:
    return _POISON_MARKER in str(error)


def _is_provider_failure(content: object) -> bool:
    """The 'answer' is agno's error text, not the model's output.

    agno builds that text from an uncalled ClientResponse.text, so what lands in
    content is the repr of a bound method rather than the provider's message. The
    real reason is only in agno's own log, which leaves the repr as the one thing
    we can actually test for.
    """
    return isinstance(content, str) and "<bound method" in content


def _is_rate_limited(error: BaseException, content: object = None) -> bool:
    text = f"{error} {content}".casefold()
    return any(marker in text for marker in ("429", "resource_exhausted", "quota exceeded"))


def _normalise_model_json(content: str) -> str:
    """Coerce Gemma's compact MCQ string into the AgentTurn shape."""
    payload = json.loads(content)
    for field in ("running_urgency_score",):
        value = payload.get(field)
        if isinstance(value, (int, float)):
            payload[field] = max(0, min(100, value))
    if isinstance(payload.get("report"), dict):
        report_payload = payload["report"]
        score = payload.get("running_urgency_score", 0)
        report_payload.setdefault("symptoms_described", payload.get("identified_symptoms") or ["unspecified symptoms"])
        report_payload.setdefault("urgency_score", score)
        report_payload.setdefault("urgency_breakdown", [score])
        report_payload.setdefault("recommended_specialty", "general_medicine")
        report_payload.setdefault("possible_diagnosis", None)
        report_payload.setdefault("confidence_score", None)
        report_payload.setdefault("rationale", report_payload.get("summary"))
        value = report_payload.get("urgency_score")
        if isinstance(value, (int, float)):
            report_payload["urgency_score"] = max(0, min(100, value))
    elif isinstance(payload.get("report"), str):
        score = payload.get("running_urgency_score", 0)
        payload["report"] = {
            "symptoms_described": payload.get("identified_symptoms") or ["unspecified symptoms"],
            "urgency_score": score,
            "urgency_breakdown": [score],
            "recommended_specialty": "general_medicine",
            "possible_diagnosis": None,
            "confidence_score": None,
            "rationale": payload["report"].strip(),
        }
    follow_up = payload.get("follow_up")
    if isinstance(follow_up, str):
        option_start = re.search(r"\bA\)\s*", follow_up)
        options = [match.group(2).strip(" ,") for match in re.finditer(
            r"(?<!\w)([A-E])\)\s*(.*?)(?=\s+[A-E]\)\s*|,\s*[A-E]\)\s*|$)",
            follow_up,
        )]
        if option_start and len(options) >= 2:
            question = follow_up[:option_start.start()].strip()
            payload["follow_up"] = {"question": question, "options": options}
    return json.dumps(payload)


def _hospital_context(hospitals: list[dict]) -> str:
    if not hospitals:
        return "No hospital directory was supplied."
    return "\n".join(
        f"- {hospital.get('name')} (id={hospital.get('id')}, distance_km={hospital.get('distance_km')}, "
        f"specialties={', '.join(hospital.get('specialties') or [])})"
        for hospital in hospitals
    )


async def _run_agent(session_id: str, turn_message: str) -> tuple[AgentTurn, str]:
    """One agent call, with whatever it returns coerced into an AgentTurn.

    Deliberately no retry on a parse failure. A call that dies mid tool-use leaves
    a function_call turn with no response after it in the agent's stored history,
    and replaying that history is rejected outright -- "Please ensure that function
    call turn comes immediately after a user turn or after a function response
    turn" -- which poisons every later turn in the conversation, not just this one.
    One clean failure the patient can retry beats a silently broken thread.
    """
    try:
        agent, session_id = await get_agent(session_id=session_id)
        run_response = await asyncio.wait_for(agent.arun(turn_message), timeout=15)
        content = run_response.content
        turn = (
            content
            if isinstance(content, AgentTurn)
            else AgentTurn.model_validate_json(_normalise_model_json(content))
            if isinstance(content, str)
            else AgentTurn.model_validate(content)
        )
    except asyncio.TimeoutError as e:
        raise TurnError("AI provider timed out; retry later.") from e
    except ValidationError as e:
        # A provider failure does not come back as an exception: agno puts its own
        # error text where the model's answer should be, and it fails to parse.
        # That is a different problem from a model that answered badly, and needs
        # a different answer -- see PoisonedHistory.
        if _is_rate_limited(e, locals().get("content")):
            raise TurnError("AI provider quota is exhausted; retry after the quota resets.") from e
        if _is_provider_failure(locals().get("content")):
            raise TurnError("AI provider did not return a usable response; retry later.") from e
        if _is_poisoned(e):
            raise PoisonedHistory(f"Agent history rejected by the provider: {e}") from e
        raise TurnError(f"Agent returned an invalid triage response: {e}") from e
    except Exception as e:
        if _is_rate_limited(e):
            raise TurnError("AI provider quota is exhausted; retry after the quota resets.") from e
        if _is_poisoned(e):
            raise PoisonedHistory(f"Agent history rejected by the provider: {e}") from e
        raise TurnError(f"Agent could not be called: {e}") from e
    return turn, session_id


def _missing_payload(turn: AgentTurn) -> bool:
    """The agent named an action but did not supply what that action needs."""
    return (
        (turn.action == "ask_question" and turn.follow_up is None)
        or (turn.action == "generate_report" and turn.report is None)
    )


async def run_turn(
    session_id: str | None,
    user_query: str,
    hospitals: list[dict] | None = None,
) -> tuple[AgentTurn, str, dict]:
    """Advance one session by one patient message.

    Returns the agent's turn, the session id it ran under, and the session state
    after the update. Urgency is recomputed here from the symptoms table rather
    than trusted from the model: the agent proposes symptoms, the database scores
    them.
    """
    session_id = db.add_session(session_id)
    report.init_session_state(session_id)
    state = report.get_session_state(session_id)

    force = report.force_report(state, user_query)
    keep_asking = report.must_keep_asking(state, user_query)
    turn_message = report.build_turn_message(user_query, state, force, keep_asking)
    turn_message += "\n\nSymptom knowledge-base context:\n" + query_symptoms(user_query)
    turn_message += "\n\nHospital directory:\n" + _hospital_context(hospitals or [])

    turn, session_id = await _run_agent(session_id, turn_message)

    # The directive alone does not always hold -- the model will still try to
    # finalize off one sentence. One retry, then take whatever comes back: an
    # interview one question short beats failing the patient's turn outright.
    if keep_asking and turn.action == "generate_report":
        retry, session_id = await _run_agent(
            session_id,
            turn_message
            + " Your previous answer tried to finalize the report. That was rejected"
            " because the interview is too short. Ask one more multiple-choice"
            " question instead.",
        )
        if retry.action == "ask_question" and retry.follow_up is not None:
            turn = retry

    # A turn that announces an action and then omits it is the model contradicting
    # itself, not a broken call: it parsed cleanly, so the stored history is
    # well-formed and re-asking is safe. (Retrying an unparseable answer is not --
    # see _run_agent.) One corrective attempt, then give up honestly.
    if _missing_payload(turn):
        turn, session_id = await _run_agent(
            session_id,
            turn_message
            + f" Your previous answer set action='{turn.action}' but left the matching"
            " field empty, so it could not be used. Answer again and fill it in.",
        )
    if turn.action == "ask_question" and turn.follow_up is None:
        raise TurnError("Agent chose to ask a question but produced no follow-up.")
    if turn.action == "generate_report" and turn.report is None:
        raise TurnError("Agent chose to generate a report but produced none.")

    # identified_symptoms is optional in the schema, and a model that omits it
    # would score the patient at zero urgency. The report names its symptoms too,
    # so take the union rather than trusting one field.
    named = list(turn.identified_symptoms)
    if turn.report is not None:
        named += turn.report.symptoms_described
    confirmed = check_symptoms(named)
    merged_symptoms, server_score, _ = report.apply_confirmed_symptoms(
        state["identified_symptoms"], state["total_urgency_score"], confirmed,
    )
    breakdown = [float(s["urgency_score"]) for s in check_symptoms(merged_symptoms)]

    turn.running_urgency_score = server_score
    if turn.report is not None:
        turn.report = report.apply_server_urgency(turn.report, server_score, breakdown)
        if turn.action == "generate_report":
            report.save_report(session_id, turn.report)

    now = datetime.now(timezone.utc)
    db.add_entry(session_id, role="user", content=user_query, timestamp=now.isoformat())
    db.add_entry(session_id, role="assistant", content=turn.model_dump_json(),
                 timestamp=datetime.now(timezone.utc).isoformat())

    questions_asked = state["questions_asked"] + (1 if turn.action == "ask_question" else 0)
    status = "completed" if turn.action == "generate_report" else "in_progress"
    report.update_session_state(session_id, server_score, questions_asked, merged_symptoms, status=status)

    return turn, session_id, {
        "questions_asked": questions_asked,
        "total_urgency_score": server_score,
        "identified_symptoms": merged_symptoms,
        "status": status,
    }
