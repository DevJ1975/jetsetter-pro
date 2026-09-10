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
    /// Profile fields this run filled because they were blank, with the value
    /// written. Teardown clears a field only when it still holds that exact
    /// value, so anything the traveler typed afterwards survives.
    var filledDisplayName: String?
    var filledHomeAirport: String?
    var completedOnboarding = false
    /// True when this run started the Live Activity, so teardown never ends one
    /// belonging to the traveler's own flight.
    var startedLiveActivity = false

    struct SeededFlight: Codable, Equatable {
        var flightNumber: String
        var departure: Date
    }

    var isEmpty: Bool {
        tripIDs.isEmpty && walletItemIDs.isEmpty && bagIDs.isEmpty && expenseIDs.isEmpty
    }

    init() {}

    /// Tolerant decoding. A ledger written by an earlier build must still decode,
    /// or the records it lists become unremovable: teardown would read an empty
    /// ledger and silently leave the seeded trip, bags and tickets behind.
    /// `filledDisplayName` and `filledHomeAirport` were Booleans before they
    /// carried the written value, so both shapes are accepted.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tripIDs = (try? c.decode([UUID].self, forKey: .tripIDs)) ?? []
        walletItemIDs = (try? c.decode([UUID].self, forKey: .walletItemIDs)) ?? []
        bagIDs = (try? c.decode([UUID].self, forKey: .bagIDs)) ?? []
        expenseIDs = (try? c.decode([UUID].self, forKey: .expenseIDs)) ?? []
        seededFlights = (try? c.decode([SeededFlight].self, forKey: .seededFlights)) ?? []
        completedOnboarding = (try? c.decode(Bool.self, forKey: .completedOnboarding)) ?? false
        startedLiveActivity = (try? c.decode(Bool.self, forKey: .startedLiveActivity)) ?? false

        func legacyString(_ key: CodingKeys, fallback: String) -> String? {
            if let value = try? c.decode(String.self, forKey: key) { return value }
            if let flag = try? c.decode(Bool.self, forKey: key) { return flag ? fallback : nil }
            return nil
        }
        filledDisplayName = legacyString(.filledDisplayName, fallback: DemoDataSeeder.passengerName)
        filledHomeAirport = legacyString(.filledHomeAirport, fallback: DemoDataSeeder.homeAirport)
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
        if !ledger.isEmpty { await removeSeededData() }
        ledger = await DemoDataSeeder.seed()
        isOn = true
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    /// Removes every record this seeder created and turns demo mode off.
    static func disable() async {
        await removeSeededData()
        isOn = false
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    /// Rewinds the demo to its opening state, which is what a presenter wants
    /// between two run-throughs.
    static func reseed() async {
        await removeSeededData()
        ledger = await DemoDataSeeder.seed()
        isOn = true
        NotificationCenter.default.post(name: .jetSetterDemoDataChanged, object: nil)
    }

    // MARK: - Teardown

    private static func removeSeededData() async {
        let led = ledger
        guard !led.isEmpty || led.filledDisplayName != nil || led.filledHomeAirport != nil
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
            // Awaited, so the mirror is clean before this returns; a fired-and-
            // forgotten delete let a later wallet load restore the demo items.
            for id in led.walletItemIDs { await LocalDataService.shared.deleteWalletItem(id: id) }
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

        // Cancel the local notifications the seeded flights scheduled. Adding a
        // trip schedules them through TravelNotificationScheduler, and that
        // rescheduler only ever adds, so a removed trip leaves its alerts behind
        // to fire days later on a tester's lock screen.
        for flight in led.seededFlights {
            await NotificationManager.shared.cancelFlightAlerts(flightNumber: flight.flightNumber)
        }

        // Only clear a profile field this run filled AND that still holds the
        // value this run wrote.
        let prefs = UserPreferences.shared
        if let written = led.filledDisplayName, prefs.displayName == written { prefs.displayName = "" }
        if let written = led.filledHomeAirport, prefs.homeAirport == written { prefs.homeAirport = "" }
        if led.completedOnboarding { prefs.hasCompletedOnboarding = false }

        if led.startedLiveActivity { FlightLiveActivityService.shared.end() }
        ledger = DemoSeedLedger()
        // No notification here on purpose. Teardown is a step inside enable()
        // and reseed() as well as a whole operation on its own; posting from
        // both places raced two reloads, and the pre-seed one could land last.
        // Each public entry point posts exactly once when it has finished.
    }
}

extension Notification.Name {
    /// Posted after demo data is seeded or removed, so open screens reload.
    static let jetSetterDemoDataChanged = Notification.Name("jetSetterDemoDataChanged")
}

#endif
