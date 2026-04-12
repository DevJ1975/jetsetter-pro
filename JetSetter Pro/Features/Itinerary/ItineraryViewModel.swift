// File: Features/Itinerary/ItineraryViewModel.swift

import Foundation
import Combine
import SwiftUI

// MARK: - ItineraryViewModel

/// Manages all trip and itinerary item state.
/// Persists trips locally via UserDefaults.
/// TODO: Replace UserDefaults persistence with Supabase when backend is integrated.
@MainActor
final class ItineraryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var trips: [Trip] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var calendarStatusMessage: String? = nil

    // MARK: - UserDefaults Key

    private let storageKey = "jetsetter_trips"

    // MARK: - Init

    init() {
        loadTrips()
    }

    // MARK: - Persistence

    /// Loads saved trips from UserDefaults on launch.
    private func loadTrips() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            trips = try JSONDecoder().decode([Trip].self, from: data)
        } catch {
            // If decoding fails, start with an empty list rather than crashing
            trips = []
        }
    }

    /// Saves the current trips array to UserDefaults.
    private func saveTrips() {
        do {
            let data = try JSONEncoder().encode(trips)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            errorMessage = "Failed to save your itinerary."
        }
    }

    // MARK: - Trip CRUD

    func addTrip(_ trip: Trip) {
        trips.append(trip)
        saveTrips()
    }

    func deleteTrip(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        saveTrips()
    }

    // MARK: - Item CRUD

    func addItem(_ item: ItineraryItem, to tripID: UUID) {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[index].items.append(item)
        saveTrips()
    }

    func deleteItem(withID itemID: UUID, from tripID: UUID) {
        guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
              let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        trips[tripIndex].items.remove(at: itemIndex)
        saveTrips()
    }

    // MARK: - Packing List CRUD

    func addPackingItem(_ name: String, to tripID: UUID) {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let item = PackingItem(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        trips[index].packingList.append(item)
        saveTrips()
    }

    func togglePackingItem(withID itemID: UUID, in tripID: UUID) {
        guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
              let itemIndex = trips[tripIndex].packingList.firstIndex(where: { $0.id == itemID }) else { return }
        trips[tripIndex].packingList[itemIndex].isPacked.toggle()
        saveTrips()
    }

    func deletePackingItem(withID itemID: UUID, from tripID: UUID) {
        guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }) else { return }
        trips[tripIndex].packingList.removeAll { $0.id == itemID }
        saveTrips()
    }

    // MARK: - Calendar Sync

    /// Adds an itinerary item to the user's calendar and stores the event identifier.
    func syncItemToCalendar(_ item: ItineraryItem, in tripID: UUID) async {
        isLoading = true
        errorMessage = nil
        calendarStatusMessage = nil

        defer { isLoading = false }

        do {
            let eventIdentifier = try await CalendarService.shared.addEvent(for: item)

            // Store the event identifier on the item so we can remove it later
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                  let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == item.id }) else { return }

            trips[tripIndex].items[itemIndex].calendarEventIdentifier = eventIdentifier
            saveTrips()

            calendarStatusMessage = "\"\(item.title)\" added to Calendar."
        } catch let error as CalendarError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Could not sync to Calendar. Please try again."
        }
    }

    /// Removes a previously synced itinerary item from the user's calendar.
    func removeItemFromCalendar(_ item: ItineraryItem, in tripID: UUID) async {
        guard let identifier = item.calendarEventIdentifier else { return }

        isLoading = true
        errorMessage = nil
        calendarStatusMessage = nil

        defer { isLoading = false }

        do {
            try await CalendarService.shared.removeEvent(identifier: identifier)

            // Clear the stored event identifier
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                  let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == item.id }) else { return }

            trips[tripIndex].items[itemIndex].calendarEventIdentifier = nil
            saveTrips()

            calendarStatusMessage = "\"\(item.title)\" removed from Calendar."
        } catch let error as CalendarError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Could not remove from Calendar. Please try again."
        }
    }
}
