"""
Turn-control logic and report finalization for the triage agent. This file only tracks session state and
guarantees the final report is clean JSON.
"""
import json
from schemas.triage import PreliminaryReport
from uuid import UUID
from pydantic import ValidationError

MAX_QUESTIONS = 7
# symptoms.urgency_score is 0-100, where a single genuine emergency already
# scores in the 90s. Was 50, which every serious symptom cleared on its own.
TOTAL_URGENCY_LIMIT = 85
MAX_URGENCY_SCORE = 100

# How many follow-ups must be asked before a report is allowed at all.
#
# These exist because urgency alone used to end the interview. "chest pain"
# scores 45 and "shortness of breath" 40, so a patient naming both in their first
# message cleared TOTAL_URGENCY_LIMIT immediately and got a report built out of a
# single sentence. A high score means hurry, not skip the intake, so an alarming
# opening now shortens the interview instead of cancelling it.
MIN_QUESTIONS = 4
MIN_QUESTIONS_URGENT = 2

FORCE_PHRASES = (
    "generate my report",
    "generate the report",
    "give me the report",
    "finalize",
    "i am done",
    "it's urgent",
    "its urgent",
    "too painful",
)


def patient_asked_to_finish(user_query: str) -> bool:
    """The patient's own request to stop. Honoured immediately -- the floors are
    here to stop the agent cutting the interview short, never the patient."""
    normalized_query = " ".join(user_query.casefold().split())
    return any(phrase in normalized_query for phrase in FORCE_PHRASES)


def _question_floor(state: dict) -> int:
    return (
        MIN_QUESTIONS_URGENT
        if state["total_urgency_score"] >= TOTAL_URGENCY_LIMIT
        else MIN_QUESTIONS
    )


def force_report(state: dict, user_query: str) -> bool:
    """Whether the agent must stop asking and finalize this turn."""
    if patient_asked_to_finish(user_query):
        return True
    if state["questions_asked"] >= MAX_QUESTIONS:
        return True
    return (
        state["total_urgency_score"] >= TOTAL_URGENCY_LIMIT
        and state["questions_asked"] >= MIN_QUESTIONS_URGENT
    )


def must_keep_asking(state: dict, user_query: str) -> bool:
    """Whether a report is forbidden this turn because the interview is too short."""
    if patient_asked_to_finish(user_query):
        return False
    if state["questions_asked"] >= MAX_QUESTIONS:
        return False
    return state["questions_asked"] < _question_floor(state)


def apply_confirmed_symptoms(
    existing_symptoms: list[str],
    current_score: float,
    confirmed_symptoms: list[dict],
) -> tuple[list[str], float, list[float]]:
    """Add only newly confirmed, database-backed symptom scores on the server."""
    known_names = {symptom.casefold() for symptom in existing_symptoms}
    merged_symptoms = list(existing_symptoms)
    new_scores: list[float] = []

    for symptom in confirmed_symptoms:
        name = symptom["name"]
        if name.casefold() in known_names:
            continue
        known_names.add(name.casefold())
        merged_symptoms.append(name)
        new_scores.append(float(symptom["urgency_score"]))

    # The worst symptom sets the urgency, rather than the sum of them.
    #
    # Each row's urgency_score is an absolute 0-100 severity, not an additive
    # weight: adding two of them saturated at MAX_URGENCY_SCORE the moment a
    # patient reported anything twice, which made every multi-symptom patient
    # maximally urgent. seed_symptomsV3.sql is the confirmation -- it scores
    # combinations as their own rows ("Chest pain with shortness of breath", 98)
    # precisely because the pair is worse than either alone by an amount the
    # dataset states rather than one this code should invent.
    total_score = min(MAX_URGENCY_SCORE, max([current_score, *new_scores]))
    return merged_symptoms, total_score, new_scores


def apply_server_urgency(
    generated_report: PreliminaryReport,
    urgency_score: float,
    urgency_breakdown: list[float],
) -> PreliminaryReport:
    """Return a schema-valid report with server-derived urgency data."""
    return PreliminaryReport.model_validate(
        {
            **generated_report.model_dump(),
            "urgency_score": urgency_score,
            "urgency_breakdown": urgency_breakdown or [urgency_score],
        }
    )


def build_turn_message(
    user_query: str, state: dict, force_report: bool, keep_asking: bool = False,
) -> str:
    asked = state["questions_asked"]
    state_block = (
        f"Questions asked so far: {asked}\n"
        f"Cumulative urgency score so far: {state['total_urgency_score']}\n"
        f"Symptoms identified so far: {', '.join(state['identified_symptoms']) or 'none yet'}"
    )

    if force_report:
        directive = (
            "You MUST set action='generate_report' now and produce the final report, "
            "using everything discussed so far even if information is incomplete."
        )
    elif keep_asking:
        remaining = _question_floor(state) - asked
        directive = (
            f"You have asked {asked} follow-up question(s). You MUST ask at least "
            f"{remaining} more before finalizing. Set action='ask_question' and ask "
            "exactly one more multiple-choice question now. Generating a report this "
            "turn is not allowed. Ask about something you do not know yet -- when the "
            "symptom started, how severe it is, whether it comes and goes, what makes "
            "it better or worse, or any related symptom the knowledge base links to "
            "what they have already told you. Never repeat a question already asked."
        )
    else:
        directive = (
            "Decide whether to ask exactly one more follow-up MCQ, look up a symptom "
            "using your knowledge base tool, or generate the report if you have enough to go on."
        )

    return f"""Patient message: {user_query} Session state:{state_block} {directive}"""


def generate_report_tool(session_id: str):
    """
    Build a generate_report tool bound to one session_id. Agno tools are
    plain functions — session context has to arrive via closure, so
    get_agent() must build a fresh one per session rather than sharing one
    globally.
    """    
    def generate_report(report_json: str) -> str:
            """
            Finalize and save the patient's preliminary triage report. Call this, when you have enough information to recommend a specialty and estimate overall urgency, or when told to finalize now.
            report_json must be a JSON string with fields: symptoms_described (list of strings), urgency_score (number), urgency_breakdown (list of
            objects each with symptom, score, and optional note), recommended_specialty (string), and optionally possible_diagnosis (list of strings), confidence_score (number), rationale (string).
            If the function returns : "Could not save report, fix the JSON and retry:", find the error in the json and regenerate.
            Here is the format:
            symptoms_described: list[str]
            urgency_score: float
            urgency_breakdown: list[float] # list of scores
            recommended_specialty: str
            possible_diagnosis: list[str] | None = None
            confidence_score: float | None = None
            rationale: str | None = None
            """
            try:
                data = json.loads(report_json)
                report = PreliminaryReport(**data)
            except (json.JSONDecodeError, ValidationError) as e:
                return f"Could not save report, fix the JSON and retry: {e}"

            save_report(session_id, report)
            return "Report saved. Let the patient know their triage summary is ready."
    return generate_report

def save_report(session_id: str, report: PreliminaryReport) -> bool:
    """Replace the stored report for a session.

    Postgres, not a JSON file beside this module: the service runs in a container
    with no volume, so file-backed reports vanish on every restart and are invisible
    to anything else reading the same database.
    """
    init_session_state(session_id)
    with connection() as con:
        con.execute(
            """
            UPDATE session_state
            SET report = %s, status = 'completed', updated_at = NOW()
            WHERE session_id = %s
            """,
            (report.model_dump_json(), session_id),
        )
        con.commit()
    return True


def _stored_report(session_id: str) -> dict | None:
    with connection() as con:
        row = con.execute(
            "SELECT report FROM session_state WHERE session_id = %s", (session_id,)
        ).fetchone()
    return row[0] if row and row[0] else None


def report_exists(session_id: str) -> bool:
    return _stored_report(session_id) is not None


def read_report(session_id: str) -> PreliminaryReport:
    stored = _stored_report(session_id)
    if stored is None:
        raise RuntimeError(f"No report stored for session {session_id}")
    return PreliminaryReport.model_validate(stored)

"""Session state helpers"""
from services.database import connection
def init_session_state(session_id: str) -> None:
    with connection() as con:
        con.execute(
            "INSERT INTO session_state (session_id) VALUES (%s) ON CONFLICT DO NOTHING",
            (session_id,),
        )
        con.commit()


def get_session_state(session_id: str) -> dict:
    with connection() as con:
        row = con.execute(
            """
            SELECT total_urgency_score, questions_asked, identified_symptoms, status
            FROM session_state WHERE session_id = %s
            """,
            (session_id,),
        ).fetchone()
    if row is None:
        raise RuntimeError(f"No session_state row for session {session_id}")
    return {
        "total_urgency_score": float(row[0]),
        "questions_asked": row[1],
        "identified_symptoms": row[2] or [],
        "status": row[3],
    }


def update_session_state(
    session_id: str, total_urgency_score: float, questions_asked: int,
    identified_symptoms: list[str], status: str = "in_progress",
) -> None:
    with connection() as con:
        con.execute(
            """
            UPDATE session_state
            SET total_urgency_score = %s, questions_asked = %s,
                identified_symptoms = %s, status = %s, updated_at = NOW()
            WHERE session_id = %s
            """,
            (total_urgency_score, questions_asked, json.dumps(identified_symptoms), status, session_id),
        )
        con.commit()
