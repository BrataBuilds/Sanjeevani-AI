from contextlib import asynccontextmanager

from fastapi import FastAPI
from api.routes import chat 
from api.routes import report
from services import knowledge
from services.vector_db import build_symptom_db


@asynccontextmanager
async def lifespan(_: FastAPI):
    knowledge.initialize()
    build_symptom_db()
    yield


app = FastAPI(title="Sanjeevani AI RAG Backend server", lifespan=lifespan)
app.include_router(chat.router, tags=["Chat"])
app.include_router(report.router, tags=["Generate the report"])

@app.get("/")
def root() -> str: 
    return "This is the root directory, the current endpoints that can be accessed are: /chat and /chat/{session_id}"
