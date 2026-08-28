import json

from schemas.triage import PreliminaryReport
from services import report


class _FakeSessionState:
    """Stands in for the session_state row. Reports moved out of JSON files and
    into Postgres so they survive a container restart, so this test follows."""

    def __init__(self) -> None:
        self.stored: str | None = None

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query: str, params: tuple | None = None):
        if "UPDATE session_state" in query:
            self.stored = params[0]
        self.rows = [(json.loads(self.stored),)] if self.stored else [(None,)]
        return self

    def fetchone(self):
        return self.rows[0]

    def commit(self) -> None:
        pass


def test_saved_report_can_be_retrieved(monkeypatch) -> None:
    state = _FakeSessionState()
    monkeypatch.setattr(report, "connection", lambda: state)
    session_id = "362afea1-313d-4c93-b5d2-361082bef1e0"
    generated_report = PreliminaryReport(
        symptoms_described=["chest pain"],
        urgency_score=45,
        urgency_breakdown=[45],
        recommended_specialty="Cardiology",
    )

    assert not report.report_exists(session_id)
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
