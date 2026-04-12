// File: Core/Services/DisruptionMonitorService.swift
// BGTaskScheduler-based background service that polls FlightAware AeroAPI
// every 10 minutes for all active trip flights and triggers DisruptionResponseEngine
// when a disruption is detected.
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
    static let baseURL = "https://aeroapi.flightaware.com/aeroapi"
    // TODO: Replace with your FlightAware AeroAPI key from flightaware.com/aeroapi
    static let apiKey  = "YOUR_FLIGHTAWARE_AEROAPI_KEY"

    /// BGTask identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers entry.
    static let bgTaskID = "com.jetsetter.pro.disruption.poll"

    /// Minimum interval between background polls (BGAppRefreshTask enforces this).
    static let pollInterval: TimeInterval = 10 * 60  // 10 minutes

    static let majorDelayThresholdMinutes   = 45
    static let missedConnectionThresholdMin = 60
}

// MARK: - DisruptionMonitorService

/// Singleton actor that orchestrates background flight disruption monitoring.
/// Uses BGAppRefreshTask to wake the app every ~10 minutes while there are
/// active trips, checks each flight via FlightAware, and fires
/// DisruptionResponseEngine for any detected disruption.
actor DisruptionMonitorService {

    static let shared = DisruptionMonitorService()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Gate cache: tracks the last observed departure gate per flight number
    /// so we can detect changes across successive polls.
    private var lastKnownGates: [String: String] = [:]

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
        let request = BGAppRefreshTaskRequest(identifier: FlightAwareConfig.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FlightAwareConfig.pollInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Background Task Handler

    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Schedule next poll first so it fires even if this task expires.
        let request = BGAppRefreshTaskRequest(identifier: FlightAwareConfig.bgTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FlightAwareConfig.pollInterval)
        try? BGTaskScheduler.shared.submit(request)

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

    /// Fetches all active trips from Supabase and checks each flight item for disruptions.
    /// "Active" means: started within the last 24 hours OR departing within the next 24 hours.
    func pollActiveFlights() async throws {
        let isSignedIn = await SupabaseService.shared.isSignedIn
        guard isSignedIn else { return }

        let trips = try await SupabaseService.shared.fetchTrips()
        let now   = Date()
        let windowStart = now.addingTimeInterval(-24 * 3600)
        let windowEnd   = now.addingTimeInterval(24 * 3600)

        let activeTrips = trips.filter {
            $0.startDate <= windowEnd && $0.endDate >= windowStart
        }

        // Process each trip's flight items concurrently.
        await withTaskGroup(of: Void.self) { group in
            for trip in activeTrips {
                let flightItems = trip.items.filter { $0.type == .flight }
                for (index, item) in flightItems.enumerated() {
                    guard let flightNumber = extractFlightNumber(from: item.title) else { continue }

                    // Determine if this item has a connecting leg following it.
                    let nextItemDate: Date? = flightItems.indices.contains(index + 1)
                        ? flightItems[index + 1].startDate
                        : nil

                    group.addTask {
                        await self.checkAndProcessFlight(
                            flightNumber: flightNumber,
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
        trip: Trip,
        nextFlightDeparture: Date?
    ) async {
        do {
            let flight = try await fetchFlightStatus(flightNumber: flightNumber)

            if let disruptionType = detectDisruption(
                flight: flight,
                flightNumber: flightNumber,
                nextDeparture: nextFlightDeparture
            ) {
                // Update gate cache to avoid re-alerting the same gate change.
                if disruptionType == .gateChange, let gate = flight.gateOrigin {
                    lastKnownGates[flightNumber] = gate
                }
                await processDisruption(type: disruptionType, flight: flight,
                                        flightNumber: flightNumber, trip: trip)
            } else {
                // No disruption — just update gate cache for future comparison.
                if let gate = flight.gateOrigin {
                    lastKnownGates[flightNumber] = gate
                }
            }
        } catch {
            // Non-fatal: a single failed check does not stop the overall poll.
        }
    }

    // MARK: - FlightAware AeroAPI

    /// Fetches the latest status for a flight from FlightAware AeroAPI v4.
    /// Returns the most recent flight matching the ident (IATA or ICAO code).
    func fetchFlightStatus(flightNumber: String) async throws -> Flight {
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

        let parsed = try decoder.decode(FlightSearchResponse.self, from: data)
        guard let flight = parsed.flights.first else { throw URLError(.zeroByteResource) }
        return flight
    }

    // MARK: - Disruption Detection

    /// Evaluates a live flight against all four disruption conditions.
    /// Returns the highest-priority type detected, or nil if the flight is normal.
    private func detectDisruption(
        flight: Flight,
        flightNumber: String,
        nextDeparture: Date?
    ) -> DisruptionType? {
        // 1. Cancellation — highest priority
        if flight.cancelled { return .cancellation }

        // 2. Major delay — departure delay exceeds 45-minute threshold
        if let delayMin = flight.departureDelayMinutes,
           delayMin > FlightAwareConfig.majorDelayThresholdMinutes {
            return .majorDelay
        }

        // 3. Gate change — current gate differs from previously cached gate
        let currentGate  = flight.gateOrigin
        let previousGate = lastKnownGates[flightNumber]
        if let current = currentGate, let previous = previousGate, current != previous {
            return .gateChange
        }

        // 4. Missed connection risk — estimated arrival leaves < 60 min before next departure
        if let nextDep = nextDeparture,
           let estimatedArrival = flight.bestArrivalTime {
            let layoverMinutes = Int(nextDep.timeIntervalSince(estimatedArrival) / 60)
            if layoverMinutes < FlightAwareConfig.missedConnectionThresholdMin {
                return .missedConnection
            }
        }

        return nil
    }

    // MARK: - Disruption Processing

    /// Builds the disruption event, fires the response engine and push notification
    /// concurrently, then persists the fully-populated event to Supabase.
    private func processDisruption(
        type: DisruptionType,
        flight: Flight,
        flightNumber: String,
        trip: Trip
    ) async {
        let userId = await SupabaseService.shared.currentUser?.id ?? "anonymous"

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
        var event = DisruptionEvent(
            id: eventId,
            userId: userId,
            tripId: trip.id,
            eventType: type,
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

        // Fire response engine and push notification concurrently.
        async let updatedEvent = DisruptionResponseEngine.shared.handleDisruption(
            event: event, trip: trip
        )
        async let notifyResult: Void = sendDisruptionNotification(
            type: type, flightNumber: flightNumber, eventId: eventId
        )

        event = await updatedEvent
        await notifyResult

        do {
            try await SupabaseService.shared.upsertDisruptionEvent(event)
        } catch {
            // Persist failure is non-fatal — user still gets the push notification.
        }
    }

    // MARK: - Push Notification

    /// Sends an immediate rich push notification when a disruption is detected.
    /// The notification's userInfo includes the event ID so the deep link can open
    /// DisruptionDashboardView pre-scrolled to the right card.
    private func sendDisruptionNotification(
        type: DisruptionType,
        flightNumber: String,
        eventId: UUID
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "\(type.displayName) — \(flightNumber)"
        content.body  = notificationBody(for: type, flightNumber: flightNumber)
        content.sound = .defaultCritical
        content.categoryIdentifier = "DISRUPTION_ALERT"
        content.userInfo = [
            "disruption_event_id": eventId.uuidString,
            "disruption_type": type.rawValue,
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

    private func notificationBody(for type: DisruptionType, flightNumber: String) -> String {
        switch type {
        case .cancellation:
            return "\(flightNumber) has been cancelled. We've found 3 alternatives — tap to rebook."
        case .majorDelay:
            return "\(flightNumber) is delayed 45+ min. Alternative flights are ready."
        case .gateChange:
            return "\(flightNumber) gate changed. Open JetSetter Pro for your new gate and Uber link."
        case .missedConnection:
            return "Layover under 60 min on \(flightNumber). Tap to see rebooking options."
        }
    }

    // MARK: - Helpers

    /// Extracts a valid IATA flight number (carrier code + 1–4 digits) from an itinerary
    /// item title string. Handles formats like "Flight UA837", "UA 837 to Tokyo", "UA837".
    private func extractFlightNumber(from title: String) -> String? {
        // Remove spaces between carrier code and number (e.g. "UA 837" → "UA837")
        let normalized = title.replacingOccurrences(of: #"([A-Z]{2})\s+(\d)"#,
                                                     with: "$1$2",
                                                     options: .regularExpression)
        let pattern = #"\b[A-Z]{2}\d{1,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let range = Range(match.range, in: normalized)
        else { return nil }
        return String(normalized[range])
    }
}
