// File: Core/Services/IRIS/IRISMemory.swift
//
// IRIS's persistent memory of the user's travel preferences. Stored in
// UserDefaults so it survives launches and works fully offline. Users see
// and edit this memory in IRISMemoryView for full transparency.

import Foundation

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
@Observable
final class IRISMemory {

    static let shared = IRISMemory()

    private(set) var preferences: [IRISPreference] = []

    /// Confidence half-life: a preference not reinforced for this many days counts
    /// for half as much in recall/prompt, so stale opinions fade instead of lingering.
    private static let decayHalfLifeDays: Double = 180
    /// Hard cap on stored preferences; the weakest are evicted past this.
    private static let maxPreferences = 200
    /// Preferences whose *effective* (decayed) confidence is below this are omitted
    /// from the prompt so IRIS doesn't assert faded or barely-held opinions.
    private static let promptConfidenceFloor = 0.35
    /// Categories where a newly stated value typically supersedes an older one
    /// (you don't have two diets); used to decay contradicted values.
    private static let singleValued: Set<IRISPreference.Category> = [.dietary, .seating, .hotelStyle]

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

        // Contradiction path: in single-valued categories a freshly stated value
        // supersedes prior ones (e.g. "I'm vegan now" over an old "vegetarian"). Decay
        // the conflicting values' confidence rather than deleting them outright, so a
        // one-off misunderstanding doesn't erase real history but the latest wins.
        if Self.singleValued.contains(category) {
            for i in preferences.indices where preferences[i].category == category
                && preferences[i].value.lowercased() != normalized.lowercased() {
                preferences[i].confidence = max(0, preferences[i].confidence - 0.3)
            }
        }

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
        enforceCap()
        save()
        return new
    }

    /// Confidence decayed by how long since the preference was last reinforced, so
    /// recall and the prompt favor fresh, actively-held opinions over stale ones.
    func effectiveConfidence(_ p: IRISPreference, now: Date = Date()) -> Double {
        let ageDays = max(0, now.timeIntervalSince(p.lastReinforcedAt) / 86_400)
        return p.confidence * pow(0.5, ageDays / Self.decayHalfLifeDays)
    }

    /// Returns matching preferences, strongest (effective confidence) first.
    func recall(category: IRISPreference.Category? = nil) -> [IRISPreference] {
        let filtered = category.map { c in preferences.filter { $0.category == c } } ?? preferences
        return filtered.sorted { effectiveConfidence($0) > effectiveConfidence($1) }
    }

    /// A summary of the preferences IRIS still holds with meaningful confidence,
    /// formatted for her system prompt. Faded/contradicted preferences (below the
    /// confidence floor) are omitted so she doesn't over-assert stale opinions.
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
        return "What you remember about this user:\n\(lines.joined(separator: "\n"))"
    }

    /// Evicts the weakest preferences once the store grows past its cap. Weakest =
    /// lowest effective confidence, oldest reinforcement as the tiebreak.
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
              let decoded = try? decoder.decode([IRISPreference].self, from: data) else { return }
        preferences = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
