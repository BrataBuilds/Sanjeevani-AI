# *Name in progress* SIH 2026 Submissions Smart Healthcare app
## Brief overview
*Name in progress* is an AI assisted health care app that streamlines the process of visiting hospitals. Users describe their problem to our chat assistant that boots up an agent, automatically creates an registration form, a preliminary clinical summary and shows the user a list of recommended hospitals. Based on user's choice, their report is forwarded to the respective facilities, and they are automatically assigned a doctor/department, enabling a seamless experience.
## Core Features 
- **One-time profile setup** with a persistent patient ID, registration takes seconds.
- **Easy Appointment booking** + **walk-in/emergency** registration
- **Auto department/doctor assignment** based on specialty match + real-time doctor availability. 
- **Hospital admin dashboard**: patient flow analytics, department load, bottleneck visibility
- **Deterministic red-flag/emergency detection** that can escalate immediately, independent of the AI's own judgment.
- **Nearest-alternative-hospital** / **User preferred** recommendation when the current facility is unsuitable or overloaded.
- **Doctor-side dashboard:** see the AI-generated report before the consult, manage queue, override urgency if needed
### Planned features for future expansion
- **Portable medical history** that follows the patient across visits and, across hospitals overtime.
- **Multi-lingual** and **multimodal** LLM chat bot.
- **Billing & payments**: One place to view/pay bills.
## Our methodology
### Problems we are trying to solve
1. **Registration is manual and repetitive.** Patients fill the same paper/counter form on every visit, often standing in a separate line just to be allowed into the real line.
2. **Patients don't know who to see.** All patients join the same general queue, and self-routing to "the right doctor" is a guess made by someone with no medical training, sometimes literally by asking a stranger in line, sometimes referring to long lost cousins or uncle ramesh nearby.
3. **No urgency-based prioritization.** Because there's no structured intake, urgent cases don't get flagged until a doctor happens to see them — the queue is *first-come-first-served* regardless of severity.
4. **Overcrowding everywhere**. A handful of well-known hospitals get flooded while nearby, equally capable facilities sit underused, simply because patients default to "the big hospital" out of habit or lack of information about alternatives.
5.  **Managing Records is a burden,** History, past prescriptions, and reports are fragmented across paper files and hospital-specific systems, so every new visit — even at the same hospital — often starts from zero.
6.  **Billing and insurance are a nightmare.** Cashless claims, reimbursement paperwork, and bill tracking are handled through slow, mostly manual processes layered on top of an already slow visit.
7.  **Loss of time and poor logistics**: patients lose time and clarity, doctors lose time to administrative overhead and mis-routed cases, and hospitals lose the ability to allocate their own capacity intelligently.

### Design principles and rationale behind our technical choices
1. **Main focus is on reducing burdens**, *Having a  disease/illness already in it self a burden, our focus is to make that more manageable*, this means no more standing in long queues, for hours on end only to be told your appointment is two weeks later. No more contacting your 5th cousins to recommend a good doctor.
2. **Triage and assistant system not a diagnostic one**: *Our goal is to guide users to right place, not to make medical decisions for them*, that power resides with the doctors, we only tell people where to go and whom to meet, **this is not a flaw but entirely by design**, as we believe current frontier models aren't capable of/**aren't deterministic** enough *to manage critical medical decisions for an individual*.
Right now AI is only capable of making amateur level diagnosis, but falls apart when it comes to critical decisions. This is the main reason why we have a rule-based RAG safety layer on top on the general purpose LLM. 
1. **Make a profile once, register everywhere**, improves accessibility, reduces friction, Re-entering the same history every visit is pure friction, and it's actively dangerous for people who can't communicate well in the moment (elderly patients, unconscious/semi-conscious emergency cases, non-native speakers). A persistent, portable profile — ideally interoperable with India's existing ABHA (Ayushman Bharat Health Account) digital health ID — removes that friction and gives emergency staff something to work from even if the patient can't speak. 
2. **Enabling streamlined process and ease of use**: One click everything, reduces overhead for all users, hospitals, and doctors.
3. **Privacy focused**, no data is stored on external servers/shared with third parties without consent. Everything is stored locally.
4. **Human in the loop enabled**, no false positives, ensure critical decisions are always made by a professional.
## Tech Stack
- App : Flutter 
- Dashboards Doctor/Hospital: Next JS
- AI : Gemini API, groq, open router, pinecone/chroma db, agno / langchain, 
- Backend: Dockerized Postgresql, Node, Google OAuth, Docker, Redis, GCP, cloudinary
-

---

# Repository

| Path | What | Stack |
|---|---|---|
| `app/` | Patient app | Flutter 3.44 — Android, iOS, web |
| `web/` | Doctor + hospital admin console | Next.js 16 App Router |
| `backend/` | REST API | Node 24, Express 5, `pg` (raw SQL) |
| `db/` | Schema + demo seed | PostgreSQL 17 |
| `RAG/` | Triage / retrieval layer | Python — separate team, see the seam below |
| `Design docs/` | Problem statement, design doc, feature set, workflows | |
| `scripts/smoke.sh` | End-to-end check of the whole journey | bash + curl |
| `docs/` | Source for the [wiki](../../wiki) | |

## Run it

```bash
cp .env.example .env

docker compose up -d db                      # Postgres on host port 5433, schema + seed applied
cd backend && npm install && npm run dev     # API on :4000
cd web     && npm install && npm run dev     # console on :3000
cd app     && flutter run                    # or: flutter run -d chrome
```

Or `docker compose up` for db + API + console together.

Seeded accounts, all with password `password123`:

| Role | Email |
|---|---|
| Patient | `patient@demo.test` |
| Doctor | `dr.mehta@citygeneral.test` |
| Hospital admin | `admin@citygeneral.test` |

Doctors and admins cannot self-register — a hospital admin creates them from the console.

## The AI seam

The triage / RAG layer is **not** implemented in the app or backend. The platform exposes
a documented interface and stores whatever comes back; it never decides a specialty, an
urgency score, or whether a case is an emergency.

- Unset `AI_SERVICE_URL` and the backend answers from a clearly-labelled stub, so the app
  and both dashboards are fully demoable with no model connected.
- Set it and the backend `POST`s the conversation, patient profile, and a distance-sorted
  hospital list to `{AI_SERVICE_URL}/triage`. Synchronous, async-callback, and
  worker-pull modes are all supported.

Full contract, with request/response examples: **[AI Integration Contract](../../wiki/AI-Integration-Contract)**.

## Checks

```bash
cd backend && npm test          # pure-logic unit tests, no DB
cd app     && flutter test      # client unit + widget tests
cd app     && flutter analyze
cd web     && npm run build     # typechecks and builds
bash scripts/smoke.sh           # 73 end-to-end assertions; needs db + backend up
```

`scripts/smoke.sh` walks register → profile → document upload → triage chat → MCQ answers
→ report → queue token → doctor queue → urgency override → care-team chat → admin
analytics → audit trail, and asserts the access-control boundaries.

## Notes on this build

- **The UI on both frontends is placeholder** — plain Material 3 and one stylesheet, no
  component library. It is meant to be replaced by the design team. The data model, the
  API, the access rules, and the AI seam are the parts meant to last.
- **Stack differs from `Design docs/Design_doc.md` in places**: Node + Express instead of
  Python + FastAPI, images in Postgres `bytea` instead of an object store, no Redis,
  Docker Compose instead of Kubernetes. Reasons for each are in the
  [wiki](../../wiki).
- **Open questions** that need a decision are listed in
  [Feature Coverage](../../wiki/Feature-Coverage) — notably the urgency scale
  (`Symptom Urgency_Score.txt` uses 0–100, the design doc implies a 1–5 tier; the code
  currently uses 1–5) and whether registration should wait for hospital-admin approval.

Developer documentation: **[wiki](../../wiki)**.
