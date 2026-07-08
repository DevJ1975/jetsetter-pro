// File: JetSetter ProTests/FinancialStoreTests.swift
//
// Unit tests for the on-device SQLite financial store: CRUD for expenses,
// currency-tracker expenses, and receipts (OCR text + image bytes), plus the
// first-launch UserDefaults→SQLite migration round-trip.
//
// Every test uses its own temporary database file and a private UserDefaults suite,
// so nothing touches the shared store or the host environment, and tests are safe to
// run in parallel.

import Testing
import Foundation
@testable import JetSetter_Pro

struct FinancialStoreTests {

    // MARK: - Fixtures

    /// A throwaway on-disk SQLite database + isolated UserDefaults suite. Migration is
    /// off by default so CRUD tests start from a clean, empty schema.
    private static func makeDatabase(autoMigrate: Bool = false)
        -> (db: FinancialDatabase, defaults: UserDefaults, flagKey: String, cleanup: () -> Void) {
        let unique = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("financial-test-\(unique).sqlite")
        let suiteName = "financial.tests.\(unique)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let flagKey = "migrated_flag_\(unique)"
        let db = FinancialDatabase(url: url, defaults: defaults,
                                   migrationFlagKey: flagKey, autoMigrate: autoMigrate)
        let cleanup: () -> Void = {
            try? FileManager.default.removeItem(at: url)
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (db, defaults, flagKey, cleanup)
    }

    private func sampleExpense(merchant: String = "Nobu", amount: Double = 42.50) -> Expense {
        Expense(amount: amount, currency: "USD", category: .food, merchant: merchant,
                date: Date(timeIntervalSince1970: 1_700_000_000), notes: "Team dinner",
                receiptText: "NOBU\nTOTAL 42.50")
    }

    private func sampleCurrencyExpense(tripId: UUID) -> CurrencyExpense {
        CurrencyExpense(id: UUID(), tripId: tripId, amount: 4_800, currency: "JPY",
                        convertedAmount: 32.45, homeCurrency: "USD",
                        category: .food, description: "Sushi lunch",
                        date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Expense CRUD

    @Test func insertsAndReadsBackExpense() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)

        let loaded = ctx.db.allExpenses()
        #expect(loaded.count == 1)
        let round = loaded.first
        #expect(round?.id == expense.id)
        #expect(round?.amount == 42.50)
        #expect(round?.currency == "USD")
        #expect(round?.category == .food)
        #expect(round?.merchant == "Nobu")
        #expect(round?.notes == "Team dinner")
        #expect(round?.receiptText == "NOBU\nTOTAL 42.50")
        // Dates round-trip through a REAL column — allow sub-second tolerance.
        #expect(abs((round?.date.timeIntervalSince1970 ?? 0) - 1_700_000_000) < 1)
    }

    @Test func upsertReplacesSameID() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        var expense = sampleExpense(amount: 10)
        ctx.db.upsertExpense(expense)
        expense.amount = 99   // same id, new amount
        ctx.db.upsertExpense(expense)

        let loaded = ctx.db.allExpenses()
        #expect(loaded.count == 1)
        #expect(loaded.first?.amount == 99)
    }

    @Test func deletesExpense() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)
        ctx.db.deleteExpense(id: expense.id)
        #expect(ctx.db.allExpenses().isEmpty)
    }

    @Test func replaceAllExpensesSwapsTheWholeSet() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        ctx.db.upsertExpense(sampleExpense(merchant: "Old"))
        let fresh = [sampleExpense(merchant: "A"), sampleExpense(merchant: "B")]
        ctx.db.replaceAllExpenses(fresh)

        let merchants = Set(ctx.db.allExpenses().map(\.merchant))
        #expect(merchants == ["A", "B"])
    }

    @Test func preservesMileageFields() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let mileage = Expense(amount: 21, currency: "USD", category: .mileage,
                              merchant: "Airport → Hotel", mileageDistance: 30)
        ctx.db.upsertExpense(mileage)
        let round = ctx.db.allExpenses().first
        #expect(round?.category == .mileage)
        #expect(round?.mileageDistance == 30)
        #expect(round?.notes == nil)   // NULL round-trips as nil
    }

    // MARK: - Currency expense CRUD

    @Test func currencyExpensesAreScopedByTrip() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let tripA = UUID(); let tripB = UUID()
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: tripA))
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: tripA))
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: tripB))

        #expect(ctx.db.allCurrencyExpenses(tripId: tripA).count == 2)
        #expect(ctx.db.allCurrencyExpenses(tripId: tripB).count == 1)
    }

    @Test func currencyExpenseRoundTripsAllFields() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let trip = UUID()
        let expense = sampleCurrencyExpense(tripId: trip)
        ctx.db.upsertCurrencyExpense(expense)

        let round = ctx.db.allCurrencyExpenses(tripId: trip).first
        #expect(round?.id == expense.id)
        #expect(round?.amount == 4_800)
        #expect(round?.currency == "JPY")
        #expect(round?.convertedAmount == 32.45)
        #expect(round?.homeCurrency == "USD")
        #expect(round?.category == .food)
        #expect(round?.description == "Sushi lunch")
    }

    @Test func replaceCurrencyExpensesOnlyAffectsOneTrip() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let tripA = UUID(); let tripB = UUID()
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: tripA))
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: tripB))

        ctx.db.replaceCurrencyExpenses([sampleCurrencyExpense(tripId: tripA)], tripId: tripA)
        #expect(ctx.db.allCurrencyExpenses(tripId: tripA).count == 1)
        #expect(ctx.db.allCurrencyExpenses(tripId: tripB).count == 1)   // untouched
    }

    // MARK: - Receipts (OCR text + image bytes)

    @Test func receiptRoundTripsTextAndImageBytes() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        // Receipts FK-reference a real expense (ON DELETE CASCADE, foreign_keys ON), so
        // the parent must exist before the receipt is inserted.
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)
        let expenseID = expense.id
        let bytes = Data([0xFF, 0xD8, 0xFF, 0x00, 0x11, 0x22])   // fake JPEG-ish blob
        let receipt = Receipt(expenseID: expenseID, ocrText: "TOTAL 42.50", imageData: bytes)
        ctx.db.upsertReceipt(receipt)

        let loaded = ctx.db.receipt(forExpenseID: expenseID)
        #expect(loaded?.ocrText == "TOTAL 42.50")
        #expect(loaded?.imageData == bytes)
        #expect(loaded?.expenseID == expenseID)
    }

    @Test func receiptImageMayBeAbsent() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)
        ctx.db.upsertReceipt(Receipt(expenseID: expense.id, ocrText: "text only", imageData: nil))
        let loaded = ctx.db.receipt(forExpenseID: expense.id)
        #expect(loaded?.ocrText == "text only")
        #expect(loaded?.imageData == nil)
    }

    // MARK: - Wipe

    @Test func wipeClearsEveryTable() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let trip = UUID()
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)
        ctx.db.upsertCurrencyExpense(sampleCurrencyExpense(tripId: trip))
        ctx.db.upsertReceipt(Receipt(expenseID: expense.id, ocrText: "x"))

        ctx.db.wipeAllFinancialData()

        #expect(ctx.db.allExpenses().isEmpty)
        #expect(ctx.db.allCurrencyExpenses(tripId: trip).isEmpty)
        #expect(ctx.db.receipt(forExpenseID: expense.id) == nil)
    }

    // MARK: - Migration round-trip (UserDefaults → SQLite)

    @Test func migratesExpensesAndCurrencyFromUserDefaults() throws {
        let ctx = Self.makeDatabase(autoMigrate: false); defer { ctx.cleanup() }

        // Seed legacy blobs the way the old view-models wrote them:
        //  - expenses: default (numeric) date strategy (old ExpenseViewModel)
        //  - currency: ISO-8601 (old CurrencyExpenseViewModel)
        let legacyExpenses = [sampleExpense(merchant: "Legacy Cafe"),
                              sampleExpense(merchant: "Legacy Hotel", amount: 200)]
        let expenseData = try JSONEncoder().encode(legacyExpenses)
        ctx.defaults.set(expenseData, forKey: FinancialDatabase.legacyExpensesKey)

        let trip = UUID()
        let isoEncoder = JSONEncoder(); isoEncoder.dateEncodingStrategy = .iso8601
        let currencyData = try isoEncoder.encode([sampleCurrencyExpense(tripId: trip)])
        let currencyKey = FinancialDatabase.legacyCurrencyPrefix + trip.uuidString
        ctx.defaults.set(currencyData, forKey: currencyKey)

        // Run the migration.
        ctx.db.migrateFromUserDefaultsIfNeeded()

        // Data landed in SQLite…
        #expect(ctx.db.allExpenses().count == 2)
        #expect(Set(ctx.db.allExpenses().map(\.merchant)) == ["Legacy Cafe", "Legacy Hotel"])
        #expect(ctx.db.allCurrencyExpenses(tripId: trip).count == 1)

        // …and the legacy UserDefaults keys were removed (we stop writing them).
        #expect(ctx.defaults.data(forKey: FinancialDatabase.legacyExpensesKey) == nil)
        #expect(ctx.defaults.data(forKey: currencyKey) == nil)
        #expect(ctx.defaults.bool(forKey: ctx.flagKey) == true)
    }

    @Test func migrationIsIdempotent() throws {
        let ctx = Self.makeDatabase(autoMigrate: false); defer { ctx.cleanup() }
        let data = try JSONEncoder().encode([sampleExpense(merchant: "Once")])
        ctx.defaults.set(data, forKey: FinancialDatabase.legacyExpensesKey)

        ctx.db.migrateFromUserDefaultsIfNeeded()
        // A second run must not re-import (the flag is set, and the source key is gone).
        ctx.defaults.set(data, forKey: FinancialDatabase.legacyExpensesKey)   // re-seed to prove no-op
        ctx.db.migrateFromUserDefaultsIfNeeded()

        #expect(ctx.db.allExpenses().count == 1)
        // The re-seeded key is left untouched because migration short-circuits on the flag.
        #expect(ctx.defaults.data(forKey: FinancialDatabase.legacyExpensesKey) != nil)
    }

    @Test func migrationNoOpsWhenNothingToMigrate() {
        let ctx = Self.makeDatabase(autoMigrate: false); defer { ctx.cleanup() }
        ctx.db.migrateFromUserDefaultsIfNeeded()
        #expect(ctx.db.allExpenses().isEmpty)
        #expect(ctx.defaults.bool(forKey: ctx.flagKey) == true)   // still marks itself done
    }

    // MARK: - Migration safety (BUG 1 — never lose the only copy)

    /// The legacy blob is present but undecodable (corrupt / foreign format), so
    /// `decodeExpenses` yields []. The migration must treat that as a FAILURE: it must
    /// NOT delete the source key and must NOT set the one-time flag, so a later launch
    /// retries instead of the history being lost forever.
    @Test func migrationPreservesKeyAndFlagOnDecodeFailure() {
        let ctx = Self.makeDatabase(autoMigrate: false); defer { ctx.cleanup() }
        ctx.defaults.set(Data([0x00, 0x01, 0x02, 0x03]),
                         forKey: FinancialDatabase.legacyExpensesKey)

        ctx.db.migrateFromUserDefaultsIfNeeded()

        #expect(ctx.db.allExpenses().isEmpty)                                        // nothing imported
        #expect(ctx.defaults.data(forKey: FinancialDatabase.legacyExpensesKey) != nil)  // key kept
        #expect(ctx.defaults.bool(forKey: ctx.flagKey) == false)                     // flag NOT set → retries
    }

    /// A currency key that fails to decode must not sink the whole run silently: its key
    /// is preserved and the flag stays unset, even though the (valid) expenses key
    /// migrated and was removed.
    @Test func migrationKeepsUndecodableCurrencyKeyAndBlocksFlag() throws {
        let ctx = Self.makeDatabase(autoMigrate: false); defer { ctx.cleanup() }

        let expenseData = try JSONEncoder().encode([sampleExpense(merchant: "Good")])
        ctx.defaults.set(expenseData, forKey: FinancialDatabase.legacyExpensesKey)

        let badCurrencyKey = FinancialDatabase.legacyCurrencyPrefix + UUID().uuidString
        ctx.defaults.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: badCurrencyKey)

        ctx.db.migrateFromUserDefaultsIfNeeded()

        // The good expenses key migrated and was removed…
        #expect(ctx.db.allExpenses().count == 1)
        #expect(ctx.defaults.data(forKey: FinancialDatabase.legacyExpensesKey) == nil)
        // …but the undecodable currency key is preserved and the flag is withheld.
        #expect(ctx.defaults.data(forKey: badCurrencyKey) != nil)
        #expect(ctx.defaults.bool(forKey: ctx.flagKey) == false)
    }

    /// When the database never opened (`db == nil`), there is nowhere safe to move the
    /// data, so the migration must abort WITHOUT deleting the legacy key or setting the
    /// flag — preserving the user's only copy for a later retry.
    @Test func migrationAbortsWithoutTouchingDataWhenDatabaseUnavailable() throws {
        // A URL whose parent directory doesn't exist → sqlite3_open_v2 fails → db == nil.
        let unique = UUID().uuidString
        let badURL = URL(fileURLWithPath: "/jetsetter-nonexistent-\(unique)/sub/financial.sqlite")
        let suiteName = "financial.tests.baddb.\(unique)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let flagKey = "migrated_flag_baddb_\(unique)"
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expenseData = try JSONEncoder().encode([sampleExpense(merchant: "Precious")])
        defaults.set(expenseData, forKey: FinancialDatabase.legacyExpensesKey)

        let db = FinancialDatabase(url: badURL, defaults: defaults,
                                   migrationFlagKey: flagKey, autoMigrate: false)
        db.migrateFromUserDefaultsIfNeeded()

        #expect(defaults.data(forKey: FinancialDatabase.legacyExpensesKey) != nil)   // key kept
        #expect(defaults.bool(forKey: flagKey) == false)                            // flag NOT set
    }

    // MARK: - Demo seed guard (BUG 2 — never clobber real/migrated data)

    @Test func isExpensesEmptyReflectsTableState() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        #expect(ctx.db.isExpensesEmpty() == true)
        ctx.db.upsertExpense(sampleExpense())
        #expect(ctx.db.isExpensesEmpty() == false)
    }

    /// Replicates `MockDataService`'s guarded demo seed: with real (freshly-migrated)
    /// expenses already present, the empty-check is false, so the demo `replaceAllExpenses`
    /// never runs and the real data survives.
    @Test func demoSeedDoesNotClobberExistingExpenses() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        ctx.db.upsertExpense(sampleExpense(merchant: "Real Migrated"))

        let demo = [sampleExpense(merchant: "Demo A"), sampleExpense(merchant: "Demo B")]
        if ctx.db.isExpensesEmpty() {              // false → skipped
            ctx.db.replaceAllExpenses(demo)
        }

        #expect(Set(ctx.db.allExpenses().map(\.merchant)) == ["Real Migrated"])
    }

    @Test func demoSeedRunsIntoAnEmptyTable() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let demo = [sampleExpense(merchant: "Demo A")]
        if ctx.db.isExpensesEmpty() {              // true → seeds
            ctx.db.replaceAllExpenses(demo)
        }
        #expect(ctx.db.allExpenses().map(\.merchant) == ["Demo A"])
    }

    // MARK: - Granular writes preserve out-of-band data (BUG 3)

    /// A single add via the granular writer must not disturb a row inserted out-of-band
    /// (e.g. by Siri/IRIS) that the on-screen view-model never observed. The old
    /// whole-array `replaceAllExpenses([A, C])` would have dropped B.
    @Test func granularAddPreservesOutOfBandWrites() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        ctx.db.upsertExpense(sampleExpense(merchant: "A"))   // in the VM's snapshot
        ctx.db.upsertExpense(sampleExpense(merchant: "B"))   // written out-of-band
        ctx.db.upsertExpense(sampleExpense(merchant: "C"))   // VM adds this granularly

        #expect(Set(ctx.db.allExpenses().map(\.merchant)) == ["A", "B", "C"])
    }

    @Test func granularDeleteLeavesOtherRowsIntact() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let a = sampleExpense(merchant: "A")
        let b = sampleExpense(merchant: "B")
        ctx.db.upsertExpense(a)
        ctx.db.upsertExpense(b)

        ctx.db.deleteExpense(id: a.id)
        #expect(ctx.db.allExpenses().map(\.merchant) == ["B"])
    }

    /// Same guarantee for currency-tracker expenses: granular add/delete on one item
    /// doesn't wipe a sibling written out-of-band for the same trip.
    @Test func granularCurrencyWritesPreserveOutOfBandData() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let trip = UUID()
        let a = sampleCurrencyExpense(tripId: trip)
        let b = sampleCurrencyExpense(tripId: trip)   // out-of-band sibling
        ctx.db.upsertCurrencyExpense(a)
        ctx.db.upsertCurrencyExpense(b)

        ctx.db.deleteCurrencyExpense(id: a.id)
        #expect(ctx.db.allCurrencyExpenses(tripId: trip).map(\.id) == [b.id])
    }

    // MARK: - Receipt image cleanup (BUG 4 — no orphaned BLOBs)

    /// Deleting an expense must remove its receipt row (and image bytes) — via the FK
    /// ON DELETE CASCADE and the explicit belt-and-suspenders purge.
    @Test func deletingExpenseRemovesItsReceipt() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let expense = sampleExpense()
        ctx.db.upsertExpense(expense)
        ctx.db.upsertReceipt(Receipt(expenseID: expense.id, ocrText: "TOTAL 9.99",
                                     imageData: Data([0xFF, 0xD8, 0xFF, 0x01])))
        #expect(ctx.db.receipt(forExpenseID: expense.id) != nil)

        ctx.db.deleteExpense(id: expense.id)
        #expect(ctx.db.receipt(forExpenseID: expense.id) == nil)   // no orphan
    }

    /// A bulk replace (demo seed / migration) wipes the expenses table; the receipts it
    /// referenced — and their image BLOBs — must go with it.
    @Test func replaceAllExpensesRemovesOrphanedReceipts() {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let expense = sampleExpense(merchant: "Has Receipt")
        ctx.db.upsertExpense(expense)
        ctx.db.upsertReceipt(Receipt(expenseID: expense.id, ocrText: "x",
                                     imageData: Data([0x01, 0x02])))

        ctx.db.replaceAllExpenses([sampleExpense(merchant: "Fresh")])

        #expect(ctx.db.receipt(forExpenseID: expense.id) == nil)
    }

    // MARK: - Actor wrapper

    @Test func financialStoreActorForwardsToDatabase() async {
        let ctx = Self.makeDatabase(); defer { ctx.cleanup() }
        let store = FinancialStore(database: ctx.db)
        let expense = sampleExpense(merchant: "Via Actor")
        await store.upsert(expense)

        let loaded = await store.allExpenses()
        #expect(loaded.count == 1)
        #expect(loaded.first?.merchant == "Via Actor")

        await store.delete(expenseID: expense.id)
        #expect(await store.allExpenses().isEmpty)
    }
}
