// File: Features/PackingList/PackingListViewModel.swift
// ViewModel for the Smart Packing List feature (Feature 2).
// Coordinates PackingListService (weather + on-device Apple Intelligence) and persistence.

import SwiftUI

@MainActor
@Observable
final class PackingListViewModel {

    private(set) var packingList: PackingListResult? = nil
    private(set) var isGenerating = false
    private(set) var isLoading    = false
    var errorMessage: String?      = nil

    // Add-item sheet state
    var showAddItem     = false
    var newItemName     = ""
    var newItemCategory: PackingCategory = .misc
    var newItemQuantity = 1

    // Regenerate confirmation state
    var showRegenerateConfirm = false

    let trip: Trip

    private var persistTask: Task<Void, Never>? = nil
    private static let localKey = "packing_list_v1_"

    init(trip: Trip) {
        self.trip = trip
    }

    // MARK: - Load

    func load() async {
        guard packingList == nil else { return }
        isLoading = true
        defer { isLoading = false }

        // Prefer the shared local store (the app tools write there too), then the
        // per-trip cache.
        if let stored = await LocalDataService.shared.fetchPackingList(tripId: trip.id) {
            packingList = stored
            saveLocally(stored)
            return
        }
        packingList = loadLocally()
    }

    // MARK: - Generate

    func generateList() async {
        await generateList(preservingCustomizationsFrom: nil)
    }

    /// Generates a fresh list. When `previous` is supplied, the newly generated
    /// AI items inherit the packed state of any prior item with the same
    /// name+category, and all user-added (`isCustom`) items are carried over so a
    /// regenerate never silently destroys progress or personal additions.
    private func generateList(preservingCustomizationsFrom previous: PackingListResult?) async {
        isGenerating = true
        defer { isGenerating = false }

        let listID = UUID()
        var received = false
        do {
            // Snapshots arrive as the on-device model writes; show them as they
            // land so the list fills in instead of spinning for the whole wait.
            for try await snapshot in await PackingListService.shared.packingItemsStream(for: trip) {
                received = true
                packingList = PackingListResult(
                    id: listID,
                    tripId: trip.id,
                    items: Self.merged(newItems: snapshot, preserving: previous),
                    generatedAt: Date()
                )
            }
            guard received, let list = packingList else {
                packingList = previous
                errorMessage = "Couldn't generate your packing list. Pull to retry."
                return
            }
            persist(list)
        } catch {
            // Restore the prior list so a failed regenerate never wipes progress.
            packingList = previous
            errorMessage = "Couldn't generate your packing list. Pull to retry."
        }
    }

    /// Merges freshly generated AI items with a prior list: re-maps `isPacked`
    /// onto matching regenerated items and appends the user's custom items.
    private static func merged(
        newItems: [SmartPackingItem],
        preserving previous: PackingListResult?
    ) -> [SmartPackingItem] {
        guard let previous else { return newItems }

        // Map of "category|lowercased-name" → isPacked from the prior AI items.
        let packedByKey: [String: Bool] = previous.items.reduce(into: [:]) { acc, item in
            guard !item.isCustom else { return }
            acc[matchKey(name: item.name, category: item.category)] = item.isPacked
        }

        var result = newItems.map { item -> SmartPackingItem in
            var updated = item
            if let wasPacked = packedByKey[matchKey(name: item.name, category: item.category)] {
                updated.isPacked = wasPacked
            }
            return updated
        }

        // Preserve every user-added item exactly as-is.
        result.append(contentsOf: previous.items.filter { $0.isCustom })
        return result
    }

    private static func matchKey(name: String, category: PackingCategory) -> String {
        "\(category.rawValue)|\(name.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    // MARK: - Regenerate

    func regenerateList() async {
        // Preserve the user's packed progress and custom items across regeneration
        // instead of discarding them. `merged` re-maps isPacked onto matching
        // regenerated items and carries over every custom addition.
        let previous = packingList
        await generateList(preservingCustomizationsFrom: previous)
    }

    // MARK: - Toggle

    func toggleItem(id: UUID) {
        guard var list = packingList,
              let i = list.items.firstIndex(where: { $0.id == id }) else { return }
        list.items[i].isPacked.toggle()
        packingList = list
        persist(list)
    }

    // MARK: - Add Custom Item

    func commitAddItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        let quantity = max(1, newItemQuantity)
        guard !name.isEmpty, var list = packingList else {
            resetAddItemState()
            return
        }

        // Dedupe by case-insensitive name within the same category: bump the
        // existing item's quantity instead of creating a duplicate row.
        if let i = list.items.firstIndex(where: {
            $0.category == newItemCategory &&
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame
        }) {
            list.items[i].quantity += quantity
        } else {
            let item = SmartPackingItem(
                name: name,
                category: newItemCategory,
                isCustom: true,
                quantity: quantity
            )
            list.items.append(item)
        }

        packingList = list
        persist(list)
        resetAddItemState()
    }

    private func resetAddItemState() {
        newItemName     = ""
        newItemQuantity = 1
        showAddItem     = false
    }

    // MARK: - Delete

    func deleteItem(id: UUID) {
        guard var list = packingList else { return }
        list.items.removeAll { $0.id == id }
        packingList = list
        persist(list)
    }

    // MARK: - Persistence (debounced)

    /// Debounces store writes — waits 0.5 s after the last change before persisting.
    private func persist(_ list: PackingListResult) {
        saveLocally(list)
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await LocalDataService.shared.upsertPackingList(list)
        }
    }

    // MARK: - Local Cache

    private var cacheKey: String { Self.localKey + trip.id.uuidString }

    private func saveLocally(_ list: PackingListResult) {
        // No key strategy: SmartPackingItem already declares explicit snake_case
        // CodingKeys (is_packed, …). Adding .convertToSnakeCase/.convertFromSnakeCase
        // double-converted the keys, so the round-trip decode always failed and
        // the local cache silently never loaded.
        try? CodableDefaults.save(list, forKey: cacheKey)
    }

    private func loadLocally() -> PackingListResult? {
        CodableDefaults.load(PackingListResult.self, forKey: cacheKey)
    }
}
