from pathlib import Path

from services import knowledge


class _Cursor:
    def __init__(self, rows: list[tuple]) -> None:
        self._rows = rows

    def fetchall(self) -> list[tuple]:
        return self._rows


class _Connection:
    def __init__(self, rows: list[tuple]) -> None:
        self.rows = rows
        self.queries: list[tuple[str, tuple | None]] = []

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def execute(self, query: str, params: tuple | None = None) -> _Cursor:
        self.queries.append((query, params))
        return _Cursor(self.rows)

    def commit(self) -> None:
        pass


def test_get_symptoms_by_ids_preserves_chroma_order(monkeypatch) -> None:
    rows = [
        (1, "chest pain", "", ["Cardiology"], [], 45, [], "", None),
        (2, "fainting", "", ["Neurology"], [], 35, [], "", None),
    ]
    connection = _Connection(rows)
    monkeypatch.setattr(knowledge, "connection", lambda: connection)

    symptoms = knowledge.get_symptoms_by_ids(["2", "1"])

    assert [symptom["name"] for symptom in symptoms] == ["fainting", "chest pain"]
    assert connection.queries[0][1] == ([2, 1],)


def test_initialize_executes_schema_then_both_seed_files(monkeypatch, tmp_path: Path) -> None:
    schema = tmp_path / "schema.sql"
    symptoms = tmp_path / "seed_symptoms.sql"
    doctors = tmp_path / "seed_doctors.sql"
    schema.write_text("schema", encoding="utf-8")
    symptoms.write_text("symptoms", encoding="utf-8")
    doctors.write_text("doctors", encoding="utf-8")
    connection = _Connection([])

    monkeypatch.setattr(knowledge, "SCHEMA_FILE", schema)
    monkeypatch.setattr(knowledge, "SEED_FILES", (symptoms, doctors))
    monkeypatch.setattr(knowledge, "connection", lambda: connection)

    knowledge.initialize()

    assert [query for query, _ in connection.queries] == [
        "schema",
        "symptoms",
        "doctors",
    ]
