// File: Features/Itinerary/ItineraryViewModel.swift

import Foundation
import SwiftUI

// MARK: - ItineraryViewModel

/// Manages all trip and itinerary item state.
/// Persists trips locally via UserDefaults.
/// TODO: Replace UserDefaults persistence with Firebase when backend is integrated.
@MainActor
@Observable
final class ItineraryViewModel {

    // MARK: - Published State

    var trips: [Trip] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var calendarStatusMessage: String? = nil

    // MARK: - UserDefaults Key

    private let storageKey = "jetsetter_trips"

    // MARK: - Init

    // `nonisolated(unsafe)` so the observer can be removed from the nonisolated
    // `deinit`. Safe: it's written once in `init` and read once in `deinit`, and
    // `NotificationCenter.removeObserver` is itself thread-safe.
    nonisolated(unsafe) private var tripsChangedObserver: NSObjectProtocol?

    init() {
        loadTrips()
        // Reload when another writer (e.g. a booking flow, IRIS, or a demo
        // reseed) mutates the trip collection, so our in-memory copy stays
        // fresh and a later save() doesn't clobber their change.
        tripsChangedObserver = NotificationCenter.default.addObserver(
            forName: .jetSetterTripsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadTrips() }
        }
    }

    deinit {
        if let tripsChangedObserver {
            NotificationCenter.default.removeObserver(tripsChangedObserver)
        }
    }

    // MARK: - Persistence

    /// Loads saved trips from UserDefaults on launch.
    private func loadTrips() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            trips = try JSONCoding.iso8601Decoder.decode([Trip].self, from: data)
        } catch {
            // Current builds encode dates with `.iso8601`, but an older build may
            // have written them with the default `.deferredToDate` strategy.
            // Attempt a fallback decode before giving up so we never silently
            // wipe the user's saved trips on a strategy mismatch.
            let fallbackDecoder = JSONDecoder()
            fallbackDecoder.dateDecodingStrategy = .deferredToDate
            if let recovered = try? fallbackDecoder.decode([Trip].self, from: data) {
                trips = recovered
                // Re-persist in the current format so future loads succeed cleanly.
                saveTrips()
            } else {
                // Keep any existing in-memory trips rather than blanking them, and
                // surface the failure instead of silently emptying the list.
                errorMessage = "We couldn't load your saved itinerary."
            }
        }
    }

    /// Saves the current trips array to UserDefaults.
    private func saveTrips() {
        do {
            let data = try JSONCoding.iso8601Encoder.encode(trips)
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
        // Collect calendar event identifiers for every synced item in the
        // trips being removed, so we can clean them out of the user's real
        // calendar instead of orphaning them.
        let orphanedIdentifiers = offsets.flatMap { index -> [String] in
            guard trips.indices.contains(index) else { return [] }
            return trips[index].items.compactMap { $0.calendarEventIdentifier }
        }
        trips.remove(atOffsets: offsets)
        saveTrips()
        removeOrphanedCalendarEvents(orphanedIdentifiers)
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
        // Capture any synced calendar event before removing the item so it
        // can be cleaned out of the user's real calendar rather than orphaned.
        let orphanedIdentifier = trips[tripIndex].items[itemIndex].calendarEventIdentifier
        trips[tripIndex].items.remove(at: itemIndex)
        saveTrips()
        if let orphanedIdentifier {
            removeOrphanedCalendarEvents([orphanedIdentifier])
        }
    }

    // MARK: - Packing List CRUD

    func addPackingItem(_ name: String, to tripID: UUID) {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Skip duplicates (case-insensitive) so repeated submits don't create a
        // second "Passport" entry.
        let alreadyExists = trips[index].packingList.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !alreadyExists else { return }
        trips[index].packingList.append(PackingItem(name: trimmed))
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

    /// Best-effort removal of calendar events for items/trips that have been
    /// deleted locally. Fired from the non-async delete paths so a swipe-delete
    /// doesn't leave orphaned EventKit events in the user's real calendar.
    /// Failures are silent by design: the local model is already gone and the
    /// user hasn't asked for a calendar status update here.
    private func removeOrphanedCalendarEvents(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        Task { @MainActor in
            for identifier in identifiers {
                try? await CalendarService.shared.removeEvent(identifier: identifier)
            }
        }
    }

    /// Adds an itinerary item to the user's calendar and stores the event identifier.
    func syncItemToCalendar(_ item: ItineraryItem, in tripID: UUID) async {
        // Guard against double-syncing the same item (e.g. a rapid second tap
        // before the button reflects the new state), which would create a
        // duplicate calendar event.
        guard item.calendarEventIdentifier == nil else { return }

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
