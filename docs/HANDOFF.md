# JetSetter Pro — Session Handoff

_Last updated: 2026-09-09. Read this first. `docs/EXECUTION-BACKLOG.md` and `AUDIT_REPORT.md` are historical and largely superseded by the decisions below._

## What the app is now

A business-traveler iOS app with **no backend, no accounts, and no custom chatbot**. Its assistant is **Siri**: every action is an App Intent (`Core/Intents/AppIntents.swift`) exposed through App Shortcuts, so it works from Siri, Spotlight, Shortcuts and the Action button. Apple Intelligence runs on the phone for generation and understanding; Apple frameworks replace nearly every third-party API.

| Capability | How it works | Framework |
|---|---|---|
| Assistant | 13 App Intents, 10 App Shortcuts, `SiriAssistantView` tab teaches phrases | AppIntents |
| Packing list | Guided generation, streamed rows | FoundationModels (`PackingListGenerator`) |
| Activity extraction | Content-tagging model + keyword table | FoundationModels (`ActivityTagger`) |
| Local Experiences | POI search around the destination, ranked on device | MapKit + FoundationModels (`LocalExperienceService`) |
| Receipt OCR | Vision text recognition + guided field extraction, regex fallback | Vision + FoundationModels (`VisionOCRService`) |
| Expense category | Guided enum generation | FoundationModels (`ExpenseCategorizer`) |
| Weather | WeatherKit first, Open-Meteo fallback, attribution view | WeatherKit (`WeatherService`) |
| Rental cars | Counters near the airport, brand deep links | MapKit (`RentalCarService`) |
| Hotels | Pre-filled hotel-site search + Apple Maps hotels nearby | MapKit (`BookingViewModel`) |
| Flights | Pre-filled flight-site search (Kayak) | — |
| Ground transport | Driving ETA, then Uber/Lyft with the route filled in | MapKit `MKDirections` |
| Check-in | Airline check-in page in-app, then scan the real pass | VisionKit barcode scanner |
| Translator | Translation framework + camera text scanner | Translation, VisionKit |
| Luggage | Manual status log, AirTag via Find My, airline links | — |
| Disruptions | FlightAware polling (optional key) → alerts, same-route search link, hotel email, Uber link, wallet insurance | BackgroundTasks |
| Persistence | SwiftData (trips, bags) + `LocalDataService` (wallet, packing, disruption events, signals) + encrypted vault | SwiftData, CryptoKit |

**Removed on 2026-09-09:** Supabase (auth, sync, edge functions), the Duffel/Expedia/Stripe proxy, Claude and the claude-proxy, Google Vision, Amadeus, Uber/Lyft estimate APIs, SITA WorldTracer, the fictional Enterprise/Hertz/National APIs, the IRIS chat/voice/tool stack, the fake seat-map check-in, the fake departure-board rows, the mock insurance policy, and demo/persona placeholder data.

## Locked decisions

- **No backend.** Nothing in the app talks to a server the owner runs. `LocalDataService` is the only store besides SwiftData. If cross-device sync is ever wanted, use SwiftData + CloudKit (Apple, no server) — see the beta review.
- **Siri is the assistant.** Add capabilities as App Intents, not chat tools. Keep App Shortcuts at 10 or fewer.
- **Apple frameworks before third-party APIs.** The only optional key is FlightAware (`API_FLIGHTAWARE`). Expense-provider OAuth keys remain for the export feature but are not needed for beta.
- **Never fabricate data.** Missing gate/seat/route render as "—". No sample rows unless labeled SAMPLE.
- **Deployment target iOS 18.** Apple Intelligence features are `@available(iOS 26)` gated and degrade to nil/fallbacks.

## Owner-side steps (need the developer portal or a product decision)

1. **WeatherKit capability** on the App ID (developer portal → Identifiers → JetSetter Pro → WeatherKit). The `com.apple.developer.weatherkit` entitlement is already in `JetSetter Pro.entitlements`; until the capability exists WeatherKit calls fail and the app falls back to Open-Meteo. This needs a signed-in Apple Developer account, which this Mac doesn't have.
2. **Register the App IDs** (bundle ID decided 2026-09-09: keep `DevJ.JetSetter-Pro`): app `DevJ.JetSetter-Pro` with App Groups (`group.DevJ.JetSetter-Pro`), WeatherKit, Time Sensitive Notifications, Background Modes and In-App Purchase; widget `DevJ.JetSetter-Pro.Widgets` with App Groups. Create the subscription products `DevJ.JetSetter-Pro.subscription.pro.monthly` and `.annual` in App Store Connect. (`Scripts/rename-bundle-id.sh` exists only if this ever changes.)
3. Optional: a FlightAware AeroAPI key in `Config/Secrets.xcconfig` (wire the file as the project's base configuration — `SETUP.md`).

Done on 2026-09-09 (no longer owner steps): the **Widget Extension target** (`JetSetter Pro Widgets`, embedded in the app; `Shared/FlightActivityAttributes.swift` compiles into both targets), the **unit test target** (`JetSetter ProTests`, Swift Testing, wired into the shared scheme and CI), and the **beta unlock** (TestFlight builds run against the sandbox App Store with no embedded provisioning profile, which `SubscriptionManager.isBetaBuild` detects to grant Pro; Xcode, Ad Hoc and App Store installs are unaffected). **Remove the beta unlock before App Store submission** — App Review also runs against the sandbox and would see Pro unlocked without a purchase.

## Until the portal steps are done (verified behaviour)

- **WeatherKit capability missing:** `WeatherService` tries WeatherKit once, then pauses it for 30 minutes and serves Open-Meteo, so weather still loads fast. No user-visible error. It retries on its own after the pause, so enabling the capability needs no relaunch.
- **No FlightAware key:** Flight Tracker, Flight Detail refresh, and Disruption "Check Now" show one plain sentence ("Live flight status isn't switched on in this build yet…") instead of an HTTP error; Home hides its "Track This Flight" / "Search Flights" buttons, and no background poll is registered or scheduled (so BGTaskScheduler never sees a failing wake). Everything driven by the itinerary (Home, check-in, leave-by, packing, Siri) is unaffected.
- **App Group not on the App ID:** the app and widget each fall back to their own `UserDefaults`, so the Next Trip widget shows "No upcoming trips" until the group exists. Nothing crashes.
- **Subscription products not in App Store Connect:** TestFlight testers get Pro through the sandbox-environment check; the paywall's "couldn't load options" message only appears if someone opens it deliberately.

## Bug-hunt notes (2026-09-09)

- **Siri actions are routed through `AppRouter.pendingAction`** (check-in, disruption, packing-list generation, loved-ones text). The destination view consumes the action in its `.task`, so a cold launch from Siri can't lose it; there are no fire-and-forget notifications for these any more.
- **Flight numbers** parse through one function, `TravelStore.extractFlightNumber`, which accepts alphanumeric designators (B6, F9, U2). Every `CheckInStateStore` caller uses the same fallback token, so a check-in recorded on Home is seen by the suggestion engine and Siri.
- **WeatherKit** is only paused after a real WeatherKit error (not a cancelled task or a network blip); the Apple Weather attribution is rendered wherever WeatherKit data is shown.
- **Local store** never overwrites a blob it couldn't decode; the blob moves to `<key>_undecodable` (cleared by Clear Local Data).
- **Notifications** are requested on first use by the vault expiry and check-in reminders as well as on the first saved trip.
- A one-time launch step deletes the pre-1.0 cloud session token from the Keychain (flag `cloud_session_purged`).

## Build / verify recipe

```
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```
Build Debug and Release. Launch on a simulator and open every tab; the Siri tab lists the App Shortcuts. Apple Intelligence features need a device (or a Mac with Apple Intelligence on) to exercise.

## Known gaps (see the beta review for the full list)

- Nested `NavigationStack`s under More (11 screens) — strip inner stacks, wrap at sheet call sites.
- Three background systems (theme vs system grouped vs forced dark) and fixed font sizes in Home/Disruption/Check-in.
- Dead `.swipeActions` in Wallet and Packing (they're in `ScrollView`s).
- Notification permission is now asked when the first trip is saved; location is still requested on Home load.
- iPhone 18 Pro / iPhone Duo layout pass needs the iOS 27 SDK (size-class-adaptive layouts, `NavigationSplitView` on regular width, no fixed card widths).
