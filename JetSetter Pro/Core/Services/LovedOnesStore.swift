// File: Core/Services/LovedOnesStore.swift
//
// Stores the traveler's "loved ones" — the people IRIS offers to text on
// takeoff and landing. Persisted locally (UserDefaults JSON), mirroring the
// IRISMemory / CheckInStateStore persistence idiom. Numbers never leave the
// device except when the user taps Send in the pre-filled Messages composer.

import Foundation

// MARK: - Model

struct LovedOne: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var phoneNumber: String
    /// Text this person when the flight takes off.
    var notifyOnTakeoff: Bool = true
    /// Text this person when the flight lands.
    var notifyOnLanding: Bool = true
}

// MARK: - Store

@MainActor
@Observable
final class LovedOnesStore {

    static let shared = LovedOnesStore()

    private let storageKey = "jetsetter_loved_ones"

    private(set) var contacts: [LovedOne] = []

    private init() {
        load()
    }

    // MARK: - Queries

    /// Contacts that should be texted for the given flight event.
    func contacts(for event: LovedOnesEvent) -> [LovedOne] {
        switch event {
        case .takeoff: return contacts.filter { $0.notifyOnTakeoff }
        case .landing: return contacts.filter { $0.notifyOnLanding }
        }
    }

    var isEmpty: Bool { contacts.isEmpty }

    // MARK: - Mutations

    func add(name: String, phoneNumber: String,
             notifyOnTakeoff: Bool = true, notifyOnLanding: Bool = true) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedNumber.isEmpty else { return }
        contacts.append(LovedOne(
            name: trimmedName,
            phoneNumber: trimmedNumber,
            notifyOnTakeoff: notifyOnTakeoff,
            notifyOnLanding: notifyOnLanding
        ))
        save()
    }

    func update(_ contact: LovedOne) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[idx] = contact
        save()
    }

    func remove(_ contact: LovedOne) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    /// Wipes all stored contacts. Called by the "Clear Local Data" privacy flow.
    func removeAll() {
        contacts = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        contacts = (try? JSONDecoder().decode([LovedOne].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Event

/// A flight milestone that can trigger a message to loved ones.
enum LovedOnesEvent: String {
    case takeoff
    case landing
}
