# Setup

Everything needed to get the platform running on a machine that has none of it today.

There are four pieces. You do not need all four — pick a track:

| I want to… | Run |
|---|---|
| Poke at the API | db + backend |
| Work on the doctor/admin console | db + backend + web |
| Work on the patient app | db + backend + app |
| Demo the whole thing | all four |

The AI/RAG layer is **not** in this repository and you do not need it. With no AI
service configured the backend answers with clearly-labelled placeholder data, so every
screen in the app and both dashboards work end to end. See
[AI Integration Contract](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/AI-Integration-Contract).

---

## 1. Prerequisites

| Tool | Version here | Needed for | Install |
|---|---|---|---|
| Git | any | everything | <https://git-scm.com/downloads> |
| Docker Desktop | 29 / Compose v5 | Postgres, optionally API + web | <https://docs.docker.com/get-started/get-docker/> |
| Node | 24 (≥20.12 works) | backend, web | <https://nodejs.org> |
| Flutter | 3.44 (Dart 3.12) | patient app only | <https://docs.flutter.dev/get-started/install> |

`≥20.12` is not arbitrary — the backend's dev script uses `--env-file-if-exists`, which
landed in that release.

For `scripts/smoke.sh` you also need `bash`, `curl`, and `python3`. macOS and Linux have
all three. On Windows they come with Git Bash — run the script from a Git Bash prompt,
not PowerShell.

Android Studio or Xcode are needed only to put the app on a device or emulator.
`flutter run -d chrome` needs neither. Check what Flutter can see:

```bash
flutter doctor
```

---

## 2. Clone and configure

```bash
git clone https://github.com/BrataBuilds/SIH2026-Smart-Health-App.git
cd SIH2026-Smart-Health-App
cp .env.example .env
```

Most defaults work as-is, but **`JWT_SECRET` ships empty and the backend refuses to
start without it** — on every run path, not just in Docker. Generate one:

```bash
node -e "console.log(crypto.randomBytes(32).toString('hex'))"
```

Paste it into `.env`. Do the same for `AI_CALLBACK_SECRET` if you will connect a real
AI service; left empty, every `/ai/*` call is rejected, which is the safe default.

`.env` is gitignored. `.env.example` is the tracked template — keep them in step when you
add a variable.

---

## 3. Database

```bash
docker compose up -d db
```

Postgres 17, **host port 5433** (container 5432 — 5433 so a Postgres already running on
5432 keeps working). On its first boot the container runs `db/01-schema.sql`, then
`db/02-seed.sh`, which loads `db/seed.sql` unless `SEED_DEMO_DATA=false`.

Set `SEED_DEMO_DATA=false` in `.env` for any instance that will hold real patients: the
demo staff accounts below share one well-known password. You get the schema and an empty
database.

Confirm it is up and seeded:

```bash
docker compose ps
docker exec sanjeevani-db psql -U sanjeevani -d sanjeevani -c '\dt'      # 17 tables
```

> **Those SQL files run only once, on an empty data directory.** Editing the schema and
> restarting does nothing. To re-apply: `docker compose down -v && docker compose up -d db`
> — which **deletes all data**. There is no migration tool yet; see
> [Feature Coverage](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/Feature-Coverage).

---

## 4. Backend

```bash
cd backend
npm install
npm run dev
```

Listens on **:4000** under `node --watch`, so it restarts on save. It reads `../.env`,
so anything you set there (`GOOGLE_CLIENT_IDS`, `CORS_ORIGINS`, `AI_SERVICE_URL`) takes
effect on restart.

```bash
curl localhost:4000/health      # {"ok":true,"db":"up"}
curl localhost:4000/ai/health   # {"triage_backend":"stub","callback_enabled":true}
```

`"db":"up"` is the one that matters — it proves the backend reached Postgres.
`triage_backend: "stub"` means no AI service is connected, which is the normal
development state.

---

## 5. Staff web console

```bash
cd web
npm install
npm run dev
```

<http://localhost:3000> — sign in with a seeded doctor or admin from
[section 8](#8-seeded-accounts). One app serves both roles and routes on the JWT role;
there is no signup, because staff accounts are provisioned by a hospital admin.

`NEXT_PUBLIC_API_URL` is baked into the browser bundle at **build** time. Changing it
means a rebuild, not a restart.

---

## 6. Patient app

```bash
cd app
flutter pub get
```

### Fastest — in a browser

```bash
flutter run -d chrome --web-port=8081
```

Then add that origin to `CORS_ORIGINS` in `.env` and restart the backend, or the browser
blocks every request:

```
CORS_ORIGINS=http://localhost:3000,http://localhost:8081
```

Pin `--web-port`; without it Flutter picks a random port each run and the allowlist can
never keep up.

### Android emulator

```bash
flutter run
```

No configuration needed. The app defaults to `10.0.2.2:4000`, which is the emulator's
alias for your host machine.

### A real Android phone

Plug it in over USB with developer options and USB debugging on, confirm the pairing
prompt, then:

```bash
adb devices                                # your phone should be listed as "device"
adb reverse tcp:4000 tcp:4000
flutter run --dart-define=API_URL=http://localhost:4000
```

`adb reverse` makes the phone's own `localhost:4000` tunnel to your machine's port 4000
over the USB cable. Prefer it over putting your LAN IP in `API_URL`: it does not care
what network either device is on, it survives your laptop changing IP, and it keeps
working on Wi-Fi that isolates clients from each other.

Two things to know:

- **The tunnel dies when the cable is unplugged.** Re-run the `adb reverse` line after
  re-plugging; you do not need to rebuild the app.
- Plain HTTP works because `usesCleartextTraffic` is set in the **debug** manifest only.
  Release builds keep the platform's block, which is deliberate — see
  [Security and Compliance](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/Security-and-Compliance).

If `adb` is not on your PATH, it ships with the Android SDK at
`~/Android/Sdk/platform-tools/adb` (`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
on Windows).

### iOS

```bash
flutter run -d <device>
```

`localhost:4000` is the default and works on the simulator. A physical iPhone has no
`adb reverse` equivalent, so use your machine's LAN IP with both devices on the same
network: `--dart-define=API_URL=http://192.168.1.20:4000`.

---

## 7. Everything at once — one command

```bash
bash run.sh
```

That is the whole thing: Postgres, the API, the staff console, and the patient app as
Flutter web. It creates `.env` from the template on a first run and generates the
secrets that have no default, then does `docker compose up --build`.

| | |
|---|---|
| Staff console | <http://localhost:3000> |
| Patient app (web) | <http://localhost:8081> |
| API | <http://localhost:4000> |
| Postgres | host port 5433 |

Add the AI team's triage service:

```bash
bash run.sh --profile ai      # also starts RAG on :8000, needs GEMINI_API in .env
```

Any extra arguments go straight through to `docker compose up`, so `bash run.sh -d`
detaches.

**The mobile app is not in here.** A Flutter app needs a device or an emulator, so
`:8081` is the browser build — every screen, but not the real thing. For a phone or
emulator, sections 3–6 above.

Plain `docker compose up` also works if you already have a `.env` with a real
`JWT_SECRET`; `run.sh` exists only because that value has no default and the backend
refuses to start without it. Rebuild rather than restart after changing
`NEXT_PUBLIC_API_URL` or `API_URL` — both are compiled into their browser bundles:

```bash
docker compose up --build web app-web
```

---

## 8. Seeded accounts

> **Off by default.** Every account below shares one password published in this
> repository, so loading them anywhere reachable hands out a hospital-admin
> session to anyone who reads the file. Set `SEED_DEMO_DATA=true` in `.env`
> **before the first boot** (they only load into an empty database) to use them.
>
> For anything else, set `ADMIN_EMAIL` / `ADMIN_PASSWORD` / `ADMIN_HOSPITAL`
> instead: the backend provisions that administrator on every start, and that
> admin creates the doctors.

All use the password `password123`.

| Role | Email | Sees |
|---|---|---|
| Patient | `patient@demo.test` | The app. Profile pre-filled, one waiting token. |
| Doctor | `dr.mehta@citygeneral.test` | General Medicine queue at City General |
| Doctor | `dr.rao@citygeneral.test` | Cardiology |
| Doctor | `dr.khan@citygeneral.test` | Emergency |
| Hospital admin | `admin@citygeneral.test` | City General analytics + staff management |

Also seeded: two Bhubaneswar hospitals about 6 km apart — so the nearest-alternative
suggestion has something to show — eight departments, and one waiting visit.

Doctors and admins **cannot sign themselves up.** An admin creates them at
**Staff & departments → Add a doctor** and hands over the password out of band. Running
`scripts/smoke.sh` adds throwaway `smoke…@demo.test` patients and `dr.new…` doctors; they
are harmless, and `docker compose down -v` clears them.

---

## 9. Check it works

```bash
cd backend && npm test          # 8 unit tests, no database needed
cd app     && flutter analyze   # should print "No issues found"
cd app     && flutter test      # 5 tests
cd web     && npm run build     # typechecks and builds
bash scripts/smoke.sh           # 78 assertions, needs db + backend running
```

`scripts/smoke.sh` is the one that matters. It walks register → profile → document
upload → triage chat → MCQ answers → report → queue token → doctor queue → urgency
override → care-team chat → admin analytics → audit trail, and asserts the
access-control boundaries: patients blocked from staff routes, doctors unable to post in
a patient's assistant thread, cross-hospital isolation, and the AI shared secret. Run it
after any backend change.

It talks to `http://localhost:4000` by default; override with `API=…`.

---

## 10. Google sign-in (optional)

Off by default. With `GOOGLE_CLIENT_IDS` empty the button is hidden and email/password
works everywhere, so skip this unless you are specifically working on it.

1. In Google Cloud Console, create OAuth client IDs for each platform you build
   (Android, iOS, Web).
2. Put **all** of them, comma-separated, in `GOOGLE_CLIENT_IDS`. The backend uses that
   list as the allowed audience set when it verifies the ID token.
3. Run the app with the **web** client ID as its server client ID:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com
```

4. Drop `google-services.json` into `app/android/app/` and `GoogleService-Info.plist`
   into `app/ios/Runner/`. Both are gitignored.

The client only performs the Google handshake and sends the resulting ID token; the
backend verifies it server-side and mints its own JWT. An unknown Google account becomes
a **patient** — staff are never created this way. A Google account whose email matches an
existing password account is linked to it rather than duplicated.

The staff console has no Google button on purpose.

---

## 11. The AI triage service

Optional. Everything works without it — the backend answers from a labelled stub, so
the app and both dashboards demo fine with no Gemini key at all.

To run it, put a Gemini key in `.env` and start the `ai` profile:

```bash
GEMINI_API=<your key>
```

```bash
bash run.sh --profile ai
```

That starts `RAG/` on :8000 and points `AI_SERVICE_URL` at it. Confirm with:

```bash
curl localhost:4000/ai/health     # {"triage_backend":"http", ...}
curl localhost:8000/              # lists the RAG endpoints
```

`run.sh` sets `AI_SERVICE_URL` only for this profile, on purpose: pointing the backend
at a service that is not running turns stub answers into "the assistant is
unavailable".

**It shares this Postgres.** `DB_URL` points at the same container, and the service
creates its own tables on startup — `sessions`, `session_state`, `symptoms`, `doctors`
— alongside the platform's 17. Reports are stored in `session_state.report`, not on
the container filesystem, so they survive a restart.

The endpoint the backend calls is `POST /triage` in `RAG/api/routes/triage.py`. It is a
translator only: it hands the newest patient message to the agent and maps the answer
onto the platform's contract, including converting the service's 0–100 urgency score to
the platform's ESI 1–5. Request and response shapes are in
[AI Integration Contract](https://github.com/BrataBuilds/SIH2026-Smart-Health-App/wiki/AI-Integration-Contract).

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ECONNREFUSED ::1:5433` from the backend | The db container is not up yet. `docker compose ps`; it has a healthcheck, give it a few seconds. |
| Schema edits have no effect | Init scripts run once, on an empty volume. `docker compose down -v && docker compose up -d db`. Deletes all data. |
| `port is already allocated` | Something already holds 5433, 4000, or 3000. Change `POSTGRES_PORT` / `API_PORT` / `WEB_PORT` in `.env`. |
| A variable in `.env` seems ignored | The backend reads it at startup only — restart. For `NEXT_PUBLIC_API_URL`, rebuild the web bundle. |
| App on Android says "Failed host lookup" or "Connection refused" | The phone cannot see your machine. Re-run `adb reverse tcp:4000 tcp:4000`, and pass `--dart-define=API_URL=http://localhost:4000`. |
| `adb devices` shows `unauthorized` | Accept the USB debugging prompt on the phone; re-plug if it never appeared. |
| Browser console shows a CORS error, or `403 origin … is not allowed` | Add the exact origin to `CORS_ORIGINS` and restart the backend. Native clients send no `Origin` header and are always allowed. |
| Google button missing | `GOOGLE_CLIENT_IDS` is empty, or `GOOGLE_SERVER_CLIENT_ID` was not passed to `flutter run`. |
| Assistant never replies | Check `/ai/health`. If it says `http`, your AI service is unreachable — a `status` message saying so appears in the chat. |
| Doctor's page shows a "sample values" banner | Working as intended: no AI service is connected, so the report is stub output. |
| Upload rejected | 10 MB cap and a mime allowlist: jpeg, png, webp, heic, pdf. |
| `smoke.sh: command not found` / path errors on Windows | Run it from Git Bash, not PowerShell or CMD. |
