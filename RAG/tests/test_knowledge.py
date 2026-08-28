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


def test_initialize_rebuilds_the_table_from_every_generation(monkeypatch, tmp_path: Path) -> None:
    """Order matters: the legacy file is rescaled onto the 0-100 scale while it is
    the only thing in the table, and the de-dupe runs after the newer files land
    so their rows are the ones that survive."""
    schema = tmp_path / "schema.sql"
    legacy = tmp_path / "seed_symptoms.sql"
    v2 = tmp_path / "seed_symptomsV2.sql"
    v3 = tmp_path / "seed_symptomsV3.sql"
    for path, text in ((schema, "schema"), (legacy, "legacy"), (v2, "v2"), (v3, "v3")):
        path.write_text(text, encoding="utf-8")
    connection = _Connection([])

    monkeypatch.setattr(knowledge, "SCHEMA_FILE", schema)
    monkeypatch.setattr(knowledge, "LEGACY_SEED_FILE", legacy)
    monkeypatch.setattr(knowledge, "SEED_FILES", (v2, v3))
    monkeypatch.setattr(knowledge, "connection", lambda: connection)

    knowledge.initialize()

    steps = [q.strip().split()[0].upper() for q, _ in connection.queries]
    assert steps == ["SCHEMA", "TRUNCATE", "LEGACY", "UPDATE", "V2", "V3", "DELETE"]

    # The rescale must land between the legacy file and the newer ones.
    queries = [q for q, _ in connection.queries]
    assert queries.index("legacy") < queries.index("v2")
    rescale = next(i for i, q in enumerate(queries) if q.strip().startswith("UPDATE"))
    assert queries.index("legacy") < rescale < queries.index("v2")
