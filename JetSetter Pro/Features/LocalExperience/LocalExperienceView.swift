// File: Features/LocalExperience/LocalExperienceView.swift
// Local Experience Engine — Apple Maps places around the destination, ranked on
// device for this traveler, organized by Right Now / Tonight / This Trip (Feature 5).

import SwiftUI

struct LocalExperienceView: View {

    @State private var vm: LocalExperienceViewModel
    @Environment(SubscriptionManager.self) private var subscriptions

    init(trip: Trip) {
        _vm = State(wrappedValue: LocalExperienceViewModel(trip: trip))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    loadingView
                } else if vm.experiences.isEmpty {
                    emptyView
                } else {
                    experienceFeed
                }
            }
            .navigationTitle("Local Experiences")
            .navigationBarTitleDisplayMode(.large)
            .background(JetsetterTheme.Colors.background)
            .inAppWeb(url: $vm.externalWebURL, title: "Experience")
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
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

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.accent)
            Text("Nothing to show yet")
                .font(JetsetterTheme.Typography.pageTitle)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text(vm.errorMessage ?? "Pull to refresh to look around \(vm.destinationCity.isEmpty ? "your destination" : vm.destinationCity) again.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await vm.refresh() } }
                .buttonStyle(.bordered)
                .tint(JetsetterTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Experience Feed

    private var experienceFeed: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    Image(systemName: vm.isRankedOnDevice ? "sparkles" : "map")
                    Text(vm.isRankedOnDevice
                         ? "Ranked for you on this iPhone · distances from \(vm.distanceOrigin)"
                         : "From Apple Maps · distances from \(vm.distanceOrigin)")
                }
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
            ZStack(alignment: .topTrailing) {
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

                // Category badge (top-leading)
                Text(experience.category.rawValue)
                    .font(JetsetterTheme.Typography.label)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: experience.category.colorHex))
                    .clipShape(Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                // Open / Closed badge (top-trailing) — only when hours are known
                if let openNow = experience.openNow {
                    Text(openNow ? "Open" : "Closed")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(openNow ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.textSecondary)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(experience.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Rating — only when the source actually supplies one
                    if experience.hasRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.caption2)
                            Text(String(format: "%.1f", experience.rating)).font(.caption)
                        }
                        .foregroundStyle(JetsetterTheme.Colors.warning)
                        Text("·").foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }

                    if experience.distanceMeters != nil {
                        Text(experience.distanceFormatted)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    } else if !experience.address.isEmpty {
                        Text(experience.address)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            .lineLimit(1)
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
                        Text(experience.bookActionLabel)
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
        .environment(SubscriptionManager.shared)
}
