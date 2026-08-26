// File: Core/Services/ApplePayService.swift
//
// Apple Pay collection for real bookings. Presents the native Apple Pay sheet,
// forwards the encrypted PKPaymentToken payload to the proxy's Stripe charge
// route (never decrypted or logged client-side), and returns the Stripe
// PaymentIntent id as a payment reference. The booking (Duffel order / Expedia
// itinerary) is created only AFTER this reference comes back — charge first,
// book second.
//
// Requires the Apple Pay capability + com.apple.developer.in-app-payments
// entitlement (merchant.com.jetsetter.pro) on the app target — added in Xcode.

import Foundation
import PassKit

enum ApplePayError: LocalizedError {
    case unavailable
    case cancelled
    case notConfigured
    case chargeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:        return "Apple Pay isn't available on this device."
        case .cancelled:          return "Payment was cancelled."
        case .notConfigured:      return "Payments aren't configured yet."
        case .chargeFailed(let m): return m
        }
    }
}

@MainActor
final class ApplePayService: NSObject {

    static let shared = ApplePayService()
    private override init() {}

    static let merchantID = "merchant.com.jetsetter.pro"
    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    /// True only when the device can pay AND a matching card is provisioned —
    /// the UI shows the Apple Pay button on true, else a card-entry fallback.
    static var canPay: Bool {
        PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: supportedNetworks, capabilities: .threeDSecure
        )
    }

    // Per-transaction state bridging the delegate callbacks to the async caller.
    private var continuation: CheckedContinuation<String, Error>?
    private var didResume = false
    private var pendingReference: String?
    private var pendingError: Error?
    private var amountMinorUnits = 0
    private var currencyCode = "USD"

    /// Presents Apple Pay for `total` and returns the payment reference
    /// (Stripe PaymentIntent id) once the charge clears. Throws on cancel/failure.
    func pay(total: Decimal, currency: String, itemLabel: String) async throws -> String {
        guard Self.canPay else { throw ApplePayError.unavailable }

        let request = PKPaymentRequest()
        request.merchantIdentifier = Self.merchantID
        request.merchantCapabilities = .threeDSecure
        request.supportedNetworks = Self.supportedNetworks
        request.countryCode = "US"
        request.currencyCode = currency
        // Last summary item is the grand total; its label is the merchant name.
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: itemLabel, amount: NSDecimalNumber(decimal: total)),
            PKPaymentSummaryItem(label: "JetSetter Pro", amount: NSDecimalNumber(decimal: total)),
        ]

        currencyCode = currency
        amountMinorUnits = Self.minorUnits(total, currency: currency)

        didResume = false
        pendingReference = nil
        pendingError = nil

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.present { presented in
                if !presented {
                    Task { @MainActor in self.finish(throwing: ApplePayError.unavailable) }
                }
            }
        }
    }

    private func finish(returning value: String) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func finish(throwing error: Error) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(throwing: error)
        continuation = nil
    }

    /// Smallest currency unit. Two-decimal default; zero-decimal currencies
    /// (e.g. JPY, KRW) use the whole amount.
    private static func minorUnits(_ amount: Decimal, currency: String) -> Int {
        let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK"]
        let factor: Decimal = zeroDecimal.contains(currency.uppercased()) ? 1 : 100
        return NSDecimalNumber(decimal: amount * factor).intValue
    }

    // MARK: - Proxy charge

    private func charge(paymentData: Data) async throws -> String {
        guard let base = DuffelBookingService.secret("API_DUFFEL_PROXY_URL"),
              let key = DuffelBookingService.secret("API_DUFFEL_PROXY_KEY"),
              let url = URL(string: "\(base)/payments/apple-pay/charge") else {
            throw ApplePayError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "payment_data": paymentData.base64EncodedString(),
            "amount": amountMinorUnits,
            "currency": currencyCode,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ChargeError.self, from: data))?.error
                ?? "Payment failed."
            throw ApplePayError.chargeFailed(message)
        }
        guard let result = try? JSONDecoder().decode(ChargeResult.self, from: data) else {
            throw ApplePayError.chargeFailed("Couldn't read the payment response.")
        }
        return result.paymentReference
    }

    private struct ChargeResult: Decodable {
        let paymentReference: String
        enum CodingKeys: String, CodingKey { case paymentReference = "payment_reference" }
    }
    private struct ChargeError: Decodable { let error: String }
}

// MARK: - PKPaymentAuthorizationControllerDelegate

extension ApplePayService: PKPaymentAuthorizationControllerDelegate {

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let paymentData = payment.token.paymentData
        Task { @MainActor in
            do {
                let reference = try await self.charge(paymentData: paymentData)
                self.pendingReference = reference
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            } catch {
                self.pendingError = error
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { }
        if let reference = pendingReference {
            finish(returning: reference)
        } else {
            finish(throwing: pendingError ?? ApplePayError.cancelled)
        }
    }
}
