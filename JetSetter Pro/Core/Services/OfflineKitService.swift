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
    let expiresAt: Date
    let exchangeRatesBase: String?
    let exchangeRatesCount: Int
    let hasDestinationWeather: Bool
    let hasCountryEssentials: Bool
    let itineraryItemCount: Int
    let walletItemCount: Int
    let payload: OfflinePayload

    /// True when the cache is still considered fresh.
    var isFresh: Bool { expiresAt > Date() }
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

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

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
    /// new snapshot on success. Designed to be called manually from the UI
    /// (or automatically when a trip enters its 48h-before window).
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
        let snapshot = OfflineTripSnapshot(
            tripID: trip.id,
            destinationName: trip.destination,
            cachedAt: now,
            // Cache stays fresh for 24h.
            expiresAt: now.addingTimeInterval(24 * 3600),
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

    // MARK: - Helpers

    private func storageKey(for tripID: UUID) -> String {
        "jetsetter_offline_kit_\(tripID.uuidString)"
    }

    /// Pulls the destination IATA from the first flight item in the trip's
    /// itinerary, e.g. "SFO → NRT" → "NRT".
    private func extractAirportCode(from trip: Trip) -> String {
        for item in trip.items where item.type == .flight {
            let parts = (item.location ?? "").components(separatedBy: " → ")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
