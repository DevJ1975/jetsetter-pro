// File: Core/Services/BookingItineraryMapper.swift
//
// Pure mapping from a backend `BackendBooking` to the app's own records: one
// `ItineraryItem` and one boarding-pass `WalletItem` per flight segment, placed
// in the trip that overlaps the flights (or a new one). No I/O, so the rules
// are testable and `BookingSync` stays thin.
//
// Idempotence is the whole point. Syncing runs on every launch and foreground,
// so the same booking arrives again and again. Every record gets an id derived
// deterministically from `duffel_order_id` + slice + segment, which makes an
// upsert by id exact: syncing twice never duplicates, and a schedule change
// from the airline updates the existing record in place.
//
// Merges keep what the traveler or other features added since: a seat assigned
// at check-in, a gate, an imported barcode, a calendar link and edited notes
// survive a re-sync. Only the fields the airline owns (times, flight number,
// airports, PNR) are overwritten.
//
// One deliberate difference from "an item per slice": a slice with a connection
// becomes one item per SEGMENT. Flight tracking, check-in, disruption alerts
// and boarding passes are all per flight number, and a connecting slice has two.
// A nonstop slice, the common case, is identical either way.

import Foundation
import CryptoKit

nonisolated enum BookingItineraryMapper {

    /// `source` marker written to wallet `rawData`.
    static let walletSource = "jetsetter_backend"

    // MARK: - Identity

    /// A stable UUID from a seed string (SHA-256, laid out as an RFC 4122
    /// version-5-style UUID). Same seed, same id, on every device and launch.
    static func stableUUID(_ seed: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// The key a booking is synced under: its Duffel order id, or the backend
    /// booking id for the rare confirmed booking that lacks one.
    static func syncKey(for booking: BackendBooking) -> String {
        if let order = booking.duffelOrderId?.trimmingCharacters(in: .whitespacesAndNewlines), !order.isEmpty {
            return order
        }
        return "booking-\(booking.id)"
    }

    static func itineraryItemID(key: String, slice: Int, segment: Int) -> UUID {
        stableUUID("jetsetter.itinerary.\(key).\(slice).\(segment)")
    }

    static func walletItemID(key: String, slice: Int, segment: Int) -> UUID {
        stableUUID("jetsetter.wallet.\(key).\(slice).\(segment)")
    }

    // MARK: - Legs

    /// One flight segment with its absolute times resolved.
    nonisolated struct Leg: Equatable, Sendable {
        let sliceIndex: Int
        let segmentIndex: Int
        let segment: BackendSegment
        let departure: Date
        let arrival: Date
    }

    /// Every segment whose times can be read. A segment with an unreadable time
    /// is skipped rather than given an invented one.
    static func legs(for booking: BackendBooking) -> [Leg] {
        var result: [Leg] = []
        for (sliceIndex, slice) in booking.slices.enumerated() {
            for (segmentIndex, segment) in slice.segments.enumerated() {
                // The airport's zone; the device zone is the app-wide fallback
                // for an airport nobody knows the zone of.
                let originZone = BackendDates.zone(for: segment.origin) ?? .current
                let destinationZone = BackendDates.zone(for: segment.destination) ?? .current
                guard let departure = BackendDates.instant(segment.departingAt, in: originZone),
                      let arrival = BackendDates.instant(segment.arrivingAt, in: destinationZone)
                else { continue }
                result.append(Leg(sliceIndex: sliceIndex, segmentIndex: segmentIndex,
                                  segment: segment, departure: departure, arrival: arrival))
            }
        }
        return result
    }

    // MARK: - Itinerary items

    static func itineraryItems(for booking: BackendBooking) -> [ItineraryItem] {
        let key = syncKey(for: booking)
        let resolved = legs(for: booking)
        let soleSeat = singlePassengerSeat(booking)
        let cost = BackendMoney.double(booking.totalAmount).map {
            BookingCost(amount: $0, currencyCode: booking.totalCurrency.uppercased())
        }

        return resolved.enumerated().map { position, leg in
            let carrier = leg.segment.marketingCarrier ?? booking.airline
            let carrierName = FlightDisplay.nonEmpty(carrier?.name)
            let number = FlightDisplay.flightNumber(leg.segment, fallbackCarrier: booking.airline)
            var title = [carrierName, number].compactMap { $0 }.joined(separator: " ")
            if title.isEmpty { title = "Flight" }
            if booking.testMode { title += " (TEST)" }

            let origin = leg.segment.origin.iataCode
            let destination = leg.segment.destination.iataCode
            return ItineraryItem(
                id: itineraryItemID(key: key, slice: leg.sliceIndex, segment: leg.segmentIndex),
                title: title,
                type: .flight,
                startDate: leg.departure,
                endDate: leg.arrival,
                location: "\(origin) → \(destination)",
                notes: booking.testMode ? "Test booking. Not a real reservation." : nil,
                confirmationNumber: FlightDisplay.nonEmpty(booking.bookingReference),
                bookingProvider: carrierName,
                // The order total sits on the first leg only, so it isn't
                // counted once per segment.
                cost: position == 0 ? cost : nil,
                flightDetails: FlightBookingDetails(
                    airline: carrierName,
                    flightNumber: number,
                    originCode: origin,
                    destinationCode: destination,
                    seat: soleSeat,
                    cabinClass: nil,
                    terminal: FlightDisplay.nonEmpty(leg.segment.originTerminal),
                    gate: nil
                )
            )
        }
    }

    /// The seat, only when exactly one passenger has one. With several
    /// travelers a single seat label would be someone's guess.
    private static func singlePassengerSeat(_ booking: BackendBooking) -> String? {
        guard booking.passengers.count == 1 else { return nil }
        return FlightDisplay.nonEmpty(booking.passengers[0].seat)
    }

    /// Fresh airline-owned fields win; everything the traveler or another
    /// feature added to the existing item is kept.
    static func merge(existing: ItineraryItem, with fresh: ItineraryItem) -> ItineraryItem {
        var merged = existing
        merged.title = fresh.title
        merged.startDate = fresh.startDate
        merged.endDate = fresh.endDate
        merged.location = fresh.location
        merged.confirmationNumber = fresh.confirmationNumber ?? existing.confirmationNumber
        merged.bookingProvider = fresh.bookingProvider ?? existing.bookingProvider
        merged.cost = fresh.cost ?? existing.cost
        if (existing.notes ?? "").isEmpty { merged.notes = fresh.notes }

        var details = existing.flightDetails ?? FlightBookingDetails()
        let new = fresh.flightDetails ?? FlightBookingDetails()
        details.airline = new.airline ?? details.airline
        details.flightNumber = new.flightNumber ?? details.flightNumber
        details.originCode = new.originCode ?? details.originCode
        details.destinationCode = new.destinationCode ?? details.destinationCode
        details.terminal = new.terminal ?? details.terminal
        details.seat = details.seat ?? new.seat
        merged.flightDetails = details == FlightBookingDetails() ? nil : details
        return merged
    }

    // MARK: - Trips

    /// Result of placing a booking into the trip list.
    nonisolated struct Placement: Equatable, Sendable {
        let tripID: UUID
        let createdTrip: Bool
        /// False when every record was already present and identical, which is
        /// the normal result of a repeat sync. Callers skip the write (and the
        /// change notification that reschedules alerts) in that case.
        let changed: Bool
    }

    /// Adds or updates the booking's flights in `trips`:
    ///  1. a trip that already holds any of these items gets them updated;
    ///  2. otherwise the trip whose dates overlap the flights (most overlap
    ///     wins) receives them;
    ///  3. otherwise a new "Trip to <city>" is created.
    /// Returns where the flights went, or nil when the booking has no readable
    /// flights.
    @discardableResult
    static func apply(
        _ booking: BackendBooking, to trips: inout [Trip],
        calendar: Calendar = .current
    ) -> Placement? {
        let items = itineraryItems(for: booking)
        guard let firstStart = items.map(\.startDate).min() else { return nil }
        let lastEnd = items.map { $0.endDate ?? $0.startDate }.max() ?? firstStart
        let ids = Set(items.map(\.id))

        /// Adds or merges `items`; true when anything actually changed.
        func place(_ items: [ItineraryItem], in trip: inout Trip) -> Bool {
            var changed = false
            for item in items {
                if let index = trip.items.firstIndex(where: { $0.id == item.id }) {
                    let merged = merge(existing: trip.items[index], with: item)
                    if !isSame(merged, trip.items[index]) {
                        trip.items[index] = merged
                        changed = true
                    }
                } else {
                    trip.items.append(item)
                    changed = true
                }
            }
            return changed
        }

        if let index = trips.firstIndex(where: { trip in trip.items.contains { ids.contains($0.id) } }) {
            let changed = place(items, in: &trips[index])
            return Placement(tripID: trips[index].id, createdTrip: false, changed: changed)
        }

        let windowStart = calendar.startOfDay(for: firstStart)
        let windowEnd = endOfDay(lastEnd, calendar: calendar)
        var best: (index: Int, overlap: TimeInterval)?
        for (index, trip) in trips.enumerated() {
            let tripStart = calendar.startOfDay(for: trip.startDate)
            let tripEnd = endOfDay(trip.endDate, calendar: calendar)
            let overlap = min(windowEnd, tripEnd).timeIntervalSince(max(windowStart, tripStart))
            if overlap >= 0, overlap > (best?.overlap ?? -1) { best = (index, overlap) }
        }
        if let best {
            let changed = place(items, in: &trips[best.index])
            return Placement(tripID: trips[best.index].id, createdTrip: false, changed: changed)
        }

        let destination = tripDestination(for: booking)
        var trip = Trip(
            name: "Trip to \(destination)",
            destination: destination,
            startDate: windowStart,
            endDate: calendar.startOfDay(for: lastEnd)
        )
        _ = place(items, in: &trip)
        trips.append(trip)
        return Placement(tripID: trip.id, createdTrip: true, changed: true)
    }

    /// Field-for-field equality of two items. `ItineraryItem` isn't
    /// `Equatable`, so compare the encoded form (stable key order).
    private static func isSame(_ a: ItineraryItem, _ b: ItineraryItem) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        guard let x = try? encoder.encode(a), let y = try? encoder.encode(b) else { return false }
        return x == y
    }

    /// Removes the flights a cancelled booking added. Records the traveler made
    /// themselves are untouched because only the deterministic ids are matched.
    @discardableResult
    static func remove(_ booking: BackendBooking, from trips: inout [Trip]) -> Bool {
        let ids = Set(itineraryItems(for: booking).map(\.id))
        guard !ids.isEmpty else { return false }
        var changed = false
        for index in trips.indices {
            let before = trips[index].items.count
            trips[index].items.removeAll { ids.contains($0.id) }
            changed = changed || trips[index].items.count != before
        }
        return changed
    }

    /// The city to name a new trip after. A round trip (the last slice returns
    /// to where the first began) is a trip TO the first slice's destination.
    static func tripDestination(for booking: BackendBooking) -> String {
        guard let first = booking.slices.first, let last = booking.slices.last else { return "your destination" }
        let target = (booking.slices.count > 1 && last.destination.iataCode == first.origin.iataCode)
            ? first.destination : last.destination
        return FlightDisplay.nonEmpty(target.cityName) ?? target.iataCode
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
    }

    // MARK: - Wallet items

    static func walletItems(for booking: BackendBooking, tripID: UUID?) -> [WalletItem] {
        let key = syncKey(for: booking)
        let soleSeat = singlePassengerSeat(booking)
        let formatter = ISO8601DateFormatter()

        return legs(for: booking).map { leg in
            let carrier = leg.segment.marketingCarrier ?? booking.airline
            let number = FlightDisplay.flightNumber(leg.segment, fallbackCarrier: booking.airline)
            let origin = leg.segment.origin.iataCode
            let destination = leg.segment.destination.iataCode

            var raw: [String: String] = [
                "departure_airport": origin,
                "arrival_airport": destination,
                "end_date": formatter.string(from: leg.arrival),
                "duffel_order_id": booking.duffelOrderId ?? "",
                "booking_reference": booking.bookingReference ?? "",
                "source": walletSource
            ]
            if let name = FlightDisplay.nonEmpty(carrier?.name) { raw["airline"] = name }
            if let number { raw["flight_number"] = number }
            if let code = FlightDisplay.nonEmpty(carrier?.iataCode) { raw["iata_code"] = code.uppercased() }
            if let terminal = FlightDisplay.nonEmpty(leg.segment.originTerminal) { raw["terminal"] = terminal }
            if let soleSeat { raw["seat_number"] = soleSeat }
            // Never write an empty marker value the disruption code might read.
            raw = raw.filter { !$0.value.isEmpty }

            var title = [number, "\(origin) → \(destination)"].compactMap { $0 }.joined(separator: " · ")
            if booking.testMode { title += " (TEST)" }

            return WalletItem(
                id: walletItemID(key: key, slice: leg.sliceIndex, segment: leg.segmentIndex),
                tripId: tripID,
                itemType: .boardingPass,
                title: title,
                confirmationNumber: FlightDisplay.nonEmpty(booking.bookingReference),
                date: leg.departure,
                rawData: raw
            )
        }
    }

    /// Fresh airline-owned fields win; a gate, barcode, seat or boarding group
    /// added since (by check-in or a pass import) is kept.
    static func merge(existing: WalletItem, with fresh: WalletItem) -> WalletItem {
        var merged = existing
        merged.title = fresh.title
        merged.date = fresh.date
        merged.confirmationNumber = fresh.confirmationNumber ?? existing.confirmationNumber
        merged.tripId = fresh.tripId ?? existing.tripId
        merged.rawData = existing.rawData.merging(fresh.rawData) { _, new in new }
        return merged
    }
}
