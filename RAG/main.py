from contextlib import asynccontextmanager

from fastapi import FastAPI
from api.routes import chat 
from api.routes import report
from api.routes import triage
from services import database, knowledge
from services.vector_db import build_symptom_db


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Must run first: it creates the `rag` schema every other table lands in.
    database.initialize()
    knowledge.initialize()
    build_symptom_db()
    yield


app = FastAPI(title="Sanjeevani AI RAG Backend server", lifespan=lifespan)
app.include_router(chat.router, tags=["Chat"])
app.include_router(report.router, tags=["Generate the report"])
# The contract the platform backend calls; see docs/AI-Integration-Contract.md.
app.include_router(triage.router, tags=["Triage seam"])

@app.get("/")
def root() -> str: 
    return "Endpoints: /chat, /chats/{session_id}, /generate-report/{session_id}, /triage"
