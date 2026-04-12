// File: Features/CurrencyTracker/CurrencyModel.swift
// Models for the Currency + Expense Tracker feature (Feature 3).

import Foundation

// MARK: - ExchangeRates

/// Live exchange rates from ExchangeRate-API (free tier).
/// Base currency is always the user's home currency.
struct ExchangeRates: Codable {
    let base: String
    let rates: [String: Double]
    let fetchedAt: Date

    /// Converts an amount from base currency to the given target currency.
    func convert(amount: Double, to targetCurrency: String) -> Double? {
        guard let rate = rates[targetCurrency] else { return nil }
        return amount * rate
    }

    /// True if the rates were fetched within the last 6 hours.
    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 6 * 3600
    }
}

// MARK: - SpendCategory

enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case food          = "Food"
    case transport     = "Transport"
    case accommodation = "Accommodation"
    case activities    = "Activities"
    case shopping      = "Shopping"
    case other         = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .accommodation: return "bed.double.fill"
        case .activities:    return "star.fill"
        case .shopping:      return "bag.fill"
        case .other:         return "ellipsis.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .food:          return "#E84040"
        case .transport:     return "#3B9EF0"
        case .accommodation: return "#0A7A5E"
        case .activities:    return "#E8A020"
        case .shopping:      return "#7B3FBF"
        case .other:         return "#8B92A8"
        }
    }
}

// MARK: - CurrencyExpense

/// One expense entry tracked during the trip.
/// Supabase table: expenses_v2 (separate from legacy expenses table)
struct CurrencyExpense: Identifiable, Codable {
    let id: UUID
    var tripId: UUID
    var amount: Double            // In destination (trip) currency
    var currency: String          // Destination currency code
    var convertedAmount: Double?  // In home currency (calculated at entry time)
    var homeCurrency: String
    var category: SpendCategory
    var description: String
    var date: Date
    var receiptImagePath: String? // Supabase Storage path (optional)

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, category, description, date
        case tripId           = "trip_id"
        case convertedAmount  = "converted_amount"
        case homeCurrency     = "home_currency"
        case receiptImagePath = "receipt_image_path"
    }
}

// MARK: - BudgetSummary

struct BudgetSummary {
    let totalSpentHome: Double
    let totalBudgetHome: Double?
    let spendByCategory: [SpendCategory: Double]
    let dailySpend: [Date: Double]

    var budgetProgress: Double? {
        guard let budget = totalBudgetHome, budget > 0 else { return nil }
        return min(totalSpentHome / budget, 1.0)
    }

    var isOverBudget: Bool {
        guard let budget = totalBudgetHome else { return false }
        return totalSpentHome > budget
    }
}
