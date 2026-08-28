CREATE TABLE IF NOT EXISTS doctors (
    doctor_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id  UUID NOT NULL,
    name         TEXT NOT NULL,
    specialty    TEXT NOT NULL,
    available    BOOLEAN DEFAULT TRUE
);
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