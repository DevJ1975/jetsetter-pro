// File: Core/Services/Persistence/JetDataStore.swift
//
// SwiftData-backed local persistence for trips (behind `TravelStore`) and bags
// (behind `BagStore`). The `@Model` records here are a PRIVATE storage detail —
// the rest of the app keeps using the plain Codable value types `Trip` / `Bag`.
//
// Read-mirror: every write also mirrors the value array back to the legacy
// `jetsetter_trips` / `jetsetter_bags` UserDefaults JSON blob (iso8601). Many
// call sites still read those keys directly (IRIS, OfflineKit, FlightBoard,
// DepartureOptimizer, App Intents, TravelProfileStore, …); the mirror keeps them
// seeing fresh data without editing those files. SwiftData is the source of
// truth for reads through the facades; the mirror is a compatibility shim until
// those readers are migrated too.
//
// Expenses intentionally remain on UserDefaults for now — migrating them would
// require touching `ExpenseViewModel` (a direct writer) in the ExpenseTracker
// feature, which is out of scope for this change.

import Foundation
import SwiftData

// MARK: - @Model records (private storage detail)

/// SwiftData mirror of `Trip`. Scalars are mirrored as stored properties (so the
/// store stays queryable by date/destination later); the nested `items` and
/// `packingList` collections are kept as JSON `Data` blobs so `ItineraryItem` /
/// `PackingItem` don't need to be redesigned into relationships. `order`
/// preserves the caller's array ordering across the replace-all write.
@Model
final class TripRecord {
    var id: UUID
    var order: Int
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var itemsData: Data
    var packingListData: Data

    init(id: UUID, order: Int, name: String, destination: String,
         startDate: Date, endDate: Date, itemsData: Data, packingListData: Data) {
        self.id = id
        self.order = order
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.itemsData = itemsData
        self.packingListData = packingListData
    }
}

/// SwiftData mirror of `Bag`. Stored as a whole-object JSON blob (plus `id`/`order`)
/// rather than field-by-field: `Bag` has a hand-written backward-compatible
/// `Codable` initializer, and nothing queries individual bag columns, so a blob is
/// the most faithful and least error-prone mirror.
@Model
final class BagRecord {
    var id: UUID
    var order: Int
    var bagData: Data

    init(id: UUID, order: Int, bagData: Data) {
        self.id = id
        self.order = order
        self.bagData = bagData
    }
}

// MARK: - Converters

extension TripRecord {
    convenience init(trip: Trip, order: Int) {
        let items = (try? JSONCoding.iso8601Encoder.encode(trip.items)) ?? Data()
        let packing = (try? JSONCoding.iso8601Encoder.encode(trip.packingList)) ?? Data()
        self.init(id: trip.id, order: order, name: trip.name, destination: trip.destination,
                  startDate: trip.startDate, endDate: trip.endDate,
                  itemsData: items, packingListData: packing)
    }

    func toTrip() -> Trip {
        let items = (try? JSONCoding.iso8601Decoder.decode([ItineraryItem].self, from: itemsData)) ?? []
        let packing = (try? JSONCoding.iso8601Decoder.decode([PackingItem].self, from: packingListData)) ?? []
        return Trip(id: id, name: name, destination: destination,
                    startDate: startDate, endDate: endDate, items: items, packingList: packing)
    }
}

extension BagRecord {
    convenience init?(bag: Bag, order: Int) {
        guard let data = try? JSONCoding.iso8601Encoder.encode(bag) else { return nil }
        self.init(id: bag.id, order: order, bagData: data)
    }

    func toBag() -> Bag? {
        try? JSONCoding.iso8601Decoder.decode(Bag.self, from: bagData)
    }
}

// MARK: - JetDataStore (container + serialized engine)

enum JetDataStore {

    static let tripsKey = "jetsetter_trips"
    static let bagsKey  = "jetsetter_bags"

    /// Single local (no CloudKit) container shared by the app's SwiftUI environment
    /// and the `TravelStore`/`BagStore` facades. Remote sync stays in SupabaseService.
    static let container: ModelContainer = {
        let schema = Schema([TripRecord.self, BagRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
        // Last-resort in-memory store so the app still runs if the on-disk store
        // can't be opened (corruption / failed store migration).
        return try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }()

    // Serializes every load-modify-save so concurrent writers (an IRIS tool off
    // the main actor + a `@MainActor` view model) can't interleave. A fresh
    // `ModelContext` is created per operation and never shared across threads.
    private static let lock = NSLock()
    private static var didMigrate = false

    /// Runs `body` with a fresh background `ModelContext` under the lock, after
    /// ensuring the one-time UserDefaults→SwiftData migration has run.
    @discardableResult
    static func withContext<T>(_ body: (ModelContext) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        migrateIfNeededLocked()
        let context = ModelContext(container)
        return body(context)
    }

    /// Touch the store early at launch so migration completes before first read.
    static func warmUp() { withContext { _ in } }

    // MARK: Trips

    static func fetchTrips(_ context: ModelContext) -> [Trip] {
        let descriptor = FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.order)])
        return ((try? context.fetch(descriptor)) ?? []).map { $0.toTrip() }
    }

    /// Replace-all write: mirrors the previous full-blob semantics exactly and
    /// keeps ordering stable via `order`. Also mirrors to the legacy UserDefaults
    /// key for the direct readers that haven't been migrated yet.
    static func writeTrips(_ trips: [Trip], _ context: ModelContext) {
        if let existing = try? context.fetch(FetchDescriptor<TripRecord>()) {
            for record in existing { context.delete(record) }
        }
        for (index, trip) in trips.enumerated() {
            context.insert(TripRecord(trip: trip, order: index))
        }
        try? context.save()
        mirror(trips, forKey: tripsKey)
    }

    // MARK: Bags

    static func fetchBags(_ context: ModelContext) -> [Bag] {
        let descriptor = FetchDescriptor<BagRecord>(sortBy: [SortDescriptor(\.order)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap { $0.toBag() }
    }

    static func writeBags(_ bags: [Bag], _ context: ModelContext) {
        if let existing = try? context.fetch(FetchDescriptor<BagRecord>()) {
            for record in existing { context.delete(record) }
        }
        for (index, bag) in bags.enumerated() {
            if let record = BagRecord(bag: bag, order: index) { context.insert(record) }
        }
        try? context.save()
        mirror(bags, forKey: bagsKey)
    }

    // MARK: - Legacy mirror + migration

    private static func mirror<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONCoding.iso8601Encoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// One-time import of any pre-existing UserDefaults blobs into SwiftData, run
    /// once per launch and guarded per-collection by an empty check so it never
    /// overwrites live SwiftData data. Old keys are left in place (inert once the
    /// facades stop reading them; still used as the read-mirror above).
    private static func migrateIfNeededLocked() {
        guard !didMigrate else { return }
        didMigrate = true
        let context = ModelContext(container)

        let tripCount = (try? context.fetchCount(FetchDescriptor<TripRecord>())) ?? 0
        if tripCount == 0, let trips = decodeLegacy([Trip].self, key: tripsKey), !trips.isEmpty {
            for (index, trip) in trips.enumerated() {
                context.insert(TripRecord(trip: trip, order: index))
            }
        }

        let bagCount = (try? context.fetchCount(FetchDescriptor<BagRecord>())) ?? 0
        if bagCount == 0, let bags = decodeLegacy([Bag].self, key: bagsKey), !bags.isEmpty {
            for (index, bag) in bags.enumerated() {
                if let record = BagRecord(bag: bag, order: index) { context.insert(record) }
            }
        }

        try? context.save()
    }

    /// Decodes a legacy blob tolerating both the current `.iso8601` strategy and
    /// the default `.deferredToDate` an older build may have used.
    private static func decodeLegacy<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let value = try? JSONCoding.iso8601Decoder.decode(T.self, from: data) { return value }
        let fallback = JSONDecoder()
        fallback.dateDecodingStrategy = .deferredToDate
        return try? fallback.decode(T.self, from: data)
    }
}

// MARK: - BagStore facade

/// Single funnel for bag persistence, mirroring `TravelStore`'s shape. Replaces
/// the hand-rolled UserDefaults read/write in `LuggageViewModel` and the demo
/// seeders so there is exactly one coding path (the source of the old iso8601
/// mismatch that silently wiped the bag list).
nonisolated enum BagStore {
    static func load() -> [Bag] {
        JetDataStore.withContext { JetDataStore.fetchBags($0) }
    }

    static func save(_ bags: [Bag]) {
        JetDataStore.withContext { JetDataStore.writeBags(bags, $0) }
    }
}
