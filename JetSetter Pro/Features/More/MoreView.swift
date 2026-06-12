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
                            title: "IRIS — Travel Agent",
                            subtitle: "Your proactive AI agent (Pro)",
                            icon: "sparkles",
                            iconColorHex: "#7B3FBF",
                            destination: IRISChatView().premiumGate(feature: "IRIS — your AI travel agent")
                        )
                        moreCard(
                            title: "Trip Disruption AI",
                            subtitle: "Real-time alerts & automatic rebooking",
                            icon: "exclamationmark.triangle.fill",
                            iconColorHex: "#E84040",
                            destination: DisruptionDashboardView()
                        )
                        moreCard(
                            title: "Proactive Intelligence",
                            subtitle: "Live on Home — leave-now & check-in cards",
                            icon: "brain.head.profile",
                            iconColorHex: "#7B3FBF",
                            destination: ComingSoonView(featureName: "Trigger History", icon: "brain.head.profile", description: "Browse past Proactive Intelligence cards and actions you've taken. Coming in v1.1.")
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
                            destination: ComingSoonView(featureName: "Document Vault", icon: "lock.shield.fill", description: "Encrypted storage for passport, visa, and insurance documents. Coming in v1.1.")
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
                            destination: CurrencyExpenseRouterView()
                        )
                    }

                    // ── Transport ────────────────────────────────────────────
                    moreSection(title: "TRANSPORT", icon: "car.fill") {
                        moreCard(
                            title: "Ground Transport",
                            subtitle: "Uber & Lyft ride estimates",
                            icon: "car.fill",
                            iconColorHex: "#4E8FD4",
                            destination: ComingSoonView(featureName: "Ground Transport", icon: "car.fill", description: "Live Uber and Lyft ride estimates from your location to airports. Coming in v1.1.")
                        )
                        moreCard(
                            title: "Rental Cars",
                            subtitle: "Enterprise, Hertz, National",
                            icon: "steeringwheel",
                            iconColorHex: "#C8860A",
                            destination: ComingSoonView(featureName: "Rental Cars", icon: "steeringwheel", description: "Compare Enterprise, Hertz, and National prices side-by-side. Coming in v1.1.")
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
                            title: "Departure Board",
                            subtitle: "Live split-flap display of airport departures",
                            icon: "rectangle.stack.fill",
                            iconColorHex: "#E8A020",
                            destination: FlightBoardView()
                        )
                        moreCard(
                            title: "Identity & Trusted Traveler",
                            subtitle: "Digital ID, CLEAR, PreCheck & Global Entry",
                            icon: "person.text.rectangle.fill",
                            iconColorHex: "#0066CC",
                            destination: IdentityVaultView()
                        )
                        moreCard(
                            title: "Travel Essentials",
                            subtitle: "Emergency #s, tipping, plugs, water & phrases",
                            icon: "globe.americas.fill",
                            iconColorHex: "#1DB97D",
                            destination: TravelEssentialsView()
                        )
                        moreCard(
                            title: "Miles & Loyalty",
                            subtitle: "Airline miles, hotel points & status tiers",
                            icon: "star.circle.fill",
                            iconColorHex: "#C8860A",
                            destination: LoyaltyVaultView()
                        )
                        moreCard(
                            title: "Translator",
                            subtitle: "On-device translation with live camera scan",
                            icon: "character.bubble.fill",
                            iconColorHex: "#7B3FBF",
                            destination: TranslatorView()
                        )
                        moreCard(
                            title: "Offline Kit",
                            subtitle: "Pre-cache trip data for in-flight & abroad",
                            icon: "icloud.and.arrow.down.fill",
                            iconColorHex: "#0A7A5E",
                            destination: OfflineKitView()
                        )
                        moreCard(
                            title: "Trip Journal",
                            subtitle: "Auto-built photo scrapbook from your library",
                            icon: "book.pages.fill",
                            iconColorHex: "#7B3FBF",
                            destination: TripJournalRouterView()
                        )
                        moreCard(
                            title: "In-Flight Tracker",
                            subtitle: "Live altitude, GPS position & phase detection",
                            icon: "antenna.radiowaves.left.and.right",
                            iconColorHex: "#3B9EF0",
                            destination: InFlightView()
                        )
                        moreCard(
                            title: "Visa Requirements",
                            subtitle: "Entry rules for US passport holders",
                            icon: "doc.text.fill",
                            iconColorHex: "#0066CC",
                            destination: VisaLookupView()
                        )
                        moreCard(
                            title: "Carbon Footprint",
                            subtitle: "Calculate flight emissions & offset",
                            icon: "leaf.fill",
                            iconColorHex: "#0A7A5E",
                            destination: CarbonFootprintView()
                        )
                        moreCard(
                            title: "Departure Optimizer",
                            subtitle: "Live traffic + TSA wait → when to leave",
                            icon: "clock.badge.checkmark.fill",
                            iconColorHex: "#3B9EF0",
                            destination: DepartureOptimizerView()
                        )
                        moreCard(
                            title: "Book Flights & Hotels",
                            subtitle: "Live availability via Expedia",
                            icon: "ticket.fill",
                            iconColorHex: "#1DB97D",
                            destination: ComingSoonView(featureName: "Book Flights & Hotels", icon: "ticket.fill", description: "Search and book flights and hotels with live availability. Coming in v1.1.")
                        )
                        moreCard(
                            title: "Airport Map",
                            subtitle: "Indoor navigation & gate wayfinding",
                            icon: "map.fill",
                            iconColorHex: "#7B3FBF",
                            destination: ComingSoonView(featureName: "Airport Map", icon: "map.fill", description: "Indoor navigation and gate wayfinding for major airports. Coming in v1.1.")
                        )
                        moreCard(
                            title: "Luggage Tracker",
                            subtitle: "AirTag & WorldTracer",
                            icon: "suitcase.fill",
                            iconColorHex: "#E8A020",
                            destination: ComingSoonView(featureName: "Luggage Tracker", icon: "suitcase.fill", description: "AirTag integration and SITA WorldTracer lookups for lost bags. Coming in v1.1.")
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
