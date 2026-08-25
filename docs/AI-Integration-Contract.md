# AI Integration Contract

This is the seam between the platform in this repository and the triage/RAG layer
owned by the AI team. **Nothing in this repository decides a specialty, an urgency
score, or whether a case is an emergency.** The backend builds a request, hands it
over, stores whatever comes back, and shows it to the patient and the doctor.

Files that implement this contract:

| File | Role |
|---|---|
| `backend/src/lib/ai.js` | Outbound call, response shape-checking, the offline stub |
| `backend/src/lib/triage.js` | Builds the request, persists results, fans them into chat + queue |
| `backend/src/routes/ai.js` | Inbound endpoints: callback, pending queue, request lookup |

---

## Configuration

| Variable | Effect |
|---|---|
| `AI_SERVICE_URL` | Unset → the local stub answers, so the app is fully demoable with no AI service. Set → the backend `POST`s to `{AI_SERVICE_URL}/triage`. |
| `AI_SERVICE_TOKEN` | Sent as `Authorization: Bearer …` on the outbound call. Optional. |
| `AI_TIMEOUT_MS` | Outbound request timeout, default `20000`. |
| `AI_CALLBACK_SECRET` | Shared secret the AI service must send as `x-ai-secret` on every inbound call. |
| `PUBLIC_API_URL` | Used to build the `callback_url` the AI service is told to answer on. |

Check which mode a running backend is in:

```
GET /ai/health  ->  { "triage_backend": "stub" | "http", "callback_enabled": true }
```

---

## Three ways to plug in

All three carry the same JSON body. Pick whichever suits the service.

**1. Synchronous.** The backend `POST`s `/triage` and uses the `200` response body
directly. Simplest; the patient sees the answer on the next poll (~3 s).

**2. Asynchronous.** Answer the same `POST` with `202` and no body, then call
`POST /ai/triage-callback` when the work is done. Use this when triage takes longer
than the HTTP timeout.

**3. Pull.** Ignore the outbound call entirely and poll `GET /ai/pending` for queued
work, then finish each one with `POST /ai/triage-callback`. Useful for a worker that
cannot accept inbound connections.

---

## Request the backend sends

`POST {AI_SERVICE_URL}/triage`

```json
{
  "request_id": "d290f1ee-6c54-4b01-90e6-d701748f0851",
  "callback_url": "http://api.internal:4000/ai/triage-callback",
  "language": "hi",
  "patient": {
    "id": "9a7e0001-0000-0000-0000-000000000001",
    "age": 31,
    "gender": "female",
    "blood_type": "O+",
    "known_conditions": [
      { "kind": "disease", "label": "Type 2 diabetes", "notes": "on metformin" },
      { "kind": "allergy", "label": "Penicillin", "notes": "rash" }
    ],
    "location": { "lat": 20.296, "lng": 85.818 }
  },
  "conversation": {
    "id": "0c8f…",
    "messages": [
      {
        "role": "patient",
        "kind": "text",
        "body": "my stomach hurts since morning and I feel dizzy",
        "payload": null,
        "file_id": null,
        "created_at": "2026-08-25T09:14:02.114Z"
      },
      {
        "role": "ai",
        "kind": "mcq",
        "body": "A few quick questions",
        "payload": { "questions": [ … ] },
        "file_id": null,
        "created_at": "2026-08-25T09:14:05.902Z"
      }
    ]
  },
  "attachments": [
    { "file_id": "6f1b…", "kind": "image", "url": "/files/6f1b…" }
  ],
  "hospitals": [
    {
      "id": "1111…",
      "name": "City General Hospital",
      "specialties": ["general_medicine", "cardiology", "emergency"],
      "lat": 20.2961,
      "lng": 85.8245,
      "distance_km": 0.6
    }
  ]
}
```

Notes:

- `conversation.messages` is the **full transcript in order**, including the
  assistant's own earlier turns and the patient's MCQ answers (`kind: "mcq_answer"`,
  with the chosen options in `payload.answers`). It is the whole context; there is no
  separate "history" field.
- `role` is one of `patient`, `ai`, `doctor`, `system`.
- `attachments` are **referenced, not inlined.** Fetch the bytes from
  `GET {PUBLIC_API_URL}/files/{file_id}` with the `x-ai-secret` header. That endpoint
  streams the original image or PDF.
- `hospitals` is pre-sorted by distance from the patient and already carries each
  facility's specialty keys, so a recommendation can name real `hospital_id`s.
- `age` is derived from date of birth at request time; the raw DOB is not sent.

---

## Response the backend expects

Either as the `200` body of `/triage`, or as the body of
`POST /ai/triage-callback` (with header `x-ai-secret`). In the callback case
`request_id` is required — that is how the answer is matched to its request.

```json
{
  "request_id": "d290f1ee-6c54-4b01-90e6-d701748f0851",
  "status": "ok",
  "reply": "Here is a preliminary summary of what you told me.",
  "chief_complaint": "Abdominal pain with dizziness since this morning",
  "symptoms": [
    { "name": "abdominal pain", "duration": "8 hours", "severity": "moderate" },
    { "name": "dizziness", "duration": "8 hours", "severity": "mild" }
  ],
  "specialty": "general_medicine",
  "urgency": 3,
  "red_flag": false,
  "summary": "Plain-language paragraph shown to the patient.",
  "clinical_note": "Clinical shorthand shown to the doctor.",
  "confidence": 0.82,
  "sources": [
    { "title": "ICD-10 R10.9 — unspecified abdominal pain", "ref": "kb://icd10/R10.9" }
  ],
  "follow_up_questions": [
    {
      "id": "duration",
      "question": "How long have you had this problem?",
      "options": ["Less than a day", "1-3 days", "About a week", "Longer"],
      "multi": false
    }
  ],
  "suggested_hospitals": [
    {
      "hospital_id": "1111…",
      "name": "City General Hospital",
      "distance_km": 0.6,
      "reason": "Has a general medicine OPD with capacity today."
    }
  ]
}
```

### Field reference

| Field | Type | Meaning |
|---|---|---|
| `request_id` | uuid | Required on the callback path; echoed on the sync path. |
| `status` | `ok` \| `needs_more_info` \| `emergency` | Anything else is coerced to `ok`. |
| `reply` | string | Shown as the assistant's chat bubble. Omit for a silent turn. |
| `chief_complaint` | string | Headline on the doctor's dashboard. |
| `symptoms` | array | Free-form objects; stored as JSON and listed on the doctor's screen. |
| `specialty` | string | **Routing key.** Must match a `departments.specialty` slug to auto-assign a department — see below. |
| `urgency` | int 1–5 | 1 = most urgent. Clamped into range; non-numeric becomes null. |
| `red_flag` | bool | **Only literal `true` counts.** Forces urgency 1, routes to `emergency`, and paints the patient and doctor screens red. |
| `summary` | string | Patient-facing, plain language. |
| `clinical_note` | string | Doctor-facing shorthand. Never shown to the patient. |
| `confidence` | float 0–1 | Displayed as a percentage next to the suggestion. |
| `sources` | array | Provenance. `{title, ref}` is what the dashboard renders. Design_doc §2 requires every routing decision be traceable — populate this. |
| `follow_up_questions` | array | Rendered as tappable MCQs in the app. `{id, question, options[], multi}`. Answering one starts a fresh triage round with the answers in the transcript. |
| `suggested_hospitals` | array | `{hospital_id, name, distance_km, reason}`. The **first entry with a `hospital_id` wins** the queue placement. |

Everything except `request_id` is optional. `normaliseTriage()` in
`backend/src/lib/ai.js` drops wrong-typed fields rather than rejecting the whole
response, so a missing nice-to-have never loses a triage.

### Open point: the urgency scale

The contract above says **1–5, 1 most urgent**, matching the ESI framework
`Design docs/Design_doc.md` §5 cites, and `triage_results.urgency` has a
`CHECK (urgency between 1 and 5)`.

`Design docs/Symptom Urgency_Score.txt` instead uses a **0–100 score where higher is more
urgent**. If that is the scale the triage layer will emit, say so before writing it —
values outside 1–5 are currently clamped, so `100` would silently arrive as `5` and `10`
as `5` too, losing the whole distinction. See
[Feature Coverage](Feature-Coverage) for what changing it costs.

### Reporting a failure

```json
POST /ai/triage-callback
{ "request_id": "d290f1ee-…", "error": "model timeout after 30s" }
```

The request is marked `failed` and the patient sees a "the assistant is unavailable"
message in the chat rather than silence.

---

## What the backend does with the response

In one transaction (`applyTriageResult` in `backend/src/lib/triage.js`):

1. Inserts a `triage_results` row, keeping the untouched response in `raw` for audit.
2. Marks the `triage_requests` row `done`.
3. Emits chat messages: a `text` bubble for `reply`, one `mcq` message holding all
   `follow_up_questions`, a `report` message, a `hospital_suggestion` message.
4. If `specialty` or `red_flag` is present, creates a `visits` row — the queue token.
   Hospital preference: first suggested hospital → the patient's preferred hospital →
   the nearest one. Department by specialty, falling back to `general_medicine`.
   Doctor = first available doctor in that department.
5. Emits a `status` message with the token number, department, and doctor, which the
   app shows as its status bar.
6. Writes an `audit_log` entry with the specialty, urgency, red flag, and visit id.

Idempotency: replaying the same `request_id` is a no-op, so at-least-once delivery
from the AI side is safe.

---

## Specialty keys

`specialty` is matched against `departments.specialty`, a lowercase underscore slug.
Seeded values:

```
general_medicine   cardiology   orthopaedics   dermatology
emergency          paediatrics
```

A hospital admin adds more at **Staff & departments → Add a department**; the display
name is free text and the key is slugified (`ENT / Otolaryngology` →
`ent_otolaryngology`). An unknown specialty still creates a visit — it falls back to
`general_medicine`, or lands unassigned if that department does not exist either.
`GET /hospitals` returns every hospital's live specialty list, and each triage request
carries it, so the AI side never has to guess the vocabulary.

---

## The stub

With `AI_SERVICE_URL` unset, `stubTriage()` returns fixed placeholder text. It reads
the message count *only* to alternate between the "asks MCQs" and "returns a report"
screens so both UIs can be demoed. It contains no clinical logic and none should be
added — that is the whole point of this boundary.

Stub responses are labelled: `confidence: 0`, `sources: [{ref: "stub://no-model-connected"}]`,
and the reply text says so. The doctor's dashboard detects those markers and shows a
banner saying the values are samples.

---

## Testing against a real service

```bash
# terminal 1 — your service on :9000, exposing POST /triage
# terminal 2
docker compose up -d db
cd backend
AI_SERVICE_URL=http://localhost:9000 \
AI_CALLBACK_SECRET=dev-callback-secret \
PUBLIC_API_URL=http://localhost:4000 \
npm run dev
```

Then drive a conversation from the app, or straight over HTTP:

```bash
TOKEN=$(curl -s -XPOST localhost:4000/auth/login -H 'content-type: application/json' \
  -d '{"email":"patient@demo.test","password":"password123"}' | jq -r .token)

CONV=$(curl -s -XPOST localhost:4000/conversations -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"kind":"ai"}' | jq -r .id)

curl -s -XPOST "localhost:4000/conversations/$CONV/messages" \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"body":"chest pain and breathlessness"}'

# what your service was actually sent
curl -s "localhost:4000/ai/pending" -H 'x-ai-secret: dev-callback-secret' | jq
```

`bash scripts/smoke.sh` walks the whole journey and asserts the results, including the
seam. Run it after any change to this contract.
