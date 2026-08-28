from typing import Literal
from pydantic import BaseModel, ConfigDict, Field


class MCQOptions(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    question: str = Field(min_length=1, max_length=500)
    options: list[str] = Field(min_length=2, max_length=5)


class PreliminaryReport(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    symptoms_described: list[str] = Field(min_length=1, max_length=20)
    urgency_score: float = Field(ge=0, le=100)
    urgency_breakdown: list[float] = Field(min_length=1, max_length=20)
    recommended_specialty: str = Field(min_length=1, max_length=100)
    possible_diagnosis: list[str] | None = None
    confidence_score: float | None = Field(default=None, ge=0, le=1)
    rationale: str | None = None


class AgentTurn(BaseModel):
    action: Literal["ask_question", "generate_report"]
    running_urgency_score: float = Field(ge=0, le=100)
    identified_symptoms: list[str] = Field(default_factory=list, max_length=20)
    follow_up: MCQOptions | None = None
    report: PreliminaryReport | None = None
