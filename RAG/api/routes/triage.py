"""
The endpoint the platform backend calls.

Contract: docs/AI-Integration-Contract.md in the repository root. The backend POSTs
the whole transcript, the patient's profile and known conditions, referenced
attachments, and a distance-sorted hospital list; whatever comes back is stored in
`triage_results`, fanned out into chat messages, and turned into a queue token.

This module is only a translator. All of the reasoning is in services/turn.py and
the agent behind it; nothing here decides urgency or specialty on its own.
"""
import re
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict

from services.database import session_exists
from services.knowledge import check_symptoms
from services.turn import TurnError, run_turn

router = APIRouter()


class TriageRequest(BaseModel):
    """Deliberately permissive: the backend may add fields, and an unknown one
    must not fail the whole triage."""
    model_config = ConfigDict(extra="allow")

    request_id: str
    conversation: dict[str, Any] | None = None
    patient: dict[str, Any] | None = None
    hospitals: list[dict[str, Any]] = []
    language: str | None = None
    callback_url: str | None = None


# The platform stores urgency as ESI 1-5, 1 most urgent, with a CHECK constraint.
# This service scores 0-100, higher being more urgent. That disagreement is open
# question 1 in the Feature Coverage wiki page; until it is settled, the two
# scales meet here and nowhere else. Widen these bands, do not scatter copies.
URGENCY_BANDS = ((80, 1), (60, 2), (40, 3), (20, 4))


def to_esi(score_0_100: float | None) -> int:
    if score_0_100 is None:
        return 4
    for floor, esi in URGENCY_BANDS:
        if score_0_100 >= floor:
            return esi
    return 5


# departments.specialty in the platform schema is a lowercase underscore slug, and
# the backend falls back to general_medicine on anything it does not recognise.
SPECIALTY_ALIASES = {
    "general medicine": "general_medicine",
    "internal medicine": "general_medicine",
    "gp": "general_medicine",
    "family medicine": "general_medicine",
    "cardiology": "cardiology",
    "cardiac": "cardiology",
    "orthopaedics": "orthopaedics",
    "orthopedics": "orthopaedics",
    "ortho": "orthopaedics",
    "dermatology": "dermatology",
    "skin": "dermatology",
    "emergency": "emergency",
    "emergency medicine": "emergency",
    "casualty": "emergency",
    "paediatrics": "paediatrics",
    "pediatrics": "paediatrics",
    # Irregular practitioner nouns the -ologist rule below cannot derive.
    "paediatrician": "paediatrics",
    "pediatrician": "paediatrics",
    "physician": "general_medicine",
    "general physician": "general_medicine",
    "orthopaedic surgeon": "orthopaedics",
    "orthopedic surgeon": "orthopaedics",
}


def _field_of(word: str) -> str:
    """`dermatologist` -> `dermatology`.

    The agent names the practitioner about as often as the department, but
    departments.specialty only ever holds the field. Without this, a perfectly
    good answer slugs to `dermatologist`, matches no department, and the backend
    quietly downgrades the routing to general_medicine.
    """
    return word[:-3] + "y" if word.endswith("ologist") else word


# Splits "Emergency Medicine / Cardiology" into two candidates. Deliberately not
# comma or "and": those sit inside single specialty names ("Ear, Nose and Throat")
# far more often than they separate two of them.
SPECIALTY_SEPARATORS = re.compile(r"\s*(?:[/\\+&]|\bor\b)\s*")


def to_specialty_slug(name: str | None) -> str | None:
    """Best department slug for whatever the agent called the specialty.

    The agent hedges -- "Emergency Medicine / Cardiology" is a normal answer, and
    slugging it whole produced `emergency_medicine___cardiology`, which matched no
    department and quietly demoted a cardiac case to general medicine. Take the
    first candidate the platform actually has a department for.
    """
    if not name:
        return None
    cleaned = " ".join(name.strip().casefold().replace("_", " ").split())
    if not cleaned:
        return None

    candidates = [
        " ".join(_field_of(word) for word in segment.split())
        for segment in SPECIALTY_SEPARATORS.split(cleaned)
        if segment.strip()
    ] or [cleaned]

    for candidate in candidates:
        if candidate in SPECIALTY_ALIASES:
            return SPECIALTY_ALIASES[candidate]
    return candidates[0].replace(" ", "_").replace("/", "_")


def patient_messages(conversation: dict[str, Any] | None) -> list[str]:
    return [
        message["body"].strip()
        for message in (conversation or {}).get("messages") or []
        if message.get("role") == "patient" and (message.get("body") or "").strip()
    ]


def query_for(conversation: dict[str, Any] | None, session_is_new: bool) -> str | None:
    """What to hand the agent this turn.

    The transcript arrives in full every time, but the agent keeps its own history
    in Postgres, so normally only the newest patient turn is new information.

    The exception is the first turn. The platform opens every triage thread with a
    short registration intake -- who it is for, how long, how bad, what they have
    tried -- and answering it deliberately does not fire a triage round, because
    there is no complaint in it yet. Those answers are still the patient's own
    words and belong in the interview, so on a session the agent has never seen,
    replay everything they have said rather than just the last line.
    """
    messages = patient_messages(conversation)
    if not messages:
        return None
    if session_is_new and len(messages) > 1:
        return "\n\n".join(messages)
    return messages[-1]


def sources_for(symptoms: list[str]) -> list[dict[str, str]]:
    """Provenance. Design_doc §2 requires every routing decision be traceable, and
    the doctor's dashboard renders whatever is here."""
    return [
        {"title": s["name"], "ref": f"kb://symptom/{s['symptom_id']}"}
        for s in check_symptoms(symptoms)
    ]


def suggest_hospitals(hospitals: list[dict[str, Any]], specialty: str | None) -> list[dict[str, Any]]:
    """The list arrives pre-sorted by distance and carries each facility's
    specialty keys, so this only has to prefer the ones that can actually treat it."""
    if not hospitals:
        return []
    matching = [h for h in hospitals if specialty and specialty in (h.get("specialties") or [])]
    chosen = (matching or hospitals)[:3]
    return [
        {
            "hospital_id": h.get("id"),
            "name": h.get("name"),
            "distance_km": h.get("distance_km"),
            "reason": (
                f"Has a {specialty.replace('_', ' ')} department."
                if h in matching and specialty
                else "Nearest facility to you."
            ),
        }
        for h in chosen
    ]


@router.post("/triage")
async def triage(payload: TriageRequest) -> dict[str, Any]:
    # One agent session per platform conversation, so history lines up across turns.
    session_id = (payload.conversation or {}).get("id")
    session_is_new = not (session_id and session_exists(str(session_id)))

    query = query_for(payload.conversation, session_is_new)
    if not query:
        raise HTTPException(400, detail="No patient message in the conversation to triage.")

    try:
        turn, _session_id, _state = await run_turn(session_id, query)
    except TurnError as e:
        # The backend marks the request failed and tells the patient the assistant
        # is unavailable, rather than leaving them with silence.
        raise HTTPException(502, detail=str(e)) from e

    if turn.action == "ask_question":
        follow_up = turn.follow_up
        return {
            "request_id": payload.request_id,
            "status": "needs_more_info",
            "reply": follow_up.question,
            "confidence": None,
            "sources": sources_for(turn.identified_symptoms),
            "follow_up_questions": [
                {
                    "id": "q1",
                    "question": follow_up.question,
                    "options": follow_up.options,
                    "multi": False,
                }
            ],
        }

    report = turn.report
    specialty = to_specialty_slug(report.recommended_specialty)
    return {
        "request_id": payload.request_id,
        "status": "ok",
        "reply": "Here is a preliminary summary of what you told me.",
        "chief_complaint": ", ".join(report.symptoms_described[:3]),
        "symptoms": [{"name": name} for name in report.symptoms_described],
        "specialty": specialty,
        "urgency": to_esi(report.urgency_score),
        # PreliminaryReport carries no red-flag field, and inventing a threshold
        # here would be a clinical rule this repository must not own. Left false
        # until the schema gains one.
        "red_flag": False,
        "summary": report.rationale,
        "clinical_note": "; ".join(report.possible_diagnosis or []) or None,
        "confidence": report.confidence_score,
        "sources": sources_for(report.symptoms_described),
        "suggested_hospitals": suggest_hospitals(payload.hospitals, specialty),
    }
