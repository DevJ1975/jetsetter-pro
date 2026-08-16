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

    /// Validates the inputs, builds the deep link, and opens it in-app.
    func searchFlights() {
        errorMessage = nil

        let origin = searchParams.originCode
        let destination = searchParams.destinationCode

        // Both must be airport codes we recognize, so we never hand off a URL
        // for a route the site can't resolve.
        guard AirportCoordinates.isKnown(origin), AirportCoordinates.isKnown(destination) else {
            errorMessage = "Enter valid 3-letter airport codes, e.g. JFK → LAX."
            return
        }

        guard origin != destination else {
            errorMessage = "Origin and destination must be different."
            return
        }

        // Round trips can't return before they depart.
        if searchParams.tripType == .roundTrip {
            let calendar = Calendar.current
            let depart = calendar.startOfDay(for: searchParams.departDate)
            let returnDay = calendar.startOfDay(for: searchParams.returnDate)
            guard returnDay >= depart else {
                errorMessage = "Return date must be on or after the departure date."
                return
            }
        }

        guard let url = provider.deepLinkURL(for: searchParams) else {
            errorMessage = "Could not build the search link. Please try again."
            return
        }

        externalWebURL = url
    }
}
