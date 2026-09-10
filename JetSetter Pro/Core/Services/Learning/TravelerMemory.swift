// File: Core/Services/Learning/TravelerMemory.swift
//
// Preferences the traveler has explicitly asked the app to remember ("I'm
// vegetarian", "aisle seat"), via Siri ("Remember that I prefer…") or the
// preferences screen. Stored in UserDefaults so it survives launches and works
// fully offline; shown and editable in TravelerMemoryView for transparency.

import Foundation

// MARK: - Preference

struct TravelerPreference: Identifiable, Codable, Equatable {
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
@Observable
final class TravelerMemory {

    static let shared = TravelerMemory()

    private(set) var preferences: [TravelerPreference] = []

    /// Confidence half-life: a preference not reinforced for this many days counts
    /// for half as much in recall, so stale opinions fade instead of lingering.
    private static let decayHalfLifeDays: Double = 180
    /// Hard cap on stored preferences; the weakest are evicted past this.
    private static let maxPreferences = 200
    /// Preferences whose *effective* (decayed) confidence is below this are omitted
    /// from prompt summaries so faded opinions aren't asserted.
    private static let promptConfidenceFloor = 0.35
    /// Categories where a newly stated value typically supersedes an older one
    /// (you don't have two diets); used to decay contradicted values.
    private static let singleValued: Set<TravelerPreference.Category> = [.dietary, .seating, .hotelStyle]

    // Same key as earlier builds so existing preferences carry over.
    private let storageKey = "iris_memory"

    private init() { load() }

    // MARK: - API

    /// A normalized comparison key so trivially different phrasings of the same
    /// intent ("aisle seat", "Aisle  Seats", "aisle-seat.") collapse to one
    /// preference instead of accumulating near-duplicates.
    private static func matchKey(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let collapsed = lowered
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .punctuationCharacters)
        if trimmed.count > 3, trimmed.hasSuffix("s") {
            return String(trimmed.dropLast())
        }
        return trimmed
    }

    /// Records a new preference, or reinforces an existing one with the same
    /// category+value. Reinforcement bumps confidence and updates timestamp.
    @discardableResult
    func remember(category: TravelerPreference.Category, value: String) -> TravelerPreference {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.matchKey(normalized)

        if Self.singleValued.contains(category) {
            for i in preferences.indices where preferences[i].category == category
                && Self.matchKey(preferences[i].value) != key {
                preferences[i].confidence = max(0, preferences[i].confidence - 0.3)
            }
        }

        if let index = preferences.firstIndex(where: {
            $0.category == category && Self.matchKey($0.value) == key
        }) {
            preferences[index].lastReinforcedAt = Date()
            preferences[index].confidence = min(1.0, preferences[index].confidence + 0.1)
            save()
            return preferences[index]
        }
        let new = TravelerPreference(category: category, value: normalized)
        preferences.append(new)
        enforceCap()
        save()
        return new
    }

    /// Confidence decayed by how long since the preference was last reinforced.
    func effectiveConfidence(_ p: TravelerPreference, now: Date = Date()) -> Double {
        let ageDays = max(0, now.timeIntervalSince(p.lastReinforcedAt) / 86_400)
        return p.confidence * pow(0.5, ageDays / Self.decayHalfLifeDays)
    }

    /// Returns matching preferences, strongest (effective confidence) first.
    func recall(category: TravelerPreference.Category? = nil) -> [TravelerPreference] {
        let filtered = category.map { c in preferences.filter { $0.category == c } } ?? preferences
        return filtered.sorted { effectiveConfidence($0) > effectiveConfidence($1) }
    }

    /// Preferences still held with meaningful confidence, formatted for an
    /// on-device prompt (packing lists, place ranking). Faded ones are omitted.
    func summaryForPrompt() -> String {
        let now = Date()
        let strong = preferences.filter { effectiveConfidence($0, now: now) >= Self.promptConfidenceFloor }
        guard !strong.isEmpty else { return "" }
        let grouped = Dictionary(grouping: strong) { $0.category }
        let lines = grouped.compactMap { (cat, prefs) -> String? in
            let values = prefs
                .sorted { effectiveConfidence($0, now: now) > effectiveConfidence($1, now: now) }
                .map(\.value)
                .joined(separator: ", ")
            return "- \(cat.displayName): \(values)"
        }.sorted()
        return "Traveler preferences:\n\(lines.joined(separator: "\n"))"
    }

    private func enforceCap() {
        guard preferences.count > Self.maxPreferences else { return }
        preferences.sort { a, b in
            let ca = effectiveConfidence(a), cb = effectiveConfidence(b)
            return ca != cb ? ca > cb : a.lastReinforcedAt > b.lastReinforcedAt
        }
        preferences.removeLast(preferences.count - Self.maxPreferences)
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
              let decoded = try? JSONCoding.iso8601Decoder.decode([TravelerPreference].self, from: data) else { return }
        preferences = decoded
    }

    private func save() {
        guard let data = try? JSONCoding.iso8601Encoder.encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
