// File: Core/Services/TravelNotificationScheduler.swift
//
// Bridges the trip/flight data in `TravelStore` to the (previously dormant)
// proactive schedulers on `NotificationManager`. Before this, the manager could
// schedule trip-eve, trip-day, and 2-hours-before-departure reminders — but
// nothing ever called them, so users never got proactive nudges.
//
// This coordinator recomputes all reminders from the current trips on launch
// and whenever trips change (`.jetSetterTripsChanged`, posted by TravelStore).
// The manager uses deterministic notification identifiers keyed on timestamps,
// so re-adding a reminder simply replaces it — making `rescheduleAll()`
// idempotent and safe to call repeatedly. The departure alert carries the
// origin airport so its time reads in that airport's zone and its "Get a ride"
// button can drop the traveler at the right terminal.

import Foundation

@MainActor
final class TravelNotificationScheduler {

    static let shared = TravelNotificationScheduler()
    private init() {}

    private var isObserving = false

    /// Start listening for trip changes so reminders stay in sync. Idempotent —
    /// safe to call once at launch.
    func startObservingTripChanges() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            forName: .jetSetterTripsChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in await TravelNotificationScheduler.shared.rescheduleAll() }
        }
    }

    /// Recomputes trip + flight reminders for every upcoming trip. No-ops when
    /// notification permission hasn't been granted (each manager method also
    /// guards `isAuthorized`, so this is belt-and-suspenders).
    func rescheduleAll() async {
        let manager = NotificationManager.shared
        guard manager.isAuthorized else { return }

        let now = Date()
        let trips = TravelStore.loadTrips().filter { $0.endDate >= now }

        for trip in trips {
            // Trip-level reminders only make sense before the trip starts.
            if trip.startDate > now {
                await manager.scheduleTripEveReminder(tripName: trip.name, startDate: trip.startDate)
                await manager.scheduleTripDayReminder(tripName: trip.name, startDate: trip.startDate)
            }

            // A "2 hours before departure" alert per upcoming flight. Gate
            // reminders are intentionally skipped here — they need a boarding
            // time and gate that itinerary items don't reliably carry.
            for item in trip.items where item.type == .flight && item.startDate > now {
                // Skip flights whose title carries no parseable IATA flight number.
                // Using the raw free-text title as a "flight number" would bake it
                // into the notification identifier ("flight_<whole title>_…"), and
                // `cancelFlightAlerts(flightNumber:)` (which matches the normalized
                // "flight_<number>_" prefix) could then never cancel it.
                guard let flightNumber = TravelStore.extractFlightNumber(from: item.title) else { continue }
                // The alert names the airport the flight leaves from and gives the
                // time there. It used to fall back to the trip's destination,
                // which told a traveler their flight "departs Atlanta" when it
                // leaves Las Vegas for Atlanta.
                let origin = Self.originIATA(of: item)
                let airportName = origin.map { code in
                    AirportNames.spokenName(for: code).map { "\($0) (\(code))" } ?? code
                } ?? item.location ?? "the airport"
                await manager.scheduleFlightDepartureAlert(
                    flightNumber: flightNumber,
                    departureTime: item.startDate,
                    airportName: airportName,
                    originIATA: origin
                )
            }
        }
    }

    /// The departure airport's code: the booking form's field first, then the
    /// "LAS → ATL" location the form writes. Nil when neither holds a code.
    static func originIATA(of item: ItineraryItem) -> String? {
        let candidates = [
            item.flightDetails?.originCode,
            item.location?.components(separatedBy: "→").first
        ]
        for candidate in candidates {
            let code = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) { return code }
        }
        return nil
    }
}
