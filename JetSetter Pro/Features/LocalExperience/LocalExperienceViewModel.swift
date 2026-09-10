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

    /// In-app web target for a booking link (§7.7 — presented via `.inAppWeb`).
    var externalWebURL: URL?

    func openBookingURL(for experience: Experience) {
        guard let urlString = experience.bookingUrl,
              let url = URL(string: urlString) else { return }
        externalWebURL = url
    }
}
