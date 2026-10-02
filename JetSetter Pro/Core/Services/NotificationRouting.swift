// File: Core/Services/NotificationRouting.swift
//
// What a notification tap or action button does, decided as plain data. The
// delegate (`NotificationManager`) reads the category, action and userInfo,
// asks `route(...)` here, and applies the answer: in-app navigation goes to
// `AppRouter.handle(_:)`, which survives a cold launch because the router
// holds it until the destination view consumes it. Notification taps used to
// post NotificationCenter names that only a mounted Home view heard, so a tap
// that launched the app went nowhere.
//
// Categories: the backend's pushes use FLIGHT_ALERT and DISRUPTION_ALERT, so
// local alerts reuse those names and get the same buttons. LEAVE_BY_ALERT adds
// "Snooze 10 min" to the leave-for-the-airport reminder. Push payloads carry
// `deepLink`, `flightNumber` and `alertType`; a valid `deepLink` decides where
// a tap goes, because the server knows which screen it meant.
//
// Pure and `nonisolated` except `rideURL`, which uses the Ground Transport
// ride links (main-actor types).

import Foundation
import CoreLocation
import UserNotifications

// MARK: - Route

/// Where a notification response should take the traveler.
nonisolated enum NotificationRoute: Equatable, Sendable {
    case deepLink(JetSetterDeepLink)
    case checkIn
    case disruption
    case expenses
    case boardingPass(flightNumber: String?, departure: Date?)
    /// "Get a ride": to this airport when known, else the Ground Transport screen.
    case ride(airportIATA: String?)
    case snooze(minutes: Int)
    case lovedOnes(recipients: [String], body: String)
    case none
}

// MARK: - Routing

nonisolated enum NotificationRouting {

    nonisolated enum Category {
        static let flightAlert      = "FLIGHT_ALERT"
        static let disruptionAlert  = "DISRUPTION_ALERT"
        static let leaveByAlert     = "LEAVE_BY_ALERT"
        static let checkInOpen      = "CHECK_IN_OPEN"
        static let expenseReminder  = "EXPENSE_REMINDER"
        static let lovedOnesTakeoff = "LOVED_ONES_TAKEOFF"
        static let lovedOnesLanding = "LOVED_ONES_LANDING"
    }

    nonisolated enum Action {
        static let viewBoardingPass = "VIEW_BOARDING_PASS"
        static let getRide          = "GET_RIDE"
        static let snooze           = "SNOOZE_10_MIN"
    }

    /// userInfo keys. The first three are the backend's push keys.
    nonisolated enum Key {
        static let deepLink     = "deepLink"
        static let flightNumber = "flightNumber"
        static let alertType    = "alertType"
        /// Older local alerts (disruptions, the demo) use snake_case.
        static let legacyFlightNumber = "flight_number"
        /// Departure (or boarding) time, seconds since 1970. Pass matching
        /// allows a day either way, so either identifies the flight.
        static let departure    = "departure"
        /// IATA code of the airport a "Get a ride" should drop off at.
        static let rideAirport  = "rideAirport"
        static let recipients   = "recipients"
        static let body         = "body"
    }

    static let snoozeMinutes = 10

    // MARK: Categories

    /// Every category with action buttons. Registered once at launch, before
    /// any notification can be shown (`setNotificationCategories` replaces the
    /// whole set).
    static func categories() -> Set<UNNotificationCategory> {
        // Both open the app: the pass is shown in-app and a ride link is
        // opened from the app, neither of which can run in the background.
        let viewPass = UNNotificationAction(
            identifier: Action.viewBoardingPass, title: "View boarding pass",
            options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "qrcode")
        )
        let ride = UNNotificationAction(
            identifier: Action.getRide, title: "Get a ride",
            options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "car.fill")
        )
        // Snooze reschedules in the background without opening the app.
        let snooze = UNNotificationAction(
            identifier: Action.snooze, title: "Snooze \(snoozeMinutes) min",
            options: [], icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath")
        )
        return [
            UNNotificationCategory(identifier: Category.flightAlert, actions: [viewPass, ride],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.disruptionAlert, actions: [viewPass, ride],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.leaveByAlert, actions: [viewPass, ride, snooze],
                                   intentIdentifiers: [], options: [])
        ]
    }

    // MARK: Responses

    /// Where a response goes. `action` is the response's action identifier
    /// (`UNNotificationDefaultActionIdentifier` for a plain tap).
    static func route(
        category: String,
        action: String,
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NotificationRoute {
        let flightNumber = Self.flightNumber(in: userInfo)
        let departure = Self.departure(in: userInfo)

        // Buttons first: they say exactly what the traveler asked for.
        switch action {
        case Action.viewBoardingPass:
            return .boardingPass(flightNumber: flightNumber, departure: departure)
        case Action.getRide:
            return .ride(airportIATA: userInfo[Key.rideAirport] as? String)
        case Action.snooze:
            return .snooze(minutes: snoozeMinutes)
        case UNNotificationDismissActionIdentifier:
            return .none
        default:
            break
        }

        // A plain tap. The server's deep link names the exact screen.
        if let raw = userInfo[Key.deepLink] as? String,
           let url = URL(string: raw),
           let link = JetSetterDeepLink(url: url) {
            return .deepLink(link)
        }

        switch category {
        case Category.disruptionAlert:
            return .disruption
        case Category.checkInOpen:
            return .checkIn
        case Category.expenseReminder:
            return .expenses
        case Category.lovedOnesTakeoff, Category.lovedOnesLanding:
            return .lovedOnes(
                recipients: (userInfo[Key.recipients] as? [String]) ?? [],
                body: (userInfo[Key.body] as? String) ?? ""
            )
        case Category.flightAlert, Category.leaveByAlert:
            // Boarding wants the pass in hand; everything else about a flight
            // (leave now, gate change) is on its Home card.
            if TravelAlertKind(alertType: userInfo[Key.alertType] as? String) == .boarding {
                return .boardingPass(flightNumber: flightNumber, departure: departure)
            }
            return flightNumber.map { NotificationRoute.deepLink(.flight($0)) } ?? .deepLink(.nextTrip)
        default:
            return legacyRoute(requestIdentifier: requestIdentifier)
        }
    }

    /// Requests scheduled without a category: reminders a previous build left
    /// pending, and the Departure Optimizer's leave reminder. Identified by
    /// their identifier prefixes.
    static func legacyRoute(requestIdentifier id: String) -> NotificationRoute {
        // "gate_<flight>_<gate>_<time>" and "flight_<flight>_<time>".
        let flight = id.split(separator: "_").dropFirst().first
            .flatMap { TravelStore.extractFlightNumber(from: String($0).uppercased()) }
        if id.hasPrefix("gate_") { return .boardingPass(flightNumber: flight, departure: nil) }
        if id.hasPrefix("flight_") { return flight.map { NotificationRoute.deepLink(.flight($0)) } ?? .deepLink(.nextTrip) }
        if id.hasPrefix("checkin_") { return .checkIn }
        if id.hasPrefix("disruption_") { return .disruption }
        if id == "weekly_expense" { return .expenses }
        if id.hasPrefix("trip_start_") || id.hasPrefix("trip_eve_") || id.hasPrefix("depart_") {
            return .deepLink(.nextTrip)
        }
        return .none
    }

    // MARK: Payload values

    /// The flight number a payload names, through the one flight-number parser.
    static func flightNumber(in userInfo: [AnyHashable: Any]) -> String? {
        let raw = (userInfo[Key.flightNumber] as? String) ?? (userInfo[Key.legacyFlightNumber] as? String)
        return raw.flatMap { TravelStore.extractFlightNumber(from: $0.uppercased()) }
    }

    /// The scheduled departure a payload carries, if any.
    static func departure(in userInfo: [AnyHashable: Any]) -> Date? {
        guard let seconds = (userInfo[Key.departure] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: Snooze

    /// The same alert again `minutes` from now, with the same content (sound,
    /// category, interruption level). Snoozing a snoozed alert replaces it
    /// rather than stacking copies. The identifier keeps its prefix, so
    /// removing the trip still cancels it (`cancelFlightAlerts(flightNumber:)`
    /// matches on "flight_<number>_").
    static func snoozedRequest(from request: UNNotificationRequest, minutes: Int) -> UNNotificationRequest? {
        guard minutes > 0,
              let content = request.content.mutableCopy() as? UNMutableNotificationContent else { return nil }
        let suffix = "_snoozed"
        let identifier = request.identifier.hasSuffix(suffix) ? request.identifier : request.identifier + suffix
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    // MARK: Ride

    /// An Uber link to the airport with the drop-off filled in: the same ride
    /// link the Ground Transport screen builds (`RideProvider.rideURL`), which
    /// opens the Uber app when installed and its mobile site otherwise. Nil
    /// for an airport outside `AirportCoordinates`, where the caller opens
    /// Ground Transport so the traveler can type the address.
    @MainActor
    static func rideURL(toAirport iata: String?) -> URL? {
        guard let code = iata?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !code.isEmpty,
              let coordinate = AirportCoordinates.coordinate(for: code) else { return nil }
        let name = AirportNames.spokenName(for: code).map { "\($0) Airport (\(code))" } ?? "\(code) Airport"
        return RideProvider.uber.rideURL(
            pickup: nil,
            dropoff: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            dropoffAddress: name
        )
    }
}
