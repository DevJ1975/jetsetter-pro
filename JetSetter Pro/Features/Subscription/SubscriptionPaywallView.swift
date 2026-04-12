// SubscriptionPaywallView.swift

import StoreKit
import SwiftUI

struct SubscriptionPaywallView: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
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
            VStack(spacing: 10) {
                ForEach(subscriptionManager.products, id: \.id) { product in
                    ProductRow(
                        product: product,
                        isRecommended: product.id == SubscriptionTier.annualID,
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
        .environmentObject(SubscriptionManager.shared)
}
