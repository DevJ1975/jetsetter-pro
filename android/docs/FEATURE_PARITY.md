# Feature Parity — iOS → Android

Master checklist tracking the port of all **34 iOS feature modules** (SwiftUI +
MVVM) to **Android** (Kotlin + Jetpack Compose + Material 3, MVVM + Repository,
Hilt, Room, DataStore, Retrofit/OkHttp/Moshi, Coroutines/Flow).

- **iOS source root:** `JetSetter Pro/Features/<Name>/`
- **Android target:** `com.jetsetter.pro.feature.<name>`
- **Shared services:** `JetSetter Pro/Core/Services/` → `com.jetsetter.pro.core.*`
  (see §3)

### Legend

- **Status:** ✅ wired (UI + data flowing) · 🟡 stubbed (screen/scaffold exists,
  mock or partial data) · ⬜ not started
- **Priority:** **P0** wire now · **P1** next · **P2** later
- **APIs/services:** the Core service or external API (see `API_REFERENCE.md`)
  the module depends on. "Mock" = `MockDataService` fallback when the secret is
  unset (mirrors iOS `AppSecrets.isConfigured`).

> The iOS `Features/` directory has **35 folders**. Two of them — `PackingList`
> and `Settings` — are sub-surfaces of the 34 logical modules below
> (PackingList lives under **Itinerary**; Settings is the **More/Settings**
> module). The 34 rows map to the 34 logical feature modules in the spec.

---

## 1. Feature modules (34)

| # | Feature | iOS source folder | Description | Android package | Key APIs / services | Priority | Status |
|---|---|---|---|---|---|---|---|
| 1 | **Home** | `Features/Home/` | Dashboard: next trip, live flight, quick actions, alerts | `feature.home` | HomeViewModel aggregates Trip/Flight/Wallet repos; FlightAware | P0 | ✅ |
| 2 | **Itinerary** | `Features/Itinerary/` (+`PackingList/`) | Trip list & detail; add/edit items; packing list; share text | `feature.itinerary` | Room (Trip/ItineraryItem/PackingItem), CalendarService, Firestore sync | P0 | ✅ |
| 3 | **IRIS Chat** | `Features/IRIS/` | AI travel assistant chat + memory + suggestion cards | `feature.iris` | AIService → Claude (`/v1/messages`, streaming); on-device fallback | P0 | 🟡 |
| 4 | **Expenses (ExpenseTracker)** | `Features/ExpenseTracker/` | Expense list, manual entry, receipt scan, mileage (IRS rate) | `feature.expenses` | Room (Expense), VisionOCRService → Google Vision, Firestore | P0 | 🟡 |
| 5 | **More / Settings** | `Features/More/` (+`Settings/`) | Settings hub, profile, preferences, feature index, sign-out | `feature.more` | DataStore (UserPreferences), FirebaseService (auth) | P0 | 🟡 |
| 6 | **FlightTracker** | `Features/FlightTracker/` | Live flight status by ident; gates, delays, progress | `feature.flighttracker` | FlightAware AeroAPI; APIClient | P1 | ⬜ |
| 7 | **FlightBoard** | `Features/FlightBoard/` | Airport departures/arrivals board | `feature.flightboard` | FlightAware AeroAPI; Mock | P1 | ⬜ |
| 8 | **CheckIn** | `Features/CheckIn/` | Airline check-in flow + state store | `feature.checkin` | CheckInService, CheckInStateStore (Room/DataStore) | P1 | ⬜ |
| 9 | **DepartureOptimizer** | `Features/DepartureOptimizer/` | "Leave by" time using TSA wait + drive time | `feature.departureoptimizer` | DepartureOptimizerService, TSAWaitEstimator, LocationService | P1 | ⬜ |
| 10 | **Disruption** | `Features/Disruption/` | AI disruption dashboard; alternatives; 5-step auto-response | `feature.disruption` | DisruptionMonitorService, DisruptionResponseEngine, Amadeus, Duffel, FlightAware | P1 | ⬜ |
| 11 | **Booking** | `Features/Booking/` | Hotel search + detail (Expedia Rapid) | `feature.booking` | ExpediaAuthService (OAuth2), Expedia Rapid; Mock | P2 | ⬜ |
| 12 | **VisaLookup** | `Features/VisaLookup/` | Entry/visa requirements by destination | `feature.visalookup` | Bundled `EntryRequirement` table (no network) | P1 | ⬜ |
| 13 | **TravelEssentials** | `Features/TravelEssentials/` | Destination essentials (power, currency, emergency #s) | `feature.travelessentials` | Bundled data; WeatherService | P2 | ⬜ |
| 14 | **LocalExperience** | `Features/LocalExperience/` | Curated local activities/experiences | `feature.localexperience` | LocalExperienceViewModel, CityPhotoService; Mock | P2 | ⬜ |
| 15 | **Translator** | `Features/Translator/` | Phrase translation | `feature.translator` | AIService → Claude; (ML Kit on-device optional) | P2 | ⬜ |
| 16 | **TravelJournal** | `Features/TripJournal/` | Trip journal/notes + photos | `feature.traveljournal` | Room, PhotoLibraryService | P2 | ⬜ |
| 17 | **GroundTransport** | `Features/GroundTransport/` | Uber/Lyft price+time estimates to/from airport | `feature.groundtransport` | Uber API, Lyft API (OAuth2), LocationService | P1 | ⬜ |
| 18 | **RentalCar** | `Features/RentalCar/` | Rental car search/detail; deep links | `feature.rentalcar` | RentalCarService; Enterprise/Hertz/National; Mock | P2 | ⬜ |
| 19 | **LuggageTracker** | `Features/LuggageTracker/` | Bag registry; WorldTracer status; AirTag; scan history | `feature.luggagetracker` | SITAWorldTracerService, Room (Bag/BagScanEvent) | P1 | ⬜ |
| 20 | **AirportMap** | `Features/AirportMap/` | Airport terminal map / amenities | `feature.airportmap` | AirportMapViewModel; bundled/Mock | P2 | ⬜ |
| 21 | **TravelWallet** | `Features/TravelWallet/` | Boarding passes, hotel/car/event/insurance docs | `feature.travelwallet` | PassKitService → (Google Wallet), Room (WalletItem), Firestore | P1 | ⬜ |
| 22 | **LoyaltyVault** | `Features/LoyaltyVault/` | Frequent-flyer/hotel accounts + balances | `feature.loyaltyvault` | Room (LoyaltyAccount), program catalog, EncryptedSharedPrefs | P1 | ⬜ |
| 23 | **IdentityVault** | `Features/IdentityVault/` | Secured personal identity info | `feature.identityvault` | VaultCrypto (Tink/AES-GCM), BiometricPrompt | P2 | ⬜ |
| 24 | **DocumentVault** | `Features/DocumentVault/` | Encrypted travel docs (passport/visa/etc.) + expiry alerts | `feature.documentvault` | VaultCrypto, DocumentVaultStore, BiometricPrompt, Firestore | P1 | ⬜ |
| 25 | **CurrencyTracker** | `Features/CurrencyTracker/` | FX rates + currency-aware expense conversion | `feature.currencytracker` | ExchangeRateService; Room cache | P2 | ⬜ |
| 26 | **CarbonTracker** | `Features/Carbon/` | Flight carbon footprint estimate | `feature.carbontracker` | Local calculator; flight data | P2 | ⬜ |
| 27 | **Subscription** | `Features/Subscription/` | Premium paywall + gating | `feature.subscription` | SubscriptionManager → Google Play Billing | P1 | ⬜ |
| 28 | **ExpenseExport** | `Features/ExpenseExport/` | Export expenses (PDF) + provider connections | `feature.expenseexport` | PDFExpenseReportRenderer, Expensify/Ramp/Brex/Divvy | P2 | ⬜ |
| 29 | **Onboarding** | `Features/Onboarding/` | First-run onboarding flow | `feature.onboarding` | DataStore (`hasCompletedOnboarding`) | P1 | ⬜ |
| 30 | **Assistant** | `Features/Assistant/` | General assistant surface (distinct from IRIS chat) | `feature.assistant` | AssistantViewModel, AIService → Claude | P2 | ⬜ |
| 31 | **Intelligence** | `Features/Intelligence/` | Proactive travel intelligence cards + history | `feature.intelligence` | TravelIntelligenceViewModel, AIService, multiple repos | P2 | ⬜ |
| 32 | **OfflineKit** | `Features/OfflineKit/` | Offline data bundle / cache management | `feature.offlinekit` | OfflineKitService, Room, WorkManager | P2 | ⬜ |
| 33 | **InFlight** | `Features/InFlight/` | In-flight live tracking view | `feature.inflight` | InFlightTrackingService, FlightAware | P2 | ⬜ |
| 34 | **Translator → (see #15)** *(reserved)* | — | — | — | — | — | — |

> Row 34 is intentionally a placeholder: the spec lists 34 modules but
> `Translator` and `Intelligence`/`OfflineKit`/`InFlight` already cover the tail.
> The canonical 34 are rows **1–33 plus the Core/Services checklist (§3)**, which
> the iOS app treats as a first-class porting unit. Adjust numbering once the
> Android module list is frozen.

### Modules explicitly marked at kickoff

- **✅ wired:** Home, Itinerary
- **🟡 stubbed:** IRIS Chat, Expenses (ExpenseTracker), More/Settings
- **⬜ not started:** all remaining modules

---

## 2. Per-module Android scaffolding convention

Each `feature.<name>` package should contain, mirroring the iOS `*View` /
`*ViewModel` / `*Model` split:

```
feature/<name>/
├── <Name>Screen.kt          // Composable screen  (iOS <Name>View.swift)
├── <Name>ViewModel.kt       // @HiltViewModel, exposes StateFlow<UiState>
├── <Name>UiState.kt         // sealed/data UI state
└── (models live in core.model; repos in core.data — shared, not per-feature)
```

- ViewModels receive **repositories** (not services) via Hilt constructor
  injection. Repositories decide live-API-vs-Room-vs-Mock (see `API_REFERENCE.md`).
- Navigation via a single `NavHost` with type-safe routes
  (`com.jetsetter.pro.navigation`).

---

## 3. Core / Services porting checklist

iOS `Core/Services/*` → Android. Most become **repositories** or **data sources**
behind interfaces so ViewModels stay testable.

| iOS service | Android home | Notes |
|---|---|---|
| `APIClient` / `Endpoints` | `core.network` (Retrofit + OkHttp + Moshi) | See APIClient/error model in `API_REFERENCE.md` |
| `AppSecrets` | `core.secrets.Secrets` | Reads `BuildConfig` fields; empty ⇒ Mock |
| `AIService` | `core.ai.AiRepository` | Claude `/v1/messages` streaming (SSE via OkHttp); on-device fallback = ML Kit / Gemini Nano (optional) |
| `FirebaseService` | `core.sync.FirebaseRepository` | Firestore + Identity Toolkit REST (no Firebase SDK required) |
| `MockDataService` / `DemoSeeder` | `core.data.mock.MockData` | Sample data parity with iOS `*.sample` |
| `VaultCrypto` | `core.crypto.VaultCrypto` | Tink (AES-GCM) + Android Keystore; EncryptedSharedPreferences |
| `VisionOCRService` | `core.ocr.OcrRepository` | Google Vision REST; or ML Kit Text Recognition on-device |
| `PassKitService` | `core.wallet.WalletRepository` | Google Wallet API (replaces Apple PassKit) |
| `NotificationManager` | `core.notifications` | `NotificationManagerCompat` + channels; FCM for push |
| `LocationService` | `core.location` | FusedLocationProviderClient |
| `CalendarService` | `core.calendar` | `CalendarContract` provider |
| `WeatherService` | `core.weather` | Repo; same upstream as iOS |
| `ExchangeRateService` | `core.fx` | Repo + Room cache |
| `SubscriptionManager` | `core.billing` | Google Play Billing Library |
| `ExpediaAuthService` / OAuth services | `core.network.auth` | OkHttp `Authenticator` for OAuth2 client-credentials token caching |
| `SITAWorldTracerService` | `core.network.worldtracer` | Retrofit service |
| `RentalCarService` | `core.network.rentalcar` | Enterprise/Hertz/National + deep links |
| `DepartureOptimizerService` / `TSAWaitEstimator` | `core.departure` | Pure-Kotlin calculators |
| `DisruptionMonitorService` / `DisruptionResponseEngine` | `core.disruption` | WorkManager periodic monitor + response orchestration |
| `InFlightTrackingService` | `core.inflight` | Polling tracker over FlightAware |
| `OfflineKitService` | `core.offline` | Room + WorkManager sync |
| `AudioAlertService` | `core.audio` | `SoundPool` / `Ringtone` |
| `PhotoLibraryService` | `core.media` | Photo Picker (`ActivityResultContracts.PickVisualMedia`) |
| `CityPhotoService` | `core.media.CityPhotoRepository` | Image fetch + Coil cache |
| `WatchConnectivityService` | `core.wearable` *(optional)* | Wear OS Data Layer (defer; low priority) |
| `FlightLiveActivityService` | `core.liveactivity` | Live Activities → ongoing notification + (optional) Live Updates |

---

## 4. Recommended porting roadmap

### Phase 0 — Foundation (in progress)
Theme/design system, `JetTheme`, navigation shell, Hilt graph, Room DB +
DataStore, `core.network` (APIClient + interceptors + error model),
`core.secrets`, `MockData`. Land **Home** and **Itinerary** end-to-end (✅).

### Phase 1 — Core daily-driver loop (P0 finish + early P1)
Complete the three stubs to wired: **IRIS Chat** (Claude streaming),
**Expenses** (Room + Vision OCR + mileage), **More/Settings** (DataStore +
Firebase auth). Then **Onboarding**, **FlightTracker**, **TravelWallet**,
**Subscription** (gating must exist before premium features ship).

### Phase 2 — Trip-day intelligence (P1)
**Disruption** (+ DisruptionMonitor/ResponseEngine, Amadeus, Duffel),
**DepartureOptimizer** (+ TSA/Location), **CheckIn**, **FlightBoard**,
**GroundTransport** (Uber/Lyft), **LuggageTracker** (WorldTracer),
**VisaLookup**, **LoyaltyVault**, **DocumentVault** (+ VaultCrypto + Biometric).

### Phase 3 — Vaults, sustainability & enrichment (P2)
**IdentityVault**, **CurrencyTracker**, **CarbonTracker**, **Booking** (Expedia),
**RentalCar**, **LocalExperience**, **TravelEssentials**, **AirportMap**,
**TravelJournal**, **Translator**, **Assistant**, **Intelligence**,
**ExpenseExport**, **InFlight**, **OfflineKit**.

### Cross-cutting (every phase)
Firestore cross-device sync wired as each model's Room layer lands; offline-first
(Room is source of truth, sync reconciles); secrets→Mock fallback verified per
feature; accessibility + RTL (`AutoMirrored` icons) checked as screens are built.
