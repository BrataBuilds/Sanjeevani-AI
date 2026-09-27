from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, HTTPException
import services.database as db
from schemas.chat import ChatEntry, ChatResponse, UserPrompt, HistoryResponse
from services.turn import TurnError, run_turn

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
async def chat(prompt: UserPrompt):
    try:
        turn, session_id, _state = await run_turn(
            str(prompt.session_id) if prompt.session_id else None,
            prompt.user_query,
            prompt.hospitals,
        )
    except TurnError as e:
        raise HTTPException(502, detail=str(e)) from e

    if turn.action == "ask_question" and isinstance(turn.follow_up, str):
        response_type, content = "text", turn.follow_up
    elif turn.action == "ask_question":
        response_type, content = "mcq", turn.follow_up
    else:
        response_type = "text"
        content = (
            f"Your preliminary report is ready. Recommended specialty: "
            f"{turn.report.recommended_specialty}. Urgency score: {turn.running_urgency_score}."
        )

    return ChatResponse(
        session_id=UUID(session_id),
        timestamp=datetime.now(timezone.utc),
        response_type=response_type,
        content=content,
        report=turn.report,
        identified_symptoms=turn.identified_symptoms,
        urgency_score=turn.running_urgency_score,
    )


@router.get("/chats/{session_id}", response_model=HistoryResponse)
async def get_chats(session_id: UUID):
    try:
        chats = db.session_details(str(session_id))
    except RuntimeError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return HistoryResponse(session_id=session_id, chats=chats)
