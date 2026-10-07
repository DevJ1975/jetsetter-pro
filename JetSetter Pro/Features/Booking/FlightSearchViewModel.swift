// File: Features/Booking/FlightSearchViewModel.swift

import Foundation

// MARK: - FlightSearchViewModel

/// Two ways to book, chosen by what the backend offers:
///
///  * Backend flights enabled (`BackendStatus.flightsEnabled`): Search opens the
///    in-app booking flow (`FlightBookingFlowView`), with "Compare on Kayak"
///    kept as the vendor route.
///  * Otherwise, exactly as before: build a pre-filled flight-search URL from
///    the inputs and hand off to the provider's site in-app (§7.7, presented via
///    `.inAppWeb`). No flight data is fetched or stored; the site completes the
///    booking.
@MainActor
@Observable
final class FlightSearchViewModel {

    // MARK: - Published State

    var searchParams = FlightSearchParams()
    var errorMessage: String? = nil

    /// In-app web target for the provider's pre-filled search page. Setting this
    /// non-nil drives the `.inAppWeb` sheet in `FlightSearchView`.
    var externalWebURL: URL? = nil

    /// Non-nil presents the in-app booking flow sheet.
    var flightFlow: FlightBookingModel? = nil

    /// The flight site to hand off to. Only Kayak today.
    private let provider: FlightBookingProvider = .kayak

    // MARK: - Search

    /// True when Search should run the in-app booking flow.
    var usesInAppBooking: Bool { BackendStatus.shared.flightsEnabled }

    /// The pre-filled Kayak search for the current inputs, or nil if the route
    /// isn't usable yet.
    var kayakURL: URL? { provider.deepLinkURL(for: searchParams) }

    /// Search: the in-app flow when the backend has flights, else the Kayak
    /// hand-off.
    func searchFlights() {
        guard validateRoute() else { return }
        if usesInAppBooking {
            flightFlow = FlightBookingModel(params: searchParams)
            return
        }
        openKayak()
    }

    /// The secondary route while in-app booking is on.
    func compareOnKayak() {
        guard validateRoute() else { return }
        openKayak()
    }

    /// Validates the inputs, builds the Kayak deep link, and opens it in-app.
    private func openKayak() {
        guard let url = provider.deepLinkURL(for: searchParams) else {
            errorMessage = "Could not build the search link. Please try again."
            return
        }
        externalWebURL = url
    }

    /// Shared origin/destination/date validation. Sets `errorMessage` and returns
    /// false on any problem.
    private func validateRoute() -> Bool {
        errorMessage = nil
        let origin = searchParams.originCode
        let destination = searchParams.destinationCode

        // The in-app search can book any airport the airlines serve (the server
        // supplies each airport's time zone); the Kayak link needs one the app
        // knows, as before.
        func isUsable(_ code: String) -> Bool {
            usesInAppBooking ? (code.count == 3 && code.allSatisfy(\.isLetter)) : AirportCoordinates.isKnown(code)
        }
        guard isUsable(origin), isUsable(destination) else {
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
