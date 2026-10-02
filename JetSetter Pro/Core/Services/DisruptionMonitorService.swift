// File: Core/Services/DisruptionMonitorService.swift
// BGTaskScheduler-based background service that polls FlightAware AeroAPI
// every 10 minutes for the traveler's flights departing soon (or recently) and
// triggers DisruptionResponseEngine when a disruption is detected.
//
// Alerts are about one specific flight *instance*: FlightAware lists every
// instance of a flight number it knows (about a week back, a day or two ahead),
// so the monitor picks the one scheduled within ±12 h of the itinerary's
// departure and ignores the rest. What has already been alerted, and the last
// gate seen, are remembered across relaunches in `DisruptionAlertLedgerStore`,
// so each disruption alerts once and again only when it materially changes.
// The pure matching/detection rules live in `DisruptionMatching` so tests can
// pin them without the network.
//
// SETUP REQUIRED:
//  1. In Xcode: Signing & Capabilities → Background Modes → enable
//     "Background fetch" and "Background processing".
//  2. In Info.plist add key BGTaskSchedulerPermittedIdentifiers (Array) with
//     value "com.jetsetter.pro.disruption.poll".
//  3. Call DisruptionMonitorService.shared.registerBackgroundTask() from
//     JetSetter_ProApp.init() before the app finishes launching.

import Foundation
import BackgroundTasks
import UserNotifications

// MARK: - FlightAware Configuration

private enum FlightAwareConfig {
    // All statics are `nonisolated` so they can be read from `nonisolated`
    // BGTaskScheduler callbacks and from the `DisruptionMonitorService`
    // actor context alike. The project defaults to `@MainActor`, which
    // would otherwise pin these to the main actor.
    nonisolated static let baseURL = "https://aeroapi.flightaware.com/aeroapi"
    /// FlightAware AeroAPI key — sourced from Secrets.xcconfig → Info.plist.
    nonisolated static let apiKey: String = readFlightAwareSecret("API_FLIGHTAWARE")
    /// True when live flight status can be fetched at all.
    nonisolated static var isConfigured: Bool { !apiKey.isEmpty }

    /// BGTask identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers entry.
    nonisolated static let bgTaskID = "com.jetsetter.pro.disruption.poll"

    /// Minimum interval between background polls (BGAppRefreshTask enforces this).
    nonisolated static let pollInterval: TimeInterval = 10 * 60  // 10 minutes

    nonisolated static let majorDelayThresholdMinutes   = 45
    nonisolated static let missedConnectionThresholdMin = 60
}

/// Bundle-level secret reader. Mirrors `AppSecrets.value(for:)` but is
/// `nonisolated` so it can be referenced from any actor context.
private nonisolated func readFlightAwareSecret(_ key: String) -> String {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return "" }
    if trimmed.hasPrefix("YOUR_") || trimmed == "REPLACE_ME" { return "" }
    return trimmed
}

// MARK: - Errors

enum DisruptionMonitorError: LocalizedError {
    /// No FlightAware key in this build — live status and disruption checks are off.
    case liveStatusUnavailable

    var errorDescription: String? {
        switch self {
        case .liveStatusUnavailable:
            return "Live flight status isn't switched on in this build yet. Your flights still show on Home and in your itinerary."
        }
    }
}

// MARK: - Matching & detection (pure)

/// The monitor's decisions with no networking or persistence, so they can be
/// tested directly. Functions that read `Flight` are `@MainActor` because the
/// model inherits main-actor isolation from the project default.
nonisolated enum DisruptionMatching {

    /// A FlightAware instance is "the itinerary's flight" only when its scheduled
    /// gate departure is within this of the itinerary time. Daily flights are
    /// 24 h apart, so yesterday's and tomorrow's instances always fall outside,
    /// while an itinerary time that's off by a few hours (a time-zone slip in a
    /// pasted booking) still matches.
    static let instanceMatchWindow: TimeInterval = 12 * 3600

    /// Legs that departed longer ago than this are finished as far as the
    /// monitor is concerned, so they're no longer polled.
    static let pastDepartureCutoff: TimeInterval = 6 * 3600

    /// How far ahead legs are polled, matching the old ±24 h trip window so
    /// FlightAware usage stays where it was.
    static let lookahead: TimeInterval = 24 * 3600

    /// Upper bound on a plausible flight connection layover. Beyond this, the
    /// following itinerary flight is treated as a separate segment rather than a
    /// connection, so its gap never triggers a missed-connection alert.
    static let maxConnectionWindowMinutes = 8 * 60  // 8 hours

    /// Delay alert buckets in minutes. The first is the major-delay threshold;
    /// each later one is worth a fresh alert ("now 90+ min late"), while every
    /// poll inside the same bucket is not.
    static let delayBuckets = [FlightAwareConfig.majorDelayThresholdMinutes, 90, 150, 240, 360]

    /// Departure delay at which the Live Activity says "Delayed". Fifteen
    /// minutes is the industry's on-time definition.
    static let liveDelayThresholdMinutes = 15

    /// True when an itinerary leg departing at `departure` is worth polling now.
    static func shouldMonitor(departure: Date, now: Date) -> Bool {
        departure >= now.addingTimeInterval(-pastDepartureCutoff)
            && departure <= now.addingTimeInterval(lookahead)
    }

    /// The bucket a departure delay falls in, or nil below the major-delay threshold.
    static func delayBucket(minutes: Int) -> Int? {
        delayBuckets.last { minutes >= $0 }
    }

    /// Canonical gate for comparison ("b 12" → "B12"). Placeholders mean unknown.
    static func normalizedGate(_ gate: String?) -> String? {
        guard let gate else { return nil }
        let cleaned = gate.uppercased().filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, cleaned != "—", cleaned != "-", cleaned != "TBD" else { return nil }
        return cleaned
    }

    /// The instance whose scheduled departure is closest to the itinerary's,
    /// provided it's within `instanceMatchWindow`. Nil means FlightAware doesn't
    /// list this day's flight (yet), and the caller must not alert at all.
    @MainActor
    static func matchingInstance(in flights: [Flight], scheduledDeparture: Date) -> Flight? {
        var best: Flight?
        var bestGap = TimeInterval.infinity
        for flight in flights {
            guard let scheduledOut = flight.scheduledOut else { continue }
            let gap = abs(scheduledOut.timeIntervalSince(scheduledDeparture))
            if gap <= instanceMatchWindow, gap < bestGap {
                best = flight
                bestGap = gap
            }
        }
        return best
    }

    /// True once the flight has landed or reached the gate.
    @MainActor
    static func hasLanded(_ flight: Flight) -> Bool {
        if flight.actualIn != nil { return true }
        // AeroAPI reports e.g. "Landed / Taxiing" and "Arrived / Gate Arrival"
        // before (or without) a gate-in time.
        let status = flight.status.lowercased()
        return status.contains("landed") || status.contains("arrived")
    }

    /// Every disruption currently true for `flight`, most severe first. Dedupe
    /// against what was already sent happens in `DisruptionAlertLedger`.
    @MainActor
    static func detectAlerts(
        flight: Flight,
        previousGate: String?,
        nextDeparture: Date?
    ) -> [DisruptionAlert] {
        // 1. Cancellation makes everything else about the flight moot.
        if flight.cancelled {
            return [DisruptionAlert(type: .cancellation, value: "cancelled")]
        }

        // 2. Diversion, checked before "landed": a diverted flight that has
        //    landed has landed at the wrong airport. The value is FlightAware's
        //    destination code (used only for dedupe, never shown), so a second
        //    diversion alerts again.
        if flight.diverted {
            let value = flight.destination.codeIata ?? flight.destination.code ?? "diverted"
            return [DisruptionAlert(type: .diversion, value: value)]
        }

        // 3. Landed or at the gate: delays, gates and connections are history.
        if hasLanded(flight) { return [] }

        var alerts: [DisruptionAlert] = []

        // 4. Major delay, bucketed so it re-alerts only when it grows.
        if let delay = flight.departureDelayMinutes, let bucket = delayBucket(minutes: delay) {
            alerts.append(DisruptionAlert(type: .majorDelay, value: String(bucket)))
        }

        // 5. Gate change: the current gate differs from the last one known.
        if let current = normalizedGate(flight.gateOrigin),
           let previous = normalizedGate(previousGate),
           current != previous {
            alerts.append(DisruptionAlert(type: .gateChange, value: current))
        }

        // 6. Missed connection risk: projected arrival leaves < 60 min before the
        //    next departure. Only a following leg that departs *after* this one
        //    arrives and within a plausible connection window counts: a return
        //    flight or a separate trip segment is not a connection.
        if let nextDeparture, let projectedArrival = projectedArrivalTime(for: flight) {
            let layoverMinutes = Int(nextDeparture.timeIntervalSince(projectedArrival) / 60)
            let isPlausibleConnection = layoverMinutes >= 0 && layoverMinutes <= maxConnectionWindowMinutes
            if isPlausibleConnection, layoverMinutes < FlightAwareConfig.missedConnectionThresholdMin {
                alerts.append(DisruptionAlert(type: .missedConnection, value: "risk"))
            }
        }

        return alerts
    }

    /// Projected gate arrival used for missed-connection evaluation.
    /// Prefers a live time (actual → estimated). When only the scheduled
    /// arrival is known, folds in any known delay (arrival delay preferred,
    /// else departure delay) so a delayed inbound with no live estimate is
    /// still evaluated against a realistic arrival rather than its on-time
    /// schedule.
    @MainActor
    static func projectedArrivalTime(for flight: Flight) -> Date? {
        if let live = flight.actualIn ?? flight.estimatedIn {
            return live
        }
        guard let scheduled = flight.scheduledIn else { return nil }
        if let delayMin = flight.arrivalDelayMinutes ?? flight.departureDelayMinutes,
           delayMin > 0 {
            return scheduled.addingTimeInterval(TimeInterval(delayMin) * 60)
        }
        return scheduled
    }

    /// The Live Activity status FlightAware's data supports, or nil when the
    /// monitor shouldn't touch the card (after pushback InFlightTrackingService
    /// owns it). With no delay figure at all we stay on the neutral `.scheduled`
    /// rather than claim "On Time".
    @MainActor
    static func liveActivityStatus(for flight: Flight) -> FlightActivityState.FlightStatus? {
        if flight.cancelled { return .cancelled }
        if flight.diverted { return .diverted }
        if flight.actualOut != nil || hasLanded(flight) { return nil }
        guard let delay = flight.departureDelayMinutes else { return .scheduled }
        return delay >= liveDelayThresholdMinutes ? .delayed : .onTime
    }
}

// MARK: - DisruptionMonitorService

/// Singleton actor that orchestrates background flight disruption monitoring.
/// Uses BGAppRefreshTask to wake the app every ~10 minutes, checks each flight
/// leg departing soon via FlightAware, and fires DisruptionResponseEngine for
/// any new disruption.
actor DisruptionMonitorService {

    static let shared = DisruptionMonitorService()
    private init() {}

    /// True when a FlightAware key is present, so live status and background
    /// disruption checks can run. Without it the app works fully from the
    /// itinerary; the Flight Tracker and Disruption screens say so.
    nonisolated static var isLiveStatusConfigured: Bool { FlightAwareConfig.isConfigured }

    // MARK: - Background Task Registration

    /// Register with BGTaskScheduler. Must be called before the app finishes
    /// launching — place in JetSetter_ProApp.init().
    nonisolated func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FlightAwareConfig.bgTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { await DisruptionMonitorService.shared.handleBackgroundTask(refreshTask) }
        }
    }

    /// Schedules the next background poll. Call at app launch AND after each poll completes.
    nonisolated func scheduleNextPoll() {
        // Without a FlightAware key every wake would fail and BGTaskScheduler
        // would deprioritise the app; don't ask for wakes we can't use.
        guard FlightAwareConfig.isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: FlightAwareConfig.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FlightAwareConfig.pollInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Background Task Handler

    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // A request submitted by an earlier keyed build can still fire after the
        // key is gone: finish quietly and don't chain another.
        guard FlightAwareConfig.isConfigured else {
            task.setTaskCompleted(success: true)
            return
        }
        // Schedule next poll first so it fires even if this task expires.
        scheduleNextPoll()

        // Provide an expiration handler so the OS can terminate cleanly.
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        do {
            try await pollActiveFlights()
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Main Poll Loop

    /// Reads the traveler's trips from the on-device store and checks each
    /// flight leg that departs within the next 24 hours or departed within the
    /// last 6 (`DisruptionMatching.shouldMonitor`). Legs further out aren't
    /// listed by FlightAware yet; legs further back are over.
    func pollActiveFlights() async throws {
        // No key → nothing to poll. Quiet for the background task; the manual
        // "Check Now" path explains the situation to the user itself.
        guard FlightAwareConfig.isConfigured else { throw DisruptionMonitorError.liveStatusUnavailable }
        let trips = await MainActor.run { TravelStore.loadTrips() }
        let now = Date()

        // Process each trip's flight items concurrently.
        await withTaskGroup(of: Void.self) { group in
            for trip in trips {
                // Sort chronologically before pairing connecting legs — trip
                // items are not guaranteed to be in departure order, and pairing
                // by raw array position would otherwise yield negative layovers.
                let flightItems = trip.items
                    .filter { $0.type == .flight }
                    .sorted { $0.startDate < $1.startDate }
                for (index, item) in flightItems.enumerated() {
                    guard DisruptionMatching.shouldMonitor(departure: item.startDate, now: now) else { continue }
                    // The structured flight number is the more reliable source;
                    // the title is what older and pasted items carry.
                    guard let flightNumber = extractFlightNumber(from: item.flightDetails?.flightNumber ?? "")
                            ?? extractFlightNumber(from: item.title)
                    else { continue }

                    // Determine if this item has a connecting leg following it.
                    let nextItemDate: Date? = flightItems.indices.contains(index + 1)
                        ? flightItems[index + 1].startDate
                        : nil

                    group.addTask {
                        await self.checkAndProcessFlight(
                            flightNumber: flightNumber,
                            item: item,
                            trip: trip,
                            nextFlightDeparture: nextItemDate
                        )
                    }
                }
            }
        }
    }

    // MARK: - Per-Flight Check

    private func checkAndProcessFlight(
        flightNumber: String,
        item: ItineraryItem,
        trip: Trip,
        nextFlightDeparture: Date?
    ) async {
        do {
            let instances = try await fetchFlightInstances(flightNumber: flightNumber)
            await evaluate(
                instances: instances,
                flightNumber: flightNumber,
                item: item,
                trip: trip,
                nextFlightDeparture: nextFlightDeparture
            )
        } catch {
            // Non-fatal: a single failed check does not stop the overall poll.
        }
    }

    /// Matches the itinerary leg to one FlightAware instance, updates the gate
    /// memory and any Live Activity, and alerts on whatever is new.
    /// `@MainActor` because `Flight` and the ledger store are main-actor types.
    @MainActor
    private func evaluate(
        instances: [Flight],
        flightNumber: String,
        item: ItineraryItem,
        trip: Trip,
        nextFlightDeparture: Date?
    ) async {
        // Taking `flights.first` used to alert on yesterday's delay or
        // tomorrow's cancellation. No instance within ±12 h means no alert.
        guard let flight = DisruptionMatching.matchingInstance(
            in: instances, scheduledDeparture: item.startDate
        ) else { return }

        let now = Date()
        let originZone = flight.origin.timeZone
            ?? item.flightDetails?.originCode.flatMap { AirportCoordinates.timeZone(for: $0) }
        let flightKey = DisruptionAlertLedger.flightKey(
            faFlightId: flight.faFlightId,
            flightNumber: flightNumber,
            scheduledDeparture: item.startDate,
            originTimeZone: originZone
        )
        let store = DisruptionAlertLedgerStore.shared

        // The remembered gate survives relaunches; before FlightAware has ever
        // reported one, the gate on the traveler's itinerary is the baseline,
        // so a change from the gate they were told is still caught.
        let previousGate = store.ledger.knownGate(flightKey: flightKey)
            ?? DisruptionMatching.normalizedGate(item.flightDetails?.gate)
        let candidates = DisruptionMatching.detectAlerts(
            flight: flight,
            previousGate: previousGate,
            nextDeparture: nextFlightDeparture
        )
        let currentGate = DisruptionMatching.normalizedGate(flight.gateOrigin)

        // Decide and record in one synchronous main-actor step, so two
        // overlapping polls can't both send the same alert.
        let toSend: [DisruptionAlert] = store.mutate(now: now) { ledger in
            if let currentGate {
                ledger.recordGate(currentGate, flightKey: flightKey, at: now)
            }
            let fresh = candidates.filter { ledger.shouldSend($0, flightKey: flightKey) }
            for alert in fresh {
                ledger.recordSent(alert, flightKey: flightKey, at: now)
            }
            return fresh
        }

        // Reflect real FlightAware status on this flight's Live Activity, if one
        // is showing (no-op otherwise; skipped by the service when unchanged).
        if let liveStatus = DisruptionMatching.liveActivityStatus(for: flight) {
            let delay = flight.departureDelayMinutes.flatMap { $0 > 0 ? $0 : nil }
            FlightLiveActivityService.shared.update(
                forFlight: flightNumber,
                departing: item.startDate,
                gate: flight.gateOrigin,
                terminal: flight.terminalOrigin,
                status: liveStatus,
                estimatedDeparture: flight.bestDepartureTime ?? item.startDate,
                delayMinutes: delay
            )
        }

        for alert in toSend {
            await processDisruption(alert: alert, flight: flight, flightNumber: flightNumber, trip: trip)
        }
    }

    // MARK: - FlightAware AeroAPI

    /// Fetches every instance FlightAware lists for a flight number from AeroAPI
    /// v4. The caller picks the right one with
    /// `DisruptionMatching.matchingInstance`.
    /// Runs on `@MainActor` because `FlightSearchResponse`/`Flight` inherit
    /// MainActor isolation from the project-wide default, and decoding them
    /// must happen in a MainActor-isolated context.
    @MainActor
    func fetchFlightInstances(flightNumber: String) async throws -> [Flight] {
        guard FlightAwareConfig.isConfigured else { throw DisruptionMonitorError.liveStatusUnavailable }
        // AeroAPI v4 endpoint: GET /flights/{ident}
        guard let url = URL(string: "\(FlightAwareConfig.baseURL)/flights/\(flightNumber)?max_pages=1") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue(FlightAwareConfig.apiKey, forHTTPHeaderField: "x-apikey")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FlightSearchResponse.self, from: data).flights
    }

    // MARK: - Disruption Processing

    /// Builds the disruption event, fires the response engine and push
    /// notification concurrently, then persists the fully-populated event.
    /// Only called for alerts the ledger says are new.
    /// `@MainActor` so we can read MainActor-isolated `Flight` properties
    /// and construct MainActor-isolated `DisruptionEvent` / `ResponseActions`.
    @MainActor
    private func processDisruption(
        alert: DisruptionAlert,
        flight: Flight,
        flightNumber: String,
        trip: Trip
    ) async {
        let userId = "local"

        let snapshot = FlightSnapshot(
            flightNumber: flightNumber,
            airline: flight.operatorName ?? "Unknown Airline",
            origin: flight.origin.codeIata ?? flight.origin.code ?? "—",
            destination: flight.destination.codeIata ?? flight.destination.code ?? "—",
            scheduledDeparture: flight.scheduledOut ?? Date(),
            originalGate: flight.gateOrigin,
            status: flight.status,
            delayMinutes: flight.departureDelayMinutes
        )

        let eventId = UUID()
        let initialEvent = DisruptionEvent(
            id: eventId,
            userId: userId,
            tripId: trip.id,
            eventType: alert.type,
            originalFlight: snapshot,
            alternatives: [],
            responseActions: ResponseActions(),
            resolved: false,
            rebookingUrl: nil,
            hotelContact: nil,
            uberDeepLink: nil,
            insuranceDocumentId: nil,
            createdAt: Date()
        )

        // Fire response engine and push notification concurrently. We capture
        // `initialEvent` (a `let`) so the `async let` task can safely read it
        // without tripping the captured-var checker.
        async let updatedEvent = DisruptionResponseEngine.shared.handleDisruption(
            event: initialEvent, trip: trip
        )
        async let notifyResult: Void = sendDisruptionNotification(
            alert: alert, flightNumber: flightNumber, eventId: eventId
        )

        let finalEvent = await updatedEvent
        await notifyResult

        await LocalDataService.shared.upsertDisruptionEvent(finalEvent)
    }

    // MARK: - Push Notification

    /// Sends an immediate rich push notification when a disruption is detected.
    /// The notification's userInfo includes the event ID so the deep link can open
    /// DisruptionDashboardView pre-scrolled to the right card.
    /// `@MainActor` because `DisruptionType.displayName` inherits MainActor
    /// isolation from the project-wide default.
    @MainActor
    private func sendDisruptionNotification(
        alert: DisruptionAlert,
        flightNumber: String,
        eventId: UUID
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "\(alert.type.displayName) — \(flightNumber)"
        content.body  = notificationBody(for: alert, flightNumber: flightNumber)
        // Cabin "fasten seatbelt" chime on every disruption alert (IOS_PARITY_NOTES.md §7.4).
        // The ledger guarantees this plays once per disruption, not once per poll.
        content.sound = NotificationManager.cabinChimeSound
        content.categoryIdentifier = "DISRUPTION_ALERT"
        content.userInfo = [
            "disruption_event_id": eventId.uuidString,
            "disruption_type": alert.type.rawValue,
            "flight_number": flightNumber
        ]

        // nil trigger = deliver immediately
        let request = UNNotificationRequest(
            identifier: "disruption_\(eventId.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    private func notificationBody(for alert: DisruptionAlert, flightNumber: String) -> String {
        switch alert.type {
        case .cancellation:
            return "\(flightNumber) has been cancelled. Tap for a same-route flight search and your trip's hotel and insurance details."
        case .majorDelay:
            return "\(flightNumber) is delayed \(alert.value)+ min. Tap to search alternative flights and let your hotel know."
        case .gateChange:
            return "\(flightNumber) now departs from gate \(alert.value). Open JetSetter Pro for a ride to the terminal."
        case .missedConnection:
            return "Layover under 60 min on \(flightNumber). Tap for a search of onward flights."
        case .diversion:
            return "\(flightNumber) has been diverted and won't arrive at its scheduled destination. Tap for a flight search and your trip's hotel details."
        }
    }

    // MARK: - Helpers

    /// Flight number from an itinerary string. Delegates to the one shared
    /// parser: the private regex that used to live here disagreed with it and,
    /// for example, read "Gate B12" in a title as flight B12.
    private func extractFlightNumber(from title: String) -> String? {
        TravelStore.extractFlightNumber(from: title)
    }
}
