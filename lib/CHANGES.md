# Changes — wiring notes

Nine files. Eight replace existing ones; `lib/widgets/extract_from_text_sheet.dart`
is new. `android/DeadlineWidgetProvider.kt` goes in
`android/app/src/main/kotlin/com/example/phd_tracker/`, and
`android/res/layout/widget_deadlines.xml` replaces the one in
`android/app/src/main/res/layout/`.

---

## Required elsewhere

### `pubspec.yaml`

```yaml
  file_picker: ^8.1.7
```

**Check this does not wake the NDK before you commit to it.** After
`flutter pub get`:

```bash
flutter pub deps --style=compact | grep -E 'jni|code_assets'
```

`file_picker` should pull in only `flutter_plugin_android_lifecycle` and
`plugin_platform_interface`. If `jni` reappears the way it did with
`path_provider_android`, tell me and I will swap this for an
`ACTION_OPEN_DOCUMENT` call on the channel MainActivity already owns —
about 40 lines of Kotlin and no dependency.

`csv` is already a dependency and is now used at runtime, not just for export.

### `lib/main.dart`

Warm the preferences cache before the first frame, so the list can read the
swipe flag synchronously:

```dart
  await SettingsService.warmUp();
```

Put it next to the Firestore settings, before `runApp`. It is a single
already-cached channel call, so it does not meaningfully delay startup — and
without it the first build of the list falls back to the default (swipe on)
until something else touches preferences.

### `android/app/src/main/AndroidManifest.xml`

The widget receiver needs to accept the refresh broadcast:

```xml
        <receiver
            android:name=".DeadlineWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
                <action android:name="com.example.phd_tracker.WIDGET_REFRESH" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/deadline_widget_info" />
        </receiver>
```

Without the second `<action>` the button does nothing at all — the broadcast
is sent and silently dropped.

---

## What changed, and why

### Share always produces an entry

`ImportQueueService` now saves in every outcome:

| Outcome | Saved as |
|---|---|
| Confident extraction | Full position, normal tags |
| Low confidence | Full position plus a `needs-details` tag, original text in notes |
| Gemini failed, no key, page was a shell | Stub named after the site, `needs-details` tag, original text in notes |

The old behaviour dropped the third case into a review screen you had to
remember to visit. Losing a shared advert to a transient 503 is worse than
holding an untidy row, so nothing is discarded now.

`needs-details` is a tag rather than a new model field because tags already
flow through search, the card chips, the CSV export and the Firestore rules —
a new field would need all four touched.

Manual re-extraction from the edit screen passes `saveNote: false`, so
retrying never creates a second entry for the same advert.

### Manual add can paste and retry

The edit screen has an **Extract from text** button in the app bar. It opens a
paste sheet, runs Gemini, and fills the form — overwriting only fields the
model actually found, so a partial result tops up what you typed rather than
wiping it. Nothing is written until you press Save.

When an import failed, its original text is stored in the notes under a
`--- shared text ---` marker, and the sheet opens pre-filled with it. Retrying
a failed import is: open the entry, tap the button, tap Extract.

### CSV import from a file picker

`SeedService.loadCsv` matches columns by name, case-insensitively and loosely,
so "College", "University" and "Institution" all work. Unrecognised columns
are appended to the notes rather than dropped. Row ids are an FNV-1a hash of
university + programme + deadline, so re-importing the same file updates
instead of duplicating.

Dates: ISO is taken as-is; "15 Apr 2026" and "15.Apr.2026" parse; "06/03/2026"
is read day-first. An ambiguous `06/03` with no year is **not** guessed — it
stays null and the raw text goes into the notes. The confirmation dialog
reports how many rows had an inferred year and how many have no deadline at
all, before anything is written.

The bundled sheet is still importable from its own tile.

### Widget refresh

The button recomputes every "days left" from the stored deadline dates against
today. That is the part that actually goes stale — a snapshot taken on Monday
would otherwise still say "3 days" on Thursday. Day counts are now recomputed
on every draw, not just on the button press.

It cannot fetch *new* positions. A widget runs in the launcher's process with
no Dart VM and no Firestore, so new entries still appear only after the app
runs. Tapping anywhere else on the widget opens the app, which pushes a fresh
snapshot.

### Optimisations

`SettingsService` now caches the `SharedPreferences` instance instead of
awaiting `getInstance()` on every read. The list build path reads the swipe
flag per frame, so this one matters; the rest is tidiness.

`PositionCard` construction is hoisted out of the `Dismissible` in the list
builder, so the no-swipe path builds one widget instead of three.
