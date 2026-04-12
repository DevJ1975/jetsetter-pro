// File: Features/CurrencyTracker/CurrencyExpenseViewModel.swift
// ViewModel for the Currency + Expense Tracker (Feature 3).
// TODO: Full implementation in Feature 3 sprint.

import SwiftUI
import Combine

@MainActor
final class CurrencyExpenseViewModel: ObservableObject {

    @Published private(set) var expenses: [CurrencyExpense] = []
    @Published private(set) var exchangeRates: ExchangeRates? = nil
    @Published private(set) var budgetSummary: BudgetSummary? = nil
    @Published private(set) var isLoading = false
    @Published var errorMessage: String? = nil

    // Live currency converter input
    @Published var converterInput: String = ""
    var convertedAmount: Double? {
        guard let amount = Double(converterInput),
              let rates = exchangeRates else { return nil }
        return rates.convert(amount: amount, to: destinationCurrency)
    }

    let trip: Trip
    let homeCurrency: String
    let destinationCurrency: String
    var budget: Double?

    init(trip: Trip, homeCurrency: String, destinationCurrency: String, budget: Double? = nil) {
        self.trip = trip
        self.homeCurrency = homeCurrency
        self.destinationCurrency = destinationCurrency
        self.budget = budget
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // TODO: Fetch expenses from Supabase + ExchangeRate-API rates
    }

    func addExpense(amount: Double, category: SpendCategory, description: String) {
        let converted = exchangeRates?.convert(amount: amount, to: homeCurrency)
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
        // TODO: Persist to SwiftData locally, sync to Supabase when online
    }

    func deleteExpense(id: UUID) {
        expenses.removeAll { $0.id == id }
        updateSummary()
    }

    private func updateSummary() {
        let totalHome = expenses.compactMap { $0.convertedAmount }.reduce(0, +)
        var byCategory: [SpendCategory: Double] = [:]
        for expense in expenses {
            byCategory[expense.category, default: 0] += expense.convertedAmount ?? expense.amount
        }
        budgetSummary = BudgetSummary(
            totalSpentHome: totalHome,
            totalBudgetHome: budget,
            spendByCategory: byCategory,
            dailySpend: [:]
        )
    }
}
