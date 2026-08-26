from fastapi import FastAPI 
from config import Settings

from api.routes import chat 
app = FastAPI(title="Chat with Gemini")
app.include_router(chat.router, tags=["Chat"])