// File: Features/TravelWallet/CheckInCardView.swift

import SwiftUI
import SafariServices

// MARK: - CheckInCardView

/// Displayed inside WalletItemDetailView for boarding passes.
/// Resolves the airline's check-in URL and presents it in SFSafariViewController.
struct CheckInCardView: View {

    let iataCode: String
    let flightNumber: String
    let departureDate: Date

    @State private var result: CheckInResult? = nil
    @State private var isLoading: Bool = false
    @State private var showSafari: Bool = false
    @State private var safariURL: URL? = nil
    @State private var notificationScheduled: Bool = false
    @State private var errorMessage: String? = nil

    private var checkInOpensAt: Date {
        // Check-in window typically opens 24 h before departure
        departureDate.addingTimeInterval(-24 * 3_600)
    }

    private var checkInIsOpen: Bool {
        Date() >= checkInOpensAt
    }

    private var timeUntilCheckIn: String {
        let interval = checkInOpensAt.timeIntervalSinceNow
        guard interval > 0 else { return "Open now" }
        let hours = Int(interval / 3_600)
        let mins  = Int((interval.truncatingRemainder(dividingBy: 3_600)) / 60)
        if hours > 0 { return "Opens in \(hours)h \(mins)m" }
        return "Opens in \(mins)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text("ONLINE CHECK-IN")
                .font(JetsetterTheme.Typography.label)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: JetsetterTheme.Spacing.medium) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Looking up check-in link…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(JetsetterTheme.Spacing.medium)
                } else if let result {
                    resolvedCard(result: result)
                } else if let error = errorMessage {
                    errorCard(message: error)
                }
            }
            .jetCard()
        }
        .task { await loadCheckInLink() }
        // SFSafariViewController presented via UIViewControllerRepresentable
        .sheet(isPresented: $showSafari) {
            if let url = safariURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Resolved Card

    @ViewBuilder
    private func resolvedCard(result: CheckInResult) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.medium) {
            // Airline icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(JetsetterTheme.Colors.accent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "airplane")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.airlineName)
                    .font(.system(size: 15, weight: .semibold))
                Text(flightNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(departureDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if result.source == .fallback {
                    Text("Fallback")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(timeUntilCheckIn)
                    .font(.caption2)
                    .foregroundStyle(checkInIsOpen ? JetsetterTheme.Colors.success : .secondary)
            }
        }
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.top, JetsetterTheme.Spacing.medium)

        Divider().padding(.horizontal, JetsetterTheme.Spacing.medium)

        VStack(spacing: JetsetterTheme.Spacing.small) {
            // Primary: Check In Now / disabled state
            Button {
                safariURL = result.mobileURL ?? result.webURL
                showSafari = true
            } label: {
                HStack {
                    Image(systemName: checkInIsOpen ? "checkmark.seal.fill" : "clock.fill")
                    Text(checkInIsOpen ? "Check In Now" : "Check In (Not Yet Open)")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(JetsetterTheme.Spacing.small + 2)
                .background(checkInIsOpen ? JetsetterTheme.Colors.accent : Color(.systemFill))
                .foregroundStyle(checkInIsOpen ? .white : .secondary)
                .cornerRadius(10)
            }
            .disabled(!checkInIsOpen)

            // Notification toggle
            HStack {
                Image(systemName: notificationScheduled ? "bell.fill" : "bell")
                    .foregroundStyle(notificationScheduled ? JetsetterTheme.Colors.accent : .secondary)
                    .font(.subheadline)
                Text(notificationScheduled
                     ? "You'll be notified when check-in opens"
                     : "Notify me when check-in opens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notificationScheduled },
                    set: { newValue in
                        Task { await toggleNotification(newValue, airlineName: result.airlineName) }
                    }
                ))
                .labelsHidden()
                .tint(JetsetterTheme.Colors.accent)
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
    }

    // MARK: - Error Card

    private func errorCard(message: String) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JetsetterTheme.Colors.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(JetsetterTheme.Spacing.medium)
    }

    // MARK: - Actions

    private func loadCheckInLink() async {
        guard !iataCode.isEmpty else {
            errorMessage = "Airline code unavailable for this flight."
            return
        }
        isLoading = true
        result = await CheckInService.shared.checkInResult(for: iataCode)
        isLoading = false
        if result == nil {
            errorMessage = "Check-in link unavailable. Visit the airline's website directly."
        }
    }

    private func toggleNotification(_ on: Bool, airlineName: String) async {
        if on {
            await CheckInService.shared.scheduleCheckInNotification(
                airlineName: airlineName,
                flightNumber: flightNumber,
                departureDate: departureDate
            )
            notificationScheduled = true
        } else {
            Task {
                await CheckInService.shared.cancelCheckInNotification(
                    flightNumber: flightNumber,
                    departureDate: departureDate
                )
            }
            notificationScheduled = false
        }
    }
}

// MARK: - SafariView

/// Wraps SFSafariViewController in a SwiftUI-compatible UIViewControllerRepresentable.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            CheckInCardView(
                iataCode: "DL",
                flightNumber: "DL 400",
                departureDate: Date().addingTimeInterval(20 * 3_600)
            )
            .padding()
        }
    }
}
