// File: JetSetter ProTests/BackendContractTests.swift
//
// The wire contract with the booking backend (docs/BACKEND_API.md): every
// object decodes from the documented JSON, every error body maps to the right
// case, request bodies are encoded with the documented snake_case keys, and
// the client's URL building handles the ways an xcconfig value goes wrong.
//
// Nothing here touches the network or the Keychain.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct BackendContractTests {

    // MARK: - Decoding

    @Test func configDecodesEveryDocumentedField() throws {
        let config = try BackendFixtures.decode(BackendConfig.self, BackendFixtures.config)
        #expect(config.flightsEnabled)
        #expect(config.paymentsEnabled)
        #expect(!config.testMode)
        #expect(config.supportEmail == "support@jetsetterpro.app")
        #expect(config.privacyUrl == "https://api.jetsetterpro.app/privacy/")
        #expect(config.termsUrl == "https://api.jetsetterpro.app/terms/")
        #expect(config.supportUrl == "https://api.jetsetterpro.app/support/")
    }

    /// An older or partial server must not turn into "flights on".
    @Test func configMissingFlagsDefaultsToOff() throws {
        let config = try BackendFixtures.decode(BackendConfig.self, "{}")
        #expect(!config.flightsEnabled)
        #expect(!config.paymentsEnabled)
        #expect(!config.testMode)
    }

    @Test func deviceRegistrationDecodes() throws {
        let registration = try BackendFixtures.decode(BackendDeviceRegistration.self, BackendFixtures.deviceRegistration)
        #expect(registration.deviceId == "7f1d2a3e-0000-4000-8000-000000000001")
        #expect(registration.token == "opaque-token-value")
    }

    @Test func offerDecodesSlicesSegmentsConditionsAndBaggage() throws {
        let offer = try BackendFixtures.decode(BackendOffer.self, BackendFixtures.offer)
        #expect(offer.id == "off_0000AaBbCc")
        #expect(offer.airline.name == "Delta Air Lines")
        #expect(offer.airline.iataCode == "DL")
        #expect(offer.airline.logoUrl == "https://assets.example.com/DL.svg")
        #expect(offer.totalAmount == "245.30")
        #expect(offer.totalCurrency == "USD")
        #expect(offer.cabinClass == "economy")
        #expect(offer.passengers == [BackendOfferPassenger(id: "pas_0000AaBbCc", type: "adult")])
        #expect(!offer.requiresIdentityDocuments)
        #expect(offer.baggage == [BackendBaggage(type: "checked", quantity: 1), BackendBaggage(type: "carry_on", quantity: 1)])
        #expect(offer.expiresAt == "2026-10-07T18:00:00Z")

        let slice = try #require(offer.slices.first)
        #expect(slice.origin.iataCode == "LAS")
        #expect(slice.origin.timeZone == "America/Los_Angeles")
        #expect(slice.destination.cityName == "Atlanta")
        #expect(slice.stops == 0)
        #expect(slice.fareBrandName == "Main Cabin")

        let segment = try #require(slice.segments.first)
        #expect(segment.flightNumber == "DL1423")
        #expect(segment.departingAt == "2026-11-02T09:05:00")
        #expect(segment.arrivingAt == "2026-11-02T16:15:00")
        #expect(segment.aircraft == "Boeing 737-900")
        #expect(segment.originTerminal == "1")
        #expect(segment.destinationTerminal == "S")

        let refund = try #require(offer.conditions?.refundBeforeDeparture)
        #expect(refund.allowed == true)
        #expect(refund.penaltyAmount == "50.00")
        #expect(refund.penaltyCurrency == "USD")
        let change = try #require(offer.conditions?.changeBeforeDeparture)
        #expect(change.allowed == true)
        #expect(change.penaltyAmount == nil)
    }

    @Test func searchResponseDecodes() throws {
        let response = try BackendFixtures.decode(BackendSearchResponse.self, BackendFixtures.searchResponse)
        #expect(response.searchId == "orq_0000AaBbCc")
        #expect(response.offers.count == 1)
    }

    @Test func bookingDecodesEveryDocumentedField() throws {
        let booking = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.booking)
        #expect(booking.id == "3b1f6d0e-7a54-4c1e-9d3a-0f2b8a6c1e55")
        #expect(booking.kind == "flight")
        #expect(booking.status == .confirmed)
        #expect(booking.statusDetail == "Ticketed")
        #expect(booking.bookingReference == "ABC123")
        #expect(booking.duffelOrderId == "ord_0000AaBbCc")
        #expect(booking.totalAmount == "245.30")
        #expect(booking.feeAmount == "0.00")
        #expect(!booking.testMode)
        #expect(booking.airline?.logoUrl == nil)
        #expect(booking.slices.count == 1)
        #expect(!booking.hasAirlineChanges)
        #expect(booking.refund == BackendRefund(amount: "120.00", currency: "USD", status: "succeeded"))

        let passenger = try #require(booking.passengers.first)
        #expect(passenger.id == "pas_0000AaBbCc")
        #expect(passenger.title == "mr")
        #expect(passenger.displayName == "Ada Lovelace")
        #expect(passenger.ticketNumber == "006-1234567890")
        #expect(passenger.seat == nil)
    }

    /// Django emits microseconds on some timestamps; that must not break decoding
    /// or the parsed instant.
    @Test func bookingTimestampsParseWithAndWithoutMicroseconds() throws {
        let booking = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.booking)
        let created = try #require(booking.createdDate)
        let updated = try #require(booking.updatedDate)
        let expectedCreated = try #require(ISO8601DateFormatter().date(from: "2026-10-07T12:30:45Z"))
        #expect(created == expectedCreated)
        #expect(updated == expectedCreated.addingTimeInterval(17))
    }

    @Test func everyDocumentedBookingStatusDecodes() throws {
        let expected: [(String, BackendBookingStatus, Bool)] = [
            ("pending_payment", .pendingPayment, false),
            ("processing", .processing, false),
            ("confirmed", .confirmed, true),
            ("failed", .failed, true),
            ("cancelled", .cancelled, true),
            ("expired", .expired, true)
        ]
        for (raw, status, terminal) in expected {
            let booking = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(status: raw))
            #expect(booking.status == status)
            #expect(booking.status.isTerminal == terminal)
            #expect(booking.status.rawValue == raw)
        }
    }

    /// A status the app has never heard of is kept, and is not terminal, so
    /// polling doesn't stop on a state it can't interpret.
    @Test func unknownBookingStatusIsPreservedAndNotTerminal() throws {
        let booking = try BackendFixtures.decode(BackendBooking.self, BackendFixtures.bookingJSON(status: "ticketing_delayed"))
        #expect(booking.status == .unknown("ticketing_delayed"))
        #expect(!booking.status.isTerminal)
    }

    @Test func checkoutResponseWithStripeLinkDecodes() throws {
        let response = try BackendFixtures.decode(BackendCheckoutResponse.self, BackendFixtures.checkoutPending)
        #expect(response.booking.status == .pendingPayment)
        #expect(response.checkoutLink?.host == "checkout.stripe.com")
    }

    @Test func testModeCheckoutHasNoPaymentLink() throws {
        let response = try BackendFixtures.decode(BackendCheckoutResponse.self, BackendFixtures.checkoutTestMode)
        #expect(response.booking.status == .confirmed)
        #expect(response.checkoutUrl == nil)
        #expect(response.checkoutLink == nil)
    }

    /// The in-app browser raises an exception on a non-web scheme, so a
    /// server-supplied link must be filtered, not trusted.
    @Test func nonWebCheckoutLinksAreRejected() throws {
        let json = #"{"booking": \#(BackendFixtures.booking), "checkout_url": "jetsetterpro://evil"}"#
        let response = try BackendFixtures.decode(BackendCheckoutResponse.self, json)
        #expect(response.checkoutLink == nil)
    }

    @Test func bookingsListDecodes() throws {
        let response = try BackendFixtures.decode(BackendBookingsResponse.self, BackendFixtures.bookingsList)
        #expect(response.bookings.map(\.id) == ["3b1f6d0e-7a54-4c1e-9d3a-0f2b8a6c1e55"])
    }

    @Test func cancelQuoteDecodes() throws {
        let quote = try BackendFixtures.decode(BackendCancelQuote.self, BackendFixtures.cancelQuote)
        #expect(quote.cancellationId == "ore_0000AaBbCc")
        #expect(quote.refundAmount == "120.00")
        #expect(quote.refundCurrency == "USD")
        #expect(quote.expiresDate != nil)
    }

    @Test func handoffProvidersDecodeAndLinksAreWebOnly() throws {
        let response = try BackendFixtures.decode(BackendHandoffResponse.self, BackendFixtures.handoff)
        #expect(response.providers.map(\.id) == ["delta", "kayak", "hertz"])
        #expect(response.providers.map(\.kind) == ["airline", "agency", "car_rental"])
        #expect(response.providers.allSatisfy { $0.link != nil })

        let bad = BackendHandoffProvider(id: "x", name: "X", url: "tel:+14155550123", kind: nil)
        #expect(bad.link == nil)
    }

    // MARK: - Errors

    @Test func priceChangedCarriesTheFreshOffer() throws {
        let error = BackendError.make(status: 409, body: Data(BackendFixtures.priceChanged.utf8))
        guard case .priceChanged(let message, let offer) = error else {
            Issue.record("expected priceChanged, got \(error)")
            return
        }
        #expect(message == "The fare changed since you searched.")
        #expect(offer?.id == "off_0000AaBbCc")
        #expect(offer?.totalAmount == "245.30")
    }

    @Test func validationErrorKeepsFieldMessages() {
        let error = BackendError.make(status: 400, body: Data(BackendFixtures.validationError.utf8))
        guard case .validation(let message, _) = error else {
            Issue.record("expected validation, got \(error)")
            return
        }
        #expect(message == "Check the traveler details.")
        // The decoder rewrites dictionary keys too; `fieldKey` matches either form.
        #expect(error.fieldMessages[BackendError.fieldKey("given_name")] == ["This field may not be blank."])
        #expect(error.fieldMessages[BackendError.fieldKey("passengers")] == ["Expected 1 passenger."])
    }

    @Test func errorCodesMapToTheirCases() {
        func make(_ status: Int, _ code: String, retryAfter: TimeInterval? = nil) -> BackendError {
            let body = #"{"error": "\#(code)", "message": "Say this."}"#
            return BackendError.make(status: status, body: Data(body.utf8), retryAfter: retryAfter)
        }
        #expect(make(401, "not_authenticated") == .notAuthenticated)
        #expect(make(404, "not_found") == .notFound(message: "Say this."))
        #expect(make(409, "offer_expired") == .offerExpired(message: "Say this."))
        #expect(make(409, "not_cancellable") == .invalidState(code: "not_cancellable", message: "Say this."))
        #expect(make(409, "invalid_state") == .invalidState(code: "invalid_state", message: "Say this."))
        #expect(make(429, "throttled", retryAfter: 7) == .throttled(message: "Say this.", retryAfter: 7))
        #expect(make(502, "upstream_error") == .upstream(message: "Say this."))
        #expect(make(503, "flights_unavailable") == .flightsUnavailable(message: "Say this."))
        #expect(make(500, "boom") == .server(status: 500, code: "boom", message: "Say this."))
    }

    /// A hotel captive portal answers with HTML, not the contract's JSON.
    @Test func nonJSONErrorBodiesStillProduceASafeMessage() {
        let error = BackendError.make(status: 500, body: Data("<html>Please sign in</html>".utf8))
        guard case .server(let status, let code, let message) = error else {
            Issue.record("expected server error, got \(error)")
            return
        }
        #expect(status == 500)
        #expect(code == nil)
        #expect(!message.contains("<html>"))
    }

    /// The defect this guards: auto-retrying a checkout that timed out can
    /// charge twice. These outcomes must send the app to the booking list.
    @Test func ambiguousCheckoutFailuresAreFlaggedAsPossiblyBooked() {
        #expect(BackendError.timedOut.mayHaveCreatedBooking)
        #expect(BackendError.transport("lost").mayHaveCreatedBooking)
        #expect(BackendError.upstream(message: "x").mayHaveCreatedBooking)
        #expect(BackendError.server(status: 500, code: nil, message: "x").mayHaveCreatedBooking)

        #expect(!BackendError.offline.mayHaveCreatedBooking)
        #expect(!BackendError.validation(message: "x", fields: [:]).mayHaveCreatedBooking)
        #expect(!BackendError.notAuthenticated.mayHaveCreatedBooking)
        #expect(!BackendError.offerExpired(message: "x").mayHaveCreatedBooking)
    }

    @Test func connectivityErrorsMapFromURLErrors() {
        #expect(BackendError.make(urlError: URLError(.notConnectedToInternet)) == .offline)
        #expect(BackendError.make(urlError: URLError(.dataNotAllowed)) == .offline)
        #expect(BackendError.make(urlError: URLError(.timedOut)) == .timedOut)
        #expect(BackendError.offline.isConnectivity)
        #expect(!BackendError.notAuthenticated.isConnectivity)
    }

    // MARK: - Requests

    @Test func checkoutRequestEncodesTheDocumentedKeys() throws {
        let request = BackendCheckoutRequest(
            expectedTotalAmount: "245.30",
            expectedTotalCurrency: "USD",
            passengers: [BackendPassengerInput(
                id: "pas_0000AaBbCc", title: "mr", givenName: "Ada", familyName: "Lovelace",
                bornOn: "1990-12-10", gender: "f", email: "ada@example.com", phoneNumber: "+14155550123",
                identityDocuments: [BackendIdentityDocument(
                    type: "passport", uniqueIdentifier: "X123", issuingCountryCode: "US", expiresOn: "2032-01-01")]
            )]
        )
        let data = try BackendCoding.makeEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["expected_total_amount"] as? String == "245.30")
        #expect(json["expected_total_currency"] as? String == "USD")

        let passenger = try #require((json["passengers"] as? [[String: Any]])?.first)
        #expect(passenger["id"] as? String == "pas_0000AaBbCc")
        #expect(passenger["given_name"] as? String == "Ada")
        #expect(passenger["family_name"] as? String == "Lovelace")
        #expect(passenger["born_on"] as? String == "1990-12-10")
        #expect(passenger["phone_number"] as? String == "+14155550123")

        let document = try #require((passenger["identity_documents"] as? [[String: Any]])?.first)
        #expect(document["type"] as? String == "passport")
        #expect(document["unique_identifier"] as? String == "X123")
        #expect(document["issuing_country_code"] as? String == "US")
        #expect(document["expires_on"] as? String == "2032-01-01")
    }

    /// `identity_documents` is only for fares that need them; absent otherwise.
    @Test func checkoutRequestOmitsDocumentsWhenNotRequired() throws {
        let passenger = BackendPassengerInput(
            id: "pas_1", title: "ms", givenName: "Grace", familyName: "Hopper", bornOn: "1985-12-09",
            gender: "f", email: "g@example.com", phoneNumber: "+12025550100", identityDocuments: nil)
        let data = try BackendCoding.makeEncoder().encode(passenger)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["identity_documents"] == nil)
    }

    @Test func searchRequestEncodesTheDocumentedKeys() throws {
        let request = BackendSearchRequest(
            slices: [
                BackendSearchSlice(origin: "LAS", destination: "ATL", departureDate: "2026-11-02"),
                BackendSearchSlice(origin: "ATL", destination: "LAS", departureDate: "2026-11-05")
            ],
            passengers: BackendSearchPassengers(adults: 2, children: 0, infants: 0),
            cabinClass: "premium_economy"
        )
        let data = try BackendCoding.makeEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["cabin_class"] as? String == "premium_economy")
        let slices = try #require(json["slices"] as? [[String: Any]])
        #expect(slices.count == 2)
        #expect(slices[0]["departure_date"] as? String == "2026-11-02")
        #expect((json["passengers"] as? [String: Any])?["adults"] as? Int == 2)
    }

    @Test func searchRequestIsBuiltFromTheFormIncludingTheReturnLeg() throws {
        var params = FlightSearchParams()
        params.origin = " las "
        params.destination = "atl"
        params.adults = 2
        params.tripType = .roundTrip
        params.cabinClass = .premiumEconomy
        params.departDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        params.returnDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))

        let request = try #require(FlightSearchRequestBuilder.make(from: params))
        #expect(request.slices == [
            BackendSearchSlice(origin: "LAS", destination: "ATL", departureDate: "2026-11-02"),
            BackendSearchSlice(origin: "ATL", destination: "LAS", departureDate: "2026-11-05")
        ])
        #expect(request.passengers.adults == 2)
        #expect(request.cabinClass == "premium_economy")

        params.tripType = .oneWay
        #expect(FlightSearchRequestBuilder.make(from: params)?.slices.count == 1)

        params.destination = "LAS"
        #expect(FlightSearchRequestBuilder.make(from: params) == nil)
    }

    // MARK: - Client configuration

    @Test func baseURLIsNormalised() {
        func url(_ raw: String?) -> String? { BackendConfiguration.normalizedBaseURL(raw)?.absoluteString }
        #expect(url("https://jetsetter-api.up.railway.app") == "https://jetsetter-api.up.railway.app")
        #expect(url("  https://jetsetter-api.up.railway.app/  ") == "https://jetsetter-api.up.railway.app")
        #expect(url("https://jetsetter-api.up.railway.app/api/v1") == "https://jetsetter-api.up.railway.app")
        #expect(url("https://jetsetter-api.up.railway.app/api/v1/") == "https://jetsetter-api.up.railway.app")
        #expect(url("jetsetter-api.up.railway.app") == "https://jetsetter-api.up.railway.app")
        #expect(url("http://localhost:8000") == "http://localhost:8000")
    }

    /// The xcconfig `//` trap: "https://host" is cut to "https:" at the comment.
    @Test func unusableBaseURLsMeanNotConfigured() {
        #expect(BackendConfiguration.normalizedBaseURL(nil) == nil)
        #expect(BackendConfiguration.normalizedBaseURL("") == nil)
        #expect(BackendConfiguration.normalizedBaseURL("   ") == nil)
        #expect(BackendConfiguration.normalizedBaseURL("https:") == nil)
        #expect(BackendConfiguration.normalizedBaseURL("$(API_BACKEND_URL)") == nil)
        #expect(BackendConfiguration.normalizedBaseURL("YOUR_BACKEND_URL") == nil)
        #expect(BackendConfiguration.normalizedBaseURL("http://example.com") == nil)
    }

    @Test func endpointURLsAddTheVersionPrefixAndQuery() throws {
        let base = try #require(URL(string: "https://api.example.com"))
        #expect(BackendConfiguration.endpointURL(base: base, path: "/config")?.absoluteString
                == "https://api.example.com/api/v1/config")
        #expect(BackendConfiguration.endpointURL(
            base: base, path: "/bookings/abc", query: [URLQueryItem(name: "refresh", value: "true")])?.absoluteString
                == "https://api.example.com/api/v1/bookings/abc?refresh=true")

        let withPath = try #require(URL(string: "https://example.com/jetsetter"))
        #expect(BackendConfiguration.endpointURL(base: withPath, path: "/config")?.absoluteString
                == "https://example.com/jetsetter/api/v1/config")
    }

    @Test func clientWithoutAURLReportsNotConfigured() async {
        let client = BackendClient(baseURL: nil)
        #expect(!client.isConfigured)
        await #expect(throws: BackendError.notConfigured) { try await client.config() }
    }
}
