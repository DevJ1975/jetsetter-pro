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

    // All trip reads and writes funnel through `TravelStore`, the single atomic
    // owner of the `jetsetter_trips` blob. Mutations use `TravelStore.mutateTrips`,
    // which loads the freshest saved array, applies the change, and persists it
    // under a lock — so a concurrent write (booking flow, IRIS) can never be lost
    // to a stale in-memory overwrite. Each mutator assigns the returned
    // authoritative array back to `trips`.

    /// Loads saved trips via TravelStore (which tolerates a legacy date-encoding
    /// blob and re-persists it in the current format).
    private func loadTrips() {
        trips = TravelStore.loadTrips()
    }

    // MARK: - Trip CRUD

    func addTrip(_ trip: Trip) {
        trips = TravelStore.mutateTrips { $0.append(trip) }
    }

    func deleteTrip(at offsets: IndexSet) {
        // Collect calendar event identifiers for every synced item in the
        // trips being removed, so we can clean them out of the user's real
        // calendar instead of orphaning them.
        let orphanedIdentifiers = offsets.flatMap { index -> [String] in
            guard trips.indices.contains(index) else { return [] }
            return trips[index].items.compactMap { $0.calendarEventIdentifier }
        }
        // Match by id against the authoritative array rather than by offset, so
        // we delete the right trips even if the saved order drifted from ours.
        let idsToRemove = Set(offsets.compactMap { trips.indices.contains($0) ? trips[$0].id : nil })
        trips = TravelStore.mutateTrips { $0.removeAll { idsToRemove.contains($0.id) } }
        removeOrphanedCalendarEvents(orphanedIdentifiers)
    }

    // MARK: - Item CRUD

    func addItem(_ item: ItineraryItem, to tripID: UUID) {
        trips = TravelStore.mutateTrips { trips in
            guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
            trips[index].items.append(item)
        }
    }

    /// Replaces an existing item (matched by `id`) in place, preserving its
    /// position. Backs the edit flow; the passed `item` keeps its original `id`
    /// and any `calendarEventIdentifier`, so editing never creates a duplicate.
    func updateItem(_ item: ItineraryItem, in tripID: UUID) {
        trips = TravelStore.mutateTrips { trips in
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                  let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
            trips[tripIndex].items[itemIndex] = item
        }
    }

    func deleteItem(withID itemID: UUID, from tripID: UUID) {
        // Capture any synced calendar event before removing the item so it
        // can be cleaned out of the user's real calendar rather than orphaned.
        let orphanedIdentifier = trips.first(where: { $0.id == tripID })?
            .items.first(where: { $0.id == itemID })?.calendarEventIdentifier
        trips = TravelStore.mutateTrips { trips in
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }) else { return }
            trips[tripIndex].items.removeAll { $0.id == itemID }
        }
        if let orphanedIdentifier {
            removeOrphanedCalendarEvents([orphanedIdentifier])
        }
    }

    // MARK: - Packing List CRUD

    func addPackingItem(_ name: String, to tripID: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        trips = TravelStore.mutateTrips { trips in
            guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
            // Skip duplicates (case-insensitive) so repeated submits don't create
            // a second "Passport" entry.
            let alreadyExists = trips[index].packingList.contains {
                $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            guard !alreadyExists else { return }
            trips[index].packingList.append(PackingItem(name: trimmed))
        }
    }

    func togglePackingItem(withID itemID: UUID, in tripID: UUID) {
        trips = TravelStore.mutateTrips { trips in
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                  let itemIndex = trips[tripIndex].packingList.firstIndex(where: { $0.id == itemID }) else { return }
            trips[tripIndex].packingList[itemIndex].isPacked.toggle()
        }
    }

    func deletePackingItem(withID itemID: UUID, from tripID: UUID) {
        trips = TravelStore.mutateTrips { trips in
            guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }) else { return }
            trips[tripIndex].packingList.removeAll { $0.id == itemID }
        }
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

            // Store the event identifier on the item so we can remove it later.
            trips = TravelStore.mutateTrips { trips in
                guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                      let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
                trips[tripIndex].items[itemIndex].calendarEventIdentifier = eventIdentifier
            }

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

            // Clear the stored event identifier.
            trips = TravelStore.mutateTrips { trips in
                guard let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
                      let itemIndex = trips[tripIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
                trips[tripIndex].items[itemIndex].calendarEventIdentifier = nil
            }

            calendarStatusMessage = "\"\(item.title)\" removed from Calendar."
        } catch let error as CalendarError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Could not remove from Calendar. Please try again."
        }
    }
}
