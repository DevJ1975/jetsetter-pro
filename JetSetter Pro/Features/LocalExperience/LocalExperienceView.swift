// File: Features/LocalExperience/LocalExperienceView.swift
// Local Experience Engine — AI-ranked card feed organized by Right Now / Tonight / This Trip
// (Feature 5). Scaffolded UI — full implementation in Feature 5 sprint.

import SwiftUI

struct LocalExperienceView: View {

    @StateObject private var vm: LocalExperienceViewModel
    @EnvironmentObject private var subscriptions: SubscriptionManager

    init(trip: Trip) {
        _vm = StateObject(wrappedValue: LocalExperienceViewModel(trip: trip))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    loadingView
                } else if !vm.isAtDestination {
                    notAtDestinationView
                } else if vm.experiences.isEmpty {
                    emptyView
                } else {
                    experienceFeed
                }
            }
            .navigationTitle("Local Experiences")
            .navigationBarTitleDisplayMode(.large)
            .background(JetsetterTheme.Colors.background)
            .task { await vm.load() }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
        .premiumGate(feature: "Local Experience Engine")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(JetsetterTheme.Colors.accent).scaleEffect(1.4)
            Text("Finding experiences near you…")
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not At Destination

    private var notAtDestinationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 52))
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)

            VStack(spacing: 8) {
                Text("Not at \(vm.destinationCity) Yet")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text("Local experiences activate automatically when you're within 50km of your destination.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.accent)
            Text("No recommendations yet.")
                .font(JetsetterTheme.Typography.pageTitle)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Experience Feed

    private var experienceFeed: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !vm.rightNow.isEmpty {
                    experienceSection("RIGHT NOW", slot: .rightNow, items: vm.rightNow)
                }
                if !vm.tonight.isEmpty {
                    experienceSection("TONIGHT", slot: .tonight, items: vm.tonight)
                }
                if !vm.thisTrip.isEmpty {
                    experienceSection("THIS TRIP", slot: .thisTrip, items: vm.thisTrip)
                }
            }
            .padding(16)
        }
    }

    private func experienceSection(
        _ title: String,
        slot: ExperienceTimeSlot,
        items: [Experience]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: slot == .rightNow ? "bolt.fill" : slot == .tonight ? "moon.fill" : "calendar")
                    .font(.caption.bold())
                Text(title).font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { exp in
                        ExperienceCard(experience: exp) {
                            vm.openBookingURL(for: exp)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - ExperienceCard

struct ExperienceCard: View {

    let experience: Experience
    let onBook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Photo placeholder / AsyncImage
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: experience.category.colorHex).opacity(0.15))
                    .frame(height: 120)

                if let urlString = experience.photoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                                .frame(height: 120)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else {
                    Image(systemName: experience.category.systemImage)
                        .font(.system(size: 32))
                        .foregroundStyle(Color(hex: experience.category.colorHex))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Category badge
                Text(experience.category.rawValue)
                    .font(JetsetterTheme.Typography.label)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: experience.category.colorHex))
                    .clipShape(Capsule())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(experience.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Rating
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.caption2)
                        Text(String(format: "%.1f", experience.rating)).font(.caption)
                    }
                    .foregroundStyle(JetsetterTheme.Colors.warning)

                    Text("·").foregroundStyle(JetsetterTheme.Colors.textSecondary)

                    // Price
                    Text(experience.priceLevel.symbol)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)

                    if let dist = experience.distanceMeters {
                        Text("·").foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        Text(experience.distanceFormatted)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }

                // AI reason
                if let reason = experience.aiReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .lineLimit(2)
                }

                // Book button
                if experience.bookingUrl != nil {
                    Button(action: onBook) {
                        Text("Reserve")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(JetsetterTheme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 220)
        .padding(12)
        .jetCard()
    }
}

#Preview {
    LocalExperienceView(trip: .sample)
        .environmentObject(SubscriptionManager.shared)
}
