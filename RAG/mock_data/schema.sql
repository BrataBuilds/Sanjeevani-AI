-- No doctors table here on purpose. The platform schema (db/01-schema.sql) owns
-- `doctors` and `departments`; a mock one with the same name silently loses to
-- CREATE TABLE IF NOT EXISTS and then fails on the first insert.
CREATE TABLE IF NOT EXISTS symptoms (
    symptom_id         SERIAL PRIMARY KEY,
    symptom_name       TEXT NOT NULL,
    description        TEXT,
    specialties        TEXT[] NOT NULL,
    related_symptoms   TEXT[],
    urgency_score      FLOAT NOT NULL,
    possible_diseases  TEXT[],
    additional_info    TEXT,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Per-conversation triage state. report.py, knowledge.py and api/routes/chat.py all
-- read and write this; it had no CREATE statement anywhere, so every session failed
-- on the first insert.
CREATE TABLE IF NOT EXISTS session_state (
    session_id          UUID PRIMARY KEY,
    total_urgency_score FLOAT   NOT NULL DEFAULT 0,
    questions_asked     INTEGER NOT NULL DEFAULT 0,
    identified_symptoms JSONB   NOT NULL DEFAULT '[]'::jsonb,
    status              TEXT    NOT NULL DEFAULT 'in_progress',
    report              JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
