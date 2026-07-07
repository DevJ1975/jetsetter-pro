// File: Core/Services/IRIS/IRISContext.swift
//
// Builds a compact, live snapshot of the traveler's current trip, upcoming
// flights, and expenses, injected into IRIS's instructions so she can ground
// answers in real data without first making a tool round-trip. Reads the same
// UserDefaults stores the IRIS tools use.

import Foundation

enum IRISContext {

    private static let tripsKey    = "jetsetter_trips"
    private static let expensesKey = "jetsetter_expenses"

    /// A short, plain-text summary for IRIS's system instructions. Empty when
    /// there's nothing on file (so the persona stays lean for new users).
    static func currentSnapshot() -> String {
        let trips = loadTrips()
        let expenses = loadExpenses()
        guard !trips.isEmpty || !expenses.isEmpty else { return "" }

        let now = Date()
        var lines: [String] = []

        if let trip = activeOrNextTrip(in: trips, now: now) {
            let range = "\(shortDate(trip.startDate)) – \(shortDate(trip.endDate))"
            let label = (trip.startDate <= now && now <= trip.endDate) ? "Current trip" : "Next trip"
            lines.append("• \(label): \(trip.name) — \(trip.destination) (\(range))")

            let upcoming = trip.items
                .filter { ($0.endDate ?? $0.startDate) >= now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(3)
            for item in upcoming {
                var detail = "    \(emoji(item.type)) \(item.title) — \(shortDateTime(item.startDate))"
                if let loc = item.location, !loc.isEmpty { detail += " · \(loc)" }
                if let notes = item.notes, !notes.isEmpty { detail += " · \(notes)" }
                lines.append(detail)
            }
        }

        // The next flight may be on a different trip than the active one.
        if let flight = nextFlight(in: trips, now: now) {
            var detail = "• Next flight: \(flight.title) — \(shortDateTime(flight.startDate))"
            if let loc = flight.location, !loc.isEmpty { detail += " (\(loc))" }
            if let notes = flight.notes, !notes.isEmpty { detail += " · \(notes)" }
            lines.append(detail)
        }

        if !expenses.isEmpty {
            lines.append(expenseSummary(expenses))
        }

        guard !lines.isEmpty else { return "" }
        return "Live traveler data (use this to ground answers; don't invent details):\n"
            + lines.joined(separator: "\n")
    }

    // MARK: - Selection

    private static func activeOrNextTrip(in trips: [Trip], now: Date) -> Trip? {
        if let active = trips.first(where: { $0.startDate <= now && now <= $0.endDate }) {
            return active
        }
        if let next = trips.filter({ $0.startDate > now }).min(by: { $0.startDate < $1.startDate }) {
            return next
        }
        // Fall back to the most recently ended trip.
        return trips.max(by: { $0.endDate < $1.endDate })
    }

    private static func nextFlight(in trips: [Trip], now: Date) -> ItineraryItem? {
        trips.flatMap { $0.items }
            .filter { $0.type == .flight && $0.startDate >= now }
            .min(by: { $0.startDate < $1.startDate })
    }

    private static func expenseSummary(_ expenses: [Expense]) -> String {
        var totals: [String: Double] = [:]
        for e in expenses { totals[e.currency, default: 0] += e.amount }
        let dominant = totals.max(by: { $0.value < $1.value })
        let totalText = dominant.map { "\(formatAmount($0.value)) \($0.key)" } ?? ""
        return "• Expenses logged: \(expenses.count)\(totalText.isEmpty ? "" : " totaling \(totalText)")"
    }

    // MARK: - Loading

    private static func loadTrips() -> [Trip] { decode([Trip].self, key: tripsKey) ?? [] }
    private static func loadExpenses() -> [Expense] { decode([Expense].self, key: expensesKey) ?? [] }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONCoding.iso8601Decoder.decode(T.self, from: data)
    }

    // MARK: - Formatting

    private static func emoji(_ type: ItineraryItemType) -> String {
        switch type {
        case .flight:     return "✈"
        case .hotel:      return "🏨"
        case .activity:   return "⭐"
        case .transport:  return "🚗"
        case .restaurant: return "🍽"
        }
    }

    private static func shortDate(_ date: Date) -> String {
        AppDateFormatters.mediumDate.string(from: date)
    }

    private static func shortDateTime(_ date: Date) -> String {
        AppDateFormatters.mediumDateShortTime.string(from: date)
    }

    private static func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
