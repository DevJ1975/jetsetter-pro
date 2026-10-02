// File: Core/Services/DepartureOptimizerService.swift
//
// Tells the user the optimal time to leave for the airport. Fuses:
//   • Live MapKit driving ETA with current traffic (MKDirections)
//   • TSA security wait estimate (TSAWaitEstimator)
//   • Boarding-time buffer (typically 30 min before departure)
//   • Optional walking-to-curb / parking buffer
//   • The airline's bag-drop cutoff when the traveler is checking a bag
//
// Returns a single recommendation with all the components so the UI can show
// "Leave by 5:42 PM — here's why" with the breakdown. The arithmetic lives in
// `LeaveByPlanner` (pure, tested); this service only gathers live inputs.

import Foundation
import MapKit
import CoreLocation

// MARK: - Result

struct DepartureRecommendation {
    let leaveAt: Date
    let driveMinutes: Int
    /// False when MapKit had no ETA and `driveMinutes` is the pessimistic
    /// fallback. Screens must label that as an estimate, never "live traffic".
    let isDriveTimeLive: Bool
    let tsaWait: TSAWaitEstimate
    let boardingBufferMinutes: Int
    let curbBufferMinutes: Int
    let arriveAtAirportAt: Date
    let arriveAtGateAt: Date
    let scheduledDeparture: Date
    /// Whether the international buffers were used (origin and destination
    /// are known airports in different countries).
    let isInternational: Bool
    /// Last moment to hand over a checked bag; nil when no bag is being checked.
    let bagDropDeadline: Date?
    /// Which deadline set `leaveAt`: security-plus-boarding or bag drop.
    let bindingConstraint: LeaveByPlanner.Constraint
    /// How urgent the situation is — drives UI color and audio.
    let urgency: Urgency
    /// Live departure-airport weather rolled into the estimate (IOS_PARITY_NOTES.md §7.6).
    var weather: DepartureWeather? = nil

    enum Urgency {
        case relaxed         // > 60 min runway
        case onTime          // 30-60 min runway
        case tight           // 10-30 min runway
        case critical        // 0-10 min runway
        case missed          // leave-by time is already in the past — window likely gone

        var label: String {
            switch self {
            case .relaxed:  return "Plenty of time"
            case .onTime:   return "On schedule"
            case .tight:    return "Cutting it close"
            case .critical: return "Leave now!"
            case .missed:   return "Departure window passed"
            }
        }

        var colorHex: String {
            switch self {
            case .relaxed:  return "#1DB97D"
            case .onTime:   return "#3B9EF0"
            case .tight:    return "#E8A020"
            case .critical: return "#E84040"
            case .missed:   return "#B71C1C"   // deeper red — distinct from "leave now"
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
    ///
    /// The default buffers are tuned for domestic US travel. International
    /// departures typically require earlier boarding plus document / immigration
    /// checks and longer terminal walks, so pass `destinationIATA` and the
    /// service works out whether the flight crosses a border (via
    /// `LeaveByPlanner.isInternational`) and widens the buffers unless they were
    /// explicitly overridden. An unknown airport falls back to domestic buffers.
    ///
    /// `checkingBag` adds the airline's bag-drop cutoff; the earlier of the
    /// security path and the bag-drop path sets the leave time. Use
    /// `hasBagToDrop(flightNumber:)` for a sensible default.
    func recommend(
        currentLocation: CLLocationCoordinate2D,
        airportIATA: String,
        destinationIATA: String? = nil,
        scheduledDeparture: Date,
        lane: SecurityLane = .standard,
        checkingBag: Bool = false,
        boardingBufferMinutes: Int? = nil,
        curbBufferMinutes: Int? = nil,
        flightNumber: String? = nil
    ) async -> DepartureRecommendation? {
        guard let airportCoord = AirportCoordinates.coordinate(for: airportIATA) else { return nil }

        let isInternational = LeaveByPlanner.isInternational(
            originIATA: airportIATA,
            destinationIATA: destinationIATA
        )

        // 1. Live drive time with traffic. Nil means MapKit couldn't say
        //    (offline, captive portal, routing error); the planner then uses a
        //    pessimistic estimate and marks it as not live. This used to fall
        //    back to a silent 30 minutes that the UI labelled "live traffic".
        let liveDriveSeconds = await driveTime(from: currentLocation, to: airportCoord)
        let driveSeconds = LeaveByPlanner.effectiveDriveSeconds(live: liveDriveSeconds)

        // 2. Estimate TSA wait at predicted arrival time (drive ends at arriveAtAirport)
        let arriveAtAirportAt = Date().addingTimeInterval(driveSeconds)
        let tsaWait = TSAWaitEstimator.estimate(
            airportIATA: airportIATA,
            arrivingAt: arriveAtAirportAt,
            lane: lane
        )

        // 3. Work backwards from departure: security path vs bag-drop path,
        //    whichever needs the traveler out of the door first.
        let plan = LeaveByPlanner.plan(
            scheduledDeparture: scheduledDeparture,
            liveDriveSeconds: liveDriveSeconds,
            tsaWaitMinutes: tsaWait.midpoint,
            isInternational: isInternational,
            checkingBag: checkingBag,
            boardingBufferMinutes: boardingBufferMinutes,
            curbBufferMinutes: curbBufferMinutes
        )
        let leaveAt = plan.leaveAt

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
        case ..<0:        urgency = .missed     // leave-by already passed — flag, don't quote a stale clock time
        case 0..<10:      urgency = .critical
        case 10..<30:     urgency = .tight
        case 30..<60:     urgency = .onTime
        default:          urgency = .relaxed
        }

        // Publish the live briefing so the app quotes the same numbers (§7.3).
        // If the leave-by time is already in the past, quoting a stale clock time
        // (e.g. "2:15 PM" at 4 PM) would mislead the app — surface the passed state instead.
        // Only a LIVE drive time is published: Siri reads it back as "about a
        // 34-minute drive", and a fallback guess must not be quoted that way.
        if plan.isDriveTimeLive {
            let leaveFmt = DateFormatter()
            leaveFmt.dateStyle = .none
            leaveFmt.timeStyle = .short   // follows the user's 12/24-hour setting
            let leaveByText = minutesRunway < 0 ? "now (window passed)" : leaveFmt.string(from: leaveAt)
            DepartureBriefing.cachedLive = DepartureBriefing(
                leaveBy: leaveByText,
                driveMinutes: plan.driveMinutes,
                tsaMinutes: tsaWait.midpoint,
                weatherLabel: weather?.conditionLabel ?? "Weather unavailable",
                temperatureF: weather?.temperatureF,
                flightNumber: flightNumber ?? "your flight",
                originIATA: airportIATA,
                computedAt: Date()
            )
        }

        return DepartureRecommendation(
            leaveAt: leaveAt,
            driveMinutes: plan.driveMinutes,
            isDriveTimeLive: plan.isDriveTimeLive,
            tsaWait: tsaWait,
            boardingBufferMinutes: plan.boardingBufferMinutes,
            curbBufferMinutes: plan.curbBufferMinutes,
            arriveAtAirportAt: arriveAtAirportAt,
            arriveAtGateAt: plan.arriveAtGateAt,
            scheduledDeparture: scheduledDeparture,
            isInternational: plan.isInternational,
            bagDropDeadline: plan.bagDropDeadline,
            bindingConstraint: plan.bindingConstraint,
            urgency: urgency,
            weather: weather
        )
    }

    // MARK: - Checked bags

    /// True when the luggage tracker holds a bag for `flightNumber` that hasn't
    /// been handed over yet. That is the default for "checking a bag"; the
    /// optimizer screen lets the traveler override it either way.
    func hasBagToDrop(flightNumber: String?) -> Bool {
        let bags = BagStore.load().map { bag in
            (flightNumber: bag.flightNumber, isHandedOver: bag.status != .unknown)
        }
        return LeaveByPlanner.hasBagToDrop(flightNumber: flightNumber, bags: bags)
    }

    // MARK: - MapKit drive time

    private func driveTime(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> TimeInterval? {
        await driveEstimate(from: origin, to: destination)?.travelTime
    }

    /// Live-traffic driving estimate between two points. Shared with Ground
    /// Transport so every drive time in the app is computed the same way.
    func driveEstimate(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> (travelTime: TimeInterval, distance: CLLocationDistance)? {
        let request = MKDirections.Request()
        request.source = Self.mapItem(for: origin)
        request.destination = Self.mapItem(for: destination)
        request.transportType = .automobile
        request.departureDate = Date()    // tells MapKit to factor in live traffic

        do {
            let response = try await MKDirections(request: request).calculateETA()
            return (response.expectedTravelTime, response.distance)
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
