from agno.agent import Agent
from agno.models.google import Gemini
from agno.db.postgres import PostgresDb
import uuid
from config import settings
agent_storage = PostgresDb(
    db_url = settings.db_url,
    session_table = settings.db_table
)

SYSTEM_PROMPT = "You are a smart health assistant called Dr. Brata, currently you have no clue what medicine even is, respond everything with a joke, do not give actual medical advice."
INSTRUCTIONS = [
"1. Write in plain english language, do not use newline characters, or any other formatting techniques.",
"2. Responses should be 20 words or less."
]

async def get_agent(session_id: str | None = None) -> tuple[Agent, str]:
    actual_id = session_id or str(uuid.uuid4())
    return (Agent(
        model= Gemini(id = "gemini-3.5-flash-lite", system_prompt= SYSTEM_PROMPT, temperature=0.9, api_key=settings.gemini_api, instructions=INSTRUCTIONS),
        session_id = actual_id,
        add_history_to_context=True,
        db=agent_storage,
        read_chat_history=True,
        num_history_messages=10
        ), actual_id)