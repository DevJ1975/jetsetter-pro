# JetSetter Pro — Execution Backlog (Demo → TestFlight → App Store)

> Source: 6-domain, adversarially-verified production-readiness audit (20 agents).
> Generated 2026-06-22. Goal: business/frequent-traveler positioning; in-app booking via **Duffel** (NDC aggregator, no IATA accreditation) + free **IATA TIDS**; first milestone = a real working app on **TestFlight**.
> Severity: **P0** = blocks archive/review · **P1** = needed for a credible release · **P2** = polish. **BLOCKED-ON** = external dependency, not code.

---

## Corrections to the first-pass evaluation (read first)

The deep audit overturned several earlier assumptions — don't act on the old ones:

- **Active demo trip is `Boston Pitch Day` (DL2244, Gate B27, Seat 1A)** — *not* Tokyo/AA169. Any "active trip" context/verify logic must expect the Boston DL flight first.
- **`MockDataService.isEnabled` has 30 read-only call sites** (not ~20), incl. two missed in `TripJournalView.swift:31,301`. Flipping it the moment an API key exists would send Booking/RentalCar/GroundTransport/Vision/FlightTracker to **live endpoints with empty keys** — use a `#if DEBUG` definition, never auto-flip-on-key.
- **`SITAWorldTracerService` already exists** (`traceBag(tagNumber:)` wired) — baggage work is an `activate/poll` layer, not a from-scratch service.
- **Persistence is Firebase, not Supabase** — `SupabaseService` is a `typealias` to `FirebaseService` (`FirebaseService.swift:426`); `SETUP.md §4` still has a stale Supabase section to delete.
- **`ExpenseExportView` already loads connected providers** via `ExpenseExportRegistry.connectedProviders()` — not hardcoded to email.
- **Claude model `claude-sonnet-4-20250514` is retired (2026-06-15)** → would 404 today. Migrate to `claude-sonnet-4-6` (current Sonnet) or `claude-opus-4-8`.
- **Camera/Location/Photos/Background-modes usage strings are present** (added in Phase 0). The remaining permission gap was **`NSCalendarsFullAccessUsageDescription`** (now added — `CalendarService.swift:49` calls `requestFullAccessToEvents()`).

---

## External dependencies you must provision (gate most of Phase 1)

These are **human/account actions**, not code. Almost every P0 below is blocked on one of them:

1. **Apple Developer Team ID** + a real reverse-DNS **bundle id** (replace `DevJ.JetSetter-Pro`), and register the App ID with App Groups / Background Modes / In-App Purchase / Push capabilities.
2. **App Store Connect**: paid-apps/banking agreement + subscription **products** (monthly/annual) under the final bundle id, a hosted **Privacy Policy URL** + **Support URL**.
3. **API keys** (each empty today): Anthropic, FlightAware, Google Places + Vision, Eventbrite, Expedia (prod), Amadeus (prod), Uber/Lyft.
4. **Duffel** account + API token (real booking + rebooking).
5. **Firebase** project (Auth + Firestore + FCM) — gates sync, disruption polling, account-delete.
6. **A secrets proxy backend** (e.g. Cloud Function) — Anthropic/Vision/Ramp secrets must **not** ship client-side.
7. Enterprise contracts (later): **SITA WorldTracer** (baggage), Expedia/Amadeus partner agreements.

---

## Phase 0 — Build Unblock  ✅ mostly done

| # | Item · file(s) | Status |
|---|---|---|
| 0.A | Deployment target 26.4→18.0; 5 usage strings; background modes; PrivacyInfo; FoundationModels + MapKit `@available` gating | ✅ done, build-verified, merged |
| 0.6 | **`NSCalendarsFullAccessUsageDescription`** · `project.pbxproj` | ✅ added (prevents EventKit SIGABRT) |
| 0.1 | **`DEVELOPMENT_TEAM`** both configs | ⏳ BLOCKED-ON Apple Developer team |
| 0.2 | **Real bundle id** + App ID capabilities | ⏳ BLOCKED-ON Apple Developer team |
| 0.3 | **`.entitlements` file** (App Groups first) + `CODE_SIGN_ENTITLEMENTS` | ⏳ after 0.2 |
| 0.4 | **Wire `Secrets.xcconfig` as base config + ~19 `INFOPLIST_KEY_API_*` forwarders** (zero today → every key reads nil) | ☐ P0 |
| 0.5 | Add Amadeus + Duffel `Key` enum cases · `AppSecrets.swift` (avoid dup-case) | ☐ P1 |
| 0.7 | `NSSupportsLiveActivities=YES` + Widget Extension target (extract `FlightActivityAttributes` to shared file) | ☐ P0, after 0.2 |
| 0.9 | **Do all pbxproj capability/target edits in Xcode UI in ONE pass** (4 domains touch this file; hand-edited UUIDs are risky) | ☐ P0 |

---

## Phase 1 — Demo → Real Data + StoreKit + Backend

### 1A · The master flag (one contract — sequence carefully)
| # | Item · file(s) | P | Blocked |
|---|---|---|---|
| 1.1 | **ONE `MockDataService.isEnabled` definition** — `#if DEBUG` computed (+QA override), keep `SystemLanguageModel` behind `if #available(iOS 26,*)` | P0 | — |
| 1.2 | Re-audit/`#if DEBUG`-guard all **30** call sites together (incl. `TripJournalView:31,301`) | P0 | 1.1 |
| 1.3 | **Decouple Pro auto-unlock** from the flag · `JetSetter_ProApp.swift:35` | P0 | 1.1 |
| 1.4 | Separate **seed gate** (`shouldSeedDemoData`) · `MockDataService:32`, `DemoSeeder:24` | P1 | 1.1 |

### 1B · Stub call sites with NO real fallthrough (empty screens if flag flips)
| # | Item | P | Blocked |
|---|---|---|---|
| 1.5 | LocalExperience real pipeline (`LocalExperienceService`: Places + Eventbrite + Claude rank) | P0 | Google Places + Eventbrite |
| 1.6 | DocumentVault encrypted persistence (`DocumentVaultStore`, CryptoKit AES-GCM; never persist `docNumberClear`) | P0 | — |
| 1.7 | Bag tracking on check-in — add `activate(flightNumber:)`/poll on existing `SITAWorldTracerService` | P1 | SITA contract |

### 1C · Partially-real (DEBUG-guard the mock short-circuit; real path exists)
| # | Item | P | Blocked |
|---|---|---|---|
| 1.8 | AIService: `#if DEBUG`-guard mock; **migrate model id**; keep iOS-26 gate | P1 | Anthropic key |
| 1.9 | IRIS Claude fallback + guard canned (`IRISAgentService.swift:66-69,84-87`) | P0 | Anthropic key |
| 1.10 | IRIS context block (`IRISContext`: trip/flight/expense/loyalty from UserDefaults) | P0 | 1.9 |
| 1.11 | Booking/FlightTracker/GroundTransport/Vision/RentalCar/PackingList/Home/InFlight mock guards (PackingList: fix silent Tokyo catch-fallback `:81-91`) | P1 | per-provider keys |
| 1.12 | GroundTransport real booking → deep link + App Store fallback (`LSApplicationQueriesSchemes`) | P1 | — |
| 1.13 | **Duffel rebooking eligibility** (`DisruptionResponseEngine.swift:252`): real `GET /air/orders/{id}`; selector MUST filter `itemType == .boardingPass` | P0 | Duffel token |
| 1.14 | Amadeus/Expedia **prod hosts** + HTTP-status guard before token decode | P1 | prod creds |

### 1D · StoreKit (monetization is 100% bypassed today — release blocker)
| # | Item | P | Blocked |
|---|---|---|---|
| 1.15 | Implement real `refreshEntitlements()` (`Transaction.currentEntitlements`, keep `@MainActor`) | P0 | — |
| 1.16 | `isProSubscriber` default **`false`** (`SubscriptionManager:30`) — land WITH 1.15 | P0 | 1.15 |
| 1.17 | Remove/`#if DEBUG` `unlockForTesting` + the Settings developer section (`SettingsView:447-473`) — also DEBUG-guard the caller at `:451` or Release won't compile | P0 | 1.3 |
| 1.18 | Apply `.premiumGate` on the 5 paywall-promised view bodies (note: `ExpenseTrackerView`/`IRISChatView` are **root tabs** in `ContentView.swift:44,49`) | P0 | 1.15-1.16 |
| 1.19 | Wire `Products.storekit` to a **shared** Run scheme + IAP capability + ASC products | P1 | Apple/ASC |
| 1.20 | Paywall load-error retry + intro-offer ("Free 1 week, then…") display | P2 | 1.19 |

### 1E · Backend / proxy (assumed by 3 P0 fixes — exists nowhere)
| # | Item | P | Blocked |
|---|---|---|---|
| 1.21 | Secrets **proxy backend** (Anthropic/Vision/Ramp off-device; prefer on-device VisionKit for OCR) | P0 | proxy infra |
| 1.22 | Firebase project + Auth + Firestore rules + **in-app sign-in flow** (may not exist) | P0 | Firebase |
| 1.23 | **Account deletion** (Guideline 5.1.1(v)) — Identity Toolkit `accounts:delete` + Firestore subtree wipe (no list API today) + Keychain wipe | P0 | 1.22 |
| 1.24 | Delete stale Supabase section in `SETUP.md §4`; add Firebase rows | P1 | — |

---

## Phase 2 — TestFlight Hardening

**2A Security:** one `VaultCrypto`/Keychain primitive (`WhenUnlockedThisDeviceOnly`); Firebase session token → Keychain (off plaintext UserDefaults); DocumentVault biometric fail-closed; PII UserDefaults → encrypted store under `NSFileProtectionComplete`; fix "wipe all PII" (correct prefix `jetsetter_offline_kit_`); **one** TLS-pinning impl (`PinningDelegate` must be `nonisolated`/`Sendable`); APIClient `.unauthorized`/`.rateLimited` + retry/backoff; **stop bundling `Secrets.xcconfig`/`Products.storekit` in the `.app`** (UNSAFE — they sit under the synced root and ship in the IPA); ATS hardening.

**2B Privacy/Review:** Privacy Policy + Support URL; reviewer demo/sandbox account (Pro is gated once auto-unlock is removed); export-compliance (`ITSAppUsesNonExemptEncryption`); fill `PrivacyInfo` `NSPrivacyCollectedDataTypes`. (ATT and microphone are **not** needed — document so nobody adds them.)

**2C Tests/CI/Observability (entirely unowned today):** add a crash reporter (Crashlytics/Sentry); add an XCTest/Testing target + **shared** scheme; CI workflow (`xcodebuild build/test` on PR) + secret scanner (gitleaks).

---

## Shared primitives — assign ONE owner before parallelizing
`MockDataService.isEnabled` · `PinningDelegate` · `VaultCrypto`/Keychain · `APIError` · `project.pbxproj` — each is touched by 3–5 work-streams. Land each once or they get rebuilt/conflict.

## Differentiators — sequence right after TestFlight (the moat vs Flighty/TripIt/Navan)
1. **Closed disruption → rebook (Duffel) → EU261/DOT compensation** (no competitor automates the claim — the wedge).
2. **Agentic IRIS** grounded in the real itinerary (acts: submit expenses, check in, rebook).
3. **Expense OCR + one-tap submit** to connected Brex/Ramp/Expensify/Divvy.
4. **Baggage / Find My + SITA** ("where is my bag" with carrier data).

All four depend on the same plumbing (1.1 flag, 1.21 proxy, 1.22 Firebase auth) — land that once first.
