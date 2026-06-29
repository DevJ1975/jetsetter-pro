// File: JetSetter ProTests/WalletModelTests.swift
// Unit tests for WalletItem grouping/status logic (pure, deterministic — no network).

import Testing
import Foundation
@testable import JetSetter_Pro

struct WalletModelTests {

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    /// Builds a wallet item whose computed `status` is controlled via its dates.
    private func item(trip: UUID?, date: Date, endDate: Date? = nil) -> WalletItem {
        var raw: [String: String] = [:]
        if let endDate {
            raw["end_date"] = ISO8601DateFormatter().string(from: endDate)
        }
        return WalletItem(tripId: trip, itemType: .boardingPass,
                          title: "Test", date: date, rawData: raw)
    }

    @Test func statusDerivesFromDates() {
        let now = Date()
        let upcoming = item(trip: nil, date: now.addingTimeInterval(Self.day))
        let active   = item(trip: nil, date: now.addingTimeInterval(-Self.hour),
                            endDate: now.addingTimeInterval(Self.day))
        let completed = item(trip: nil, date: now.addingTimeInterval(-Self.day))

        #expect(upcoming.status == .upcoming)
        #expect(active.status == .active)
        #expect(completed.status == .completed)
    }

    @Test func groupsItemsByTrip() {
        let tripA = UUID()
        let tripB = UUID()
        let now = Date()

        let items: [WalletItem] = [
            item(trip: tripA, date: now.addingTimeInterval(-Self.day)),                 // completed
            item(trip: tripA, date: now.addingTimeInterval(Self.day)),                  // upcoming
            item(trip: tripB, date: now.addingTimeInterval(-Self.day)),                 // completed
            item(trip: nil,   date: now.addingTimeInterval(Self.day))                   // unassigned
        ]

        let grouped = items.groupedByTrip
        #expect(grouped.count == 3)

        let tripAGroup = grouped.first { $0.tripId == tripA }
        #expect(tripAGroup?.items.count == 2)

        let nilGroup = grouped.first { $0.tripId == nil }
        #expect(nilGroup?.items.count == 1)
    }

    /// A trip containing an active item must sort ahead of trips with none.
    @Test func activeTripsSortFirst() {
        let activeTrip = UUID()
        let doneTrip = UUID()
        let now = Date()

        let items: [WalletItem] = [
            item(trip: doneTrip,   date: now.addingTimeInterval(-2 * Self.day)),        // completed
            item(trip: activeTrip, date: now.addingTimeInterval(-Self.hour),
                 endDate: now.addingTimeInterval(Self.day))                             // active
        ]

        let grouped = items.groupedByTrip
        #expect(grouped.first?.tripId == activeTrip)
    }
}
