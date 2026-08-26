// File: Core/Services/ExpenseCategorizer.swift
//
// On-device expense categorization using Apple Intelligence (FoundationModels).
// Classifies a receipt / merchant into one of the app's fixed ExpenseCategory
// cases via guided generation, so the result is ALWAYS a valid category — no
// free-form string parsing or tag-to-category mapping needed.
//
// Degrades gracefully: returns nil whenever the on-device model is unavailable
// (pre-iOS 26, ineligible device, or Apple Intelligence turned off), letting
// callers keep whatever default category they already have.

import Foundation
import FoundationModels

@MainActor
final class ExpenseCategorizer {

    static let shared = ExpenseCategorizer()
    private init() {}

    /// True when the on-device model can classify right now. Use this to decide
    /// whether to show an "AI suggested" affordance in the UI.
    var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Suggests the best category for an expense, or nil if on-device
    /// classification isn't available. Never throws — any failure degrades to nil.
    func suggestCategory(
        merchant: String,
        notes: String? = nil,
        receiptText: String? = nil
    ) async -> ExpenseCategory? {
        guard #available(iOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        return await classify(merchant: merchant, notes: notes, receiptText: receiptText)
    }

    // MARK: - Apple Intelligence

    @available(iOS 26.0, *)
    private func classify(
        merchant: String,
        notes: String?,
        receiptText: String?
    ) async -> ExpenseCategory? {
        // Keep the prompt short — the on-device model has a small context window.
        var details = "Merchant: \(merchant.isEmpty ? "Unknown" : merchant)"
        if let notes, !notes.isEmpty {
            details += "\nNote: \(notes)"
        }
        if let receiptText, !receiptText.isEmpty {
            details += "\nReceipt: \(receiptText.prefix(400))"
        }

        let instructions = """
        You classify a single business-travel expense into exactly one category. \
        Pick the category that best matches the merchant and receipt. \
        Use 'other' only when nothing else fits.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Classify this expense:\n\(details)",
                generating: CategoryChoice.self,
                // Greedy sampling makes classification deterministic.
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.category
        } catch {
            // Guardrail violations, context overflow, etc. → fall back to nil.
            return nil
        }
    }
}

// MARK: - Generable classification result

// Mirrors ExpenseCategory minus `.mileage`, which is logged explicitly by the
// user (distance-based) and never inferred from a receipt. Guided generation
// constrains the model to exactly these cases.
@available(iOS 26.0, *)
@Generable
private enum CategoryChoice {
    case food
    case transport
    case accommodation
    case entertainment
    case business
    case shopping
    case medical
    case other

    var category: ExpenseCategory {
        switch self {
        case .food:          return .food
        case .transport:     return .transport
        case .accommodation: return .accommodation
        case .entertainment: return .entertainment
        case .business:      return .business
        case .shopping:      return .shopping
        case .medical:       return .medical
        case .other:         return .other
        }
    }
}
