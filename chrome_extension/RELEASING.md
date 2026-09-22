# Releasing the extension

## 1. Bake in the project

Edit `config.js`:

```js
export const DEFAULTS = {
  projectId: 'phd-tracker-abc12',
  apiKey: 'AIzaSy...',
  geminiKey: '',                    // leave empty — see below
  geminiModel: 'gemini-3.5-flash',
};
```

Both values are in `android/app/google-services.json`:
`project_info.project_id` and `client[0].api_key[0].current_key`.

Once `projectId` and `apiKey` are set, the options page hides the Firebase
fields behind an *Advanced* toggle and shows **Create account** alongside
**Sign in**, so someone who has never installed the app can still get started.

## 2. Leave the Gemini key empty

A packed extension is a zip file. Anyone who installs it can unpack it and
read `config.js`. An embedded Gemini key is quota anyone can spend, and on a
paid tier it is your invoice — with no way to tell whose traffic is whose.

Each user pastes their own key on the options page. Keys are free from
aistudio.google.com, so this is a one-minute step, not a barrier.

If you ever do want to serve extraction centrally, the shape is a Cloud
Function holding the key server-side and rate-limiting per authenticated uid.
That is a different project.

## 3. Understand what you are signing up for

Shipping your project ID means **every user's data lives in your Firebase
project, and you pay for it.**

The rules keep users isolated — `users/{uid}` is owner-only and there is no
collection-group read path — so this is not a privacy problem between users.
It is a cost and responsibility one:

- Firestore's free tier is 50 000 reads and 20 000 writes per day. Each app
  launch streams that user's whole collection, and entries now carry the full
  advert text, so reads add up faster than you would guess.
- Every account is a real account in your project. You are the one who can see
  the user list, and the one who has to delete it if someone asks.
- Anyone with the API key can call `accounts:signUp` directly and create
  accounts without the extension.

Two things worth doing before a public release:

**Enable App Check** with the reCAPTCHA or Play Integrity provider. It is the
supported way to stop clients you did not ship from writing to your project,
and without it the API key is an open door to your Auth endpoints (not to
other people's data, but to account creation and quota).

**Set a budget alert** in Google Cloud Billing. Even on Spark, knowing when
you approach the limits beats discovering it from users.

If you would rather not host anyone else's data, ship with `config.js` empty.
Users then paste their own project ID and key, exactly as now, and you carry
no cost or duty of care.

## 4. Package it

```bash
cd ext
zip -r ../phd-tracker-extension.zip . -x '*.git*' -x '*.DS_Store'
```

**Loading unpacked still needs Developer mode**, which is fine for you and
awkward to ask of anyone else.

**Handing someone a `.crx` file does not work.** Chrome stopped allowing
installs from outside the Web Store several years ago; a downloaded `.crx`
is refused, and the only exceptions are enterprise policy allowlists. Worth
verifying against current Chrome docs before you plan around it, but do not
assume self-hosting a `.crx` is an option.

So for real distribution:

**Chrome Web Store**, one-time developer registration fee (US$5 at the time
of writing), upload the zip, wait for review. You can publish **Unlisted** —
the extension is not searchable and only people with the link can install it,
which suits something built for yourself and a few friends. Unlisted still
goes through review.

## 5. Before you upload

- [ ] `config.js` has `projectId` and `apiKey` filled, `geminiKey` empty
- [ ] `firestore.rules` deployed, including the 40 000-character notes cap
- [ ] Email/Password **and** Anonymous enabled in Firebase Auth
- [ ] Bump `version` in `manifest.json` — the store rejects a re-upload at the
      same version
- [ ] Load the zip unpacked once and save a real advert end to end
- [ ] Sign out, **Create account** with a fresh email, save an advert, confirm
      it lands under the new uid and not yours
- [ ] Confirm `config.js` contains no Gemini key: `grep -i gemini config.js`

## A note on API key restrictions

Google Cloud lets you restrict an API key by HTTP referrer, which does not
apply to extension requests, and by API, which does. Restricting the Firebase
key to just Identity Toolkit and Firestore limits the damage if it is misused
elsewhere. It does not stop someone using it against your project — App Check
is the tool for that.
