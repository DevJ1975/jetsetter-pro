// File: Core/Services/Expense/Providers/DivvyProvider.swift
//
// Divvy rebranded to BILL Spend & Expense (2023). Its current API is the BILL
// Connect v3 gateway, authenticated with a static Spend & Expense API token in
// the `apiToken` header — NOT the OAuth2 authorization-code flow the app's other
// card providers use. So this provider is a standalone `.apiKey` integration
// rather than an `OAuthExpenseProvider` subclass.

import Foundation

@MainActor
final class DivvyProvider: ExpenseExportProvider {

    static let shared = DivvyProvider()
    private init() {}

    let id = "divvy"
    let displayName = "BILL Spend & Expense"
    let tagline = "Formerly Divvy — push reimbursements to BILL"
    let brandColorHex = "#0046FF"
    let systemImage = "creditcard.fill"
    let authKind: ExpenseProviderAuthKind = .apiKey

    // BILL Connect v3 Spend & Expense gateway. Staging is gateway.stage.bill.com.
    #if DEBUG
    private let baseURL = "https://gateway.stage.bill.com/connect/v3/spend"
    #else
    private let baseURL = "https://gateway.bill.com/connect/v3/spend"
    #endif

    // MARK: - Connection
    //
    // The Spend & Expense API token is an organization-level secret generated in
    // the BILL dashboard, supplied here via AppSecrets (Secrets.xcconfig).
    //
    // NOTE (verify with live credentials): for a multi-tenant deployment each
    // BILL customer has their own token, which would need a user-entry auth sheet
    // (like ExpensifyProvider's) storing the token in the Keychain rather than a
    // single build-time secret. Wire that in before shipping to multiple orgs.

    func isConnected() async -> Bool {
        !APIKeys.billSpend.isEmpty
    }

    func connect() async throws -> Bool {
        guard await isConnected() else {
            throw ExpenseExportError.configurationMissing(displayName)
        }
        return true
    }

    func disconnect() async {
        // Token is build-time configuration; nothing user-stored to wipe.
    }

    // MARK: - Submit

    func submit(trip: Trip?, expenses: [Expense]) async throws -> ExportBatchResult {
        let token = APIKeys.billSpend
        guard !token.isEmpty else { throw ExpenseExportError.notConnected }
        guard let url = URL(string: "\(baseURL)/reimbursements") else {
            throw ExpenseExportError.providerFailure("Invalid BILL endpoint.")
        }

        var per: [UUID: ExportOutcome] = [:]
        for expense in expenses {
            do {
                let remoteID = try await postReimbursement(expense, url: url, token: token)
                per[expense.id] = .submitted(remoteID: remoteID)
            } catch {
                per[expense.id] = .failed(error: error.localizedDescription)
            }
        }
        return ExportBatchResult(
            providerID: id, providerName: displayName,
            submittedAt: Date(), perExpense: per
        )
    }

    /// POSTs one reimbursement to the BILL Connect v3 Spend & Expense API.
    ///
    /// NOTE (verify with live credentials): the exact reimbursement request
    /// schema is defined in BILL's OpenAPI (developer.bill.com). This sends a
    /// reasonable shape (amount in currency minor units, merchant, transaction
    /// date, memo). A `userId` for the person being reimbursed is typically
    /// required and must be resolved from the connected BILL org.
    private func postReimbursement(_ expense: Expense, url: URL, token: String) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "apiToken")

        let payload: [String: Any] = [
            "merchantName": expense.merchant,
            "amount": CurrencyMinorUnits.minorUnits(expense.amount, currencyCode: expense.currency),
            "currency": expense.currency,
            "transactionDate": ExpenseDateFormatting.localDay(expense.date),
            "note": expense.notes ?? expense.category.displayName,
            "clientReferenceId": expense.id.uuidString
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        do {
            data = try await APIClient.shared.data(for: request)
        } catch let error as APIError {
            throw ExpenseExportError.providerFailure("BILL request failed: \(error.errorDescription ?? "")")
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = dict["id"] as? String {
            return id
        }
        return expense.id.uuidString
    }
}
