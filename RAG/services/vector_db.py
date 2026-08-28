"""
TODO 1. Generate embeddings for the symptoms present in the database.
TODO 2. Store the data persistently in 'mock_data/'
This file handles symptom embeddings and semantic search using ChromaDB.

1. build_symptom_db()
- Calls all_symptoms() from database.py.

2. query_symptoms()
- Takes a user's text query.
- Chroma converts the query into an embedding.
- Finds the most semantically similar symptoms.
- Returns their stored text as plain text.

The Chroma database is persisted in ./mock_data/chroma_data."""

from pathlib import Path
import chromadb
from services.knowledge import all_symptoms, get_symptoms_by_ids
VDB_DIR = Path(__file__).parent.parent / "mock_data" / ""


# Persistent ChromaDB database
client = chromadb.PersistentClient(path=VDB_DIR)

collection = client.get_or_create_collection(
    name="symptoms"
)


def build_symptom_db():
    """
    - Converts every symptom record into a text document which is then stored in ChromaDB.
    - Chroma automatically generates and stores embeddings. We are using the default embedding model as of now.
    """
    records = all_symptoms()
    documents = []
    ids = []
    for record in records:
        symptom_id = str(record["symptom_id"])
        document = f"""
    Symptom: {record["name"]}
    Description: {record["description"]}
    Urgency Score: {record["urgency_score"]}
    Related Symptoms: {record["related_symptoms"]}
    Specialties: {record["specialties"]}
    Additional Information: {record["additional_info"]}
    Updated At: {record["updated_at"]}""".strip()
        ids.append(symptom_id)
        documents.append(document)

    collection.upsert(
        ids=ids,
        documents=documents,
    )


def query_symptoms(query: str, top_k: int = 5) -> str:
    """
    Search the hospital's symptom knowledge base for entries related to the given description or keyword, and return their urgency score, relevant
    specialties, related symptoms, and possible diseases as plain text. Call this every time the patient, before estimating its urgency score or recommending a specialty.
    You will receive the following details:
    symptom description,related_symptoms, doctor_specialities who can handle that symptom/associated disease,urgency_score from 5 to 100 where 5 indicates very minor issue, 100 indicates immediate emergency escalation
    """
    results = collection.query(query_texts=[query], n_results=top_k)
    matched_ids = results["ids"][0] if results["ids"] else []

    matched = get_symptoms_by_ids(matched_ids)
    if not matched:
        return "No matching symptoms found in the knowledge base."

    lines = []
    for s in matched:
        specialties = ", ".join(s["specialties"])
        related = ", ".join(s["related_symptoms"] or []) or "none listed"
        diseases = ", ".join(s["possible_diseases"] or []) or "none listed"
        lines.append(f"{s['name']}: urgency score {s['urgency_score']} from 5 to 100 where 5 indicates very minor issue, 100 indicates immediate emergency escalation, "
            f"relevant specialties: {specialties}, related symptoms: {related}, "
            f"possible diseases: {diseases}. {s['description'] or ''}"
        )
    return "\n".join(lines)
