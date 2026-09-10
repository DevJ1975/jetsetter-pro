// File: Core/Services/OfflineKitService.swift
//
// Pre-caches everything a traveler needs while in flight or in a country with
// poor data: exchange rates, current weather snapshot at destination, country
// essentials, and a JSON archive of the trip's itinerary + wallet items. The
// archive is persisted to UserDefaults keyed by trip ID so OfflineKitView can
// surface its status.

import Foundation
import CoreLocation

// MARK: - Snapshot

struct OfflineTripSnapshot: Codable {
    let tripID: UUID
    let destinationName: String
    let cachedAt: Date
    /// End of the trip window. The cached JSON (itinerary, wallet, country
    /// essentials) stays usable through this date even without connectivity.
    let tripEndDate: Date
    /// When the perishable parts (weather, FX rates) should be considered
    /// out of date. The kit is still usable past this point — just "stale".
    let perishableExpiresAt: Date
    let exchangeRatesBase: String?
    let exchangeRatesCount: Int
    let hasDestinationWeather: Bool
    let hasCountryEssentials: Bool
    let itineraryItemCount: Int
    let walletItemCount: Int
    let payload: OfflinePayload

    /// True while the cache is still usable offline — i.e. the trip hasn't
    /// ended yet. The static parts (itinerary, wallet, country notes) never
    /// go bad before the trip is over, so we base usability on the trip window
    /// rather than an arbitrary 24h TTL.
    var isFresh: Bool { tripEndDate > Date() }

    /// True when the kit is usable but its perishable data (weather / exchange
    /// rates) is likely out of date and worth refreshing when back online.
    var isStale: Bool { perishableExpiresAt <= Date() }

    /// The date the kit stops being usable offline (the trip's end). Retained
    /// under the old name so existing UI that showed a "Fresh until" date keeps
    /// compiling; it now reflects the trip window instead of a 24h TTL.
    var expiresAt: Date { tripEndDate }

    // Backward-compatible decoding: older persisted snapshots used a single
    // `expiresAt` (now + 24h) with no trip-window field. Map it onto the new
    // model so previously cached kits still load and don't false-expire.
    private enum CodingKeys: String, CodingKey {
        case tripID, destinationName, cachedAt, tripEndDate, perishableExpiresAt
        case expiresAt // legacy
        case exchangeRatesBase, exchangeRatesCount, hasDestinationWeather
        case hasCountryEssentials, itineraryItemCount, walletItemCount, payload
    }

    init(
        tripID: UUID,
        destinationName: String,
        cachedAt: Date,
        tripEndDate: Date,
        perishableExpiresAt: Date,
        exchangeRatesBase: String?,
        exchangeRatesCount: Int,
        hasDestinationWeather: Bool,
        hasCountryEssentials: Bool,
        itineraryItemCount: Int,
        walletItemCount: Int,
        payload: OfflinePayload
    ) {
        self.tripID = tripID
        self.destinationName = destinationName
        self.cachedAt = cachedAt
        self.tripEndDate = tripEndDate
        self.perishableExpiresAt = perishableExpiresAt
        self.exchangeRatesBase = exchangeRatesBase
        self.exchangeRatesCount = exchangeRatesCount
        self.hasDestinationWeather = hasDestinationWeather
        self.hasCountryEssentials = hasCountryEssentials
        self.itineraryItemCount = itineraryItemCount
        self.walletItemCount = walletItemCount
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripID          = try c.decode(UUID.self,   forKey: .tripID)
        destinationName = try c.decode(String.self, forKey: .destinationName)
        cachedAt        = try c.decode(Date.self,   forKey: .cachedAt)
        let legacyExpiry = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        // Prefer the new fields; fall back to the legacy 24h expiry when reading
        // an older snapshot so it neither crashes nor false-expires immediately.
        tripEndDate = try c.decodeIfPresent(Date.self, forKey: .tripEndDate)
            ?? legacyExpiry
            ?? cachedAt
        perishableExpiresAt = try c.decodeIfPresent(Date.self, forKey: .perishableExpiresAt)
            ?? legacyExpiry
            ?? cachedAt
        exchangeRatesBase    = try c.decodeIfPresent(String.self, forKey: .exchangeRatesBase)
        exchangeRatesCount   = try c.decode(Int.self,  forKey: .exchangeRatesCount)
        hasDestinationWeather = try c.decode(Bool.self, forKey: .hasDestinationWeather)
        hasCountryEssentials  = try c.decode(Bool.self, forKey: .hasCountryEssentials)
        itineraryItemCount    = try c.decode(Int.self,  forKey: .itineraryItemCount)
        walletItemCount       = try c.decode(Int.self,  forKey: .walletItemCount)
        payload               = try c.decode(OfflinePayload.self, forKey: .payload)
    }

    // Explicit encoder required: the `CodingKeys` enum carries a legacy `expiresAt`
    // case with no matching stored property, which prevents the compiler from
    // synthesizing `encode(to:)`. We write only the current fields (the legacy key
    // is decode-only, for reading older snapshots).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(destinationName, forKey: .destinationName)
        try c.encode(cachedAt, forKey: .cachedAt)
        try c.encode(tripEndDate, forKey: .tripEndDate)
        try c.encode(perishableExpiresAt, forKey: .perishableExpiresAt)
        try c.encodeIfPresent(exchangeRatesBase, forKey: .exchangeRatesBase)
        try c.encode(exchangeRatesCount, forKey: .exchangeRatesCount)
        try c.encode(hasDestinationWeather, forKey: .hasDestinationWeather)
        try c.encode(hasCountryEssentials, forKey: .hasCountryEssentials)
        try c.encode(itineraryItemCount, forKey: .itineraryItemCount)
        try c.encode(walletItemCount, forKey: .walletItemCount)
        try c.encode(payload, forKey: .payload)
    }
}

struct OfflinePayload: Codable {
    let itinerary: [OfflineItineraryItem]
    let wallet: [OfflineWalletEntry]
    let countryNotes: OfflineCountryNotes?
    let weatherSummary: String?
    let exchangeRateSummary: String?
}

struct OfflineItineraryItem: Codable {
    let title: String
    let type: String
    let startDate: Date
    let location: String?
    let notes: String?
}

struct OfflineWalletEntry: Codable {
    let title: String
    let type: String
    let confirmationNumber: String?
    let date: Date
}

struct OfflineCountryNotes: Codable {
    let countryName: String
    let emergencyGeneral: String?
    let emergencyPolice: String
    let waterSafe: Bool
    let plugTypes: [String]
    let voltage: String
    let tipping: String
    let phrases: [OfflinePhrase]
}

struct OfflinePhrase: Codable {
    let english: String
    let local: String
}

// MARK: - Service

@MainActor
final class OfflineKitService {

    static let shared = OfflineKitService()
    private init() {}

    private let encoder = JSONCoding.iso8601Encoder
    private let decoder = JSONCoding.iso8601Decoder

    // MARK: - Read

    /// Returns the cached snapshot for a trip if one exists.
    func snapshot(tripID: UUID) -> OfflineTripSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(for: tripID)) else { return nil }
        return try? decoder.decode(OfflineTripSnapshot.self, from: data)
    }

    func clear(tripID: UUID) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: tripID))
    }

    // MARK: - Build

    /// Builds and persists a fresh snapshot for the given trip. Returns the
    /// new snapshot on success. Called manually from the Refresh button in the
    /// UI, and from `cacheUpcomingTripIfWithinWindow()` when a trip enters its
    /// 48h-before window.
    func cache(trip: Trip, walletItems: [WalletItem], homeCurrency: String) async -> OfflineTripSnapshot {
        let country = TravelEssentialsData.find(query: trip.destination)

        // Weather (only if we can find the destination airport in our lookup)
        var weatherSummary: String?
        if let dest = AirportCoordinates.coordinate(for: extractAirportCode(from: trip)),
           let weather = try? await WeatherService.shared.fetch(
               latitude: dest.latitude, longitude: dest.longitude
           ) {
            weatherSummary = "\(Int(weather.temperatureFahrenheit))°F · \(weather.conditionDescription)"
        }

        // Exchange rates
        var ratesSummary: String?
        var ratesCount = 0
        if let rates = await ExchangeRateService.shared.rates(for: homeCurrency) {
            ratesCount = rates.rates.count
            // Pick a few high-traffic currencies to surface
            let codes = ["EUR", "GBP", "JPY", "CAD", "AUD", "MXN", "CHF", "CNY"]
            let preview = codes.compactMap { code -> String? in
                guard let rate = rates.rates[code] else { return nil }
                return "1\(homeCurrency)=\(String(format: "%.2f", rate))\(code)"
            }.joined(separator: " · ")
            ratesSummary = preview.isEmpty ? "Cached" : preview
        }

        // Country notes
        let countryNotes = country.map { c in
            OfflineCountryNotes(
                countryName: c.name,
                emergencyGeneral: c.emergency.general,
                emergencyPolice: c.emergency.police,
                waterSafe: c.waterSafe,
                plugTypes: c.electrical.plugTypes,
                voltage: c.electrical.voltage,
                tipping: c.tipping.restaurantPercent,
                phrases: c.phrases.map { OfflinePhrase(english: $0.english, local: $0.local) }
            )
        }

        // Itinerary
        let offlineItinerary = trip.items.map {
            OfflineItineraryItem(
                title: $0.title,
                type: $0.type.rawValue,
                startDate: $0.startDate,
                location: $0.location,
                notes: $0.notes
            )
        }

        // Wallet
        let tripWallet = walletItems
            .filter { $0.tripId == trip.id }
            .map {
                OfflineWalletEntry(
                    title: $0.title,
                    type: $0.itemType.rawValue,
                    confirmationNumber: $0.confirmationNumber,
                    date: $0.date
                )
            }

        let payload = OfflinePayload(
            itinerary: offlineItinerary,
            wallet: tripWallet,
            countryNotes: countryNotes,
            weatherSummary: weatherSummary,
            exchangeRateSummary: ratesSummary
        )

        let now = Date()
        // Static content (itinerary, wallet, country notes) stays usable for
        // the whole trip; only weather/FX are perishable, so those get a short
        // TTL. Never let the trip window make the kit expire *before* it ends.
        let perishableTTL: TimeInterval = 24 * 3600
        let snapshot = OfflineTripSnapshot(
            tripID: trip.id,
            destinationName: trip.destination,
            cachedAt: now,
            tripEndDate: max(trip.endDate, now),
            perishableExpiresAt: now.addingTimeInterval(perishableTTL),
            exchangeRatesBase: ratesSummary == nil ? nil : homeCurrency,
            exchangeRatesCount: ratesCount,
            hasDestinationWeather: weatherSummary != nil,
            hasCountryEssentials: countryNotes != nil,
            itineraryItemCount: offlineItinerary.count,
            walletItemCount: tripWallet.count,
            payload: payload
        )

        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey(for: trip.id))
        }
        return snapshot
    }

    // MARK: - Auto-cache

    /// Finds the soonest upcoming trip and, if it departs within ~48h, ensures
    /// an offline kit is cached for it. Safe (and cheap) to call on every app
    /// foreground: it no-ops when there's no imminent trip, and skips work when
    /// a fresh-enough kit with current perishable data already exists.
    ///
    /// Trips and wallet items are read from the same persisted stores the
    /// OfflineKit UI uses so this can run without any injected dependencies.
    func cacheUpcomingTripIfWithinWindow() async {
        guard let trip = soonestUpcomingTrip() else { return }

        let now = Date()
        let secondsUntilDeparture = trip.startDate.timeIntervalSince(now)
        // Only pre-cache once the trip is within the 48h-before window and
        // hasn't already departed.
        guard secondsUntilDeparture <= 48 * 3600 else { return }

        // Idempotent: skip if we already have a usable kit whose perishable
        // data (weather / FX) is still fresh. `cache()` will be re-run by the
        // manual Refresh button or a later foreground once it goes stale.
        if let existing = snapshot(tripID: trip.id), existing.isFresh, !existing.isStale {
            return
        }

        let homeCurrency = UserPreferences.shared.currency.isEmpty
            ? "USD"
            : UserPreferences.shared.currency
        _ = await cache(
            trip: trip,
            walletItems: loadPersistedWalletItems(),
            homeCurrency: homeCurrency
        )
    }

    // MARK: - Helpers

    /// Reads persisted trips and returns the soonest one that hasn't ended yet.
    private func soonestUpcomingTrip() -> Trip? {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_trips"),
              let trips = try? decoder.decode([Trip].self, from: data) else { return nil }
        let now = Date()
        return trips
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    /// Reads persisted wallet items (matches the OfflineKit UI's source).
    private func loadPersistedWalletItems() -> [WalletItem] {
        guard let data = UserDefaults.standard.data(forKey: "jetsetter_wallet_items") else { return [] }
        return (try? decoder.decode([WalletItem].self, from: data)) ?? []
    }

    private func storageKey(for tripID: UUID) -> String {
        "jetsetter_offline_kit_\(tripID.uuidString)"
    }

    /// Pulls the destination IATA from the *chronologically first* (outbound)
    /// flight in the trip's itinerary, e.g. "SFO → NRT" → "NRT".
    ///
    /// `trip.items` is stored in edit order, which is not guaranteed to be
    /// chronological — on a round trip the return leg (…→ home) can appear
    /// first and would otherwise cache weather for the origin city. Sorting by
    /// `startDate` (via `trip.sortedItems`) ensures we take the outbound leg,
    /// whose arrival code is the destination.
    ///
    /// Only leg-only IATA routes are parsed here (no free-text geocoding of
    /// `trip.destination`); a few common separators are tolerated so a route
    /// typed as "SFO-NRT" or "SFO to NRT" still resolves.
    private func extractAirportCode(from trip: Trip) -> String {
        for item in trip.sortedItems where item.type == .flight {
            if let arrival = arrivalCode(from: item.location) {
                return arrival
            }
        }
        return ""
    }

    /// Extracts the arrival airport code from a flight location string of the
    /// form "ORIGIN <sep> DEST", tolerating the separators the app emits (" → ")
    /// and a few a traveler might type by hand. Returns `nil` when no separator
    /// is found so the caller can keep looking for a parseable leg.
    private func arrivalCode(from location: String?) -> String? {
        guard let location, !location.isEmpty else { return nil }
        let separators = [" → ", " — ", " – ", " to ", "->", "→", "–", "—", "-"]
        for separator in separators {
            let parts = location.components(separatedBy: separator)
            if parts.count > 1 {
                let arrival = parts[1].trimmingCharacters(in: .whitespaces)
                if !arrival.isEmpty { return arrival }
            }
        }
        return nil
    }
}
