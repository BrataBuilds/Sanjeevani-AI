"""
Turn-control logic and report finalization for the triage agent. This file only tracks session state and
guarantees the final report is clean JSON.
"""
import json
from schemas.triage import PreliminaryReport
from uuid import UUID
from pathlib import Path
from pydantic import ValidationError

MAX_QUESTIONS = 7
TOTAL_URGENCY_LIMIT = 50  # match whatever scale symptoms.urgency_score uses
MAX_URGENCY_SCORE = 100
REPORT_DIR = Path(__file__).parent

def force_report(state: dict, user_query: str) -> bool:
    force_phrases = (
        "generate my report",
        "generate the report",
        "give me the report",
        "finalize",
        "i am done",
        "it's urgent",
        "its urgent",
        "too painful",
    )
    normalized_query = " ".join(user_query.casefold().split())
    return (
        state["questions_asked"] >= MAX_QUESTIONS
        or state["total_urgency_score"] >= TOTAL_URGENCY_LIMIT
        or any(phrase in normalized_query for phrase in force_phrases)
    )


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

    total_score = min(MAX_URGENCY_SCORE, current_score + sum(new_scores))
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


def build_turn_message(user_query: str, state: dict, force_report: bool) -> str:
    state_block = (
        f"Questions asked so far: {state['questions_asked']}\n"
        f"Cumulative urgency score so far: {state['total_urgency_score']}\n"
        f"Symptoms identified so far: {', '.join(state['identified_symptoms']) or 'none yet'}"
    )

    directive = (
        "You MUST set action='generate_report' now and produce the final report, "
        "using everything discussed so far even if information is incomplete."
        if force_report else
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

def _report_path(session_id: str) -> Path:
    return REPORT_DIR / f"{session_id}.json"


def save_report(session_id: str, report: PreliminaryReport) -> bool:
    """Replace the stored report for a session."""
    _report_path(session_id).write_text(report.model_dump_json(indent=2), encoding="utf-8")
    return True


def report_exists(session_id: str) -> bool:
    return _report_path(session_id).is_file()


def read_report(session_id: str) -> PreliminaryReport:
    return PreliminaryReport.model_validate_json(
        _report_path(session_id).read_text(encoding="utf-8")
    )

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
