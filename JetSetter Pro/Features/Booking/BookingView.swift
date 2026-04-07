// File: Features/Booking/BookingView.swift

import SwiftUI

// MARK: - BookingView

/// Hotel search screen — users enter destination, dates, and guests to find available properties.
struct BookingView: View {

    @StateObject private var viewModel = BookingViewModel()
    @State private var isShowingSearch: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchForm
                Divider()
                resultContent
            }
            .navigationTitle("Book")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Search Form

    private var searchForm: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            // Destination field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Destination (e.g. Tokyo)", text: $viewModel.searchParams.destination)
                    .autocorrectionDisabled()
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .cornerRadius(10)

            // Date pickers row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                datePickerField(
                    label: "Check-in",
                    icon: "calendar",
                    selection: $viewModel.searchParams.checkInDate
                )

                datePickerField(
                    label: "Check-out",
                    icon: "calendar",
                    selection: $viewModel.searchParams.checkOutDate,
                    minDate: viewModel.searchParams.checkInDate
                )
            }

            // Guests + Search row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                // Guest stepper
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Stepper(
                        "\(viewModel.searchParams.adults) Guest\(viewModel.searchParams.adults == 1 ? "" : "s")",
                        value: $viewModel.searchParams.adults,
                        in: 1...8
                    )
                    .font(.subheadline)
                }
                .padding(JetsetterTheme.Spacing.small)
                .background(.background)
                .cornerRadius(10)

                // Search button
                Button {
                    Task { await viewModel.searchHotels() }
                } label: {
                    Text("Search")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, JetsetterTheme.Spacing.large)
                        .padding(.vertical, 10)
                        .background(JetsetterTheme.Colors.accent)
                        .cornerRadius(10)
                }
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
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else if viewModel.hotels.isEmpty && viewModel.hasSearched {
            emptyResultsView
        } else if viewModel.hotels.isEmpty {
            promptView
        } else {
            hotelList
        }
    }

    // MARK: - Hotel List

    private var hotelList: some View {
        ScrollView {
            LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                Text("\(viewModel.hotels.count) properties found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.hotels) { hotel in
                    NavigationLink(
                        destination: HotelDetailView(
                            hotel: hotel,
                            searchParams: viewModel.searchParams
                        )
                    ) {
                        HotelRowView(hotel: hotel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            ProgressView().scaleEffect(1.4)
            Text("Searching hotels…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

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

    // MARK: - Empty / Prompt States

    private var emptyResultsView: some View {
        placeholderState(
            icon: "building.2",
            title: "No Hotels Found",
            subtitle: "Try adjusting your dates or searching a different destination."
        )
    }

    private var promptView: some View {
        placeholderState(
            icon: "ticket.fill",
            title: "Find Your Stay",
            subtitle: "Enter a destination and dates above to search for available hotels."
        )
    }

    private func placeholderState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Date Picker Field

    private func datePickerField(
        label: String,
        icon: String,
        selection: Binding<Date>,
        minDate: Date? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.small)

            if let minDate = minDate {
                DatePicker("", selection: selection, in: minDate..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(.horizontal, JetsetterTheme.Spacing.small)
            } else {
                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(.horizontal, JetsetterTheme.Spacing.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JetsetterTheme.Spacing.xsmall)
        .background(.background)
        .cornerRadius(10)
    }
}

// MARK: - HotelRowView

/// A single hotel card row in the search results list.
private struct HotelRowView: View {
    let hotel: HotelProperty

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            // Property icon
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.primary.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(JetsetterTheme.Colors.primary.opacity(0.08))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(hotel.name ?? "Property \(hotel.propertyId)")
                    .font(.headline)

                if let score = hotel.score {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(hotel.rooms.count) room type\(hotel.rooms.count == 1 ? "" : "s") available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Price
            VStack(alignment: .trailing, spacing: 2) {
                if let lowest = hotel.lowestNightlyRate {
                    Text("\(hotel.lowestRateCurrency) \(String(format: "%.0f", lowest))")
                        .font(.headline)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    Text("/ night")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Preview

#Preview("Search Form") {
    BookingView()
}

#Preview("With Results") {
    let viewModel = BookingViewModel()
    Task { @MainActor in
        viewModel.hotels = HotelProperty.sampleProperties
        viewModel.hasSearched = true
    }
    return NavigationStack {
        VStack {
            ForEach(HotelProperty.sampleProperties) { hotel in
                HotelRowView(hotel: hotel)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
