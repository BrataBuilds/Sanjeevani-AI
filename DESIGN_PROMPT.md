# Design brief

Two prompts. Run them separately; the patient app and the staff console have different
users, devices, and constraints. The shared language section applies to both.

---

## Shared design language (include in both prompts)

```
PRODUCT

Sanjeevani AI — conversational hospital triage and registration for Indian
public hospitals. A patient describes their problem in their own language and
comes out with a completed registration, a plain-language summary, a department
and doctor, and a queue token. The doctor gets a filled-in starting point
instead of a blank slate.

It is a triage and ROUTING layer, not a diagnostic one. It decides who a
patient should see and how urgently. Nothing in it diagnoses. Any design that
implies a diagnosis is wrong.

WHO USES IT

Patients: walk-in outpatients at a government hospital. Assume low digital
literacy, mid-range Android on a slow network, one hand, standing in a queue,
possibly in pain or holding a child. Many are more comfortable reading Odia or
Hindi than English. Some are elderly. Some are accompanying a relative rather
than themselves.

Staff: doctors in an OPD seeing 60+ patients a day, 90 seconds per patient on
a shared desktop, and hospital admins watching flow across departments.

NON-NEGOTIABLES

1. Urgency is a 5-level scale where 1 is MOST urgent (ESI). It must be legible
   without colour alone — colour-blind users and cheap washed-out screens are
   both in scope. Levels: 1 immediate, 2 very urgent, 3 urgent, 4 standard,
   5 non-urgent.
2. A red flag is a separate, louder state than urgency 1. It means a possible
   emergency was detected. It must be impossible to miss and impossible to
   confuse with ordinary high urgency.
3. AI output is a SUGGESTION, never a verdict. Anywhere a specialty, urgency,
   or summary is shown, its provenance and confidence must be visible, and the
   doctor's ability to override must be adjacent — not buried in a menu. This
   is a regulatory property, not a preference.
4. Stub-sourced data must look obviously provisional. When no AI service is
   connected the backend returns placeholder text with confidence 0. Design a
   state for that, so a demo is never mistaken for real output.
5. 12 languages, including Odia, Hindi, Bengali, Tamil, Telugu. Devanagari and
   Odia script run taller than Latin — no fixed-height text containers, no
   layouts that break when a label doubles in length.
6. Accessibility is the point, not a checkbox. The users this exists to serve
   are disproportionately elderly, low-literacy, and low-vision. Minimum 16px
   body text, large touch targets, real focus states, WCAG AA contrast.

WHAT TO IGNORE

The current UI in the repository is deliberately unstyled placeholder — plain
Material 3 in Flutter, one hand-written stylesheet in Next.js, no component
library, div-width bars instead of charts. Do not carry any of it forward.
Treat it only as a map of what screens exist and what data each one holds.
```

---

## Prompt 1 — patient app (Flutter, Android/iOS)

```
Design the patient mobile app for Sanjeevani AI.

[paste the Shared design language section here]

SCREENS TO DESIGN

1. Sign in / register
   Email + password, and a Google button that is present only when the server
   has Google configured. Design for its absence too.

2. App lock
   A separate PIN gate on reopen, distinct from sign-in. The patient has
   already signed in; this is the "welcome back" moment. Needs a way out
   (sign out) that is findable but not accidental.

3. Profile setup, reused as profile edit
   The longest screen in the app and the one most likely to be abandoned.
   Fields: photo, full name, date of birth (age is derived, never entered),
   gender, blood type, phone, address, optional coarse location, insurance
   provider and policy number, preferred hospitals (multi-select), known
   conditions (multi-input, typed as disease / allergy / genetic), emergency
   contacts (multi-input: name, contact, relation, notify flag), medical
   document uploads (images and scanned PDFs with a label), an app PIN, and a
   mock Aadhaar step.
   Design the progressive path: what is required to proceed, what can wait,
   how a half-finished profile is resumed. Multi-input groups are the hard
   part — adding a third allergy must not feel like filling a form again.
   The Aadhaar step is a UI-only mock and must say so honestly to the user
   without looking broken.

4. Assistant chat — the core screen
   A conversation with the triage assistant. Elements, all of which can appear
   in one thread:
     - patient text messages
     - assistant text replies
     - tappable multiple-choice follow-up questions (single and multi select),
       which become an answered, non-editable state once submitted
     - a preliminary report card: chief complaint, symptoms with duration and
       severity, plain-language summary, and its confidence and sources
     - hospital suggestion cards: name, distance, live queue length, and the
       reason it was suggested
     - a live token status bar: token number, department, doctor — pinned, and
       the single most important thing on the screen once it exists
     - a red-flag state that changes the whole screen, not one badge
     - a "thinking" state while triage runs
     - a language selector, reachable at any point mid-conversation
     - an image attach button (real) and a voice button (currently a mock —
       design the real intent, since speech-to-text is the accessibility path
       for this user base)
   Design the empty state: what a patient who has never used this sees, and
   what makes them type the first message.

5. Hospital / care-team chat
   Same conversation surface, real humans at the hospital. Must be
   unmistakably distinct from the assistant at a glance — a patient must never
   wonder whether they are talking to a machine or a person.

6. Home shell
   How the above are navigated. Currently a bottom nav. Question whether that
   is right for a user who mostly does one thing.

7. Profile view
   Read-back of everything collected, with a route to edit.

8. Bills and visit records
   Past visits with token, department, doctor, status, and self-uploaded
   documents. Billing is not connected, and the screen currently says so.
   Design an honest empty/unavailable state rather than a fake ledger.

DELIVER

Screen designs for the above, the urgency and red-flag visual system, the
component set the chat needs, both light and dark, and the empty / loading /
error / offline state for every screen that fetches. Show at least one screen
in Odia or Hindi to prove the layout survives the script.
```

---

## Prompt 2 — staff console (web, Next.js)

```
Design the doctor and hospital-admin web console for Sanjeevani AI.

[paste the Shared design language section here]

CONTEXT THAT SHAPES EVERY DECISION

A shared hospital desktop, often 1366×768, often an old browser, often a
mouse and no trackpad gestures. The doctor has roughly 90 seconds per patient
and is reading this while the patient sits down. Information density is a
feature here, the opposite of the patient app. Nothing important below the
fold. No hover-only affordances.

One app, split by role on sign-in. Staff never self-register — accounts are
provisioned by a hospital admin — so there is no signup and no Google button.

SCREENS TO DESIGN

Doctor
1. Queue — the default landing screen. Rows ordered most-urgent-then-
   longest-waiting, with three scopes (mine / department / hospital), status
   filters, urgency, red-flag markers, waiting time, and the patient's chief
   complaint. This screen is looked at hundreds of times a day: optimise for
   scanning, and for the doctor knowing instantly whether anything needs them
   right now.

2. Visit detail — the pre-consult screen, the most important in the console.
   Holds the AI's preliminary report (chief complaint, symptoms, summary,
   clinical note, specialty, urgency, red flag) WITH its confidence and
   sources; the patient's profile, known conditions, relatives with contact
   numbers, and uploaded documents inline; and the doctor's own controls:
   urgency override, status transitions (claim / start / done / refer), and
   notes. The override must sit next to the value it overrides. Design the
   banner state for when the report is stub-sourced rather than real.

3. Care-team messages: thread list, and a thread.
   A patient's assistant transcript is READABLE here but not postable — the
   doctor can read what the patient told the machine and cannot inject
   messages into it. Design that read-only state so the absence of a composer
   reads as intentional, not broken.

Hospital admin
4. Dashboard — patient flow: totals, department load, routed-specialty mix,
   daily volume, status breakdown, urgency breakdown, over a configurable
   window. The question it answers is "where is the bottleneck right now".
5. Visits list — all visits at this hospital, filterable.
6. Staff and departments — provision a doctor, toggle duty and account state,
   add a department.
7. Audit trail — every AI recommendation and every doctor override, scoped to
   this hospital. Each entry carries an actor, an action, and a JSON detail.
   Design for a real audit read: finding the one entry that matters, and
   seeing an AI value and a doctor's value disagree at a glance.
8. Sign in — email and password only.

DELIVER

Screen designs, the urgency and red-flag system shared with the patient app,
a table and data-dense list pattern, a chart set for the admin dashboard
(currently div-width bars, so treat charts as unsolved), form patterns for
provisioning, empty and loading and permission-denied states, and both light
and dark. State the type scale and spacing scale explicitly — this console
lives or dies on density being deliberate rather than accidental.
```

---

## Source of truth for behaviour

Screen inventory, field lists, and the data each screen holds:
[Patient App](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/Patient-App) ·
[Staff Web Console](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/Staff-Web-Console) ·
[API Reference](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/API-Reference)

Four product questions are still open and one of them touches design directly:
the urgency scale is built as 1–5 but one source document uses 0–100. If it
changes, the whole colour system changes with it. See
[Feature Coverage](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/Feature-Coverage).
