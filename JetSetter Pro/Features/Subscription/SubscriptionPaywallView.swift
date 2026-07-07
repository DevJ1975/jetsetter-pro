// SubscriptionPaywallView.swift

import StoreKit
import SwiftUI

struct SubscriptionPaywallView: View {

    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.dismiss) private var dismiss

    private let proFeatures: [(icon: String, title: String, description: String)] = [
        ("sparkles",                        "AI Travel Concierge",    "Unlimited Claude-powered travel advice"),
        ("airplane.circle.fill",            "Live Flight Tracking",   "Real-time status, gate & delay alerts"),
        ("chart.bar.fill",                  "Expense Analytics",      "Multi-currency reports & CSV export"),
        ("suitcase.fill",                   "Luggage Tracker",        "AirTag & WorldTracer integration"),
        ("arrow.triangle.2.circlepath",     "Cloud Sync",             "All your devices, always in sync"),
        ("ticket.fill",                     "Booking Assistant",      "Live hotel & flight availability")
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            JetsetterTheme.Colors.heroGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                        .padding(.top, 56)
                        .padding(.bottom, 28)

                    featureList
                        .padding(.bottom, 28)

                    pricingSection
                        .padding(.bottom, 12)

                    restoreButton
                        .padding(.bottom, 12)

                    legalFooter
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 20)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(20)
            }
            .accessibilityLabel("Close")
        }
        .onChange(of: subscriptionManager.isProSubscriber) { _, isPro in
            if isPro { dismiss() }
        }
        .task {
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.accent.opacity(0.10))
                    .frame(width: 84, height: 84)
                    .overlay(Circle().strokeBorder(JetsetterTheme.Colors.accent.opacity(0.25), lineWidth: 0.8))

                Image(systemName: "crown.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }

            Text("JETSETTER PRO")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(3.5)
                .foregroundStyle(JetsetterTheme.Colors.goldGradient)

            Text("Travel Like an Executive")
                .font(JetsetterTheme.Typography.displayTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("One subscription. Every premium feature.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(proFeatures, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(JetsetterTheme.Colors.goldGradient)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                        Text(feature.description)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }

                    Spacer()

                    Image(systemName: "checkmark")
                        .font(.caption2).bold()
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(JetsetterTheme.Colors.accent.opacity(0.12), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Pricing

    @ViewBuilder
    private var pricingSection: some View {
        if subscriptionManager.products.isEmpty {
            ProgressView()
                .tint(JetsetterTheme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            let bestValueID = bestValueProductID
            VStack(spacing: 10) {
                ForEach(subscriptionManager.products, id: \.id) { product in
                    ProductRow(
                        product: product,
                        // "BEST VALUE" is derived from the actual normalized
                        // per-month price rather than hardcoding the annual tier,
                        // so a misconfigured/promo price can never mislabel a plan.
                        isRecommended: product.id == bestValueID,
                        savingsText: savingsText(for: product),
                        isPurchasing: subscriptionManager.purchaseInProgress
                    ) {
                        Task { await subscriptionManager.purchase(product) }
                    }
                }

                if let error = subscriptionManager.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Best-Value Derivation

    /// The product ID with the lowest normalized per-month price, or `nil` when
    /// there is only one plan / no comparable subscription pricing is available.
    /// Ties (or missing period data) fall back to no recommendation rather than
    /// guessing, so the "BEST VALUE" badge only appears when it is provably true.
    private var bestValueProductID: String? {
        let priced: [(id: String, monthly: Decimal)] = subscriptionManager.products.compactMap { product in
            guard let monthly = product.normalizedMonthlyPrice else { return nil }
            return (product.id, monthly)
        }
        guard priced.count > 1 else { return nil }
        guard let cheapest = priced.min(by: { $0.monthly < $1.monthly }) else { return nil }
        // Only recommend if it is strictly cheaper than every other plan.
        let isStrictlyCheapest = priced
            .filter { $0.id != cheapest.id }
            .allSatisfy { cheapest.monthly < $0.monthly }
        return isStrictlyCheapest ? cheapest.id : nil
    }

    /// A "Save NN% vs monthly" string for `product` when it is the best-value plan
    /// and its normalized monthly price beats the standalone monthly product.
    private func savingsText(for product: Product) -> String? {
        guard product.id == bestValueProductID,
              let monthlyPlan = subscriptionManager.products.first(where: { $0.id == SubscriptionTier.monthlyID }),
              product.id != monthlyPlan.id,
              let candidateMonthly = product.normalizedMonthlyPrice,
              monthlyPlan.price > 0,
              candidateMonthly < monthlyPlan.price
        else { return nil }

        let saved = (monthlyPlan.price - candidateMonthly) / monthlyPlan.price
        let percent = Int((NSDecimalNumber(decimal: saved).doubleValue * 100).rounded())
        guard percent > 0 else { return nil }
        return "Save \(percent)% vs monthly"
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await subscriptionManager.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .disabled(subscriptionManager.purchaseInProgress)
    }

    // MARK: - Legal

    private var legalFooter: some View {
        Text("Subscriptions auto-renew unless cancelled at least 24 hours before the period ends. Manage anytime in App Store Settings.")
            .font(.system(size: 10))
            .foregroundStyle(Color.white.opacity(0.25))
            .multilineTextAlignment(.center)
    }
}

// MARK: - ProductRow

private struct ProductRow: View {

    let product: Product
    let isRecommended: Bool
    let savingsText: String?
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        if isRecommended {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.5)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(JetsetterTheme.Colors.accent)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    if let sub = product.subscription {
                        Text(sub.subscriptionPeriod.periodLabel)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.45))
                    }

                    if let savingsText {
                        Text(savingsText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(JetsetterTheme.Colors.accent)

                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .padding(16)
            .background(
                isRecommended
                    ? JetsetterTheme.Colors.accent.opacity(0.10)
                    : Color.white.opacity(0.04)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isRecommended
                            ? JetsetterTheme.Colors.accent.opacity(0.45)
                            : Color.white.opacity(0.08),
                        lineWidth: isRecommended ? 1.0 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}

// MARK: - Normalized Pricing Helper

private extension Product {
    /// This product's price expressed as an equivalent cost per 30-day month,
    /// enabling an apples-to-apples comparison across billing periods. Returns
    /// `nil` for non-subscription products or unknown period units.
    var normalizedMonthlyPrice: Decimal? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        let value = Decimal(period.value)
        guard value > 0 else { return nil }

        // Convert the total price over the period into a per-month figure.
        let monthsPerPeriod: Decimal
        switch period.unit {
        case .day:   monthsPerPeriod = value / 30
        case .week:  monthsPerPeriod = value * 7 / 30
        case .month: monthsPerPeriod = value
        case .year:  monthsPerPeriod = value * 12
        @unknown default: return nil
        }
        guard monthsPerPeriod > 0 else { return nil }
        return price / monthsPerPeriod
    }
}

// MARK: - SubscriptionPeriod Helper

private extension Product.SubscriptionPeriod {
    var periodLabel: String {
        let unitName: String
        switch unit {
        case .day:    unitName = "day"
        case .week:   unitName = "week"
        case .month:  unitName = "month"
        case .year:   unitName = "year"
        @unknown default: unitName = "period"
        }
        return value == 1 ? "Billed every \(unitName)" : "Billed every \(value) \(unitName)s"
    }
}

#Preview {
    SubscriptionPaywallView()
        .environment(SubscriptionManager.shared)
}
