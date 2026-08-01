# JetSetter Pro — Session Handoff

_Last updated: 2026-07-31. Read this first, then `docs/DEVICE-TESTING-AND-RELEASE.md` to get the app onto a phone and out to TestFlight, then `docs/EXECUTION-BACKLOG.md` for the file:line task list._

## TL;DR
Taking this app from a polished **demo** to a **TestFlight-ready** iOS app. The entire **safe, non-blocked, code-only backlog is done and merged to `origin/main`** (each step build-verified Debug + Release). The next real milestone — signing + real backend → TestFlight — is **gated on the owner providing a few external inputs** (below). Don't re-do the completed work; don't re-litigate the locked decisions.

## Locked decisions (do not re-litigate)
- **Positioning:** business / frequent traveler.
- **Booking:** Duffel (NDC aggregator, agent of record) + free IATA **TIDS** — **no** full IATA accreditation.
- **Backend:** **Supabase** (Auth + Postgres, REST, no SDK). `SupabaseService` is the impl, and `supabase/` holds the schema-as-code. Firebase was retired — `API_FIREBASE_*` still exists in `AppSecrets` but no code reads it. Leave those keys blank.
- **Demo gating:** `MockDataService.isEnabled` is `#if DEBUG` (demo data in Debug, live in Release). Pro demo-unlock is DEBUG-only via `SubscriptionManager.demoUnlockEnabled`.
- **Deployment target:** iOS 18. FoundationModels + iOS-26 MapKit APIs are `@available`-gated, so you still need an **Xcode 26+ SDK to compile** (iOS 26 SDK).

## What's DONE (merged to origin/main, build-verified)
Phase 0 build-unblock (iOS 18 floor, permission strings incl. `NSCalendarsFullAccessUsageDescription`, background modes, `PrivacyInfo.xcprivacy`, iOS-26 API gating) · StoreKit hardening (real `Transaction.currentEntitlements`, default `isProSubscriber=false`, removed the free-Pro Settings button) · Firebase backend conversion + `INFOPLIST_KEY_API_FIREBASE_*` forwarders · GroundTransport real Uber/Lyft deep-link booking · **secrets-bundling fix** (`Config/` moved out of the synced app folder) · Document Vault encryption (`VaultCrypto` AES-GCM + Keychain key) · Firebase session token → Keychain · IRIS live trip/expense context block · APIClient retry/backoff + typed `unauthorized`/`rateLimited` errors · complete PII wipe in "Clear Local Data" · **in-app account deletion** (App Store Guideline 5.1.1(v)) · current Claude model id (`claude-sonnet-4-6`).

## ⚠️ CI existed but was never merged
`.github/workflows/ci.yml` + `.gitleaks.toml` did eventually get pushed — to the branch **`claude/status-markdown-audit-7wru46`**, never to `main`. (`.github/workflows/jetsetter-android-ci.yml` is likewise stranded on `claude/jetsetter-android-setup-ov8wy6`.) Because neither file is on `main`, **no CI runs on any pull request** — a PR into `main` showed zero check runs.

Both files are now carried on this branch, so CI runs here and merging to `main` turns it on repo-wide. The old workflow could not have worked as written anyway: it invokes `xcodebuild -scheme "JetSetter Pro"`, and there was no *shared* scheme until now, so a fresh checkout had no such scheme to resolve.

## ✅ Since resolved (2026-07-31)
- **Signing is unblocked.** `DEVELOPMENT_TEAM = 8V5XV2A6KE` and `CODE_SIGN_STYLE = Automatic` are set on both configs.
- **Shared scheme + unit-test target** now exist. The 7 Swift Testing suites in `JetSetter ProTests/` had **zero** references in the pbxproj and had never compiled; they are now in the project and **passing in CI**.
- **The app builds again.** It did not: `main` failed both Debug and Release against the iOS 26 SDK. Three pre-existing errors, all fixed — a missing `import CoreLocation` in `FlightDetailView` (`_LocationEssentials` members under `MEMBER_IMPORT_VISIBILITY`), a FoundationModels beta rename (`samplingMode:` → `sampling:`) in `ExpenseCategorizer`, and a test referring to `OpenScreenTool` after it became `NavigateTool`. None had ever surfaced because CI had never run.
- **Secrets actually reach the app.** The target had only ever forwarded `API_FIREBASE_*` into Info.plist, so all 27 other credentials — including the live Supabase pair — read nil no matter what was in `Secrets.xcconfig`. All 29 `AppSecrets.Key` cases are forwarded now.
- **Three crash-on-launch-path permission strings added** (mic, speech recognition, motion). Those paths — IRIS voice, Translator, Airport Map, In-Flight Tracker — used to terminate the app on a real device.

## 🔴 Still blocked on the owner
1. **Supabase project** — create it, enable Email/Password auth, apply the schema in `supabase/`, paste **Project URL + anon key** into `Config/Secrets.xcconfig`, and do the one-time **base-config wiring** step (`SETUP.md` §1). Without that step the keys still read nil.
2. **Travel API keys** (FlightAware, Amadeus, Expedia, Google Vision, Uber/Lyft) + a **Duffel** token — to flip real data on and close the disruption→rebook loop.
3. **Two product decisions** before the App Store Connect record exists: whether to keep the non-reverse-DNS bundle id `DevJ.JetSetter-Pro` (it is baked into the StoreKit product ids), and whether to stay iPad-compatible while portrait-only. Both are written up in `docs/DEVICE-TESTING-AND-RELEASE.md` §6.

## ▶️ Suggested next actions for the next session
1. Follow `docs/DEVICE-TESTING-AND-RELEASE.md` end to end: wire `Secrets.xcconfig`, run on a device, walk the per-feature checklist.
2. With **Supabase** configured: test sign-up → row write → cross-device restore, and the Delete Account flow end-to-end.
3. Remaining code items, still better paired with a signing/device pass: a **Widget Extension** target (Live Activities are declared and guarded but cannot render without one, and need an App Group), a **crash reporter** (SPM dep), and **TLS cert pinning** (needs the real proxy host + a `nonisolated`/`Sendable` `PinningDelegate`).

## Build / verify recipe (no signing needed)
```
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```
Notes: builds output to a repo-local `build/` dir (gitignored). There's also a **stale Jun-15 bundle in `~/Library/.../DerivedData`** — ignore it; verify against `build/<config>-iphonesimulator/JetSetter Pro.app/` or a fresh build. Build both Debug **and** Release (the `#if DEBUG` gates must hold in Release).

## Pointers
- `docs/EXECUTION-BACKLOG.md` — the verified, file:line backlog (Phases 0–2 + differentiators).
- `SETUP-FIREBASE.md` — Firebase setup incl. the base-config step + the secrets-bundling note.
- The differentiators to sequence right after TestFlight: closed **disruption → rebook (Duffel) → EU261/DOT compensation** loop, agentic IRIS, expense OCR+submit, baggage/Find My.
