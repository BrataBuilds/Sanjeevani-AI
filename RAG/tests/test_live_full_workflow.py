"""Opt-in live workflow test.

Run with: $env:RUN_LIVE_WORKFLOW_TEST='1'; uv run pytest tests/test_live_full_workflow.py -m live -q
"""

import os
from uuid import UUID

import pytest


pytestmark = pytest.mark.live

RUN_LIVE_WORKFLOW_TEST = os.getenv("RUN_LIVE_WORKFLOW_TEST") == "1"


USER_CONVERSATIONS = {
    "cardiology": [
        "I have had chest discomfort since this morning.",
        "The discomfort feels like pressure in the centre of my chest.",
        "It started while I was resting.",
        "I also feel short of breath.",
        "I have not fainted, but I feel worried.",
        "Please generate my report now.",
    ],
    "neurology": [
        "I have had a severe headache for two hours.",
        "The pain started suddenly.",
        "I feel dizzy when I stand up.",
        "I do not have chest pain.",
        "I have not lost consciousness.",
        "Please generate my report now.",
    ],
    "gastroenterology": [
        "I have pain in my lower abdomen.",
        "The pain began yesterday evening.",
        "I feel nauseated but have not vomited.",
        "I have no chest pain or breathing difficulty.",
        "The pain is getting worse after meals.",
        "Please generate my report now.",
    ],
}



@pytest.mark.skipif(
    not RUN_LIVE_WORKFLOW_TEST,
    reason="Set RUN_LIVE_WORKFLOW_TEST=1 to call configured PostgreSQL and Gemini services.",
)
def test_three_users_complete_six_turn_workflows_with_new_session_uuids() -> None:
    """The server issues a new UUID, then each user keeps it for six turns."""
    from fastapi.testclient import TestClient
    from main import app

    session_ids: dict[str, UUID] = {}

    with TestClient(app, raise_server_exceptions=False) as client:
        for user, messages in USER_CONVERSATIONS.items():
            session_id: UUID | None = None

            for turn_number, message in enumerate(messages):
                payload = {"user_query": message}
                if turn_number > 0:
                    assert session_id is not None
                    payload["session_id"] = str(session_id)

                response = client.post("/chat", json=payload)

                assert response.status_code == 200, response.text
                response_body = response.json()
                response_session_id = UUID(response_body["session_id"])
                if turn_number == 0:
                    session_id = response_session_id
                    session_ids[user] = session_id
                else:
                    assert response_session_id == session_id
                assert response_body["response_type"] in {"text", "mcq"}

            assert session_id is not None
            history_response = client.get(f"/chats/{session_id}")
            assert history_response.status_code == 200, history_response.text
            history = history_response.json()["chats"]
            user_messages = [entry["content"] for entry in history if entry["role"] == "user"]
            assert user_messages[-len(messages):] == messages

            report_response = client.get(f"/generate-report/{session_id}")
            assert report_response.status_code == 200, report_response.text
            generated_report = report_response.json()
            assert 0 <= generated_report["urgency_score"] <= 100
            assert generated_report["urgency_breakdown"]
            assert generated_report["recommended_specialty"]

    assert len(set(session_ids.values())) == len(USER_CONVERSATIONS)
