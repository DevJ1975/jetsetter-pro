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
            clientID: AppSecrets.value(for: .rampClientID) ?? "",
            clientSecret: AppSecrets.value(for: .rampClientSecret)
        )
    }

    /// Guard against an unconfigured client before launching the OAuth session.
    /// When the Ramp client ID secret is unset, `endpoints.clientID` is empty and
    /// the base flow would otherwise open a web session with `client_id=`,
    /// surfacing an opaque provider-side error. Fail fast with a clear message.
    override func connect() async throws -> Bool {
        guard !endpoints.clientID.isEmpty else {
            throw ExpenseExportError.configurationMissing(displayName)
        }
        return try await super.connect()
    }

    /// Ramp expects `merchant_name`, `amount` (cents), `currency`, `transaction_date`.
    override func payload(for expense: Expense) -> [String: Any] {
        [
            "merchant_name": expense.merchant,
            "amount": CurrencyMinorUnits.minorUnits(expense.amount, currencyCode: expense.currency),
            "currency_code": expense.currency,
            "transaction_date": ExpenseDateFormatting.localDay(expense.date),
            "memo": expense.notes ?? expense.category.displayName,
            "user_provided_external_id": expense.id.uuidString
        ]
    }
}
