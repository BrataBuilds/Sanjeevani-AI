# Sanjeevani AI — Developer Wiki

Conversational hospital triage and registration. A patient describes their problem in
their own language, and comes out with a completed registration, a preliminary summary,
a department and doctor, and a queue token — or a redirect to a better-suited facility.

The system is a **triage and routing layer, not a diagnostic one**: it decides who a
patient should see and how urgently, and hands the doctor a filled-in starting point
instead of a blank slate.

---

## What is in the repository

| Path | What it is | Stack |
|---|---|---|
| `app/` | Patient mobile app | Flutter 3.44 (Android, iOS, web) |
| `web/` | Doctor + hospital admin console | Next.js 16 App Router |
| `backend/` | REST API | Node 24, Express 5, `pg` (raw SQL) |
| `db/` | Schema + demo seed | PostgreSQL 17, applied on first container boot |
| `scripts/smoke.sh` | End-to-end check of the whole journey | bash + curl |
| `docs/` | These pages | |
| `RAG/` | Triage / retrieval layer | Python — separate team, currently empty |
| `Design docs/` | Problem statement, design doc, feature set, workflows | |

The AI/RAG triage layer is **not** in this repository. It is owned by another team and
plugs into a documented seam — see **[AI Integration Contract](AI-Integration-Contract)**.

---

## Start here

| I want to… | Page |
|---|---|
| Run the whole thing locally | [Getting Started](Getting-Started) |
| Understand how the pieces fit | [Architecture](Architecture) |
| Plug in the triage model | [AI Integration Contract](AI-Integration-Contract) |
| Know what every table holds | [Data Model](Data-Model) |
| Call the API | [API Reference](API-Reference) |
| Work on the patient app | [Patient App](Patient-App) |
| Work on the staff console | [Staff Web Console](Staff-Web-Console) |
| Know what is built vs. deferred, **and the four open questions** | [Feature Coverage](Feature-Coverage) |
| Understand what is mocked and what is risky | [Security and Compliance](Security-and-Compliance) |

---

## The one-paragraph version of the flow

The patient signs in (Google or email/password), fills a profile once, and opens the
assistant chat. Each message they send creates a `triage_requests` row and is handed to
the AI seam with the full transcript, the patient's known conditions, and a
distance-sorted hospital list. Whatever comes back is stored in `triage_results` and
fanned out into chat messages — a reply bubble, tappable follow-up questions, a
plain-language report, hospital suggestions — plus a `visits` row, which is the queue
token. The doctor's console shows that queue sorted by urgency, opens the full report
before the consult, and lets the doctor override the urgency; every override is written
to `audit_log`. The hospital admin console shows department load, urgency mix, daily
volume, and the audit trail.

---

## Stack decisions that differ from the design document

`Design docs/Design_doc.md` in the repository root proposes Python + FastAPI + ChromaDB + Redis +
S3 + Kubernetes. The owner overrode that for this build:

| Design doc | Built | Why |
|---|---|---|
| Python + FastAPI | **Node 24 + Express 5** | Team preference. |
| S3 / GCS object storage | **Postgres `bytea`** | One container to run; no cloud account needed for a demo. |
| Redis for queue/session state | **Postgres** | Queue volumes here do not need it, and it is one less moving part. |
| ChromaDB / Pinecone | **not in this repo** | Belongs to the AI team, behind the seam. |
| JWT + OTP | **JWT + Google OAuth + password** | OTP needs an SMS provider; not wired. |
| Kubernetes | **Docker Compose** | Single-host demo deployment. |

The RAG pipeline design in `Design docs/Design_doc.md` §5 — the probabilistic retrieval path and
the deterministic red-flag path that can override it — still stands. It just lives
behind `POST /triage` rather than inside this codebase.
