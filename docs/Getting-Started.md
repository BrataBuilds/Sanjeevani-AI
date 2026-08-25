# Getting Started

## Prerequisites

| Tool | Version used | Needed for |
|---|---|---|
| Docker + Compose | 29 / v5 | Postgres, and optionally the API + web |
| Node | 24 (≥20 works) | backend, web |
| Flutter | 3.44 (Dart 3.12) | patient app |
| bash + curl + python3 | any | `scripts/smoke.sh` |

Android Studio or Xcode only if you want to run the app on a device/emulator;
`flutter run -d chrome` needs neither.

---

## 1. Environment

```bash
git clone https://github.com/BrataBuilds/SIH2026-Smart-Health-App.git
cd SIH2026-Smart-Health-App
cp .env.example .env
```

The defaults work as-is for local development. `JWT_SECRET` is a throwaway value —
replace it before anything leaves your machine.

## 2. Database

```bash
docker compose up -d db
```

Postgres 17 comes up on **host port 5433** (container 5432 — 5433 avoids clashing with
a local Postgres). On the very first boot it runs `db/01-schema.sql` then
`db/02-seed.sql` from `docker-entrypoint-initdb.d`.

> Those files run **only on an empty data directory.** After changing the schema:
> `docker compose down -v && docker compose up -d db`. There is no migration tool yet.

Confirm:

```bash
docker exec sanjeevani-db psql -U sanjeevani -d sanjeevani -c '\dt'
```

## 3. Backend

```bash
cd backend
npm install
npm run dev          # node --watch, listens on :4000
```

```bash
curl localhost:4000/health      # {"ok":true,"db":"up"}
curl localhost:4000/ai/health   # {"triage_backend":"stub","callback_enabled":true}
```

`triage_backend: "stub"` means no AI service is connected and the backend answers with
placeholder data — the app and dashboards are fully usable in that state. See
[AI Integration Contract](AI-Integration-Contract).

## 4. Staff web console

```bash
cd web
npm install
npm run dev          # :3000
```

Open <http://localhost:3000> and sign in with a seeded account below.

## 5. Patient app

```bash
cd app
flutter pub get
flutter run                     # pick a device
flutter run -d chrome           # quickest, no emulator needed
```

The app picks its API base URL automatically: `10.0.2.2:4000` on Android (the emulator's
alias for the host), `localhost:4000` elsewhere. Override for a physical device:

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:4000
```

**Running the app on Flutter web?** Add its origin to `CORS_ORIGINS`, or the browser
blocks every request:

```bash
CORS_ORIGINS=http://localhost:3000,http://localhost:PORT npm run dev
```

`flutter run -d chrome` picks a random port each time; use `--web-port=8081` to pin it.

---

## Everything at once

```bash
docker compose up          # db + backend + web
cd app && flutter run      # the app still runs from your machine
```

`NEXT_PUBLIC_API_URL` is baked into the browser bundle at **build** time, so change it
in `.env` and rebuild (`docker compose up --build web`) rather than just restarting.

---

## Seeded accounts

All use the password `password123`.

| Role | Email | Sees |
|---|---|---|
| Patient | `patient@demo.test` | The app. Profile is pre-filled, one waiting token. |
| Doctor | `dr.mehta@citygeneral.test` | General Medicine queue at City General |
| Doctor | `dr.rao@citygeneral.test` | Cardiology |
| Doctor | `dr.khan@citygeneral.test` | Emergency |
| Hospital admin | `admin@citygeneral.test` | City General analytics + staff management |

Also seeded: two hospitals in Bhubaneswar ~6 km apart (so the nearest-alternative
suggestion has something to show), eight departments, one waiting visit.

Doctors and admins **cannot self-register.** An admin creates doctors at
**Staff & departments → Add a doctor**; the password is handed over out of band.

---

## Checks

```bash
cd backend && npm test              # pure-logic unit tests, no DB needed
cd app     && flutter test          # client unit + widget tests
cd app     && flutter analyze       # should be clean
cd web     && npm run build         # typechecks and builds
bash scripts/smoke.sh               # end-to-end, needs db + backend running
```

`scripts/smoke.sh` is the one that matters: 73 assertions covering register → profile →
document upload → triage chat → MCQ answers → report → queue token → doctor queue →
urgency override → care-team chat → admin analytics → audit trail, plus the
access-control boundaries (patients blocked from staff routes, doctors unable to post in
a patient's assistant thread, cross-hospital isolation, the AI secret).

---

## Google sign-in (optional)

Off by default: with `GOOGLE_CLIENT_IDS` empty, the button is hidden and email/password
still works everywhere. To turn it on:

1. In Google Cloud Console create OAuth client IDs for each platform you build
   (Android, iOS, Web).
2. Put **all** of them, comma-separated, in `GOOGLE_CLIENT_IDS` — the backend uses the
   list as the allowed audience set when verifying the ID token.
3. Run the app with the **web** client id as the server client id:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com
```

4. Drop `google-services.json` into `app/android/app/` and
   `GoogleService-Info.plist` into `app/ios/Runner/`. Both are gitignored.

The client only ever does the Google dance and sends the resulting ID token; the backend
verifies it server-side and mints its own JWT. An unknown Google account becomes a
**patient** — staff are never created this way. A Google account whose email matches an
existing password account is linked to it rather than duplicated.

The staff web console has no Google button on purpose: staff accounts are provisioned,
not self-served.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `ECONNREFUSED ::1:5433` | The db container is not up, or still starting. `docker compose ps`. |
| Schema changes have no effect | Init scripts run once. `docker compose down -v`. |
| App shows "Failed host lookup" on Android | Use `10.0.2.2`, not `localhost`. It is the default; you may have overridden `API_URL`. |
| Browser console shows a CORS error | Add the origin to `CORS_ORIGINS` and restart the backend. |
| `403 origin … is not allowed` | Same. Native clients send no Origin header and are always allowed. |
| Google button missing | `GOOGLE_CLIENT_IDS` is empty, or `GOOGLE_SERVER_CLIENT_ID` was not passed to `flutter run`. |
| Assistant never replies | Check `/ai/health`. If `http`, your service is unreachable — a `status` message saying so appears in the chat. |
| Upload rejected | 10 MB cap (`MAX_UPLOAD_BYTES`) and a mime allowlist: jpeg, png, webp, heic, pdf. |
