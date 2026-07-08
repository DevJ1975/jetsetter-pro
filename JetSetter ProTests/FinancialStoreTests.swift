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
        let expenseID = UUID()
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
        let expenseID = UUID()
        ctx.db.upsertReceipt(Receipt(expenseID: expenseID, ocrText: "text only", imageData: nil))
        let loaded = ctx.db.receipt(forExpenseID: expenseID)
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
