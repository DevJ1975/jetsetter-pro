// File: Features/FlightTracker/FlightTrackerView.swift

import SwiftUI

// MARK: - FlightTrackerView

/// Main search and results screen for the Flight Tracker feature.
/// Display only — all logic lives in FlightTrackerViewModel.
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

                // Show clear button only when there is text
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
}

// MARK: - FlightRowView

/// A single card row representing one flight in the search results list.
private struct FlightRowView: View {
    let flight: Flight

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            // Route info
            VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
                Text(flight.identIata ?? flight.ident)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(flight.operatorName ?? "Unknown airline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Origin → Destination
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

            // Status badge
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
