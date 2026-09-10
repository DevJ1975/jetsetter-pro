// File: Features/Booking/BookingView.swift

import SwiftUI

// MARK: - BookingView

/// Booking screen — hotels hand off to a hotel site pre-filled from the form and
/// list nearby properties from Apple Maps; flights hand off to a flight site.
struct BookingView: View {

    /// Which kind of booking the user is searching for.
    private enum BookingMode: String, CaseIterable, Identifiable {
        case hotels = "Hotels"
        case flights = "Flights"
        var id: String { rawValue }
    }

    @State private var viewModel = BookingViewModel()
    @State private var isShowingSearch: Bool = false
    @State private var mode: BookingMode = .hotels

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Booking type", selection: $mode) {
                    ForEach(BookingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(JetsetterTheme.Spacing.medium)
                .background(Color(.systemGroupedBackground))

                Divider()

                switch mode {
                case .hotels:
                    hotelContent
                case .flights:
                    FlightSearchView()
                }
            }
            .navigationTitle("Book")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .inAppWeb(url: $viewModel.externalWebURL, title: "Hotels")
        }
    }

    // MARK: - Hotel Content

    /// The existing hotel search form + results, shown when the Hotels tab is
    /// selected. Extracted so the mode switch above stays readable.
    private var hotelContent: some View {
        VStack(spacing: 0) {
            searchForm
            Divider()
            resultContent
        }
        .onChange(of: viewModel.searchParams.destination) {
            // Editing the destination invalidates the previous results, so
            // return to the neutral "Find Your Stay" prompt instead of
            // leaving the stale "No Hotels Found" framing from a prior run.
            viewModel.invalidateResults()
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
            .clipShape(.rect(cornerRadius: 10))

            // Date pickers row
            HStack(spacing: JetsetterTheme.Spacing.small) {
                datePickerField(
                    label: "Check-in",
                    icon: "calendar",
                    selection: $viewModel.searchParams.checkInDate,
                    minDate: Self.earliestCheckIn,
                    maxDate: Self.latestCheckIn
                )

                datePickerField(
                    label: "Check-out",
                    icon: "calendar",
                    selection: $viewModel.searchParams.checkOutDate,
                    minDate: viewModel.searchParams.checkInDate,
                    maxDate: latestCheckOut
                )
            }

            // Guests + Browse row
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
                .clipShape(.rect(cornerRadius: 10))

                // Browse nearby hotels (Apple Maps)
                Button {
                    Task { await viewModel.findNearbyHotels() }
                } label: {
                    Text("Browse")
                        .fontWeight(.semibold)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .padding(.horizontal, JetsetterTheme.Spacing.large)
                        .padding(.vertical, 10)
                        .background(JetsetterTheme.Colors.accent.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 10))
                }
            }

            // Hand-off: rates and booking happen on the hotel site, pre-filled.
            Button {
                viewModel.openHotelSite()
            } label: {
                Label("Search Rates on \(viewModel.providerName)", systemImage: "safari")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(JetsetterTheme.Colors.accent)
                    .clipShape(.rect(cornerRadius: 12))
            }
            .disabled(viewModel.searchParams.destination.trimmingCharacters(in: .whitespaces).isEmpty)
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
        } else if viewModel.nearbyHotels.isEmpty && viewModel.hasSearched {
            emptyResultsView
        } else if viewModel.nearbyHotels.isEmpty {
            promptView
        } else {
            hotelList
        }
    }

    // MARK: - Hotel List

    private var hotelList: some View {
        ScrollView {
            LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                Text("\(viewModel.nearbyHotels.count) hotels near \(viewModel.searchParams.destination) · from Apple Maps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.nearbyHotels) { hotel in
                    Button { viewModel.open(hotel) } label: {
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
            Text("Looking up hotels…")
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
            title: "No Hotels Listed",
            subtitle: "Apple Maps has nothing near there yet. Try a larger city, or search rates directly."
        )
    }

    private var promptView: some View {
        placeholderState(
            icon: "bed.double.fill",
            title: "Find Your Stay",
            subtitle: "Enter a destination and dates, then search rates on \(viewModel.providerName) or browse hotels nearby."
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
        minDate: Date? = nil,
        maxDate: Date? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.small)

            Group {
                switch (minDate, maxDate) {
                case let (min?, max?) where min <= max:
                    DatePicker("", selection: selection, in: min...max, displayedComponents: .date)
                case let (min?, _):
                    DatePicker("", selection: selection, in: min..., displayedComponents: .date)
                case let (_, max?):
                    DatePicker("", selection: selection, in: ...max, displayedComponents: .date)
                default:
                    DatePicker("", selection: selection, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .datePickerStyle(.compact)
            .padding(.horizontal, JetsetterTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JetsetterTheme.Spacing.xsmall)
        .background(.background)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Date Bounds

    /// Bookings can't be made for a past date.
    private static var earliestCheckIn: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// How far ahead a stay may be booked (matches typical availability windows).
    private static let bookingHorizonInDays = 500

    /// The maximum length of a single stay, in nights.
    private static let maxStayInNights = 30

    /// Latest selectable check-in date (today + booking horizon).
    private static var latestCheckIn: Date {
        Calendar.current.date(byAdding: .day, value: bookingHorizonInDays, to: earliestCheckIn) ?? earliestCheckIn
    }

    /// Latest selectable check-out date: capped at check-in + max stay, but
    /// never beyond the overall booking horizon.
    private var latestCheckOut: Date {
        let checkIn = viewModel.searchParams.checkInDate
        let byStay = Calendar.current.date(byAdding: .day, value: Self.maxStayInNights, to: checkIn) ?? checkIn
        return min(byStay, Self.latestCheckIn)
    }
}

// MARK: - HotelRowView

/// A hotel near the destination, from Apple Maps. Rates live on the hotel site.
private struct HotelRowView: View {
    let hotel: HotelPlace

    var body: some View {
        HStack(alignment: .center, spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.primary.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(JetsetterTheme.Colors.primary.opacity(0.08))
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(hotel.name)
                    .font(.headline)
                    .lineLimit(1)
                if !hotel.address.isEmpty {
                    Text(hotel.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Label(hotel.formattedDistance + " from centre", systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(JetsetterTheme.Colors.accent)
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Preview

#Preview("Search Form") {
    BookingView()
}

#Preview("Nearby Hotels") {
    NavigationStack {
        VStack {
            ForEach(HotelPlace.samples) { hotel in
                HotelRowView(hotel: hotel)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
