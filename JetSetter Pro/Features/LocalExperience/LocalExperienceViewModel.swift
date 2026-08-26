// File: Features/LocalExperience/LocalExperienceViewModel.swift
// ViewModel for the Local Experience Engine (Feature 5).
// TODO: Full implementation in Feature 5 sprint.
// Key responsibilities: Core Location destination match (50km radius),
// Google Places API fetch, Eventbrite API, Claude ranking, 30-min background refresh.

import SwiftUI
import CoreLocation

@MainActor
@Observable
final class LocalExperienceViewModel {

    private(set) var experiences: [Experience] = []
    private(set) var isAtDestination = false
    private(set) var isLoading = false
    private(set) var destinationCity: String = ""
    /// True when the (not-yet-implemented) live engine has nothing to show, so the
    /// UI renders a friendly "Coming soon" state instead of a blank/misleading screen.
    private(set) var isComingSoon = false
    var errorMessage: String? = nil

    private let locationManager = CLLocationManager()

    init(trip: Trip) {
        self.destinationCity = trip.destination
    }

    // A venue we know to be closed shouldn't be surfaced under "Right Now" — it
    // falls back to "This Trip" so users aren't nudged to tap something they
    // can't act on immediately.
    var rightNow: [Experience]  { experiences.filter { $0.timeSlot == .rightNow && !$0.isClosedNow } }
    var tonight: [Experience]   { experiences.filter { $0.timeSlot == .tonight } }
    var thisTrip: [Experience]  {
        experiences.filter { $0.timeSlot == .thisTrip || ($0.timeSlot == .rightNow && $0.isClosedNow) }
    }

    func load() async {
        // The live engine is not yet implemented (see TODOs below). Until it ships,
        // present a "Coming soon" state rather than a blank or misleading screen.
        isLoading = false
        isComingSoon = true
        // TODO: Check user location vs trip destination (50km radius)
        // TODO: Fetch Google Places (rating > 4.2) + Eventbrite events
        // TODO: Call Claude API to rank + add aiReason
        // TODO: Filter outdoor activities if raining (WeatherKit)
    }

    // MARK: - Demo Seed

    private static func tokyoDemoExperiences() -> [Experience] {
        let now = Date()
        func hoursFromNow(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

        return [
            // RIGHT NOW — nil eventDate routes to .rightNow
            Experience(
                id: UUID(),
                name: "Tsukiji Outer Market Tour",
                category: .attraction,
                address: "4 Chome-16-2 Tsukiji, Chuo City, Tokyo",
                latitude: 35.6654,
                longitude: 139.7707,
                rating: 4.9,
                reviewCount: 3120,
                priceLevel: .budget,
                distanceMeters: 850,
                openNow: true,
                photoUrl: nil,
                bookingUrl: "https://www.viator.com/tours/Tokyo/Tsukiji-Outer-Market-Food-Tour",
                eventDate: nil,
                aiReason: "Morning street-food tour — uni rice bowls and grilled scallops.",
                source: .aiCurated
            ),

            // TONIGHT — 3..<12 hours from now
            Experience(
                id: UUID(),
                name: "teamLab Planets TOKYO",
                category: .attraction,
                address: "6-1-16 Toyosu, Koto City, Tokyo",
                latitude: 35.6478,
                longitude: 139.7905,
                rating: 4.7,
                reviewCount: 18450,
                priceLevel: .moderate,
                distanceMeters: 4200,
                openNow: true,
                photoUrl: nil,
                bookingUrl: "https://teamlab.art/e/planets/",
                eventDate: hoursFromNow(4),
                aiReason: "Perfect 90 mins between your hotel check-in and dinner.",
                source: .aiCurated
            ),
            Experience(
                id: UUID(),
                name: "Shibuya Sky",
                category: .attraction,
                address: "2-24-12 Shibuya, Shibuya City, Tokyo",
                latitude: 35.6587,
                longitude: 139.7016,
                rating: 4.6,
                reviewCount: 22100,
                priceLevel: .budget,
                distanceMeters: 2300,
                openNow: true,
                photoUrl: nil,
                bookingUrl: "https://www.shibuya-sky.com/",
                eventDate: hoursFromNow(6),
                aiReason: "Sunset slot 6:30 PM — book the rooftop deck for the Mt. Fuji view.",
                source: .aiCurated
            ),
            Experience(
                id: UUID(),
                name: "Park Hyatt New York Bar",
                category: .bar,
                address: "3-7-1-2 Nishi Shinjuku, Shinjuku City, Tokyo",
                latitude: 35.6855,
                longitude: 139.6911,
                rating: 4.7,
                reviewCount: 4280,
                priceLevel: .upscale,
                distanceMeters: 3100,
                openNow: true,
                photoUrl: nil,
                bookingUrl: "https://www.hyatt.com/park-hyatt/tyoph-park-hyatt-tokyo/dining",
                eventDate: hoursFromNow(8),
                aiReason: "Same as the Lost in Translation bar. Live jazz starts 8 PM.",
                source: .aiCurated
            ),

            // THIS TRIP — >=12 hours from now
            Experience(
                id: UUID(),
                name: "Sukiyabashi Jiro Honten",
                category: .restaurant,
                address: "Tsukamoto Sogyo Building B1F, 4-2-15 Ginza, Chuo City, Tokyo",
                latitude: 35.6717,
                longitude: 139.7639,
                rating: 4.8,
                reviewCount: 1840,
                priceLevel: .luxury,
                distanceMeters: 1500,
                openNow: false,
                photoUrl: nil,
                bookingUrl: "https://www.opentable.com/sukiyabashi-jiro",
                eventDate: hoursFromNow(48),
                aiReason: "Considered the best omakase in Tokyo. Book 1 month ahead — IRIS already added the reminder.",
                source: .aiCurated
            ),
            Experience(
                id: UUID(),
                name: "Golden Gai",
                category: .bar,
                address: "1 Chome Kabukicho, Shinjuku City, Tokyo",
                latitude: 35.6943,
                longitude: 139.7048,
                rating: 4.5,
                reviewCount: 9620,
                priceLevel: .moderate,
                distanceMeters: 3400,
                openNow: true,
                photoUrl: nil,
                bookingUrl: nil,
                eventDate: hoursFromNow(26),
                aiReason: "200 tiny bars in 6 alleys — start at Bar Araku.",
                source: .aiCurated
            )
        ]
    }

    /// In-app web target for a booking link (§7.7 — presented via `.inAppWeb`).
    var externalWebURL: URL?

    func openBookingURL(for experience: Experience) {
        guard let urlString = experience.bookingUrl,
              let url = URL(string: urlString) else { return }
        externalWebURL = url
    }
}
