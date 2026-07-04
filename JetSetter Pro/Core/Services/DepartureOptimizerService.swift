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
    /// Live departure-airport weather rolled into the estimate (IOS_PARITY_NOTES.md §7.6).
    var weather: DepartureWeather? = nil

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

// MARK: - Departure weather (LIVE CONDITIONS)

/// Weather factor shown in the LIVE CONDITIONS card next to traffic + TSA.
struct DepartureWeather {
    let conditionLabel: String   // e.g. "Clear skies"
    let temperatureF: Int        // e.g. 74
    let systemIcon: String
    let risk: Risk

    enum Risk {
        case clear, caution, high

        var label: String {
            switch self {
            case .clear:   return "Clear"
            case .caution: return "Caution"
            case .high:    return "High risk"
            }
        }

        var colorHex: String {
            switch self {
            case .clear:   return "#1DB97D"
            case .caution: return "#E8A020"
            case .high:    return "#E84040"
            }
        }
    }

    /// Maps a WMO weather code to a delay-risk band for the departure window.
    static func risk(forWMOCode code: Int) -> Risk {
        switch code {
        case 0, 1:                                  return .clear        // clear / mainly clear
        case 2, 3, 45, 48, 51, 53, 61, 71, 80:      return .caution      // cloud, fog, light precip
        default:                                    return .high         // heavy rain, snow, storms
        }
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

        // 3b. Live departure-airport weather → delay-risk factor (§7.6).
        var weather: DepartureWeather? = nil
        if let w = try? await WeatherService.shared.fetch(
            latitude: airportCoord.latitude, longitude: airportCoord.longitude
        ) {
            weather = DepartureWeather(
                conditionLabel: w.conditionDescription,
                temperatureF: Int(w.temperatureFahrenheit.rounded()),
                systemIcon: w.systemIcon,
                risk: DepartureWeather.risk(forWMOCode: w.weatherCode)
            )
        }

        // 4. Urgency
        let minutesRunway = Int(leaveAt.timeIntervalSinceNow / 60)
        let urgency: DepartureRecommendation.Urgency
        switch minutesRunway {
        case ..<10:       urgency = .critical
        case 10..<30:     urgency = .tight
        case 30..<60:     urgency = .onTime
        default:          urgency = .relaxed
        }

        // Publish the live briefing so IRIS quotes the same numbers (§7.3).
        let leaveFmt = DateFormatter()
        leaveFmt.dateFormat = "h:mm a"
        DepartureBriefing.cachedLive = DepartureBriefing(
            leaveBy: leaveFmt.string(from: leaveAt),
            driveMinutes: driveMinutes,
            tsaMinutes: tsaWait.midpoint,
            weatherLabel: weather?.conditionLabel ?? DepartureBriefing.personaDefault.weatherLabel,
            temperatureF: weather?.temperatureF ?? DepartureBriefing.personaDefault.temperatureF,
            flightNumber: DepartureBriefing.personaDefault.flightNumber,
            originIATA: airportIATA
        )

        return DepartureRecommendation(
            leaveAt: leaveAt,
            driveMinutes: driveMinutes,
            tsaWait: tsaWait,
            boardingBufferMinutes: boardingBufferMinutes,
            curbBufferMinutes: curbBufferMinutes,
            arriveAtAirportAt: arriveAtAirportAt,
            arriveAtGateAt: arriveAtGateAt,
            scheduledDeparture: scheduledDeparture,
            urgency: urgency,
            weather: weather
        )
    }

    // MARK: - MapKit drive time

    private func driveTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = Self.mapItem(for: origin)
        request.destination = Self.mapItem(for: destination)
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

    /// Builds an `MKMapItem` for a coordinate, using the iOS 26 initializer when
    /// available and the pre-26 placemark initializer otherwise.
    private static func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
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
