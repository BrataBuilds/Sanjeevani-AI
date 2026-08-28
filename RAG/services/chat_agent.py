from agno.agent import Agent
from agno.models.google import Gemini
from agno.db.postgres import PostgresDb
import uuid
from config.config import settings
import services.database as database
from schemas.triage import AgentTurn
from services.vector_db import query_symptoms

agent_storage = PostgresDb(
    db_url = settings.db_url,
    db_schema = database.SCHEMA,
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
    "Always fill identified_symptoms with every symptom the patient has confirmed so far, "
    "cumulatively, spelled the way query_symptoms returns it. The server scores urgency from "
    "this field alone -- leaving it empty scores the patient as not urgent.",
    "Set action to 'generate_report' only when you have enough information, or when explicitly told to finalize.",
    "Build a picture before you conclude: onset, duration, severity, what makes it better or worse, and related symptoms. "
    "A single alarming symptom is a reason to ask faster, not a reason to stop asking.",
    "Obey the per-turn directive about whether you may finalize. It overrides your own judgment.",
    "Never state a definitive diagnosis to the patient — possible_diagnosis is a list of possibilities for clinical staff, not a conclusion.",
    "Write in plain English, no markdown formatting, no newline characters.",
]

async def get_agent(session_id: str | None = None) -> tuple[Agent, str]:
    session_id = session_id if session_id != None else str(uuid.uuid4())
    return (Agent(
        model= Gemini(id = settings.gemini_model, system_prompt= SYSTEM_PROMPT, temperature=0.9, api_key=settings.gemini_api, instructions=INSTRUCTIONS),
        output_schema=AgentTurn,
        structured_outputs=True,
        session_id = session_id,
        add_history_to_context=True,
        db=agent_storage,
        read_chat_history=True,
        num_history_messages=10,
        # query_symptoms only. generate_report_tool duplicated output_schema: the
        # model answered a finalizing turn with a function_call instead of an
        # AgentTurn, agno returned the (empty) text parts, and the turn died on
        # "Invalid JSON". run_turn already persists turn.report, so the tool was
        # only ever a second way to do the same save.
        tools=[query_symptoms],
        ), session_id)
