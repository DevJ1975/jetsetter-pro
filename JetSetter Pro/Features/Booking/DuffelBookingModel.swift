// File: Features/Booking/DuffelBookingModel.swift
//
// App-side models for real Duffel flight booking through the proxy. The app
// never talks to Duffel directly (the token is server-only); it searches for
// offers and books an offer id via the proxy routes in server/duffel-proxy.
// Field names decode from the proxy's snake_case JSON via convertFromSnakeCase
// — mirror Duffel's documented shapes. `nonisolated` so they cross the booking
// actor boundary cleanly (matching Trip/Expense/WalletItem).

import Foundation

// MARK: - Search input

/// User-entered flight search, turned into a Duffel offer-request.
nonisolated struct DuffelSearchParams {
    var origin: String            // IATA, e.g. "JFK"
    var destination: String       // IATA, e.g. "LAX"
    var departDate: Date
    var returnDate: Date?         // nil = one-way
    var adults: Int = 1

    /// yyyy-MM-dd, the format Duffel slices require. Reuses the shared date-only
    /// formatter defined in BookingModel.
    private func day(_ date: Date) -> String {
        ISO8601DateFormatter.expediaDate.string(from: date)
    }

    /// Encodable body for `POST /duffel/offer-requests`.
    func offerRequestBody() -> DuffelOfferRequestBody {
        var slices = [DuffelOfferRequestBody.Slice(
            origin: origin, destination: destination, departureDate: day(departDate)
        )]
        if let returnDate {
            slices.append(.init(origin: destination, destination: origin, departureDate: day(returnDate)))
        }
        let passengers = Array(repeating: DuffelOfferRequestBody.Passenger(type: "adult"),
                               count: max(1, adults))
        return DuffelOfferRequestBody(slices: slices, passengers: passengers, cabinClass: "economy")
    }
}

// MARK: - Request bodies (snake_case out)

nonisolated struct DuffelOfferRequestBody: Encodable {
    nonisolated struct Slice: Encodable {
        let origin: String
        let destination: String
        let departureDate: String
        enum CodingKeys: String, CodingKey { case origin, destination, departureDate = "departure_date" }
    }
    nonisolated struct Passenger: Encodable { let type: String }

    let slices: [Slice]
    let passengers: [Passenger]
    let cabinClass: String
    enum CodingKeys: String, CodingKey { case slices, passengers, cabinClass = "cabin_class" }
}

/// A traveler as sent to `POST /duffel/offers/:id/order`. `id` MUST be the
/// passenger id Duffel echoed on the chosen offer (not invented).
nonisolated struct DuffelPassengerBooking: Encodable {
    let id: String
    let title: String            // "mr" | "mrs" | "ms" | "miss" | "dr"
    let givenName: String
    let familyName: String
    let bornOn: String           // yyyy-MM-dd
    let gender: String           // "m" | "f"
    let email: String
    let phoneNumber: String      // E.164, e.g. "+14155550123"
    let type: String             // "adult"
    enum CodingKeys: String, CodingKey {
        case id, title, gender, email, type
        case givenName = "given_name"
        case familyName = "family_name"
        case bornOn = "born_on"
        case phoneNumber = "phone_number"
    }
}

nonisolated struct DuffelOrderRequestBody: Encodable {
    let passengers: [DuffelPassengerBooking]
    let paymentReference: String?
    enum CodingKeys: String, CodingKey {
        case passengers
        case paymentReference = "payment_reference"
    }
}

// MARK: - Responses (snake_case in → camelCase via convertFromSnakeCase)

nonisolated struct DuffelSearchResponse: Decodable {
    let offerRequestId: String
    let offers: [DuffelOffer]
}

/// A bookable offer. Only the fields the app needs are modeled; the rest of
/// Duffel's large offer object is ignored.
nonisolated struct DuffelOffer: Decodable, Identifiable {
    let id: String
    let totalAmount: String       // decimal string, e.g. "245.30"
    let totalCurrency: String
    let passengers: [OfferPassenger]
    let owner: Carrier?
    let slices: [Slice]?

    nonisolated struct OfferPassenger: Decodable { let id: String }
    nonisolated struct Carrier: Decodable { let name: String?; let iataCode: String? }
    nonisolated struct Slice: Decodable {
        let origin: Place?
        let destination: Place?
        nonisolated struct Place: Decodable { let iataCode: String?; let cityName: String? }
    }
}

/// Result of a successful `POST /duffel/offers/:id/order`.
nonisolated struct DuffelOrderConfirmation: Decodable {
    let orderId: String           // ord_…
    let bookingReference: String  // airline PNR
    let totalAmount: String
    let totalCurrency: String
}
