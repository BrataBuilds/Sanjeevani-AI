from fastapi import APIRouter, HTTPException
from schemas.chat import ChatMessage, ChatResponse, HistoryResponse
from services.chat_agent import get_agent
from datetime import datetime
router = APIRouter()

@router.post("/chat", response_model=ChatResponse)
async def chat(message: ChatMessage, session_id : str | None = None):
    try:
        agent, actual_session_id = await get_agent(session_id=session_id)
        response  = await agent.arun(message.user_query)
    except Exception as e:
        raise HTTPException(500, detail=str(e))
    # return RedirectResponse(f"/chat/{actual_session_id}")
    return ChatResponse(session_id=actual_session_id, response=response.content, timestamp=str(datetime.now()))

@router.get("/chat/", response_model = HistoryResponse)
async def get_chats(session_id : str):
    agent, actual_id = await get_agent(session_id=session_id)
    try:
        raw_chat_history = agent.get_chat_history(actual_id)
        chat_history = []
        for json in raw_chat_history:
            if json.content != None :
                chat_history.append([json.id, json.role, json.content, ])
    except Exception as e:
        raise HTTPException(500, detail=str(e))
    return HistoryResponse(session_id=actual_id, chats=chat_history)
