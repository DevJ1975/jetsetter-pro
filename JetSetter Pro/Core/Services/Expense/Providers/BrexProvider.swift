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
        // Brex OAuth lives on the Okta-style accounts-api host; the resource API
        // is api.brex.com. Scopes use space-delimited resource names alongside
        // the OIDC scopes.
        //
        // NOTE (verify with live credentials): the Brex Expenses API is
        // primarily read/update. There is no documented public endpoint that
        // *creates* a standalone card/reimbursement expense out-of-band, so the
        // create call below targets the Expenses collection and may require the
        // Budgets/Reimbursements API (partner-gated) to actually succeed.
        OAuthProviderEndpoints(
            authorizationURL: "https://accounts-api.brex.com/oauth2/default/v1/authorize",
            tokenURL: "https://accounts-api.brex.com/oauth2/default/v1/token",
            createExpenseURL: "https://api.brex.com/v1/expenses",
            scope: "openid offline_access expenses",
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
