// File: Features/LocalExperience/LocalExperienceViewModel.swift
// ViewModel for the Local Experience Engine (Feature 5).
// Apple Maps points of interest around the trip destination, ranked on device
// by Apple Intelligence for this traveler. No third-party API, no key.

import SwiftUI
import CoreLocation

@MainActor
@Observable
final class LocalExperienceViewModel {

    private(set) var experiences: [Experience] = []
    private(set) var isLoading = false
    private(set) var destinationCity: String = ""
    /// "you" when the traveler is at the destination, otherwise "city centre".
    private(set) var distanceOrigin: String = "city centre"
    private(set) var isRankedOnDevice = false
    var errorMessage: String? = nil

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
        guard experiences.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Best-effort current location; a denied permission just means distances
        // are measured from the city centre instead of from the traveler.
        let userLocation = try? await LocationService.shared.requestCurrentLocation()
        do {
            let result = try await LocalExperienceService.shared.experiences(near: destinationCity, userLocation: userLocation)
            experiences = result.items
            distanceOrigin = result.centerLabel
            isRankedOnDevice = result.items.contains { $0.aiReason != nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        experiences = []
        await load()
    }

    /// In-app web target for a venue link (§7.7 — presented via `.inAppWeb`).
    var externalWebURL: URL?

    func openBookingURL(for experience: Experience) {
        guard let urlString = experience.bookingUrl,
              let url = URL(string: urlString) else { return }
        externalWebURL = url
    }
}
