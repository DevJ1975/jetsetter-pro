// File: JetSetter ProTests/BackendFixtures.swift
//
// JSON fixtures for the booking backend tests. Each one is the example object
// from docs/BACKEND_API.md with the elided parts ("off_…", "https://…") filled
// in, so a decoding test breaks if the contract and the app's models drift apart.

import Foundation
@testable import JetSetter_Pro

enum BackendFixtures {

    // MARK: - Config

    static let config = #"""
    {
      "flights_enabled": true,
      "payments_enabled": true,
      "test_mode": false,
      "support_email": "support@jetsetterpro.app",
      "privacy_url": "https://api.jetsetterpro.app/privacy/",
      "terms_url": "https://api.jetsetterpro.app/terms/",
      "support_url": "https://api.jetsetterpro.app/support/"
    }
    """#

    static let deviceRegistration = #"""
    {"device_id": "7f1d2a3e-0000-4000-8000-000000000001", "token": "opaque-token-value"}
    """#

    // MARK: - Slice and offer

    /// LAS 09:05 (America/Los_Angeles) -> ATL 16:15 (America/New_York), DL1423.
    /// 2 November 2026 is after US daylight time ended (1 November): LAS is UTC-8
    /// and ATL is UTC-5, so this is 17:05Z -> 21:15Z, a 4h10m flight.
    static let slice = #"""
    {
      "origin": {"iata_code": "LAS", "name": "Harry Reid International", "city_name": "Las Vegas", "time_zone": "America/Los_Angeles"},
      "destination": {"iata_code": "ATL", "name": "Hartsfield-Jackson Atlanta International", "city_name": "Atlanta", "time_zone": "America/New_York"},
      "duration": "PT4H10M",
      "stops": 0,
      "fare_brand_name": "Main Cabin",
      "segments": [{
        "marketing_carrier": {"name": "Delta Air Lines", "iata_code": "DL"},
        "flight_number": "DL1423",
        "origin": {"iata_code": "LAS", "name": "Harry Reid International", "city_name": "Las Vegas", "time_zone": "America/Los_Angeles"},
        "destination": {"iata_code": "ATL", "name": "Hartsfield-Jackson Atlanta International", "city_name": "Atlanta", "time_zone": "America/New_York"},
        "departing_at": "2026-11-02T09:05:00",
        "arriving_at": "2026-11-02T16:15:00",
        "duration": "PT4H10M",
        "aircraft": "Boeing 737-900",
        "origin_terminal": "1",
        "destination_terminal": "S"
      }]
    }
    """#

    static let conditions = #"""
    {
      "refund_before_departure": {"allowed": true, "penalty_amount": "50.00", "penalty_currency": "USD"},
      "change_before_departure": {"allowed": true, "penalty_amount": null, "penalty_currency": null}
    }
    """#

    static let offer = #"""
    {
      "id": "off_0000AaBbCc",
      "airline": {"name": "Delta Air Lines", "iata_code": "DL", "logo_url": "https://assets.example.com/DL.svg"},
      "total_amount": "245.30", "total_currency": "USD",
      "cabin_class": "economy",
      "slices": [\#(slice)],
      "passengers": [{"id": "pas_0000AaBbCc", "type": "adult"}],
      "requires_identity_documents": false,
      "conditions": \#(conditions),
      "baggage": [{"type": "checked", "quantity": 1}, {"type": "carry_on", "quantity": 1}],
      "expires_at": "2026-10-07T18:00:00Z"
    }
    """#

    static let searchResponse = #"""
    {"search_id": "orq_0000AaBbCc", "offers": [\#(offer)]}
    """#

    // MARK: - Booking

    static let booking = #"""
    {
      "id": "3b1f6d0e-7a54-4c1e-9d3a-0f2b8a6c1e55",
      "kind": "flight",
      "status": "confirmed",
      "status_detail": "Ticketed",
      "booking_reference": "ABC123",
      "duffel_order_id": "ord_0000AaBbCc",
      "total_amount": "245.30", "total_currency": "USD",
      "fee_amount": "0.00",
      "test_mode": false,
      "airline": {"name": "Delta Air Lines", "iata_code": "DL", "logo_url": null},
      "slices": [\#(slice)],
      "passengers": [{"id": "pas_0000AaBbCc", "type": "adult", "title": "mr", "given_name": "Ada", "family_name": "Lovelace", "ticket_number": "006-1234567890", "seat": null}],
      "baggage": [{"type": "checked", "quantity": 1}],
      "conditions": \#(conditions),
      "has_airline_changes": false,
      "refund": {"amount": "120.00", "currency": "USD", "status": "succeeded"},
      "created_at": "2026-10-07T12:30:45.123456Z", "updated_at": "2026-10-07T12:31:02Z"
    }
    """#

    /// A booking with the given status and no refund object (`refund` null).
    static func bookingJSON(status: String, detail: String? = nil, refund: String = "null") -> String {
        let detailJSON = detail.map { "\"\($0)\"" } ?? "null"
        return #"""
        {
          "id": "3b1f6d0e-7a54-4c1e-9d3a-0f2b8a6c1e55",
          "kind": "flight",
          "status": "\#(status)",
          "status_detail": \#(detailJSON),
          "booking_reference": null,
          "duffel_order_id": null,
          "total_amount": "245.30", "total_currency": "USD",
          "test_mode": false,
          "slices": [],
          "passengers": [],
          "refund": \#(refund),
          "created_at": "2026-10-07T12:30:45Z", "updated_at": "2026-10-07T12:31:02Z"
        }
        """#
    }

    static let checkoutPending = #"""
    {"booking": \#(bookingJSON(status: "pending_payment")), "checkout_url": "https://checkout.stripe.com/c/pay/cs_test_abc"}
    """#

    static let checkoutTestMode = #"""
    {"booking": \#(booking), "checkout_url": null}
    """#

    static let bookingsList = #"""
    {"bookings": [\#(booking)]}
    """#

    static let cancelQuote = #"""
    {"cancellation_id": "ore_0000AaBbCc", "refund_amount": "120.00", "refund_currency": "USD", "expires_at": "2026-10-07T13:00:00Z"}
    """#

    static let handoff = #"""
    {"providers": [
      {"id": "delta", "name": "Delta Air Lines", "url": "https://www.delta.com/flights?from=LAS&to=ATL", "kind": "airline"},
      {"id": "kayak", "name": "Kayak", "url": "https://www.kayak.com/flights/LAS-ATL/2026-11-02", "kind": "agency"},
      {"id": "hertz", "name": "Hertz", "url": "https://www.hertz.com/", "kind": "car_rental"}
    ]}
    """#

    // MARK: - Errors

    static let priceChanged = #"""
    {"error": "price_changed", "message": "The fare changed since you searched.", "offer": \#(offer)}
    """#

    static let validationError = #"""
    {"error": "validation_error", "message": "Check the traveler details.", "fields": {"given_name": ["This field may not be blank."], "passengers": ["Expected 1 passenger."]}}
    """#

    // MARK: - Decoding

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try BackendCoding.makeDecoder().decode(T.self, from: Data(json.utf8))
    }
}
