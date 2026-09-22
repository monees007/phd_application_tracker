# PhD Tracker — Chrome extension

Right-click a job advert, and it is extracted and written straight into the
same Firestore board the Android app reads. No review step, matching the app's
behaviour.

**Not compiled or run.** Written and syntax-checked (`node --check` on every
script, JSON parsed, every `R.id`-equivalent reference traced by hand), but
never loaded into a browser. Expect to fix something on first load; the
service worker console is at `chrome://extensions` → Details → *Inspect views:
service worker*.

---

## Why this is better than sharing a link from the phone

The app fetches a URL over plain HTTP and sees only the HTML the server sent.
Most university job boards — ReachMee, Varbi, Workday, Taleo — build the
advert with JavaScript *after* load, so the app sees a navigation shell and
gives up. That was the Chalmers problem.

A content script reads the **rendered DOM**. Whatever you can see on screen,
the extension can read. ATS pages that the phone cannot handle at all work
here without any special handling.

---

## Install

1. `chrome://extensions` → turn on **Developer mode**.
2. **Load unpacked** → pick this folder.
3. Click the extension icon to open settings.

## Configure

**Firebase project.** Both values come from
`android/app/google-services.json`:

| Field | JSON key |
|---|---|
| Project ID | `project_info.project_id` |
| Web API key | `client[0].api_key[0].current_key` |

The Web API key is not a secret — it identifies the project, and your
Firestore rules are what actually protect the data.

**Sign in** with the same email and password as the app. This matters: entries
are written to `users/{uid}/positions`, so a different account means a
different, empty board.

> If the app is still on a guest (anonymous) login, open **Settings → Add
> email & password** there *first*. That links an email to the existing
> anonymous uid and keeps everything already saved. Creating a fresh account
> here instead would strand your data under the old anonymous uid, which
> cannot be recovered once you sign out of it.

**Gemini key** from aistudio.google.com. The *List models my key can use*
button queries the API rather than guessing, because model names change and
retired ones return 404.

---

## Use

Right-click on a page → **Save this advert to PhD Tracker**. Or select just
the advert text and right-click → **Save selected text to PhD Tracker**, which
skips the page-scraping heuristics entirely and is worth doing when a page has
several jobs on it.

What gets saved, always:

| Extraction | Entry | Notification |
|---|---|---|
| Confident | Full position | "Added: Chalmers University of Technology · …" |
| Low confidence | Full position, `needs-details` tag, page text in notes | "Saved as a note" |
| Gemini failed or key missing | Stub named after the site, `needs-details` tag, page text in notes | "Saved as a note" |

Nothing is discarded. A transient 503 costs you a tidy entry, not the advert.
The saved page text sits in the notes under a `--- shared text ---` marker,
which is exactly what the app's **Extract from text** button reads — so
retrying a failed extraction on the phone needs no copy-and-paste.

---

## Permissions, and why each one

| Permission | Reason |
|---|---|
| `contextMenus` | the right-click entries |
| `scripting` + `activeTab` | read the rendered page — **only** on the tab you right-clicked |
| `storage` | project config, refresh token, Gemini key |
| `notifications` | report the result |
| 4 × `host_permissions` | the Firebase, Google Identity and Gemini endpoints |

There is no `<all_urls>` and no persistent content script. The extension can
read a page only after you explicitly invoke it there.

---

## Things worth knowing

**The password is never stored.** Signing in exchanges it for a refresh token,
which is what gets kept and is used to mint short-lived ID tokens. Sign out
clears it.

**The Gemini key is stored in plain text** in extension storage. Fine for a
personal build, not fine for distributing this to anyone else. Revoke it in AI
Studio if the profile is ever compromised.

**The prompt and schema are duplicated** between `lib/gemini.js` here and
`gemini_service.dart` in the app. Change one and they will disagree about what
a field means. The alternative is a server in the middle, which is a lot of
infrastructure for a personal tracker — but it is a real maintenance cost, so
keep them in sync deliberately.

**The document shape must match `Position.toMap()`** and satisfy
`firestore.rules`. `lib/firestore.js` enforces the rules' string caps before
sending, because exceeding one produces a 403 that reads like an auth failure
and sends you debugging the wrong thing.

**No duplicate detection.** Saving the same advert twice creates two entries;
unlike the CSV importer, there is no content-hashed document id here, because
the app generates ids server-side. Worth adding if it becomes annoying.

**Firefox and Edge** both run Manifest V3, and nothing here uses a
Chrome-only API beyond the `chrome.*` namespace, which Firefox aliases. It is
untested on either.
