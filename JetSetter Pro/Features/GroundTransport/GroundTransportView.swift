// File: Features/GroundTransport/GroundTransportView.swift

import SwiftUI
import CoreLocation

// MARK: - GroundTransportView

/// Ground transport screen: a real driving time for the route, then one tap
/// into Uber or Lyft with pickup and destination already filled in.
struct GroundTransportView: View {

    @State private var viewModel = GroundTransportViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                locationForm
                Divider()
                resultContent
            }
            .navigationTitle("Ground Transport")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .inAppWeb(url: $viewModel.externalWebURL, title: "Book a Ride")
        }
    }

    // MARK: - Location Form

    private var locationForm: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            // Pickup row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                Circle()
                    .fill(JetsetterTheme.Colors.success)
                    .frame(width: 10, height: 10)

                Text(viewModel.pickupAddress)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.isLocating ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                // Refresh location button
                Button {
                    Task { await viewModel.detectCurrentLocation() }
                } label: {
                    Image(systemName: viewModel.isLocating ? "location.fill" : "location.circle")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .symbolEffect(.pulse, isActive: viewModel.isLocating)
                }
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .clipShape(.rect(cornerRadius: 10))

            // Dropoff row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                Circle()
                    .fill(JetsetterTheme.Colors.danger)
                    .frame(width: 10, height: 10)

                TextField("Where to?", text: $viewModel.dropoffAddress)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.findRides() }
                    }

                if !viewModel.dropoffAddress.isEmpty {
                    Button {
                        viewModel.dropoffAddress = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .clipShape(.rect(cornerRadius: 10))

            // Search button
            Button {
                Task { await viewModel.findRides() }
            } label: {
                Text("Find a Ride")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        viewModel.dropoffAddress.isEmpty
                            ? JetsetterTheme.Colors.accent.opacity(0.4)
                            : JetsetterTheme.Colors.accent
                    )
                    .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(viewModel.dropoffAddress.isEmpty)
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isLoadingRoute {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else if viewModel.rideOptions.isEmpty && viewModel.hasSearched {
            noRidesView
        } else if viewModel.rideOptions.isEmpty {
            promptView
        } else {
            rideList
        }
    }

    // MARK: - Ride List

    private var rideList: some View {
        ScrollView {
            LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                if let first = viewModel.rideOptions.first {
                    HStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                        Text("About \(first.estimatedMinutes) min · \(first.formattedDistance) by car")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                }

                ForEach(viewModel.rideOptions) { option in
                    RideOptionCard(option: option) {
                        viewModel.open(option: option)
                    }
                }

                Text("Fares are quoted by the ride app once you open it — JetSetter Pro never estimates a price it can't verify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView().scaleEffect(1.4)
            Text("Checking the drive…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.warning)
            Text(message)
                .font(.body).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noRidesView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "car.fill")
                .font(.system(size: 44))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
            Text("Couldn't plan that route")
                .font(.headline)
            Text("Try a more specific destination address.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            Text("Get a Ride")
                .font(.headline)

            Text("Enter your destination above. We'll check the drive and open Uber or Lyft with the route filled in.")
                .font(.subheadline).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RideOptionCard

/// One provider card: driving time, distance, and an "Open" button.
private struct RideOptionCard: View {
    let option: RideOption
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: option.provider.iconName)
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.primary.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(JetsetterTheme.Colors.primary.opacity(0.08))
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(option.provider.displayName)
                    .font(.headline)
                HStack(spacing: JetsetterTheme.Spacing.small) {
                    Label("\(option.estimatedMinutes) min", systemImage: "clock")
                    Label(option.formattedDistance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onOpen) {
                Label("Open \(option.provider.displayName)", systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(JetsetterTheme.Colors.accent)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .disabled(option.rideURL == nil)
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Preview

#Preview("Prompt State") {
    GroundTransportView()
}

#Preview("With Ride Options") {
    NavigationStack {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ForEach(RideOption.sampleOptions) { option in
                RideOptionCard(option: option, onOpen: {})
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ground Transport")
    }
}
