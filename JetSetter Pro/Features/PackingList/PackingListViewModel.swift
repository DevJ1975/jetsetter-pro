// File: Features/PackingList/PackingListViewModel.swift
// ViewModel for the Smart Packing List feature (Feature 2).
// Coordinates PackingListService (weather + Claude AI) and SupabaseService (persistence).

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

        // 1. Try Supabase first
        do {
            if let remote = try await SupabaseService.shared.fetchPackingList(tripId: trip.id) {
                packingList = remote
                saveLocally(remote)
                return
            }
        } catch {
            // Not signed in or network error — fall through to local cache
        }

        // 2. Fall back to local UserDefaults cache
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

        // Demo mode: skip all network calls and use the curated Tokyo list.
        if MockDataService.isEnabled {
            let list = PackingListResult(
                id: UUID(),
                tripId: trip.id,
                items: Self.merged(newItems: Self.demoTokyoPackingItems(), preserving: previous),
                generatedAt: Date()
            )
            packingList = list
            persist(list)
            return
        }

        do {
            let items = try await PackingListService.shared.generatePackingItems(for: trip)
            let list = PackingListResult(
                id: UUID(),
                tripId: trip.id,
                items: Self.merged(newItems: items, preserving: previous),
                generatedAt: Date()
            )
            packingList = list
            persist(list)
        } catch {
            // Demo mode already returned above, so this path is only reached in
            // live builds — surface the error instead of showing demo data.
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

    // MARK: - Demo Fallback List

    /// Hardcoded ~30-item Tokyo business-trip packing list used when the
    /// Claude API key is missing or the request fails. Drives a polished
    /// generate-list flow on the simulator during the investor demo.
    private static func demoTokyoPackingItems() -> [SmartPackingItem] {
        [
            // Documents
            SmartPackingItem(name: "Passport", category: .documents),
            SmartPackingItem(name: "Japan eVisa printout", category: .documents),
            SmartPackingItem(name: "Travel insurance card", category: .documents),
            SmartPackingItem(name: "Hotel confirmations", category: .documents),
            SmartPackingItem(name: "AA169 boarding pass backup", category: .documents),

            // Clothing
            SmartPackingItem(name: "Dress shirts", category: .clothing, quantity: 4),
            SmartPackingItem(name: "Suit (jacket + trousers)", category: .clothing),
            SmartPackingItem(name: "Dress shoes", category: .clothing),
            SmartPackingItem(name: "Sneakers", category: .clothing),
            SmartPackingItem(name: "Casual pants", category: .clothing, quantity: 2),
            SmartPackingItem(name: "Sleepwear", category: .clothing),
            SmartPackingItem(name: "Socks", category: .clothing, quantity: 5),
            SmartPackingItem(name: "Underwear", category: .clothing, quantity: 5),
            SmartPackingItem(name: "Light jacket", category: .clothing),
            SmartPackingItem(name: "Folding umbrella", category: .clothing),

            // Toiletries
            SmartPackingItem(name: "Toothbrush + toothpaste", category: .toiletries),
            SmartPackingItem(name: "Deodorant", category: .toiletries),
            SmartPackingItem(name: "Razor", category: .toiletries),
            SmartPackingItem(name: "Shampoo (3 oz)", category: .toiletries),
            SmartPackingItem(name: "Facial moisturizer", category: .toiletries),
            SmartPackingItem(name: "Prescription meds", category: .health),

            // Electronics
            SmartPackingItem(name: "iPhone + cable", category: .electronics),
            SmartPackingItem(name: "iPad", category: .electronics),
            SmartPackingItem(name: "MacBook + charger", category: .electronics),
            SmartPackingItem(name: "Type A/B universal adapter", category: .electronics),
            SmartPackingItem(name: "AirPods", category: .electronics),
            SmartPackingItem(name: "Portable battery", category: .electronics),

            // Misc
            SmartPackingItem(name: "Reusable water bottle", category: .misc),
            SmartPackingItem(name: "Eye mask", category: .misc),
            SmartPackingItem(name: "Packing cubes", category: .misc),
            SmartPackingItem(name: "Suica / Pasmo card", category: .misc)
        ]
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

    /// Debounces Supabase writes — waits 0.5 s after the last change before syncing.
    private func persist(_ list: PackingListResult) {
        saveLocally(list)
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await SupabaseService.shared.upsertPackingList(list)
            } catch {
                // Silently fail — local cache already updated
            }
        }
    }

    // MARK: - Local Cache

    private var cacheKey: String { Self.localKey + trip.id.uuidString }

    private func saveLocally(_ list: PackingListResult) {
        // No key strategy: SmartPackingItem already declares explicit snake_case
        // CodingKeys (is_packed, …). Adding .convertToSnakeCase/.convertFromSnakeCase
        // double-converted the keys, so the round-trip decode always failed and
        // the local cache silently never loaded.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadLocally() -> PackingListResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PackingListResult.self, from: data)
    }
}
