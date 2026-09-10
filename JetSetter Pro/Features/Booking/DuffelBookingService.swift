// File: Features/Booking/DuffelBookingService.swift
//
// Talks to the server-side Duffel proxy (server/duffel-proxy) — search offers,
// then create a paid order. The Duffel token lives only on the proxy; the app
// authenticates with the shared PROXY_APP_KEY. On a successful order the id is
// persisted to BOTH the trip's flight ItineraryItem (for display) and a
// boarding-pass WalletItem's rawData["duffel_order_id"] (which
// DisruptionResponseEngine.fetchDuffelOrderID reads for rebooking eligibility).

import Foundation

enum DuffelBookingError: LocalizedError {
    case notConfigured
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Flight booking isn't configured yet."
        case .requestFailed(let message):
            return message
        }
    }
}

actor DuffelBookingService {

    static let shared = DuffelBookingService()
    private init() {}

    /// True when the proxy is configured — the UI uses this to choose the real
    /// Duffel flow vs. the Kayak deep-link fallback.
    nonisolated static var isConfigured: Bool {
        secret("API_DUFFEL_PROXY_URL") != nil && secret("API_DUFFEL_PROXY_KEY") != nil
    }

    /// Reads a proxy config value from Info.plist without touching the
    /// MainActor-isolated `AppSecrets` (this type is an actor). Mirrors
    /// `AppSecrets.value(for:)`'s placeholder handling and
    /// `DisruptionResponseEngine.readDisruptionSecret`.
    nonisolated static func secret(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("YOUR_") || trimmed == "REPLACE_ME" { return nil }
        return trimmed
    }

    // MARK: - Public API

    /// Searches Duffel for bookable offers matching `params`.
    func searchOffers(_ params: DuffelSearchParams) async throws -> [DuffelOffer] {
        let response: DuffelSearchResponse = try await post(
            path: "/duffel/offer-requests", body: params.offerRequestBody()
        )
        return response.offers
    }

    /// Creates a paid order for `offerId`. `paymentReference` is the Stripe
    /// PaymentIntent id from a completed Apple Pay charge (the charge must succeed
    /// first); it's stashed in Duffel metadata for reconciliation.
    func createOrder(
        offerId: String,
        passengers: [DuffelPassengerBooking],
        paymentReference: String?
    ) async throws -> DuffelOrderConfirmation {
        try await post(
            path: "/duffel/offers/\(offerId)/order",
            body: DuffelOrderRequestBody(passengers: passengers, paymentReference: paymentReference)
        )
    }

    // MARK: - Networking

    private func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        guard let base = Self.secret("API_DUFFEL_PROXY_URL"),
              let key = Self.secret("API_DUFFEL_PROXY_KEY"),
              let url = URL(string: "\(base)\(path)") else {
            throw DuffelBookingError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Order creation can be slow (airlines take up to ~120s) — give it room.
        request.timeoutInterval = 130
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DuffelBookingError.requestFailed("No response from booking service.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The proxy returns { error } for handled failures.
            let message = (try? JSONDecoder().decode(ProxyError.self, from: data))?.error
                ?? "Booking request failed (\(http.statusCode))."
            throw DuffelBookingError.requestFailed(message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DuffelBookingError.requestFailed("Couldn't read the booking response.")
        }
    }

    private struct ProxyError: Decodable { let error: String }
}

// MARK: - Persistence

enum DuffelBookingPersistence {

    /// Records a booked flight after a successful order:
    ///  1. appends a flight `ItineraryItem` to `trip` (via TravelStore), carrying
    ///     the airline PNR as its confirmation number and the Duffel order id in
    ///     notes for display;
    ///  2. upserts a boarding-pass `WalletItem` whose rawData carries
    ///     `duffel_order_id` so rebooking-eligibility works.
    static func record(
        order: DuffelOrderConfirmation,
        offer: DuffelOffer,
        params: DuffelSearchParams,
        tripID: UUID
    ) async {
        let route = "\(params.origin) → \(params.destination)"
        let airline = offer.owner?.name ?? "Flight"

        // 1. Itinerary item (display) — routed through the atomic TravelStore.
        let item = ItineraryItem(
            title: "\(airline) · \(route)",
            type: .flight,
            startDate: params.departDate,
            endDate: params.returnDate,
            location: params.origin,
            notes: "Duffel order: \(order.orderId)",
            confirmationNumber: order.bookingReference,
            bookingProvider: airline
        )
        if !TravelStore.appendItem(item, toTripID: tripID) {
            // No matching trip — fall back to creating a dedicated one so the
            // booking is never dropped.
            let trip = Trip(id: tripID, name: route, destination: params.destination,
                            startDate: params.departDate,
                            endDate: params.returnDate ?? params.departDate,
                            items: [item])
            TravelStore.upsertTrip(trip)
        }

        // 2. Boarding-pass wallet item carrying the Duffel order id for rebooking.
        let wallet = WalletItem(
            tripId: tripID,
            itemType: .boardingPass,
            title: "\(airline) \(route)",
            confirmationNumber: order.bookingReference,
            date: params.departDate,
            rawData: [
                "duffel_order_id": order.orderId,
                "booking_reference": order.bookingReference,
                "airline": airline,
                "departure_airport": params.origin,
                "arrival_airport": params.destination,
            ]
        )
        try? await SupabaseService.shared.upsertWalletItem(wallet)
    }
}
