// PremiumGate.swift
// Composable ViewModifier that gates any feature behind an active Pro subscription.
// Usage: SomeView().premiumGate(feature: "AI Assistant")

import SwiftUI

// MARK: - PremiumGateModifier

struct PremiumGateModifier: ViewModifier {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    let featureName: String

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: subscriptionManager.isProSubscriber ? 0 : 10)
                .allowsHitTesting(subscriptionManager.isProSubscriber)
                .animation(.easeInOut(duration: 0.3), value: subscriptionManager.isProSubscriber)

            if !subscriptionManager.isProSubscriber {
                upgradeOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: subscriptionManager.isProSubscriber)
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
                .environmentObject(subscriptionManager)
        }
    }

    // MARK: - Upgrade Overlay

    private var upgradeOverlay: some View {
        VStack(spacing: 20) {
            // Crown
            ZStack {
                Circle()
                    .fill(Color(hex: "#C9A84C").opacity(0.1))
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(Color(hex: "#C9A84C").opacity(0.25), lineWidth: 0.8))

                Image(systemName: "crown.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(JetsetterTheme.Colors.goldGradient)
            }

            VStack(spacing: 6) {
                Text("\(featureName)")
                    .font(.title3).bold()
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Available with JetSetter Pro")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            // Upgrade CTA button
            Button { showPaywall = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.caption).bold()
                    Text("Upgrade to Pro")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: 240)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#E8C877"), location: 0.0),
                            .init(color: Color(hex: "#C9A84C"), location: 0.5),
                            .init(color: Color(hex: "#B8962E"), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(Color(hex: "#0A0A10"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color(hex: "#C9A84C").opacity(0.35), radius: 12, x: 0, y: 6)
            }
        }
        .padding(32)
        .jetCard()
        .padding(.horizontal, 32)
    }
}

// MARK: - View Extension

extension View {
    /// Blurs this view and overlays an upgrade CTA when the user is not a Pro subscriber.
    func premiumGate(feature: String) -> some View {
        modifier(PremiumGateModifier(featureName: feature))
    }
}
