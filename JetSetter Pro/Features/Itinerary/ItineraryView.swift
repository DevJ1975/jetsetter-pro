// File: Features/Itinerary/ItineraryView.swift

import SwiftUI

// MARK: - ItineraryView

/// Main itinerary screen showing the list of trips.
/// Tapping a trip shows its items; items can be synced to Calendar.
struct ItineraryView: View {

    @StateObject private var viewModel = ItineraryViewModel()
    @State private var isShowingAddTrip: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trips.isEmpty {
                    emptyStateView
                } else {
                    tripList
                }
            }
            .navigationTitle("Itinerary")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAddTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddTrip) {
                AddTripView(viewModel: viewModel)
            }
            // Show calendar status banner
            .overlay(alignment: .top) {
                if let status = viewModel.calendarStatusMessage {
                    calendarBanner(message: status)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation { viewModel.calendarStatusMessage = nil }
                            }
                        }
                }
            }
            .animation(.easeInOut, value: viewModel.calendarStatusMessage)
        }
    }

    // MARK: - Trip List

    private var tripList: some View {
        List {
            ForEach(viewModel.trips) { trip in
                NavigationLink(destination: TripDetailView(trip: trip, viewModel: viewModel)) {
                    TripRowView(trip: trip)
                }
            }
            .onDelete { offsets in
                viewModel.deleteTrip(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("No Trips Yet")
                    .font(.headline)
                Text("Tap + to create your first trip and start building your itinerary.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }

            Button {
                isShowingAddTrip = true
            } label: {
                Text("Create Trip")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
                    .padding(.vertical, JetsetterTheme.Spacing.small)
                    .background(JetsetterTheme.Colors.accent)
                    .cornerRadius(12)
            }
            Spacer()
        }
    }

    // MARK: - Calendar Banner

    private func calendarBanner(message: String) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(JetsetterTheme.Colors.success)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.top, JetsetterTheme.Spacing.small)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

// MARK: - TripRowView

private struct TripRowView: View {
    let trip: Trip

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
            Text(trip.name)
                .font(.headline)

            Text(trip.destination)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("\(dateFormatter.string(from: trip.startDate)) – \(dateFormatter.string(from: trip.endDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(trip.items.count) item\(trip.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TripDetailView

/// Shows all items within a single trip, with calendar sync controls per item.
struct TripDetailView: View {

    let trip: Trip
    @ObservedObject var viewModel: ItineraryViewModel
    @State private var isShowingAddItem: Bool = false

    var body: some View {
        List {
            if trip.sortedItems.isEmpty {
                emptyItemsView
            } else {
                ForEach(trip.sortedItems) { item in
                    ItineraryItemRowView(item: item, tripID: trip.id, viewModel: viewModel)
                }
                .onDelete { offsets in
                    // Map sorted offsets back to original items by ID
                    let sortedItems = trip.sortedItems
                    offsets.forEach { index in
                        viewModel.deleteItem(withID: sortedItems[index].id, from: trip.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddItem = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $isShowingAddItem) {
            AddItineraryItemView(tripID: trip.id, viewModel: viewModel)
        }
    }

    private var emptyItemsView: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))
            Text("No items yet — tap + to add your first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Spacing.large)
        .listRowBackground(Color.clear)
    }
}

// MARK: - ItineraryItemRowView

private struct ItineraryItemRowView: View {
    let item: ItineraryItem
    let tripID: UUID
    @ObservedObject var viewModel: ItineraryViewModel

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: JetsetterTheme.Spacing.medium) {
            // Type icon badge
            Image(systemName: item.type.systemImage)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(hex: item.type.color))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(dateFormatter.string(from: item.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let location = item.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Calendar sync button
            Button {
                Task {
                    if item.isSyncedToCalendar {
                        await viewModel.removeItemFromCalendar(item, in: tripID)
                    } else {
                        await viewModel.syncItemToCalendar(item, in: tripID)
                    }
                }
            } label: {
                Image(systemName: item.isSyncedToCalendar ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .foregroundStyle(item.isSyncedToCalendar ? JetsetterTheme.Colors.success : JetsetterTheme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AddTripView

/// Sheet form for creating a new trip.
private struct AddTripView: View {

    @ObservedObject var viewModel: ItineraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var destination: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Info") {
                    TextField("Trip name (e.g. Tokyo Spring Trip)", text: $name)
                    TextField("Destination (e.g. Tokyo, Japan)", text: $destination)
                }
                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveTrip() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveTrip() {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate
        )
        viewModel.addTrip(trip)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Empty") {
    ItineraryView()
}

#Preview("With Sample Trip") {
    let viewModel = ItineraryViewModel()
    viewModel.addTrip(.sample)
    return NavigationStack {
        TripDetailView(trip: .sample, viewModel: viewModel)
    }
}
