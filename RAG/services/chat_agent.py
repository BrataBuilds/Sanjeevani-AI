from agno.agent import Agent
from agno.models.google import Gemini
from agno.db.postgres import PostgresDb
import uuid
from config.config import settings
from schemas.triage import AgentTurn
from services.vector_db import query_symptoms
from services.report import generate_report_tool

agent_storage = PostgresDb(
    db_url = settings.db_url,
    session_table = settings.db_table
)

SYSTEM_PROMPT = (
    "You are Sanjeevani, a hospital triage assistant. Your job is to have a short, structured conversation with a patient to understand their symptoms, estimate how "
    "urgent their situation is, and recommend which specialty they should see. "
    "You are not a doctor and must never give a definitive diagnosis or treatment advice — "
    "you only produce a preliminary triage report for hospital staff to review. "
    "Be calm, clear, and reassuring. Use plain, simple language a worried patient can "
    "follow, avoid jargon, and keep every message short."
)

INSTRUCTIONS = [
    "Ask at most one multiple-choice follow-up question per turn.",
    "Before judging a symptom you're unsure about, use the query_symptoms tool to look up its urgency score, related specialties, and related symptoms.",
    "Keep a running cumulative urgency score across the whole conversation, never reset it, only add to it as symptoms are confirmed.",
    "Base every urgency and specialty judgment on what query_symptoms returns, not on assumptions.",
    "Set action to 'generate_report' only when you have enough information, or when explicitly told to finalize.",
    "Never state a definitive diagnosis to the patient — possible_diagnosis is a list of possibilities for clinical staff, not a conclusion.",
    "Write in plain English, no markdown formatting, no newline characters.",
]

async def get_agent(session_id: str | None = None) -> tuple[Agent, str]:
    session_id = session_id if session_id != None else str(uuid.uuid4())
    return (Agent(
        model= Gemini(id = "gemma-4-31b-it", system_prompt= SYSTEM_PROMPT, temperature=0.9, api_key=settings.gemini_api, instructions=INSTRUCTIONS),
        output_schema=AgentTurn,
        structured_outputs=True,
        session_id = session_id,
        add_history_to_context=True,
        db=agent_storage,
        read_chat_history=True,
        num_history_messages=10,
        tools=[query_symptoms,generate_report_tool(session_id)],
        ), session_id)
