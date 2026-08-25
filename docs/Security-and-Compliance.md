# Security and Compliance

This is a demo-stage system holding real-shaped health data. This page states plainly
what protects it today, what is a mock, and what has to be built before it touches a
real patient.

`Design docs/Design_doc.md` §6 lists the obligations. This page tracks them against the code.

---

## What is enforced today

### Authentication
- bcrypt (cost 10) for passwords and for the app-lock PIN. The PIN hash never leaves the
  server — the API returns a boolean `app_lock_set`.
- JWT, HS256, 30-day expiry, `sub` + `role` + `email`. Verified on every request, and the
  user row is re-read each time so a disabled account (`is_active = false`) stops working
  immediately rather than at token expiry.
- Google sign-in: the client only ever obtains an ID token; the backend verifies it
  server-side against the `GOOGLE_CLIENT_IDS` audience allowlist and requires
  `email_verified`. Nothing Google-issued is trusted past that point — the backend mints
  its own JWT.
- Login returns the same 401 whether the email is unknown or the password is wrong.
- The server refuses to start unless `JWT_SECRET` is set to a real value. There is no
  fallback and no `NODE_ENV` condition: the guard used to fire only under
  `NODE_ENV=production`, which the Dockerfile sets but `npm run dev` and `npm start` do
  not, so a host-run instance silently signed sessions with a constant from this repo.
- `AI_CALLBACK_SECRET` has the same guard against its former shipped default. Left empty
  it fails closed — every `/ai/*` call is rejected.

### Authorisation
Three rules, asserted by `scripts/smoke.sh`:

1. **Patients see only their own rows.** Every `/me/*` query is keyed on the caller;
   deletes use `where id = $1 and patient_id = $2`, so a wrong id is a 404 rather than
   someone else's record.
2. **Staff are scoped to one hospital.** `staffHospitalId()` resolves the caller's
   hospital and every staff query filters on it. Cross-hospital reads fail.
3. **Staff reach a patient only through a visit.** Reading a patient's file or their
   intake transcript requires a `visits` row linking that patient to the staff member's
   hospital. Doctors can read an assistant thread but `can_post` is false — they cannot
   inject messages into the patient's conversation with the assistant.

Roles cannot cross: a patient token is rejected by `/doctor/*` and `/admin/*` (403), and
an admin token is rejected by `/doctor/*`.

### Input handling
- All SQL is parameterised. No string interpolation into queries anywhere.
- Every request field goes through the validators in `backend/src/lib/http.js`, whose
  enum lists mirror the SQL `CHECK` constraints, so bad input is a 400 rather than a
  constraint violation.
- Uploads: 10 MB cap, mime allowlist (jpeg, png, webp, heic, pdf), memory storage. Mime
  and size are recorded from the validated upload, not from client claims.
- Postgres constraint violations map to 4xx, not 500 — a unique clash is a 409.
- CORS is an explicit origin allowlist. Native clients (no `Origin` header) are allowed;
  an unlisted browser origin gets 403.

### Service authentication
The AI service uses a shared secret in `x-ai-secret`, compared with
`crypto.timingSafeEqual`, not a user JWT. It is a service, not a person. That secret also
gates its access to `GET /files/:id` for referenced attachments.

### Audit trail
`audit_log` is append-only and records logins, registrations, profile edits, the mock
Aadhaar action, MCQ answers, every triage result (specialty, urgency, red flag, visit),
triage failures, every visit change, and staff provisioning.

`visit.updated` stores **both** the AI's urgency and the doctor's, so a disagreement is
visible without diffing history. That is the human-in-the-loop record `Design docs/Design_doc.md` §6
requires, and the raw material for the doctor-feedback loop in §3.

Audit writes never fail the request they describe.

---

## Mocks — do not mistake these for features

| Thing | Reality |
|---|---|
| **Aadhaar verification** | `POST /me/aadhaar/verify` checks that 12 digits were entered, stores the last four, sets `aadhaar_verified = true`, and returns `{mock: true}`. **No UIDAI contact, nothing verified.** `Design docs/App_Feature_Set.md` specifies "UI only". The dialog says so to the user. Do not let `aadhaar_verified` gate anything that matters, and do not wire real Aadhaar without the KYC and consent work — it is regulated. |
| **Triage output, with no AI service** | The stub returns fixed text with `confidence: 0` and a `stub://no-model-connected` source. The doctor's page detects those markers and shows a banner. Keep both markers if you touch the stub. |
| **Relative notification** | `patient_relatives.notify` is stored and shown to the doctor. Nothing sends an SMS. The app implies otherwise — the widest gap between promise and behaviour. |
| **Voice input** | A snackbar. |
| **Billing** | `GET /me/bills` returns `billing_enabled: false` and the visit ledger. The screen says billing is not connected. |

---

## Not built yet — required before real patients

### 1. Consent capture (DPDP Act, 2023)
Health data is sensitive personal data. There is **no consent flow, no purpose
statement, no withdrawal path, and no retention policy** in the code today.

`Design docs/App_Feature_Set.md` intended profile details to stay on the device until the patient searched
for hospitals. This build uploads them on save (reasons in
[Feature Coverage](Feature-Coverage)), which makes consent load-bearing rather than
optional. Needed: purpose-specific consent at collection, a visible record of what was
shared with which hospital and when, withdrawal, and deletion that actually deletes.

The cascade behaviour is at least right: deleting a `users` row removes the patient row,
files, conditions, relatives, documents, conversations, and visits.

### 2. Transport security
Everything above assumes HTTPS. Development is plain HTTP:
- Android cleartext is enabled in the **debug** manifest only, so release builds keep the
  platform block.
- iOS has `NSAllowsLocalNetworking` for the dev API — remove it before shipping.
- Serve the API and console behind TLS. JWTs in `localStorage` are readable by any script
  on the page; over plain HTTP they are readable by the network.

### 3. Rate limiting and brute-force protection
None. `/auth/login`, `/auth/register`, and the upload endpoints are unthrottled. Add a
limiter and login backoff.

### 4. Secret management
Secrets come from environment variables with working defaults, which is convenient and
dangerous. `JWT_SECRET`, `AI_CALLBACK_SECRET`, and `POSTGRES_PASSWORD` must all be real
values from a secret store in any shared deployment. Rotating `JWT_SECRET` invalidates
every session, which is the correct behaviour but needs planning.

### 5. Data at rest
`bytea` blobs and every field are stored unencrypted. Postgres is reachable on host port
5433 with a default password in development. Needs disk encryption, a real password, and
no public port.

### 6. CDSCO / clinical decision support
The tool influences clinical decisions, so it likely falls under evolving guidance on
AI-based clinical decision support. Two architectural facts help:
- The AI's output is a **suggestion with a visible rationale**: `sources` and
  `confidence` are shown to the doctor, and a stub-sourced report is labelled.
- The doctor always confirms or overrides, and the override is recorded with the original
  value.

Keep both properties. A change that lets a triage result act without a doctor seeing it,
or that drops `sources`, changes the system's regulatory character.

### 7. Accessibility
`Design docs/Design_doc.md` §6 requires a voice-first path for elderly, low-literacy, and
differently-abled users. The placeholder UI is typing-and-reading. Since it is being
redesigned anyway, this is the moment to build it in rather than retrofit.

### 8. Bias testing across languages
The language selector offers 12 languages; whether triage quality holds across them
belongs to the AI layer's evaluation. A system that works in English and Hindi and
degrades elsewhere recreates the inequity it exists to fix.

---

## Checklist before any real deployment

- [ ] TLS everywhere; remove the debug cleartext and `NSAllowsLocalNetworking`
- [ ] Real `JWT_SECRET`, `AI_CALLBACK_SECRET`, `POSTGRES_PASSWORD` from a secret store
- [ ] `SEED_DEMO_DATA=false` — the demo staff accounts share one well-known password
- [ ] Postgres not publicly reachable; disk encryption on
- [ ] Rate limiting on auth and upload routes
- [ ] Consent capture, purpose statement, withdrawal, retention policy
- [ ] A migration tool, so a fix does not mean dropping the volume
- [ ] Backup and restore rehearsed — the database is the entire system state
- [ ] Audit log shipped somewhere append-only and retained
- [ ] The mock Aadhaar flow either removed or unmistakably labelled in the shipped UI
- [ ] Notifications either implemented or the promise removed from the UI copy
- [ ] Penetration test of the three access-control rules above
