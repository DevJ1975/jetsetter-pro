// File: Core/Services/EmailIntelligence/TravelEmailCommitService.swift
//
// Writes reviewed parse results into the app's existing stores, following the
// same offline-first pattern the rest of the app uses (local UserDefaults
// first, best-effort Supabase sync after):
//   flights      → WalletItem(.boardingPass) + ItineraryItem(.flight)
//   hotels       → WalletItem(.hotelReservation) + ItineraryItem(.hotel)
//   car rentals  → WalletItem(.carRental)
//   meetings     → ItineraryItem(.activity) + optional Calendar event
//   disruptions  → DisruptionEvent (feeds the Disruption dashboard)
//
// Dedupe: a fingerprint registry keyed on confirmation number / flight+date
// prevents re-forwarded emails from creating duplicates; a fingerprint match
// UPDATES the existing wallet item (gate change, new seat) instead of adding.

import Foundation

@MainActor
final class TravelEmailCommitService {

    static let shared = TravelEmailCommitService()
    private init() {}

    // MARK: - Types

    struct Options {
        var syncMeetingsToCalendar = true
        var scheduleFlightAlerts = true
    }

    struct Summary {
        var added = 0
        var updated = 0
        var calendarEvents = 0
        var disruptions = 0
        var lines: [String] = []

        var isEmpty: Bool { added == 0 && updated == 0 && calendarEvents == 0 && disruptions == 0 }
    }

    // MARK: - Storage keys (shared with the rest of the app)

    private let walletKey = "jetsetter_wallet_items"                    // WalletViewModel / DemoSeeder
    private let tripsKey = "jetsetter_trips"                            // ItineraryViewModel
    private let disruptionKey = "jetsetter_disruption_events_local"     // DisruptionViewModel / DemoSeeder
    private static let fingerprintKey = "jetsetter_parsed_email_fingerprints"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Entry point

    /// Commits the selected entities. `selectedIDs == nil` commits everything.
    func commit(
        _ parsed: ParsedTravelEmail,
        selectedIDs: Set<UUID>? = nil,
        options: Options = Options()
    ) async -> Summary {
        var summary = Summary()
        var wallet = loadWallet()
        var trips = loadTrips()
        var fingerprints = Set(UserDefaults.standard.stringArray(forKey: Self.fingerprintKey) ?? [])
        var walletItemsToSync: [WalletItem] = []
        var tripsChanged = false

        func isSelected(_ id: UUID) -> Bool { selectedIDs?.contains(id) ?? true }

        // ── Flights ──────────────────────────────────────────────────────
        for flight in parsed.flights where isSelected(flight.id) {
            let departure = TravelDateParser.date(from: flight.departureLocal)
            let arrival = TravelDateParser.date(from: flight.arrivalLocal)
            let route = [flight.departureAirport, flight.arrivalAirport]
                .compactMap { $0 }.joined(separator: " → ")
            let title = route.isEmpty
                ? flight.flightNumber
                : "\(flight.flightNumber) · \(route)"

            var rawData: [String: String] = ["flight_number": flight.flightNumber]
            rawData["iata_code"] = String(flight.flightNumber.prefix(2))
            if let v = flight.airline { rawData["airline"] = v }
            if let v = flight.departureAirport { rawData["departure_airport"] = v }
            if let v = flight.arrivalAirport { rawData["arrival_airport"] = v }
            if let v = flight.seat { rawData["seat_number"] = v }
            if let v = flight.gate { rawData["gate"] = v }
            if let v = flight.terminal { rawData["terminal"] = v }

            let matchIndex = wallet.firstIndex { item in
                item.itemType == .boardingPass && (
                    (flight.confirmationNumber != nil && item.confirmationNumber == flight.confirmationNumber)
                    || (item.rawData["flight_number"] == flight.flightNumber
                        && departure.map { Calendar.current.isDate(item.date, inSameDayAs: $0) } == true)
                )
            }

            if fingerprints.contains(flight.fingerprint), let index = matchIndex {
                // Re-forwarded confirmation → update in place (gate/seat/time).
                var existing = wallet[index]
                existing.title = title
                if let departure { existing.date = departure }
                existing.rawData.merge(rawData) { _, new in new }
                wallet[index] = existing
                walletItemsToSync.append(existing)
                summary.updated += 1
                summary.lines.append("Updated flight \(flight.flightNumber)")
            } else {
                let tripId = matchOrCreateTripForFlight(flight, departure: departure, arrival: arrival,
                                                        trips: &trips, changed: &tripsChanged)
                let item = WalletItem(
                    tripId: tripId,
                    itemType: .boardingPass,
                    title: title,
                    confirmationNumber: flight.confirmationNumber,
                    date: departure ?? Date(),
                    rawData: rawData
                )
                wallet.append(item)
                walletItemsToSync.append(item)
                fingerprints.insert(flight.fingerprint)
                summary.added += 1
                summary.lines.append("Added flight \(flight.flightNumber)")

                // Trip-timeline entry
                if let tripId, let tripIndex = trips.firstIndex(where: { $0.id == tripId }), let departure {
                    let itineraryItem = ItineraryItem(
                        title: "Flight \(flight.flightNumber)" + (route.isEmpty ? "" : " — \(route)"),
                        type: .flight,
                        startDate: departure,
                        endDate: arrival,
                        location: route.isEmpty ? nil : route,
                        notes: flight.confirmationNumber.map { "Conf: \($0)" }
                    )
                    trips[tripIndex].items.append(itineraryItem)
                    tripsChanged = true
                }
            }

            if options.scheduleFlightAlerts, let departure, departure > Date() {
                await NotificationManager.shared.scheduleFlightDepartureAlert(
                    flightNumber: flight.flightNumber,
                    departureTime: departure,
                    airportName: flight.departureAirport ?? ""
                )
            }
        }

        // ── Hotels ───────────────────────────────────────────────────────
        for hotel in parsed.hotels where isSelected(hotel.id) {
            guard !fingerprints.contains(hotel.fingerprint) else {
                summary.lines.append("Skipped duplicate hotel \(hotel.name)")
                continue
            }
            let checkIn = TravelDateParser.date(from: hotel.checkInLocal)
            let checkOut = TravelDateParser.date(from: hotel.checkOutLocal)

            var rawData: [String: String] = [:]
            if let v = hotel.address { rawData["hotel_address"] = v }
            if let v = hotel.checkInLocal { rawData["check_in_date"] = v }
            if let v = hotel.checkOutLocal {
                rawData["check_out_date"] = v
                rawData["end_date"] = v
            }

            let tripId = matchOrCreateTripForHotel(hotel, checkIn: checkIn, checkOut: checkOut,
                                                   trips: &trips, changed: &tripsChanged)
            let item = WalletItem(
                tripId: tripId,
                itemType: .hotelReservation,
                title: hotel.name,
                confirmationNumber: hotel.confirmationNumber,
                date: checkIn ?? Date(),
                rawData: rawData
            )
            wallet.append(item)
            walletItemsToSync.append(item)
            fingerprints.insert(hotel.fingerprint)
            summary.added += 1
            summary.lines.append("Added hotel \(hotel.name)")

            if let tripId, let tripIndex = trips.firstIndex(where: { $0.id == tripId }), let checkIn {
                let itineraryItem = ItineraryItem(
                    title: "Check in — \(hotel.name)",
                    type: .hotel,
                    startDate: checkIn,
                    endDate: checkOut,
                    location: hotel.address,
                    notes: hotel.confirmationNumber.map { "Conf: \($0)" }
                )
                trips[tripIndex].items.append(itineraryItem)
                tripsChanged = true
            }
        }

        // ── Car rentals ──────────────────────────────────────────────────
        for car in parsed.carRentals where isSelected(car.id) {
            guard !fingerprints.contains(car.fingerprint) else {
                summary.lines.append("Skipped duplicate rental \(car.company)")
                continue
            }
            let pickup = TravelDateParser.date(from: car.pickupLocal)

            var rawData: [String: String] = ["rental_company": car.company]
            if let v = car.pickupLocation { rawData["pickup_location"] = v }
            if let v = car.vehicleClass { rawData["vehicle_class"] = v }
            if let v = car.dropoffLocal { rawData["end_date"] = v }

            let matchedTripIndex = tripIndex(matching: pickup, in: trips)
            let item = WalletItem(
                tripId: matchedTripIndex.map { trips[$0].id },
                itemType: .carRental,
                title: "\(car.company)" + (car.pickupLocation.map { " — \($0)" } ?? ""),
                confirmationNumber: car.confirmationNumber,
                date: pickup ?? Date(),
                rawData: rawData
            )
            wallet.append(item)
            walletItemsToSync.append(item)
            fingerprints.insert(car.fingerprint)
            summary.added += 1
            summary.lines.append("Added rental — \(car.company)")
        }

        // ── Meetings ─────────────────────────────────────────────────────
        for meeting in parsed.meetings where isSelected(meeting.id) {
            guard !fingerprints.contains(meeting.fingerprint) else {
                summary.lines.append("Skipped duplicate meeting \(meeting.title)")
                continue
            }
            guard let start = TravelDateParser.date(from: meeting.startLocal) else {
                summary.lines.append("Skipped meeting \(meeting.title) — no date found")
                continue
            }
            let end = TravelDateParser.date(from: meeting.endLocal)

            let noteParts = [meeting.organizer.map { "Organizer: \($0)" }, meeting.notes]
                .compactMap { $0 }
            var itineraryItem = ItineraryItem(
                title: meeting.title,
                type: .activity,
                startDate: start,
                endDate: end,
                location: meeting.location,
                notes: noteParts.isEmpty ? nil : noteParts.joined(separator: "\n")
            )

            if options.syncMeetingsToCalendar {
                if !CalendarService.shared.isAuthorized {
                    try? await CalendarService.shared.requestAccess()
                }
                if CalendarService.shared.isAuthorized,
                   let identifier = try? await CalendarService.shared.addEvent(for: itineraryItem) {
                    itineraryItem.calendarEventIdentifier = identifier
                    summary.calendarEvents += 1
                }
            }

            if let index = tripIndex(matching: start, in: trips) {
                trips[index].items.append(itineraryItem)
                tripsChanged = true
            }
            fingerprints.insert(meeting.fingerprint)
            summary.added += 1
            summary.lines.append("Added meeting \(meeting.title)")
        }

        // ── Disruption notices ───────────────────────────────────────────
        var disruptionsToSync: [DisruptionEvent] = []
        for notice in parsed.disruptions where isSelected(notice.id) {
            guard !fingerprints.contains(notice.fingerprint) else { continue }
            let scheduled = TravelDateParser.date(from: notice.scheduledDepartureLocal)

            let eventType: DisruptionType
            switch notice.kind {
            case "cancellation": eventType = .cancellation
            case "gate_change":  eventType = .gateChange
            default:             eventType = .majorDelay
            }

            let userId = await SupabaseService.shared.currentUser?.id ?? "local"
            let event = DisruptionEvent(
                id: UUID(),
                userId: userId,
                tripId: tripIndex(matching: scheduled, in: trips).map { trips[$0].id }
                    ?? trips.first?.id ?? UUID(),
                eventType: eventType,
                originalFlight: FlightSnapshot(
                    flightNumber: notice.flightNumber,
                    airline: notice.airline ?? "",
                    origin: notice.origin ?? "",
                    destination: notice.destination ?? "",
                    scheduledDeparture: scheduled ?? Date(),
                    originalGate: notice.newGate,
                    status: notice.details ?? notice.kind.replacingOccurrences(of: "_", with: " ").capitalized,
                    delayMinutes: notice.delayMinutes
                ),
                alternatives: [],
                responseActions: ResponseActions(
                    alternativesFound: false,
                    rebookingChecked: false,
                    hotelNotified: false,
                    uberRerouteReady: false,
                    insuranceSurfaced: false
                ),
                resolved: false,
                rebookingUrl: nil,
                hotelContact: nil,
                uberDeepLink: nil,
                insuranceDocumentId: nil,
                createdAt: Date()
            )

            var events = loadDisruptions()
            events.insert(event, at: 0)
            saveDisruptions(events)
            disruptionsToSync.append(event)
            fingerprints.insert(notice.fingerprint)
            summary.disruptions += 1
            summary.lines.append("Recorded \(notice.kind.replacingOccurrences(of: "_", with: " ")) for \(notice.flightNumber)")
        }

        // ── Persist locally, then best-effort cloud sync ─────────────────
        saveWallet(wallet)
        if tripsChanged { saveTrips(trips) }
        UserDefaults.standard.set(Array(fingerprints), forKey: Self.fingerprintKey)

        for item in walletItemsToSync {
            try? await SupabaseService.shared.upsertWalletItem(item)
        }
        if tripsChanged {
            try? await SupabaseService.shared.syncTrips(trips)
        }
        for event in disruptionsToSync {
            try? await SupabaseService.shared.upsertDisruptionEvent(event)
        }

        return summary
    }

    // MARK: - Trip matching

    /// Index of the trip whose (padded) date range contains `date`.
    private func tripIndex(matching date: Date?, in trips: [Trip]) -> Int? {
        guard let date else { return nil }
        let pad: TimeInterval = 86_400
        return trips.firstIndex {
            date >= $0.startDate.addingTimeInterval(-pad)
                && date <= $0.endDate.addingTimeInterval(pad)
        }
    }

    private func matchOrCreateTripForFlight(
        _ flight: ParsedFlight, departure: Date?, arrival: Date?,
        trips: inout [Trip], changed: inout Bool
    ) -> UUID? {
        if let index = tripIndex(matching: departure, in: trips) { return trips[index].id }
        guard let departure else { return nil }
        let destination = flight.arrivalAirport ?? flight.departureAirport ?? "New Trip"
        let trip = Trip(
            name: "Trip to \(destination)",
            destination: destination,
            startDate: Calendar.current.startOfDay(for: departure),
            endDate: (arrival ?? departure).addingTimeInterval(86_400)
        )
        trips.append(trip)
        changed = true
        return trip.id
    }

    private func matchOrCreateTripForHotel(
        _ hotel: ParsedHotel, checkIn: Date?, checkOut: Date?,
        trips: inout [Trip], changed: inout Bool
    ) -> UUID? {
        if let index = tripIndex(matching: checkIn, in: trips) { return trips[index].id }
        guard let checkIn else { return nil }
        let trip = Trip(
            name: "Stay — \(hotel.name)",
            destination: hotel.address ?? hotel.name,
            startDate: Calendar.current.startOfDay(for: checkIn),
            endDate: checkOut ?? checkIn.addingTimeInterval(86_400)
        )
        trips.append(trip)
        changed = true
        return trip.id
    }

    // MARK: - Local persistence (same keys/encoding as the owning ViewModels)

    private func loadWallet() -> [WalletItem] {
        guard let data = UserDefaults.standard.data(forKey: walletKey) else { return [] }
        return (try? decoder.decode([WalletItem].self, from: data)) ?? []
    }

    private func saveWallet(_ items: [WalletItem]) {
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: walletKey)
        }
    }

    private func loadTrips() -> [Trip] {
        guard let data = UserDefaults.standard.data(forKey: tripsKey) else { return [] }
        return (try? decoder.decode([Trip].self, from: data)) ?? []
    }

    private func saveTrips(_ trips: [Trip]) {
        if let data = try? encoder.encode(trips) {
            UserDefaults.standard.set(data, forKey: tripsKey)
        }
    }

    private func loadDisruptions() -> [DisruptionEvent] {
        guard let data = UserDefaults.standard.data(forKey: disruptionKey) else { return [] }
        return (try? decoder.decode([DisruptionEvent].self, from: data)) ?? []
    }

    private func saveDisruptions(_ events: [DisruptionEvent]) {
        if let data = try? encoder.encode(events) {
            UserDefaults.standard.set(data, forKey: disruptionKey)
        }
    }
}
