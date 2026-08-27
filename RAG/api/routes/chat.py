from fastapi import APIRouter, HTTPException
from schemas.chat import ChatEntry, ChatResponse, UserPrompt, HistoryResponse
from services.chat_agent import get_agent
import services.database as db
from datetime import datetime
from uuid import UUID, SafeUUID
router = APIRouter()

@router.post("/chat", response_model=ChatResponse)
async def chat(prompt: UserPrompt):
    session_id = db.add_session(str(prompt.session_id))
    try:
        agent, actual_session_id = await get_agent(session_id=str(session_id))
        response  = await agent.arun(prompt.user_query)
    except Exception as e:
        raise HTTPException(502, detail=f"Agent couldn't be called. Check if API has been provided or not, more details: {str(e)}")
    actual_session_id = UUID(actual_session_id)
    answer = response.content
    db.add_entry(session_id=session_id, role="user", content=prompt.user_query, timestamp=str(prompt.timestamp))
    assistant_time = str(datetime.now())
    db.add_entry(session_id, role="assistant", content=answer, timestamp=assistant_time)

    return ChatResponse(session_id=actual_session_id, response=response.content, timestamp=str(assistant_time))

@router.get("/chats/{session_id}", response_model = HistoryResponse)
async def get_chats(session_id : str):
    try:
        chats = db.session_details(session_id)
    except RuntimeError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return HistoryResponse(session_id=session_id, chats=chats)
