// File: Features/Booking/FlightSearchView.swift

import SwiftUI

// MARK: - FlightSearchView

/// Flight search form. Collects route, dates, and passengers. With backend
/// flights enabled, Search runs the in-app booking flow and "Compare on Kayak"
/// stays as the vendor route; otherwise it hands off to a flight site (Kayak)
/// pre-filled with the search, presented in-app, exactly as before.
struct FlightSearchView: View {

    @State private var viewModel = FlightSearchViewModel()
    @State private var backend = BackendStatus.shared

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.small) {
                if viewModel.usesInAppBooking && backend.isTestMode {
                    TestModeBanner()
                }
                tripTypePicker
                routeFields
                dateFields
                if viewModel.usesInAppBooking {
                    cabinPicker
                }
                passengersAndSearch

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                if viewModel.usesInAppBooking {
                    compareOnKayakButton
                }

                helperText

                HandoffProvidersSection(kind: .flights, query: handoffQuery, webURL: $viewModel.externalWebURL)
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
        .background(Color(.systemGroupedBackground))
        .vendorHandoffWeb(url: $viewModel.externalWebURL, kind: .flight, title: "Flights",
                          destinationHint: viewModel.searchParams.destinationCode)
        .sheet(item: $viewModel.flightFlow) { flow in
            FlightBookingFlowView(model: flow, kayakURL: viewModel.kayakURL)
        }
        // Learn whether the backend has flights switched on. A failure keeps the
        // last known answer, so this never blanks the form.
        .task { await backend.refresh() }
    }

    /// Whether (and how) to offer extra vendor links from the backend.
    private var handoffQuery: [URLQueryItem]? {
        let params = viewModel.searchParams
        return HandoffQuery.flights(
            origin: params.origin, destination: params.destination,
            depart: params.departDate,
            return: params.tripType == .roundTrip ? params.returnDate : nil,
            adults: params.adults
        )
    }

    // MARK: - Trip Type

    private var tripTypePicker: some View {
        Picker("Trip type", selection: $viewModel.searchParams.tripType) {
            ForEach(FlightTripType.allCases) { type in
                Text(type.label).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Route

    private var routeFields: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            airportField(title: "From", placeholder: "JFK", text: $viewModel.searchParams.origin)
            Image(systemName: "airplane")
                .foregroundStyle(.secondary)
            airportField(title: "To", placeholder: "LAX", text: $viewModel.searchParams.destination)
        }
    }

    private func airportField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.headline)
        }
        .padding(JetsetterTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Dates

    /// Two compact date pickers don't fit on one line in a 320 pt side-by-side
    /// window, so a round trip's dates stack when they must.
    private var dateFields: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: JetsetterTheme.Spacing.small) { dateFieldContent }
            VStack(spacing: JetsetterTheme.Spacing.small) { dateFieldContent }
        }
    }

    @ViewBuilder
    private var dateFieldContent: some View {
        datePickerField(
            label: "Depart",
            selection: $viewModel.searchParams.departDate,
            minDate: Self.earliestDate
        )
        if viewModel.searchParams.tripType == .roundTrip {
            datePickerField(
                label: "Return",
                selection: $viewModel.searchParams.returnDate,
                minDate: viewModel.searchParams.departDate
            )
        }
    }

    private func datePickerField(label: String, selection: Binding<Date>, minDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, JetsetterTheme.Spacing.small)
            DatePicker("", selection: selection, in: minDate..., displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .padding(.horizontal, JetsetterTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, JetsetterTheme.Spacing.xsmall)
        .background(.background)
        .clipShape(.rect(cornerRadius: 10))
    }

    // MARK: - Cabin

    private var cabinPicker: some View {
        HStack {
            Image(systemName: "chair.lounge.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Picker("Cabin", selection: $viewModel.searchParams.cabinClass) {
                ForEach(BackendCabinClass.allCases) { cabin in
                    Text(cabin.label).tag(cabin)
                }
            }
            .pickerStyle(.menu)
            Spacer()
        }
        .font(.subheadline)
        .padding(JetsetterTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var compareOnKayakButton: some View {
        Button {
            viewModel.compareOnKayak()
        } label: {
            Label("Compare on Kayak", systemImage: "safari")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(JetsetterTheme.Colors.accent)
        }
        .padding(.top, JetsetterTheme.Spacing.xsmall)
    }

    // MARK: - Passengers + Search

    private var passengersAndSearch: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Stepper(
                    "\(viewModel.searchParams.adults) Passenger\(viewModel.searchParams.adults == 1 ? "" : "s")",
                    value: $viewModel.searchParams.adults,
                    in: 1...8
                )
                .font(.subheadline)
            }
            .padding(JetsetterTheme.Spacing.small)
            .background(.background)
            .clipShape(.rect(cornerRadius: 10))

            Button {
                viewModel.searchFlights()
            } label: {
                Text("Search")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
                    .padding(.vertical, 10)
                    .background(JetsetterTheme.Colors.accent)
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Error + Helper

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JetsetterTheme.Colors.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JetsetterTheme.Spacing.small)
    }

    private var helperText: some View {
        Text(viewModel.usesInAppBooking
             ? "Search airlines and book right here, or compare the same trip on Kayak."
             : "We'll open the flight site with your search filled in, right here in the app.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, JetsetterTheme.Spacing.small)
    }

    // MARK: - Date Bounds

    /// Flights can't be searched for a past date.
    private static var earliestDate: Date {
        Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FlightSearchView()
            .navigationTitle("Book")
    }
}
