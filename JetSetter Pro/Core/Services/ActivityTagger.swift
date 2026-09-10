// File: Core/Services/ActivityTagger.swift
//
// Pulls the activities a traveler has planned ("sunrise hike", "client dinner",
// "scuba course") out of free-text itinerary titles with Apple Intelligence's
// content-tagging model — the specialised adapter Apple ships for exactly this
// kind of topic/action extraction. Runs on device; returns nothing when the
// model is unavailable so the keyword table in PackingListService still works.

import Foundation
import FoundationModels

@MainActor
final class ActivityTagger {

    static let shared = ActivityTagger()
    private init() {}

    /// Short activity labels found in `titles`, lowercase, de-duplicated. Empty
    /// when Apple Intelligence can't run or nothing activity-like was found.
    func activities(in titles: [String]) async -> [String] {
        let text = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        guard !text.isEmpty else { return [] }
        guard #available(iOS 26.0, *) else { return [] }
        return await tag(text)
    }

    @available(iOS 26.0, *)
    private func tag(_ text: String) async -> [String] {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard case .available = model.availability else { return [] }
        let session = LanguageModelSession(model: model)
        do {
            let response = try await session.respond(
                to: String(text.prefix(1_000)),
                generating: ActivityTags.self
            )
            var seen = Set<String>()
            return response.content.activities
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        } catch {
            return []
        }
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct ActivityTags {
    @Guide(description: "Activities the traveler will do on this trip, e.g. hiking, business meetings, beach, skiing", .maximumCount(6))
    var activities: [String]
}
