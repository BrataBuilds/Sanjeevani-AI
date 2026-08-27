from fastapi import FastAPI 
from config.config import Settings

from api.routes import chat 
app = FastAPI(title="Chat with Gemini")
app.include_router(chat.router, tags=["Chat"])

@app.get("/")
def root() -> str: 
    return "This is the root directory, the current endpoints that can be accessed are: /chat and /chat/{session_id}"