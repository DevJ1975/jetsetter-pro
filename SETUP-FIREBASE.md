# Firebase Backend Setup

JetSetter Pro uses Firebase Auth + Firestore for cross-device sync. The app talks to Firebase via **REST APIs only** — no Firebase SDK dependency required. This keeps the build lightweight and avoids needing `GoogleService-Info.plist` in the bundle.

> Replaces SETUP.md §4 (the old Supabase section). The codebase now calls `FirebaseService` / `FirebaseUser` directly — the old `Supabase*` typealiases have been removed.

---

## 1. Create the Firebase project

1. Go to **console.firebase.google.com** → Add project.
2. **Project name:** `JetSetter Pro` (or whatever you prefer)
3. **Google Analytics:** optional, your choice.

## 2. Get the two values JetSetter needs

You only need two strings from Firebase to make the REST integration work:

| Value | Where to find it |
|---|---|
| **Project ID** | Firebase Console → ⚙️ Project settings → General → "Project ID" |
| **Web API Key** | Firebase Console → ⚙️ Project settings → General → "Web API Key" |

Paste both into `Secrets.xcconfig`:

```
API_FIREBASE_PROJECT_ID = your-project-id
API_FIREBASE_API_KEY = AIza...your-api-key
```

> **Important — make Xcode actually load these.** The app reads both values from its Info.plist at runtime. Two pieces wire that up:
> 1. The `INFOPLIST_KEY_API_FIREBASE_PROJECT_ID` / `..._API_KEY` forwarders are **already in the project** (they map the build settings into the generated Info.plist).
> 2. Point the build at `Config/Secrets.xcconfig` as its **base configuration** (one-time): in Xcode, **File → Add Files…** → add `Config/Secrets.xcconfig` and **uncheck "Add to targets"** (it must not be a build member). Then select the **project** (blue icon) → **Info** → **Configurations** → expand **Debug** and **Release** → set the **"JetSetter Pro"** row's *Based on Configuration File* to **Secrets**.
>
> Without step 2, `$(API_FIREBASE_*)` resolves to empty and the app stays in "Firebase isn't configured" mode even with keys pasted.
>
> **Security:** `Config/` lives at the repo root — **outside** the app's synchronized source folder — so `Secrets.xcconfig` is **not** copied into the built `.app`. (It used to be bundled, which would have leaked real keys in the IPA; that's now fixed.)

## 3. Enable Firebase Auth

1. Firebase Console → **Authentication** → Get started
2. **Sign-in method** tab → enable **Email/Password**
3. (Optional later) enable **Apple** and **Google** sign-in for one-tap auth

## 4. Enable Firestore

1. Firebase Console → **Firestore Database** → Create database
2. **Start in production mode** — we'll set the rules below
3. Pick a region close to your users (`nam5` for North America, `eur3` for Europe)

## 5. Firestore data model

JetSetter writes one document per object, with a single `payload` field containing the JSON-encoded model. This keeps the migration mechanical and avoids needing to maintain Firestore field schemas.

Collections (all under each user's UID):

```
users/{uid}/expenses/{expenseID}        — fields: payload (JSON), updatedAt
users/{uid}/trips/{tripID}              — fields: payload, updatedAt
users/{uid}/walletItems/{itemID}        — fields: payload, updatedAt
users/{uid}/packingLists/{tripID}       — fields: payload, updatedAt
users/{uid}/disruptionEvents/{eventID}  — fields: payload, updatedAt
```

You don't have to create these collections manually — Firestore creates them on first write.

## 6. Firestore Security Rules

Paste these in **Firestore Database → Rules**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

These rules say: a user can only read/write documents under their own `users/{uid}/` path. Anonymous and cross-user access are blocked.

## 7. Test the connection

1. Build & run the app
2. Open Settings → Sign in / Create account
3. Enter an email + password (≥6 chars) → tap Sign up
4. Add a trip in Itinerary → Settings → Sync now
5. Open Firebase Console → Firestore → confirm a document appeared under `users/{your-uid}/trips/{tripID}`

If the sign-up call fails:
- Check API_FIREBASE_API_KEY is correct (Web API Key, not Server Key)
- Check Email/Password sign-in is enabled in Auth settings

## 8. Notes on architecture

- **REST-only**: This integration uses `URLSession` + Firebase's public REST endpoints (`identitytoolkit.googleapis.com` for auth, `firestore.googleapis.com` for data). No `import Firebase` anywhere.
- **JSON blob storage**: Each Firestore document stores the model as a single `payload` field (string). The Firebase console will show the documents but won't decompose individual fields — you'll see `payload: "{...}"`. If you later want rich queries (e.g., "all expenses > $100"), break the model out into proper Firestore field types.
- **Session caching**: Auth tokens are cached in `UserDefaults` under key `firebase_session`. The session refreshes automatically on expiry.
- **Offline behavior**: The REST integration has no offline mode. The app's UserDefaults-based local persistence already handles offline reads/writes; Firebase is a cross-device backup layer.

## 9. When to upgrade to the Firebase SDK

If you later need any of these, add the SDK via Swift Package Manager (`firebase-ios-sdk`):

- Firestore offline cache + automatic sync
- Real-time listeners (push updates from server)
- Firebase Cloud Messaging (push notifications)
- Firebase Storage for receipt image uploads
- Apple Sign-In via Firebase Auth

The SDK doesn't replace `FirebaseService` — it would coexist as a separate sync layer.

---

## Migrating from a Supabase instance

If you previously had data in Supabase:
1. Export each table to JSON (Supabase Studio → Table → Export)
2. Write a one-time import script that POSTs each record to the Firestore REST API under the appropriate user UID
3. Use the same JSON-payload-in-`payload`-field shape

Or: skip migration. v1.0 users are starting fresh anyway.
