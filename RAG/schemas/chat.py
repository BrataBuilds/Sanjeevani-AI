from pydantic import BaseModel
from datetime import datetime
from uuid import UUID
class UserPrompt(BaseModel):
    """Return the prompt given by the user"""
    timestamp : datetime
    user_query: str
    session_id : UUID | None = None
class ChatResponse(BaseModel):
    """Return the response of the llm"""
    timestamp : datetime
    session_id: UUID
    response: str | None = None
    
class ChatEntry(BaseModel):
    """Combine the chats of user and agent into one"""
    chat_id: UUID
    role: str # Decides whether the chat is from user / assistant
    timestamp: datetime
    content: str
class HistoryResponse(BaseModel):
    """Return list of chats"""
    session_id : UUID
    # Store history as a list of user's prompts and chat response
    chats : list[ChatEntry]
    
    