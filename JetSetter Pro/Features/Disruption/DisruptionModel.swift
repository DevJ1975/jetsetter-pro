// File: Features/Disruption/DisruptionModel.swift
// Data models for the Trip Disruption AI feature.
//
// Required SQL (run once in Supabase SQL editor):
//
//   CREATE TABLE disruption_events (
//     id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//     user_id               uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
//     trip_id               uuid NOT NULL,
//     event_type            text NOT NULL,
//     original_flight       jsonb NOT NULL,
//     alternatives          jsonb DEFAULT '[]'::jsonb,
//     response_actions      jsonb DEFAULT '{}'::jsonb,
//     resolved              boolean DEFAULT false,
//     rebooking_url         text,
//     hotel_contact         text,
//     uber_deep_link        text,
//     insurance_document_id uuid,
//     created_at            timestamptz DEFAULT now()
//   );
//   ALTER TABLE disruption_events ENABLE ROW LEVEL SECURITY;
//   CREATE POLICY "user_disruptions" ON disruption_events
//     FOR ALL USING (auth.uid() = user_id);

import Foundation

// MARK: - DisruptionType

/// The category of flight disruption detected by the monitor service.
enum DisruptionType: String, Codable, CaseIterable {
    case cancellation     = "cancellation"
    case majorDelay       = "major_delay"       // departure delay > 45 min
    case gateChange       = "gate_change"
    case missedConnection = "missed_connection"  // layover < 60 min remaining

    var displayName: String {
        switch self {
        case .cancellation:     return "Flight Cancelled"
        case .majorDelay:       return "Major Delay"
        case .gateChange:       return "Gate Changed"
        case .missedConnection: return "Missed Connection Risk"
        }
    }

    var systemImage: String {
        switch self {
        case .cancellation:     return "xmark.circle.fill"
        case .majorDelay:       return "clock.badge.exclamationmark.fill"
        case .gateChange:       return "arrow.triangle.2.circlepath"
        case .missedConnection: return "exclamationmark.triangle.fill"
        }
    }

    /// Hex color matching JetsetterTheme status palette.
    var colorHex: String {
        switch self {
        case .cancellation:     return "#E84040"
        case .majorDelay:       return "#E8A020"
        case .gateChange:       return "#3B9EF0"
        case .missedConnection: return "#E84040"
        }
    }
}

// MARK: - ResponseActions

/// Tracks which of the 5 automated response steps have completed.
/// Stored as a jsonb column so the UI can show granular action status badges.
struct ResponseActions: Codable, Equatable {
    var alternativesFound: Bool = false   // Amadeus alternatives search done
    var rebookingChecked: Bool  = false   // Duffel eligibility confirmed
    var hotelNotified: Bool     = false   // Hotel mailto link generated
    var uberRerouteReady: Bool  = false   // Uber deep link built
    var insuranceSurfaced: Bool = false   // Insurance WalletItem located

    enum CodingKeys: String, CodingKey {
        case alternativesFound  = "alternatives_found"
        case rebookingChecked   = "rebooking_checked"
        case hotelNotified      = "hotel_notified"
        case uberRerouteReady   = "uber_reroute_ready"
        case insuranceSurfaced  = "insurance_surfaced"
    }

    var isFullyHandled: Bool {
        alternativesFound && rebookingChecked && hotelNotified
            && uberRerouteReady && insuranceSurfaced
    }
}

// MARK: - FlightSnapshot

/// Immutable snapshot of a flight's state at the moment disruption is detected.
/// Self-contained so the event log stays correct even after live flight data changes.
struct FlightSnapshot: Codable, Equatable {
    let flightNumber: String
    let airline: String
    let origin: String           // IATA code, e.g. "SFO"
    let destination: String      // IATA code, e.g. "NRT"
    let scheduledDeparture: Date
    let originalGate: String?
    let status: String
    let delayMinutes: Int?       // nil for cancellations / gate changes

    enum CodingKeys: String, CodingKey {
        case flightNumber       = "flight_number"
        case airline, origin, destination, status
        case scheduledDeparture = "scheduled_departure"
        case originalGate       = "original_gate"
        case delayMinutes       = "delay_minutes"
    }
}

// MARK: - AlternativeFlight

/// One alternative flight returned by Amadeus Flight Offers Search API.
/// Up to 3 stored per disruption event, sorted by earliest departure.
struct AlternativeFlight: Identifiable, Codable, Equatable {
    let id: UUID
    let flightNumber: String
    let airline: String
    let origin: String
    let destination: String
    let departure: Date
    let arrival: Date
    let durationMinutes: Int
    let price: Double
    let currency: String
    let availableSeats: Int
    let cabinClass: String
    let bookingToken: String?  // Amadeus offer ID for deep-link booking

    enum CodingKeys: String, CodingKey {
        case id, airline, origin, destination, departure, arrival, currency, price
        case flightNumber    = "flight_number"
        case durationMinutes = "duration_minutes"
        case availableSeats  = "available_seats"
        case cabinClass      = "cabin_class"
        case bookingToken    = "booking_token"
    }

    var durationFormatted: String {
        "\(durationMinutes / 60)h \(durationMinutes % 60)m"
    }

    var priceFormatted: String {
        String(format: "%@ %.0f", currency, price)
    }
}

// MARK: - DisruptionEvent

/// Top-level record stored in Supabase `disruption_events`.
/// Created when a disruption is detected; updated as automated responses complete.
struct DisruptionEvent: Identifiable, Codable {
    let id: UUID
    var userId: String
    var tripId: UUID
    var eventType: DisruptionType
    var originalFlight: FlightSnapshot
    var alternatives: [AlternativeFlight]
    var responseActions: ResponseActions
    var resolved: Bool
    var rebookingUrl: String?          // Deep link for user's chosen alternative
    var hotelContact: String?          // Email used in hotel late-arrival mailto
    var uberDeepLink: String?          // Pre-filled Uber URL to updated gate/terminal
    var insuranceDocumentId: UUID?     // WalletItem.id of surfaced insurance doc
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, alternatives, resolved
        case userId              = "user_id"
        case tripId              = "trip_id"
        case eventType           = "event_type"
        case originalFlight      = "original_flight"
        case responseActions     = "response_actions"
        case rebookingUrl        = "rebooking_url"
        case hotelContact        = "hotel_contact"
        case uberDeepLink        = "uber_deep_link"
        case insuranceDocumentId = "insurance_document_id"
        case createdAt           = "created_at"
    }

    /// Lowest-price alternative — preferred for the one-tap rebook CTA.
    var bestAlternative: AlternativeFlight? {
        alternatives.min { $0.price < $1.price }
    }

    /// Earliest departure among alternatives.
    var earliestAlternative: AlternativeFlight? {
        alternatives.min { $0.departure < $1.departure }
    }
}

// MARK: - Sample Data (Previews)

extension DisruptionEvent {
    static let sample = DisruptionEvent(
        id: UUID(),
        userId: "preview-user",
        tripId: UUID(),
        eventType: .majorDelay,
        originalFlight: FlightSnapshot(
            flightNumber: "UA837",
            airline: "United Airlines",
            origin: "SFO",
            destination: "NRT",
            scheduledDeparture: Date().addingTimeInterval(3600),
            originalGate: "B22",
            status: "Delayed",
            delayMinutes: 87
        ),
        alternatives: [
            AlternativeFlight(
                id: UUID(),
                flightNumber: "NH108",
                airline: "ANA",
                origin: "SFO",
                destination: "NRT",
                departure: Date().addingTimeInterval(5400),
                arrival: Date().addingTimeInterval(5400 + 36_000),
                durationMinutes: 600,
                price: 1240,
                currency: "USD",
                availableSeats: 4,
                cabinClass: "Economy",
                bookingToken: "OFFER_ABC123"
            ),
            AlternativeFlight(
                id: UUID(),
                flightNumber: "JL001",
                airline: "Japan Airlines",
                origin: "SFO",
                destination: "NRT",
                departure: Date().addingTimeInterval(9000),
                arrival: Date().addingTimeInterval(9000 + 37_800),
                durationMinutes: 630,
                price: 1185,
                currency: "USD",
                availableSeats: 7,
                cabinClass: "Economy",
                bookingToken: "OFFER_DEF456"
            )
        ],
        responseActions: ResponseActions(
            alternativesFound: true,
            rebookingChecked: true,
            hotelNotified: true,
            uberRerouteReady: true,
            insuranceSurfaced: false
        ),
        resolved: false,
        rebookingUrl: nil,
        hotelContact: "reservations@parkhyatt.com",
        uberDeepLink: "uber://?action=setPickup&pickup=my_location",
        insuranceDocumentId: nil,
        createdAt: Date()
    )
}
