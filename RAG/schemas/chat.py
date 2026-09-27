from pydantic import AwareDatetime, BaseModel, ConfigDict, Field
from uuid import UUID
from schemas.triage import MCQOptions, PreliminaryReport
from typing import Literal


class UserPrompt(BaseModel):
    """A patient message. Timestamps are assigned by the server."""
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    user_query: str = Field(min_length=1, max_length=2_000)
    session_id: UUID | None = None
    hospitals: list[dict] = Field(default_factory=list, max_length=100)

class ChatResponse(BaseModel):
    timestamp: AwareDatetime
    session_id: UUID
    response_type: Literal["text", "mcq"]
    content: str | MCQOptions
    report: PreliminaryReport | None = None
    identified_symptoms: list[str] = []
    urgency_score: float | None = None

class ChatEntry(BaseModel):
    """Combine the chats of user and agent into one"""
    chat_id: UUID
    role: Literal["user", "assistant"]
    timestamp: AwareDatetime
    content: str


class HistoryResponse(BaseModel):
    """Return list of chats"""
    session_id: UUID
    chats: list[ChatEntry]
