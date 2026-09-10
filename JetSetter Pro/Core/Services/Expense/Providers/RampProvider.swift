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
        // Ramp has no JSON "create reimbursement" endpoint. Out-of-pocket
        // reimbursements are created by uploading a receipt to the receipts
        // endpoint (multipart/form-data): when no `reimbursement_id` is supplied,
        // Ramp OCRs the receipt and creates a draft reimbursement. Auth is
        // OAuth2 (authorize on app.ramp.com, token on api.ramp.com).
        OAuthProviderEndpoints(
            authorizationURL: "https://app.ramp.com/v1/authorize",
            tokenURL: "https://api.ramp.com/developer/v1/token",
            createExpenseURL: "https://api.ramp.com/developer/v1/receipts",
            scope: "receipts:write reimbursements:write transactions:read",
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

    /// Ramp's reimbursement creation goes through the multipart receipt-upload
    /// endpoint rather than a JSON body. We send the expense metadata as
    /// form-data parts; Ramp creates a draft reimbursement via OCR.
    ///
    /// NOTE (verify with live credentials): Ramp additionally requires a `user_id`
    /// (the UUID of the Ramp user to reimburse) and, for OCR, the receipt image
    /// itself as an `attachment` part. The app does not yet resolve the connected
    /// Ramp user or attach the receipt image, so this request carries only the
    /// metadata parts — wire those two in before relying on live submission.
    override func createRequest(for expense: Expense, accessToken: String) throws -> URLRequest {
        guard let url = URL(string: endpoints.createExpenseURL) else {
            throw ExpenseExportError.providerFailure("Bad create URL.")
        }
        let boundary = "----JetSetterRampBoundary\(UUID().uuidString)"
        var body = Data()
        // `idempotency_key` prevents duplicate uploads on retry.
        appendFormField("idempotency_key", value: expense.id.uuidString, boundary: boundary, to: &body)
        appendFormField("merchant", value: expense.merchant, boundary: boundary, to: &body)
        appendFormField("amount",
                        value: String(CurrencyMinorUnits.minorUnits(expense.amount, currencyCode: expense.currency)),
                        boundary: boundary, to: &body)
        appendFormField("currency_code", value: expense.currency, boundary: boundary, to: &body)
        appendFormField("transaction_date", value: ExpenseDateFormatting.localDay(expense.date),
                        boundary: boundary, to: &body)
        appendFormField("memo", value: expense.notes ?? expense.category.displayName,
                        boundary: boundary, to: &body)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }
}
