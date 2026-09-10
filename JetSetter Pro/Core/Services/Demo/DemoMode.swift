// File: Core/Services/Demo/DemoMode.swift
//
// Explicit, opt-in sample data for investor and beta demos.
//
// COMPILED ONLY INTO Debug AND Beta. Both configurations define DEMO_ENABLED;
// Release does not, and App Store builds archive from Release. Nothing in this
// file — or the data it writes — can reach a paying customer or App Review.
//
// The rule this replaces: the previous demo mode scattered `MockDataService
// .isEnabled` branches through 22 files, so fake gates and mock policies were
// indistinguishable from real data. This version never branches a production
// code path. It writes ordinary records through the ordinary stores, records
// every id it created in a ledger, and removes exactly those on teardown.

#if DEMO_ENABLED

import Foundation

/// Ledger of everything a seed run created, so `disable()` can undo precisely
/// that and never touch the traveler's own records.
struct DemoSeedLedger: Codable, Equatable {
    var tripIDs: [UUID] = []
    var walletItemIDs: [UUID] = []
    var bagIDs: [UUID] = []
    var expenseIDs: [UUID] = []
    /// Flights this seed created. Their check-in flags are cleared on teardown
    /// so a reseed always starts from "not checked in".
    var seededFlights: [SeededFlight] = []
    /// Profile fields this run filled because they were blank. Only these are
    /// cleared again on teardown, so a real profile is never overwritten.
    var filledDisplayName = false
    var filledHomeAirport = false
    var completedOnboarding = false

    struct SeededFlight: Codable, Equatable {
        var flightNumber: String
        var departure: Date
    }

    var isEmpty: Bool {
        tripIDs.isEmpty && walletItemIDs.isEmpty && bagIDs.isEmpty && expenseIDs.isEmpty
    }
}

@MainActor
enum DemoMode {

    /// Whether demo data is currently loaded. Defaults to false: a developer or
    /// tester who never asks for it never sees it.
    static let storageKey = "demo_mode_enabled"
    private static let ledgerKey = "demo_seed_ledger"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    /// The ledger from the current seed run, empty when nothing is seeded.
    static var ledger: DemoSeedLedger {
        get {
            guard let data = UserDefaults.standard.data(forKey: ledgerKey),
                  let value = try? JSONCoding.iso8601Decoder.decode(DemoSeedLedger.self, from: data)
            else { return DemoSeedLedger() }
            return value
        }
        set {
            guard let data = try? JSONCoding.iso8601Encoder.encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: ledgerKey)
        }
    }

    // MARK: - Switching

    /// Seeds the demo dataset. Safe to call twice: an existing seed is removed
    /// first, so the traveler always gets one clean copy rather than duplicates.
    static func enable() async {
        if !ledger.isEmpty { removeSeededData() }
        ledger = DemoDataSeeder.seed()
        isOn = true
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    /// Removes every record this seeder created and turns demo mode off.
    static func disable() {
        removeSeededData()
        isOn = false
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    /// Rewinds the demo to its opening state, which is what a presenter wants
    /// between two run-throughs.
    static func reseed() async {
        removeSeededData()
        ledger = DemoDataSeeder.seed()
        isOn = true
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    // MARK: - Teardown

    private static func removeSeededData() {
        let led = ledger
        guard !led.isEmpty || led.filledDisplayName || led.filledHomeAirport
                || led.completedOnboarding || !led.seededFlights.isEmpty else {
            ledger = DemoSeedLedger()
            return
        }

        // Trips, by id, against the authoritative array.
        if !led.tripIDs.isEmpty {
            let ids = Set(led.tripIDs)
            _ = TravelStore.mutateTrips { $0.removeAll { ids.contains($0.id) } }
            // Per-trip derived caches keyed by trip id.
            let defaults = UserDefaults.standard
            for id in led.tripIDs {
                let key = id.uuidString
                defaults.removeObject(forKey: "jetsetter_offline_kit_\(key)")
                defaults.removeObject(forKey: "jetsetter_currency_expenses_\(key)")
                defaults.removeObject(forKey: "packing_list_v1_\(key)")
                defaults.removeObject(forKey: "supabase_local_packing_\(key)")
            }
        }

        // Wallet items, from both stores that hold them.
        if !led.walletItemIDs.isEmpty {
            let ids = Set(led.walletItemIDs)
            var items: [WalletItem] = CodableDefaults.load([WalletItem].self, forKey: "jetsetter_wallet_items") ?? []
            items.removeAll { ids.contains($0.id) }
            try? CodableDefaults.save(items, forKey: "jetsetter_wallet_items")
            let removed = led.walletItemIDs
            Task { for id in removed { await LocalDataService.shared.deleteWalletItem(id: id) } }
        }

        // Bags.
        if !led.bagIDs.isEmpty {
            let ids = Set(led.bagIDs)
            var bags = BagStore.load()
            bags.removeAll { ids.contains($0.id) }
            BagStore.save(bags)
            NotificationCenter.default.post(name: .jetSetterBagsActivated, object: nil)
        }

        // Expenses.
        if !led.expenseIDs.isEmpty {
            TravelStore.removeExpenses(withIDs: Set(led.expenseIDs))
        }

        // Check-in flags for the flights this seed created.
        for flight in led.seededFlights {
            CheckInStateStore.markNotCheckedIn(flightNumber: flight.flightNumber, departure: flight.departure)
        }

        // Only clear profile fields this run filled in.
        let prefs = UserPreferences.shared
        if led.filledDisplayName { prefs.displayName = "" }
        if led.filledHomeAirport { prefs.homeAirport = "" }
        if led.completedOnboarding { prefs.hasCompletedOnboarding = false }

        FlightLiveActivityService.shared.end()
        ledger = DemoSeedLedger()
    }
}

extension Notification.Name {
    /// Posted after demo data is seeded or removed, so open screens reload.
    static let jetSetterDemoDataChanged = Notification.Name("jetSetterDemoDataChanged")
}

#endif
