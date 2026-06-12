// File: Core/Services/IRIS/IRISMemory.swift
//
// IRIS's persistent memory of the user's travel preferences. Stored in
// UserDefaults so it survives launches and works fully offline. Users see
// and edit this memory in IRISMemoryView for full transparency.

import Foundation
import Combine

// MARK: - Preference

struct IRISPreference: Identifiable, Codable, Equatable {
    let id: UUID
    var category: Category
    var value: String
    var createdAt: Date
    var lastReinforcedAt: Date
    /// 0.0 to 1.0; rises when the user reinforces, can decay if contradicted.
    var confidence: Double

    enum Category: String, Codable, CaseIterable, Identifiable {
        case dietary, seating, hotelStyle, airlinePreference,
             transportation, destinations, activities, general

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dietary:          return "Dietary"
            case .seating:          return "Seating"
            case .hotelStyle:       return "Hotel Style"
            case .airlinePreference:return "Airline Preference"
            case .transportation:   return "Transportation"
            case .destinations:     return "Destinations"
            case .activities:       return "Activities"
            case .general:          return "General"
            }
        }

        var systemImage: String {
            switch self {
            case .dietary:          return "fork.knife"
            case .seating:          return "chair.fill"
            case .hotelStyle:       return "bed.double.fill"
            case .airlinePreference:return "airplane.circle.fill"
            case .transportation:   return "car.fill"
            case .destinations:     return "globe.americas.fill"
            case .activities:       return "star.fill"
            case .general:          return "ellipsis.circle.fill"
            }
        }
    }

    init(
        id: UUID = UUID(),
        category: Category,
        value: String,
        createdAt: Date = Date(),
        lastReinforcedAt: Date = Date(),
        confidence: Double = 0.7
    ) {
        self.id = id
        self.category = category
        self.value = value
        self.createdAt = createdAt
        self.lastReinforcedAt = lastReinforcedAt
        self.confidence = confidence
    }
}

// MARK: - Memory

@MainActor
final class IRISMemory: ObservableObject {

    static let shared = IRISMemory()

    @Published private(set) var preferences: [IRISPreference] = []

    private let storageKey = "iris_memory"
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private init() { load() }

    // MARK: - API for IRIS (via tools)

    /// Records a new preference, or reinforces an existing one with the same
    /// category+value. Reinforcement bumps confidence and updates timestamp.
    @discardableResult
    func remember(category: IRISPreference.Category, value: String) -> IRISPreference {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = preferences.firstIndex(where: {
            $0.category == category && $0.value.lowercased() == normalized.lowercased()
        }) {
            preferences[index].lastReinforcedAt = Date()
            preferences[index].confidence = min(1.0, preferences[index].confidence + 0.1)
            save()
            return preferences[index]
        }
        let new = IRISPreference(category: category, value: normalized)
        preferences.append(new)
        save()
        return new
    }

    /// Returns matching preferences. When `category` is nil, returns everything.
    func recall(category: IRISPreference.Category? = nil) -> [IRISPreference] {
        let filtered = category.map { c in preferences.filter { $0.category == c } } ?? preferences
        return filtered.sorted { $0.confidence > $1.confidence }
    }

    /// Returns a single line summary of all preferences, formatted for inclusion
    /// in IRIS's system prompt at conversation start.
    func summaryForPrompt() -> String {
        guard !preferences.isEmpty else { return "" }
        let grouped = Dictionary(grouping: preferences) { $0.category }
        let lines = grouped.compactMap { (cat, prefs) -> String? in
            let values = prefs.map(\.value).joined(separator: ", ")
            return "- \(cat.displayName): \(values)"
        }.sorted()
        return "What you remember about this user:\n\(lines.joined(separator: "\n"))"
    }

    // MARK: - User-facing controls

    func delete(_ id: UUID) {
        preferences.removeAll { $0.id == id }
        save()
    }

    func forgetEverything() {
        preferences = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([IRISPreference].self, from: data) else { return }
        preferences = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
