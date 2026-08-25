# API Reference

Base URL in development: `http://localhost:4000`.

Auth: `Authorization: Bearer <jwt>` from `/auth/login`, `/auth/register`, or
`/auth/google`. Tokens last 30 days (`JWT_TTL`). Bodies are JSON except the three
upload endpoints, which are `multipart/form-data`.

Errors are always `{ "error": "message", "details": … }`. Status codes:
`400` validation, `401` missing/expired token, `403` wrong role or wrong hospital,
`404` not found (also returned instead of 403 where existence itself is private),
`409` uniqueness conflict, `413` file too large, `500` server.

**Role column:** `—` public · `P` patient · `D` doctor · `A` hospital admin ·
`S` the AI service (`x-ai-secret` header, not a JWT).

---

## Health

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/health` | — | `{ok, db}`. 503 if Postgres is unreachable. |
| GET | `/ai/health` | — | `{triage_backend: "stub"\|"http", callback_enabled}`. |

## Auth — `/auth`

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/auth/config` | — | `{google_enabled}`. Lets a client hide the Google button. |
| POST | `/auth/register` | — | `{email, password, full_name}`. Creates a **patient** and their profile row. Password ≥ 8 chars. → `{token, user}` |
| POST | `/auth/login` | — | `{email, password}`. Same 401 message whether the email exists or the password is wrong. |
| POST | `/auth/google` | — | `{id_token}`. Verified server-side against `GOOGLE_CLIENT_IDS`. Unknown account → new patient (`201`); email matches an existing account → linked (`200`). |
| GET | `/auth/me` | P D A | Everything the client needs to pick a first screen: `user`, plus `patient`, `doctor`, or `admin` context. Never returns the PIN hash — `app_lock_set` instead. |
| POST | `/auth/app-lock` | P | `{pin}` 4–12 digits, bcrypt-hashed. |
| POST | `/auth/app-lock/verify` | P | `{pin}` → `{ok: bool}`. |

## Patient — `/me`

All scoped to the caller. A wrong id is a `404`, never someone else's row.

| Method | Path | Notes |
|---|---|---|
| GET | `/me/profile` | Profile + `age` (derived) + conditions + relatives + preferred hospitals. |
| PUT | `/me/profile` | Partial: absent keys are left alone. `dob`, `gender`, `blood_type`, `phone`, `address`, `lat`, `lng`, `insurance_provider`, `policy_number`, `language`, `profile_complete`, `full_name`. Returns the whole profile. |
| POST | `/me/profile/photo` | `multipart`: `file`. |
| GET/POST | `/me/conditions` | `{kind: disease\|allergy\|genetic, label, notes?}`. |
| DELETE | `/me/conditions/:id` | `204`. |
| GET/POST | `/me/relatives` | `{name, contact, relation, notify?}`. |
| DELETE | `/me/relatives/:id` | `204`. |
| PUT | `/me/preferred-hospitals` | `{hospital_ids: [uuid]}` — replaces the whole set. |
| GET | `/me/documents` | Medical history with `file_id`, `mime`, `size_bytes`. |
| POST | `/me/documents` | `multipart`: `file`, `label` (required), `description`. |
| DELETE | `/me/documents/:id` | `204`. Deletes the underlying file too. |
| POST | `/me/aadhaar/verify` | `{aadhaar_number}` 12 digits. **Mock** — nothing is verified; stores the last four and returns `{mock: true}`. |
| GET | `/me/visits` | The patient's own tokens with status, department, doctor, and the triage summary. |
| GET | `/me/bills` | `{bills: [], billing_enabled: false, visits, uploaded_bills}`. Billing is Phase 2; this returns the visit ledger and any file the patient labelled bill/invoice/receipt. |

## Hospitals — `/hospitals`

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/hospitals?lat=&lng=` | P D A | Each hospital with its `specialties[]` and today's `queue_length`. With coordinates, adds `distance_km` and sorts nearest first. |
| GET | `/hospitals/:id` | P D A | Plus departments and each one's available doctor count. |

## Chat — `/conversations`

Both surfaces, one set of endpoints. `kind` is `ai` (triage assistant) or `care_team`
(hospital staff).

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/conversations` | P D A | Patients: their threads. Staff: `care_team` threads at their hospital. |
| POST | `/conversations` | P | `{kind, hospital_id?, title?, force_new?}`. `kind:"ai"` reuses the existing thread unless `force_new`. `care_team` requires `hospital_id`. A new `ai` thread gets a greeting. |
| GET | `/conversations/:id` | P D A | Metadata plus `can_post`. |
| GET | `/conversations/:id/messages?after=&limit=` | P D A | `{messages, triage_pending}`. `after` is an ISO timestamp — pass the newest you hold to poll incrementally. Attachments come back as `file_url`. |
| POST | `/conversations/:id/messages` | P D | `{body, language?}`. On an `ai` thread from a patient this starts a triage round and returns `{message, triage_pending: true}` immediately. `language` also updates the patient's stored preference. |
| POST | `/conversations/:id/attachments` | P D | `multipart`: `file`, `body?`. Images and PDFs; `audio/*` is accepted so wiring speech-to-text later needs no client change. |
| POST | `/conversations/:id/mcq-answer` | P | `{message_id, answers: {question_id: value}}`. Stored as one `mcq_answer` message and starts the next triage round. |

Access rules: a patient sees only their own threads. Staff see `care_team` threads at
their own hospital, and can **read but not post in** a patient's assistant thread — and
only while that patient has a visit at their hospital.

## Files — `/files`

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/files/:id` | P D A S | Streams the bytes with the stored mime. Allowed for the owner; for staff only if the owner has a visit at their hospital; for the AI service with `x-ai-secret`. Needs the header, so a bare `<img src>` will 401 — see `AuthFile` / `AuthedImage` in the clients. |

## Doctor — `/doctor`

| Method | Path | Notes |
|---|---|---|
| GET | `/doctor/queue?scope=&status=&date=` | `scope`: `mine` (default) \| `department` \| `hospital`. Ordered `in_consult` first, then urgency ascending, then oldest. Each row carries the patient's age/gender, the suggested specialty, `red_flag`, and the chief complaint. |
| GET | `/doctor/visits/:id` | Everything before the consult: visit, full patient profile, conditions, relatives, documents, the triage result with its sources, and `ai_conversation_id` for the transcript. |
| PATCH | `/doctor/visits/:id` | `{status?, urgency?, doctor_notes?, claim?}`. Changing urgency sets `urgency_overridden`. Every call writes an `audit_log` entry recording both the AI's value and the doctor's. |
| POST | `/doctor/patients/:id/conversation` | Opens or reuses the `care_team` thread with that patient. `404` unless they have a visit at this hospital. |

## Hospital admin — `/admin`

All scoped to the admin's own hospital.

| Method | Path | Notes |
|---|---|---|
| GET | `/admin/overview?days=` | Totals (today, in queue, urgency-1 today, all time), staff on duty, average minutes to close, and breakdowns by status, urgency, department, routed specialty, and day. |
| GET | `/admin/visits?status=&limit=` | Full visit list, newest day first. |
| GET/POST | `/admin/departments` | `{name, specialty}`. The specialty key is slugified and must be unique per hospital. |
| GET | `/admin/doctors` | Staff with department, duty flag, and today's queue count. |
| POST | `/admin/doctors` | `{email, full_name, password, department_id?, specialty?, reg_no?}`. **The only way a doctor account is created** — staff never self-register. |
| PATCH | `/admin/doctors/:id` | `{department_id?, is_available?, is_active?}`. |
| GET | `/admin/audit?limit=` | Recent audit entries with actor and detail. |

## AI seam — `/ai`

Authenticated with `x-ai-secret` (compared with `timingSafeEqual`), not a JWT.
Full contract: [AI Integration Contract](AI-Integration-Contract).

| Method | Path | Notes |
|---|---|---|
| POST | `/ai/triage-callback` | `{request_id, …result}` or `{request_id, error}`. Idempotent — replaying a done request is a no-op. |
| GET | `/ai/pending?limit=` | Queued triage requests, for a worker that polls instead of receiving. |
| GET | `/ai/requests/:id` | The stored request and whether a result exists. |

---

## Worked example

```bash
API=http://localhost:4000
J='content-type: application/json'

TOKEN=$(curl -s -XPOST $API/auth/login -H "$J" \
  -d '{"email":"patient@demo.test","password":"password123"}' | jq -r .token)
A="authorization: Bearer $TOKEN"

CONV=$(curl -s -XPOST $API/conversations -H "$A" -H "$J" -d '{"kind":"ai"}' | jq -r .id)

curl -s -XPOST "$API/conversations/$CONV/messages" -H "$A" -H "$J" \
  -d '{"body":"stomach pain since morning, feeling dizzy","language":"hi"}'

sleep 1
curl -s "$API/conversations/$CONV/messages" -H "$A" | jq '.messages[] | {kind, body}'
```

`scripts/smoke.sh` is the same flow with 73 assertions, including the access-control
boundaries. Run it after touching any route.
