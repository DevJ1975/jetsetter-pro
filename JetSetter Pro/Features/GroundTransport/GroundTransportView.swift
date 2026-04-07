// File: Features/GroundTransport/GroundTransportView.swift

import SwiftUI
import CoreLocation

// MARK: - GroundTransportView

/// Ground transport screen showing ride estimates from Uber and Lyft.
/// Tapping a ride option deep-links into the respective app for booking.
struct GroundTransportView: View {

    @StateObject private var viewModel = GroundTransportViewModel()

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
            .cornerRadius(10)

            // Dropoff row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                Circle()
                    .fill(JetsetterTheme.Colors.danger)
                    .frame(width: 10, height: 10)

                TextField("Where to?", text: $viewModel.dropoffAddress)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.fetchEstimates() }
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
            .cornerRadius(10)

            // Search button
            Button {
                Task { await viewModel.fetchEstimates() }
            } label: {
                Text("Get Ride Estimates")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        viewModel.dropoffAddress.isEmpty
                            ? JetsetterTheme.Colors.accent.opacity(0.4)
                            : JetsetterTheme.Colors.accent
                    )
                    .cornerRadius(12)
            }
            .disabled(viewModel.dropoffAddress.isEmpty)
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isLoadingEstimates {
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
                // Group by provider
                ForEach(RideProvider.allCases, id: \.self) { provider in
                    let options = viewModel.rideOptions.filter { $0.provider == provider }
                    if !options.isEmpty {
                        providerSection(provider: provider, options: options)
                    }
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
    }

    private func providerSection(provider: RideProvider, options: [RideOption]) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            // Provider header
            HStack {
                Image(systemName: provider.iconName)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text(provider.displayName)
                    .font(.headline)
            }

            ForEach(options) { option in
                RideOptionCard(option: option) {
                    viewModel.book(option: option)
                }
            }
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView().scaleEffect(1.4)
            Text("Finding rides near you…")
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
            Text("No rides available")
                .font(.headline)
            Text("Try a different destination or check back shortly.")
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

            Text("Enter your destination above to compare Uber and Lyft prices instantly.")
                .font(.subheadline).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RideOptionCard

/// A single ride option card showing product name, price, ETA, and a Book button.
private struct RideOptionCard: View {
    let option: RideOption
    let onBook: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            // Ride type icon
            Image(systemName: option.provider.iconName)
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.primary.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(JetsetterTheme.Colors.primary.opacity(0.08))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(option.productName)
                        .font(.headline)

                    // Surge badge
                    if option.isSurging {
                        Text("Surge")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(JetsetterTheme.Colors.danger)
                            .cornerRadius(6)
                    }
                }

                HStack(spacing: JetsetterTheme.Spacing.small) {
                    Label("\(option.estimatedMinutes) min away", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(option.priceRange)
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.accent)

                Button(action: onBook) {
                    Text("Book")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(JetsetterTheme.Colors.accent)
                        .cornerRadius(8)
                }
            }
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
                RideOptionCard(option: option) {}
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ground Transport")
    }
}
