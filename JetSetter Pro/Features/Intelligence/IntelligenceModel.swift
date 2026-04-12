// File: Features/Intelligence/IntelligenceModel.swift
// Models for the Proactive Travel Intelligence feature (Feature 6).
//
// Supabase table:
//   CREATE TABLE intelligence_events (
//     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//     user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
//     trip_id uuid NOT NULL,
//     trigger_type text NOT NULL,
//     trigger_data jsonb DEFAULT '{}'::jsonb,
//     action_taken text,
//     fired_at timestamptz DEFAULT now()
//   );
//   ALTER TABLE intelligence_events ENABLE ROW LEVEL SECURITY;
//   CREATE POLICY "user_intelligence" ON intelligence_events
//     FOR ALL USING (auth.uid() = user_id);

import Foundation

// MARK: - TriggerType

/// Every proactive signal the intelligence engine monitors.
enum TriggerType: String, Codable, CaseIterable {
    case leaveNow           = "leave_now"
    case weatherChange      = "weather_change"
    case checkInOpen        = "check_in_open"
    case gateChanged        = "gate_changed"
    case hotelCheckInReady  = "hotel_check_in_ready"
    case flightDelayed      = "flight_delayed"
    case flightCancelled    = "flight_cancelled"

    var displayName: String {
        switch self {
        case .leaveNow:          return "Leave Now"
        case .weatherChange:     return "Weather Change"
        case .checkInOpen:       return "Check-In Open"
        case .gateChanged:       return "Gate Changed"
        case .hotelCheckInReady: return "Hotel Check-In Ready"
        case .flightDelayed:     return "Flight Delayed"
        case .flightCancelled:   return "Flight Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .leaveNow:          return "car.fill"
        case .weatherChange:     return "cloud.bolt.fill"
        case .checkInOpen:       return "airplane.departure"
        case .gateChanged:       return "arrow.triangle.2.circlepath"
        case .hotelCheckInReady: return "bed.double.fill"
        case .flightDelayed:     return "clock.badge.exclamationmark.fill"
        case .flightCancelled:   return "xmark.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .leaveNow:          return "#3B9EF0"
        case .weatherChange:     return "#7B3FBF"
        case .checkInOpen:       return "#1DB97D"
        case .gateChanged:       return "#E8A020"
        case .hotelCheckInReady: return "#0A7A5E"
        case .flightDelayed:     return "#E8A020"
        case .flightCancelled:   return "#E84040"
        }
    }
}

// MARK: - ProactiveTrigger

/// Defines the condition, timing, notification content, and in-app action for one signal.
struct ProactiveTrigger: Identifiable {
    let id: UUID
    let type: TriggerType
    let title: String
    let body: String
    let actionLabel: String?      // CTA label for the in-app card button
    let actionURL: String?        // Deep link or URL for the action
    let firedAt: Date
    var isDismissed: Bool = false
}

// MARK: - IntelligenceEvent

/// Logged to Supabase when a trigger fires or the user acts on it.
struct IntelligenceEvent: Identifiable, Codable {
    let id: UUID
    var userId: String
    var tripId: UUID
    var triggerType: TriggerType
    var triggerData: [String: String]  // Contextual data (flight number, gate, etc.)
    var actionTaken: String?           // "dismissed", "acted", "ignored"
    var firedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case tripId      = "trip_id"
        case triggerType = "trigger_type"
        case triggerData = "trigger_data"
        case actionTaken = "action_taken"
        case firedAt     = "fired_at"
    }
}

// MARK: - LeaveNow Calculation

/// Encapsulates the "leave now" ETA calculation inputs.
struct LeaveNowContext {
    let currentLocation: (lat: Double, lon: Double)
    let airportIATA: String
    let flightDeparture: Date
    let estimatedDriveMinutes: Int    // From MapKit ETA
    let checkInMinutes: Int           // Airline-specific (60–120 min domestic, 120–180 international)
    let securityMinutes: Int          // Estimated security wait (TSA Pre✓: 10, standard: 25)

    /// The latest time to leave to make the flight.
    var latestDepartureTime: Date {
        let totalBufferMinutes = estimatedDriveMinutes + checkInMinutes + securityMinutes
        return flightDeparture.addingTimeInterval(-Double(totalBufferMinutes) * 60)
    }

    var minutesUntilLeave: Int {
        Int(latestDepartureTime.timeIntervalSinceNow / 60)
    }

    var isUrgent: Bool { minutesUntilLeave <= 15 }
}
