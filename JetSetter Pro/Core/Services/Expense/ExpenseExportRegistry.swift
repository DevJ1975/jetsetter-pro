// File: Core/Services/Expense/ExpenseExportRegistry.swift
//
// Single source of truth for all available expense export providers. The UI
// asks the registry for the full list or just the connected ones.

import Foundation

@MainActor
enum ExpenseExportRegistry {

    /// All providers, in user-facing display order.
    static let allProviders: [any ExpenseExportProvider] = [
        EmailPDFProvider.shared,
        ExpensifyProvider.shared,
        RampProvider.shared,
        BrexProvider.shared,
        DivvyProvider.shared
    ]

    /// Providers the user has already connected (Email PDF always returns true).
    static func connectedProviders() async -> [any ExpenseExportProvider] {
        var results: [any ExpenseExportProvider] = []
        for provider in allProviders where await provider.isConnected() {
            results.append(provider)
        }
        return results
    }

    static func find(id: String) -> (any ExpenseExportProvider)? {
        allProviders.first { $0.id == id }
    }
}
