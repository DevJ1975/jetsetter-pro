// File: Core/Services/LocalExperienceService.swift
//
// Things to do around a destination, with no third-party API:
//   1. MapKit local search (Apple's own points-of-interest data) for
//      restaurants, cafés, sights, nightlife and shopping near the destination.
//   2. Apple Intelligence (FoundationModels) ranks the candidates for THIS
//      traveler — learned profile, time of day, weather — and writes a one-line
//      reason per pick. Runs on device; nothing about the user leaves the phone.
//
// When the on-device model is unavailable the list is simply ordered by
// distance without reasons, so the screen always works.

import Foundation
import CoreLocation
import MapKit
import FoundationModels

@MainActor
final class LocalExperienceService {

    static let shared = LocalExperienceService()
    private init() {}

    enum Failure: LocalizedError {
        case destinationNotFound(String)
        case nothingNearby

        var errorDescription: String? {
            switch self {
            case .destinationNotFound(let name):
                return "Couldn't place \"\(name)\" on the map. Try a city name or airport code."
            case .nothingNearby:
                return "Apple Maps has no listings near there yet."
            }
        }
    }

    /// Radius around the center to search. City centres are dense, so this is
    /// tight on purpose; MapKit returns its best ~25 results per query.
    private let radiusMeters: CLLocationDistance = 4_000

    // MARK: - Public

    /// Resolves the destination, gathers candidates from MapKit, then ranks them
    /// on device. `userLocation` (if within 50 km of the destination) becomes the
    /// distance origin so "0.4 km away" is from the traveler, not the city centre.
    func experiences(near destination: String, userLocation: CLLocation?) async throws -> (items: [Experience], centerLabel: String) {
        let center = try await resolve(destination)
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        var origin = centerLocation
        var centerLabel = "city centre"
        if let userLocation, userLocation.distance(from: centerLocation) < 50_000 {
            origin = userLocation
            centerLabel = "you"
        }

        var candidates: [Experience] = []
        for query in Self.queries {
            let found = await search(query: query, center: center, origin: origin)
            candidates.append(contentsOf: found)
        }
        // De-duplicate by name (the same café can match "coffee" and "restaurants").
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.name.lowercased()).inserted }
        guard !candidates.isEmpty else { throw Failure.nothingNearby }

        let ranked = await rank(candidates, destination: destination, center: center)
        return (ranked, centerLabel)
    }

    // MARK: - MapKit

    private struct POIQuery {
        let text: String
        let categories: [MKPointOfInterestCategory]
        let experienceCategory: ExperienceCategory
        let slot: ExperienceTimeSlot
    }

    private static let queries: [POIQuery] = [
        POIQuery(text: "restaurants",   categories: [.restaurant, .bakery],                                   experienceCategory: .restaurant, slot: .rightNow),
        POIQuery(text: "coffee",        categories: [.cafe],                                                  experienceCategory: .cafe,       slot: .rightNow),
        POIQuery(text: "things to do",  categories: [.museum, .park, .theater, .amusementPark, .aquarium, .zoo, .beach, .nationalPark], experienceCategory: .attraction, slot: .thisTrip),
        POIQuery(text: "bars",          categories: [.nightlife, .brewery, .winery],                          experienceCategory: .bar,        slot: .tonight),
        POIQuery(text: "shopping",      categories: [.store],                                                 experienceCategory: .shopping,   slot: .thisTrip)
    ]

    private func search(query: POIQuery, center: CLLocationCoordinate2D, origin: CLLocation) async -> [Experience] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.text
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: query.categories)

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(12).compactMap { item -> Experience? in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            return Experience(
                id: UUID(),
                name: name,
                category: query.experienceCategory,
                address: item.placemark.title ?? "",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                rating: 0,
                reviewCount: 0,
                priceLevel: .moderate,
                distanceMeters: distance,
                openNow: nil,
                photoUrl: nil,
                bookingUrl: (item.url ?? Self.mapsURL(for: name, coordinate: coordinate))?.absoluteString,
                eventDate: nil,
                aiReason: nil,
                source: .appleMaps,
                slotOverride: query.slot
            )
        }
    }

    private static func mapsURL(for name: String, coordinate: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q",  value: name),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")
        ]
        return components?.url
    }

    private func resolve(_ destination: String) async throws -> CLLocationCoordinate2D {
        let upper = destination.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.count == 3, upper.allSatisfy(\.isLetter), let coordinate = AirportCoordinates.coordinate(for: upper) {
            return coordinate
        }
        if let placemarks = try? await CLGeocoder().geocodeAddressString(destination),
           let coordinate = placemarks.first?.location?.coordinate {
            return coordinate
        }
        throw Failure.destinationNotFound(destination)
    }

    // MARK: - On-device ranking

    /// Orders candidates for this traveler and attaches a one-line reason to the
    /// top picks. Distance order (no reasons) when Apple Intelligence is off.
    private func rank(_ candidates: [Experience], destination: String, center: CLLocationCoordinate2D) async -> [Experience] {
        let byDistance = candidates.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        guard #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability else {
            return byDistance
        }

        // Keep the prompt small: the ~20 nearest candidates, one line each.
        let shortlist = Array(byDistance.prefix(20))
        let profile = TravelProfileStore.shared.profile.summaryForPrompt()
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 11 ? "morning" : hour < 17 ? "afternoon" : hour < 21 ? "evening" : "late night"
        var weatherLine = ""
        if let weather = try? await WeatherService.shared.fetch(latitude: center.latitude, longitude: center.longitude) {
            weatherLine = "Weather now: \(weather.summaryForPrompt)."
        }

        let candidateLines = shortlist.map { "- \($0.name) (\($0.category.rawValue.lowercased()))" }.joined(separator: "\n")
        let prompt = """
        Destination: \(destination). Time of day: \(timeOfDay). \(weatherLine)
        \(profile.isEmpty ? "" : "Traveler profile: \(profile)")

        Candidates nearby:
        \(candidateLines)

        Pick the best 8 for this traveler right now. Use only names from the list, spelled exactly. \
        Prefer indoor places when it is raining. One short reason each, in the second person.
        """

        do {
            let session = LanguageModelSession(instructions: """
            You are a local concierge choosing places for one traveler. Be specific and brief. \
            Never invent a place that is not in the candidate list.
            """)
            let response = try await session.respond(
                to: prompt,
                generating: RankedPlaces.self,
                options: GenerationOptions(sampling: .greedy)
            )
            var reasons: [String: String] = [:]
            var order: [String] = []
            for pick in response.content.picks {
                let key = pick.name.lowercased()
                guard reasons[key] == nil else { continue }
                reasons[key] = pick.whyItFits
                order.append(key)
            }
            let picked = order.compactMap { key -> Experience? in
                guard let match = byDistance.first(where: { $0.name.lowercased() == key }) else { return nil }
                return match.withReason(reasons[key])
            }
            let pickedIDs = Set(picked.map(\.id))
            return picked + byDistance.filter { !pickedIDs.contains($0.id) }
        } catch {
            return byDistance
        }
    }
}

// MARK: - Generable schema

@available(iOS 26.0, *)
@Generable
nonisolated struct RankedPlaces {
    @Guide(description: "Best picks for this traveler, best first")
    @Guide(.maximumCount(8))
    var picks: [RankedPick]
}

@available(iOS 26.0, *)
@Generable
nonisolated struct RankedPick {
    @Guide(description: "Exact name from the candidate list")
    var name: String
    @Guide(description: "One short sentence on why it suits this traveler, in the second person")
    var whyItFits: String
}
