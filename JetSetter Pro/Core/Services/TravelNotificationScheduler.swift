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
// idempotent and safe to call repeatedly.

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
                let flightNumber = TravelStore.extractFlightNumber(from: item.title) ?? item.title
                let airportName = item.location ?? trip.destination
                await manager.scheduleFlightDepartureAlert(
                    flightNumber: flightNumber,
                    departureTime: item.startDate,
                    airportName: airportName
                )
            }
        }
    }
}
