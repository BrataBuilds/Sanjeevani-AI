"""The two scale translations in the /triage seam.

Both are the kind of thing that fails silently: a bad specialty slug matches no
department and the backend downgrades to general_medicine, and a bad ESI value
trips the platform's CHECK constraint. Neither shows up as an error here.
"""
from api.routes.triage import to_esi, to_specialty_slug


def test_urgency_bands_map_onto_esi_1_to_5() -> None:
    assert to_esi(95) == 1
    assert to_esi(80) == 1      # band floors are inclusive
    assert to_esi(79) == 2
    assert to_esi(60) == 2
    assert to_esi(45) == 3
    assert to_esi(25) == 4
    assert to_esi(0) == 5
    assert to_esi(None) == 4    # unknown is not an emergency, and not ignorable
    assert all(1 <= to_esi(score) <= 5 for score in range(0, 101))


def test_specialty_names_reach_the_real_department_slugs() -> None:
    # Whatever the agent calls it, departments.specialty holds the field.
    for name in ("Dermatology", "dermatologist", "Dermatologist", "skin"):
        assert to_specialty_slug(name) == "dermatology"
    for name in ("Cardiology", "cardiologist", "Cardiac"):
        assert to_specialty_slug(name) == "cardiology"
    for name in ("General Medicine", "internal medicine", "physician", "GP"):
        assert to_specialty_slug(name) == "general_medicine"
    for name in ("Pediatrics", "paediatrician", "Paediatrics"):
        assert to_specialty_slug(name) == "paediatrics"
    for name in ("Orthopedics", "orthopaedic surgeon"):
        assert to_specialty_slug(name) == "orthopaedics"
    assert to_specialty_slug("Emergency Medicine") == "emergency"

    # A hedged answer picks the first specialty the platform has a department for,
    # instead of slugging the whole thing into something that matches nothing.
    assert to_specialty_slug("Emergency Medicine / Cardiology") == "emergency"
    assert to_specialty_slug("Cardiology or Emergency") == "cardiology"
    assert to_specialty_slug("Dermatology & Allergy") == "dermatology"

    # An unknown field still slugs cleanly rather than reaching the backend with
    # spaces or slashes in it. Commas and "and" stay inside one name.
    assert to_specialty_slug("Ear, Nose and Throat") == "ear,_nose_and_throat"
    assert to_specialty_slug(None) is None
    assert to_specialty_slug("") is None


# --- interview depth --------------------------------------------------------
# The reported bug: "chest pain" (45) plus "shortness of breath" (40) cleared
# TOTAL_URGENCY_LIMIT on the first message, so the patient answered one question
# and got a report. Urgency must shorten the interview, never cancel it.
from services.report import (
    MAX_QUESTIONS,
    apply_confirmed_symptoms,
    MIN_QUESTIONS,
    MIN_QUESTIONS_URGENT,
    force_report,
    must_keep_asking,
)


def _state(asked: int, score: float) -> dict:
    return {"questions_asked": asked, "total_urgency_score": score,
            "identified_symptoms": [], "status": "in_progress"}


def test_alarming_first_message_does_not_end_the_interview() -> None:
    opening = _state(asked=0, score=98)          # chest pain with shortness of breath
    assert not force_report(opening, "I have chest pain and shortness of breath")
    assert must_keep_asking(opening, "I have chest pain and shortness of breath")


def test_urgency_shortens_the_interview_rather_than_skipping_it() -> None:
    urgent = "I have chest pain"
    assert must_keep_asking(_state(MIN_QUESTIONS_URGENT - 1, 95), urgent)
    assert not must_keep_asking(_state(MIN_QUESTIONS_URGENT, 95), urgent)
    assert force_report(_state(MIN_QUESTIONS_URGENT, 95), urgent)
    # A calm case still gets the full floor.
    assert must_keep_asking(_state(MIN_QUESTIONS_URGENT, 20), "mild rash")
    assert not must_keep_asking(_state(MIN_QUESTIONS, 20), "mild rash")


def test_the_worst_symptom_sets_urgency_not_the_sum() -> None:
    """Scores are absolute 0-100 severities. Adding them made anyone reporting
    two symptoms maximally urgent."""
    confirmed = [{"name": "sore throat", "urgency_score": 30},
                 {"name": "nasal congestion", "urgency_score": 20}]
    merged, score, _ = apply_confirmed_symptoms([], 0, confirmed)
    assert merged == ["sore throat", "nasal congestion"]
    assert score == 30, "two mild symptoms must not add up to something urgent"

    # A worse symptom later in the interview does raise it.
    _, score, _ = apply_confirmed_symptoms(
        merged, score, [{"name": "chest pain", "urgency_score": 95}])
    assert score == 95

    # An already-known symptom neither repeats nor moves the score.
    merged2, score2, new = apply_confirmed_symptoms(
        ["chest pain"], 95, [{"name": "chest pain", "urgency_score": 95}])
    assert merged2 == ["chest pain"] and score2 == 95 and new == []


def test_the_patient_can_always_stop_early() -> None:
    first_turn = _state(asked=0, score=0)
    assert force_report(first_turn, "please generate the report")
    assert not must_keep_asking(first_turn, "please generate the report")


def test_the_interview_always_terminates() -> None:
    assert force_report(_state(MAX_QUESTIONS, 0), "still going")
    assert not must_keep_asking(_state(MAX_QUESTIONS, 0), "still going")
