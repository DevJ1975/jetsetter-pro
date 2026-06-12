// File: Core/Services/Expense/Providers/DivvyProvider.swift

import Foundation

@MainActor
final class DivvyProvider: OAuthExpenseProvider {

    static let shared = DivvyProvider()

    override var id: String              { "divvy" }
    override var displayName: String     { "BILL Spend & Expense" }
    override var tagline: String         { "Formerly Divvy — push to your account" }
    override var brandColorHex: String   { "#0046FF" }
    override var systemImage: String     { "creditcard.fill" }
    override var keychainService: String { KeychainCredentials.Service.divvy }

    override var endpoints: OAuthProviderEndpoints {
        OAuthProviderEndpoints(
            authorizationURL: "https://app.divvy.co/oauth/authorize",
            tokenURL: "https://api.divvy.co/oauth/token",
            createExpenseURL: "https://api.divvy.co/v1/expenses",
            scope: "expenses.write",
            redirectScheme: "jetsetter",
            clientID: AppSecrets.value(for: .anthropic) ?? "",   // placeholder until DIVVY_CLIENT_ID is added
            clientSecret: nil
        )
    }

    override func payload(for expense: Expense) -> [String: Any] {
        [
            "merchant": expense.merchant,
            "amount_cents": Int(round(expense.amount * 100)),
            "currency": expense.currency,
            "transaction_date": ISO8601DateFormatter().string(from: expense.date),
            "category_name": expense.category.displayName,
            "memo": expense.notes ?? "",
            "client_reference_id": expense.id.uuidString
        ]
    }
}
