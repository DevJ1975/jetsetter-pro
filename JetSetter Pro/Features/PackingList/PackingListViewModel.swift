// File: Features/PackingList/PackingListViewModel.swift
// ViewModel for the Smart Packing List feature (Feature 2).
// Coordinates PackingListService (weather + Claude AI) and SupabaseService (persistence).

import SwiftUI
import Combine

@MainActor
final class PackingListViewModel: ObservableObject {

    @Published private(set) var packingList: PackingListResult? = nil
    @Published private(set) var isGenerating = false
    @Published private(set) var isLoading    = false
    @Published var errorMessage: String?      = nil

    // Add-item sheet state
    @Published var showAddItem   = false
    @Published var newItemName   = ""
    @Published var newItemCategory: PackingCategory = .misc

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
        isGenerating = true
        defer { isGenerating = false }

        // Demo mode: skip all network calls and use the curated Tokyo list.
        if MockDataService.isEnabled {
            let list = PackingListResult(
                id: UUID(),
                tripId: trip.id,
                items: Self.demoTokyoPackingItems(),
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
                items: items,
                generatedAt: Date()
            )
            packingList = list
            persist(list)
        } catch {
            // Demo builds fall back to the curated list so the demo always
            // renders; live builds surface the error instead of silently
            // showing demo data.
            if MockDataService.isEnabled {
                let list = PackingListResult(
                    id: UUID(),
                    tripId: trip.id,
                    items: Self.demoTokyoPackingItems(),
                    generatedAt: Date()
                )
                packingList = list
                persist(list)
            } else {
                errorMessage = "Couldn't generate your packing list. Pull to retry."
            }
        }
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
        // Clear current list so generate prompt appears, then re-generate immediately
        packingList = nil
        await generateList()
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
        guard !name.isEmpty, var list = packingList else {
            newItemName = ""
            showAddItem = false
            return
        }
        let item = SmartPackingItem(name: name, category: newItemCategory, isCustom: true)
        list.items.append(item)
        packingList = list
        persist(list)
        newItemName = ""
        showAddItem = false
    }

    // MARK: - Delete

    func deleteItem(id: UUID) {
        guard var list = packingList else { return }
        list.items.removeAll { $0.id == id }
        packingList = list
        persist(list)
    }

    func deleteItems(at offsets: IndexSet, in category: PackingCategory) {
        guard var list = packingList else { return }
        let catItems = list.items.filter { $0.category == category }
        let idsToDelete = offsets.compactMap { catItems[safe: $0]?.id }
        list.items.removeAll { idsToDelete.contains($0.id) }
        packingList = list
        persist(list)
    }

    // MARK: - Persistence (debounced)

    /// Debounces Supabase writes — waits 0.5 s after the last change before syncing.
    private func persist(_ list: PackingListResult) {
        saveLocally(list)
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
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
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy  = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadLocally() -> PackingListResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PackingListResult.self, from: data)
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
