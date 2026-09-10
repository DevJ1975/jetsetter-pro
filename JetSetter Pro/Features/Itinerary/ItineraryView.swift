// File: Features/Itinerary/ItineraryView.swift

import SwiftUI

// MARK: - ItineraryView

/// Main itinerary screen showing the list of trips.
/// Tapping a trip shows its items; items can be synced to Calendar.
struct ItineraryView: View {

    @State private var viewModel = ItineraryViewModel()
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
                    .clipShape(.rect(cornerRadius: 12))
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
        .clipShape(.rect(cornerRadius: 12))
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

/// Shows all items within a single trip, with calendar sync, packing list, and share.
struct TripDetailView: View {

    let tripID: UUID
    @Bindable var viewModel: ItineraryViewModel
    @State private var isShowingAddItem: Bool = false
    @State private var newPackingItemName: String = ""
    @State private var selectedItem: ItineraryItem?
    @State private var editingItem: ItineraryItem?

    /// Always reads live data from the view model so packing/itinerary updates reflect immediately.
    private var currentTrip: Trip? {
        viewModel.trips.first { $0.id == tripID }
    }

    init(trip: Trip, viewModel: ItineraryViewModel) {
        self.tripID = trip.id
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if let currentTrip {
                tripContent(currentTrip)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAddItem) {
            if let currentTrip {
                AddItineraryItemView(tripID: currentTrip.id, viewModel: viewModel)
            }
        }
        .sheet(item: $selectedItem) { item in
            BookingDetailSheet(itemID: item.id, tripID: tripID, viewModel: viewModel)
        }
        .sheet(item: $editingItem) { item in
            AddItineraryItemView(tripID: tripID, viewModel: viewModel, existingItem: item)
        }
    }

    @ViewBuilder
    private func tripContent(_ trip: Trip) -> some View {
        List {
            // MARK: Itinerary Items
            Section("Itinerary") {
                if trip.sortedItems.isEmpty {
                    emptyItemsView
                } else {
                    ForEach(trip.sortedItems) { item in
                        ItineraryItemRowView(item: item, tripID: trip.id, viewModel: viewModel) {
                            selectedItem = item
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(JetsetterTheme.Colors.accent)
                        }
                    }
                    .onDelete { offsets in
                        let sortedItems = trip.sortedItems
                        offsets.forEach { index in
                            viewModel.deleteItem(withID: sortedItems[index].id, from: trip.id)
                        }
                    }
                }
            }

            // MARK: Packing List
            Section("Packing List") {
                ForEach(trip.packingList) { item in
                    PackingItemRow(item: item) {
                        viewModel.togglePackingItem(withID: item.id, in: trip.id)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deletePackingItem(withID: item.id, from: trip.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                // Inline add row
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    TextField("Add item…", text: $newPackingItemName)
                        .submitLabel(.done)
                        .onSubmit { submitPackingItem(to: trip.id) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trip.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    ShareLink(item: trip.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                    Button {
                        isShowingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
        }
    }

    private func submitPackingItem(to tripID: UUID) {
        let trimmed = newPackingItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addPackingItem(trimmed, to: tripID)
        newPackingItemName = ""
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

// MARK: - PackingItemRow

private struct PackingItemRow: View {
    let item: PackingItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: JetsetterTheme.Spacing.medium) {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isPacked ? JetsetterTheme.Colors.success : .secondary)
                    .font(.title3)
                Text(item.name)
                    .strikethrough(item.isPacked)
                    .foregroundStyle(item.isPacked ? .secondary : .primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ItineraryItemRowView

private struct ItineraryItemRowView: View {
    let item: ItineraryItem
    let tripID: UUID
    @Bindable var viewModel: ItineraryViewModel
    /// Called when the row body (not the calendar button) is tapped.
    let onTap: () -> Void

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
                .clipShape(.rect(cornerRadius: 10))

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

                // Booking detail: one key fact (seat / room / vehicle) + confirmation.
                if let keyFact = item.bookingKeyFact {
                    Text(keyFact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let confirmation = item.confirmationNumber {
                    Text("Conf: \(confirmation)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let cost = item.cost {
                    Text(MoneyFormatting.formatAmount(cost.amount, code: cost.currencyCode))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(JetsetterTheme.Colors.accent.opacity(0.12), in: Capsule())
                        .padding(.top, 2)
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
            // `.borderless` so the button owns only its own tap region and the
            // surrounding row tap (below) still opens the detail sheet.
            .buttonStyle(.borderless)
            // Prevent a second tap while a sync/remove is in flight, which could
            // otherwise create a duplicate calendar event.
            .disabled(viewModel.isLoading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - AddTripView

/// Sheet form for creating a new trip.
private struct AddTripView: View {

    @Bindable var viewModel: ItineraryViewModel
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

// MARK: - BookingDetailSheet

/// Read-only detail for a booking-type itinerary item, with an Edit affordance
/// and a scannable code rendered from the confirmation number. Reads the item
/// live from the view model so it reflects edits immediately.
private struct BookingDetailSheet: View {
    let itemID: UUID
    let tripID: UUID
    @Bindable var viewModel: ItineraryViewModel

    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var item: ItineraryItem? {
        viewModel.trips.first { $0.id == tripID }?.items.first { $0.id == itemID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    detail(item)
                } else {
                    // Item was deleted out from under the sheet.
                    ContentUnavailableView("Booking removed", systemImage: "trash")
                }
            }
            .navigationTitle(item?.title ?? "Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
                if item != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") { isEditing = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                if let item {
                    AddItineraryItemView(tripID: tripID, viewModel: viewModel, existingItem: item)
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ item: ItineraryItem) -> some View {
        List {
            Section {
                detailRow("Type", item.type.displayName)
                detailRow("Starts", dateFormatter.string(from: item.startDate))
                if let end = item.endDate {
                    detailRow("Ends", dateFormatter.string(from: end))
                }
                detailRow("Where", item.location)
                detailRow(item.type == .hotel ? "Hotel" : "Provider", item.bookingProvider)
            }

            if let flight = item.flightDetails, item.type == .flight {
                Section("Flight") {
                    detailRow("Airline", flight.airline)
                    detailRow("Flight", flight.flightNumber)
                    detailRow("From", flight.originCode)
                    detailRow("To", flight.destinationCode)
                    detailRow("Seat", flight.seat)
                    detailRow("Cabin", flight.cabinClass)
                    detailRow("Terminal", flight.terminal)
                    detailRow("Gate", flight.gate)
                }
            }

            if let hotel = item.hotelDetails, item.type == .hotel {
                Section("Reservation") {
                    detailRow("Address", hotel.address)
                    detailRow("Room", hotel.roomType)
                    detailRow("Phone", hotel.phone)
                }
            }

            if let car = item.carDetails, item.type == .transport {
                Section("Rental") {
                    detailRow("Class", car.vehicleClass)
                    detailRow("Vehicle", car.vehicleDescription)
                    detailRow("Pickup", car.pickupLocation)
                    detailRow("Drop-off", car.dropoffLocation)
                }
            }

            if let cost = item.cost {
                Section("Cost") {
                    detailRow("Amount", MoneyFormatting.formatAmount(cost.amount, code: cost.currencyCode))
                }
            }

            if let confirmation = item.confirmationNumber {
                Section("Confirmation") {
                    detailRow("Code", confirmation)
                    if let qr = QRCodeGenerator.image(from: confirmation, size: 180) {
                        HStack {
                            Spacer()
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                            Spacer()
                        }
                    }
                }
            }

            if let notes = item.notes {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Renders a labeled value row, or nothing when the value is nil/blank.
    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
        }
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
