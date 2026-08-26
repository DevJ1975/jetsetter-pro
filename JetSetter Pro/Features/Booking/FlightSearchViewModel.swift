// File: Features/Booking/FlightSearchViewModel.swift

import Foundation

// MARK: - FlightSearchViewModel

/// Builds a pre-filled flight-search URL from the user's inputs and hands off to
/// the provider's site in-app (§7.7 — presented via `.inAppWeb`). No flight data
/// is fetched or stored; the site completes the booking.
@MainActor
@Observable
final class FlightSearchViewModel {

    // MARK: - Published State

    var searchParams = FlightSearchParams()
    var errorMessage: String? = nil

    /// In-app web target for the provider's pre-filled search page. Setting this
    /// non-nil drives the `.inAppWeb` sheet in `FlightSearchView`.
    var externalWebURL: URL? = nil

    /// The flight site to hand off to. Only Kayak today.
    private let provider: FlightBookingProvider = .kayak

    // MARK: - Search

    /// True when the real Duffel booking flow is available (proxy configured).
    /// The view shows "Book with Apple Pay" instead of the Kayak hand-off.
    var canBookRealFlights: Bool { DuffelBookingService.isConfigured }

    /// Validates the inputs, builds the Kayak deep link, and opens it in-app.
    func searchFlights() {
        guard validateRoute() else { return }
        guard let url = provider.deepLinkURL(for: searchParams) else {
            errorMessage = "Could not build the search link. Please try again."
            return
        }
        externalWebURL = url
    }

    /// Validated Duffel search params for the real booking flow, or nil (setting
    /// `errorMessage`) when the inputs are invalid. Same checks as the Kayak path.
    func duffelSearchParams() -> DuffelSearchParams? {
        guard validateRoute() else { return nil }
        return DuffelSearchParams(
            origin: searchParams.originCode,
            destination: searchParams.destinationCode,
            departDate: searchParams.departDate,
            returnDate: searchParams.tripType == .roundTrip ? searchParams.returnDate : nil,
            adults: searchParams.adults
        )
    }

    /// Shared origin/destination/date validation. Sets `errorMessage` and returns
    /// false on any problem.
    private func validateRoute() -> Bool {
        errorMessage = nil
        let origin = searchParams.originCode
        let destination = searchParams.destinationCode

        guard AirportCoordinates.isKnown(origin), AirportCoordinates.isKnown(destination) else {
            errorMessage = "Enter valid 3-letter airport codes, e.g. JFK → LAX."
            return false
        }
        guard origin != destination else {
            errorMessage = "Origin and destination must be different."
            return false
        }
        if searchParams.tripType == .roundTrip {
            let calendar = Calendar.current
            let depart = calendar.startOfDay(for: searchParams.departDate)
            let returnDay = calendar.startOfDay(for: searchParams.returnDate)
            guard returnDay >= depart else {
                errorMessage = "Return date must be on or after the departure date."
                return false
            }
        }
        return true
    }
}
