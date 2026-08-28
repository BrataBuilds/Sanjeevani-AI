import pytest
from pydantic import ValidationError

from schemas.chat import UserPrompt
from schemas.triage import AgentTurn, MCQOptions


def test_user_prompt_uses_server_timestamp_and_rejects_blank_messages() -> None:
    assert UserPrompt(user_query="  chest pain  ").user_query == "chest pain"

    with pytest.raises(ValidationError):
        UserPrompt(user_query="   ")

    with pytest.raises(ValidationError):
        UserPrompt(user_query="chest pain", timestamp="2026-01-01T00:00:00Z")


def test_triage_scores_and_mcq_options_are_bounded() -> None:
    with pytest.raises(ValidationError):
        AgentTurn(
            action="ask_question",
            running_urgency_score=101,
            identified_symptoms=[],
        )

    with pytest.raises(ValidationError):
        MCQOptions(question="How do you feel?", options=["Fine"])
