# Done

Status of the platform build as of 2026-08-26. Scope was the MVP in
`Design docs/App_Feature_Set.md` and `Design docs/Design_doc.md` §3, excluding the
AI/RAG layer.

Shipped on branch `feat/app-web-backend` — 4 commits, 149 files, +14,660 lines.
PR: <https://github.com/BrataBuilds/SIH2026-Smart-Health-App/pull/1> (open, not merged).
Wiki: 10 pages pushed, source in `docs/`.

---

## Built

### Database — `db/`
- **17 tables**, PostgreSQL 17, `db/01-schema.sql` + `db/02-seed.sql`, applied by the
  container on first boot.
- Identity (`users`, `files`), patients (`patients`, `patient_conditions`,
  `patient_relatives`, `patient_preferred_hospitals`, `medical_documents`), facilities
  (`hospitals`, `departments`, `doctors`, `hospital_admins`), chat (`conversations`,
  `messages`), the triage seam (`triage_requests`, `triage_results`), the queue
  (`visits`), and `audit_log`.
- Images and scanned PDFs live in `files.data` as `bytea` — no object store.
- Age is derived from `dob`, never stored.
- Seed: 2 hospitals ~6 km apart, 8 departments, 3 doctors, 1 admin, 1 patient with a
  filled profile, 1 waiting visit. All passwords `password123`.

### Backend — `backend/`
Node 24, Express 5, `pg` with raw parameterised SQL. No ORM, no query builder.
**50 endpoints** across 8 routers.

| Area | What works |
|---|---|
| Auth | Register/login (bcrypt), Google OAuth ID-token verification, JWT (30 d), bcrypt app-lock PIN, `/auth/me` role context, `/auth/config` |
| Patient | Profile read/partial-write, photo upload, conditions and relatives CRUD, preferred hospitals, medical-document upload/list/delete, mock Aadhaar, own visits, bills ledger |
| Files | `GET /files/:id` streams bytes behind three access rules |
| Chat | Both surfaces on one set of endpoints, incremental polling via `?after=`, text + attachment + MCQ-answer posting |
| Hospitals | List with live queue length and specialty keys, distance sort, detail with departments |
| Doctor | Queue (3 scopes, urgency-ordered), full pre-consult visit detail, urgency override + status transitions + notes, open a care-team thread |
| Admin | Flow analytics over a configurable window, visit list, department create/list, doctor provisioning and duty/account toggles, audit trail |
| AI seam | `/ai/health`, `/ai/triage-callback`, `/ai/pending`, `/ai/requests/:id` |

Cross-cutting: `HttpError` → JSON error handler, Postgres constraint violations mapped
to 4xx, CORS origin allowlist (native clients allowed), 10 MB upload cap with a mime
allowlist, append-only audit that never fails its own request.

### Staff console — `web/`
Next.js 16 App Router, React 19, TypeScript. **10 pages**, one app split by JWT role.

- `/login` — email + password only; no signup, no Google (staff are provisioned).
- `/doctor` — queue, filters, urgency chips, red-flag markers, waiting time.
- `/doctor/visits/[id]` — the preliminary report with sources and confidence, patient
  history inline, urgency override, notes, claim/start/done/refer.
- `/doctor/messages`, `/doctor/conversations/[id]` — care-team chat; a patient's intake
  transcript is readable but not postable.
- `/admin` — six stat tiles plus department load, specialty mix, daily volume, status
  and urgency breakdowns.
- `/admin/visits`, `/admin/doctors`, `/admin/audit`.

No component library, no chart library — bars are `div`s. One stylesheet.

### Patient app — `app/`
Flutter 3.44, Android/iOS/web. **14 Dart files**, 5 dependencies, no state-management
package, no model codegen.

- Gate: booting → sign in → app-lock PIN → profile setup → home shell.
- Login/register, Google button that hides itself when the server has no client IDs.
- Profile setup reused as the edit screen — photo, DOB (age derived), gender, blood
  type, phone, address, optional location, insurance, preferred hospitals, multi-input
  conditions and emergency contacts, document uploads, app PIN, mock Aadhaar.
- Assistant chat: language selector (12 languages), MCQ chips, report card, hospital
  cards, live token status bar, real image upload, mock voice button.
- Hospital chat: visually distinct — different icon, label, bubble colour.
- Profile view, bills and visit records.

Platform config done: Android `INTERNET` + location permissions, cleartext HTTP in the
**debug** manifest only; iOS usage strings and `NSAllowsLocalNetworking`.

### AI seam — not implemented, only exposed
`backend/src/lib/ai.js` is the only file that talks to a triage service.

- `AI_SERVICE_URL` unset → a labelled stub answers (`confidence: 0`,
  `stub://no-model-connected` source, banner on the doctor's page), so the whole stack
  is demoable with no model.
- Set → the backend POSTs the full transcript, patient profile, known conditions,
  referenced attachments, and a distance-sorted hospital list to `{URL}/triage`.
- Three modes: synchronous, async callback (`POST /ai/triage-callback`), worker pull
  (`GET /ai/pending`). Callbacks are idempotent.
- Results become chat messages (reply, MCQs, report, hospital suggestions), a `visits`
  queue row, and an audit entry — in one transaction.

Nothing here computes a specialty, an urgency score, or a red flag.

### Docs — `docs/` → wiki
Home, Setup, Architecture, Data Model, API Reference, AI Integration Contract,
Patient App, Staff Web Console, Feature Coverage, Security and Compliance, plus sidebar
and footer.

---

## Verified

| Check | Result |
|---|---|
| `cd backend && npm test` | 8 pass — urgency clamping, red-flag strictness, wrong-type rejection, garbage input, distance, derived age, validators |
| `cd app && flutter analyze` | No issues found |
| `cd app && flutter test` | 5 pass |
| `cd app && flutter build web` | Compiles |
| `cd web && npm run build` | Typechecks, 11 routes |
| `bash scripts/smoke.sh` | **78/78 pass** |

The smoke script walks register → profile → document upload → triage chat → MCQ answers
→ report → queue token → doctor queue → urgency override → care-team chat → admin
analytics → audit trail, and asserts the access-control boundaries: patients blocked
from staff routes, doctors unable to post in a patient's assistant thread,
cross-hospital isolation, and the AI shared secret.

## Not verified

Flutter on-device widget wiring — the chat polling loop, MCQ submission, a real file
picker, Google sign-in, geolocation. The code compiles, analyzer and tests are clean,
and every endpoint underneath is covered by the smoke script, but the widgets have been
read rather than driven. Manual walkthrough at the end of the Patient App wiki page.

Google sign-in has never run against a real Google project — it needs
`GOOGLE_CLIENT_IDS`, `GOOGLE_SERVER_CLIENT_ID`, and the platform config files.

---

## Deliberately not built

| Item | Why |
|---|---|
| The AI/RAG layer | Another team's. The seam is ready; `RAG/main.py` is still empty. |
| Billing and insurance claims | Phase 2 in `Design_doc.md` §6. `/me/bills` returns `billing_enabled: false` and the visit ledger. |
| Real Aadhaar / ABHA | `App_Feature_Set.md` specifies UI-only. `/me/aadhaar/verify` stores four digits and returns `{mock: true}`. |
| Relative notification | No SMS provider wired. `notify` is stored and shown to the doctor, nothing sends. |
| Speech-to-text | Mic button is a mock, as specified. The attachment endpoint already accepts `audio/*`. |
| Appointment slots, SMS/IVR, proxy accounts, pharmacy, teleconsultation | Phase 2–3. |
| Redis, object storage, Kubernetes | Overridden — Postgres only, Docker Compose. |

## Security fixes applied after review

A security review of the merged branch confirmed four issues; all four are fixed.

| Issue | Fix |
|---|---|
| `GET /admin/audit` had no hospital filter — any hospital's admin could read every other hospital's trail: patient names, triage answers, urgency, staff emails | `audit_log` gained `hospital_id`; the route scopes on it. Events belonging to no hospital (patient register/login/profile) are null and never listed. `chat.mcq_answered` no longer copies raw symptom answers into the audit detail. |
| `AI_CALLBACK_SECRET` defaulted to a published literal with no production guard, unlike `JWT_SECRET`. That header is the only gate on `/ai/*`, which reads pending triage payloads and writes into a patient's chat | Same fail-fast guard as `JWT_SECRET`. Default removed from compose and `.env.example`; empty now rejects every `/ai/*` call. |
| `JWT_SECRET`'s guard fired only under `NODE_ENV=production`, which the Dockerfile sets but `npm run dev`/`npm start` do not — a host-run instance signed sessions with a repo constant | Guard is unconditional and there is no fallback. Missing or default secret refuses to start on every run path. |
| `docker compose up` unconditionally seeded staff accounts sharing one well-known password | `SEED_DEMO_DATA=false` skips the demo data. Still on by default so the demo works out of the box. |

Changing the schema means `docker compose down -v`.

## Known shortcuts

Marked with `ponytail:` comments in the source — 4 of them.

| Shortcut | Where | Fix when |
|---|---|---|
| Token numbers via `max()+1` | `backend/src/lib/triage.js` | Two intake points register simultaneously |
| `bytea` for all binaries | `db/01-schema.sql` | Files get large (DICOM) |
| Polling instead of push | `backend/src/routes/chat.js` | Battery or DB load shows it |
| Gallery-only attachments | `app/lib/pick_file.dart` | Someone needs in-app camera capture |

Plus: **no migration tool.** `db/*.sql` runs only on an empty data directory; changing
the schema means `docker compose down -v`. Fix this before there is data worth keeping.

---

## Open — needs a team decision

Four places where the repository's own documents disagree. Full detail in the Feature
Coverage wiki page and the PR body.

1. **Urgency scale.** `Symptom Urgency_Score.txt` uses 0–100 (higher = more urgent);
   `Design_doc.md` §5 cites ESI, which is 1–5 (1 = most urgent). **Built 1–5**, with a
   `CHECK` constraint. Out-of-range values are clamped, so a 0–100 score would collapse
   `100`, `50`, and `10` all to `5`. Settle before the triage service is written; about
   an hour to change either way.
2. **Approval before registration.** `Symptom Urgency_Score.txt` sketches
   `AI report → admin verifies → user verifies → registration`. **Built: immediate
   registration**, doctor reviews and overrides after. The approval flow needs a
   `pending_approval` status, an admin review queue, a report-editing screen, and a
   patient confirmation step — and it removes the walk-in-get-a-token property.
3. **"Everything is stored locally."** The README states it as a principle;
   `App_Feature_Set.md` says details stay on-device until the user searches hospitals.
   **Built: server-side from profile save** — otherwise the doctor's dashboard is empty
   until the patient arrives and an unconscious patient can never trigger the upload.
   Reversible, but wording and behaviour currently disagree, and there is no consent
   flow either way.
4. **AYUSH scope.** `Problem_Statement.md` (SIH 26047, Ministry of AYUSH) asks for
   Dashavidha Pariksha history mode, a full structured clinical history, document OCR
   with a chronological timeline, ABDM/FHIR push, and a kiosk form factor. Neither
   design document covers those. The additive ones are cheapest to fold into the AI
   contract now, before the model is written.

---

## Before this touches a real patient

Full list in the Security and Compliance wiki page. The non-negotiable ones:

- TLS everywhere; remove the debug cleartext and `NSAllowsLocalNetworking`.
- Real `JWT_SECRET`, `AI_CALLBACK_SECRET`, `POSTGRES_PASSWORD` from a secret store.
- Postgres not publicly reachable; encryption at rest.
- Rate limiting on auth and upload routes — there is none.
- Consent capture, purpose statement, withdrawal, retention (DPDP Act, 2023).
- A migration tool.
- The mock Aadhaar flow either removed or unmistakably labelled in the shipped UI.
- Notifications either implemented or the promise removed from the UI copy.

---

## Next

1. Merge or review PR #1.
2. Answer the four open questions above — question 1 blocks the AI team.
3. Add a migration tool before anyone stores data they mind losing.
4. Walk the app through once on a device.
5. Hand the AI team the AI Integration Contract wiki page.
