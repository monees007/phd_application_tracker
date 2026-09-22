# PhD Application Tracker

A Flutter Android app for tracking PhD / research position applications, built
around the 45 rows in `PG_-_Sheet5.csv`. Firebase (Auth + Firestore) is the
backend; deadline reminders are scheduled on-device.

> **This code has not been compiled.** There is no Flutter or Dart SDK in the
> environment it was written in, so it has been reviewed by hand and checked for
> delimiter balance and cross-file symbol resolution, but not type-checked.
> Expect to fix a small number of analyzer errors on the first
> `flutter analyze`. Everything else in this README is a factual description of
> what the code does, not a claim that it runs.

---

## Two things to decide before you trust the data

**1. The deadline year is inferred.** Your sheet records deadlines as day +
month (`2 Jan`, `17 May`, `1 Dec`) with no year. Two rows leak a year into the
*Funded* column (`06/03/2026`, `15.Apr.2026`), so the importer assigned **2026**
to every date. Today is September 2026, which means 42 of the 45 imported
deadlines are already in the past and 37 of those are still marked "not
applied". If the sheet is actually for the **2027** intake, change
`DEADLINE_YEAR` in the generator (or edit `assets/seed/positions.json`) before
importing. Every inferred date is flagged with a "?" in the UI and in the
detail screen banner.

**2. The Funded column is mostly empty.** Only one row (`Yale`) says `Yes`. Two
rows contain dates rather than a funding flag; rather than guess, the importer
copied the literal cell text into that position's notes. Nothing was
synthesised — 45 rows in, 45 rows out.

---

## What the app does

**Three boards** (plus an "All" tab), matching your three questions:

| Tab | Shows |
|---|---|
| To apply | status = Not applied |
| Pending | status = Applied or Interview |
| Decided | status = Accepted, Rejected or Withdrawn |

**Status** is one tap from the list (tap the chip) or from the detail screen.
Each change is timestamped and appended to a per-position history, so you can
see when you applied and when the answer came back.

**Reminders** fire 3 days before and on the day of the deadline, at 09:00 local
time by default. Both the lead times and the hour are configurable in Settings.
They only fire for positions still marked "Not applied" — once you have
submitted, nagging you to apply is noise.

**Add / edit** a position with university, programme, deadline, status, funding,
application fee + currency, link, country, tags and notes.

### Features added beyond the brief

- Anonymous sign-in with optional email/password upgrade (links to the *same*
  account, so nothing is lost)
- Overview tab: counts by status, deadlines in the next 30 days, a
  "passed without applying" list, top institutions
- Search across university / programme / notes / tags
- Filter by university, funded-only, hide past deadlines, include archived;
  sort by deadline, name or recency
- Swipe right to mark applied, swipe left to archive, both with undo
- Deadline colour coding: red overdue, red-tinted ≤3 days, amber ≤7 days
- Per-position reminder mute
- Tap a link to open the application page in a browser
- Archive (reversible) as distinct from delete (permanent)
- CSV export so the data is never trapped in the app
- Offline: Firestore's local cache is enabled, so the board works on a plane
  and syncs when you reconnect
- Dark mode, following the system setting
- Firestore security rules that validate every write and deny cross-user reads

---

## Setup

### 1. Prerequisites

Flutter **3.27 or newer** (the theme uses `Color.withValues`, added in 3.27) and
JDK 17.

```bash
flutter --version
```

### 2. Create the Firebase project

In the [Firebase console](https://console.firebase.google.com):

1. Create a project.
2. **Authentication → Sign-in method** → enable **Anonymous** and
   **Email/Password**.
3. **Firestore Database** → create in production mode, pick a region near you.

### 3. Wire the app to it

```bash
dart pub global activate flutterfire_cli
cd phd_tracker
flutterfire configure --project=<your-project-id>
```

This overwrites the placeholder `lib/firebase_options.dart` and writes
`android/app/google-services.json`. The placeholder throws a `StateError` with
this instruction if you forget — it deliberately contains no fake keys.

### 4. Deploy the security rules

```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules
```

Without this step Firestore's default rules will block every read and write and
the app will show "Could not load your positions".

### 5. Run

```bash
flutter pub get
flutter analyze        # fix anything it reports
flutter test
flutter run
```

### 6. Import your sheet

Open **Settings → Import positions from the bundled sheet**. It writes all 45
rows with stable IDs, so running it twice updates rather than duplicates.

### 7. Build a release APK

Generate your own keystore and replace the `signingConfig` in
`android/app/build.gradle.kts` — it currently points at the debug key, which is
fine for testing and unacceptable for distribution.

```bash
flutter build apk --release
```

---

## How reminders actually work

Reminders are **local exact alarms** (`flutter_local_notifications` +
`AlarmManager`), not push notifications. That choice matters:

- they fire with no network and no Firebase cost
- they survive reboot (see the boot receiver in the manifest)
- they are rescheduled wholesale whenever the position list or the reminder
  settings change, debounced by 1.2 s so a burst of Firestore updates causes one
  rebuild rather than twenty

Constraints worth knowing:

- Android caps pending alarms at roughly 500 per app. The scheduler sorts
  candidates by fire time and keeps the nearest 440.
- On Android 12+ exact alarms need a user grant. Settings shows a warning
  banner and a "Fix" button when the grant is missing; without it reminders
  degrade to inexact and can drift.
- Aggressive OEM battery managers (Xiaomi, Oppo, Samsung) kill background
  alarms. If reminders stop arriving, exempt the app from battery optimisation.
- `USE_EXACT_ALARM` in the manifest is auto-granted but Google Play restricts it
  to apps whose core purpose is alarms and reminders. If a Play review rejects
  it, delete that one line and rely on `SCHEDULE_EXACT_ALARM` plus the in-app
  prompt.

`functions/index.js` holds an **optional** server-side FCM backup. It is not
wired up: enabling it needs the Blaze plan and `firebase_messaging` added to the
app so device tokens get written to Firestore. The app is fully functional
without it.

---

## Project layout

```
lib/
  main.dart                     Firebase init, offline cache, notification bootstrap
  app.dart                      Theme, auth gate, per-uid controller injection
  theme.dart                    Material 3 theme + status/deadline colour logic
  firebase_options.dart         PLACEHOLDER — regenerate with flutterfire
  models/position.dart          Position + AppStatus + StatusChange
  services/
    auth_service.dart           Anonymous, email/password, account linking
    firestore_service.dart      CRUD, batched writes, status transitions
    notification_service.dart   Exact-alarm scheduling and rescheduling
    settings_service.dart       Reminder prefs in SharedPreferences
    seed_service.dart           Loads the converted sheet from assets
    csv_service.dart            CSV export + share sheet
  state/positions_controller.dart  Stream, filters, sorting, stats, reminder sync
  screens/                      sign_in, home, detail, edit, dashboard, settings
  widgets/                      position_card, status_chip, filter_sheet
assets/seed/positions.json      45 rows generated from PG_-_Sheet5.csv
firestore.rules                 Owner-only access with write validation
functions/                      Optional FCM backup (not required)
test/position_test.dart         Unit tests for date and status logic
```

### Data model

```
users/{uid}
  seedImported: bool
  positions/{positionId}
    university, programme, deadline, deadlineYearAssumed,
    funded, applicationFee, feeCurrency, link, country,
    status, notes, tags[], searchIndex,
    appliedAt, resultAt, createdAt, updatedAt,
    archived, reminderEnabled, history[]
```

Sorting and filtering happen client-side, so no composite Firestore indexes are
needed. At a few hundred positions that is the right trade; past a few thousand
you would move sorting server-side and add indexes.

---

## Dependency pinning, and why

Three packages have made breaking API changes recently, and the code targets a
specific side of each:

| Package | Pinned | Why |
|---|---|---|
| `flutter_local_notifications` | `^18.0.1` | v18 removed `uiLocalNotificationDateInterpretation` from `zonedSchedule`. On v17 you must add it back. |
| `share_plus` | `^10.1.2` | v11 replaced `Share.shareXFiles(...)` with `SharePlus.instance.share(...)`. |
| `flutter_timezone` | `^3.0.1` | v4 changed `getLocalTimezone()` to return an object instead of a `String`. |

The theme deliberately does not set `ThemeData.cardTheme` or `tabBarTheme`,
because those parameters changed type (`CardTheme` → `CardThemeData`) in recent
Flutter releases; card styling is applied per-widget via `appCardShape()`
instead.

---

## Known gaps

- Android only. Nothing here is iOS-hostile, but the manifest, Gradle config
  and notification permission flow are Android-specific and the iOS runner is
  not included.
- No CSV *import* from a file picker — import reads the bundled asset. Adding
  `file_picker` would be a small change.
- No attachment storage (CV versions, SOP drafts) — that would want Firebase
  Storage.
- `NotificationService.onSelectPosition` is a hook for deep-linking a tapped
  notification to the position detail screen; it is wired in the service but no
  navigator is attached to it yet.
