-- Sanjeevani AI — relational schema.
-- Auto-applied by the postgres container on first boot (docker-entrypoint-initdb.d).
-- Images/PDFs live in files.data as bytea; there is no object store in this deployment.

create extension if not exists pgcrypto;   -- gen_random_uuid(), crypt() for the seed

-- ---------------------------------------------------------------- identity

create table users (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique,             -- always stored lowercased
  password_hash text,                             -- null for Google-only accounts
  google_sub    text unique,                      -- Google "sub" claim
  firebase_uid  text unique,                      -- Firebase Auth uid, the only
                                                  -- stable id there (email can change)
  role          text not null check (role in ('patient','doctor','admin')),
  full_name     text not null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Binary blobs. Kept in Postgres on purpose (single-container deployment, no S3).
-- ponytail: bytea caps out around a few MB per row; move to large objects or an
-- object store if scans/DICOM ever land here.
create table files (
  id            uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references users(id) on delete cascade,
  filename      text,
  mime          text not null,
  size_bytes    integer not null,
  data          bytea not null,
  created_at    timestamptz not null default now()
);
create index files_owner_idx on files(owner_user_id);

-- ---------------------------------------------------------------- facilities

create table hospitals (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  address    text,
  city       text,
  phone      text,
  lat        double precision,
  lng        double precision,
  created_at timestamptz not null default now()
);

create table departments (
  id          uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references hospitals(id) on delete cascade,
  name        text not null,
  specialty   text not null,        -- routing key the triage layer returns
  unique (hospital_id, specialty)
);

create table doctors (
  user_id       uuid primary key references users(id) on delete cascade,
  hospital_id   uuid not null references hospitals(id) on delete cascade,
  department_id uuid references departments(id) on delete set null,
  specialty     text,
  reg_no        text,
  photo_file_id uuid references files(id) on delete set null,
  is_available  boolean not null default true
);
create index doctors_hospital_idx on doctors(hospital_id);

create table hospital_admins (
  user_id     uuid primary key references users(id) on delete cascade,
  hospital_id uuid not null references hospitals(id) on delete cascade
);

-- ---------------------------------------------------------------- patients

create table patients (
  user_id            uuid primary key references users(id) on delete cascade,
  profile_file_id    uuid references files(id) on delete set null,
  dob                date,                  -- age is derived, never stored
  gender             text check (gender in ('male','female','other','prefer_not_to_say')),
  blood_type         text,
  phone              text,
  address            text,
  lat                double precision,
  lng                double precision,
  insurance_provider text,
  policy_number      text,
  aadhaar_last4      text,
  aadhaar_verified   boolean not null default false,   -- UI-only flow, see appfeature.md
  app_lock_pin_hash  text,
  language           text not null default 'en',
  profile_complete   boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table patient_conditions (
  id         uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(user_id) on delete cascade,
  kind       text not null check (kind in ('disease','allergy','genetic')),
  label      text not null,
  notes      text,
  created_at timestamptz not null default now()
);
create index patient_conditions_patient_idx on patient_conditions(patient_id);

-- Auto-notified when the patient is admitted.
create table patient_relatives (
  id         uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(user_id) on delete cascade,
  name       text not null,
  contact    text not null,
  relation   text not null,          -- guardian | sibling | spouse | parent | ...
  notify     boolean not null default true,
  created_at timestamptz not null default now()
);
create index patient_relatives_patient_idx on patient_relatives(patient_id);

create table patient_preferred_hospitals (
  patient_id  uuid not null references patients(user_id) on delete cascade,
  hospital_id uuid not null references hospitals(id) on delete cascade,
  primary key (patient_id, hospital_id)
);

create table medical_documents (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references patients(user_id) on delete cascade,
  file_id     uuid not null references files(id) on delete cascade,
  label       text not null,        -- the patient's own words: "blood test", "x-ray"
  description text,
  created_at  timestamptz not null default now()
);
create index medical_documents_patient_idx on medical_documents(patient_id);

-- ---------------------------------------------------------------- chat

-- 'ai'        -> triage assistant thread
-- 'care_team' -> humans at a hospital (doctors / front desk)
create table conversations (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references patients(user_id) on delete cascade,
  kind            text not null check (kind in ('ai','care_team')),
  hospital_id     uuid references hospitals(id) on delete set null,
  title           text,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);
create index conversations_patient_idx on conversations(patient_id, last_message_at desc);

create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_role     text not null check (sender_role in ('patient','ai','doctor','system')),
  sender_user_id  uuid references users(id) on delete set null,
  kind            text not null default 'text'
                  check (kind in ('text','image','audio','mcq','mcq_answer',
                                  'hospital_suggestion','report','status')),
  body            text,             -- display text for every kind
  payload         jsonb,            -- mcq options, hospital list, report fields
  file_id         uuid references files(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index messages_conversation_idx on messages(conversation_id, created_at);

-- ---------------------------------------------------------------- triage seam
-- Owned by the AI team. This backend only writes requests and reads results;
-- it never computes a specialty, urgency, or red flag itself.

create table triage_requests (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  patient_id      uuid not null references patients(user_id) on delete cascade,
  status          text not null default 'pending'
                  check (status in ('pending','done','failed')),
  source          text not null default 'stub'
                  check (source in ('stub','http')),
  request         jsonb not null,
  error           text,
  created_at      timestamptz not null default now(),
  completed_at    timestamptz
);
create index triage_requests_status_idx on triage_requests(status, created_at);
create unique index triage_requests_one_pending_idx
  on triage_requests(conversation_id) where status = 'pending';

create table triage_results (
  id                  uuid primary key default gen_random_uuid(),
  triage_request_id   uuid not null unique references triage_requests(id) on delete cascade,
  patient_id          uuid not null references patients(user_id) on delete cascade,
  chief_complaint     text,
  symptoms            jsonb,      -- [{name, duration, severity}]
  specialty           text,
  urgency             integer check (urgency between 1 and 5),   -- 1 = most urgent
  red_flag            boolean not null default false,
  summary             text,       -- plain language, shown to the patient
  clinical_note       text,       -- shorthand, shown to the doctor
  sources             jsonb,      -- provenance for every routing decision
  suggested_hospitals jsonb,
  follow_up_questions jsonb,      -- MCQs the assistant still wants answered
  confidence          double precision,
  raw                 jsonb,      -- untouched provider response, for audit
  created_at          timestamptz not null default now()
);
create index triage_results_patient_idx on triage_results(patient_id, created_at desc);

-- ---------------------------------------------------------------- queue

create table visits (
  id                 uuid primary key default gen_random_uuid(),
  patient_id         uuid not null references patients(user_id) on delete cascade,
  hospital_id        uuid not null references hospitals(id) on delete cascade,
  department_id      uuid references departments(id) on delete set null,
  doctor_user_id     uuid references users(id) on delete set null,
  triage_result_id   uuid references triage_results(id) on delete set null,
  token_date         date not null default current_date,
  -- Null until a doctor decides the patient should physically come in. Triage
  -- alone does not earn a queue position: a doctor may answer over chat instead,
  -- and that patient never takes a token. Postgres lets nulls repeat under the
  -- unique constraint below, which is exactly what we want here.
  token_no           integer,
  urgency            integer not null default 4 check (urgency between 1 and 5),
  urgency_overridden boolean not null default false,
  -- pending_review: triaged, waiting on a doctor's call-in-or-chat decision.
  -- chat:           doctor chose to handle it remotely. No token, no queue slot.
  status             text not null default 'pending_review'
                     check (status in ('pending_review','chat','waiting','in_consult',
                                       'done','referred','cancelled')),
  -- Set when a token is issued, so "triaged at" and "called in at" stay distinct.
  admitted_at        timestamptz,
  reason             text,
  doctor_notes       text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (hospital_id, token_date, token_no)
);
create index visits_queue_idx on visits(hospital_id, status, urgency, created_at);
-- The doctor's review list: everything triaged but not yet decided.
create index visits_pending_idx on visits(hospital_id, created_at)
  where status = 'pending_review';

-- ---------------------------------------------------------------- audit
-- Design_doc §6 requires every AI recommendation and doctor override be logged.

create table audit_log (
  id            bigserial primary key,
  actor_user_id uuid references users(id) on delete set null,
  -- Whose trail this belongs to. Null means it is no single hospital's business
  -- (a patient registering, or editing their own profile), and those rows are
  -- never shown to a hospital admin. Staff read the log scoped to this column.
  hospital_id   uuid references hospitals(id) on delete set null,
  action        text not null,
  entity        text,
  entity_id     uuid,
  detail        jsonb,
  created_at    timestamptz not null default now()
);
create index audit_log_created_idx on audit_log(created_at desc);
create index audit_log_hospital_idx on audit_log(hospital_id, id desc);
