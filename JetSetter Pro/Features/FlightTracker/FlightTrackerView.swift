// File: Features/FlightTracker/FlightTrackerView.swift

import SwiftUI

// MARK: - FlightTrackerView

struct FlightTrackerView: View {

    @StateObject private var viewModel = FlightTrackerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                resultContent
            }
            .navigationTitle("Flight Tracker")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Flight number (e.g. AA100)", text: $viewModel.searchText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchFlight(ident: viewModel.searchText) }
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .cornerRadius(12)

            Button {
                Task { await viewModel.searchFlight(ident: viewModel.searchText) }
            } label: {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.medium)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accent)
                    .cornerRadius(12)
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(message: errorMessage)
        } else if viewModel.flights.isEmpty {
            emptyStateView
        } else {
            flightList
        }
    }

    // MARK: - Flight List

    private var flightList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Live status bar ───────────────────────────────────────────
                HStack(spacing: 6) {
                    // Pulsing green dot
                    Circle()
                        .fill(JetsetterTheme.Colors.success)
                        .frame(width: 7, height: 7)

                    Text("LIVE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(JetsetterTheme.Colors.success)

                    Spacer()

                    if let updated = viewModel.lastUpdated {
                        Text("Updated \(relativeTime(from: updated))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                    .disabled(viewModel.isLoading)
                    .padding(.leading, 6)
                }
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                // ── Flight cards ──────────────────────────────────────────────
                LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                    ForEach(viewModel.flights) { flight in
                        NavigationLink(destination: FlightDetailView(flight: flight)) {
                            FlightRowView(flight: flight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Searching flights…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(JetsetterTheme.Colors.warning)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "airplane")
                .font(.system(size: 56))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            Text("Search for a flight")
                .font(.headline)

            Text("Enter a flight number above to check\nstatus, gates, and delays.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60  { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - FlightRowView

private struct FlightRowView: View {
    let flight: Flight

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
                Text(flight.identIata ?? flight.ident)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(flight.operatorName ?? "Unknown airline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: JetsetterTheme.Spacing.small) {
                Text(flight.origin.codeIata ?? "—")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(flight.destination.codeIata ?? "—")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(flight.status)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(flight.status.flightStatusColor.opacity(0.15))
                .foregroundStyle(flight.status.flightStatusColor)
                .cornerRadius(8)
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Preview

#Preview("Flight Results") {
    NavigationStack {
        VStack {
            FlightRowView(flight: .sample)
            FlightRowView(flight: .sampleDelayed)
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Flight Tracker")
    }
}

#Preview("Empty State") {
    FlightTrackerView()
}
