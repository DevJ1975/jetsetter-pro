// SubscriptionManager.swift
// Manages App Store auto-renewable subscriptions via StoreKit 2.
// The system purchase sheet natively presents Apple Pay / Apple Wallet
// as a payment option when the user has a card on file.

import Combine
import StoreKit
import SwiftUI

// MARK: - Subscription Products

enum SubscriptionTier {
    // Replace these IDs with the exact ones created in App Store Connect.
    static let monthlyID = "DevJ.JetSetter-Pro.subscription.pro.monthly"
    static let annualID  = "DevJ.JetSetter-Pro.subscription.pro.annual"

    static let allProductIDs: [String] = [monthlyID, annualID]
}

// MARK: - SubscriptionManager

@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    // MARK: - Published State

    /// True when the user holds an active, verified Pro entitlement.
    @Published private(set) var isProSubscriber: Bool = false

    /// Products loaded from App Store Connect (or a local .storekit config for testing).
    @Published private(set) var products: [Product] = []

    /// True while a purchase or restore is in flight — disables all purchase buttons.
    @Published private(set) var purchaseInProgress: Bool = false

    /// Set to a human-readable message when a purchase error occurs.
    @Published var purchaseError: String? = nil

    // MARK: - Private

    /// Long-lived listener for renewals, refunds, and billing-retry events.
    private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // Start listening before fetching products so no transactions are missed
        // that were processed while the app was not running.
        transactionListenerTask = makeTransactionListener()

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: SubscriptionTier.allProductIDs)
            // Annual first (best value lead), monthly second.
            products = fetched.sorted { $0.id == SubscriptionTier.annualID && $1.id != SubscriptionTier.annualID }
        } catch {
            // Non-fatal — paywall will show a loading spinner until retried.
        }
    }

    // MARK: - Purchase

    /// Initiates the StoreKit purchase flow. The system sheet includes Apple Pay
    /// when the user has a card in their Apple Wallet.
    func purchase(_ product: Product) async {
        purchaseInProgress = true
        purchaseError = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                // Ask-to-Buy or deferred payment — no action needed; listener handles it.
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore Purchases

    /// Required by App Store guidelines — must surface a "Restore Purchases" button.
    func restorePurchases() async {
        purchaseInProgress = true
        purchaseError = nil
        defer { purchaseInProgress = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement Refresh

    /// Re-derives `isProSubscriber` from `Transaction.currentEntitlements`.
    /// Never trusts a cached value — always reads from StoreKit.
    func refreshEntitlements() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if SubscriptionTier.allProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                hasPro = true
            }
        }
        isProSubscriber = hasPro
    }

    // MARK: - Transaction Listener

    private func makeTransactionListener() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }
}
