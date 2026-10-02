// File: Features/FlightTracker/FlightTrackerView.swift
//
// Flight Tracker: search a flight number and see its status, gates and times.
//
// Offline behaviour (see `FlightTrackerViewModel`): results never blank on a
// failed refresh. Errors appear as a banner with Retry above the last results,
// "Updated 12 min ago" says how old they are, and "LIVE" shows only for a
// result fetched in the last 10 minutes. On open, the most recent saved flight
// comes back from the cache and refreshes in the background.

import SwiftUI

// MARK: - FlightTrackerView

struct FlightTrackerView: View {

    @State private var viewModel = FlightTrackerViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var stateIconSize: CGFloat = 52

    // No NavigationStack here: it is shown as a sheet (Home, and the routed
    // sheet in ContentView), and those call sites wrap it with
    // `.inSheetNavigation()`, which also gives it the Done button it lacked.
    // The stack must still be an ancestor: rows push `FlightDetailView`.
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultContent
        }
        .navigationTitle("Flight Tracker")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        // the app can ask the tracker to look up a flight via the trackFlight tool.
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterTrackFlight)) { note in
            guard let ident = note.object as? String, !ident.isEmpty else { return }
            viewModel.searchText = ident
            Task { await viewModel.searchFlight(ident: ident) }
        }
        .task {
            // Reopen on the last flight, from the saved copy, then try to
            // bring it up to date. Offline, the saved copy simply stays.
            if viewModel.restoreLastSearch() {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Flight number (e.g. AA100)", text: $viewModel.searchText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchFlight(ident: viewModel.searchText) }
                    }
                    .accessibilityLabel("Flight number")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .clipShape(.rect(cornerRadius: 12))

            Button {
                Task { await viewModel.searchFlight(ident: viewModel.searchText) }
            } label: {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.medium)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accentFill)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
        .tripDayReadableWidth()
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if !viewModel.flights.isEmpty {
            // Results win over every other state: a refresh in progress or a
            // failed one shows on top of them, never instead of them.
            flightList
        } else if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            messageView(errorMessage, canRetry: !viewModel.isLiveStatusUnavailable)
        } else {
            emptyStateView
        }
    }

    // MARK: - Flight List

    private var flightList: some View {
        ScrollView {
            VStack(spacing: 0) {
                statusBar

                if let message = viewModel.errorMessage {
                    errorBanner(message)
                        .padding(.horizontal, JetsetterTheme.Spacing.medium)
                        .padding(.bottom, JetsetterTheme.Spacing.small)
                }

                // ── Flight cards ──────────────────────────────────────────────
                LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                    ForEach(viewModel.flights) { flight in
                        NavigationLink(destination: FlightDetailView(flight: flight, updatedAt: viewModel.lastUpdated)) {
                            FlightRowView(flight: flight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(FlightRowView.accessibilityText(for: flight))
                        .accessibilityHint("Shows gates and times")
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
            }
            .tripDayReadableWidth()
        }
        .refreshable { await viewModel.refresh() }
    }

    /// LIVE badge (fresh data only), freshness stamp and refresh button.
    /// TimelineView re-evaluates every 30 s, so the stamp counts up and LIVE
    /// drops off at 10 minutes without any other state changing.
    private var statusBar: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 6) {
                if viewModel.showsLiveBadge(now: context.date) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(JetsetterTheme.Colors.success)
                            .frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.system(.caption2, design: .rounded, weight: .black))
                            .tracking(1)
                            .foregroundStyle(JetsetterTheme.Colors.success)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live status")
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing")
                }

                if let updated = viewModel.lastUpdated {
                    Text(FlightTrackerViewModel.updatedText(since: updated, now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(FlightTrackerViewModel.updatedText(
                            since: updated, now: context.date, unitsStyle: .full))
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
                .accessibilityLabel("Refresh flight status")
            }
            .padding(.horizontal, JetsetterTheme.Spacing.medium)
            .padding(.vertical, 10)
        }
    }

    /// A failed refresh over results that are still on screen.
    private func errorBanner(_ message: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return layout {
            Label {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: viewModel.isLiveStatusUnavailable ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !viewModel.isLiveStatusUnavailable {
                Button("Retry") {
                    Task { await viewModel.refresh() }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(viewModel.isLoading)
                .accessibilityHint("Tries to load the latest status again")
            }
        }
        .padding(12)
        .background(JetsetterTheme.Colors.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView()
                .controlSize(.large)
            Text("Searching flights…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message View (nothing to show)

    /// No results and nothing saved: the error (with Retry), or the plain
    /// "not switched on in this build" sentence (without one).
    private func messageView(_ message: String, canRetry: Bool) -> some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                Image(systemName: canRetry ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: stateIconSize))
                    .foregroundStyle(canRetry ? JetsetterTheme.Colors.warning : .secondary)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)

                if canRetry, !viewModel.currentIdent.isEmpty {
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                }
            }
            .padding(.top, JetsetterTheme.Spacing.xlarge)
            .tripDayReadableWidth()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "airplane")
                .font(.system(size: stateIconSize))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
                .accessibilityHidden(true)

            Text("Search for a flight")
                .font(.headline)

            Text("Enter a flight number above to check status, gates, and delays.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FlightRowView

private struct FlightRowView: View {
    let flight: Flight

    /// "UA2391, United Airlines, Chicago to New York, On Time".
    static func accessibilityText(for flight: Flight) -> String {
        [
            flight.identIata ?? flight.ident,
            flight.operatorName ?? "Unknown airline",
            TripSpeech.spokenRoute([flight.origin.codeIata, flight.destination.codeIata]),
            flight.status
        ].joined(separator: ", ")
    }

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
                .clipShape(.rect(cornerRadius: 8))
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
    NavigationStack { FlightTrackerView() }
}
