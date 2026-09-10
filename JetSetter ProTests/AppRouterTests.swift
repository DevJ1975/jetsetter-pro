// File: JetSetter ProTests/AppRouterTests.swift
// Unit tests for the shared persistence facade and the App Intents routing
// layer: flight-number parsing, TravelStore round-trips, AppRouter navigation,
// and the Siri screen enum → destination mapping. The TravelStore round-trip
// snapshots and restores UserDefaults so it doesn't pollute the host.

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite(.serialized)
struct AppRouterTests {

    // MARK: - Flight number extraction

    @Test func extractsFlightNumberFromTitles() {
        #expect(TravelStore.extractFlightNumber(from: "Flight AA169 to Tokyo") == "AA169")
        #expect(TravelStore.extractFlightNumber(from: "AA 169") == "AA169")
        #expect(TravelStore.extractFlightNumber(from: "UA55") == "UA55")
        #expect(TravelStore.extractFlightNumber(from: "Dinner reservation") == nil)
    }

    // MARK: - TravelStore round-trip (with cleanup)

    @Test func appendsExpenseAndTripThenReadsBack() {
        let expensesKey = TravelStore.expensesKey
        let tripsKey = TravelStore.tripsKey
        let savedExpenses = UserDefaults.standard.data(forKey: expensesKey)
        let savedTrips = UserDefaults.standard.data(forKey: tripsKey)
        defer {
            UserDefaults.standard.set(savedExpenses, forKey: expensesKey)
            UserDefaults.standard.set(savedTrips, forKey: tripsKey)
        }

        UserDefaults.standard.removeObject(forKey: expensesKey)
        UserDefaults.standard.removeObject(forKey: tripsKey)

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

    // MARK: - Router

    @Test func navigatingToTabRootsSwitchesTabs() {
        let router = AppRouter.shared
        router.navigate(to: .expenses)
        #expect(router.selectedTab == .expenses)
        router.navigate(to: .assistant)
        #expect(router.selectedTab == .assistant)
        router.navigate(to: .home)
        #expect(router.selectedTab == .home)
    }

    @Test func navigatingToFeatureScreensPresentsSheets() {
        let router = AppRouter.shared
        router.navigate(to: .packingList)
        #expect(router.presentedSheet == .packingList)
        router.navigate(to: .currency)
        #expect(router.presentedSheet == .currency)
        router.presentedSheet = nil
    }

    // MARK: - Siri screen enum

    @Test func siriScreenEnumMapsToEveryDestination() {
        #expect(AppScreen.expenses.destination == .expenses)
        #expect(AppScreen.flightTracker.destination == .flightTracker)
        #expect(AppScreen.packingList.destination == .packingList)
        #expect(AppScreen.disruption.destination == .disruption)
    }

    // MARK: - Suggestions carry a real destination

    @Test func suggestionKindsAllHaveIcons() {
        for kind in TravelSuggestion.Kind.allCases {
            #expect(!kind.systemImage.isEmpty)
        }
    }
}
