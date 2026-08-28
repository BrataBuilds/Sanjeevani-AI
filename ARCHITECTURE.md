# Architecture

Sanjeevani AI — conversational hospital triage and registration.

Two diagrams: what the pieces are, and how a patient's problem moves through them.
Both are Mermaid and render on GitHub.

Related: [`SETUP.md`](SETUP.md) to run it, [`docs/AI-Integration-Contract.md`](docs/AI-Integration-Contract.md)
for the triage payload, [`db/01-schema.sql`](db/01-schema.sql) for the tables.

---

## 1. Architecture

Four services and one database. The AI service is profile-gated (`--profile ai`)
and reachable only through a single seam, so the platform runs and demos without it.

```mermaid
graph TB
    subgraph clients["Clients"]
        APP["<b>Patient app</b><br/>Flutter · Android / iOS / web<br/>:8081"]
        WEB["<b>Staff console</b><br/>Next.js 15 · doctor + admin<br/>:3000"]
    end

    subgraph platform["Platform — this repository"]
        API["<b>Backend</b><br/>Node 24 · Express 5 · raw SQL<br/>:4000"]
        SEAM["<b>AI seam</b><br/>src/lib/ai.js<br/>stub when AI_SERVICE_URL unset"]
        API --- SEAM
    end

    subgraph ai["Triage service — separate team, profile-gated"]
        RAG["<b>RAG API</b><br/>FastAPI · agno agent<br/>:8000"]
        CHROMA[("Chroma<br/>symptom embeddings")]
        RAG --- CHROMA
    end

    subgraph data["Postgres 17 · :5433"]
        PUB[("<b>public</b><br/>users · patients · doctors<br/>conversations · messages<br/>triage_requests / _results<br/>visits · audit_log<br/>files as bytea")]
        RAGS[("<b>rag</b><br/>symptoms · sessions<br/>session_state<br/>per-session transcripts")]
    end

    EXT["<b>Google / Firebase</b><br/>ID token verification<br/>public certs only"]
    GEM["<b>Gemini API</b>"]

    APP -->|"REST + Bearer JWT"| API
    WEB -->|"REST + Bearer JWT"| API
    APP -.->|"sign in"| EXT
    API -.->|"verify ID token"| EXT

    SEAM -->|"POST /triage"| RAG
    RAG -->|"POST /ai/triage-callback<br/>(async path, x-ai-secret)"| API
    RAG --> GEM

    API --> PUB
    RAG --> RAGS
    RAG -.->|"reads departments.specialty"| PUB

    classDef ours fill:#e8f0fe,stroke:#3b6ea5,stroke-width:2px,color:#12263a
    classDef theirs fill:#fdf1e0,stroke:#c98a2e,stroke-width:2px,color:#3a2a12
    classDef store fill:#eef6ee,stroke:#4a8055,stroke-width:2px,color:#16301c
    classDef ext fill:#f3f0f7,stroke:#7a5ea8,stroke-width:2px,color:#241a33
    class APP,WEB,API,SEAM ours
    class RAG,CHROMA theirs
    class PUB,RAGS store
    class EXT,GEM ext
```

**Boundaries that matter**

| Boundary | Rule |
|---|---|
| AI seam | The backend never decides a specialty, an urgency or a red flag. It builds a payload, stores what comes back, and renders it. All reasoning is behind `POST /triage`. |
| Postgres schemas | The triage service shares the database but owns the `rag` schema. It reads `departments.specialty` and writes nothing to `public`. |
| Staff accounts | Never self-signup. An admin authorises the address; the first admin comes from `ADMIN_*` env. |
| Files | Stored as `bytea` in Postgres, served through `/files/:id` behind auth. No object store. |

---

## 2. Dataflow — one problem, end to end

The thing worth following is **where a token is issued**: triage routes a patient to
a department, but only a doctor deciding they should come in creates one. A consult
answered over chat never takes a queue slot.

```mermaid
sequenceDiagram
    autonumber
    actor P as Patient
    participant A as Patient app
    participant B as Backend
    participant R as Triage service
    participant D as Postgres
    actor Doc as Doctor

    rect rgb(232, 240, 254)
    note over P,D: Intake — registration questions, asked one at a time
    P->>A: opens a new consultation
    A->>B: POST /conversations {kind:"ai"}
    B->>D: conversation + first intake question
    loop 4 questions
        P->>A: taps an option
        A->>B: POST /:id/mcq-answer
        B->>D: store answer, ask the next
    end
    note right of B: intake alone never fires triage —<br/>there is no complaint in it yet
    end

    rect rgb(253, 241, 224)
    note over P,R: Interview — the assistant must ask before it may conclude
    P->>A: "severe chest pain, short of breath"
    A->>B: POST /:id/messages
    B->>D: triage_requests (pending)
    B->>R: POST /triage — transcript, profile, hospitals
    note right of R: first turn replays the intake too
    R->>R: symptoms → urgency (0-100) → ESI 1-5
    R-->>B: needs_more_info + one MCQ
    B->>D: messages (mcq)
    loop until the question floor is cleared
        P->>A: answers
        A->>B: POST /:id/mcq-answer
        B->>R: POST /triage
        R-->>B: another question
    end
    R-->>B: ok — complaint, symptoms, specialty, ESI, sources
    end

    rect rgb(238, 246, 238)
    note over B,Doc: Routing — a department, not a token
    B->>D: triage_results
    B->>D: visit (status pending_review, token_no NULL)
    B-->>A: report + suggested hospitals
    A-->>P: "a doctor will review this"
    end

    rect rgb(243, 240, 247)
    note over Doc,P: The decision — the only place a token is issued
    Doc->>B: GET /doctor/queue — undecided first
    Doc->>B: GET /doctor/visits/:id — report + the thread that produced it
    alt Come in
        Doc->>B: POST /visits/:id/decision {"admit"}
        B->>D: token_no = next, status waiting, admitted_at
        B-->>P: "Token #14 · Cardiology"
    else Answer here
        Doc->>B: POST /visits/:id/decision {"chat"}
        B->>D: status chat, token_no stays NULL
        B-->>P: "your doctor will answer you here"
    end
    B->>D: audit_log — every decision, scoped to the hospital
    end
```

### Where each thing is decided

```mermaid
graph LR
    subgraph rag["Triage service decides"]
        S1["which symptoms<br/>were described"]
        S2["urgency 0-100<br/>from the symptom table"]
        S3["recommended<br/>specialty"]
        S4["ask again, or<br/>conclude"]
    end
    subgraph be["Backend decides"]
        B1["which hospital<br/>nearest / preferred / suggested"]
        B2["which department<br/>specialty → departments"]
        B3["ESI → queue order"]
    end
    subgraph doc["The doctor decides"]
        D1["come in, or<br/>answer in chat"]
        D2["override the<br/>urgency"]
        D3["when the token<br/>is issued"]
    end

    rag --> be --> doc

    classDef a fill:#fdf1e0,stroke:#c98a2e,color:#3a2a12
    classDef b fill:#e8f0fe,stroke:#3b6ea5,color:#12263a
    classDef c fill:#f3f0f7,stroke:#7a5ea8,color:#241a33
    class S1,S2,S3,S4 a
    class B1,B2,B3 b
    class D1,D2,D3 c
```

Nothing clinical is decided in the middle column, and nothing final is decided in
the left one. That is the whole design: the model proposes, the database scores,
the doctor disposes — and every step lands in `audit_log`.

---

## 3. Authentication

```mermaid
graph TD
    START(["someone opens the app"]) --> WHO{"account exists?"}

    WHO -->|"patient, new"| SELF["self-signup<br/>email + password, or<br/>Google / Firebase ID token"]
    WHO -->|"patient, returning"| VERIFY
    WHO -->|"doctor"| PROV["an admin already created<br/>this email"]
    WHO -->|"admin"| ENV["ADMIN_EMAIL / ADMIN_PASSWORD<br/>from the environment"]

    SELF --> VERIFY["server verifies:<br/>bcrypt hash, or<br/>ID token signature + audience"]
    PROV --> VERIFY
    ENV --> VERIFY

    VERIFY -->|"ok"| JWT["our own JWT<br/>sub · role · email"]
    VERIFY -->|"bad token / password"| NO(["401"])

    JWT --> GUARD["requireAuth → requireRole<br/>staffHospitalId scopes every staff query"]

    classDef ok fill:#eef6ee,stroke:#4a8055,color:#16301c
    classDef no fill:#fdecec,stroke:#b4544c,color:#3a1614
    class JWT,GUARD ok
    class NO no
```

An external ID token is only ever an assertion of identity. Roles come from our
`users` table, never from the token — and a Firebase or Google account is linked to
an existing user **only when the provider says the email is verified**, because an
unverified claim would otherwise hand someone the doctor account an admin created
for that address.

---

## 4. Deployment

```mermaid
graph LR
    ENV[".env<br/>secrets, ports, project ids"] --> RUN["run.sh"]
    RUN --> COMPOSE["docker compose"]
    COMPOSE --> C1["db · postgres:17-alpine<br/>01-schema.sql, then 02-seed.sh"]
    COMPOSE --> C2["backend · node:24"]
    COMPOSE --> C3["web · next build"]
    COMPOSE --> C4["app-web · flutter build web → nginx"]
    COMPOSE -.->|"--profile ai"| C5["rag · uv + FastAPI"]

    classDef box fill:#e8f0fe,stroke:#3b6ea5,color:#12263a
    class C1,C2,C3,C4 box
```

`01-schema.sql` runs once on an empty volume. `02-seed.sh` loads demo data only
when `SEED_DEMO_DATA=true` — **off by default**, because every seeded account shares
one password published in this repository. A real deployment provisions its first
administrator from `ADMIN_*` instead, and that account is reconciled against the
environment on every boot.

The Flutter mobile build cannot be containerised; `app/Dockerfile` is the web build
served by nginx.
