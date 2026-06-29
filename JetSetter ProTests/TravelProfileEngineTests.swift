// File: JetSetter ProTests/TravelProfileEngineTests.swift
// Unit tests for the pure learning aggregation (no I/O, deterministic).

import Testing
import Foundation
@testable import JetSetter_Pro

struct TravelProfileEngineTests {

    private static let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * Self.day) }

    // MARK: - Seat parsing

    @Test func seatColumnMapping() {
        #expect(TravelProfileEngine.seatColumn("14A") == .window)
        #expect(TravelProfileEngine.seatColumn("2F") == .window)
        #expect(TravelProfileEngine.seatColumn("14C") == .aisle)
        #expect(TravelProfileEngine.seatColumn("9D") == .aisle)
        #expect(TravelProfileEngine.seatColumn("3B") == .middle)
        #expect(TravelProfileEngine.seatColumn("12e") == .middle)   // lowercase
        #expect(TravelProfileEngine.seatColumn("") == .unknown)
        #expect(TravelProfileEngine.seatColumn("42") == .unknown)   // no letter
    }

    @Test func seatZoneMapping() {
        #expect(TravelProfileEngine.seatZone("3A") == .forward)
        #expect(TravelProfileEngine.seatZone("10C") == .forward)
        #expect(TravelProfileEngine.seatZone("11A") == .mid)
        #expect(TravelProfileEngine.seatZone("25F") == .mid)
        #expect(TravelProfileEngine.seatZone("26A") == .rear)
        #expect(TravelProfileEngine.seatZone("A") == .unknown)      // no row
    }

    // MARK: - Seat preference

    @Test func seatPreferenceDominantColumn() {
        let seats = [("2A", now), ("4A", now), ("8F", now), ("14C", now)].map { (code: $0.0, date: $0.1) }
        let pref = TravelProfileEngine.seatPreference(from: seats, now: now)
        #expect(pref?.column == .window)        // 3 window vs 1 aisle
        #expect(pref?.zone == .forward)
        #expect((pref?.confidence ?? 0) > 0.7)
        #expect(pref?.sampleSize == 4)
    }

    @Test func seatPreferenceRecencyWeighted() {
        // One recent aisle vs one very old window — recent should win.
        let seats = [("3C", daysAgo(1)), ("3A", daysAgo(800))].map { (code: $0.0, date: $0.1) }
        let pref = TravelProfileEngine.seatPreference(from: seats, now: now)
        #expect(pref?.column == .aisle)
    }

    @Test func seatPreferenceNilWhenNoParseable() {
        let seats = [("42", now), ("", now)].map { (code: $0.0, date: $0.1) }
        #expect(TravelProfileEngine.seatPreference(from: seats, now: now) == nil)
    }

    // MARK: - Ranking

    @Test func weightedRankingOrderAndLimit() {
        let entries = [("AA", now), ("AA", now), ("AA", now), ("DL", now), ("UA", now)]
        let ranked = TravelProfileEngine.weightedRanking(entries, now: now, limit: 2)
        #expect(ranked.count == 2)
        #expect(ranked.first?.value == "AA")
        #expect(ranked.first?.count == 3)
    }

    @Test func weightedRankingIgnoresBlanks() {
        let entries = [("  ", now), ("AA", now)]
        let ranked = TravelProfileEngine.weightedRanking(entries, now: now)
        #expect(ranked.count == 1)
        #expect(ranked.first?.value == "AA")
    }

    // MARK: - Recency weight

    @Test func recencyWeightDecays() {
        let fresh = TravelProfileEngine.recencyWeight(now, now: now)
        let halfLife = TravelProfileEngine.recencyWeight(daysAgo(TravelProfileEngine.halfLifeDays), now: now)
        #expect(abs(fresh - 1.0) < 0.0001)
        #expect(abs(halfLife - 0.5) < 0.01)
    }

    // MARK: - Spend

    @Test func spendStatsAverageAndExcludesMileage() {
        let expenses = [
            Expense(amount: 40, currency: "USD", category: .food, merchant: "A", date: now),
            Expense(amount: 60, currency: "USD", category: .food, merchant: "B", date: now),
            Expense(amount: 999, currency: "USD", category: .mileage, merchant: "Drive", date: now, mileageDistance: 100)
        ]
        let stats = TravelProfileEngine.spendStats(from: expenses)
        let food = stats.first { $0.category == ExpenseCategory.food.displayName }
        #expect(food?.average == 50)
        #expect(food?.count == 2)
        #expect(!stats.contains { $0.category == ExpenseCategory.mileage.displayName })
    }

    // MARK: - Build

    @Test func buildProfileEmptyForNoInput() {
        #expect(TravelProfileEngine.buildProfile(signals: [], now: now).isEmpty)
    }

    @Test func buildProfileCombinesSignals() {
        let signals = [
            TravelSignal(kind: .seatChosen, value: "3A", timestamp: now),
            TravelSignal(kind: .seatChosen, value: "5A", timestamp: now),
            TravelSignal(kind: .flightFlown, value: "AA", attributes: ["airline": "AA"], timestamp: now),
            TravelSignal(kind: .loyaltyAdded, value: "Hilton", attributes: ["brandKind": "HOTEL"], timestamp: now) // case-insensitive
        ]
        let p = TravelProfileEngine.buildProfile(signals: signals, now: now)
        #expect(p.typicalSeat?.column == .window)
        #expect(p.topAirlines.first?.value == "AA")
        #expect(p.topHotelBrands.contains { $0.value == "Hilton" })   // brandKind matched case-insensitively
        #expect(!p.isEmpty)
    }
}
