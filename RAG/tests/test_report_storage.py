from schemas.triage import PreliminaryReport
from services import report


def test_saved_report_can_be_retrieved(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(report, "REPORT_DIR", tmp_path)
    session_id = "362afea1-313d-4c93-b5d2-361082bef1e0"
    generated_report = PreliminaryReport(
        symptoms_described=["chest pain"],
        urgency_score=45,
        urgency_breakdown=[45],
        recommended_specialty="Cardiology",
    )

    assert report.save_report(session_id, generated_report)
    assert report.report_exists(session_id)
    assert report.read_report(session_id) == generated_report


def test_server_urgency_keeps_a_report_valid_without_confirmed_symptoms() -> None:
    generated_report = PreliminaryReport(
        symptoms_described=["unspecified pain"],
        urgency_score=10,
        urgency_breakdown=[10],
        recommended_specialty="General Medicine",
    )

    finalized_report = report.apply_server_urgency(generated_report, 0, [])

    assert finalized_report.urgency_score == 0
    assert finalized_report.urgency_breakdown == [0]
