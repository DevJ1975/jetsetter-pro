// File: Core/Services/DepartureOptimizerService.swift
//
// Tells the user the optimal time to leave for the airport. Fuses:
//   • Live MapKit driving ETA with current traffic (MKDirections)
//   • TSA security wait estimate (TSAWaitEstimator)
//   • Boarding-time buffer (typically 30 min before departure)
//   • Optional walking-to-curb / parking buffer
//
// Returns a single recommendation with all the components so the UI can show
// "Leave by 5:42 PM — here's why" with the breakdown.

import Foundation
import MapKit
import CoreLocation

// MARK: - Result

struct DepartureRecommendation {
    let leaveAt: Date
    let driveMinutes: Int
    let tsaWait: TSAWaitEstimate
    let boardingBufferMinutes: Int
    let curbBufferMinutes: Int
    let arriveAtAirportAt: Date
    let arriveAtGateAt: Date
    let scheduledDeparture: Date
    /// How urgent the situation is — drives UI color and audio.
    let urgency: Urgency

    enum Urgency {
        case relaxed         // > 60 min runway
        case onTime          // 30-60 min runway
        case tight           // 10-30 min runway
        case critical        // < 10 min runway or already late

        var label: String {
            switch self {
            case .relaxed:  return "Plenty of time"
            case .onTime:   return "On schedule"
            case .tight:    return "Cutting it close"
            case .critical: return "Leave now!"
            }
        }

        var colorHex: String {
            switch self {
            case .relaxed:  return "#1DB97D"
            case .onTime:   return "#3B9EF0"
            case .tight:    return "#E8A020"
            case .critical: return "#E84040"
            }
        }
    }

    /// Minutes until the user must leave.
    var minutesUntilLeave: Int {
        Int(leaveAt.timeIntervalSinceNow / 60)
    }
}

// MARK: - Service

@MainActor
final class DepartureOptimizerService {

    static let shared = DepartureOptimizerService()
    private init() {}

    /// Computes the optimal leave time given current location, destination
    /// airport, scheduled departure, and the user's lane preference.
    ///
    /// `curbBufferMinutes` covers walk-from-parking, drop-off chaos, etc.
    /// `boardingBufferMinutes` is how far before scheduled departure the user
    /// wants to be at the gate (default 30 min — boarding closes 15 min before).
    func recommend(
        currentLocation: CLLocationCoordinate2D,
        airportIATA: String,
        scheduledDeparture: Date,
        lane: SecurityLane = .standard,
        boardingBufferMinutes: Int = 30,
        curbBufferMinutes: Int = 10
    ) async -> DepartureRecommendation? {
        guard let airportCoord = AirportCoordinates.coordinate(for: airportIATA) else { return nil }

        // 1. Live drive time with traffic
        let driveSeconds = await driveTime(
            from: currentLocation,
            to: airportCoord
        ) ?? 30 * 60  // fall back to 30 min if MapKit fails
        let driveMinutes = Int(driveSeconds / 60)

        // 2. Estimate TSA wait at predicted arrival time (drive ends at arriveAtAirport)
        let arriveAtAirportAt = Date().addingTimeInterval(driveSeconds)
        let tsaWait = TSAWaitEstimator.estimate(
            airportIATA: airportIATA,
            arrivingAt: arriveAtAirportAt,
            lane: lane
        )

        // 3. Walk through total buffer
        // Plane should be at gate by:
        let arriveAtGateAt = scheduledDeparture.addingTimeInterval(
            -Double(boardingBufferMinutes) * 60
        )
        // To be at gate by then, the user must clear security by arriveAtGateAt.
        // So they need to enter the security line by:
        let enterSecurityBy = arriveAtGateAt.addingTimeInterval(
            -Double(tsaWait.midpoint) * 60
        )
        // And reach the curb by:
        let reachCurbBy = enterSecurityBy.addingTimeInterval(
            -Double(curbBufferMinutes) * 60
        )
        // So they need to leave at:
        let leaveAt = reachCurbBy.addingTimeInterval(-driveSeconds)

        // 4. Urgency
        let minutesRunway = Int(leaveAt.timeIntervalSinceNow / 60)
        let urgency: DepartureRecommendation.Urgency
        switch minutesRunway {
        case ..<10:       urgency = .critical
        case 10..<30:     urgency = .tight
        case 30..<60:     urgency = .onTime
        default:          urgency = .relaxed
        }

        return DepartureRecommendation(
            leaveAt: leaveAt,
            driveMinutes: driveMinutes,
            tsaWait: tsaWait,
            boardingBufferMinutes: boardingBufferMinutes,
            curbBufferMinutes: curbBufferMinutes,
            arriveAtAirportAt: arriveAtAirportAt,
            arriveAtGateAt: arriveAtGateAt,
            scheduledDeparture: scheduledDeparture,
            urgency: urgency
        )
    }

    // MARK: - MapKit drive time

    private func driveTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.departureDate = Date()    // tells MapKit to factor in live traffic

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }
}

// MARK: - Rideshare helpers

enum RideshareDeepLink {

    /// Builds an Uber deep link that pre-fills pickup and drop-off.
    static func uber(pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D, dropoffNickname: String) -> URL? {
        var components = URLComponents(string: "uber://")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "setPickup"),
            URLQueryItem(name: "pickup", value: "my_location"),
            URLQueryItem(name: "dropoff[latitude]", value: "\(dropoff.latitude)"),
            URLQueryItem(name: "dropoff[longitude]", value: "\(dropoff.longitude)"),
            URLQueryItem(name: "dropoff[nickname]", value: dropoffNickname),
            URLQueryItem(name: "client_id", value: "JetSetter")
        ]
        _ = pickup  // pickup is implicit ("my_location")
        return components?.url
    }

    /// Builds a Lyft deep link.
    static func lyft(pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents(string: "lyft://ridetype")
        components?.queryItems = [
            URLQueryItem(name: "id", value: "lyft"),
            URLQueryItem(name: "pickup[latitude]", value: "\(pickup.latitude)"),
            URLQueryItem(name: "pickup[longitude]", value: "\(pickup.longitude)"),
            URLQueryItem(name: "destination[latitude]", value: "\(dropoff.latitude)"),
            URLQueryItem(name: "destination[longitude]", value: "\(dropoff.longitude)"),
            URLQueryItem(name: "partner", value: "JetSetter")
        ]
        return components?.url
    }
}
