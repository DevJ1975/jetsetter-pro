// File: Features/Booking/FlightSearchView.swift

import SwiftUI

// MARK: - FlightSearchView

/// Flight search form. Collects route, dates, and passengers, then hands off to
/// a flight site (Kayak) pre-filled with the search, presented in-app.
struct FlightSearchView: View {

    @State private var viewModel = FlightSearchViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.small) {
                tripTypePicker
                routeFields
                dateFields
                passengersAndSearch

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                helperText
            }
            .padding(JetsetterTheme.Spacing.medium)
        }
        .background(Color(.systemGroupedBackground))
        .inAppWeb(url: $viewModel.externalWebURL, title: "Flights")
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

    private var dateFields: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
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
        Text("We'll open the flight site with your search filled in, right here in the app.")
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
