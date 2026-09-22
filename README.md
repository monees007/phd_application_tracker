
<h1 align="center">PhD Tracker</h1>

<p align="center">
  Track PhD and research position applications — deadlines, statuses and
  reminders — with one-tap capture from your phone or your browser.
</p>

<p align="center">
  <a href="https://github.com/monees007/phd_application_tracker/releases/download/v1.0.0/app-arm64-v8a-release.apk">
    <img alt="Download the Android app"
         src="https://img.shields.io/badge/Download-Android%20APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
  </a>
  &nbsp;
  <a href="https://github.com/monees007/phd_application_tracker/releases/download/v1.0.0/chrome_extension.crx">
    <img alt="Download the Chrome extension"
         src="https://img.shields.io/badge/Download-Chrome%20Extension-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white" />
  </a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-lightgrey" />
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white" />
  <img alt="Backend" src="https://img.shields.io/badge/backend-Firebase-FFCA28?logo=firebase&logoColor=black" />
</p>

---

## What it does

Applying for PhD positions means juggling a few dozen adverts across as many
university job boards, each with its own deadline and its own idea of what an
application looks like. A spreadsheet handles that until the day you miss a
closing date because you never opened it.

PhD Tracker keeps the same list, but it reminds you, and it captures new
positions in one tap instead of ten minutes of copy-and-paste.

### Three boards

| Board | What's on it |
|---|---|
| **To apply** | Open positions you haven't submitted to |
| **Pending** | Submitted, waiting on a decision (including interview stage) |
| **Decided** | Accepted, rejected or withdrawn |

Status changes are timestamped and kept as a per-position history, so you can
see when you applied and when the answer came back.

### Deadline reminders

Three days before, and on the day itself — both configurable, along with the
time of day. Reminders only fire while a position is still marked *Not
applied*, because being nagged to apply for something you already submitted is
just noise.

They're scheduled as on-device exact alarms rather than push notifications, so
they work with no network, cost nothing to run, and survive a reboot.

### One-tap capture

Share a job advert to the app, or right-click it in Chrome. The page is read,
sent to Gemini for extraction, and saved as a proper entry — university,
title, deadline, funding, fee, link and tags — with no review step.

If the model isn't confident, or the API call fails, the advert is **still**
saved: as an entry tagged `needs-details` with the full text kept in its
notes, ready to retry from the edit screen. Nothing you capture is lost to a
transient error.

The whole advert is archived with every entry, so a position survives its
source page being taken down.

### Everything else

- **CSV import** from any spreadsheet export — columns matched by name, and
  re-importing the same file updates rather than duplicates
- **CSV export**, so the data is never trapped in the app
- **Home screen widget** showing your next five deadlines with live day counts
- **Search and filters** by university, funding, open-only, archived
- **Overview** with a status breakdown, the next 30 days, and the deadlines
  that passed without an application
- **Offline** — the board works on a plane and syncs when you reconnect
- **Dark mode**, following the system setting

---

## Install

### Android app

Download the APK from the button above. You'll need to allow installation from
unknown sources; Android will prompt you.

On first launch:

1. **Sign in** — email and password, or continue as a guest. Guests can attach
   an email later from Settings without losing anything.
2. **Settings → AI extraction** — paste a [Gemini API
   key](https://aistudio.google.com/app/apikey). *Fetch available models*
   queries your key rather than guessing at a model name.
3. **Settings → Import** — pull in an existing CSV if you have one.
4. Grant notification permission when asked, and the *Alarms & reminders*
   permission if Settings shows a warning about exact alarms.

### Chrome extension

1. Download and unzip.
2. `chrome://extensions` → enable **Developer mode** → **Load unpacked** →
   select the folder.
3. Click the extension icon and fill in the settings page: your Firebase
   project ID and Web API key, the same email and password as the app, and
   your Gemini key.

> **Sign in to the app first if you're on a guest account.** Open
> Settings → *Add email & password* there before configuring the extension.
> That links an email to your existing account and keeps what you've already
> saved. Creating a new account in the extension instead writes to a different
> user, and the old anonymous board can't be signed back into.

Then right-click any job advert → **Save this advert to PhD Tracker**. Select
just the advert text first if the page lists several positions.

The extension reads the *rendered* page, so applicant tracking systems that
build their adverts with JavaScript — ReachMee, Varbi, Workday — work here
even though a plain fetch from the phone can't see them.

---

## Building from source

Requires Flutter 3.27 or newer and JDK 17.

```bash
git clone https://github.com/YOUR-USERNAME/phd-tracker.git
cd phd-tracker

dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id>

firebase deploy --only firestore:rules

flutter pub get
flutter run
```

In the [Firebase console](https://console.firebase.google.com), enable
**Anonymous** and **Email/Password** under Authentication → Sign-in method,
and create a Firestore database.

Deploying the rules isn't optional — the defaults block every read and write,
and the app will show "Could not load your positions".

---

## Your data

Everything lives under `users/{uid}` in **your own** Firebase project. The
security rules are owner-only, with no collection-group read path that could
leak across accounts. Nothing is sent anywhere except your Firestore and, when
you capture an advert, the Gemini API.

Your Gemini API key is stored in plain text — in app preferences on the phone,
in extension storage in Chrome. That's fine for a personal build and not fine
for handing someone a copy with your key still in it. Revoke it in AI Studio
if a device goes missing.

---

## Licence

MIT. See [LICENSE](LICENSE).
