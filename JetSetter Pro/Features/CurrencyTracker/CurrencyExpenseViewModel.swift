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

    var convertedAmount: Double? {
        guard let amount = Self.parseDecimal(converterInput),
              let rates = exchangeRates else { return nil }
        return rates.convert(amount: amount, to: destinationCurrency)
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

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

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
            // Backfill convertedAmount for any expenses that were entered offline
            backfillConversions()
            updateSummary()
        } else {
            errorMessage = "Couldn't load live exchange rates. Try again later."
        }
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
