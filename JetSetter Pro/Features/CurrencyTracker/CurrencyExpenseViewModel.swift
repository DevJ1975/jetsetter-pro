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
        MoneyFormatting.parseDecimal(text)
    }

    let trip: Trip
    let homeCurrency: String
    let destinationCurrency: String
    var budget: Double?

    private let encoder = JSONCoding.iso8601Encoder
    private let decoder = JSONCoding.iso8601Decoder

    private var storageKey: String {
        "jetsetter_currency_expenses_\(trip.id.uuidString)"
    }

    init(trip: Trip, homeCurrency: String, destinationCurrency: String, budget: Double? = nil) {
        self.trip = trip
        self.homeCurrency = homeCurrency
        self.destinationCurrency = destinationCurrency
        self.budget = budget
        loadLocalExpenses()
        updateSummary()
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

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
        saveLocalExpenses()
        updateSummary()
    }

    func deleteExpense(id: UUID) {
        expenses.removeAll { $0.id == id }
        saveLocalExpenses()
        updateSummary()
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
        for index in expenses.indices where expenses[index].convertedAmount == nil {
            expenses[index].convertedAmount = convertToHome(
                amount: expenses[index].amount,
                from: expenses[index].currency
            )
        }
        saveLocalExpenses()
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

    // MARK: - Local Persistence

    private func saveLocalExpenses() {
        guard let data = try? encoder.encode(expenses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadLocalExpenses() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([CurrencyExpense].self, from: data)
        else { return }
        expenses = decoded
    }
}
