// File: JetSetter ProTests/DemoModeTests.swift
//
// Demo mode is only compiled into Debug and Beta, so these tests compile with
// it. They cover the two things that would actually hurt: a boarding pass whose
// barcode does not parse, and a teardown that deletes the traveler's own data.

#if DEMO_ENABLED

import Testing
import Foundation
@testable import JetSetter_Pro

@Suite(.serialized)
@MainActor
struct DemoModeTests {

    /// Snapshots every store the seeder touches and puts it back afterwards, so
    /// a test run leaves the host app exactly as it found it.
    private struct StoreSnapshot {
        let trips: [Trip]
        let bags: [Bag]
        let expenses: Data?
        let wallet: Data?
        let ledger: Data?
        /// The LocalDataService mirror, which the seeder also writes.
        let walletMirror: Data?
        let demoOn: Bool
        let displayName: String
        let homeAirport: String
        let onboarded: Bool

        static func capture() -> StoreSnapshot {
            let defaults = UserDefaults.standard
            let prefs = UserPreferences.shared
            return StoreSnapshot(
                trips: TravelStore.loadTrips(),
                bags: BagStore.load(),
                expenses: defaults.data(forKey: TravelStore.expensesKey),
                wallet: defaults.data(forKey: "jetsetter_wallet_items"),
                ledger: defaults.data(forKey: "demo_seed_ledger"),
                walletMirror: defaults.data(forKey: "supabase_local_wallet_items"),
                demoOn: DemoMode.isOn,
                displayName: prefs.displayName,
                homeAirport: prefs.homeAirport,
                onboarded: prefs.hasCompletedOnboarding
            )
        }

        func restore() {
            let defaults = UserDefaults.standard
            TravelStore.saveTrips(trips)
            BagStore.save(bags)
            defaults.set(expenses, forKey: TravelStore.expensesKey)
            defaults.set(wallet, forKey: "jetsetter_wallet_items")
            defaults.set(ledger, forKey: "demo_seed_ledger")
            defaults.set(walletMirror, forKey: "supabase_local_wallet_items")
            DemoMode.isOn = demoOn
            let prefs = UserPreferences.shared
            prefs.displayName = displayName
            prefs.homeAirport = homeAirport
            prefs.hasCompletedOnboarding = onboarded
        }
    }

    // MARK: - Boarding pass

    @Test func demoBoardingPassBarcodeParsesBackAsARealPass() throws {
        let departure = Date(timeIntervalSince1970: 1_789_000_000)
        let payload = DemoDataSeeder.boardingPassBarcode(departure: departure)

        // The mandatory BCBP section is fixed-width; anything shorter means the
        // offsets the parser reads would run off the end.
        #expect(payload.hasPrefix("M1"))
        #expect(payload.count >= 52)

        let pass = try #require(BCBPParser.parse(payload), "the demo pass must parse as a real BCBP payload")
        #expect(pass.originCode == "LAS")
        #expect(pass.destinationCode == "ATL")
        #expect(pass.airlineCode == "DL")
        #expect(pass.flightNumber == "DL 1423")
        #expect(pass.seat == "3A")
        #expect(pass.pnr?.trimmingCharacters(in: .whitespaces) == "JX7QF2")
    }

    // MARK: - Seeding

    @Test func seedingBuildsTheLasToAtlantaTripWithBagsLoadingAtLas() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        let now = Date()
        let ledger = await DemoDataSeeder.seed(now: now)

        // Trip and its outbound flight.
        let trip = TravelStore.loadTrips().first { ledger.tripIDs.contains($0.id) }
        let seeded = try? #require(trip)
        #expect(seeded?.destination == "Atlanta, GA")

        let flight = seeded?.items.first { $0.type == .flight }
        #expect(flight?.location == "LAS → ATL")
        #expect(TravelStore.extractFlightNumber(from: flight?.title ?? "") == "DL1423")
        // Gate and terminal must survive the notes-parsing convention the rest
        // of the app reads them back through.
        #expect(flight?.notes?.contains("Gate C22") == true)
        #expect(flight?.notes?.contains("Terminal 1") == true)
        #expect(flight?.flightDetails?.seat == "3A")

        // Departure sits inside the check-in window and the gate-closing window,
        // which is what makes the demo screen interesting.
        let minutesOut = (flight?.startDate.timeIntervalSince(now) ?? 0) / 60
        #expect(minutesOut > 0 && minutesOut <= 90)

        // Bags: the whole LAS ground pipeline, including one mid-load.
        let bags = BagStore.load().filter { ledger.bagIDs.contains($0.id) }
        #expect(bags.count == 4)
        let loading = bags.first { $0.status == .loading }
        #expect(loading != nil)
        #expect(loading?.lastLocation?.contains("LAS") == true)
        #expect(loading?.scanHistory.contains { $0.scanType == .loaderTransfer } == true)
        #expect(bags.allSatisfy { ($0.lastLocation ?? "").contains("LAS") || ($0.lastLocation ?? "").contains("DL1423") })
        #expect(bags.contains { $0.status == .onAircraft })

        // Tickets, with a scannable pass.
        let wallet: [WalletItem] = CodableDefaults.load([WalletItem].self, forKey: "jetsetter_wallet_items") ?? []
        let seededWallet = wallet.filter { ledger.walletItemIDs.contains($0.id) }
        #expect(seededWallet.count == 5)
        let pass = seededWallet.first { $0.itemType == .boardingPass }
        #expect(pass?.gate == "C22")
        #expect(pass?.seatNumber == "3A")
        #expect(pass?.rawData["barcode_message"]?.isEmpty == false)
        #expect(Set(seededWallet.map(\.itemType)).count == 5)
    }

    /// The defect this covers: teardown used to trust a boolean, so a name typed
    /// between enabling and disabling demo mode was blanked.
    @Test func teardownKeepsAProfileTypedAfterSeeding() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        let prefs = UserPreferences.shared
        prefs.displayName = ""
        prefs.homeAirport = ""

        DemoMode.ledger = await DemoDataSeeder.seed()
        #expect(prefs.displayName == DemoDataSeeder.passengerName)

        // The traveler fills in their own details while the demo is on.
        prefs.displayName = "Sarah Chen"
        prefs.homeAirport = "SFO"

        await DemoMode.disable()
        #expect(prefs.displayName == "Sarah Chen")
        #expect(prefs.homeAirport == "SFO")
    }

    /// Teardown must clear the value it wrote when the traveler left it alone.
    @Test func teardownClearsTheProfileItFilledIn() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        let prefs = UserPreferences.shared
        prefs.displayName = ""
        prefs.homeAirport = ""

        DemoMode.ledger = await DemoDataSeeder.seed()
        await DemoMode.disable()
        #expect(prefs.displayName.isEmpty)
        #expect(prefs.homeAirport.isEmpty)
    }

    /// Seeded tickets must reach both wallet stores, or a load from the other
    /// one wipes them mid-demo.
    @Test func seededWalletItemsReachBothStores() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        let ledger = await DemoDataSeeder.seed()
        DemoMode.ledger = ledger

        let ids = Set(ledger.walletItemIDs)
        let cached: [WalletItem] = CodableDefaults.load([WalletItem].self, forKey: "jetsetter_wallet_items") ?? []
        #expect(ids.isSubset(of: Set(cached.map(\.id))))

        let mirrored = await LocalDataService.shared.fetchWalletItems()
        #expect(ids.isSubset(of: Set(mirrored.map(\.id))))

        await DemoMode.disable()
        let mirroredAfter = await LocalDataService.shared.fetchWalletItems()
        #expect(Set(mirroredAfter.map(\.id)).isDisjoint(with: ids))
    }

    // MARK: - Teardown

    @Test func teardownRemovesOnlyTheSeededRecords() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        // A trip, a bag and an expense that belong to the traveler, not the demo.
        let ownTrip = Trip(name: "My Own Trip", destination: "Lisbon",
                           startDate: Date(timeIntervalSince1970: 2_100_000_000),
                           endDate: Date(timeIntervalSince1970: 2_100_600_000))
        TravelStore.appendTrip(ownTrip)
        let ownBag = Bag(nickname: "My Own Bag", status: .checkedIn)
        BagStore.save(BagStore.load() + [ownBag])
        let ownExpense = Expense(amount: 9.99, category: .food, merchant: "My Own Cafe")
        TravelStore.appendExpense(ownExpense)

        let ledger = await DemoDataSeeder.seed()
        DemoMode.ledger = ledger
        #expect(!ledger.isEmpty)

        await DemoMode.disable()

        // Every seeded record is gone.
        let tripsAfter = TravelStore.loadTrips()
        #expect(!tripsAfter.contains { ledger.tripIDs.contains($0.id) })
        let bagsAfter = BagStore.load()
        #expect(!bagsAfter.contains { ledger.bagIDs.contains($0.id) })
        let expensesAfter = TravelStore.loadExpenses()
        #expect(!expensesAfter.contains { ledger.expenseIDs.contains($0.id) })
        let walletAfter: [WalletItem] = CodableDefaults.load([WalletItem].self, forKey: "jetsetter_wallet_items") ?? []
        #expect(!walletAfter.contains { ledger.walletItemIDs.contains($0.id) })

        // And the traveler's own records are untouched.
        #expect(tripsAfter.contains { $0.id == ownTrip.id })
        #expect(bagsAfter.contains { $0.id == ownBag.id })
        #expect(expensesAfter.contains { $0.id == ownExpense.id })

        #expect(DemoMode.isOn == false)
        #expect(DemoMode.ledger.isEmpty)
    }

    @Test func seedingTwiceDoesNotDuplicateTheTrip() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        await DemoMode.enable()
        let firstLedger = DemoMode.ledger
        await DemoMode.enable()
        let secondLedger = DemoMode.ledger

        let atlantaTrips = TravelStore.loadTrips().filter { $0.name == "Atlanta Board Meeting" }
        #expect(atlantaTrips.count == 1)
        #expect(firstLedger.tripIDs != secondLedger.tripIDs)

        let bags = BagStore.load().filter { $0.flightNumber == "DL1423" }
        #expect(bags.count == 4)
    }

    // MARK: - Profile

    @Test func seedingDoesNotOverwriteARealProfile() async {
        let snapshot = StoreSnapshot.capture()
        defer { snapshot.restore() }

        let prefs = UserPreferences.shared
        prefs.displayName = "Jamil"
        prefs.homeAirport = "SFO"

        let ledger = await DemoDataSeeder.seed()
        DemoMode.ledger = ledger

        #expect(prefs.displayName == "Jamil")
        #expect(prefs.homeAirport == "SFO")
        #expect(ledger.filledDisplayName == nil)
        #expect(ledger.filledHomeAirport == nil)

        await DemoMode.disable()
        #expect(prefs.displayName == "Jamil")
        #expect(prefs.homeAirport == "SFO")
    }
}

#endif
