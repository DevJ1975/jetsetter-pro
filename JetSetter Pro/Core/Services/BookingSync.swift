// File: Core/Services/BookingSync.swift
//
// Keeps the app's own records in step with the bookings the backend holds.
//
// Every list sync (launch, foreground, opening My Bookings) and every single
// booking update (the post-checkout poll, a cancellation, a pull to refresh)
// funnels through here:
//
//  * a CONFIRMED booking is upserted into the itinerary and the wallet
//    (`BookingItineraryMapper` decides where, keyed by `duffel_order_id`, so
//    syncing twice never duplicates and an airline schedule change updates the
//    existing records);
//  * a CANCELLED booking has the flights it added removed again;
//  * the list is cached so My Bookings and its confirmation numbers work
//    offline ("Updated 12 min ago"), per the rule that itinerary and PNRs must
//    never depend on a connection.
//
// Quiet by design. With no backend configured, or on a device that has never
// registered (nothing can be booked under it), a sync makes no network call.
// A failure keeps the previous list and sets `lastError`; it never throws at
// the launch path.

import Foundation

// MARK: - Cache

nonisolated struct BackendBookingsCache: Codable, Sendable, Equatable {
    var savedAt: Date
    var bookings: [BackendBooking]
}

extension Notification.Name {
    /// Posted after BookingSync changes the wallet, so an open Wallet screen
    /// reloads (the wallet view model otherwise reads the store once a session).
    static let jetSetterWalletChanged = Notification.Name("jetSetterWalletChanged")
}

// MARK: - BookingSync

@MainActor
@Observable
final class BookingSync {

    static let shared = BookingSync()
    private init() {}

    /// The wallet view model's cache key (see `WalletViewModel`, `DemoDataSeeder`).
    private static let walletCacheKey = "jetsetter_wallet_items"
    /// Foreground syncs closer together than this are skipped.
    private static let minimumInterval: TimeInterval = 60

    // MARK: State

    /// Newest first, as the server returns them.
    private(set) var bookings: [BackendBooking] = []
    /// When `bookings` was last confirmed by the server (or loaded from cache).
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    /// The last sync failure, cleared by the next success.
    private(set) var lastError: BackendError?

    private var hasLoadedCache = false
    private var lastAttempt: Date?

    // MARK: Cache

    /// Loads the cached list once, so the screen has something to show before
    /// (and without) the network.
    func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard let data = await LocalDataService.shared.fetchBackendBookingsCache(),
              let cache = try? JSONCoding.iso8601Decoder.decode(BackendBookingsCache.self, from: data)
        else { return }
        if bookings.isEmpty {
            bookings = cache.bookings
            lastSynced = cache.savedAt
        }
    }

    private func persistCache() async {
        let cache = BackendBookingsCache(savedAt: lastSynced ?? Date(), bookings: bookings)
        if let data = try? JSONCoding.iso8601Encoder.encode(cache) {
            await LocalDataService.shared.saveBackendBookingsCache(data)
        }
    }

    /// Forgets everything (Delete my data). Itinerary and wallet records stay:
    /// they are the traveler's own copy on this phone.
    func reset() async {
        bookings = []
        lastSynced = nil
        lastError = nil
        hasLoadedCache = true
        await LocalDataService.shared.clearBackendBookingsCache()
    }

    // MARK: Sync

    /// Fetches the list and applies it. Returns true when the server answered.
    /// `force` skips the one-minute throttle (My Bookings opening, pull to
    /// refresh); the launch and foreground paths leave it off.
    @discardableResult
    func sync(force: Bool = false) async -> Bool {
        let client = BackendClient.shared
        guard client.isConfigured, !isSyncing else { return false }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.minimumInterval { return false }

        await loadCacheIfNeeded()
        // A device that never registered has nothing on the server; listing
        // would register it just to learn that. (The Keychain survives a
        // reinstall, so a returning traveler does have an identity.)
        guard await client.isRegistered else { return true }

        isSyncing = true
        lastAttempt = Date()
        defer { isSyncing = false }

        do {
            let list = try await client.bookings()
            bookings = list
            lastSynced = Date()
            lastError = nil
            await persistCache()
            await applyToLocalStores(list)
            return true
        } catch let error as BackendError {
            lastError = error
            return false
        } catch {
            // Cancelled: the screen went away. Nothing to report.
            return false
        }
    }

    /// Re-reads one booking from the airline (`refresh=true`), then applies it.
    /// Throws so a pull-to-refresh can say what went wrong.
    @discardableResult
    func refreshBooking(id: String) async throws -> BackendBooking {
        let booking = try await BackendClient.shared.booking(id: id, refresh: true)
        await record(booking)
        return booking
    }

    /// Stores one booking the server just returned (checkout poll, cancel
    /// confirm, detail refresh): updates the list and applies it locally.
    func record(_ booking: BackendBooking) async {
        await loadCacheIfNeeded()
        if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
            bookings[index] = booking
        } else {
            bookings.insert(booking, at: 0)
        }
        lastSynced = Date()
        await persistCache()
        await applyToLocalStores([booking])
    }

    // MARK: Applying

    /// Upserts confirmed bookings and removes cancelled ones, touching the
    /// stores (and posting change notifications) only when something differs.
    private func applyToLocalStores(_ list: [BackendBooking]) async {
        let confirmed = list.filter { $0.status == .confirmed }
        let cancelled = list.filter { $0.status == .cancelled }
        guard !confirmed.isEmpty || !cancelled.isEmpty else { return }

        // Dry run on a copy: is anything different? Skips the write, and the
        // "trips changed" notification that reschedules alerts, on a repeat sync.
        var preview = TravelStore.loadTrips()
        var needsWrite = false
        for booking in confirmed {
            if let placement = BookingItineraryMapper.apply(booking, to: &preview), placement.changed {
                needsWrite = true
            }
        }
        for booking in cancelled {
            if BookingItineraryMapper.remove(booking, from: &preview) { needsWrite = true }
        }

        var tripIDs: [String: UUID] = [:]
        if needsWrite {
            // Re-apply against the freshest trips under the store's lock, so an
            // edit made during the dry run isn't overwritten.
            TravelStore.mutateTrips { trips in
                for booking in confirmed {
                    if let placement = BookingItineraryMapper.apply(booking, to: &trips) {
                        tripIDs[booking.id] = placement.tripID
                    }
                }
                for booking in cancelled { BookingItineraryMapper.remove(booking, from: &trips) }
            }
        } else {
            let current = TravelStore.loadTrips()
            for booking in confirmed {
                let ids = Set(BookingItineraryMapper.itineraryItems(for: booking).map(\.id))
                tripIDs[booking.id] = current.first { trip in trip.items.contains { ids.contains($0.id) } }?.id
            }
        }

        await syncWallet(confirmed: confirmed, cancelled: cancelled, tripIDs: tripIDs)
    }

    /// The wallet lives in two stores (the view model's cache and
    /// `LocalDataService`); both are written, like the demo seeder does.
    private func syncWallet(confirmed: [BackendBooking], cancelled: [BackendBooking], tripIDs: [String: UUID]) async {
        var cache = CodableDefaults.load([WalletItem].self, forKey: Self.walletCacheKey) ?? []
        let stored = await LocalDataService.shared.fetchWalletItems()
        var cacheChanged = false

        for booking in confirmed {
            for fresh in BookingItineraryMapper.walletItems(for: booking, tripID: tripIDs[booking.id]) {
                let cached = cache.first { $0.id == fresh.id }
                let inStore = stored.first { $0.id == fresh.id }
                let merged = (cached ?? inStore).map { BookingItineraryMapper.merge(existing: $0, with: fresh) } ?? fresh

                if inStore != merged { await LocalDataService.shared.upsertWalletItem(merged) }
                if cached != merged {
                    if let index = cache.firstIndex(where: { $0.id == merged.id }) {
                        cache[index] = merged
                    } else {
                        cache.append(merged)
                    }
                    cacheChanged = true
                }
            }
        }

        for booking in cancelled {
            for item in BookingItineraryMapper.walletItems(for: booking, tripID: nil) {
                if stored.contains(where: { $0.id == item.id }) {
                    await LocalDataService.shared.deleteWalletItem(id: item.id)
                }
                if cache.contains(where: { $0.id == item.id }) {
                    cache.removeAll { $0.id == item.id }
                    cacheChanged = true
                }
            }
        }

        if cacheChanged {
            try? CodableDefaults.save(cache, forKey: Self.walletCacheKey)
            NotificationCenter.default.post(name: .jetSetterWalletChanged, object: nil)
        }
    }
}
