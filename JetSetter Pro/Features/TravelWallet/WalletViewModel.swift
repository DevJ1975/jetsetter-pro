// File: Features/TravelWallet/WalletViewModel.swift

import Foundation
import Combine

// MARK: - WalletViewModel

@MainActor
final class WalletViewModel: ObservableObject {

    // MARK: - Published State

    @Published var items: [WalletItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil

    // MARK: - Private

    private let localKey = "jetsetter_wallet_items"
    /// Prevents redundant Supabase round-trips if the wallet view appears multiple times per session.
    private var hasLoadedFromRemote = false

    // Reuse encoder/decoder to avoid repeated allocations on saves/loads
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Init

    init() {
        loadLocal()  // populate immediately from disk; Supabase sync happens lazily in load()
    }

    // MARK: - Load

    /// Syncs from Supabase if authenticated and not yet fetched this session.
    /// Local cache (from init) is shown immediately while the remote fetch is in-flight.
    func load() async {
        guard !hasLoadedFromRemote else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let signedIn = await SupabaseService.shared.isSignedIn
            guard signedIn else { return }  // already showing local cache; nothing to do
            let remote = try await SupabaseService.shared.fetchWalletItems()
            items = remote.sorted { $0.date < $1.date }
            saveLocal()
            hasLoadedFromRemote = true
        } catch {
            // Remote fetch failed — local cache is already displayed from init(); no data loss
            errorMessage = "Could not sync wallet: \(error.localizedDescription)"
        }
    }

    // MARK: - Add Item

    func addItem(_ item: WalletItem) async {
        // Optimistic insert — UI updates immediately
        items.append(item)
        items.sort { $0.date < $1.date }
        saveLocal()

        do {
            try await SupabaseService.shared.upsertWalletItem(item)
            successMessage = "\"\(item.title)\" added to wallet."
        } catch {
            errorMessage = "Saved locally — will sync when online."
        }
    }

    // MARK: - Delete Item

    func deleteItem(withID id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        saveLocal()

        do {
            try await SupabaseService.shared.deleteWalletItem(id: removed.id)
        } catch {
            // Rollback optimistic delete if remote fails
            items.insert(removed, at: index)
            saveLocal()
            errorMessage = "Could not delete item. Please try again."
        }
    }

    // MARK: - Update Item

    func updateItem(_ updated: WalletItem) async {
        guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
        items[index] = updated
        saveLocal()

        do {
            try await SupabaseService.shared.upsertWalletItem(updated)
        } catch {
            errorMessage = "Saved locally — will sync when online."
        }
    }

    // MARK: - Filtered Accessors

    var boardingPasses: [WalletItem] { items.filter { $0.itemType == .boardingPass } }
    var activeItems: [WalletItem]    { items.filter { $0.status == .active } }
    var upcomingItems: [WalletItem]  { items.filter { $0.status == .upcoming } }

    // MARK: - Local Persistence

    private func saveLocal() {
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let decoded = try? decoder.decode([WalletItem].self, from: data) else { return }
        items = decoded.sorted { $0.date < $1.date }
    }
}
