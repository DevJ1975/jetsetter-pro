// File: Core/Services/DisruptionResponseEngine.swift
// Executes the automated disruption response once a disruption is detected:
//  1. Builds a pre-filled alternative-flight search (same route, same day) the
//     traveler can open in-app — no airline inventory API is involved, so no
//     invented seats or fares.
//  2. Generates the hotel late-arrival contact from the trip's wallet.
//  3. Builds an Uber deep link to the updated terminal/gate.
//  4. Surfaces the user's travel insurance WalletItem from the local wallet.
//
// Rebooking eligibility (whether the ORIGINAL fare can be changed) needs the
// carrier or a booking provider to answer; with no backend it stays unknown
// (`nil`) and the UI says so rather than guessing.

import Foundation

// MARK: - DisruptionResponseEngine

/// Actor that concurrently executes the response steps.
/// Called by DisruptionMonitorService once a disruption is detected.
actor DisruptionResponseEngine {

    static let shared = DisruptionResponseEngine()
    private init() {}

    // MARK: - Main Orchestrator

    /// Runs all response steps and returns the fully-populated DisruptionEvent.
    func handleDisruption(event: DisruptionEvent, trip: Trip) async -> DisruptionEvent {
        var updated = event

        async let hotelEmail  = fetchHotelContactEmail(tripId: trip.id)
        async let insuranceId = fetchInsuranceDocumentId(tripId: trip.id)

        // Step 1 — Alternatives: a pre-filled same-route search the traveler opens.
        updated.alternatives = []
        updated.rebookingUrl = alternativeSearchURL(
            origin: event.originalFlight.origin,
            destination: event.originalFlight.destination,
            date: event.originalFlight.scheduledDeparture
        )?.absoluteString
        updated.responseActions.alternativesFound = updated.rebookingUrl != nil

        // Step 2 — Rebooking eligibility is unknown without carrier data.
        updated.responseActions.rebookingChecked = true
        updated.responseActions.rebookingEligible = nil

        // Step 3 — Hotel notification (mail composed on user tap; mark ready here)
        if let email = await hotelEmail {
            updated.hotelContact = email
            updated.responseActions.hotelNotified = true
        }

        // Step 4 — Uber reroute deep link
        let gate = event.originalFlight.originalGate ?? "Terminal"
        updated.uberDeepLink = buildUberDeepLink(
            destinationDescription: "\(event.originalFlight.destination) Airport \(gate)"
        )
        updated.responseActions.uberRerouteReady = true

        // Step 5 — Surface insurance document
        let docId = await insuranceId
        updated.insuranceDocumentId = docId
        updated.responseActions.insuranceSurfaced = docId != nil

        return updated
    }

    // MARK: - Step 1: Alternative flights (pre-filled search)

    /// Same-route, same-day flight search on the app's flight hand-off site.
    /// The date is formatted in the device's calendar so a departure just before
    /// local midnight isn't pushed onto the wrong day.
    func alternativeSearchURL(origin: String, destination: String, date: Date) -> URL? {
        var params = FlightSearchParams()
        params.origin = origin
        params.destination = destination
        params.departDate = date
        params.tripType = .oneWay
        params.adults = 1
        return FlightBookingProvider.kayak.deepLinkURL(for: params)
    }

    /// Kept for callers that ask directly (tools, dashboard): the app holds no
    /// carrier inventory, so this is always empty. Use `alternativeSearchURL`.
    func searchAlternativeFlights(origin: String, destination: String, date: Date) async -> [AlternativeFlight] {
        []
    }

    // MARK: - Step 2: Rebooking eligibility

    /// Whether the ORIGINAL fare can be changed. Unknown (`nil`) without a
    /// carrier or booking-provider integration.
    func checkRebookingEligibility(tripId: UUID) async -> Bool? {
        nil
    }

    // MARK: - Step 3: Hotel notification

    /// Fetches the contact email for the hotel reservation linked to this trip.
    /// Stored in WalletItem.rawData["contact_email"] for hotelReservation items.
    private func fetchHotelContactEmail(tripId: UUID) async -> String? {
        let items = await LocalDataService.shared.fetchWalletItems()
        let match = items.first { $0.itemType == .hotelReservation && $0.tripId == tripId }
        return match?.rawData["contact_email"]
    }

    // MARK: - Step 4: Uber reroute

    /// Generates an Uber deep link pre-filled with the airport terminal/gate as destination.
    func buildUberDeepLink(destinationDescription: String) -> String {
        let encoded = destinationDescription
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "uber://?action=setPickup&pickup=my_location" +
               "&dropoff[nickname]=\(encoded)" +
               "&dropoff[formatted_address]=\(encoded)"
    }

    // MARK: - Step 5: Travel insurance

    /// Finds the travel insurance WalletItem ID for this trip in the local wallet.
    private func fetchInsuranceDocumentId(tripId: UUID) async -> UUID? {
        let items = await LocalDataService.shared.fetchWalletItems()
        return items.first { $0.itemType == .travelInsurance && $0.tripId == tripId }?.id
    }
}
