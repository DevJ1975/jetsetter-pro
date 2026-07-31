# Device Testing & Release Runbook

How to get JetSetter Pro onto a physical iPhone, exercise every feature, and ship
it to TestFlight. Written 2026-07-31, against `CURRENT_PROJECT_VERSION = 2`.

`SETUP.md` covers first-time API-key setup and is still the reference for that.
This document is the path from "clone" to "installed on my phone" to "on TestFlight".

---

## 0. What was blocking this, and what changed

Three defects made a device build effectively untestable. All three are fixed in
the project now — listed here so you know what to expect if you had tried before.

| Was broken | Effect on a real phone | Now |
|---|---|---|
| Only `API_FIREBASE_*` was forwarded into Info.plist — the *retired* backend. The other 27 credentials, including the live Supabase pair and the Duffel proxy, were never passed to the app. | A Release build defaults to beta/live mode, so every service read a nil key and fell back to mock data or an empty state. Nothing real worked, regardless of what was in `Secrets.xcconfig`. | All 29 `AppSecrets.Key` cases are forwarded. |
| `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, and `NSMotionUsageDescription` were absent while the code used those APIs. | Hard crash — iOS kills an app that touches a privacy-gated API with no usage string. IRIS voice, Translator, Airport Map pedometer, and In-Flight Tracker each terminated the app. | All three added. |
| No shared scheme — `xcshareddata/` held only the Xcode Cloud manifest. | `xcodebuild -scheme "JetSetter Pro"` and Xcode Cloud could not resolve a scheme from a fresh clone. | Shared scheme added, archiving under Release. |

Also added: `ITSAppUsesNonExemptEncryption = NO` (TestFlight uploads no longer
stall on the export-compliance prompt), `NSSupportsLiveActivities = YES`, a
`JetSetter ProTests` unit-test target, and `Config/Products.storekit` wired into
the Run action so subscriptions are testable before the products exist in App
Store Connect.

---

## 1. One-time Xcode setup

### 1.1 Wire up `Secrets.xcconfig` — do not skip this

This is the single most common failure. The forwarders added to the target read
`$(API_…)` build settings; those settings only exist if `Secrets.xcconfig` is set
as the **project-level base configuration**. Without this step every key still
resolves to nil and you are back to empty states.

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Then, per `SETUP.md` §1: **File → Add Files…** → select `Config/Secrets.xcconfig`
(uncheck *Copy items if needed*) → project navigator → **JetSetter Pro** project →
**Info** tab → **Configurations** → set **both Debug and Release** to `Secrets`.
The target inherits it.

Fill in only the keys you have. Blank values are safe — `AppSecrets` maps empty
to nil and each call site falls back to mock data.

**Verify it worked.** Build, then point the preflight at the built app:

```bash
python3 scripts/preflight.py \
  --app "$(ls -d ~/Library/Developer/Xcode/DerivedData/JetSetter_Pro-*/Build/Products/Debug-iphoneos/'JetSetter Pro.app' | head -1)"
```

It reports `credentials set .... N/29` and names the ones that took. The keys are
always *present* — the target forwards them unconditionally — so the tell is
whether they expanded to a value or to an empty string. `0/29` means the
base-configuration step did not take, and the app will run entirely on mock data
no matter what you put in `Secrets.xcconfig`.

Run it with no arguments any time to check the project itself (every
`AppSecrets.Key` forwarded, a usage description for every privacy API in use, a
shared scheme whose targets resolve). CI runs it on every push.

### 1.2 Signing

`DEVELOPMENT_TEAM = 8V5XV2A6KE` and `CODE_SIGN_STYLE = Automatic` are already set,
so signing should resolve on its own. In **Signing & Capabilities**, confirm
*Automatically manage signing* is checked and the team is right.

No `.entitlements` file exists, and that is deliberate — the app currently needs
none. Local notifications, background fetch/processing, Keychain, and CryptoKit
all work without one. Do not add entitlements speculatively: an entitlement the
App ID has not been provisioned for makes the build fail to install at all.

---

## 2. Install on your iPhone

1. Connect the iPhone, trust the Mac, and enable **Developer Mode** on the device
   (Settings → Privacy & Security → Developer Mode) — required on iOS 16+.
2. Select the **JetSetter Pro** scheme and your device as the run destination.
3. **Product → Run** (⌘R).
4. First launch only: Settings → General → VPN & Device Management → trust the
   developer certificate.

Deployment target is iOS 18.0, so the device needs iOS 18 or later. Building
requires an **Xcode 26+ SDK** — FoundationModels and the iOS 26 MapKit APIs are
`@available`-gated in source but still need the newer SDK to compile.

### Debug vs Release on device

- **⌘R (Debug)** — defaults to **demo mode**: the seeded Jordan Ellis persona,
  populated trips/expenses/bags, and the scripted ~25s DL 1423 disruption push.
  Best for exercising UI and flows without any API keys.
- **Release** (Edit Scheme → Run → Build Configuration → Release) — defaults to
  **beta mode**: live services, real and empty states. This is what TestFlight
  users get. Test here before you ship.

You can flip between the two at runtime in **Settings → App Mode**, so a single
install covers both. `DemoMode.isOn` is the single source of truth and drives
`MockDataService.isEnabled` at all 30 call sites.

---

## 3. What is live vs mock, per credential

Every feature works without keys — it just shows seeded or empty data. Add a key
to make that feature live.

| Credential | Makes this live |
|---|---|
| `API_SUPABASE_URL` + `API_SUPABASE_ANON_KEY` | Account sign-up/sign-in, cross-device sync, account deletion. **The active backend — set this first.** |
| `API_FLIGHTAWARE` | Flight tracking, disruption monitoring, departure board |
| `API_ANTHROPIC` | IRIS agent, smart packing list, AI intelligence cards |
| `API_AMADEUS_CLIENT_ID` + `_SECRET` | Check-in flow, disruption rebooking search |
| `API_DUFFEL_PROXY_URL` + `_KEY` | Flight booking and rebooking (via `server/duffel-proxy`; the Duffel token stays server-side) |
| `API_EXPEDIA_CLIENT_ID` + `_SECRET` | Hotel search and booking |
| `API_UBER_CLIENT_ID` + `_SECRET`, `API_LYFT_CLIENT_ID` + `_SECRET` | Ground transport ride estimates |
| `API_ENTERPRISE` / `API_HERTZ` / `API_NATIONAL` | Rental car availability |
| `API_GOOGLE_VISION` | Receipt OCR |
| `API_SITA_WORLDTRACER` | Luggage tracking |
| `API_RAMP_*`, `API_BREX_CLIENT_ID`, `API_BILL_SPEND_TOKEN` | Expense submission to those providers |

Declared but not consumed by any code today: `API_FIREBASE_PROJECT_ID`,
`API_FIREBASE_API_KEY` (backend retired in favour of Supabase),
`API_EXPENSIFY_PARTNER_KEY`, `API_DIVVY_CLIENT_ID`. Leave them blank.

---

## 4. On-device test checklist

Run this in **Debug/demo** first (everything populated), then repeat the starred
items in **Release/beta** with real keys.

### Permissions — test these first
These are the paths that used to crash. Each should now show a system prompt with
the wording below, and continue working after you allow.

- [ ] **Microphone + Speech** — More → IRIS, tap the mic. Two prompts.
- [ ] **Motion** — More → Airport Map (pedometer), and More → In-Flight Tracker (altimeter).
- [ ] **Camera** — Expenses → Scan Receipt; Itinerary → scan boarding pass; Translator camera.
- [ ] **Photos** — attach a receipt; save a boarding pass to the library.
- [ ] **Location** — Home, Departure Optimizer, Ground Transport.
- [ ] **Calendar** — add a flight to the calendar (full-access prompt on iOS 17+).
- [ ] **Face ID** — unlock Document Vault.
- [ ] **Notifications** — allow on first launch; confirm the demo disruption push lands ~25s after enabling demo mode.

### Tabs
- [ ] **Home** — greeting, live weather, leave-now and check-in intelligence cards
- [ ] **Itinerary** — trip list, add manual flight / hotel / rental car, boarding-pass scan
- [ ] **IRIS** ★ — chat, voice, suggestion cards, confirmation cards, memory, learned profile
- [ ] **Expenses** — list, add, categorise, scan receipt, currency conversion
- [ ] **More** — everything below

### More → all features
- [ ] IRIS — Travel Agent (Pro-gated) ★
- [ ] Trip Disruption AI ★ — alerts and automatic rebooking
- [ ] Proactive Intelligence — history
- [ ] Smart Packing List ★
- [ ] Document Vault — add, encrypt, Face ID unlock
- [ ] Local Experiences ★
- [ ] Currency & Expenses — live rates, budget chart
- [ ] Ground Transport ★ — Uber/Lyft estimates, deep-link into each app
- [ ] Rental Cars ★
- [ ] Departure Optimizer ★ — traffic + TSA wait
- [ ] Book Flights & Hotels ★
- [ ] Offline Kit — pre-cache, then verify in Airplane Mode
- [ ] Departure Board ★ — split-flap
- [ ] Airport Map — pedometer walk estimates
- [ ] Identity & Trusted Traveler
- [ ] Luggage Tracker ★ — AirTag + WorldTracer
- [ ] Travel Wallet — boarding passes, add to Apple Wallet (PassKit)
- [ ] Miles & Loyalty
- [ ] Visa Requirements
- [ ] Submit Expenses ★ — email PDF, and any provider you have keys for
- [ ] In-Flight Tracker — altitude, GPS, phase detection
- [ ] Translator — on-device translation, live camera scan
- [ ] Travel Essentials
- [ ] Trip Journal — photo scrapbook
- [ ] Carbon Footprint
- [ ] Settings — preferences, notifications, **App Mode** toggle (demo ↔ beta),
      **Clear Local Data** (full PII wipe), **Delete Account** ★ (App Store
      Guideline 5.1.1(v) — needs Supabase configured)
- [ ] About — tour, founder

### Subscriptions
With the StoreKit config active (⌘R only), the paywall works without App Store
Connect products:

- [ ] Paywall lists Pro Monthly ($9.99) and Pro Annual ($69.99), each with a 1-week free trial
- [ ] Purchase completes and unlocks Pro gates
- [ ] Restore Purchases works
- [ ] Debug-only: `SubscriptionManager.unlockForTesting()` sets `demoUnlockEnabled`
      and grants Pro without a purchase. It defaults to `false`, and the `#if DEBUG`
      gate means a Release build never gives Pro away.

To test against the **real** sandbox instead, Edit Scheme → Run → Options →
StoreKit Configuration → *None*, and create the products in App Store Connect
with the exact ids in `SubscriptionTier`:
`DevJ.JetSetter-Pro.subscription.pro.monthly` and `…pro.annual`.

### Background behaviour
- [ ] Background refresh — the disruption poll registers `com.jetsetter.pro.disruption.poll`.
      Force it in Xcode with the debugger paused:
      `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jetsetter.pro.disruption.poll"]`
- [ ] Notification tap routes to the right screen rather than always Home

---

## 5. TestFlight

1. Bump **Build** (`CURRENT_PROJECT_VERSION`) — it is `2` now, and every upload
   for a given marketing version needs a higher number than the last.
2. Destination **Any iOS Device (arm64)** → **Product → Archive**.
   The scheme archives under Release and excludes the test target.
3. Organizer → **Distribute App** → **TestFlight & App Store**.
4. Export compliance should no longer prompt — `ITSAppUsesNonExemptEncryption` is
   declared `NO` in the build settings. See the caveat in §6.
5. Add a row to `BETA_BUILDS.md`.

App Store Connect will also need, before external testing: privacy nutrition
labels (the app collects trip, expense, and document data), a support URL, and a
privacy-policy URL. `PrivacyInfo.xcprivacy` already declares the four required
API-usage reasons and `NSPrivacyTracking = false`.

---

## 6. Open items — your call

These are judgement calls I deliberately did not make unilaterally.

1. **There is no live Supabase project.** `supabase/` fully defines the backend —
   `trips` + `expenses`, RLS policies, and the `delete-account` Edge Function —
   but as of 2026-07-31 the connected Supabase account hosts nine projects and
   none of them is this one. Its README described the directory as mirroring a
   live project; that has been corrected. Until a project exists, sign-in,
   cross-device sync, and account deletion cannot be tested on device, and
   §4's account-deletion check (Guideline 5.1.1(v)) cannot be satisfied. A new
   project in the current org is **$10/month**; `supabase/README.md` has the
   create-and-apply commands. If the project exists under a different Supabase
   login, verify its schema against `migrations/0001_init.sql` first.

2. **Bundle identifier is `DevJ.JetSetter-Pro`.** Legal, and Apple accepts it, but
   it is not reverse-DNS and it is baked into the StoreKit product ids. If you
   want `com.trainovations.jetsetterpro`, change it **before** you create the App
   Store Connect record — afterwards it is effectively permanent, and the
   subscription product ids would have to change with it.

3. **iPad is still a supported device family** (`TARGETED_DEVICE_FAMILY = "1,2"`)
   while the app is portrait-only. App Review can push back on an iPad build that
   does not support all orientations. Since this is a phone-first product, the
   low-risk move for v1 is `TARGETED_DEVICE_FAMILY = 1` (iPhone only); the
   alternative is doing real iPad layout QA and adding landscape.

4. **Export compliance.** I set `ITSAppUsesNonExemptEncryption = NO` on the basis
   that the app uses only Apple-provided crypto (CryptoKit AES-GCM in
   `VaultCrypto`, plus HTTPS), which is the standard exemption. Confirm that
   matches your reading before the first external release.

5. **Live Activities are declared but cannot render.** `NSSupportsLiveActivities`
   is set and `FlightLiveActivityService` is correctly guarded
   (`areActivitiesEnabled` + `do/catch`), so nothing crashes — the activity just
   never appears. Making it real needs a Widget Extension target, which also
   needs an App Group to share data with the app.

6. **Apple Watch.** `WatchConnectivityService` exists and `SETUP-WATCH.md`
   describes the target, but no watch target exists in the project.

7. **The unit tests now run and pass.** They had never been compiled — one
   suite still referenced `OpenScreenTool` after it became `NavigateTool`. Fixed,
   and the job is blocking in CI, so regressions in those 7 suites fail the PR.
   Coverage is thin though (currency math, expense categorisation, theme, wallet,
   travel profile, IRIS actions); most of the app is only covered by the manual
   checklist in §4.

---

## 7. Quick verification without signing

```bash
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -configuration Release -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

Build both Debug and Release — the `#if DEBUG` gates around demo mode and the
Pro demo-unlock must hold in Release.
