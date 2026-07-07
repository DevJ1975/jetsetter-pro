// File: Features/ExpenseTracker/ExpenseModel.swift

import Foundation

// MARK: - Expense Category

// Raw values are UPPERCASE to match the cross-platform wire contract
// (Android `ExpenseCategory` enum names). See IOS_PARITY_NOTES.md §2.
nonisolated enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food          = "FOOD"
    case transport     = "TRANSPORT"
    case accommodation = "ACCOMMODATION"
    case entertainment = "ENTERTAINMENT"
    case business      = "BUSINESS"
    case shopping      = "SHOPPING"
    case medical       = "MEDICAL"
    case mileage       = "MILEAGE"
    case other         = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food:          return "Food & Dining"
        case .transport:     return "Transportation"
        case .accommodation: return "Accommodation"
        case .entertainment: return "Entertainment"
        case .business:      return "Business"
        case .shopping:      return "Shopping"
        case .medical:       return "Medical"
        case .mileage:       return "Mileage"
        case .other:         return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .accommodation: return "bed.double.fill"
        case .entertainment: return "star.fill"
        case .business:      return "briefcase.fill"
        case .shopping:      return "bag.fill"
        case .medical:       return "cross.fill"
        case .mileage:       return "road.lanes"
        case .other:         return "ellipsis.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .food:          return "#CC3B1E"
        case .transport:     return "#0066CC"
        case .accommodation: return "#0A7A5E"
        case .entertainment: return "#C8860A"
        case .business:      return "#1A2E40"
        case .shopping:      return "#7B2D8B"
        case .medical:       return "#E5383B"
        case .mileage:       return "#4E9AF1"
        case .other:         return "#888888"
        }
    }
}

// MARK: - Expense

/// A single expense item — either a receipt scan, manual entry, or mileage log.
nonisolated struct Expense: Identifiable, Codable {
    let id: UUID
    var amount: Double
    var currency: String
    var category: ExpenseCategory
    var merchant: String
    var date: Date
    var notes: String?
    /// Raw OCR text from a scanned receipt
    var receiptText: String?
    /// Mileage distance in miles (only set for .mileage category)
    var mileageDistance: Double?

    init(
        id: UUID = UUID(),
        amount: Double,
        currency: String = "USD",
        category: ExpenseCategory,
        merchant: String,
        date: Date = Date(),
        notes: String? = nil,
        receiptText: String? = nil,
        mileageDistance: Double? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.category = category
        self.merchant = merchant
        self.date = date
        self.notes = notes
        self.receiptText = receiptText
        self.mileageDistance = mileageDistance
    }

    /// Formatted amount string (e.g. "USD 42.50")
    var formattedAmount: String {
        String(format: "%@ %.2f", currency, amount)
    }

    /// Parses a user-entered amount string in a locale-aware way.
    ///
    /// `Double(_:)` only understands a period decimal separator, so it silently
    /// fails for locales that use a comma (e.g. "12,50"). This tries the current
    /// locale via `NumberFormatter`, then falls back to a comma→period swap so
    /// the field works regardless of which separator the keyboard produced.
    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        // Fallback: normalize a comma decimal separator to a period.
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - OCR Receipt Parse Result

/// Intermediate result from the Vision OCR service before the user confirms.
struct OCRReceiptResult {
    var extractedAmount: Double?
    var extractedMerchant: String?
    var rawText: String
}

// MARK: - Currency Detection

extension OCRReceiptResult {
    /// Best-effort currency detection from the raw receipt text.
    ///
    /// A receipt scanned abroad is usually in the local currency, so defaulting
    /// to the traveler's preferred currency is often wrong. We look for an explicit
    /// ISO code (e.g. "EUR", "JPY") first, then fall back to an unambiguous symbol.
    /// The `$` symbol is intentionally excluded because it maps to many currencies
    /// (USD, CAD, AUD, HKD, SGD, MXN, NZD, …) and would produce false positives.
    /// Returns `nil` when nothing conclusive is found, leaving the caller's default.
    var detectedCurrencyCode: String? {
        let upper = rawText.uppercased()

        // 1. Explicit ISO 4217 code appearing as a standalone token.
        for code in Expense.knownCurrencyCodes {
            if upper.range(of: #"\b\#(code)\b"#, options: .regularExpression) != nil {
                return code
            }
        }

        // 2. Unambiguous single-currency symbols.
        for (symbol, code) in Expense.unambiguousCurrencySymbols where rawText.contains(symbol) {
            return code
        }

        return nil
    }
}

// MARK: - IRS Mileage Rate

extension Expense {
    /// US IRS standard mileage reimbursement rates (per mile), keyed by tax year.
    /// Source: IRS annual standard mileage rate announcements. Historical entries
    /// keep their correct-for-that-year rate; new entries use the current year.
    /// NOTE: this is the US-specific business rate — not applicable to non-US travelers.
    private static let irsMileageRatesByYear: [Int: Double] = [
        2022: 0.585,   // IRS raised mid-year to 0.625; 0.585 is the Jan–Jun rate
        2023: 0.655,
        2024: 0.67,
        2025: 0.70,
        2026: 0.70     // placeholder until the 2026 rate is published; defaults to prior year
    ]

    /// The most recent published year in the table — used as the fallback rate
    /// for any date newer than the newest entry we know about.
    private static let latestKnownRateYear = 2026

    /// The IRS standard mileage rate that applies to an expense on `date`.
    /// Dates before the earliest known year use the earliest rate; dates after
    /// the latest known year use the latest rate.
    static func irsMileageRate(for date: Date) -> Double {
        let year = Calendar.current.component(.year, from: date)
        if let rate = irsMileageRatesByYear[year] { return rate }
        let years = irsMileageRatesByYear.keys.sorted()
        guard let earliest = years.first, let latest = years.last else { return 0.67 }
        let clampedYear = min(max(year, earliest), latest)
        return irsMileageRatesByYear[clampedYear] ?? irsMileageRatesByYear[latestKnownRateYear] ?? 0.67
    }

    /// The IRS standard mileage rate for the current year.
    static var currentIRSMileageRate: Double {
        irsMileageRate(for: Date())
    }

    /// Backward-compatible accessor for the current-year IRS rate.
    ///
    /// Prefer `irsMileageRate(for:)` so historical entries keep their
    /// correct-for-that-year rate. This computed shim (formerly a hardcoded
    /// 0.67 constant) is retained for callers that only have a single rate slot.
    @available(*, deprecated, message: "Use irsMileageRate(for:) so historical expenses keep their correct rate.")
    static var irsMileageRatePerMile: Double { currentIRSMileageRate }

    /// Calculates the reimbursable amount for a given mileage distance, using the
    /// IRS rate that applied on `date` (defaults to the current date's year).
    static func mileageAmount(for miles: Double, on date: Date = Date()) -> Double {
        (miles * irsMileageRate(for: date) * 100).rounded() / 100
    }
}

// MARK: - Currency Reference Data

extension Expense {
    /// ISO 4217 codes we can recognize in OCR text — kept in sync with
    /// `UserPreferences.supportedCurrencies` so a detected code is always
    /// selectable in the currency picker.
    static let knownCurrencyCodes: [String] = [
        "USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "CNY", "HKD",
        "SGD", "AED", "MXN", "BRL", "INR", "NZD"
    ]

    /// Currency symbols that unambiguously map to a single supported currency.
    /// The `$` sign is deliberately omitted — it is shared by several currencies
    /// and would guess wrong more often than right.
    static let unambiguousCurrencySymbols: [(symbol: String, code: String)] = [
        ("€", "EUR"),
        ("£", "GBP"),
        ("¥", "JPY"),   // shared with CNY, but JPY is the more common receipt case
        ("₹", "INR")
    ]
}

// MARK: - Sample Data (Previews)

extension Expense {
    static let sampleExpenses: [Expense] = [
        Expense(
            amount: 54.20,
            category: .food,
            merchant: "Nobu Restaurant",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            notes: "Team dinner"
        ),
        Expense(
            amount: 340.00,
            category: .accommodation,
            merchant: "Park Hyatt Tokyo",
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        ),
        Expense(
            amount: 28.50,
            category: .transport,
            merchant: "Tokyo Metro",
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        ),
        Expense(
            amount: 20.10,
            currency: "USD",
            category: .mileage,
            merchant: "Airport to Hotel",
            date: Date(),
            mileageDistance: 30.0
        )
    ]

    static var sampleTotal: Double {
        sampleExpenses.reduce(0) { $0 + $1.amount }
    }
}
