"""
Knowledge-base access layer for doctors, symptoms, and reports tables.
Separate from database.py which handles chat sessions.
"""

from services.database import connection
from pathlib import Path
import json

DATA_DIR = Path(__file__).resolve().parent.parent / "mock_data"
SCHEMA_FILE = DATA_DIR / "schema.sql"

# The original symptom set, scored 0-50. Still loaded because it carries 15
# symptoms the newer files do not -- seizures, sudden vision loss, allergic
# reaction, blood in stool, high fever among them -- but its scores are doubled
# on load so everything in the table shares one scale.
LEGACY_SEED_FILE = DATA_DIR / "seed_symptoms.sql"
LEGACY_SCALE_MAX = 50

# V2 (single symptoms) and V3 (combinations), already scored 0-100, which is the
# scale /triage reports on and docs/AI-Integration-Contract.md documents. Where a
# symptom appears in both generations the newer row wins; see initialize().
SEED_FILES = (
    DATA_DIR / "seed_symptomsV2.sql",
    DATA_DIR / "seed_symptomsV3.sql",
)

def _execute_sql_file(path: Path) -> None:
    query = path.read_text(encoding="utf-8")
    with connection() as con:
        con.execute(query)
        con.commit()


def initialize() -> None:
    """Create and idempotently seed the knowledge-base tables.

    symptom_name lost its UNIQUE constraint upstream, so the seeds can no longer
    rely on ON CONFLICT DO NOTHING -- re-running them would stack a fresh copy of
    every symptom on each boot. The table is a static knowledge base built purely
    from these files, so it is rebuilt from empty instead.
    """
    _execute_sql_file(SCHEMA_FILE)

    with connection() as con:
        con.execute("TRUNCATE symptoms RESTART IDENTITY")
        con.commit()

    _execute_sql_file(LEGACY_SEED_FILE)
    with connection() as con:
        # Bring the 0-50 generation onto the 0-100 scale everything else uses.
        # Safe to run over the whole table here: only the legacy rows exist yet.
        con.execute(
            "UPDATE symptoms SET urgency_score = urgency_score * %s",
            (100 / LEGACY_SCALE_MAX,),
        )
        con.commit()

    for seed_file in SEED_FILES:
        _execute_sql_file(seed_file)

    with connection() as con:
        # Keep the highest symptom_id per name: rows are inserted oldest
        # generation first, so this drops the legacy copy of anything V2 or V3
        # also describes and leaves one row per symptom for check_symptoms.
        con.execute(
            """
            DELETE FROM symptoms a USING symptoms b
             WHERE LOWER(a.symptom_name) = LOWER(b.symptom_name)
               AND a.symptom_id < b.symptom_id
            """
        )
        con.commit()


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
    """Return all the specialities available right now.

    Reads the platform's departments table -- the routing key the backend maps a
    triage result onto -- rather than a mock doctors table of our own.
    """
    with connection() as con:
        rows = con.execute(
            """SELECT DISTINCT specialty FROM departments ORDER BY specialty"""
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
