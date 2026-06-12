// File: Core/Services/Expense/ExpenseExportProvider.swift
//
// Abstract protocol every expense export integration (Expensify, Ramp, Brex,
// Divvy, Email PDF, etc.) conforms to. The view layer treats them uniformly.

import Foundation

// MARK: - Auth kind

enum ExpenseProviderAuthKind {
    case none           // Email PDF — no auth needed
    case apiKey         // Expensify-style: user enters a key + secret
    case oauth2         // Ramp / Brex / Divvy: redirect-based flow
}

// MARK: - Result types

struct ExportBatchResult {
    let providerID: String
    let providerName: String
    let submittedAt: Date
    let perExpense: [UUID: ExportOutcome]

    var successCount: Int { perExpense.values.filter { if case .submitted = $0 { return true } else { return false } }.count }
    var failedCount: Int  { perExpense.values.filter { if case .failed = $0 { return true } else { return false } }.count }
    var skippedCount: Int { perExpense.values.filter { if case .skipped = $0 { return true } else { return false } }.count }
}

enum ExportOutcome {
    case submitted(remoteID: String)
    case skipped(reason: String)
    case failed(error: String)

    var label: String {
        switch self {
        case .submitted: return "Submitted"
        case .skipped:   return "Skipped"
        case .failed:    return "Failed"
        }
    }
}

// MARK: - Provider protocol

@MainActor
protocol ExpenseExportProvider {
    var id: String { get }
    var displayName: String { get }
    var tagline: String { get }
    var brandColorHex: String { get }
    var systemImage: String { get }
    var authKind: ExpenseProviderAuthKind { get }

    /// True when the user has supplied valid credentials (if any are needed).
    func isConnected() async -> Bool

    /// Submits the batch and returns per-expense results.
    func submit(trip: Trip?, expenses: [Expense]) async throws -> ExportBatchResult

    /// Launches the connection flow (auth UI, API key entry, etc.).
    /// Returns true on success.
    func connect() async throws -> Bool

    /// Wipes stored credentials.
    func disconnect() async
}

// MARK: - Errors

enum ExpenseExportError: LocalizedError {
    case notConnected
    case userCancelled
    case providerFailure(String)
    case configurationMissing(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:                 return "This provider isn't connected. Connect it in Settings."
        case .userCancelled:                return "Cancelled."
        case .providerFailure(let msg):     return msg
        case .configurationMissing(let m):  return "Configuration missing: \(m)"
        }
    }
}
