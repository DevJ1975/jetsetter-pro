// File: Core/Services/LocalDataService.swift
//
// Device-local persistence for the records that used to be routed through the
// Supabase actor: wallet items, packing lists, disruption events and travel
// signals. JetSetter Pro has no backend — nothing here touches the network.
//
// The UserDefaults keys are the ones the previous implementation already wrote
// to, so existing installs keep their data.

import Foundation

actor LocalDataService {

    static let shared = LocalDataService()
    private init() {}

    private static let walletKey        = "supabase_local_wallet_items"
    private static let packingPrefix    = "supabase_local_packing_"
    private static let disruptionKey    = "supabase_local_disruption_events"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Wallet

    func fetchWalletItems() -> [WalletItem] {
        load([WalletItem].self, key: Self.walletKey) ?? []
    }

    func upsertWalletItem(_ item: WalletItem) {
        var items = fetchWalletItems()
        items.removeAll { $0.id == item.id }
        items.append(item)
        save(items, key: Self.walletKey)
    }

    func deleteWalletItem(id: UUID) {
        var items = fetchWalletItems()
        items.removeAll { $0.id == id }
        save(items, key: Self.walletKey)
    }

    // MARK: - Packing lists

    /// Synchronous existence check for callers that can't hop onto the actor
    /// (the suggestion engine evaluates on the main thread).
    nonisolated static func hasPackingList(tripId: UUID) -> Bool {
        UserDefaults.standard.data(forKey: packingPrefix + tripId.uuidString) != nil
    }

    func fetchPackingList(tripId: UUID) -> PackingListResult? {
        load(PackingListResult.self, key: Self.packingPrefix + tripId.uuidString)
    }

    func upsertPackingList(_ list: PackingListResult) {
        save(list, key: Self.packingPrefix + list.tripId.uuidString)
    }

    // MARK: - Disruption events

    func fetchDisruptionEvents() -> [DisruptionEvent] {
        load([DisruptionEvent].self, key: Self.disruptionKey) ?? []
    }

    func upsertDisruptionEvent(_ event: DisruptionEvent) {
        var events = fetchDisruptionEvents()
        events.removeAll { $0.id == event.id }
        events.append(event)
        save(events, key: Self.disruptionKey)
    }

    // MARK: - Wipe (Clear Local Data)

    func clearAll() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.walletKey)
        d.removeObject(forKey: Self.disruptionKey)
        for key in d.dictionaryRepresentation().keys
        where key.hasPrefix(Self.packingPrefix) || key.hasPrefix("supabase_local_") && key.hasSuffix("_undecodable") {
            d.removeObject(forKey: key)
        }
    }

    // MARK: - Storage

    /// Decodes the blob under `key`. A blob that exists but no longer decodes
    /// (a model changed shape) is moved aside to `<key>_undecodable` instead of
    /// being read as "empty" — otherwise the next upsert would overwrite the
    /// user's data with a one-item array. The backup is kept for recovery.
    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            UserDefaults.standard.set(data, forKey: key + "_undecodable")
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
