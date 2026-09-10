// File: Core/Services/PackingListGenerator.swift
//
// On-device packing-list generation with Apple Intelligence (FoundationModels).
// Guided generation constrains the model to `GeneratedPackingList`, so the
// result is always a well-formed list of typed items — no JSON-in-a-string,
// no fence stripping, no "hope the model obeyed the schema".
//
// Streams cumulative snapshots so the UI can fill in rows as the model writes
// them (a full list takes several seconds on device). Yields nothing and
// finishes with `PackingListGenerator.Failure.unavailable` when Apple
// Intelligence can't run here; `PackingListService` then falls back to its
// static list.
//
// Follows the same shape as ExpenseCategorizer: @MainActor, iOS-26 internals
// behind @available so the iOS 18 deployment target still compiles.

import Foundation
import FoundationModels

@MainActor
final class PackingListGenerator {

    static let shared = PackingListGenerator()
    private init() {}

    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence isn't available on this device."
            }
        }
    }

    /// Hard cap on generated items. The on-device model shares a ~4K-token
    /// window between the prompt and its output; ~24 typed items keeps the
    /// whole exchange comfortably inside it and the wait under ~20 s.
    nonisolated static let maxItems = 24

    /// True when the on-device model can generate right now.
    var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Streams cumulative `[SmartPackingItem]` snapshots for `prompt`. The final
    /// snapshot is the complete list.
    func stream(prompt: String) -> AsyncThrowingStream<[SmartPackingItem], Error> {
        guard #available(iOS 26.0, *), isAvailable else {
            return AsyncThrowingStream { $0.finish(throwing: Failure.unavailable) }
        }
        return streamOnDevice(prompt: prompt)
    }

    // MARK: - Apple Intelligence

    private static let instructions = """
    You are a travel packing assistant. Produce a practical, specific packing \
    list for one traveler on the trip described. Base clothing quantities on \
    the trip length and forecast, add activity-specific gear, respect the \
    airline's baggage limits, include travel documents when the destination is \
    international, and cover health and safety basics. Item names are short \
    ("Merino socks", not "A pair of socks for each day"). Notes are optional \
    and at most one short clause. Never repeat an item.
    """

    @available(iOS 26.0, *)
    private func streamOnDevice(prompt: String) -> AsyncThrowingStream<[SmartPackingItem], Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let session = LanguageModelSession(instructions: Self.instructions)
                // Rows keep the same id across snapshots so SwiftUI updates text in
                // place instead of rebuilding every row on each token.
                var ids: [String: UUID] = [:]
                do {
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: GeneratedPackingList.self
                    )
                    for try await partial in stream {
                        try Task.checkCancellation()
                        continuation.yield(Self.items(from: partial.content.items ?? [], ids: &ids))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // When the consumer walks away, stop the on-device model too.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps partially generated items to app models, skipping rows the model
    /// hasn't finished naming yet and de-duplicating by name + category.
    @available(iOS 26.0, *)
    private static func items(from partials: [GeneratedPackingItem.PartiallyGenerated], ids: inout [String: UUID]) -> [SmartPackingItem] {
        var seen = Set<String>()
        var result: [SmartPackingItem] = []
        for partial in partials {
            guard let name = partial.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let category = partial.category
            else { continue }
            let key = "\(category.rawValue)|\(name.lowercased())"
            guard seen.insert(key).inserted else { continue }
            let id = ids[key] ?? UUID()
            ids[key] = id
            let notes = partial.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                SmartPackingItem(
                    id: id,
                    name: name,
                    category: category.packingCategory,
                    quantity: max(1, partial.quantity ?? 1),
                    notes: (notes?.isEmpty ?? true) ? nil : notes
                )
            )
        }
        return result
    }
}

// MARK: - Generable schema

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedPackingList {
    @Guide(description: "Packing items tailored to the trip, most essential first")
    @Guide(.maximumCount(PackingListGenerator.maxItems))
    var items: [GeneratedPackingItem]
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedPackingItem {
    @Guide(description: "Short item name, e.g. 'Rain jacket' or 'USB-C charger'")
    var name: String

    var category: GeneratedPackingCategory

    @Guide(description: "How many to pack")
    @Guide(.range(1...12))
    var quantity: Int

    @Guide(description: "Optional one-clause reason, e.g. 'rain expected Tuesday'")
    var notes: String?
}

/// Mirrors `PackingCategory` so guided generation can only emit a valid case.
@available(iOS 26.0, *)
@Generable
nonisolated enum GeneratedPackingCategory: String {
    case clothing
    case toiletries
    case electronics
    case documents
    case health
    case misc

    var packingCategory: PackingCategory {
        switch self {
        case .clothing:    return .clothing
        case .toiletries:  return .toiletries
        case .electronics: return .electronics
        case .documents:   return .documents
        case .health:      return .health
        case .misc:        return .misc
        }
    }
}
