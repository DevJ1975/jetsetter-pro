// File: Core/Services/Learning/TravelSignal.swift
//
// One observed datapoint about how the traveler actually behaves. The learning
// layer aggregates these (plus the history already on device) into a TravelProfile.
// Signals are recorded ONLY with the user's consent (see TravelProfileStore +
// UserPreferences.learningEnabled) and are fully wiped by "Clear Local Data".

import Foundation

nonisolated struct TravelSignal: Identifiable, Codable, Equatable {

    /// The kind of behavior observed. The raw values are persisted, so don't rename.
    enum Kind: String, Codable {
        case seatChosen          // user picked/was assigned a seat ("14A")
        case flightFlown         // a flown/booked flight (airline, route)
        case receiptScanned      // a scanned receipt (merchant, amount, category)
        case expenseLogged       // a manually logged expense
        case loyaltyAdded        // a loyalty program was added (airline/hotel/car brand)
        case tripCompleted       // a trip ended (destination, booking lead)
        case placeVisited        // a city/place derived from trips/receipts
        case suggestionFeedback  // user accepted/dismissed a proactive suggestion
    }

    let id: UUID
    let kind: Kind
    /// The primary learned value — a seat ("14A"), airline code ("AA"), merchant,
    /// city, or suggestion key, depending on `kind`.
    let value: String
    /// Structured extras keyed by a small, stable vocabulary, e.g.
    /// "airline", "cabinHint", "category", "amount", "currency", "city",
    /// "leadDays", "brandKind" (airline|hotel|car), "accepted" (true|false).
    var attributes: [String: String]
    let timestamp: Date
    /// Where the signal originated (a feature name) — useful for debugging/audit.
    let source: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        value: String,
        attributes: [String: String] = [:],
        timestamp: Date = Date(),
        source: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.attributes = attributes
        self.timestamp = timestamp
        self.source = source
    }
}
