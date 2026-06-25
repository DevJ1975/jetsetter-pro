# API & Data Layer Reference — Android

Port of the iOS data + network layer (`JetSetter Pro/Core/Network/`,
`Core/Configuration/`, `Core/Services/`) to Android.

- **Networking:** Retrofit + OkHttp + Moshi (snake_case), Coroutines/Flow
- **Persistence:** Room (entities/DAOs/converters) + DataStore (prefs) +
  EncryptedSharedPreferences/Tink (secrets & vault)
- **Sync:** Firebase Firestore + Identity Toolkit **REST** (no Firebase SDK —
  mirrors iOS `FirebaseService`)
- **Package roots:** `com.jetsetter.pro.core.network`, `.core.data`,
  `.core.model`, `.core.secrets`, `.core.sync`, `.core.crypto`

---

## 1. External APIs

Base URLs, auth schemes, and secret key names are taken verbatim from
`Core/Network/Endpoints.swift` and `Core/Configuration/AppSecrets.swift`.

| Service | Base URL | Auth scheme | Header / param | Secret key(s) |
|---|---|---|---|---|
| **FlightAware AeroAPI** | `https://aeroapi.flightaware.com/aeroapi` | API key | header `x-apikey` | `API_FLIGHTAWARE` |
| **Anthropic Claude** | `https://api.anthropic.com/v1` (`/messages`) | API key | header `x-api-key` + `anthropic-version: 2023-06-01` | `API_ANTHROPIC` |
| **Google Vision** | `https://vision.googleapis.com/v1` (`images:annotate`) | API key | query `?key=…` | `API_GOOGLE_VISION` |
| **Expedia Rapid** | data `https://test.api.expediagroup.com`; auth `https://api.expediagroup.com` | OAuth2 client-credentials → Bearer | token: `…/identity/oauth2/v3/token`; then `Authorization: Bearer <token>` | `API_EXPEDIA_CLIENT_ID`, `API_EXPEDIA_CLIENT_SECRET` |
| **Amadeus** | (Flight Offers Search) | OAuth2 client-credentials → Bearer | `Authorization: Bearer <token>` | `API_AMADEUS_CLIENT_ID`, `API_AMADEUS_CLIENT_SECRET` |
| **Duffel** | (rebooking / offers) | Bearer token | `Authorization: Bearer <token>` | `API_DUFFEL` |
| **SITA WorldTracer** | `https://api.sita.aero/baggage/v1` | Partner key | header `x-partner-key` | `API_SITA_WORLDTRACER` |
| **Uber** | `https://api.uber.com/v1.2` | Server token | `Authorization: Token <token>` | `API_UBER_SERVER_TOKEN` |
| **Lyft** | `https://api.lyft.com/v1`; auth `https://api.lyft.com/oauth/token` | OAuth2 client-credentials → Bearer | `Authorization: Bearer <token>` | `API_LYFT_CLIENT_ID`, `API_LYFT_CLIENT_SECRET` |
| **Enterprise** | `https://api.enterprise.com/v1` | API key | header `x-api-key` | `API_ENTERPRISE` |
| **Hertz** | `https://api.hertz.com/v1` | API key | header `api-key` | `API_HERTZ` |
| **National** | `https://api.nationalcar.com/v1` | API key | header `x-api-key` | `API_NATIONAL` |
| **Firebase Auth (Identity Toolkit)** | `https://identitytoolkit.googleapis.com/v1/accounts`; refresh `https://securetoken.googleapis.com/v1/token` | API key | query `?key=<API_KEY>` | `API_FIREBASE_API_KEY` |
| **Firebase Firestore (REST)** | `https://firestore.googleapis.com/v1/projects/{projectID}/databases/(default)/documents` | Bearer (Firebase idToken) | `Authorization: Bearer <idToken>` | `API_FIREBASE_PROJECT_ID`, `API_FIREBASE_API_KEY` |
| **Expensify** | (expense export) | Partner key | per provider | `API_EXPENSIFY_PARTNER_KEY` |
| **Ramp** | (expense export) | OAuth2 | `Authorization: Bearer` | `API_RAMP_CLIENT_ID`, `API_RAMP_CLIENT_SECRET` |
| **Brex** | (expense export) | OAuth2 / token | `Authorization: Bearer` | `API_BREX_CLIENT_ID` |
| **Divvy (BILL Spend & Expense)** | (expense export) | OAuth2 / token | `Authorization: Bearer` | `API_DIVVY_CLIENT_ID` |

### Endpoint specifics (from `Endpoints.swift`)

- **FlightAware** — `GET /flights/{ident}` (e.g. `AA100`). Response is
  `FlightSearchResponse { flights: [Flight], num_pages }`.
- **Claude** — `POST /v1/messages`, headers `x-api-key` + `anthropic-version: 2023-06-01`,
  `Content-Type: application/json`. Model id in iOS: **`claude-sonnet-4-6`**.
  Body: `{ model, max_tokens, system, messages: [{role, content}], stream }`;
  streaming yields SSE events, `content_block_delta` carries text deltas (iOS
  accumulates cumulative content).
- **Google Vision** — `POST /v1/images:annotate?key=…` (OCR for receipt scan).
- **Expedia** — OAuth token `POST https://api.expediagroup.com/identity/oauth2/v3/token`;
  search `GET https://test.api.expediagroup.com/v3/properties/availability`.
- **Uber** — `GET /v1.2/estimates/price?start_latitude&start_longitude&end_latitude&end_longitude`.
- **Lyft** — token `POST https://api.lyft.com/oauth/token`;
  cost `GET /v1/cost?start_lat&start_lng&end_lat&end_lng`.
- **SITA WorldTracer** — `GET /baggage/v1/baggage/{tagNumber}` (10-digit IATA bag tag).
- **Enterprise/Hertz/National** — `GET …/availability|search?pickup…&dropoff…&dates…`
  (note differing param + header names: Hertz header is `api-key`, the other two
  `x-api-key`); all also expose iOS app deep links / App Store URLs (Android port
  uses package deep links / Play Store URLs instead).

---

## 2. Secrets flow

iOS: `Secrets.xcconfig` → `Info.plist` keys → `AppSecrets.value(for:)` →
`AppSecrets.isConfigured(_:)` gates live-vs-mock. **An unset / placeholder value
(empty, `YOUR_…`, or `REPLACE_ME`) returns nil**, and call sites fall back to
mock data.

Android equivalent:

```
local.properties  (git-ignored, per-developer)
        │  read at build time
        ▼
app/build.gradle.kts  → buildConfigField(...)
        │
        ▼
BuildConfig.API_*  (generated constants)
        │  wrapped + validated
        ▼
core.secrets.Secrets  (object; isConfigured() == iOS AppSecrets.isConfigured)
        │
        ▼
Repository: Secrets.isConfigured(key) ? liveApi() : MockData
```

### `app/build.gradle.kts`

```kotlin
import java.util.Properties

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(name: String): String = localProps.getProperty(name) ?: ""

android {
    buildFeatures { buildConfig = true }
    defaultConfig {
        // Strings must be quoted for buildConfigField("String", …)
        buildConfigField("String", "API_FLIGHTAWARE",          "\"${secret("API_FLIGHTAWARE")}\"")
        buildConfigField("String", "API_ANTHROPIC",            "\"${secret("API_ANTHROPIC")}\"")
        buildConfigField("String", "API_GOOGLE_VISION",        "\"${secret("API_GOOGLE_VISION")}\"")
        buildConfigField("String", "API_EXPEDIA_CLIENT_ID",    "\"${secret("API_EXPEDIA_CLIENT_ID")}\"")
        buildConfigField("String", "API_EXPEDIA_CLIENT_SECRET","\"${secret("API_EXPEDIA_CLIENT_SECRET")}\"")
        buildConfigField("String", "API_AMADEUS_CLIENT_ID",    "\"${secret("API_AMADEUS_CLIENT_ID")}\"")
        buildConfigField("String", "API_AMADEUS_CLIENT_SECRET","\"${secret("API_AMADEUS_CLIENT_SECRET")}\"")
        buildConfigField("String", "API_DUFFEL",               "\"${secret("API_DUFFEL")}\"")
        buildConfigField("String", "API_SITA_WORLDTRACER",     "\"${secret("API_SITA_WORLDTRACER")}\"")
        buildConfigField("String", "API_UBER_SERVER_TOKEN",    "\"${secret("API_UBER_SERVER_TOKEN")}\"")
        buildConfigField("String", "API_LYFT_CLIENT_ID",       "\"${secret("API_LYFT_CLIENT_ID")}\"")
        buildConfigField("String", "API_LYFT_CLIENT_SECRET",   "\"${secret("API_LYFT_CLIENT_SECRET")}\"")
        buildConfigField("String", "API_ENTERPRISE",           "\"${secret("API_ENTERPRISE")}\"")
        buildConfigField("String", "API_HERTZ",                "\"${secret("API_HERTZ")}\"")
        buildConfigField("String", "API_NATIONAL",             "\"${secret("API_NATIONAL")}\"")
        buildConfigField("String", "API_FIREBASE_PROJECT_ID",  "\"${secret("API_FIREBASE_PROJECT_ID")}\"")
        buildConfigField("String", "API_FIREBASE_API_KEY",     "\"${secret("API_FIREBASE_API_KEY")}\"")
        buildConfigField("String", "API_EXPENSIFY_PARTNER_KEY","\"${secret("API_EXPENSIFY_PARTNER_KEY")}\"")
        buildConfigField("String", "API_RAMP_CLIENT_ID",       "\"${secret("API_RAMP_CLIENT_ID")}\"")
        buildConfigField("String", "API_RAMP_CLIENT_SECRET",   "\"${secret("API_RAMP_CLIENT_SECRET")}\"")
        buildConfigField("String", "API_BREX_CLIENT_ID",       "\"${secret("API_BREX_CLIENT_ID")}\"")
        buildConfigField("String", "API_DIVVY_CLIENT_ID",      "\"${secret("API_DIVVY_CLIENT_ID")}\"")
    }
}
```

### `core/secrets/Secrets.kt`

```kotlin
package com.jetsetter.pro.core.secrets

import com.jetsetter.pro.BuildConfig

object Secrets {
    enum class Key(val raw: String) {
        FLIGHT_AWARE(BuildConfig.API_FLIGHTAWARE),
        ANTHROPIC(BuildConfig.API_ANTHROPIC),
        GOOGLE_VISION(BuildConfig.API_GOOGLE_VISION),
        EXPEDIA_CLIENT_ID(BuildConfig.API_EXPEDIA_CLIENT_ID),
        EXPEDIA_CLIENT_SECRET(BuildConfig.API_EXPEDIA_CLIENT_SECRET),
        AMADEUS_CLIENT_ID(BuildConfig.API_AMADEUS_CLIENT_ID),
        AMADEUS_CLIENT_SECRET(BuildConfig.API_AMADEUS_CLIENT_SECRET),
        DUFFEL(BuildConfig.API_DUFFEL),
        SITA_WORLDTRACER(BuildConfig.API_SITA_WORLDTRACER),
        UBER_SERVER_TOKEN(BuildConfig.API_UBER_SERVER_TOKEN),
        LYFT_CLIENT_ID(BuildConfig.API_LYFT_CLIENT_ID),
        LYFT_CLIENT_SECRET(BuildConfig.API_LYFT_CLIENT_SECRET),
        ENTERPRISE(BuildConfig.API_ENTERPRISE),
        HERTZ(BuildConfig.API_HERTZ),
        NATIONAL(BuildConfig.API_NATIONAL),
        FIREBASE_PROJECT_ID(BuildConfig.API_FIREBASE_PROJECT_ID),
        FIREBASE_API_KEY(BuildConfig.API_FIREBASE_API_KEY),
        EXPENSIFY_PARTNER_KEY(BuildConfig.API_EXPENSIFY_PARTNER_KEY),
        RAMP_CLIENT_ID(BuildConfig.API_RAMP_CLIENT_ID),
        RAMP_CLIENT_SECRET(BuildConfig.API_RAMP_CLIENT_SECRET),
        BREX_CLIENT_ID(BuildConfig.API_BREX_CLIENT_ID),
        DIVVY_CLIENT_ID(BuildConfig.API_DIVVY_CLIENT_ID),
    }

    /** Mirrors iOS AppSecrets.value(for:) — nil/blank/placeholder ⇒ null. */
    fun value(key: Key): String? {
        val t = key.raw.trim()
        if (t.isEmpty()) return null
        if (t.startsWith("YOUR_") || t == "REPLACE_ME") return null
        return t
    }

    /** Mirrors iOS AppSecrets.isConfigured(_:). Gate live vs. MockData. */
    fun isConfigured(key: Key): Boolean = value(key) != null
}
```

### `local.properties.example`

```bash
# JetSetter Pro — Android secrets (copy to local.properties; git-ignored)
# Any key left blank, or set to YOUR_… / REPLACE_ME, disables its feature's
# live calls and falls back to bundled MockData (mirrors iOS AppSecrets).

# Flights
API_FLIGHTAWARE=

# AI
API_ANTHROPIC=
API_GOOGLE_VISION=

# Hotels (Expedia Rapid — OAuth2 client credentials)
API_EXPEDIA_CLIENT_ID=
API_EXPEDIA_CLIENT_SECRET=

# Flight offers / rebooking
API_AMADEUS_CLIENT_ID=
API_AMADEUS_CLIENT_SECRET=
API_DUFFEL=

# Baggage
API_SITA_WORLDTRACER=

# Ground transport
API_UBER_SERVER_TOKEN=
API_LYFT_CLIENT_ID=
API_LYFT_CLIENT_SECRET=

# Rental cars
API_ENTERPRISE=
API_HERTZ=
API_NATIONAL=

# Firebase backend (Auth + Firestore REST)
API_FIREBASE_PROJECT_ID=
API_FIREBASE_API_KEY=

# Expense providers
API_EXPENSIFY_PARTNER_KEY=
API_RAMP_CLIENT_ID=
API_RAMP_CLIENT_SECRET=
API_BREX_CLIENT_ID=
API_DIVVY_CLIENT_ID=
```

> Do **not** commit `local.properties`. Keep `API_*` keys out of VCS; the example
> file documents the contract. For CI, inject via Gradle properties / env.

---

## 3. Persistence strategy

| Concern | iOS | Android |
|---|---|---|
| Structured app data (trips, expenses, bags, wallet, loyalty, docs, disruptions) | `UserDefaults` + JSON `Codable` blobs / per-feature stores | **Room** (entity per model, DAO, `@TypeConverters`) — source of truth, offline-first |
| User preferences | `UserDefaults` (`pref_*` keys, `UserPreferences` singleton) | **DataStore (Preferences)** |
| Session tokens + vault secrets | Keychain + CryptoKit (`VaultCrypto`) | **EncryptedSharedPreferences** (session) + **Tink AES-GCM** via Android Keystore (vault) |
| Cross-device sync | Firestore REST (`payload` JSON per doc) | **Firestore REST** — identical doc shape |

### 3a. Room

- One `@Entity` per persisted model (`TripEntity`, `ExpenseEntity`, `BagEntity`,
  `WalletItemEntity`, `LoyaltyAccountEntity`, `VaultDocumentEntity`,
  `DisruptionEventEntity`, …). Keep the domain `data class` (§4) separate from the
  entity and map between them, or annotate the domain class directly for simple
  cases.
- **`UUID` → `String`** primary keys (`@PrimaryKey val id: String`).
- **`Date`/`Instant` → store as ISO-8601 `String`** (or epoch millis `Long`) via a
  `TypeConverter`, matching the iOS `.iso8601` JSON strategy so synced payloads
  round-trip.
- Nested collections (`Trip.items`, `Trip.packingList`, `Bag.scanHistory`,
  `WalletItem.rawData`, `DisruptionEvent.alternatives`) → either child tables with
  relations, or a Moshi-serialized JSON column via `TypeConverter`. iOS stores
  them inline, so JSON columns are the lowest-friction parity path.

```kotlin
class Converters {
    private val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()

    @TypeConverter fun instantToString(v: Instant?): String? = v?.toString()          // ISO-8601
    @TypeConverter fun stringToInstant(v: String?): Instant? = v?.let(Instant::parse)

    @TypeConverter fun mapToJson(v: Map<String, String>?): String? =
        v?.let { moshi.adapter<Map<String, String>>(/* type */).toJson(it) }
    @TypeConverter fun jsonToMap(v: String?): Map<String, String>? =
        v?.let { moshi.adapter<Map<String, String>>(/* type */).fromJson(it) }
}
```

### 3b. DataStore (preferences) — port of `UserPreferences`

Mirror the iOS `pref_*` keys and defaults (note: **dark theme** and
**flight/trip reminders ON** by default; expense reminders OFF):

| DataStore key | Type | Default |
|---|---|---|
| `pref_displayName` | String | "" |
| `pref_email` | String | "" |
| `pref_homeAirport` | String | "" |
| `pref_currency` | String | "USD" |
| `pref_distanceUnit` | String | "miles" |
| `pref_colorScheme` | String | "dark" |
| `pref_flightAlerts` | Bool | true |
| `pref_tripReminders` | Bool | true |
| `pref_expenseReminders` | Bool | false |
| `pref_onboarded` | Bool | false |

### 3c. EncryptedSharedPreferences / Tink (port of `VaultCrypto`)

- **Session** (Firebase `idToken`, `refreshToken`, `expiresAt`, uid) →
  `EncryptedSharedPreferences` (MasterKey AES256-GCM). iOS keeps these in
  `FirebaseSession`.
- **Vault** (DocumentVault / IdentityVault): document numbers are **AES-GCM
  encrypted + base64** before persistence/sync. iOS encrypts with CryptoKit
  (`docNumberEncrypted`, never persists clear-text). Android: **Tink `Aead`**
  keyset in Android Keystore; gate decryption behind `BiometricPrompt`.

### 3d. Firebase Firestore REST sync

Exactly mirrors iOS `FirebaseService` — **no Firebase SDK**.

- **Base:** `https://firestore.googleapis.com/v1/projects/{projectID}/databases/(default)/documents`
- **Auth:** `Authorization: Bearer <idToken>` (from Identity Toolkit sign-in;
  refresh via `https://securetoken.googleapis.com/v1/token`).
- **Document shape:** each doc has a **single `payload` field** holding the
  JSON-encoded model as a `stringValue`. The console shows opaque payloads (by
  design for the MVP).
- **Upsert:** `PATCH …/{path}` with body
  `{ "fields": { "payload": { "stringValue": "<json>" } } }`.
- **Per-user collections** (path `users/{uid}/{collection}/{docId}`):
  `trips`, `expenses`, `walletItems`, `packingLists`, `disruptionEvents`
  (extensible — add `bags`, `loyaltyAccounts`, `vaultDocuments` as those land).
- **Delete-all:** REST has no recursive delete — list doc IDs per collection
  (`GET .../{collection}` → read `documents[].name`), `DELETE` each, then delete
  the auth account.

```kotlin
// PATCH upsert
suspend fun upsert(uid: String, collection: String, docId: String, payloadJson: String) {
    val url = "$firestoreBase/users/$uid/$collection/$docId"
    val body = mapOf("fields" to mapOf("payload" to mapOf("stringValue" to payloadJson)))
    httpPatch(url, body, bearer = session.idToken)   // 200 ⇒ ok
}
```

---

## 4. Core data models (Kotlin)

Ported from the iOS `*Model.swift` files. Conventions:
**`UUID` → `String`** (default `UUID.randomUUID().toString()`), **`Date` →
`java.time.Instant`** (serialize ISO-8601), Swift optionals → Kotlin nullables.
`@Json(name = "…")` shows the snake_case wire key where iOS overrides it (Firestore
columns / API fields).

```kotlin
package com.jetsetter.pro.core.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import java.time.Instant
import java.util.UUID

// ── Trip / Itinerary ────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class Trip(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val destination: String,
    val startDate: Instant,
    val endDate: Instant,
    val items: List<ItineraryItem> = emptyList(),
    val packingList: List<PackingItem> = emptyList(),
)

@JsonClass(generateAdapter = true)
data class ItineraryItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val type: ItineraryItemType,
    val startDate: Instant,
    val endDate: Instant? = null,
    val location: String? = null,
    val notes: String? = null,
    val calendarEventIdentifier: String? = null,
) {
    val isSyncedToCalendar: Boolean get() = calendarEventIdentifier != null
}

@JsonClass(generateAdapter = false)
enum class ItineraryItemType(
    val displayName: String,
    val colorHex: String,   // literal — see DESIGN_SYSTEM.md §7
) {
    @Json(name = "flight")     FLIGHT("Flight", "#0066CC"),
    @Json(name = "hotel")      HOTEL("Hotel", "#0A7A5E"),
    @Json(name = "activity")   ACTIVITY("Activity", "#C8860A"),
    @Json(name = "transport")  TRANSPORT("Transport", "#1A2E40"),
    @Json(name = "restaurant") RESTAURANT("Restaurant", "#CC3B1E"),
}

@JsonClass(generateAdapter = true)
data class PackingItem(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val isPacked: Boolean = false,
)

// ── Expenses ────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class Expense(
    val id: String = UUID.randomUUID().toString(),
    val amount: Double,
    val currency: String = "USD",
    val category: ExpenseCategory,
    val merchant: String,
    val date: Instant = Instant.now(),
    val notes: String? = null,
    val receiptText: String? = null,          // raw OCR text
    val mileageDistance: Double? = null,       // miles, only for MILEAGE
) {
    companion object {
        const val IRS_MILEAGE_RATE_PER_MILE = 0.67   // 2024 IRS rate
        fun mileageAmount(miles: Double): Double =
            Math.round(miles * IRS_MILEAGE_RATE_PER_MILE * 100) / 100.0
    }
}

@JsonClass(generateAdapter = false)
enum class ExpenseCategory(val displayName: String, val colorHex: String) {
    @Json(name = "food")          FOOD("Food & Dining", "#CC3B1E"),
    @Json(name = "transport")     TRANSPORT("Transportation", "#0066CC"),
    @Json(name = "accommodation") ACCOMMODATION("Accommodation", "#0A7A5E"),
    @Json(name = "entertainment") ENTERTAINMENT("Entertainment", "#C8860A"),
    @Json(name = "business")      BUSINESS("Business", "#1A2E40"),
    @Json(name = "shopping")      SHOPPING("Shopping", "#7B2D8B"),
    @Json(name = "medical")       MEDICAL("Medical", "#E5383B"),
    @Json(name = "mileage")       MILEAGE("Mileage", "#4E9AF1"),
    @Json(name = "other")         OTHER("Other", "#888888"),
}

// ── Flight (FlightAware) ────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class FlightSearchResponse(
    val flights: List<Flight>,
    @Json(name = "num_pages") val numPages: Int,
)

@JsonClass(generateAdapter = true)
data class Flight(
    @Json(name = "fa_flight_id") val faFlightId: String,   // id = faFlightId
    val ident: String,
    @Json(name = "ident_iata") val identIata: String? = null,
    @Json(name = "operator") val operatorName: String? = null,
    @Json(name = "flight_number") val flightNumber: String? = null,
    val origin: Airport,
    val destination: Airport,
    val status: String,
    @Json(name = "aircraft_type") val aircraftType: String? = null,
    @Json(name = "gate_origin") val gateOrigin: String? = null,
    @Json(name = "gate_destination") val gateDestination: String? = null,
    @Json(name = "terminal_origin") val terminalOrigin: String? = null,
    @Json(name = "terminal_destination") val terminalDestination: String? = null,
    @Json(name = "baggage_claim") val baggageClaim: String? = null,
    @Json(name = "departure_delay") val departureDelay: Int? = null,   // seconds
    @Json(name = "arrival_delay") val arrivalDelay: Int? = null,       // seconds
    @Json(name = "progress_percent") val progressPercent: Int? = null, // 0..100
    val cancelled: Boolean = false,
    val diverted: Boolean = false,
    @Json(name = "scheduled_out") val scheduledOut: Instant? = null,
    @Json(name = "estimated_out") val estimatedOut: Instant? = null,
    @Json(name = "actual_out") val actualOut: Instant? = null,
    @Json(name = "scheduled_in") val scheduledIn: Instant? = null,
    @Json(name = "estimated_in") val estimatedIn: Instant? = null,
    @Json(name = "actual_in") val actualIn: Instant? = null,
) {
    val id: String get() = faFlightId
    val isAirborne: Boolean get() = actualOut != null && actualIn == null && !cancelled
    val departureDelayMinutes: Int? get() = departureDelay?.div(60)
    val arrivalDelayMinutes: Int? get() = arrivalDelay?.div(60)
    val bestDepartureTime: Instant? get() = actualOut ?: estimatedOut ?: scheduledOut
    val bestArrivalTime: Instant? get() = actualIn ?: estimatedIn ?: scheduledIn
}

@JsonClass(generateAdapter = true)
data class Airport(
    val code: String? = null,
    @Json(name = "code_icao") val codeIcao: String? = null,
    @Json(name = "code_iata") val codeIata: String? = null,
    val name: String? = null,
    val city: String? = null,
    val timezone: String? = null,
) {
    val displayName: String get() = city ?: codeIata ?: code ?: "Unknown"
}

// ── Travel Wallet ───────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class WalletItem(
    val id: String = UUID.randomUUID().toString(),
    @Json(name = "trip_id") val tripId: String? = null,
    @Json(name = "item_type") val itemType: WalletItemType,
    val title: String,
    @Json(name = "confirmation_number") val confirmationNumber: String? = null,
    val date: Instant,
    @Json(name = "raw_data") val rawData: Map<String, String> = emptyMap(),
    @Json(name = "created_at") val createdAt: Instant = Instant.now(),
) {
    // Boarding-pass / hotel / car / insurance / event accessors read rawData[...]
    val airline: String? get() = rawData["airline"]
    val flightNumber: String? get() = rawData["flight_number"]
    val seatNumber: String? get() = rawData["seat_number"]
    // status is computed (upcoming/active/completed) from date + rawData["end_date"]
}

@JsonClass(generateAdapter = false)
enum class WalletItemType(val displayName: String, val colorHex: String) {
    @Json(name = "boarding_pass")     BOARDING_PASS("Boarding Pass", "#0066CC"),
    @Json(name = "hotel_reservation") HOTEL_RESERVATION("Hotel Reservation", "#0A7A5E"),
    @Json(name = "car_rental")        CAR_RENTAL("Car Rental", "#C8860A"),
    @Json(name = "event_ticket")      EVENT_TICKET("Event Ticket", "#7B3FBF"),
    @Json(name = "travel_insurance")  TRAVEL_INSURANCE("Travel Insurance", "#CC3B1E"),
}

enum class WalletItemStatus(val displayName: String, val colorHex: String) {
    UPCOMING("Upcoming", "#0066CC"),
    ACTIVE("Active", "#0A7A5E"),
    COMPLETED("Completed", "#8B92A8"),
}

// ── Luggage ─────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class Bag(
    val id: String = UUID.randomUUID().toString(),
    val nickname: String,
    val description: String = "",
    val airline: String? = null,
    val flightNumber: String? = null,
    val bagTagNumber: String? = null,     // 10-digit IATA tag for WorldTracer
    val hasAirTag: Boolean = false,
    val status: BagStatus = BagStatus.UNKNOWN,
    val lastLocation: String? = null,
    val lastChecked: Instant? = null,
    val scanHistory: List<BagScanEvent> = emptyList(),
) {
    val isTrackable: Boolean get() = bagTagNumber != null || hasAirTag
}

@JsonClass(generateAdapter = false)
enum class BagStatus(val displayName: String, val colorHex: String) {
    @Json(name = "checked_in")  CHECKED_IN("Checked In", "#0066CC"),
    @Json(name = "in_transit")  IN_TRANSIT("In Transit", "#0066CC"),
    @Json(name = "on_belt")     ON_BELT("On Belt", "#3B9EF0"),
    @Json(name = "loading")     LOADING("Loading Aircraft", "#7B3FBF"),
    @Json(name = "on_aircraft") ON_AIRCRAFT("Secured in Cargo", "#1DB97D"),
    @Json(name = "arrived")     ARRIVED("Arrived", "#0A7A5E"),
    @Json(name = "at_carousel") AT_CAROUSEL("At Baggage Claim", "#0A7A5E"),
    @Json(name = "delayed")     DELAYED("Delayed", "#C8860A"),
    @Json(name = "missing")     MISSING("Cannot Locate", "#CC3B1E"),
    @Json(name = "delivered")   DELIVERED("Delivered", "#0A7A5E"),
    @Json(name = "unknown")     UNKNOWN("Unknown", "#888888"),
}

@JsonClass(generateAdapter = true)
data class BagScanEvent(
    val id: String = UUID.randomUUID().toString(),
    val timestamp: Instant,
    val location: String,
    val scanType: ScanType,
    val note: String? = null,
) {
    enum class ScanType(val displayName: String) {
        CHECK_IN("Check-In"), ON_BELT("On Belt"), LOADER_TRANSFER("Loader Transfer"),
        SECURED_IN_CARGO("Secured in Cargo"), TAKEOFF("Takeoff"),
        LANDED("Landed"), CLAIMED("Claimed"),
    }
}

// ── Disruption ──────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class DisruptionEvent(
    val id: String = UUID.randomUUID().toString(),
    @Json(name = "user_id") val userId: String,
    @Json(name = "trip_id") val tripId: String,
    @Json(name = "event_type") val eventType: DisruptionType,
    @Json(name = "original_flight") val originalFlight: FlightSnapshot,
    val alternatives: List<AlternativeFlight> = emptyList(),
    @Json(name = "response_actions") val responseActions: ResponseActions = ResponseActions(),
    val resolved: Boolean = false,
    @Json(name = "rebooking_url") val rebookingUrl: String? = null,
    @Json(name = "hotel_contact") val hotelContact: String? = null,
    @Json(name = "uber_deep_link") val uberDeepLink: String? = null,
    @Json(name = "insurance_document_id") val insuranceDocumentId: String? = null,
    @Json(name = "created_at") val createdAt: Instant = Instant.now(),
) {
    val bestAlternative: AlternativeFlight? get() = alternatives.minByOrNull { it.price }
    val earliestAlternative: AlternativeFlight? get() = alternatives.minByOrNull { it.departure }
}

@JsonClass(generateAdapter = false)
enum class DisruptionType(val displayName: String, val colorHex: String) {
    @Json(name = "cancellation")      CANCELLATION("Flight Cancelled", "#E84040"),
    @Json(name = "major_delay")       MAJOR_DELAY("Major Delay", "#E8A020"),       // > 45 min
    @Json(name = "gate_change")       GATE_CHANGE("Gate Changed", "#3B9EF0"),
    @Json(name = "missed_connection") MISSED_CONNECTION("Missed Connection Risk", "#E84040"),
}

@JsonClass(generateAdapter = true)
data class ResponseActions(
    @Json(name = "alternatives_found") val alternativesFound: Boolean = false,
    @Json(name = "rebooking_checked") val rebookingChecked: Boolean = false,
    @Json(name = "hotel_notified") val hotelNotified: Boolean = false,
    @Json(name = "uber_reroute_ready") val uberRerouteReady: Boolean = false,
    @Json(name = "insurance_surfaced") val insuranceSurfaced: Boolean = false,
) {
    val isFullyHandled: Boolean get() =
        alternativesFound && rebookingChecked && hotelNotified && uberRerouteReady && insuranceSurfaced
}

@JsonClass(generateAdapter = true)
data class FlightSnapshot(
    @Json(name = "flight_number") val flightNumber: String,
    val airline: String,
    val origin: String,        // IATA
    val destination: String,   // IATA
    @Json(name = "scheduled_departure") val scheduledDeparture: Instant,
    @Json(name = "original_gate") val originalGate: String? = null,
    val status: String,
    @Json(name = "delay_minutes") val delayMinutes: Int? = null,
)

@JsonClass(generateAdapter = true)
data class AlternativeFlight(
    val id: String = UUID.randomUUID().toString(),
    @Json(name = "flight_number") val flightNumber: String,
    val airline: String,
    val origin: String,
    val destination: String,
    val departure: Instant,
    val arrival: Instant,
    @Json(name = "duration_minutes") val durationMinutes: Int,
    val price: Double,
    val currency: String,
    @Json(name = "available_seats") val availableSeats: Int,
    @Json(name = "cabin_class") val cabinClass: String,
    @Json(name = "booking_token") val bookingToken: String? = null,  // Amadeus offer id
)

// ── Document Vault ──────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class VaultDocument(
    val id: String = UUID.randomUUID().toString(),
    @Json(name = "doc_type") val documentType: DocumentType,
    @Json(name = "issuing_country") val issuingCountry: String? = null,
    @Json(name = "doc_number_encrypted") val docNumberEncrypted: String? = null, // AES-GCM + base64
    @Transient val docNumberClear: String? = null,   // in-memory only, post-biometric; never persisted
    @Json(name = "expiry_date") val expiryDate: Instant? = null,
    @Json(name = "photo_url") val photoUrl: String? = null,           // Firebase Storage path
    val notes: String? = null,
    @Json(name = "created_at") val createdAt: Instant = Instant.now(),
)

@JsonClass(generateAdapter = false)
enum class DocumentType(val displayName: String, val colorHex: String) {
    @Json(name = "passport")          PASSPORT("Passport", "#0055CC"),
    @Json(name = "visa")              VISA("Visa", "#7B3FBF"),
    @Json(name = "travel_insurance")  TRAVEL_INSURANCE("Travel Insurance", "#CC3B1E"),
    @Json(name = "vaccination")       VACCINATION("Vaccination Records", "#0A7A5E"),
    @Json(name = "emergency_contact") EMERGENCY_CONTACT("Emergency Contacts", "#E84040"),
    @Json(name = "drivers_license")   DRIVERS_LICENSE("Driver's License", "#C8860A"),
    @Json(name = "global_entry")      GLOBAL_ENTRY("Global Entry / TSA Pre✓", "#1DB97D"),
}

// ── Loyalty ─────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class LoyaltyAccount(
    val id: String = UUID.randomUUID().toString(),
    val programID: String,           // catalog id, e.g. "UA", "MARRIOTT"
    val memberNumber: String,
    val memberSince: Instant? = null,
    val balance: Int = 0,
    val tier: String = "",           // "Silver" / "Gold" / "Platinum" / "Diamond"
    val tierExpiration: Instant? = null,
    val notes: String? = null,
)

// ── Preferences (also persisted in DataStore — see §3b) ─────────────

data class UserPreferences(
    val displayName: String = "",
    val email: String = "",
    val homeAirport: String = "",
    val currency: String = "USD",
    val distanceUnit: DistanceUnit = DistanceUnit.MILES,
    val colorScheme: ColorSchemePreference = ColorSchemePreference.DARK,  // default dark
    val flightAlertsEnabled: Boolean = true,
    val tripRemindersEnabled: Boolean = true,
    val expenseRemindersEnabled: Boolean = false,
    val hasCompletedOnboarding: Boolean = false,
)

enum class DistanceUnit(val abbreviation: String) { MILES("mi"), KILOMETERS("km") }
enum class ColorSchemePreference { SYSTEM, LIGHT, DARK }
```

> The iOS `WorldTracerBagResponse` (SITA trace result) and `OCRReceiptResult`
> (Vision intermediate) are network DTOs, not persisted models — define them in
> `core.network.dto` and map into `Bag` / `Expense`. `WorldTracerBagResponse`
> carries a `mappedStatus` that translates the upstream status string to
> `BagStatus` (see iOS `LuggageModel.swift`).

---

## 5. APIClient & error model

Retrofit + OkHttp port of iOS `APIClient` / `APIError`. Matches the iOS behavior:
**snake_case** decoding (Moshi), **ISO-8601** dates, **retry 3× for GET / 1× for
POST** (POST never double-submitted), **capped exponential backoff with jitter**
honoring `Retry-After`.

### 5a. Error sealed class (port of `APIError`)

```kotlin
package com.jetsetter.pro.core.network

sealed class ApiError(message: String? = null, cause: Throwable? = null) : Exception(message, cause) {
    data object InvalidUrl : ApiError("The request URL was invalid.")
    data object Unauthorized : ApiError("Not authorized — check your API credentials.")            // 401
    data class RateLimited(val retryAfterSeconds: Double?) :                                          // 429
        ApiError(retryAfterSeconds?.let { "Rate limited. Try again in about ${it.toInt()}s." }
            ?: "Rate limited. Please try again shortly.")
    data class RequestFailed(val statusCode: Int) : ApiError("Request failed with status code $statusCode.")
    data class DecodingFailed(val error: Throwable) : ApiError("Failed to decode the response.", error)
    data class Unknown(val error: Throwable) : ApiError("An unexpected error occurred.", error)
}
```

### 5b. OkHttp / Moshi / Retrofit setup

```kotlin
val moshi = Moshi.Builder()
    .add(InstantIso8601Adapter())                 // Instant ⇄ ISO-8601 string
    .add(KotlinJsonAdapterFactory())
    .build()
// Moshi has no global snake_case mode; per-field @Json(name=...) is used above
// to mirror iOS .convertFromSnakeCase. (Alternatively wrap with a snake_case
// JsonAdapter.Factory.)

val client = OkHttpClient.Builder()
    .callTimeout(30, TimeUnit.SECONDS)            // iOS timeoutIntervalForRequest = 30
    .addInterceptor(AuthHeaderInterceptor())      // injects x-apikey / x-api-key / bearer per host
    .addInterceptor(RetryInterceptor())           // see 5c
    .build()

val retrofit = Retrofit.Builder()
    .baseUrl("https://aeroapi.flightaware.com/aeroapi/")
    .client(client)
    .addConverterFactory(MoshiConverterFactory.create(moshi))
    .build()
```

### 5c. Retry interceptor (port of iOS `perform`/`backoff`)

```kotlin
class RetryInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val maxAttempts = if (request.method == "GET") 3 else 1   // POST: single attempt
        var attempt = 0
        var lastError: IOException? = null

        while (attempt < maxAttempts) {
            attempt++
            try {
                val response = chain.proceed(request)
                when (response.code) {
                    in 200..299 -> return response
                    401 -> throw ApiError.Unauthorized
                    429 -> {
                        val retryAfter = response.header("Retry-After")?.toDoubleOrNull()
                        if (attempt < maxAttempts) { response.close(); backoff(attempt, retryAfter); continue }
                        throw ApiError.RateLimited(retryAfter)
                    }
                    in 500..599 -> {
                        if (attempt < maxAttempts) { response.close(); backoff(attempt); continue }
                        throw ApiError.RequestFailed(response.code)
                    }
                    else -> throw ApiError.RequestFailed(response.code)   // incl. 404 (SITA matches on it)
                }
            } catch (e: IOException) {        // transient connectivity
                lastError = e
                if (attempt < maxAttempts) { backoff(attempt); continue }
                throw ApiError.Unknown(e)
            }
        }
        throw ApiError.Unknown(lastError ?: IOException("Exhausted retries"))
    }

    /** Exponential backoff + jitter, honoring server Retry-After; capped at 10s. */
    private fun backoff(attempt: Int, suggested: Double? = null) {
        val base = suggested ?: minOf(Math.pow(2.0, (attempt - 1).toDouble()), 8.0)
        val delay = minOf(base + Math.random() * 0.3, 10.0)
        Thread.sleep((delay * 1000).toLong())
    }
}
```

> The iOS client retries on these transient `URLError`s: timed out, connection
> lost, cannot-connect/find host, DNS failure, not-connected. OkHttp surfaces
> these as `IOException` subtypes (`SocketTimeoutException`, `UnknownHostException`,
> `ConnectException`) — the `catch (IOException)` branch above covers them. Throw
> typed `ApiError`s from the interceptor (do not swallow), or convert in a
> `CallAdapter`/repository `runCatching` boundary so ViewModels see `ApiError`.
>
> `Thread.sleep` inside the interceptor blocks the OkHttp dispatcher thread, which
> is fine since all calls run on `Dispatchers.IO` from suspend repositories. If you
> prefer non-blocking backoff, implement retry in the repository with
> `delay(...)` instead of an interceptor.

### 5d. AI streaming (Claude) note

`AIService` streams from `POST /v1/messages` with `stream: true`. Use OkHttp SSE
(`okhttp-sse` `EventSources.createFactory`) and emit a Kotlin `Flow<String>` of
**cumulative** content (accumulate `content_block_delta` text deltas), matching
the iOS contract where each yielded value is the full text so far. Headers:
`x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
Model id: `claude-sonnet-4-6`. When `API_ANTHROPIC` is unset, fall back to an
on-device model (ML Kit / Gemini Nano) or a canned response, mirroring iOS's
on-device-first design.
