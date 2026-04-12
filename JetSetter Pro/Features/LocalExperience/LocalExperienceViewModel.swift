// File: Features/LocalExperience/LocalExperienceViewModel.swift
// ViewModel for the Local Experience Engine (Feature 5).
// TODO: Full implementation in Feature 5 sprint.
// Key responsibilities: Core Location destination match (50km radius),
// Google Places API fetch, Eventbrite API, Claude ranking, 30-min background refresh.

import SwiftUI
import Combine
import CoreLocation

@MainActor
final class LocalExperienceViewModel: ObservableObject {

    @Published private(set) var experiences: [Experience] = []
    @Published private(set) var isAtDestination = false
    @Published private(set) var isLoading = false
    @Published private(set) var destinationCity: String = ""
    @Published var errorMessage: String? = nil

    private let locationManager = CLLocationManager()

    init(trip: Trip) {
        self.destinationCity = trip.destination
    }

    var rightNow: [Experience]  { experiences.filter { $0.timeSlot == .rightNow } }
    var tonight: [Experience]   { experiences.filter { $0.timeSlot == .tonight } }
    var thisTrip: [Experience]  { experiences.filter { $0.timeSlot == .thisTrip } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // TODO: Check user location vs trip destination (50km radius)
        // TODO: Fetch Google Places (rating > 4.2) + Eventbrite events
        // TODO: Call Claude API to rank + add aiReason
        // TODO: Filter outdoor activities if raining (WeatherKit)
    }

    func openBookingURL(for experience: Experience) {
        guard let urlString = experience.bookingUrl,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
