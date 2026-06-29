// File: JetSetter ProTests/ExpenseCategorizerTests.swift
// Unit tests for the on-device expense categorizer's graceful-degradation
// contract. The Foundation Models on-device model is unavailable in the
// simulator/CI, so these tests assert the fallback behavior (never throw,
// degrade to nil) rather than the model's actual classifications.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
struct ExpenseCategorizerTests {

    /// The view model's availability flag must mirror the categorizer's, since
    /// manual entry gates its "Suggest Category" affordance on it.
    @Test func viewModelMirrorsCategorizerAvailability() {
        let vm = ExpenseViewModel()
        #expect(vm.isCategorizationAvailable == ExpenseCategorizer.shared.isAvailable)
    }

    /// When the on-device model is unavailable, a suggestion must degrade to nil
    /// so callers keep their existing category. Skipped on the rare CI/sim where
    /// Apple Intelligence is actually on.
    @Test func unavailableModelYieldsNilSuggestion() async {
        let categorizer = ExpenseCategorizer.shared
        guard !categorizer.isAvailable else { return }
        let result = await categorizer.suggestCategory(
            merchant: "Starbucks",
            receiptText: "Grande latte $5.25"
        )
        #expect(result == nil)
    }

    /// Same contract through the ExpenseViewModel proxy used by manual entry.
    @Test func viewModelCategorizeDegradesToNil() async {
        let vm = ExpenseViewModel()
        guard !vm.isCategorizationAvailable else { return }
        let result = await vm.categorize(merchant: "Hilton Garden Inn", notes: nil)
        #expect(result == nil)
    }
}
