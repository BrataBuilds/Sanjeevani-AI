# Feature Coverage

What is built, what is stubbed, what was deliberately left out — measured against
`Design docs/App_Feature_Set.md` (the patient app MVP) and `Design docs/Design_doc.md` §3 (the platform).

Legend: **Done** · **Mock** (present in the UI, no real integration behind it) ·
**Seam** (the interface exists, another team supplies the substance) · **Deferred**.

---

## `Design docs/App_Feature_Set.md` §1.2 — patient app MVP

### First-time boot

| Item | State | Notes |
|---|---|---|
| Username/password login (app lock) | **Done** | Email + password; the app lock is a separate bcrypt-hashed PIN gate on reopen. |
| JWT auth | **Done** | 30-day tokens, `Bearer` on every call. |
| Aadhaar login verification (UI only) | **Mock** | As specified. `POST /me/aadhaar/verify` checks 12 digits, stores the last four, flips a flag, returns `{mock: true}`. Nothing reaches UIDAI. |
| Profile page, details stored locally until the user searches for hospitals | **Changed** | Details are stored server-side from the start. See the note below. |
| Google OAuth | **Done** | Added on top of `Design docs/App_Feature_Set.md`. Off unless `GOOGLE_CLIENT_IDS` is configured. |

> **Deviation worth flagging.** `Design docs/App_Feature_Set.md` says profile details stay on the device
> until the user searches for hospitals. They are sent to the server as soon as the
> profile is saved instead. Reasons: the doctor's dashboard needs the history to be
> useful before the patient reaches the desk, a device-local record is lost with the
> device, and an unconscious patient cannot trigger the upload. The cost is that data
> collection happens earlier, which makes the consent flow in
> [Security and Compliance](Security-and-Compliance) load-bearing rather than optional.
> Straightforward to reverse if the privacy posture should win.

### Personal details

| Item | State |
|---|---|
| Profile picture, name, age, DOB, address, phone, email, gender, blood type | **Done** — age derived from DOB, never stored |
| Insurance provider, policy number | **Done** |
| Location data | **Done** — optional coarse location, only used to sort hospitals |
| Preferred hospitals | **Done** — multi-select; second choice when placing a token |
| Known diseases / allergies / genetic disorders (multi-input) | **Done** — typed `disease`/`allergy`/`genetic`, sent with every triage request |
| Relative/guardian/sibling/spouse: name, contact, relation (multi-input) | **Done** |
| …automatically informed if the ward is admitted | **Deferred** — stored and shown to the doctor, but nothing sends an SMS. No provider wired. |
| Medical history: images, scanned PDFs, document label | **Done** — into Postgres `bytea`, patient-supplied label plus notes |

### AI chat window

| Item | State |
|---|---|
| Normal text window | **Done** |
| Mock image button | **Done, and real** — actually uploads |
| Mock voice button | **Mock**, as specified. The endpoint already accepts `audio/*`. |
| Language selector at the top | **Done** — 12 languages, persisted, sent with each message |
| Chat history | **Done** — full transcript, incremental polling |
| MCQ questions asked by the LLM | **Done (Seam)** — UI complete; the questions come from the AI layer |
| UI for LLM-recommended hospitals | **Done (Seam)** — cards with distance and reason |
| Status bar for hospital updates | **Done** — token, department, doctor; red on a red flag |

### Hospital / doctor chat window

| Item | State |
|---|---|
| Same as the assistant, different backend | **Done** — one widget, `kind: 'care_team'` |
| Different icons for good UX | **Done** — different icon, label, and bubble colour |
| Doctors and hospitals have their own profile pictures | **Partial** — the schema has `doctors.photo_file_id` and the doctor's real name is shown; no upload UI yet, so the avatar is an icon |

### User profile page

| Item | State |
|---|---|
| Display the data collected at login | **Done** |
| View and edit | **Done** — one screen serves setup and edit |
| Button to view collected medical bills and info | **Done, honest** — shows the visit ledger and self-uploaded bills, and says billing is not connected |

---

## `Design docs/Design_doc.md` §3 — platform core

| Item | State | Notes |
|---|---|---|
| Conversational intake, text + voice, multilingual | **Partial / Seam** | Text done, language selection done, voice is a stub. Translation belongs to the AI layer. |
| AI preliminary report: complaint, symptoms, specialty, urgency | **Seam** | Stored, rendered for patient and doctor, audited. |
| Deterministic red-flag detection independent of the AI | **Seam** | The platform honours `red_flag: true` — urgency 1, `emergency` routing, red banners both sides. The checklist itself is the AI team's, per §2. |
| Auto department/doctor assignment on specialty + availability | **Done** | Specialty → department → first available doctor, `general_medicine` fallback. |
| Nearest-alternative-hospital recommendation | **Done (Seam)** | Distance-sorted hospitals with live queue length go out with every request; suggestions come back and are rendered. Placement honours the first suggested hospital. |
| One-time profile, persistent patient id | **Done** | Repeat registration is a chat message. |
| Optional ABHA linkage | **Deferred** | Only the mock Aadhaar flow exists. |
| Appointment booking + walk-in registration | **Partial** | Walk-in registration and tokens are done. No calendar or slot booking. |
| Portable EHR across visits | **Done** | Profile, conditions, and documents follow the patient; the doctor sees them when a visit links them to that hospital. Cross-network sharing is out of scope. |
| Billing, payments, insurance claims | **Deferred** | Phase 2 in §6. Insurance provider and policy number are collected. |
| Doctor dashboard: report before the consult, queue, urgency override | **Done** | Plus notes, claim, and status transitions; every override audited. |
| Hospital admin dashboard: flow analytics, department load, bottlenecks | **Done** | Plus staff and department management and the audit trail. |
| Image input — visible symptom, or a report photo for OCR | **Partial / Seam** | Upload and storage done; attachments are referenced in the triage payload. OCR is the AI layer's. |
| Digital queue token with live status | **Done** | Token per hospital per day, live status in the app's status bar. |
| SMS/IVR fallback | **Deferred** | Phase 2. |
| Proxy / family accounts | **Deferred** | Phase 2. |
| Government scheme integration | **Deferred** | Phase 3. |
| Pharmacy, e-prescriptions, teleconsultation | **Deferred** | Phase 2–3. |
| Doctor feedback loop into KB curation | **Partial** | `audit_log` records every override with the AI's original value, which is the raw material. Nothing consumes it yet. |

---

## Not in this repository by design

The whole AI/RAG layer — entity extraction, the red-flag rule engine, the vector store,
report synthesis, STT, OCR, translation. Owned by another team, reached through a
documented interface: [AI Integration Contract](AI-Integration-Contract).

With no AI service connected the platform still runs end to end on a stub that returns
labelled placeholder text, so the app and both dashboards are fully demoable today.

---

## Open questions — these need a decision from the team

Four places where the repository's own documents disagree with each other or with what
was built. Each is cheap to change now and expensive later.

### 1. The urgency scale: 0–100 or 1–5?

`Design docs/Symptom Urgency_Score.txt` uses a **0–100 score where higher is more
urgent** (`Fever 98F mild = 10`, `Fever 105F = 100`). `Design docs/Design_doc.md` §5
says "urgency tier", and the ESI framework it cites is **1–5 where 1 is most urgent**.

**Built: 1–5, 1 most urgent.** It is the standard triage scale, it maps directly to five
queue colours, and ESI is what the design doc names. But if the AI team is scoring 0–100,
that is a real mismatch — `triage_results.urgency` has a `CHECK (urgency between 1 and 5)`
and both dashboards colour-code five bands.

Changing it touches: the `CHECK` constraint, `visits.urgency`, `clampUrgency()` in
`backend/src/lib/ai.js`, the colour classes in `web/app/globals.css`, `URGENCY_LABEL` in
`web/lib/api.ts`, and `_urgencyWords()` in `app/lib/screens/chat_screen.dart`. About an
hour. **Decide before the AI service is written**, or one side will be converting scores
forever.

### 2. Should registration wait for hospital-admin approval?

`Design docs/Symptom Urgency_Score.txt` sketches:

```
User gives query -> AI makes a report -> Hospital Admin verifies -> Makes changes
                 -> User verifies -> both accept -> Registration
```

**Built: registration is immediate.** A triage result with a specialty creates the
`visits` row and the patient gets a token straight away; the doctor reviews and can
override afterwards. That is what `Design docs/Design_doc.md` §3 describes
("auto department/doctor assignment", "queue token").

The two-sided-approval flow is a different product: it needs a `pending_approval` visit
status, an admin review queue, an edit-the-report screen, and a patient confirmation
step. Worth doing if a human must gate every registration — but it removes the "walk in
and get a token" property, so it should be a deliberate choice.

### 3. "Everything is stored locally" vs. server-side records

The repository README states as a design principle: *"no data is stored on external
servers/shared with third parties without consent. Everything is stored locally."*
`Design docs/App_Feature_Set.md` agrees — details stay on the device until the user
searches for hospitals.

**Built: server-side from the moment the profile is saved** (reasons in the deviation
note above). Whether that violates the stated principle depends on what "external" means:
a self-hosted hospital server is not a third party, but it is not the patient's device
either.

Either way, the principle cannot be honoured by intent alone — it needs the consent
capture described in [Security and Compliance](Security-and-Compliance). Pick one:
tighten the wording to "no third-party servers, consent-gated hospital sharing", or move
profile storage back onto the device and accept that the doctor's dashboard is empty
until the patient arrives.

### 4. The AYUSH problem statement is broader than what was built

`Design docs/Problem_Statement.md` is SIH **ID 26047, Ministry of AYUSH / All India
Institute of Ayurveda — "Patient Case-Taking Software"**. It asks for a kiosk-oriented
clinical **history-taking** platform. This build follows
`Design docs/App_Feature_Set.md` and `Design docs/Design_doc.md`, which describe a
triage-and-routing product. Those overlap, but the problem statement names four things
neither design document covers:

| Problem statement asks for | Status here |
|---|---|
| **AYUSH history mode** — Dashavidha Pariksha (Prakriti, Vikriti, Agni, Koshtha, Ahara-Vihara, Nidana, Samprapti) | **Not built, not designed.** The biggest gap, and the one the evaluating organisation cares most about. |
| **Structured clinical history** in standard format — chief complaint → HPI → past medical/surgical → drug & allergy → family → personal → ROS → prior investigations | **Partial.** `triage_results` holds chief complaint, symptoms, summary, and clinical note; the rest of the sections have no home. |
| **Document OCR with a chronological timeline** and abnormal-value highlighting | **Partial.** Upload, storage, and patient-supplied labels are done; extraction, dating, and ordering are not. |
| **ABHA / ABDM FHIR push** to the hospital HIS, consent-first | **Not built.** Only the mock Aadhaar flow exists. |
| **Kiosk form factor** — voice-first, icon-driven, usable untrained | **Not built.** The app assumes a personal smartphone. Flutter web can run on a kiosk, but the UI is not designed for one. |

The three that are mostly schema and prompt work — a fuller history structure, an AYUSH
section, and document timelining — are additive: `triage_results` can gain columns, and
the history sections are the AI layer's output shape.
[AI Integration Contract](AI-Integration-Contract) is where that shape is agreed, so it
is the cheapest moment to widen it.

---

## Highest-value next steps

1. **A migration tool.** `db/*.sql` runs only on an empty data directory. Everything
   below is harder once there is data worth keeping.
2. **Consent capture.** Health data under the DPDP Act, and the profile now uploads on
   save. See [Security and Compliance](Security-and-Compliance).
3. **Notifications.** `patient_relatives.notify` is stored and promised in the UI copy
   but nothing sends. That is the widest gap between what the app implies and what it
   does.
4. **Token allocation under concurrency.** `max()+1` collides if two intake points
   register at the same instant.
5. **Appointment slots.** Walk-in works; scheduled OPD does not.
