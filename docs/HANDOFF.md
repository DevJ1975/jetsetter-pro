# JetSetter Pro — Session Handoff

_Last updated: 2026-06-22. Read this first, then `docs/EXECUTION-BACKLOG.md` for the file:line task list._

> ⚠️ **SUPERSEDED — current status (2026-07-08).** This note predates the July work. Corrections: (1) the backend is **Supabase**, not Firebase (`SupabaseService` is the impl; Firebase is fully removed — see `SETUP-SUPABASE.md`); (2) the `AUDIT_REPORT.md` "Feature Swarm Audit" verified bugs were remediated (commits `ff965f1`…`c0d461e`); (3) the Anthropic key now routes through the `claude-proxy` edge function (`supabase/functions/claude-proxy`); (4) **users' financial data (expenses/receipts/currency) is moving to on-device SQLite and will not be cloud-synced** (separate workstream). The historical notes below are kept for context.

## TL;DR
Taking this app from a polished **demo** to a **TestFlight-ready** iOS app. The entire **safe, non-blocked, code-only backlog is done and merged to `origin/main`** (each step build-verified Debug + Release). The next real milestone — signing + real backend → TestFlight — is **gated on the owner providing a few external inputs** (below). Don't re-do the completed work; don't re-litigate the locked decisions.

## Locked decisions (do not re-litigate)
- **Positioning:** business / frequent traveler.
- **Booking:** Duffel (NDC aggregator, agent of record) + free IATA **TIDS** — **no** full IATA accreditation.
- **Backend:** **Supabase** (GoTrue auth + PostgREST data, REST, no SDK). `SupabaseService` is the impl; Firebase is fully removed. **Financial data (expenses/receipts/currency) stays on-device in SQLite — not cloud-synced.**
- **Demo gating:** `MockDataService.isEnabled` is `#if DEBUG` (demo data in Debug, live in Release). Pro demo-unlock is DEBUG-only via `SubscriptionManager.demoUnlockEnabled`.
- **Deployment target:** iOS 18. FoundationModels + iOS-26 MapKit APIs are `@available`-gated, so you still need an **Xcode 26+ SDK to compile** (iOS 26 SDK).

## What's DONE (merged to origin/main, build-verified)
Phase 0 build-unblock (iOS 18 floor, permission strings incl. `NSCalendarsFullAccessUsageDescription`, background modes, `PrivacyInfo.xcprivacy`, iOS-26 API gating) · StoreKit hardening (real `Transaction.currentEntitlements`, default `isProSubscriber=false`, removed the free-Pro Settings button) · Supabase backend conversion + `INFOPLIST_KEY_API_SUPABASE_*` forwarders · GroundTransport real Uber/Lyft deep-link booking · **secrets-bundling fix** (`Config/` moved out of the synced app folder) · Document Vault encryption (`VaultCrypto` AES-GCM + Keychain key) · Supabase session token → Keychain · IRIS live trip/expense context block · APIClient retry/backoff + typed `unauthorized`/`rateLimited` errors · complete PII wipe in "Clear Local Data" · **in-app account deletion** (App Store Guideline 5.1.1(v)) · current Claude model id (`claude-sonnet-4-6`).

## ⚠️ Held back locally (NOT pushed)
`.github/workflows/ci.yml` + `.gitleaks.toml` are **written and present in the working tree but untracked**. Pushing them was **rejected** because the GitHub PAT lacks the **`workflow`** scope. **Do not** bundle these into another commit/push — the whole push will be rejected. To land them: owner adds the `workflow` scope to the PAT (or adds the workflow via the GitHub Actions web UI), then push them.

## 🔴 Blocked on the owner (the real unlocks)
1. **Apple Developer Team ID (10-char) + a real reverse-DNS bundle id** (currently `DevJ.JetSetter-Pro`). #1 unlock: signing, entitlements, IAP, Live Activity/Widget target, TestFlight.
2. **Supabase project** — create it, enable Email auth + run the schema (in `SETUP-SUPABASE.md`), paste **Project URL + anon key** into `Config/Secrets.xcconfig`, and do the one-time **base-config wiring** step in Xcode (also in `SETUP-SUPABASE.md`). Without that base-config step the keys read nil.
3. **Travel API keys** (FlightAware, Amadeus, Expedia, Google Places/Vision, Uber/Lyft) + a **Duffel** token — to flip real data on and build the disruption→rebook loop.

## ▶️ Suggested next actions for the next session
1. If the owner has the **Team ID + bundle id**: set `DEVELOPMENT_TEAM` + `PRODUCT_BUNDLE_IDENTIFIER` (both build configs), create the `.entitlements` (App Groups, Push time-sensitive, PassKit), and register the App ID capabilities. Then archive for a device / TestFlight.
2. If the owner has **Supabase**: confirm the base-config wiring, then test sign-up → Supabase row write → cross-device restore, and the new Delete Account flow end-to-end.
3. Otherwise, the only remaining code items are **risky-blind** and better paired with the signing pass: **XCTest target + shared scheme**, a **crash reporter** (SPM dep), and **TLS cert pinning** (needs the real proxy host + a `nonisolated`/`Sendable` `PinningDelegate`). Don't attempt the pbxproj target/SPM additions blind.

## Build / verify recipe (no signing needed)
```
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```
Notes: builds output to a repo-local `build/` dir (gitignored). There's also a **stale Jun-15 bundle in `~/Library/.../DerivedData`** — ignore it; verify against `build/<config>-iphonesimulator/JetSetter Pro.app/` or a fresh build. Build both Debug **and** Release (the `#if DEBUG` gates must hold in Release).

## Pointers
- `docs/EXECUTION-BACKLOG.md` — the verified, file:line backlog (Phases 0–2 + differentiators).
- `SETUP-SUPABASE.md` — Supabase setup incl. the base-config step, schema, and edge functions.
- The differentiators to sequence right after TestFlight: closed **disruption → rebook (Duffel) → EU261/DOT compensation** loop, agentic IRIS, expense OCR+submit, baggage/Find My.
