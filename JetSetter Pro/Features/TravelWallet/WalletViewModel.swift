// File: Features/TravelWallet/WalletViewModel.swift

import Foundation

// MARK: - WalletViewModel

@MainActor
@Observable
final class WalletViewModel {

    // MARK: - Published State

    var items: [WalletItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var successMessage: String? = nil

    // MARK: - Private

    private let localKey = "jetsetter_wallet_items"
    /// Prevents redundant Supabase round-trips if the wallet view appears multiple times per session.
    private var hasLoadedFromRemote = false

    // MARK: - Init

    #if DEMO_ENABLED
    /// Demo seeding and teardown rewrite the wallet store underneath any live
    /// view model. Without this the stale in-memory array is flushed back on the
    /// next save, resurrecting removed items or wiping seeded ones.
    private var demoObserver: NSObjectProtocol?
    #endif

    init() {
        loadLocal()
        #if DEMO_ENABLED
        demoObserver = NotificationCenter.default.addObserver(
            forName: .jetSetterDemoDataChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.loadLocal() }
        }
        #endif  // populate immediately from disk; Supabase sync happens lazily in load()
    }

    // MARK: - Load

    /// Reconciles with the local data store once per session (the cache from
    /// init() is shown immediately). Items written by other parts of the app —
    /// e.g. a pass imported from a scan — appear here after this runs.
    func load() async {
        guard !hasLoadedFromRemote else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let stored = await LocalDataService.shared.fetchWalletItems()
        if !stored.isEmpty {
            items = stored.sorted { $0.date < $1.date }
            saveLocal()
        }
        hasLoadedFromRemote = true
    }

    // MARK: - Add Item

    func addItem(_ item: WalletItem) async {
        // Optimistic insert — UI updates immediately
        items.append(item)
        items.sort { $0.date < $1.date }
        saveLocal()

        // Learning: a saved boarding pass is a flown-flight + seat signal.
        if item.itemType == .boardingPass {
            if let airlineCode = item.iataCode {
                var attributes: [String: String] = ["airline": airlineCode]
                if let cabin = item.rawData["cabin_class"] { attributes["cabinHint"] = cabin }
                TravelProfileStore.shared.record(.flightFlown, value: airlineCode, attributes: attributes, source: "wallet")
            }
            if let seat = item.seatNumber {
                TravelProfileStore.shared.record(.seatChosen, value: seat, source: "wallet")
            }
        }

        await LocalDataService.shared.upsertWalletItem(item)
        successMessage = "\"\(item.title)\" added to wallet."
    }

    // MARK: - Delete Item

    func deleteItem(withID id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        saveLocal()

        await LocalDataService.shared.deleteWalletItem(id: removed.id)
    }

    // MARK: - Update Item

    func updateItem(_ updated: WalletItem) async {
        guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
        items[index] = updated
        saveLocal()

        await LocalDataService.shared.upsertWalletItem(updated)
    }

    // MARK: - Filtered Accessors

    var boardingPasses: [WalletItem] { items.filter { $0.itemType == .boardingPass } }
    var activeItems: [WalletItem]    { items.filter { $0.status == .active } }
    var upcomingItems: [WalletItem]  { items.filter { $0.status == .upcoming } }

    // MARK: - Local Persistence

    private func saveLocal() {
        try? CodableDefaults.save(items, forKey: localKey)
    }

    private func loadLocal() {
        guard let decoded = CodableDefaults.load([WalletItem].self, forKey: localKey) else { return }
        items = decoded.sorted { $0.date < $1.date }
    }
}
