# Staff Web Console

Next.js 16 App Router, React 19, TypeScript. Lives in `web/`. One app serving both
staff roles, split by route and guarded by the JWT role claim.

> **The UI is placeholder.** One plain stylesheet, no Tailwind, no component library,
> no chart library. The design team replaces it. The data wiring and the access rules
> are the part worth keeping.

---

## Files

```
web/
  app/
    layout.tsx                        SessionProvider + top bar
    globals.css                       the entire stylesheet
    topbar.tsx                        role-aware nav
    ui.tsx                            Urgency, Status, Stat, Bars, AuthFile
    page.tsx                          redirects by role
    login/page.tsx                    email + password
    doctor/page.tsx                   the queue
    doctor/visits/[id]/page.tsx       report before the consult + decisions
    doctor/messages/page.tsx          care-team threads
    doctor/conversations/[id]/page.tsx one thread (writable or read-only)
    admin/page.tsx                    patient-flow analytics
    admin/visits/page.tsx             full visit list
    admin/doctors/page.tsx            staff + departments
    admin/audit/page.tsx              audit trail
  lib/
    api.ts                            fetch wrapper, token, blob URLs
    session.tsx                       SessionProvider, useSession, RequireRole, usePolling
```

Every page is a client component. The backend is token-based with no cookies, so
server-side rendering has no session to render with — the JWT lives in `localStorage`
and pages fetch on mount.

---

## Auth

`/login` takes email and password only. There is no register form and no Google button:
doctors and hospital admins are provisioned by an admin (`POST /admin/doctors`) and never
self-serve. A patient account that signs in here is told to use the app.

`RequireRole` wraps each page body: while loading it renders a placeholder, no session
redirects to `/login`, and the wrong role redirects to `/`. `/` itself just forwards
doctors to `/doctor` and admins to `/admin`.

The server enforces the same rules independently — `RequireRole` is for the person using
the browser, not for security.

---

## Doctor pages

### `/doctor` — the queue
Filters: scope (`mine` / `department` / `hospital`) and status. Polls every 15 s.

Ordered `in_consult` first, then urgency ascending, then longest waiting. Each row shows
the token, an urgency chip (colour-coded 1–5, with ✎ when a doctor has overridden it), a
`red flag` chip where raised, the patient with age and gender, the suggested specialty
and department, the chief complaint, minutes waited, status, and the assigned doctor.

### `/doctor/visits/[id]` — before the consult
The page `Design docs/Design_doc.md` §3 is really asking for: the doctor should never start from a
blank slate.

Left column — the preliminary report: chief complaint, suggested specialty, urgency as
triaged, confidence, the structured symptom list, the clinical note, the plain-language
text the patient was shown, and the sources behind the routing decision. Below it, the
patient's uploaded medical history rendered inline.

Right column — **Your decision**: an urgency dropdown, notes, and queue controls
(Claim, Start consult, Mark done, Refer out). Every change `PATCH`es the visit and lands
in `audit_log` with both the AI's urgency and the doctor's. Then the patient summary
(age, blood type, phone, address, insurance, Aadhaar status), known conditions,
emergency contacts, and links to read the intake transcript or message the patient.

A red flag paints a banner at the top. If the report came from the offline stub — which
the page detects from `confidence === 0` or a `stub://` source — a notice says the
specialty and urgency are sample values, so nobody demos placeholder output as if a model
produced it.

### `/doctor/messages` and `/doctor/conversations/[id]`
The thread list and one thread. The same page renders both kinds: a `care_team` thread is
writable, and a patient's assistant transcript comes back with `can_post: false` and is
read-only, which keeps the patient's conversation with the assistant honest. MCQ sets,
report cards, hospital suggestions, and attachments all render inline.

---

## Admin pages

### `/admin` — patient flow
Six stat tiles (registered today, in queue now, urgency-1 today, doctors on duty,
average minutes to close, visits all time) and, over a 7/14/30-day window, department
load, routed specialty mix, daily volume, today's status breakdown and urgency mix.

Bars are `div`s with a percentage width. No chart library — see `Bars` in `ui.tsx`.

### `/admin/visits`
Every visit at the hospital with its filters. The ✎ marker shows where human judgement
diverged from the triage suggestion, which is the interesting column.

### `/admin/doctors`
Staff list with inline department reassignment, an on/off duty toggle, and an
enable/disable account toggle. Below it: create a doctor (the password is handed over out
of band, never emailed) and create a department.

Department creation is worth understanding: the **specialty key** is what the AI layer
returns when it routes a patient here. It is slugified — `ENT / Otolaryngology` becomes
`ent_otolaryngology` — and must be unique per hospital. See
[AI Integration Contract](AI-Integration-Contract).

### `/admin/audit`
The last 200 entries: triage results, urgency overrides, staff changes, logins, profile
edits. `Design docs/Design_doc.md` §6 requires this trail exist.

---

## Conventions

**Polling, not push.** `usePolling(load, ms)` in `lib/session.tsx`. Queue 15 s, threads
8 s, analytics 30 s. Every page also has a Refresh button.

**Files need a header.** `GET /files/:id` requires `Authorization`, so `<img src>` would
401. `AuthFile` fetches the bytes and hands back an object URL, revoking it on unmount.

**Errors.** `api()` throws `ApiError` with the server's message; pages show it in place
rather than swallowing it.

---

## Configuration

| Variable | Notes |
|---|---|
| `NEXT_PUBLIC_API_URL` | Default `http://localhost:4000`. **Baked into the browser bundle at build time** — change it and rebuild, don't just restart. The Dockerfile takes it as a build arg. |

Add the console's origin to the backend's `CORS_ORIGINS` (`http://localhost:3000` is the
default).

## Commands

```bash
cd web
npm install
npm run dev          # :3000
npm run build        # typechecks and builds; 11 routes
npm run typecheck    # tsc --noEmit
```

`output: 'standalone'` is set so the Dockerfile can ship a self-contained server.
