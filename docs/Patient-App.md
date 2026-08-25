# Patient App

Flutter 3.44 / Dart 3.12. Targets Android, iOS, and web. Lives in `app/`.

> **The UI is placeholder.** The design team replaces it. It is one seed colour, stock
> Material 3, no animation, no component library. Do not invest in styling here — do
> keep the flow and the API wiring, which is what the screens exist to prove.

---

## Files

```
app/lib/
  main.dart                     app root + the gate that picks the first screen
  api.dart                      HTTP client, token storage, one method per endpoint
  app_state.dart                ChangeNotifier: session, patient, Google, app lock
  location.dart                 optional coarse location
  pick_file.dart                one file picker for the whole app
  widgets/authed_image.dart     images that need the auth header
  screens/
    login_screen.dart           sign in / register / Google
    app_lock_screen.dart        PIN gate
    profile_setup_screen.dart   the long form — also the edit screen
    home_shell.dart             bottom nav: Assistant / Hospital / Profile
    chat_screen.dart            both chat surfaces
    care_team_screen.dart       hospital thread list
    profile_screen.dart         read-only profile
    bills_screen.dart           visit ledger + uploaded bills
app/test/widget_test.dart        unit + widget tests
```

No state-management package. `AppState` is a plain `ChangeNotifier` read through
`ListenableBuilder`; screens own their own loading state. API payloads stay as
`Map`/`List` — no model codegen, because the payloads move faster than generated classes
would.

---

## The gate

`_Gate` in `main.dart` listens to `AppState` and picks:

```
booting                      -> spinner
not signed in                -> LoginScreen
app PIN set, not unlocked     -> AppLockScreen
profile_complete == false     -> ProfileSetupScreen
otherwise                     -> HomeShell
```

Signing in sets `unlocked = true` — you just proved who you are, so the PIN is not
asked for twice in a row. The PIN gate exists for reopening the app.

---

## Screens against `Design docs/App_Feature_Set.md`

### Login / register (§1.2.1)
Email + password, with register on the same screen. Google button appears only when the
server reports `google_enabled` **and** the app was built with
`GOOGLE_SERVER_CLIENT_ID`; otherwise it is hidden and the reason is stated. The API base
URL is printed at the bottom, which saves a lot of guessing when a device cannot reach
the backend.

Aadhaar is not on this screen — `Design docs/App_Feature_Set.md` calls it "UI only", and putting a fake
verification in front of first-run makes it look load-bearing. It sits in the profile as
an optional row instead.

### Profile setup (§1.2.1) — and the edit screen
One `ProfileSetupScreen` with a `setup` flag. `setup: true` is the first-run gate;
`setup: false` is what the Edit button opens. One widget, so the field list cannot drift
between them.

Sections: photo and name · date of birth (age shown, derived), gender, blood type,
phone, address · location · insurance · preferred hospitals · conditions, allergies,
genetic disorders (multi-input) · people to inform (multi-input) · medical history
uploads · app PIN and Aadhaar.

Conditions, relatives, and documents save immediately — they are separate collections.
The scalar fields save on **Finish**, which also flips `profile_complete` and lets the
gate through.

### Assistant chat (§1.2.2)
`ChatScreen(kind: 'ai')`. Polls every 3 s.

| `Design docs/App_Feature_Set.md` asks for | Built |
|---|---|
| Normal text window | Bubbles, patient right, assistant left |
| Mock image button | **Real** — uploads via `/attachments` |
| Mock voice button | Mock, as specified. A snackbar. The endpoint already takes `audio/*`. |
| Language selector at the top | `translate` menu, 12 languages, persisted to the profile and sent with each message |
| Chat history | The full transcript, loaded once then polled incrementally with `?after=` |
| MCQ questions from the LLM | `ChoiceChip` cards; **Send answers** posts them and starts the next round |
| Recommended hospitals UI | Cards with distance and the stated reason |
| Status bar for hospital updates | Pinned bar with token number, department, doctor; turns red on a red flag |

A permanent line under the app bar says the assistant routes but does not diagnose.

### Hospital chat (§1.2.3)
`CareTeamScreen` lists threads; tapping opens the same `ChatScreen` with
`kind: 'care_team'`. Different icon (`medical_services` vs `smart_toy`), different label
("Care team" / a doctor's real name vs "Assistant"), different bubble colour. Threads
usually appear because a doctor opened one from their console; the patient can also start
one with any hospital.

### Profile (§1.2.4)
Read-only view of everything collected, plus recent visits and their tokens. The
**Bills and visit records** button opens `BillsScreen`, which says plainly that hospital
billing is not connected and shows the visit ledger and any file the patient labelled
bill/invoice/receipt.

---

## Configuration

| `--dart-define` | Default | Purpose |
|---|---|---|
| `API_URL` | `10.0.2.2:4000` on Android, `localhost:4000` elsewhere | Backend base URL |
| `GOOGLE_SERVER_CLIENT_ID` | empty | Google **web** client id, used as the ID-token audience |

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:4000
```

Android's `10.0.2.2` is the emulator's alias for the host machine; `localhost` inside the
emulator is the emulator.

## Dependencies

`http` · `shared_preferences` · `file_picker` · `google_sign_in` · `geolocator`.
Five. Nothing for state, routing, or theming.

`google_sign_in` 7.x: `GoogleSignIn.instance.initialize(serverClientId:)` then
`authenticate()`, and `account.authentication.idToken` goes to `POST /auth/google`.
`supportsAuthenticate()` is checked first — it is false on web, where a rendered button
is required instead.

## Platform config

Already in the repository:

- `android/app/src/main/AndroidManifest.xml` — `INTERNET`, coarse + fine location.
- `android/app/src/debug/AndroidManifest.xml` — `usesCleartextTraffic="true"`,
  **debug only**, because the dev API is plain HTTP. Release builds keep Android's
  cleartext block, so production has to be HTTPS.
- `ios/Runner/Info.plist` — location and photo-library usage strings,
  `NSAllowsLocalNetworking` for the dev API.

Still needed for Google sign-in: `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist`. Both gitignored — get them from the Google Cloud
project.

## Location

`location.dart` returns `null` on any failure — service off, permission denied, no fix,
timeout — and every caller works without it. It is used only to sort hospitals by
distance. Low accuracy, 12 s cap; a city block is precise enough.

## Checks

```bash
cd app
flutter analyze     # clean
flutter test        # 5 tests
flutter build web   # compiles
```

The tests cover the API error decoding, the base-URL logic, and the two screens that
gate the app (login validation, the register/sign-in toggle, the PIN screen). They do
not drive a live backend.

**Not automatically verified:** the on-device flows — the chat polling loop, MCQ
submission, file upload from a real picker, Google sign-in, and geolocation. They
compile and the endpoints behind them are covered by `scripts/smoke.sh`, but the widget
wiring has only been checked by reading it. Walk through it once on a device:

1. Register → the profile form appears.
2. Add a condition, a contact, a document; upload a photo. Finish.
3. Assistant tab → send "stomach pain since morning" → MCQs appear.
4. Answer them → report card, hospital cards, and a token in the status bar.
5. Sign in to the web console as `dr.mehta@citygeneral.test` → the token is in the queue.
6. Message the patient from the visit page → it lands in the Hospital tab.
