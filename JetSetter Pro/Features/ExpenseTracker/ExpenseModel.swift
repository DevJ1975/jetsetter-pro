// File: Features/ExpenseTracker/ExpenseModel.swift

import Foundation

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case transport
    case accommodation
    case entertainment
    case business
    case shopping
    case medical
    case mileage
    case other

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
struct Expense: Identifiable, Codable {
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
}

// MARK: - OCR Receipt Parse Result

/// Intermediate result from the Vision OCR service before the user confirms.
struct OCRReceiptResult {
    var extractedAmount: Double?
    var extractedMerchant: String?
    var rawText: String
}

// MARK: - IRS Mileage Rate

extension Expense {
    /// 2024 IRS standard mileage reimbursement rate (per mile)
    static let irsMileageRatePerMile: Double = 0.67

    /// Calculates the reimbursable amount for a given mileage distance
    static func mileageAmount(for miles: Double) -> Double {
        (miles * irsMileageRatePerMile * 100).rounded() / 100
    }
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
