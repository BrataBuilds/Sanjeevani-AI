"""
TODOs: 1.
db name: chat_sessions
db_url: taken from the .env file
2. Create a table called sessions if not present that will contain
| Session_id UUID | timestamp str |
3. Create tables with the session ids as the name (if not present) . Inside it contain
| chat_id UUID | role (user/assistant) str | timestamp str | content str |

4. Two query tools :

i. Returns all sessions 
ii. Returns the details of specified sessions.
iii. Add a session.
iv. Add an entry to a given session
"""
import os
from uuid import uuid4
import psycopg
from psycopg import sql
from dotenv import load_dotenv

from config.config import settings

load_dotenv()
DB_URL = os.getenv("DB_URL")

# This service shares the platform's Postgres. Everything it creates -- the
# sessions index, the per-session chat tables, symptoms, session_state -- goes in
# its own schema so it never collides with db/01-schema.sql. `public` stays on the
# search path so read-only lookups against platform tables still resolve.
SCHEMA = "rag"


def connection():
    if not DB_URL:
        raise RuntimeError("Database URL not provided in the .env file")
    """Handles the db connection, url is included in the .env file. Returns a connection object that can be used for executing queries"""
    return psycopg.connect(
        DB_URL.replace("+psycopg", ""),
        options=f"-c search_path={SCHEMA},public",
    )

def initialize():
    """
    2. Create a table called sessions if not present that will contain: \n
    | Session_id UUID | timestamp str |
    """
    with connection() as con:
        con.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(SCHEMA)))
        con.execute("""
    CREATE TABLE IF NOT EXISTS sessions (
        sessions_id UUID PRIMARY KEY,
        timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
    """)
        con.commit()


def create_session_table(session_id: str):
    """
    3. Create tables with the session ids as the name (if not present). Inside it contain \n
    | chat_id UUID | role (user/assistant) str | timestamp str | content str |
    """
    table_name = str(session_id)
    with connection() as con:
        query = sql.SQL(
            """
            CREATE TABLE IF NOT EXISTS {} (
                chat_id UUID PRIMARY KEY,
                role TEXT NOT NULL,
                timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                content TEXT NOT NULL
            )"""
        ).format(sql.Identifier(table_name))
        con.execute(query)
        con.commit()
    
def add_session(session_id: str | None = None)->str:
    """Insert a session row if it doesn't exist yet, and ensure its table exists.
    Pass in an existing id (e.g. the one agno generated) to keep both stores in sync."""
    session_id = session_id or str(uuid4())
    with connection() as con:
        con.execute(
            """
            INSERT INTO sessions (sessions_id)
            VALUES (%s)
            ON CONFLICT (sessions_id) DO NOTHING
            """, (session_id,))
        con.commit()
        create_session_table(session_id)
    return session_id

def all_sessions():
    """Returns all the sessions of the user, along with their timestamps.
    Returns a list of newest chats to oldest.
    """
    with connection() as con:
        rows = con.execute(
            """
            SELECT * FROM sessions ORDER BY timestamp DESC
            """).fetchall()
        return rows
    

def session_exists(session_id: str)->bool:
    """Returns if a given chat session id exists or not"""
    with connection() as con:
        row = con.execute(
            "SELECT 1 FROM sessions WHERE sessions_id = %s", (session_id,)).fetchone()
        return row is not None


def forget_agent_history(session_id: str) -> None:
    """Drop the agent's stored history for a session, keeping the session itself.

    A run that dies mid tool-use leaves a function_call with no response after it.
    Gemini rejects any later replay of that history outright -- "Please ensure that
    function call turn comes immediately after a user turn or after a function
    response turn" -- so the session is not merely broken for one turn, it is
    broken permanently. The session id is the platform's conversation id and comes
    back on every turn, so a new id is not an option: the poisoned rows have to go.

    Only the agent's own tables are touched. The patient's transcript lives in the
    platform database and is replayed onto the fresh history by the caller, so
    nothing the patient said is lost.
    """
    with connection() as con:
        con.execute(
            sql.SQL("DELETE FROM {} WHERE session_id = %s")
            .format(sql.Identifier(settings.db_table + "_runs")), (session_id,))
        con.execute(
            sql.SQL("DELETE FROM {} WHERE session_id = %s")
            .format(sql.Identifier(settings.db_table)), (session_id,))
        # The interview restarts from the replayed transcript, so its counters
        # must restart with it or the question floor is already spent.
        con.execute("DELETE FROM session_state WHERE session_id = %s", (session_id,))
        con.commit()
    
    

def session_details(session_id: str | None) ->list[dict]:
    """
    ii. Returns the details of specified sessions.
    """
    if session_id is None:
        raise RuntimeError("No session id provided")
    # Check if session id exists in the table
    if not session_exists(session_id) :
        raise RuntimeError("Given session id record, does not exists!")
    query = sql.SQL("SELECT * FROM {} ORDER BY timestamp ASC").format(sql.Identifier(session_id))
    
    with connection() as con:
        session  = con.execute(query)
        rows = session.fetchall()
    return [
        {"chat_id": str(r[0]), "role": r[1], "timestamp": r[2].isoformat(), "content": r[3]}
        for r in rows
    ]
    
def add_entry(session_id: str, role: str, timestamp: str |None = None, content: str | None=None) -> str:
    """iv. Add one chat turn (user or assistant) to the session's table."""
    if content == None or len(content) <  1:
        print("Content returned empty, skip adding into database")
        return ""
    chat_id = str(uuid4())
    with connection() as con:
        query = sql.SQL(
            """
            INSERT INTO {} (chat_id, role, timestamp, content)
            VALUES (%s, %s, COALESCE(%s, NOW()), %s)
            """
        ).format(sql.Identifier(str(session_id)))
        con.execute(query, (chat_id, role, timestamp, content))
        con.commit()
    return chat_id