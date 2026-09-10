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
    private static let travelSignalsKey = "supabase_local_travel_signals"

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

    // MARK: - Travel signals (the app learning layer)

    func syncTravelSignals(_ signals: [TravelSignal]) {
        var all = load([TravelSignal].self, key: Self.travelSignalsKey) ?? []
        for signal in signals {
            all.removeAll { $0.id == signal.id }
            all.append(signal)
        }
        save(all, key: Self.travelSignalsKey)
    }

    func fetchTravelSignals() -> [TravelSignal] {
        load([TravelSignal].self, key: Self.travelSignalsKey) ?? []
    }

    func clearTravelSignals() {
        UserDefaults.standard.removeObject(forKey: Self.travelSignalsKey)
    }

    // MARK: - Wipe (Clear Local Data)

    func clearAll() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.walletKey)
        d.removeObject(forKey: Self.disruptionKey)
        d.removeObject(forKey: Self.travelSignalsKey)
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(Self.packingPrefix) {
            d.removeObject(forKey: key)
        }
    }

    // MARK: - Storage

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
