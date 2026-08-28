"""
Knowledge-base access layer for doctors, symptoms, and reports tables.
Separate from database.py which handles chat sessions.
"""

from services.database import connection
from pathlib import Path
import json

DATA_DIR = Path(__file__).resolve().parent.parent / "mock_data"
SCHEMA_FILE = DATA_DIR / "schema.sql"
SEED_FILES = (
    DATA_DIR / "seed_symptoms.sql",
    DATA_DIR / "seed_doctors.sql",
)

def _execute_sql_file(path: Path) -> None:
    query = path.read_text(encoding="utf-8")
    with connection() as con:
        con.execute(query)
        con.commit()


def initialize() -> None:
    """Create and idempotently seed the knowledge-base tables."""
    _execute_sql_file(SCHEMA_FILE)
    for seed_file in SEED_FILES:
        _execute_sql_file(seed_file)


def _symptom_record(row: tuple) -> dict:
    return {
        "symptom_id": str(row[0]),
        "name": row[1],
        "description": row[2],
        "specialties": row[3],
        "related_symptoms": row[4],
        "urgency_score": float(row[5]),
        "possible_diseases": row[6],
        "additional_info": row[7],
        "updated_at": row[8],
    }
    

def all_symptoms() -> list[dict]:
    """Return every symptom row."""
    with connection() as con:
        rows = con.execute("SELECT * FROM symptoms ORDER BY symptom_id").fetchall()
    return [_symptom_record(row) for row in rows]
    
def check_symptoms(names: list[str])-> list[dict]:
    """Check if the given list of symptoms are in the database.
    If present return their details.
    """
    lower = [n.lower() for n in names]
    with connection() as con:
        rows =  con.execute(
            """SELECT * FROM symptoms WHERE LOWER(symptom_name) = ANY(%s)""",
            (lower, ),).fetchall()
    return [_symptom_record(row) for row in rows]


def get_symptoms_by_ids(symptom_ids: list[str]) -> list[dict]:
    """Fetch Chroma symptom IDs while preserving Chroma's relevance ordering."""
    ids = [int(symptom_id) for symptom_id in symptom_ids]
    if not ids:
        return []

    with connection() as con:
        rows = con.execute(
            "SELECT * FROM symptoms WHERE symptom_id = ANY(%s)",
            (ids,),
        ).fetchall()

    by_id = {str(row[0]): _symptom_record(row) for row in rows}
    return [by_id[symptom_id] for symptom_id in symptom_ids if symptom_id in by_id]

    
def available_specialities()->list[str]:
    """Return all the specialities available right now"""
    with connection() as con:
        rows =  con.execute(
            """SELECT DISTINCT specialty FROM doctors"""
        )
        return [str(r[0]) for r in rows]


def save_report(session_id: str, report: dict) -> None:
    with connection() as con:
        con.execute(
            """
            UPDATE session_state
            SET report = %s, status = 'completed', updated_at = NOW()
            WHERE session_id = %s
            """,
            (json.dumps(report), session_id),
        )
        con.commit()
