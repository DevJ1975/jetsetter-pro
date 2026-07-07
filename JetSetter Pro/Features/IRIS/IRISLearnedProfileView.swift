// File: Features/IRIS/IRISLearnedProfileView.swift
//
// Transparency screen for the learning layer — shows exactly what IRIS has
// inferred about the traveler from their own activity, and lets them wipe it.
// Mirrors the trust-building intent of IRISMemoryView ("What IRIS remembers"),
// but for the *derived* TravelProfile rather than explicitly-stated preferences.

import SwiftUI

struct IRISLearnedProfileView: View {

    @State private var store = TravelProfileStore.shared
    @State private var showWipeConfirm = false

    private var profile: TravelProfile { store.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !store.persona.isEmpty {
                    Text(store.persona)
                        .font(.callout)
                        .italic()
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .jetCard()
                }

                if profile.isEmpty {
                    emptyState
                } else {
                    if let seat = profile.typicalSeat, seat.column != .unknown {
                        row(icon: "chair.fill", title: "Typical seat",
                            value: seat.displayName,
                            detail: "From \(seat.sampleSize) flight\(seat.sampleSize == 1 ? "" : "s") · \(Int(seat.confidence * 100))% consistent")
                    }
                    if !profile.topAirlines.isEmpty {
                        row(icon: "airplane.circle.fill", title: "Preferred airlines",
                            value: profile.topAirlines.prefix(3).map(\.value).joined(separator: ", "))
                    }
                    if let cabin = profile.preferredCabin {
                        row(icon: "star.circle.fill", title: "Usual cabin", value: cabin)
                    }
                    if !profile.topHotelBrands.isEmpty {
                        row(icon: "bed.double.fill", title: "Preferred hotels",
                            value: profile.topHotelBrands.prefix(3).map(\.value).joined(separator: ", "))
                    }
                    if !profile.frequentCities.isEmpty {
                        row(icon: "globe.americas.fill", title: "Frequent places",
                            value: profile.frequentCities.prefix(4).map(\.value).joined(separator: ", "))
                    }
                    if !profile.spendByCategory.isEmpty {
                        row(icon: "creditcard.fill", title: "Typical spend",
                            value: profile.spendByCategory.sorted { $0.average > $1.average }.prefix(3)
                                .map { "\($0.category) ~\(Int($0.average.rounded())) \($0.currency)" }
                                .joined(separator: " · "))
                    }
                    if let lead = profile.typicalBookingLeadDays {
                        row(icon: "calendar", title: "Booking lead time", value: "~\(lead) days ahead")
                    }
                    if let dur = profile.typicalTripDurationDays {
                        row(icon: "calendar.badge.clock", title: "Typical trip length", value: "~\(dur) days")
                    }
                    if let cadence = profile.travelCadenceDays {
                        row(icon: "arrow.triangle.2.circlepath", title: "Travel cadence",
                            value: "Roughly every \(TravelProfile.humanInterval(cadence))")
                    }
                    if !profile.peakTravelMonths.isEmpty {
                        row(icon: "sun.max.fill", title: "Peak travel months",
                            value: profile.peakTravelMonths.joined(separator: ", "))
                    }

                    wipeButton
                }
            }
            .padding(20)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("What IRIS Has Learned")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.mergeFromCloud()   // pull cross-device signals if signed in
            await store.refreshPersona()      // generate the narrative persona via Claude
        }
        .confirmationDialog("Forget everything IRIS has learned?",
                            isPresented: $showWipeConfirm, titleVisibility: .visible) {
            Button("Forget Learned Profile", role: .destructive) { store.clearLearnedData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the inferred profile and its signals. Your trips, expenses, and explicitly saved IRIS preferences are not affected.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inferred from your own activity")
                .font(JetsetterTheme.Typography.pageTitle)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("IRIS builds this on your device from the seats you pick, flights you take, receipts you scan, and trips you complete. It's never shared.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.accent)
            Text("Nothing learned yet")
                .font(.headline)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("As you check in, scan receipts, and take trips, IRIS will start to recognize your preferences here.")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func row(icon: String, title: String, value: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .jetCard()
    }

    private var wipeButton: some View {
        Button(role: .destructive) {
            showWipeConfirm = true
        } label: {
            Label("Forget What IRIS Learned", systemImage: "trash")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(JetsetterTheme.Colors.danger.opacity(0.12))
                .foregroundStyle(JetsetterTheme.Colors.danger)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack { IRISLearnedProfileView() }
}
