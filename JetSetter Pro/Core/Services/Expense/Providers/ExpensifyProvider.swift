// File: Core/Services/Expense/Providers/ExpensifyProvider.swift
//
// Submits expenses to Expensify via their Integration Server API. Auth uses
// a partnerUserID + partnerUserSecret pair the user creates at
// https://www.expensify.com/tools/integrations/.

import Foundation
import UIKit

// MARK: - Credentials shape

struct ExpensifyCredentials: Codable {
    let partnerUserID: String
    let partnerUserSecret: String
    let userEmail: String   // The account expenses will be created under
}

// MARK: - Provider

@MainActor
final class ExpensifyProvider: ExpenseExportProvider {

    let id = "expensify"
    let displayName = "Expensify"
    let tagline = "Submit to your Expensify account"
    let brandColorHex = "#0D5C2F"
    let systemImage = "doc.text.fill"
    let authKind: ExpenseProviderAuthKind = .apiKey

    static let shared = ExpensifyProvider()
    private init() {}

    private let endpoint = "https://integrations.expensify.com/Integration-Server/ExpensifyIntegrations"

    // MARK: - Connection

    func isConnected() async -> Bool {
        KeychainCredentials.exists(service: KeychainCredentials.Service.expensify)
    }

    func connect() async throws -> Bool {
        // The view layer presents `ExpensifyAuthSheet` and calls `saveCredentials`
        // when the user submits. This method just confirms the result.
        return await isConnected()
    }

    func disconnect() async {
        KeychainCredentials.delete(service: KeychainCredentials.Service.expensify)
    }

    /// Called by the auth sheet after the user enters their fields.
    func saveCredentials(partnerUserID: String, partnerUserSecret: String, userEmail: String) throws {
        let creds = ExpensifyCredentials(
            partnerUserID: partnerUserID,
            partnerUserSecret: partnerUserSecret,
            userEmail: userEmail
        )
        try KeychainCredentials.store(creds, service: KeychainCredentials.Service.expensify)
    }

    // MARK: - Submit

    func submit(trip: Trip?, expenses: [Expense]) async throws -> ExportBatchResult {
        guard let creds = KeychainCredentials.load(
            ExpensifyCredentials.self,
            service: KeychainCredentials.Service.expensify
        ) else {
            throw ExpenseExportError.notConnected
        }

        let mapped = expenses.map { expense -> [String: Any] in
            [
                "created": dateString(expense.date),
                "merchant": expense.merchant,
                "amount": Int(round(expense.amount * 100)),  // Expensify expects cents
                "currency": expense.currency,
                "category": expense.category.displayName,
                "comment": expense.notes ?? "",
                "externalID": expense.id.uuidString
            ]
        }

        let requestJobDescription: [String: Any] = [
            "type": "create",
            "credentials": [
                "partnerUserID": creds.partnerUserID,
                "partnerUserSecret": creds.partnerUserSecret
            ],
            "inputSettings": [
                "type": "expenses",
                "employeeEmail": creds.userEmail,
                "transactionList": mapped
            ]
        ]

        let requestJSON = try JSONSerialization.data(withJSONObject: requestJobDescription)
        guard let requestString = String(data: requestJSON, encoding: .utf8) else {
            throw ExpenseExportError.providerFailure("Couldn't encode payload.")
        }

        // Expensify expects multipart form: 'requestJobDescription' = JSON string
        let boundary = "----JetSetterBoundary\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"requestJobDescription\"\r\n\r\n".data(using: .utf8)!)
        body.append(requestString.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: endpoint) else {
            throw ExpenseExportError.providerFailure("Invalid endpoint.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "no body"
            throw ExpenseExportError.providerFailure("Expensify responded \(((response as? HTTPURLResponse)?.statusCode).map(String.init) ?? "?"): \(detail.prefix(200))")
        }

        // Expensify returns JSON with `responseCode`. 200 = success.
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let responseCode = json?["responseCode"] as? Int ?? -1
        guard responseCode == 200 else {
            let message = (json?["responseMessage"] as? String) ?? "Unknown error"
            throw ExpenseExportError.providerFailure("Expensify: \(message)")
        }

        let perExpense: [UUID: ExportOutcome] = Dictionary(
            uniqueKeysWithValues: expenses.map { ($0.id, ExportOutcome.submitted(remoteID: $0.id.uuidString)) }
        )
        return ExportBatchResult(
            providerID: id, providerName: displayName,
            submittedAt: Date(), perExpense: perExpense
        )
    }

    // MARK: - Helpers

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
