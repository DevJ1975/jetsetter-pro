// File: Features/Itinerary/AddItineraryItemView.swift

import SwiftUI

// MARK: - AddItineraryItemView

/// Sheet form for creating a new itinerary item inside a trip.
struct AddItineraryItemView: View {

    let tripID: UUID
    @Bindable var viewModel: ItineraryViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var title: String = ""
    @State private var type: ItineraryItemType = .activity
    @State private var startDate: Date
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date
    @State private var location: String = ""
    @State private var notes: String = ""

    init(tripID: UUID, viewModel: ItineraryViewModel) {
        self.tripID = tripID
        self.viewModel = viewModel
        // Default the new item to the start of the trip rather than "now", so
        // items on a future trip don't get today's date and sort above the
        // rest of the itinerary.
        let defaultStart = viewModel.trips.first { $0.id == tripID }?.startDate ?? Date()
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultStart.addingTimeInterval(3600))
    }

    /// The trip this item is being added to, read live from the view model.
    private var trip: Trip? {
        viewModel.trips.first { $0.id == tripID }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the chosen start date falls outside the trip's date range.
    private var startDateOutsideTrip: Bool {
        guard let trip else { return false }
        let cal = Calendar.current
        let day = cal.startOfDay(for: startDate)
        return day < cal.startOfDay(for: trip.startDate) || day > cal.startOfDay(for: trip.endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Type Picker
                Section("Type") {
                    Picker("Item type", selection: $type) {
                        ForEach(ItineraryItemType.allCases) { itemType in
                            Label(itemType.displayName, systemImage: itemType.systemImage)
                                .tag(itemType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // MARK: Details
                Section("Details") {
                    TextField("Title", text: $title)

                    TextField("Location (optional)", text: $location)
                }

                // MARK: Dates
                Section {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])

                    Toggle("Add end time", isOn: $hasEndDate)

                    if hasEndDate {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                } header: {
                    Text("Date & Time")
                } footer: {
                    if startDateOutsideTrip {
                        Label("This date is outside your trip's dates.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                    }
                }

                // MARK: Notes
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveItem() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? JetsetterTheme.Colors.accent : .secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Save

    private func saveItem() {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ItineraryItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            location: trimmedLocation.isEmpty ? nil : trimmedLocation,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        viewModel.addItem(item, to: tripID)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    AddItineraryItemView(tripID: UUID(), viewModel: ItineraryViewModel())
}
