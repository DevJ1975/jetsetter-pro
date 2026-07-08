# JetSetter Pro — Android Parity Prompt (AI + Backend)

> Paste this into your Android Studio AI assistant (or use as an engineering spec). It describes what the iOS app now does so the Android app can close the gap. Focus areas: the **IRIS AI assistant** and **backend/network configuration**. Build everything idiomatically for Android (Kotlin + Jetpack Compose + coroutines/Flow), but match the *behavior, data models, and contracts* described below exactly.

---

## 0. Goal

Bring the Android app to feature parity with iOS for:
1. **IRIS** — an in-app AI travel assistant that chats, takes voice, drives the app via tool/function calling, learns the user on-device, and proactively suggests actions.
2. **Backend/network layer** — the same third-party APIs, the same auth schemes, the same Supabase data model, and the same secrets handling.

Keep all user data **on-device by default**. Cloud sync (Supabase) is opt-in via sign-in. Personal preferences and learned profile data must **never** be sent to third-party APIs.

---

## 1. IRIS AI Assistant

### 1.1 Model strategy (two tiers + demo fallback)
- **Tier 1 — on-device:** iOS uses Apple FoundationModels (`SystemLanguageModel` / `LanguageModelSession`). **Android equivalent:** use an on-device LLM — **Gemini Nano via ML Kit GenAI / AICore** (Pixel-class devices) or MediaPipe LLM Inference. Use it for chat, expense categorization, and persona generation when available.
- **Tier 2 — cloud fallback:** **Anthropic Claude**, model id **`claude-sonnet-4-6`**, `max_tokens: 1024`, **streaming SSE** (`stream: true`).
  - Endpoint: `POST https://api.anthropic.com/v1/messages`
  - Headers: `x-api-key: <ANTHROPIC_KEY>`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- **Tier 3 — demo mode:** canned mock responses when neither on-device nor Claude is configured (so the app is always demoable offline).

Maintain a **stateful conversation session** so you don't resend full context each turn; recreate the session when system instructions change or context exceeds ~4k tokens.

### 1.2 System prompt / personality (use verbatim as the base)
```
You are IRIS — the Intelligent Routing & Itinerary Specialist for JetSetter Pro.
Named after the Greek goddess of the rainbow, messenger between gods and mortals.
Female-coded; warm and precise.

PERSONA: warm, professional, quietly confident (like a top human travel agent);
anticipatory; concise (bullets for lists); never invent details — offer to use tools.
VOICE: open with "Let's see…" for a pause; prefer "I'd suggest…" over "You should…";
occasional first person; sign off "—IRIS" only when thanked; <4 short paragraphs unless asked.
CAPABILITIES: prefer real data — live weather, FX, flight schedules, visa requirements,
the user's actual trips/itinerary/wallet/expenses/saved preferences.
ACTIONS (you can drive the app): navigate immediately; look up flights; log expenses, add trips,
check in, generate packing lists, submit expenses — BUT all data-changing actions are STAGED for
confirmation first.
MEMORY: record preferences via the remember-preference tool; recall them at conversation start;
never volunteer personal details to third parties.
PRINCIPLES: safety first (mention advisories); privacy first; no external bookings (research only);
defer on politics/religion/medical.
FORMAT: bullets for lists; bold sparingly; never markdown headings (use "LABEL:" instead).
```
At session start, append dynamically:
1. Stored user preferences summary (from IRIS memory).
2. Traveler persona (if generated).
3. Learned travel profile summary (see §1.6).
4. Live context snapshot — active/next trip, next 3 itinerary items, next flight, expense totals (§1.7).

### 1.3 Tools / function calling
Implement these as LLM function-calling tools (Claude tool-use schema; mirror with on-device equivalent). **Write/data-changing tools must STAGE a pending action, not commit.** Navigation and read-only lookups run immediately.

**Read-only:**
| Tool name | Args | Behavior |
|---|---|---|
| `getUserTrips` | `filter` (upcoming/past/all) | Return trips + up to 6 itinerary items each |
| `getWeather` | `location` (city or IATA) | Temp °F, conditions, wind — via airport coords + WeatherService |
| `getVisaAndCountryEssentials` | `country` | Visa rules, emergency numbers, tipping, plugs/voltage, water safety |
| `rememberUserPreference` | `category`, `value` | Persist/reinforce a preference (see §1.5) |
| `getLearnedTravelProfile` | `aspect?` (seat/airlines/hotels/spend/places/all) | Summarize learned profile |
| `getDepartureRecommendation` | `originAirportIATA`, `scheduledDepartureISO`, `lane?`, `currentLatitude`, `currentLongitude` | Leave-by time, drive mins, TSA wait, boarding buffer |
| `submitExpenses` | `provider` (email/expensify/ramp/brex/divvy), `tripName?` | **STAGED** |

**Write / navigation:**
| Tool name | Args | Behavior |
|---|---|---|
| `openScreen` | `screen` | **Immediate** navigation (home, itinerary, iris, expenses, more, checkIn, disruption, flightTracker, documentVault, packingList, groundTransport, currency) |
| `trackFlight` | `flightNumber` | **Immediate** — open Flight Tracker + trigger live search |
| `logExpense` | `amount`, `merchant`, `currency?`=USD, `category?` | **STAGED** → append Expense |
| `addTrip` | `destination`, `startDate`(yyyy-MM-dd), `endDate`, `name?` | **STAGED** → append Trip (validate end ≥ start) |
| `checkInForFlight` | `flightNumber?` (default next upcoming) | **STAGED** → mark checked in |
| `generatePackingList` | `tripName?` (default active/next) | **STAGED** → navigate + generate |
| `flightActions` | `action` (notifyLovedOnes / luggageStatus), `event?` (takeoff/landing) | notifyLovedOnes = **immediate**, opens prefilled SMS; luggageStatus = **read-only** report |

Categories enum: `food, transport, accommodation, entertainment, business, shopping, medical, mileage, other`.

### 1.4 Confirm-before-commit flow
- Data-changing tools return an **IRISPendingAction** instead of committing:
  ```
  IRISPendingAction {
    id: UUID
    kind: { logExpense | checkIn | addTrip | trackFlight | generatePackingList | submitExpenses }
    summary: String              // human-readable, shown on the confirmation card
    commit: suspend () -> String // returns a result message to show/speak
  }
  ```
- A `ActionRouter` exposes the pending action as observable state (StateFlow). The chat UI renders a **confirmation card** (summary + context icon + Cancel/Confirm + progress). On Confirm, run `commit()`, append the result to the transcript. IRIS must phrase staged actions as "I've prepared…", never "I've logged…", until confirmed. If a required field is missing, IRIS asks before calling the tool.

### 1.5 Memory (on-device preferences)
```
IRISPreference { id: UUID; category; value: String; createdAt; lastReinforcedAt; confidence: Double }
category ∈ { dietary, seating, hotelStyle, airlinePreference, transportation, destinations, activities, general }
```
- Persist locally (SharedPreferences/DataStore or Room), JSON, ISO-8601 dates. Key like `iris_memory`.
- `remember()` creates or reinforces (confidence starts 0.7, +0.1 per reinforcement, cap 1.0). `recall(category)` sorts by confidence desc. `summaryForPrompt()` feeds the system prompt. Provide a user-facing view to inspect/delete + "forget everything". **Never** transmitted to external APIs.

### 1.6 On-device learning layer (Travel Profile)
Three tiers — **replicate the math exactly** (deterministic, testable):

**TravelSignal** (observed behavior):
```
TravelSignal { id; kind; value: String; attributes: Map<String,String>; timestamp; source: String }
kind ∈ { seatChosen, flightFlown, receiptScanned, expenseLogged, loyaltyAdded,
         tripCompleted, placeVisited, suggestionFeedback }
```
Common attribute keys: `airline, cabinHint, category, amount, currency, city, leadDays, brandKind, accepted`.

**TravelProfileEngine** (pure/stateless aggregation):
- Recency weighting: **exponential decay, 365-day half-life** → `weight = pow(0.5, ageDays / 365)`.
- Rankings: aggregate by key, sort by weight, top 5 (`WeightedValue { value, weight, count }`).
- Seat parsing: column A/F/K/L = window, C/D/G/H = aisle, B/E = middle; zone rows 1–10 forward, 11–25 mid, 26+ rear. Preference = recency-weighted mode of column & zone, with `confidence` = dominant share and `sampleSize`.
- Cabin = mode of flight signals' `cabinHint`. Cities = trip destinations + `placeVisited`. Spend stats = expenses grouped by category+currency (exclude `mileage`). Trip rhythm = mean duration, mean gap between trips (cadence), peak months (month appearing ≥2× and ≥3 trips exist).

**TravelProfile** (derived): `typicalSeat: SeatPreference?`, `topAirlines/topHotelBrands/frequentCities: [WeightedValue]`, `preferredCabin: String?`, `spendByCategory: [SpendStat{category,currency,average,count}]`, `typicalBookingLeadDays`, `typicalTripDurationDays`, `travelCadenceDays`, `peakTravelMonths: [String]`, `generatedAt`, `isEmpty`. `summaryForPrompt()` returns "" when empty (lean persona for new users).

**TravelProfileStore** (persistence + consent + sync):
- Persist signals (`jetsetter_travel_signals`, JSON, cap **2000** FIFO) and cached persona (`jetsetter_travel_persona`).
- **Consent gating** (replicate exactly): master `learningEnabled`; per-source `learnFromReceipts` (gates receiptScanned/expenseLogged), `learnFromCheckIns` (gates seatChosen), `learnFromTrips` (gates flightFlown/tripCompleted/placeVisited); loyalty + feedback gated by master only. If a signal isn't allowed, silently no-op.
- Recompute profile on signal changes; collapse to empty profile if learning disabled. Best-effort Supabase upsert + merge-by-id on sign-in.
- Persona: generate a 2–3 sentence travel persona from the profile summary via the on-device model or Claude; cache it; clear if learning off/profile empty.
- `recordSuggestionFeedback(kind, accepted)` + `dismissedCount(forKind)` feed trigger suppression.

### 1.7 Live context snapshot
Compute on each session start from local trip/expense stores: active or next trip (date range + top 3 upcoming items), next flight across all trips, expense count + totals by currency. Inject as plain text into the system prompt ("Live traveler data… don't invent details").

### 1.8 Voice (hands-free loop)
State machine: `idle → listening → thinking → speaking → listening` (loop), `stop → idle`.
- **STT:** Android `SpeechRecognizer` (prefer on-device recognition). Stream partial transcripts to UI. End-of-utterance after ~1.2 s of silence.
- **Reasoning:** send finalized transcript to IRIS; get reply text.
- **TTS:** Android `TextToSpeech`, locale-matched voice. **Tear down the mic while speaking** to avoid transcribing IRIS's own voice; auto-resume listening on `onDone`.
- Permissions: `RECORD_AUDIO`. AudioFocus: duck others; route to speaker; allow Bluetooth SCO.

### 1.9 Proactive triggers
Evaluate on home open + timer ticks; render suggestion cards. Each has a `dismissalKey` for de-dup. Kinds (priority order): `checkInWindow` (<24h, not checked in), `seatPreferenceNudge` (<36h + learned seat, conf ≥0.6 & ≥2 samples), `preferredCabinNudge` (<36h + premium cabin), `tierAtRisk` (loyalty expiring ≤7d), `rideToAirport` (<12h, no uber flag), `rideOnLanding` (arriving ~≤90m, no flag; uses bag estimator), `packingNudge` (14–28d out, no list), `visaCheck` (0–7d, eVisa/visa), `weatherWatch` (0–3d), `dailyBriefing` (active trip, daily), `budgetPacingNudge` (category spend ≥1.3× learned avg), `welcomeHome` (<24h after trip). Safety/operational nudges never suppressed; preference nudges back off after 3 dismissals.
```
IRISSuggestion { kind; title; body; promptToIRIS: String; dismissalKey: String }
```

---

## 2. Backend / Network

### 2.1 HTTP client (match the policy)
- Single client (use **OkHttp/Retrofit + coroutines**). 30 s timeout.
- **Retry:** GET retries up to 3× on transient failures (timeout/DNS/connectivity); **POST never retries**. Exponential backoff w/ jitter: `min(2^(attempt-1), 8) + random(0..0.3)` s, capped ~10 s total. Respect `Retry-After` on 429.
- JSON: snake_case ↔ camelCase, ISO-8601 dates.
- Error type: `invalidURL, unauthorized(401), rateLimited(retryAfter?), requestFailed(status), decodingFailed, unknown`.

### 2.2 Secrets
- Load from build config (Android equivalent of `Secrets.xcconfig` → `BuildConfig`/`local.properties`, kept out of VCS). Validate: trim, treat empty / `YOUR_*` / `REPLACE_ME` as **not configured**. Expose an `isConfigured(key)` check. Don't hardcode keys in source.

### 2.3 Third-party APIs (same contracts)
| Feature | Provider | Endpoint | Auth | Secret key |
|---|---|---|---|---|
| Flight status/track | FlightAware AeroAPI | `https://aeroapi.flightaware.com/aeroapi/flights/{ident}` | header `x-apikey` | `flightAware` |
| AI fallback | Anthropic Claude (via server proxy) | `POST {claudeProxyURL}` — the proxy holds the Anthropic key; body is the standard Messages API (SSE) | Supabase anon key as `Authorization: Bearer` | `claudeProxyURL` |
| Hotel search | Expedia Rapid | `https://api.expediagroup.com/v3/properties/availability` (test host in debug) | OAuth2 Bearer (token at `/identity/oauth2/v3/token`) | `expediaClientID`, `expediaClientSecret` |
| Ride price (Uber) | Uber | `https://api.uber.com/v1.2/estimates/price` | header `Authorization: Token <serverToken>` | `uberServerToken` |
| Ride price (Lyft) | Lyft | `https://api.lyft.com/v1/cost` | OAuth2 Bearer (token at `/oauth/token`) | `lyftClientID`, `lyftClientSecret` |
| Receipt OCR | Google Vision | `https://vision.googleapis.com/v1/images:annotate?key=…` | query `key` | `googleVision` |
| Baggage | SITA WorldTracer | `https://api.sita.aero/baggage/v1/baggage/{tag}` | header `x-partner-key` | `sitaWorldTracer` |
| Car rental | Enterprise/Hertz/National | deep links + placeholder search | API key headers | `enterprise`,`hertz`,`national` |
| Weather, FX | (existing services) | — | — | — |

> On-device OCR: prefer **ML Kit Text Recognition** on Android (cheaper/offline) and fall back to Google Vision for parity. Receipt text feeds the expense categorizer.

### 2.4 Supabase (backend)
iOS uses the Supabase REST APIs (GoTrue auth + PostgREST data, no SDK); **on Android use the Supabase Kotlin SDK (`supabase-kt`) or the same REST APIs**. Match this data model:
- **Auth:** email/password via GoTrue (`/auth/v1`). Session `{ accessToken, refreshToken, expiresAt, user{id,email,createdAt} }`. Persist securely (Android Keystore / EncryptedSharedPreferences). Auto-refresh on expiry.
- **PostgREST tables** (`/rest/v1`, one row per model, row-level security keyed on `auth.uid() = user_id`): `trips`, `wallet_items`, `packing_lists`, `disruption_events`, `travel_signals`. Keep primary-key IDs identical across platforms for cross-device sync.
- **⚠️ Financial data is NOT synced.** Expenses, currency amounts, and receipt text/images stay **on-device in SQLite** (see §2.5) and never leave the device — do not create cloud tables for them.
- **Account deletion (App Store / Play 5.1.1 parity):** delete all user rows across every table via the `delete-user` edge function, delete the auth account, then clear the local session **and the on-device SQLite financial store**.

### 2.5 Local stores — on-device SQLite for financial data + DataStore for the rest
- **Financial data (device-only, SQLite):** expenses (`jetsetter_expenses`), currency-tracker amounts, and receipt text/images live in a local **SQLite** database (**Room** on Android; SQLite/GRDB on iOS). Never uploaded to Supabase or any third-party API. This is the source of truth for financial info.
- **Non-financial local state (DataStore/Room, may sync):** Trips `jetsetter_trips`, Bags `jetsetter_bags`, Loved ones `jetsetter_loved_ones`, IRIS memory `iris_memory`, Signals `jetsetter_travel_signals`, Persona `jetsetter_travel_persona`. Booking flags `uber_booked`, `ride_on_landing_booked`. Match keys + JSON + ISO-8601 with iOS.
- TravelStore helpers: active trip = today's or next upcoming; next flight = first item title matching regex `[A-Z]{2,3}\d{1,4}`; emit change events after mutations. Tolerant date decoding (ISO-8601 then fallback).

> A separate agent is producing the detailed SQLite/Room financial-store schema + migration for both platforms; treat the bullets above as the contract until that lands.

---

## 3. Supporting features

### 3.1 Expense categorizer
On-device classification: given `merchant`, optional `notes`, optional `receiptText` (truncate ~400 chars), return one of `food, transport, accommodation, entertainment, business, shopping, medical, other` (never `mileage`). Use Gemini Nano / ML Kit GenAI with constrained output; **return null if unavailable** (graceful degradation). Deterministic decoding.

### 3.2 Bag delivery estimator (port heuristic as-is)
`estimate(airportIATA, hasCheckedBag)`: no checked bag → 0 min. Large hub (tier-1 set: ATL DFW ORD LAX JFK DEN SFO LAS SEA MIA EWR BOS MCO CLT IAH LHR CDG FRA AMS DXB HND NRT SIN HKG ICN PEK PVG) → 20–35 min. Otherwise → 12–25 min. Return `{ minMinutes, maxMinutes, expectedMinutes(mid), basis, display }`.

### 3.3 Loved Ones
```
LovedOne { id; name; phoneNumber; notifyOnTakeoff=true; notifyOnLanding=true }
```
Persist locally (`jetsetter_loved_ones`). Transport = **native SMS composer intent** (user taps Send; no silent SMS, no backend). Messages: takeoff "✈️ Wheels up on {flight} — I'll text you when I land."; landing "🛬 Just landed safely in {city}. Talk soon!". `flightActions(notifyLovedOnes)` opens the composer prefilled with the matching contacts for the event.

---

## 4. Acceptance checklist
- [ ] IRIS chat works with on-device model, falls back to Claude `claude-sonnet-4-6` (streaming), then demo mode.
- [ ] All tools implemented; write actions STAGE → confirmation card → commit.
- [ ] Voice loop (STT → IRIS → TTS) with mic teardown while speaking + auto-resume.
- [ ] On-device learning: signals captured under consent gates, 365-day-half-life profile, persona, 2000-cap, suggestion-feedback suppression.
- [ ] Proactive triggers render with correct priority + dismissal/suppression.
- [ ] Network client matches retry/backoff/rate-limit policy; secrets gated by `isConfigured`.
- [ ] All listed third-party APIs wired with the exact auth schemes.
- [ ] Supabase auth + PostgREST tables with matching row IDs; full account deletion.
- [ ] Expense categorizer + bag estimator + Loved Ones SMS parity.
- [ ] No preference/profile data ever leaves the device to third-party APIs.

> Platform mapping summary: FoundationModels → Gemini Nano / ML Kit GenAI (+ Claude fallback); `@Generable` tools → Claude tool-use / structured output; AVSpeech/Speech → `TextToSpeech` / `SpeechRecognizer`; UserDefaults → DataStore/Room; Keychain → Keystore/EncryptedSharedPreferences; Supabase REST → Supabase Kotlin SDK (supabase-kt); Google Vision → ML Kit Text Recognition (+ Vision fallback).
