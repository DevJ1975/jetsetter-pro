// File: Features/CurrencyTracker/CurrencyExpenseViewModel.swift
// Currency converter + per-trip expense tracker.

import SwiftUI

@MainActor
@Observable
final class CurrencyExpenseViewModel {

    private(set) var expenses: [CurrencyExpense] = []
    private(set) var exchangeRates: ExchangeRates? = nil
    private(set) var budgetSummary: BudgetSummary? = nil
    private(set) var isLoading = false
    var errorMessage: String? = nil

    var converterInput: String = ""

    /// Direction the converter reads in. `.homeToDestination` treats the input
    /// as an amount in the home currency and outputs the destination amount;
    /// `.destinationToHome` is the reciprocal ("what is this local price worth
    /// back home?"), which is what travellers most often need.
    enum ConversionDirection {
        case homeToDestination
        case destinationToHome
    }

    var conversionDirection: ConversionDirection = .homeToDestination

    /// The currency code the converter input is expressed in.
    var inputCurrency: String {
        conversionDirection == .homeToDestination ? homeCurrency : destinationCurrency
    }

    /// The currency code the converted output is expressed in.
    var outputCurrency: String {
        conversionDirection == .homeToDestination ? destinationCurrency : homeCurrency
    }

    /// Flips the conversion direction so users can convert either way.
    func toggleDirection() {
        conversionDirection = conversionDirection == .homeToDestination
            ? .destinationToHome
            : .homeToDestination
    }

    var convertedAmount: Double? {
        guard let amount = Self.parseDecimal(converterInput),
              let rates = exchangeRates else { return nil }
        switch conversionDirection {
        case .homeToDestination:
            return rates.convert(amount: amount, to: destinationCurrency)
        case .destinationToHome:
            return convertToHome(amount: amount, from: destinationCurrency)
        }
    }

    /// Locale-aware decimal parsing. `Double(String)` only accepts a '.' decimal
    /// separator, which breaks input in comma-decimal locales. This tries the
    /// user's locale first, then falls back to normalizing ',' to '.'.
    static func parseDecimal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        // Fallback: treat ',' as the decimal separator and strip grouping.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    let trip: Trip
    let homeCurrency: String
    let destinationCurrency: String
    var budget: Double?

    /// On-device, encrypted SQLite store. Currency-tracker expenses are FINANCIAL
    /// data — device-only, never synced to Supabase.
    private let store: FinancialStore

    // `nonisolated(unsafe)` so the observer can be removed from the nonisolated
    // `deinit`. Safe: written once in `init`, read once in `deinit`, and
    // `NotificationCenter.removeObserver` is thread-safe. (Same pattern as ItineraryViewModel.)
    nonisolated(unsafe) private var expensesChangedObserver: NSObjectProtocol?

    init(trip: Trip, homeCurrency: String, destinationCurrency: String, budget: Double? = nil,
         store: FinancialStore = .shared) {
        self.trip = trip
        self.homeCurrency = homeCurrency
        self.destinationCurrency = destinationCurrency
        self.budget = budget
        self.store = store
        // Expenses load asynchronously from SQLite in `load()` (invoked from the
        // view's `.task`), so `init` never blocks the main thread on disk I/O.
        updateSummary()
        // Reload this trip's expenses whenever any writer mutates the financial store
        // out-of-band, so our in-memory copy never goes stale and a later save can't
        // clobber their change.
        expensesChangedObserver = NotificationCenter.default.addObserver(
            forName: .jetSetterExpensesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reloadExpensesFromStore() }
        }
    }

    deinit {
        if let expensesChangedObserver {
            NotificationCenter.default.removeObserver(expensesChangedObserver)
        }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Load persisted per-trip expenses from the on-device SQLite store first, so
        // they're on screen even if the rates call below fails.
        expenses = await store.currencyExpenses(tripID: trip.id)
        updateSummary()

        if let rates = await ExchangeRateService.shared.rates(for: homeCurrency) {
            exchangeRates = rates
            errorMessage = nil
            // Backfill convertedAmount for any expenses that were entered offline
            // (e.g. added before rates were ever available), then recompute the
            // summary so previously-uncounted expenses are reflected.
            backfillConversions()
            updateSummary()
        } else {
            errorMessage = "Couldn't load live exchange rates. Tap to retry."
        }
    }

    /// Re-attempts a rates load (used by the error banner's retry affordance).
    func retry() async {
        await load()
    }

    /// Re-reads just this trip's expenses from the on-device store (no network). Fired
    /// from the `.jetSetterExpensesChanged` observer so an out-of-band write is picked up
    /// without a full `load()` (which would also re-hit the rates API).
    func reloadExpensesFromStore() async {
        expenses = await store.currencyExpenses(tripID: trip.id)
        updateSummary()
    }

    // MARK: - Expenses

    func addExpense(amount: Double, category: SpendCategory, description: String) {
        let converted = convertToHome(amount: amount, from: destinationCurrency)
        let expense = CurrencyExpense(
            id: UUID(),
            tripId: trip.id,
            amount: amount,
            currency: destinationCurrency,
            convertedAmount: converted,
            homeCurrency: homeCurrency,
            category: category,
            description: description,
            date: Date()
        )
        expenses.append(expense)
        updateSummary()
        // GRANULAR persist: upsert just this row, never re-write the whole trip's set,
        // so a concurrent write to this trip isn't clobbered.
        let toPersist = expense
        Task { await store.upsert(currencyExpense: toPersist) }
    }

    func deleteExpense(id: UUID) {
        expenses.removeAll { $0.id == id }
        updateSummary()
        // GRANULAR persist: delete only this row.
        Task { await store.delete(currencyExpenseID: id) }
    }

    // MARK: - Helpers

    /// open.er-api returns base→target multipliers. To go target→home we divide
    /// by the rate of `from` (because rates[from] = "1 home = X from").
    private func convertToHome(amount: Double, from currency: String) -> Double? {
        guard let rates = exchangeRates else { return nil }
        if currency == homeCurrency { return amount }
        guard let rate = rates.rates[currency], rate > 0 else { return nil }
        return amount / rate
    }

    private func backfillConversions() {
        var changed: [CurrencyExpense] = []
        for index in expenses.indices where expenses[index].convertedAmount == nil {
            expenses[index].convertedAmount = convertToHome(
                amount: expenses[index].amount,
                from: expenses[index].currency
            )
            if expenses[index].convertedAmount != nil {
                changed.append(expenses[index])
            }
        }
        guard !changed.isEmpty else { return }
        // GRANULAR persist: write back only the rows we actually filled in, so we don't
        // clobber other expenses for this trip that were added out-of-band.
        let toPersist = changed
        Task { for expense in toPersist { await store.upsert(currencyExpense: expense) } }
    }

    private func updateSummary() {
        let totalHome = expenses.compactMap { $0.convertedAmount }.reduce(0, +)
        var byCategory: [SpendCategory: Double] = [:]
        var byDay: [Date: Double] = [:]
        let calendar = Calendar.current

        for expense in expenses {
            guard let amountInHome = expense.convertedAmount else { continue }
            byCategory[expense.category, default: 0] += amountInHome
            let day = calendar.startOfDay(for: expense.date)
            byDay[day, default: 0] += amountInHome
        }

        budgetSummary = BudgetSummary(
            totalSpentHome: totalHome,
            totalBudgetHome: budget,
            spendByCategory: byCategory,
            dailySpend: byDay
        )
    }
}
