// File: Features/Booking/FlightBookingModel.swift
//
// State machine for booking a flight through the backend:
//
//   search -> offer detail -> traveler details -> review -> payment -> status
//
// Rules the flow keeps, each from a real way booking apps go wrong:
//
//  * The price the traveler saw is the price they pay. Before the traveler form
//    the offer is re-fetched (`GET /flights/offers/{id}`); checkout then sends
//    the total back as `expected_total_*`. If the fare moved, either step ends
//    in a "price changed" confirmation showing the new total, never a silent
//    charge of a different amount.
//  * A checkout is sent ONCE. If it fails in a way that might still have
//    created the booking (timeout, dropped connection, 502), the flow does not
//    retry: it tells the traveler not to pay again and points at My Bookings,
//    which is where the booking will appear if it was created.
//  * Payment happens on Stripe's hosted page in the in-app browser (Apple Pay
//    and cards there). The server creates the airline order from Stripe's
//    webhook, so a booking completes even if the app is closed; the app polls
//    the booking every 2 seconds for about 2 minutes after the browser closes.
//  * `failed`, `expired` and `cancelled` are shown plainly, with whether money
//    was returned taken from the booking's `refund` object, not assumed.

import Foundation

// MARK: - Steps

nonisolated enum FlightFlowStep: Hashable, Sendable {
    case detail, travelers, review, status, myBookings
}

/// A fare that moved between what the traveler saw and what the server
/// re-priced. Shown in an alert until they accept or back out.
struct FlightPriceChange: Identifiable, Equatable {
    let id = UUID()
    let oldAmount: String
    let oldCurrency: String
    let offer: BackendOffer

    var oldDisplay: String { BackendMoney.display(oldAmount, currency: oldCurrency) }
    var newDisplay: String { BackendMoney.display(offer.totalAmount, currency: offer.totalCurrency) }
}

// MARK: - Model

@MainActor
@Observable
final class FlightBookingModel: Identifiable {

    let id = UUID()
    let request: BackendSearchRequest
    let routeLabel: String

    // MARK: Search

    enum SearchPhase: Equatable {
        case searching
        case loaded
        case failed(String, isConnectivity: Bool)
    }

    private(set) var searchPhase: SearchPhase = .searching
    private(set) var offers: [BackendOffer] = []
    var sort: OfferSort = .price
    private var hasSearched = false

    var sortedOffers: [BackendOffer] { FlightDisplay.sorted(offers, by: sort) }

    // MARK: Navigation

    var path: [FlightFlowStep] = []

    // MARK: Offer and travelers

    private(set) var selectedOffer: BackendOffer?
    var travelers: [TravelerForm] = []
    private(set) var issues: [Int: [TravelerField: String]] = [:]
    private(set) var isRefreshingOffer = false
    /// A message on the offer screen (fare gone, can't reach the server).
    private(set) var offerMessage: String?
    var priceChange: FlightPriceChange?

    // MARK: Checkout

    enum CheckoutPhase: Equatable {
        /// Filling in details (also the state after a recoverable error).
        case editing
        case submitting
        /// The payment page is open or was just closed.
        case awaitingPayment
        case polling
        /// The booking reached a terminal status.
        case settled
        /// Polled for two minutes and it is still pending or processing.
        case stillProcessing
        /// The checkout request failed in a way that may have created a booking.
        case unconfirmed(String)
    }

    private(set) var checkoutPhase: CheckoutPhase = .editing
    private(set) var booking: BackendBooking?
    /// Bound to the in-app browser; non-nil opens it, and it returns to nil
    /// when the traveler closes it.
    var paymentURL: URL?
    private(set) var checkoutURL: URL?
    private(set) var checkoutError: String?

    /// The visible "Test booking" banner: the server is on a Duffel test token,
    /// or this booking says it is a test.
    var isTestMode: Bool { BackendStatus.shared.isTestMode || booking?.testMode == true }

    // MARK: Init

    init(params: FlightSearchParams) {
        self.request = FlightSearchRequestBuilder.make(from: params)
            ?? BackendSearchRequest(slices: [], passengers: BackendSearchPassengers(adults: 1, children: 0, infants: 0),
                                    cabinClass: params.cabinClass.rawValue)
        let first = params.originCode
        let second = params.destinationCode
        self.routeLabel = params.tripType == .roundTrip ? "\(first) ⇄ \(second)" : "\(first) → \(second)"
    }

    // MARK: Search

    /// Runs the search once. Re-appearing after a push/pop doesn't re-run it.
    func searchIfNeeded() async {
        guard !hasSearched else { return }
        hasSearched = true
        await search()
    }

    func search() async {
        guard !request.slices.isEmpty else {
            searchPhase = .failed("Check the airports and dates, then try again.", isConnectivity: false)
            return
        }
        searchPhase = .searching
        do {
            let response = try await BackendClient.shared.searchFlights(request)
            offers = response.offers
            searchPhase = .loaded
        } catch let error as BackendError {
            searchPhase = .failed(error.userMessage, isConnectivity: error.isConnectivity)
        } catch {
            // Cancelled: the sheet closed.
            hasSearched = false
        }
    }

    // MARK: Offer

    func select(_ offer: BackendOffer) {
        selectedOffer = offer
        travelers = TravelerForm.reconcile(existing: [], with: offer)
        issues = [:]
        offerMessage = nil
        priceChange = nil
        path = [.detail]
    }

    /// Re-prices the selected offer, then opens the traveler form (or asks the
    /// traveler to accept a new price first).
    func continueToTravelers() async {
        guard let offer = selectedOffer, !isRefreshingOffer else { return }
        isRefreshingOffer = true
        offerMessage = nil
        defer { isRefreshingOffer = false }
        do {
            let fresh = try await BackendClient.shared.offer(id: offer.id)
            adopt(fresh, replacing: offer)
            if priceChange == nil { path.append(.travelers) }
        } catch let error as BackendError {
            switch error {
            case .offerExpired, .notFound:
                offerMessage = "This fare is no longer available. Go back and search again for current prices."
            default:
                offerMessage = error.userMessage
            }
        } catch {
            // Cancelled.
        }
    }

    /// Takes a freshly priced offer as the selected one, flagging a price move.
    private func adopt(_ fresh: BackendOffer, replacing old: BackendOffer) {
        if !BackendMoney.isSameAmount(fresh.totalAmount, old.totalAmount) || fresh.totalCurrency != old.totalCurrency {
            priceChange = FlightPriceChange(oldAmount: old.totalAmount, oldCurrency: old.totalCurrency, offer: fresh)
        }
        selectedOffer = fresh
        travelers = TravelerForm.reconcile(existing: travelers, with: fresh)
        if let index = offers.firstIndex(where: { $0.id == fresh.id }) { offers[index] = fresh }
    }

    /// The traveler accepts the new total. From the offer screen that opens the
    /// form; from review they simply tap pay again at the new price.
    func acceptPriceChange() {
        priceChange = nil
        if path == [.detail] { path.append(.travelers) }
    }

    func declinePriceChange() {
        priceChange = nil
    }

    // MARK: Travelers

    /// Validates the form and moves to review, or records what to fix.
    func continueToReview() {
        guard let offer = selectedOffer else { return }
        let result = TravelerValidation.validateAll(travelers, offer: offer, travelEnd: Self.travelEnd(of: offer))
        issues = result.issues
        checkoutError = nil
        if result.isValid { path.append(.review) }
    }

    /// Drops a traveler's stale complaints once they edit that traveler; the
    /// next validation pass re-checks everything.
    func clearIssues(at index: Int) {
        issues[index] = nil
    }

    /// When the last flight lands, for passport-validity checks.
    static func travelEnd(of offer: BackendOffer) -> Date? {
        guard let segment = offer.slices.last?.segments.last,
              let zone = BackendDates.zone(for: segment.destination) ?? TimeZone(secondsFromGMT: 0)
        else { return nil }
        return BackendDates.instant(segment.arrivingAt, in: zone)
    }

    // MARK: Checkout

    /// Sends the checkout once. See the file header for the failure rules.
    func submit() async {
        guard let offer = selectedOffer, checkoutPhase == .editing else { return }
        let result = TravelerValidation.validateAll(travelers, offer: offer, travelEnd: Self.travelEnd(of: offer))
        guard result.isValid, let passengers = result.inputs else {
            issues = result.issues
            checkoutError = "Some traveler details need fixing."
            // Back to the form, where the problems are marked.
            path = [.detail, .travelers]
            return
        }

        checkoutError = nil
        checkoutPhase = .submitting
        let body = BackendCheckoutRequest(
            expectedTotalAmount: offer.totalAmount,
            expectedTotalCurrency: offer.totalCurrency,
            passengers: passengers
        )
        do {
            let response = try await BackendClient.shared.checkout(offerID: offer.id, request: body)
            await receive(response)
        } catch let error as BackendError {
            handleCheckoutError(error, offer: offer)
        } catch {
            checkoutPhase = .editing
        }
    }

    private func receive(_ response: BackendCheckoutResponse) async {
        booking = response.booking
        await BookingSync.shared.record(response.booking)
        path.append(.status)

        if !response.booking.status.isTerminal, let url = response.checkoutLink {
            checkoutURL = url
            checkoutPhase = .awaitingPayment
            // Let the push finish before the browser sheet rises.
            try? await Task.sleep(for: .milliseconds(600))
            if checkoutPhase == .awaitingPayment { paymentURL = url }
        } else if response.booking.status.isTerminal {
            // Test mode: confirmed immediately, no payment step.
            checkoutPhase = .settled
        } else {
            // Pending with no payment link: nothing to open, just wait on it.
            checkoutPhase = .polling
        }
    }

    private func handleCheckoutError(_ error: BackendError, offer: BackendOffer) {
        checkoutPhase = .editing
        switch error {
        case .priceChanged(_, let fresh):
            if let fresh {
                priceChange = FlightPriceChange(oldAmount: offer.totalAmount, oldCurrency: offer.totalCurrency, offer: fresh)
                selectedOffer = fresh
                travelers = TravelerForm.reconcile(existing: travelers, with: fresh)
            } else {
                checkoutError = error.userMessage
            }
        case .offerExpired, .notFound:
            checkoutError = "This fare is no longer available. Close this screen and search again for current prices."
        case .validation:
            checkoutError = error.userMessage
        default:
            if error.mayHaveCreatedBooking {
                checkoutPhase = .unconfirmed(error.userMessage)
                // The booking may exist: look for it shortly, don't retry.
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await BookingSync.shared.sync(force: true)
                }
            } else {
                checkoutError = error.userMessage
            }
        }
    }

    // MARK: Payment and status

    /// The in-app browser closed. If payment was in progress, start waiting on
    /// the server; Stripe's webhook completes the booking either way.
    func paymentBrowserClosed() {
        guard checkoutPhase == .awaitingPayment else { return }
        checkoutPhase = .polling
    }

    /// Reopens the payment page for a booking still waiting on payment.
    func reopenPayment() {
        guard let url = checkoutURL, booking?.status == .pendingPayment else { return }
        checkoutPhase = .awaitingPayment
        paymentURL = url
    }

    func checkAgain() {
        guard booking != nil else { return }
        checkoutPhase = .polling
    }

    /// Polls `GET /bookings/{id}` every 2 seconds, up to about 2 minutes, until
    /// the booking is terminal. Run from the status screen's `.task`, so it is
    /// cancelled when the screen goes away.
    func pollUntilSettled() async {
        guard checkoutPhase == .polling, let id = booking?.id else { return }
        var consecutiveFailures = 0
        for _ in 0..<60 {
            if Task.isCancelled { return }
            do {
                let latest = try await BackendClient.shared.booking(id: id)
                consecutiveFailures = 0
                booking = latest
                if latest.status.isTerminal {
                    await BookingSync.shared.record(latest)
                    checkoutPhase = .settled
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 5 { break }
            }
            try? await Task.sleep(for: .seconds(2))
        }
        if !Task.isCancelled { checkoutPhase = .stillProcessing }
    }
}
