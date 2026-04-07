// File: Features/Itinerary/AddItineraryItemView.swift

import SwiftUI

// MARK: - AddItineraryItemView

/// Sheet form for creating a new itinerary item inside a trip.
struct AddItineraryItemView: View {

    let tripID: UUID
    @ObservedObject var viewModel: ItineraryViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var title: String = ""
    @State private var type: ItineraryItemType = .activity
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var location: String = ""
    @State private var notes: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Section("Date & Time") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])

                    Toggle("Add end time", isOn: $hasEndDate)

                    if hasEndDate {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
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
        let item = ItineraryItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes
        )
        viewModel.addItem(item, to: tripID)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    AddItineraryItemView(tripID: UUID(), viewModel: ItineraryViewModel())
}
