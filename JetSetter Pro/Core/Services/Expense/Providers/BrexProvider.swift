// File: Core/Services/Expense/Providers/BrexProvider.swift

import Foundation

@MainActor
final class BrexProvider: OAuthExpenseProvider {

    static let shared = BrexProvider()

    override var id: String              { "brex" }
    override var displayName: String     { "Brex" }
    override var tagline: String         { "Push reimbursable expenses to Brex" }
    override var brandColorHex: String   { "#FF6B45" }
    override var systemImage: String     { "creditcard.fill" }
    override var keychainService: String { KeychainCredentials.Service.brex }

    override var endpoints: OAuthProviderEndpoints {
        OAuthProviderEndpoints(
            authorizationURL: "https://accounts.brex.com/oauth2/auth",
            tokenURL: "https://accounts.brex.com/oauth2/token",
            createExpenseURL: "https://platform.brexapis.com/v1/expenses/card/reimbursements",
            scope: "expenses:write",
            redirectScheme: "jetsetter",
            clientID: AppSecrets.value(for: .brexClientID) ?? "",
            clientSecret: nil
        )
    }

    /// Brex expects `merchant_descriptor`, `amount` { amount, currency }, `purchased_at`.
    override func payload(for expense: Expense) -> [String: Any] {
        [
            "merchant_descriptor": expense.merchant,
            "amount": [
                "amount": CurrencyMinorUnits.minorUnits(expense.amount, currencyCode: expense.currency),
                "currency": expense.currency
            ],
            "purchased_at": ISO8601Formatters.internetDateTime.string(from: expense.date),
            "memo": expense.notes ?? expense.category.displayName,
            "category": expense.category.displayName.uppercased().replacingOccurrences(of: " ", with: "_"),
            "external_id": expense.id.uuidString
        ]
    }
}
