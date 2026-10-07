// File: Core/Network/BackendModels.swift
//
// Wire models for the JetSetter booking backend (docs/BACKEND_API.md, v1).
// Every type mirrors one object in that contract. Three rules from the contract
// shape this file:
//
//  * Money is a decimal STRING plus an ISO currency, never a float. The strings
//    are kept exactly as received so `expected_total_amount` can be echoed back
//    byte-for-byte on checkout; display goes through `BackendMoney`.
//  * Flight times (`departing_at`, `arriving_at`) are wall-clock times at the
//    airport with NO zone ("2026-11-02T09:05:00"). They stay `String` here and
//    are converted with the airport's zone by `BackendDates`, never by decoding
//    them as a `Date` (which would silently use UTC or fail).
//  * Timestamps (`created_at`, `expires_at`) are kept as `String` too and
//    exposed as `Date?` computed properties. Django emits microseconds on some
//    of them, and one unparseable timestamp must not make a whole booking list
//    undecodable.
//
// All types are `nonisolated` + `Sendable` (the module defaults to MainActor)
// so the `BackendClient` actor can return them to any context. They are also
// `Encodable` with property-name keys so the offline bookings cache can round
// trip them; the wire decoder uses `.convertFromSnakeCase`, which maps
// `logo_url` to the `logoUrl` property name used here.

import Foundation

// MARK: - Coding

nonisolated enum BackendCoding {

    /// Decoder for backend responses: snake_case keys.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// http(s) only. `SFSafariViewController` raises an exception on any other
    /// scheme, and a server-supplied link must never be able to trigger that.
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    /// Encoder for backend request bodies: snake_case keys.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

// MARK: - Config

/// `GET /api/v1/config`. Every field has a safe default so an older server that
/// omits one doesn't make the whole config undecodable.
nonisolated struct BackendConfig: Codable, Sendable, Equatable {
    var flightsEnabled: Bool
    var paymentsEnabled: Bool
    /// True when the server runs on a `duffel_test_…` token: bookings are fake.
    var testMode: Bool
    var supportEmail: String?
    var privacyUrl: String?
    var termsUrl: String?
    var supportUrl: String?

    init(
        flightsEnabled: Bool = false,
        paymentsEnabled: Bool = false,
        testMode: Bool = false,
        supportEmail: String? = nil,
        privacyUrl: String? = nil,
        termsUrl: String? = nil,
        supportUrl: String? = nil
    ) {
        self.flightsEnabled = flightsEnabled
        self.paymentsEnabled = paymentsEnabled
        self.testMode = testMode
        self.supportEmail = supportEmail
        self.privacyUrl = privacyUrl
        self.termsUrl = termsUrl
        self.supportUrl = supportUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flightsEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .flightsEnabled) ?? false
        paymentsEnabled = try c.decodeIfPresent(Bool.self,   forKey: .paymentsEnabled) ?? false
        testMode        = try c.decodeIfPresent(Bool.self,   forKey: .testMode) ?? false
        supportEmail    = try c.decodeIfPresent(String.self, forKey: .supportEmail)
        privacyUrl      = try c.decodeIfPresent(String.self, forKey: .privacyUrl)
        termsUrl        = try c.decodeIfPresent(String.self, forKey: .termsUrl)
        supportUrl      = try c.decodeIfPresent(String.self, forKey: .supportUrl)
    }
}

// MARK: - Device registration

/// `POST /api/v1/devices/register` response.
nonisolated struct BackendDeviceRegistration: Codable, Sendable, Equatable {
    var deviceId: String
    var token: String
}

// MARK: - Airports and carriers

nonisolated struct BackendCarrier: Codable, Sendable, Equatable, Hashable {
    var name: String?
    var iataCode: String?
    var logoUrl: String?
}

nonisolated struct BackendAirport: Codable, Sendable, Equatable, Hashable {
    var iataCode: String
    var name: String?
    var cityName: String?
    /// IANA identifier from the server ("America/Los_Angeles"). Nil when
    /// Duffel didn't supply one; callers then fall back to `AirportCoordinates`.
    var timeZone: String?
}

// MARK: - Slices and segments

nonisolated struct BackendSegment: Codable, Sendable, Equatable, Hashable {
    var marketingCarrier: BackendCarrier?
    /// Not in contract v1. Decoded if the server ever sends it, because check-in
    /// happens with the operating carrier on a codeshare.
    var operatingCarrier: BackendCarrier?
    /// Already the full designator ("DL1423").
    var flightNumber: String?
    var origin: BackendAirport
    var destination: BackendAirport
    /// Local wall-clock at `origin`, no zone: "2026-11-02T09:05:00".
    var departingAt: String
    /// Local wall-clock at `destination`, no zone.
    var arrivingAt: String
    /// ISO-8601 duration: "PT4H10M".
    var duration: String?
    var aircraft: String?
    var originTerminal: String?
    var destinationTerminal: String?
}

nonisolated struct BackendSlice: Codable, Sendable, Equatable, Hashable {
    var origin: BackendAirport
    var destination: BackendAirport
    var duration: String?
    var stops: Int
    var fareBrandName: String?
    var segments: [BackendSegment]

    init(origin: BackendAirport, destination: BackendAirport, duration: String? = nil,
         stops: Int = 0, fareBrandName: String? = nil, segments: [BackendSegment] = []) {
        self.origin = origin
        self.destination = destination
        self.duration = duration
        self.stops = stops
        self.fareBrandName = fareBrandName
        self.segments = segments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin        = try c.decode(BackendAirport.self, forKey: .origin)
        destination   = try c.decode(BackendAirport.self, forKey: .destination)
        duration      = try c.decodeIfPresent(String.self, forKey: .duration)
        stops         = try c.decodeIfPresent(Int.self, forKey: .stops) ?? 0
        fareBrandName = try c.decodeIfPresent(String.self, forKey: .fareBrandName)
        segments      = try c.decodeIfPresent([BackendSegment].self, forKey: .segments) ?? []
    }
}

// MARK: - Conditions and baggage

nonisolated struct BackendConditionRule: Codable, Sendable, Equatable, Hashable {
    /// Nil when the airline didn't say. Never treat nil as "allowed".
    var allowed: Bool?
    var penaltyAmount: String?
    var penaltyCurrency: String?
}

nonisolated struct BackendConditions: Codable, Sendable, Equatable, Hashable {
    /// Either side can be nil when the airline didn't say.
    var refundBeforeDeparture: BackendConditionRule?
    var changeBeforeDeparture: BackendConditionRule?
}

nonisolated struct BackendBaggage: Codable, Sendable, Equatable, Hashable {
    /// "checked" or "carry_on".
    var type: String
    var quantity: Int
}

// MARK: - Offer

nonisolated struct BackendOfferPassenger: Codable, Sendable, Equatable, Hashable {
    /// Duffel's passenger id ("pas_…"). Must be echoed on checkout.
    var id: String
    /// "adult", "child" or "infant_without_seat".
    var type: String?
}

nonisolated struct BackendOffer: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var airline: BackendCarrier
    /// What the traveler pays: Duffel total plus any server service fee.
    var totalAmount: String
    var totalCurrency: String
    var feeAmount: String?
    var cabinClass: String?
    var slices: [BackendSlice]
    var passengers: [BackendOfferPassenger]
    var requiresIdentityDocuments: Bool
    var conditions: BackendConditions?
    var baggage: [BackendBaggage]
    var expiresAt: String?

    var expiresDate: Date? { expiresAt.flatMap(BackendDates.parseTimestamp) }

    init(id: String, airline: BackendCarrier, totalAmount: String, totalCurrency: String,
         feeAmount: String? = nil, cabinClass: String? = nil, slices: [BackendSlice] = [],
         passengers: [BackendOfferPassenger] = [], requiresIdentityDocuments: Bool = false,
         conditions: BackendConditions? = nil, baggage: [BackendBaggage] = [], expiresAt: String? = nil) {
        self.id = id
        self.airline = airline
        self.totalAmount = totalAmount
        self.totalCurrency = totalCurrency
        self.feeAmount = feeAmount
        self.cabinClass = cabinClass
        self.slices = slices
        self.passengers = passengers
        self.requiresIdentityDocuments = requiresIdentityDocuments
        self.conditions = conditions
        self.baggage = baggage
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self, forKey: .id)
        airline        = try c.decode(BackendCarrier.self, forKey: .airline)
        totalAmount    = try c.decode(String.self, forKey: .totalAmount)
        totalCurrency  = try c.decode(String.self, forKey: .totalCurrency)
        feeAmount      = try c.decodeIfPresent(String.self, forKey: .feeAmount)
        cabinClass     = try c.decodeIfPresent(String.self, forKey: .cabinClass)
        slices         = try c.decodeIfPresent([BackendSlice].self, forKey: .slices) ?? []
        passengers     = try c.decodeIfPresent([BackendOfferPassenger].self, forKey: .passengers) ?? []
        requiresIdentityDocuments = try c.decodeIfPresent(Bool.self, forKey: .requiresIdentityDocuments) ?? false
        conditions     = try c.decodeIfPresent(BackendConditions.self, forKey: .conditions)
        baggage        = try c.decodeIfPresent([BackendBaggage].self, forKey: .baggage) ?? []
        expiresAt      = try c.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

// MARK: - Booking

/// `status` is a state machine:
/// pending_payment (waiting on Stripe) -> processing (paid, ordering with the
/// airline) -> confirmed, with failed / cancelled / expired as terminal exits.
/// An unrecognised value is kept, not crashed on, so a newer server can add a
/// state without breaking an older app.
nonisolated enum BackendBookingStatus: Codable, Sendable, Equatable, Hashable {
    case pendingPayment
    case processing
    case confirmed
    case failed
    case cancelled
    case expired
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "pending_payment": self = .pendingPayment
        case "processing":      self = .processing
        case "confirmed":       self = .confirmed
        case "failed":          self = .failed
        case "cancelled":       self = .cancelled
        case "expired":         self = .expired
        default:                self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .pendingPayment: return "pending_payment"
        case .processing:     return "processing"
        case .confirmed:      return "confirmed"
        case .failed:         return "failed"
        case .cancelled:      return "cancelled"
        case .expired:        return "expired"
        case .unknown(let raw): return raw
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Nothing more will happen to this booking without the traveler acting.
    /// An unknown status is NOT terminal, so polling keeps going until its own
    /// timeout rather than stopping on a state it doesn't understand.
    var isTerminal: Bool {
        switch self {
        case .confirmed, .failed, .cancelled, .expired: return true
        case .pendingPayment, .processing, .unknown:    return false
        }
    }
}

nonisolated struct BackendBookingPassenger: Codable, Sendable, Equatable, Hashable {
    var id: String?
    var type: String?
    var title: String?
    var givenName: String?
    var familyName: String?
    var ticketNumber: String?
    var seat: String?

    /// "Ada Lovelace", or nil when the server sent no name (never invented).
    var displayName: String? {
        let parts = [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

nonisolated struct BackendRefund: Codable, Sendable, Equatable, Hashable {
    var amount: String
    var currency: String
    var status: String?
}

nonisolated struct BackendBooking: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: String
    var status: BackendBookingStatus
    var statusDetail: String?
    /// The airline PNR the traveler uses at check-in.
    var bookingReference: String?
    var duffelOrderId: String?
    var totalAmount: String
    var totalCurrency: String
    var feeAmount: String?
    var testMode: Bool
    var airline: BackendCarrier?
    var slices: [BackendSlice]
    var passengers: [BackendBookingPassenger]
    var baggage: [BackendBaggage]
    var conditions: BackendConditions?
    var hasAirlineChanges: Bool
    /// Nil unless money was returned.
    var refund: BackendRefund?
    var createdAt: String?
    var updatedAt: String?

    var createdDate: Date? { createdAt.flatMap(BackendDates.parseTimestamp) }
    var updatedDate: Date? { updatedAt.flatMap(BackendDates.parseTimestamp) }

    init(id: String, kind: String = "flight", status: BackendBookingStatus,
         statusDetail: String? = nil, bookingReference: String? = nil, duffelOrderId: String? = nil,
         totalAmount: String, totalCurrency: String, feeAmount: String? = nil, testMode: Bool = false,
         airline: BackendCarrier? = nil, slices: [BackendSlice] = [],
         passengers: [BackendBookingPassenger] = [], baggage: [BackendBaggage] = [],
         conditions: BackendConditions? = nil, hasAirlineChanges: Bool = false,
         refund: BackendRefund? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.statusDetail = statusDetail
        self.bookingReference = bookingReference
        self.duffelOrderId = duffelOrderId
        self.totalAmount = totalAmount
        self.totalCurrency = totalCurrency
        self.feeAmount = feeAmount
        self.testMode = testMode
        self.airline = airline
        self.slices = slices
        self.passengers = passengers
        self.baggage = baggage
        self.conditions = conditions
        self.hasAirlineChanges = hasAirlineChanges
        self.refund = refund
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self, forKey: .id)
        kind             = try c.decodeIfPresent(String.self, forKey: .kind) ?? "flight"
        status           = try c.decode(BackendBookingStatus.self, forKey: .status)
        statusDetail     = try c.decodeIfPresent(String.self, forKey: .statusDetail)
        bookingReference = try c.decodeIfPresent(String.self, forKey: .bookingReference)
        duffelOrderId    = try c.decodeIfPresent(String.self, forKey: .duffelOrderId)
        totalAmount      = try c.decode(String.self, forKey: .totalAmount)
        totalCurrency    = try c.decode(String.self, forKey: .totalCurrency)
        feeAmount        = try c.decodeIfPresent(String.self, forKey: .feeAmount)
        testMode         = try c.decodeIfPresent(Bool.self, forKey: .testMode) ?? false
        airline          = try c.decodeIfPresent(BackendCarrier.self, forKey: .airline)
        slices           = try c.decodeIfPresent([BackendSlice].self, forKey: .slices) ?? []
        passengers       = try c.decodeIfPresent([BackendBookingPassenger].self, forKey: .passengers) ?? []
        baggage          = try c.decodeIfPresent([BackendBaggage].self, forKey: .baggage) ?? []
        conditions       = try c.decodeIfPresent(BackendConditions.self, forKey: .conditions)
        hasAirlineChanges = try c.decodeIfPresent(Bool.self, forKey: .hasAirlineChanges) ?? false
        refund           = try c.decodeIfPresent(BackendRefund.self, forKey: .refund)
        createdAt        = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt        = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - Cancellation

/// `POST /bookings/{id}/cancel/quote`. `refundAmount` may be "0.00".
nonisolated struct BackendCancelQuote: Codable, Sendable, Equatable {
    var cancellationId: String
    var refundAmount: String
    var refundCurrency: String
    var expiresAt: String?

    var expiresDate: Date? { expiresAt.flatMap(BackendDates.parseTimestamp) }
}

// MARK: - Hand-off

nonisolated struct BackendHandoffProvider: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    /// "airline", "agency", "hotel" or "car_rental".
    var kind: String?

    var link: URL? {
        guard let parsed = URL(string: url), BackendCoding.isWebURL(parsed) else { return nil }
        return parsed
    }
}

// MARK: - Response envelopes

nonisolated struct BackendSearchResponse: Codable, Sendable, Equatable {
    var searchId: String?
    var offers: [BackendOffer]
}

nonisolated struct BackendCheckoutResponse: Codable, Sendable, Equatable {
    var booking: BackendBooking
    /// Nil in test mode (no Stripe): the booking is already confirmed.
    var checkoutUrl: String?

    var checkoutLink: URL? {
        guard let checkoutUrl, let parsed = URL(string: checkoutUrl), BackendCoding.isWebURL(parsed) else { return nil }
        return parsed
    }
}

nonisolated struct BackendBookingsResponse: Codable, Sendable, Equatable {
    var bookings: [BackendBooking]
}

nonisolated struct BackendHandoffResponse: Codable, Sendable, Equatable {
    var providers: [BackendHandoffProvider]
}

// MARK: - Requests

nonisolated struct BackendSearchSlice: Codable, Sendable, Equatable {
    var origin: String
    var destination: String
    /// yyyy-MM-dd
    var departureDate: String
}

nonisolated struct BackendSearchPassengers: Codable, Sendable, Equatable {
    var adults: Int
    var children: Int
    var infants: Int
}

nonisolated struct BackendSearchRequest: Codable, Sendable, Equatable {
    var slices: [BackendSearchSlice]
    var passengers: BackendSearchPassengers
    /// economy | premium_economy | business | first
    var cabinClass: String
}

nonisolated struct BackendIdentityDocument: Codable, Sendable, Equatable {
    /// "passport"
    var type: String
    var uniqueIdentifier: String
    /// ISO 3166-1 alpha-2
    var issuingCountryCode: String
    /// yyyy-MM-dd
    var expiresOn: String
}

nonisolated struct BackendPassengerInput: Codable, Sendable, Equatable {
    /// The id Duffel returned on the offer ("pas_…").
    var id: String
    /// mr | mrs | ms | miss | dr
    var title: String
    var givenName: String
    var familyName: String
    /// yyyy-MM-dd
    var bornOn: String
    /// m | f
    var gender: String
    var email: String
    /// E.164
    var phoneNumber: String
    /// Only sent when the offer has `requires_identity_documents`.
    var identityDocuments: [BackendIdentityDocument]?
}

nonisolated struct BackendCheckoutRequest: Codable, Sendable, Equatable {
    /// Echoed from the offer exactly as received.
    var expectedTotalAmount: String
    var expectedTotalCurrency: String
    var passengers: [BackendPassengerInput]
}

nonisolated struct BackendCancelConfirmRequest: Codable, Sendable, Equatable {
    var cancellationId: String
}

nonisolated struct BackendRegisterRequest: Codable, Sendable, Equatable {
    var appVersion: String?
    var platform: String
}
