// SubscriptionManager.swift
// Manages App Store auto-renewable subscriptions via StoreKit 2.
// The system purchase sheet natively presents Apple Pay / Apple Wallet
// as a payment option when the user has a card on file.

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
@Observable
final class SubscriptionManager {

    static let shared = SubscriptionManager()

    // MARK: - Published State

    /// True when the user holds an active, verified Pro entitlement.
    /// Defaults to false — production trusts only StoreKit (`refreshEntitlements`).
    private(set) var isProSubscriber: Bool = false

    /// Products loaded from App Store Connect (or a local .storekit config for testing).
    private(set) var products: [Product] = []

    /// True while a purchase or restore is in flight — disables all purchase buttons.
    private(set) var purchaseInProgress: Bool = false

    /// Set to a human-readable message when a purchase error occurs.
    var purchaseError: String? = nil

    // MARK: - Private

    /// Long-lived listener for renewals, refunds, and billing-retry events.
    @ObservationIgnored private var transactionListenerTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // Start listening before fetching products so no transactions are missed
        // that were processed while the app was not running.
        transactionListenerTask = makeTransactionListener()

        Task {
            await loadProducts()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: SubscriptionTier.allProductIDs)
            // Rank products so ordering is a valid strict-weak-ordering even if new
            // tiers are added: annual first (best-value lead), then monthly, then rest.
            func rank(_ id: String) -> Int {
                switch id {
                case SubscriptionTier.annualID:  return 0
                case SubscriptionTier.monthlyID: return 1
                default:                         return 2
                }
            }
            products = fetched.sorted { rank($0.id) < rank($1.id) }
            // Clear any prior load error once products are available.
            if !products.isEmpty { purchaseError = nil }
        } catch {
            // Surface the failure so the paywall can show an error + retry
            // affordance instead of spinning forever on an empty product list.
            purchaseError = "Couldn’t load subscription options. Check your connection and try again."
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
            // Give explicit feedback either way — a silent no-op left the user
            // unsure whether the restore actually did anything.
            if isProSubscriber {
                purchaseError = "Your JetSetter Pro subscription has been restored."
            } else {
                purchaseError = "No active subscription found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement Refresh

    /// Re-derives `isProSubscriber` from `Transaction.currentEntitlements`.
    /// Never trusts a cached value — always reads from StoreKit.
    func refreshEntitlements() async {
        var hasActivePro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SubscriptionTier.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }                       // refunded / revoked
            if let expiration = transaction.expirationDate, expiration < Date() { continue }  // lapsed
            if transaction.isUpgraded { continue }                                   // superseded by higher tier
            hasActivePro = true
            break
        }
        #if DEBUG
        // Demo/QA builds stay unlocked even without App Store Connect products,
        // unless a tester turns the override off to exercise the purchase flow.
        isProSubscriber = hasActivePro || demoUnlockEnabled
        #else
        isProSubscriber = hasActivePro
        #endif
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

#if DEBUG
    // MARK: - Developer Override (DEBUG only)

    /// When true, Pro stays unlocked in demo/QA builds regardless of StoreKit.
    /// Never compiled into Release, so production always enforces real entitlements.
    ///
    /// Defaults to `false` so DEBUG/QA builds exercise the *real* entitlement gate
    /// (surfacing StoreKit purchase/restore bugs) and an accidentally-shipped debug
    /// build never gives Pro away for free. Call `unlockForTesting()` to opt in for
    /// a local demo / investor walkthrough.
    private(set) var demoUnlockEnabled = false

    /// Unlocks all Pro features for local testing / investor demos.
    func unlockForTesting() {
        demoUnlockEnabled = true
        isProSubscriber = true
    }
#endif

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value):      return value
        }
    }
}
