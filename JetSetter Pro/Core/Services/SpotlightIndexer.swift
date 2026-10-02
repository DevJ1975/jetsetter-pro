// File: Core/Services/SpotlightIndexer.swift
//
// Keeps Spotlight's copy of the traveler's plans in step with the itinerary:
// upcoming trips (`TripEntity`) and the bookings inside them
// (`BookingEntity`). Searching "Atlanta" or "Marriott" on the Home Screen then
// finds the trip, and Siri can resolve "my Atlanta trip" from the same index.
//
// When it runs: once at launch and after every `.jetSetterTripsChanged`
// (posted by TravelStore on every trip write). Each pass clears both entity
// types and re-adds what is current. That is the simplest way to guarantee a
// deleted trip, or one that has ended, disappears from search; the set is a
// handful of trips, so a full rebuild is cheap.
//
// The index is created with complete file protection, so its contents can't
// be read while the phone is locked. Travel plans are exactly what shouldn't
// show up in a Lock Screen search on someone else's hands.

import AppIntents
import CoreSpotlight
import Foundation

@MainActor
final class SpotlightIndexer {

    static let shared = SpotlightIndexer()
    private init() {}

    /// A named index, as Apple recommends for app entities (the default index
    /// is meant for prototyping).
    static let indexName = "JetSetterPro.Trips"

    private var observer: NSObjectProtocol?
    private var pendingReindex: Task<Void, Never>?
    private var isIndexing = false
    private var needsAnotherPass = false

    /// Starts listening for trip changes and indexes once now. Idempotent, so
    /// it's safe to call on every launch.
    func startObservingTripChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .jetSetterTripsChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SpotlightIndexer.shared.scheduleReindex() }
        }
        scheduleReindex()
    }

    /// Coalesces a burst of trip writes (a save posts once per mutation) into
    /// one rebuild a moment later.
    func scheduleReindex() {
        pendingReindex?.cancel()
        pendingReindex = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await SpotlightIndexer.shared.reindexNow()
        }
    }

    /// Rebuilds the index from the current trips. A request that arrives while
    /// a rebuild is running triggers one more pass rather than overlapping,
    /// because two interleaved delete-then-add passes could leave stale or
    /// missing entries.
    func reindexNow() async {
        guard !isIndexing else {
            needsAnotherPass = true
            return
        }
        isIndexing = true
        defer { isIndexing = false }
        repeat {
            needsAnotherPass = false
            await rebuild(from: TravelStore.loadTrips(), now: Date())
        } while needsAnotherPass
    }

    /// Removes everything this app put in Spotlight. For "Clear Local Data".
    func removeAll() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let index = Self.makeIndex()
        try? await index.deleteAppEntities(ofType: TripEntity.self)
        try? await index.deleteAppEntities(ofType: BookingEntity.self)
    }

    private func rebuild(from allTrips: [Trip], now: Date) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let trips = SpotlightSelection.trips(from: allTrips, now: now).map(TripEntity.init)
        let bookings = SpotlightSelection.bookings(from: allTrips, now: now)
            .map { BookingEntity(item: $0.item, trip: $0.trip) }
        let index = Self.makeIndex()
        do {
            try await index.deleteAppEntities(ofType: TripEntity.self)
            try await index.deleteAppEntities(ofType: BookingEntity.self)
            if !trips.isEmpty { try await index.indexAppEntities(trips) }
            if !bookings.isEmpty { try await index.indexAppEntities(bookings) }
        } catch {
            // Spotlight is a convenience. A failed pass (index busy, phone
            // locked mid-write) leaves search a little stale until the next
            // trip change or launch; it must never surface as an app error.
        }
    }

    private static func makeIndex() -> CSSearchableIndex {
        CSSearchableIndex(name: indexName, protectionClass: .complete)
    }
}
