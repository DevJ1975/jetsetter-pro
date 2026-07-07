// File: Features/OfflineKit/OfflineKitView.swift
//
// Standalone screen showing the offline-kit status for the user's next trip.
// Lets them manually refresh the cache before they fly.

import SwiftUI

struct OfflineKitView: View {

    @State private var snapshot: OfflineTripSnapshot?
    @State private var trip: Trip?
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let trip {
                    tripCard(trip)
                    if let snapshot {
                        statusGrid(snapshot)
                        cachedContent(snapshot)
                    } else {
                        emptyCacheCard
                    }
                    if let errorMessage {
                        partialFailureBanner(errorMessage)
                    }
                    refreshButton
                } else {
                    noTripCard
                }
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Offline Kit")
        .navigationBarTitleDisplayMode(.large)
        .task { reload() }
    }

    // MARK: - Sections

    private func tripCard(_ trip: Trip) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(JetsetterTheme.Colors.accent.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.headline)
                Text(trip.destination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(trip.startDate, style: .date) – \(trip.endDate, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .jetCard()
    }

    private func statusGrid(_ snapshot: OfflineTripSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption.bold())
                Text("CACHED CONTENT")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(snapshot.isFresh ? JetsetterTheme.Colors.success : .orange)
            .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statusTile(
                    icon: "list.bullet.rectangle.fill",
                    title: "Itinerary",
                    value: "\(snapshot.itineraryItemCount) items",
                    on: snapshot.itineraryItemCount > 0
                )
                statusTile(
                    icon: "wallet.pass.fill",
                    title: "Wallet",
                    value: "\(snapshot.walletItemCount) docs",
                    on: snapshot.walletItemCount > 0
                )
                statusTile(
                    icon: "cloud.sun.fill",
                    title: "Weather",
                    value: snapshot.payload.weatherSummary ?? "Not cached",
                    on: snapshot.hasDestinationWeather
                )
                statusTile(
                    icon: "dollarsign.arrow.circlepath",
                    title: "FX rates",
                    value: snapshot.exchangeRatesBase.map { "\(snapshot.exchangeRatesCount) currencies (\($0))" } ?? "Not cached",
                    on: snapshot.exchangeRatesBase != nil
                )
                statusTile(
                    icon: "globe.americas.fill",
                    title: "Essentials",
                    value: snapshot.payload.countryNotes?.countryName ?? "Not cached",
                    on: snapshot.hasCountryEssentials
                )
                statusTile(
                    icon: "clock.fill",
                    title: snapshot.isFresh ? "Fresh until" : "Expired",
                    value: snapshot.expiresAt.formatted(.dateTime.month().day().hour().minute()),
                    on: snapshot.isFresh
                )
            }
        }
    }

    private func statusTile(icon: String, title: String, value: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(on ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.textSecondary)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemFill).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? JetsetterTheme.Colors.success.opacity(0.3) : .clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cachedContent(_ snapshot: OfflineTripSnapshot) -> some View {
        if let summary = snapshot.payload.exchangeRateSummary,
           !summary.isEmpty, summary != "Cached" {
            VStack(alignment: .leading, spacing: 8) {
                Text("EXCHANGE RATES")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .padding(.leading, 4)
                VStack(spacing: 6) {
                    let lines = summary.components(separatedBy: " · ")
                    ForEach(lines.indices, id: \.self) { i in
                        HStack {
                            Text(lines[i])
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if i != lines.count - 1 { Divider() }
                    }
                }
                .jetCard()
            }
        }

        if let phrases = snapshot.payload.countryNotes?.phrases, !phrases.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("OFFLINE PHRASES")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .padding(.leading, 4)
                VStack(spacing: 6) {
                    ForEach(phrases.indices, id: \.self) { i in
                        HStack {
                            Text(phrases[i].english)
                                .font(.caption)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            Spacer()
                            Text(phrases[i].local)
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if i != phrases.count - 1 { Divider() }
                    }
                }
                .jetCard()
            }
        }
    }

    private var emptyCacheCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nothing cached yet")
                .font(.headline)
            Text("Tap Refresh below to download everything you'll need on the plane and abroad.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var noTripCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No upcoming trip")
                .font(.headline)
            Text("Add a trip in Itinerary to enable offline caching.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private func partialFailureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var refreshButton: some View {
        Button { Task { await refresh() } } label: {
            HStack {
                if isRefreshing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(isRefreshing ? "Caching…" : "Refresh Offline Kit")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(JetsetterTheme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(isRefreshing || trip == nil)
    }

    // MARK: - Actions

    private func reload() {
        trip = nextTrip()
        if let trip { snapshot = OfflineKitService.shared.snapshot(tripID: trip.id) }
    }

    private func refresh() async {
        guard let trip else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        let walletItems = loadWalletItems()
        let fresh = await OfflineKitService.shared.cache(
            trip: trip,
            walletItems: walletItems,
            homeCurrency: UserPreferences.shared.currency.isEmpty ? "USD" : UserPreferences.shared.currency
        )
        snapshot = fresh

        // Weather and FX rates fail soft to nil when connectivity is poor, so a
        // "successful" refresh can still land a snapshot missing its perishable
        // data. Surface that so the user doesn't leave believing the kit is
        // complete when it isn't.
        var missing: [String] = []
        if !fresh.hasDestinationWeather { missing.append("weather") }
        if fresh.exchangeRatesBase == nil { missing.append("exchange rates") }
        if !missing.isEmpty {
            errorMessage = "Cached everything except \(missing.joined(separator: " & ")) — connect to Wi-Fi and refresh again to complete your kit."
        }
    }

    /// Picks the trip the offline kit should target. Mirrors how the rest of the
    /// app treats a trip as "current": a trip that has already started but not yet
    /// ended (in progress) always wins over a not-yet-started future trip — even
    /// if the future trip has an earlier `startDate` than the in-progress trip's
    /// `endDate`. Among in-progress trips we take the one ending soonest; when
    /// none is in progress we fall back to the soonest upcoming trip.
    private func nextTrip() -> Trip? {
        guard let trips = CodableDefaults.load([Trip].self, forKey: "jetsetter_trips") else { return nil }
        let now = Date()

        let inProgress = trips
            .filter { $0.startDate <= now && $0.endDate >= now }
            .sorted { $0.endDate < $1.endDate }
        if let current = inProgress.first { return current }

        return trips
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private func loadWalletItems() -> [WalletItem] {
        return CodableDefaults.load([WalletItem].self, forKey: "jetsetter_wallet_items") ?? []
    }
}

#Preview {
    NavigationStack { OfflineKitView() }
}
