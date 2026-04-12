// File: Features/More/MoreView.swift

import SwiftUI

struct MoreView: View {

    @EnvironmentObject private var preferences: UserPreferences

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Quick-access profile card ────────────────────────────
                    profileBanner

                    // ── AI & Intelligence ─────────────────────────────────────
                    moreSection(title: "AI FEATURES", icon: "sparkles") {
                        moreCard(
                            title: "Trip Disruption AI",
                            subtitle: "Real-time alerts & automatic rebooking",
                            icon: "exclamationmark.triangle.fill",
                            iconColorHex: "#E84040",
                            destination: DisruptionDashboardView()
                        )
                        moreCard(
                            title: "Proactive Intelligence",
                            subtitle: "Leave-now alerts, gate changes & more",
                            icon: "brain.head.profile",
                            iconColorHex: "#7B3FBF",
                            destination: ComingSoonView(featureName: "Proactive Intelligence", icon: "brain.head.profile", description: "Leave-now alerts, gate changes, and weather shifts detected automatically.")
                        )
                    }

                    // ── Trip Tools ────────────────────────────────────────────
                    moreSection(title: "TRIP TOOLS", icon: "briefcase.fill") {
                        moreCard(
                            title: "Smart Packing List",
                            subtitle: "AI-generated based on weather & activities",
                            icon: "checklist",
                            iconColorHex: "#3B9EF0",
                            destination: PackingListRouterView()
                        )
                        moreCard(
                            title: "Document Vault",
                            subtitle: "Encrypted passport, visa & insurance storage",
                            icon: "lock.shield.fill",
                            iconColorHex: "#0055CC",
                            destination: DocumentVaultView()
                        )
                        moreCard(
                            title: "Local Experiences",
                            subtitle: "AI-ranked restaurants, events & hidden gems",
                            icon: "sparkles",
                            iconColorHex: "#E8A020",
                            destination: ComingSoonView(featureName: "Local Experiences", icon: "sparkles", description: "AI-ranked restaurants, events and hidden gems near your destination.")
                        )
                    }

                    // ── Finance ───────────────────────────────────────────────
                    moreSection(title: "FINANCE", icon: "dollarsign.circle.fill") {
                        moreCard(
                            title: "Currency & Expenses",
                            subtitle: "Live rates, spend tracking & budget chart",
                            icon: "arrow.left.arrow.right.circle.fill",
                            iconColorHex: "#1DB97D",
                            destination: ComingSoonView(featureName: "Currency + Expense Tracker", icon: "arrow.left.arrow.right.circle.fill", description: "Live exchange rates, spend tracking, and budget charts.")
                        )
                    }

                    // ── Transport ────────────────────────────────────────────
                    moreSection(title: "TRANSPORT", icon: "car.fill") {
                        moreCard(
                            title: "Ground Transport",
                            subtitle: "Uber & Lyft ride estimates",
                            icon: "car.fill",
                            iconColorHex: "#4E8FD4",
                            destination: GroundTransportView()
                        )
                        moreCard(
                            title: "Rental Cars",
                            subtitle: "Enterprise, Hertz, National",
                            icon: "steeringwheel",
                            iconColorHex: "#C8860A",
                            destination: RentalCarView()
                        )
                    }

                    // ── Travel ───────────────────────────────────────────────
                    moreSection(title: "TRAVEL", icon: "airplane") {
                        moreCard(
                            title: "Travel Wallet",
                            subtitle: "Boarding passes, hotels, car rentals",
                            icon: "wallet.pass.fill",
                            iconColorHex: "#0066CC",
                            destination: TravelWalletView()
                        )
                        moreCard(
                            title: "Book Flights & Hotels",
                            subtitle: "Live availability via Expedia",
                            icon: "ticket.fill",
                            iconColorHex: "#1DB97D",
                            destination: BookingView()
                        )
                        moreCard(
                            title: "Airport Map",
                            subtitle: "Indoor navigation & gate wayfinding",
                            icon: "map.fill",
                            iconColorHex: "#7B3FBF",
                            destination: AirportMapView(airportIATA: "—", gate: "—")
                        )
                        moreCard(
                            title: "Luggage Tracker",
                            subtitle: "AirTag & WorldTracer",
                            icon: "suitcase.fill",
                            iconColorHex: "#E8A020",
                            destination: LuggageTrackerView()
                        )
                    }

                    // ── App ──────────────────────────────────────────────────
                    moreSection(title: "APP", icon: "gearshape.fill") {
                        moreCard(
                            title: "Settings",
                            subtitle: "Preferences, account, notifications",
                            icon: "gearshape.2.fill",
                            iconColorHex: "#8B92A8",
                            destination: SettingsView()
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Profile Banner

    private var profileBanner: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.goldGradient)
                    .frame(width: 52, height: 52)
                Text(preferences.hasProfile ? preferences.initials : "JS")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(preferences.hasProfile ? preferences.displayName : "JetSetter Traveler")
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(preferences.homeAirport.isEmpty
                     ? "Set your home airport in Settings"
                     : "Home: \(preferences.homeAirport) · \(preferences.currency)")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 36, height: 36)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Section Builder

    private func moreSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption).bold()
                Text(title)
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            VStack(spacing: 1) {
                content()
            }
            .jetCard()
        }
    }

    // MARK: - Row Card

    private func moreCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        iconColorHex: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: iconColorHex).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: iconColorHex))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption).bold()
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    MoreView()
        .environmentObject(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager.shared)
}
