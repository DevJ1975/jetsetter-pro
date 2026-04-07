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
                            iconColorHex: "#C9A84C",
                            destination: RentalCarView()
                        )
                    }

                    // ── Travel ───────────────────────────────────────────────
                    moreSection(title: "TRAVEL", icon: "briefcase.fill") {
                        moreCard(
                            title: "Book Flights & Hotels",
                            subtitle: "Live availability via Expedia",
                            icon: "ticket.fill",
                            iconColorHex: "#1DB97D",
                            destination: BookingView()
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
                    .foregroundStyle(Color(hex: "#0A0A10"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(preferences.hasProfile ? preferences.displayName : "JetSetter Traveler")
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(preferences.homeAirport.isEmpty ? "Set your home airport in Settings" : "Home: \(preferences.homeAirport) · \(preferences.currency)")
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
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption).bold()
                Text(title)
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            // Cards
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
                // Icon badge
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
}
