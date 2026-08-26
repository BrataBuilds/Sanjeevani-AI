from pydantic import BaseModel
from typing import Any
class ChatMessage(BaseModel):
    """Return the prompt given by the user"""
    timestamp : str
    user_query: str
    image_data: str | None = None
    session_id : str | None = None
class ChatResponse(BaseModel):
    """Return the response of the llm"""
    timestamp : str
    session_id: str
    response: str | None
class HistoryResponse(BaseModel):
    """Return list of chats"""
    session_id : str
    # Query / Response dicts
    chats : list[Any]
    
    