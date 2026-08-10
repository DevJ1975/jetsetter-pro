// File: JetSetter ProTests/IRISActionTests.swift
// Unit tests for the IRIS agentic action layer: shared TravelStore persistence,
// flight-number / date parsing, and the navigation tool's screen resolution.
// Pure-logic where possible; the TravelStore round-trip snapshots and restores the
// trips UserDefaults key and the SQLite expenses table so it doesn't pollute the
// host environment (expenses are now financial data in on-device SQLite).

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite(.serialized)
struct IRISActionTests {

    // MARK: - Flight number extraction

    @Test func extractsFlightNumberFromTitles() {
        #expect(TravelStore.extractFlightNumber(from: "Flight AA169 to Tokyo") == "AA169")
        #expect(TravelStore.extractFlightNumber(from: "AA 169") == "AA169")
        #expect(TravelStore.extractFlightNumber(from: "UA55") == "UA55")
        #expect(TravelStore.extractFlightNumber(from: "Dinner reservation") == nil)
    }

    // MARK: - TravelStore round-trip (with cleanup)

    @Test func appendsExpenseAndTripThenReadsBack() {
        let tripsKey = TravelStore.tripsKey
        let savedTrips = UserDefaults.standard.data(forKey: tripsKey)
        // Expenses are financial data in on-device SQLite now — snapshot + restore that
        // table (not UserDefaults) so the round-trip doesn't clobber real data.
        let savedExpenses = FinancialDatabase.shared.allExpenses()
        defer {
            UserDefaults.standard.set(savedTrips, forKey: tripsKey)
            FinancialDatabase.shared.replaceAllExpenses(savedExpenses)
        }

        UserDefaults.standard.removeObject(forKey: tripsKey)
        FinancialDatabase.shared.replaceAllExpenses([])   // start from an empty table

        TravelStore.appendExpense(Expense(amount: 12.5, currency: "USD", category: .food, merchant: "Cafe"))
        let expenses = TravelStore.loadExpenses()
        #expect(expenses.count == 1)
        #expect(expenses.first?.merchant == "Cafe")

        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let end = start.addingTimeInterval(86_400 * 3)
        TravelStore.appendTrip(Trip(name: "Test", destination: "Tokyo", startDate: start, endDate: end))
        let trips = TravelStore.loadTrips()
        #expect(trips.contains { $0.destination == "Tokyo" })
    }

    // MARK: - Date parsing (iOS 26 tool)

    @available(iOS 26.0, *)
    @Test func parsesIsoAndPlainDates() {
        #expect(AddTripTool.parseDate("2026-08-15") != nil)
        #expect(AddTripTool.parseDate(" 2026-08-15 ") != nil)
        #expect(AddTripTool.parseDate("not-a-date") == nil)
    }

    // MARK: - Screen resolution (iOS 26 tool)

    @available(iOS 26.0, *)
    @Test func resolvesScreenSynonyms() {
        #expect(OpenScreenTool.resolve("open my expenses") == .expenses)
        #expect(OpenScreenTool.resolve("check in") == .checkIn)
        #expect(OpenScreenTool.resolve("flight tracker") == .flightTracker)
        #expect(OpenScreenTool.resolve("packing list") == .packingList)
        #expect(OpenScreenTool.resolve("order me a pizza") == nil)
    }
}
