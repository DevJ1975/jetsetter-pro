// File: Core/Services/Expense/Providers/RampProvider.swift

import Foundation

@MainActor
final class RampProvider: OAuthExpenseProvider {

    static let shared = RampProvider()

    override var id: String              { "ramp" }
    override var displayName: String     { "Ramp" }
    override var tagline: String         { "Sync expenses to your Ramp account" }
    override var brandColorHex: String   { "#FFEB00" }
    override var systemImage: String     { "creditcard.fill" }
    override var keychainService: String { KeychainCredentials.Service.ramp }

    override var endpoints: OAuthProviderEndpoints {
        OAuthProviderEndpoints(
            authorizationURL: "https://app.ramp.com/v1/authorize",
            tokenURL: "https://api.ramp.com/developer/v1/token",
            createExpenseURL: "https://api.ramp.com/developer/v1/reimbursements",
            scope: "reimbursements:write transactions:read",
            redirectScheme: "jetsetter",
            clientID: AppSecrets.value(for: .anthropic) ?? "",   // placeholder until RAMP_CLIENT_ID is added
            clientSecret: nil
        )
    }

    /// Ramp expects `merchant_name`, `amount` (cents), `currency`, `transaction_date`.
    override func payload(for expense: Expense) -> [String: Any] {
        [
            "merchant_name": expense.merchant,
            "amount": Int(round(expense.amount * 100)),
            "currency_code": expense.currency,
            "transaction_date": ISO8601DateFormatter().string(from: expense.date),
            "memo": expense.notes ?? expense.category.displayName,
            "user_provided_external_id": expense.id.uuidString
        ]
    }
}
