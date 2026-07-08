// File: Core/Services/Financial/FinancialStore.swift
//
// Thin `actor` wrapper over `FinancialDatabase` — the async API that the app's
// `@MainActor`-isolated view-models (ExpenseViewModel, CurrencyExpenseViewModel) use
// to read/write financial data off the main thread. It adds no state of its own; it
// just forwards to the thread-safe SQLite engine, giving callers an `await`-friendly
// surface that keeps SQLite work off the UI.
//
// Nonisolated synchronous callers that cannot `await` (App Intents' `perform`, IRIS
// context/triggers, `TravelStore`) talk to `FinancialDatabase.shared` directly — both
// paths funnel through the same serial queue inside the engine, so there is a single
// SQLite handle and no data race.
//
// Financial data persisted here is DEVICE-ONLY and never syncs to Supabase.

import Foundation

actor FinancialStore {

    static let shared = FinancialStore()

    private let database: FinancialDatabase

    init(database: FinancialDatabase = .shared) {
        self.database = database
    }

    // MARK: - Expenses

    func allExpenses() -> [Expense] { database.allExpenses() }

    func upsert(_ expense: Expense) { database.upsertExpense(expense) }

    func delete(expenseID: UUID) { database.deleteExpense(id: expenseID) }

    func replaceAllExpenses(_ expenses: [Expense]) { database.replaceAllExpenses(expenses) }

    // MARK: - Currency expenses

    func currencyExpenses(tripID: UUID) -> [CurrencyExpense] {
        database.allCurrencyExpenses(tripId: tripID)
    }

    func upsert(currencyExpense: CurrencyExpense) {
        database.upsertCurrencyExpense(currencyExpense)
    }

    func delete(currencyExpenseID: UUID) { database.deleteCurrencyExpense(id: currencyExpenseID) }

    func replaceCurrencyExpenses(_ expenses: [CurrencyExpense], tripID: UUID) {
        database.replaceCurrencyExpenses(expenses, tripId: tripID)
    }

    // MARK: - Receipts

    func saveReceipt(_ receipt: Receipt) { database.upsertReceipt(receipt) }

    func receipt(forExpenseID expenseID: UUID) -> Receipt? {
        database.receipt(forExpenseID: expenseID)
    }

    // MARK: - Account deletion / clear

    func wipeAll() { database.wipeAllFinancialData() }
}
