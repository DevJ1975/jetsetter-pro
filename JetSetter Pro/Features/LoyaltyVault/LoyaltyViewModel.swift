// File: Features/LoyaltyVault/LoyaltyViewModel.swift

import Foundation

@MainActor
@Observable
final class LoyaltyViewModel {

    private(set) var accounts: [LoyaltyAccount] = []

    private let storageKey = "jetsetter_loyalty_accounts"
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init() { load() }

    func addOrUpdate(_ account: LoyaltyAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            let previousProgramID = accounts[index].programID
            accounts[index] = account
            // Learning: an edit that switches the account to a different program
            // is a fresh brand-affinity signal — the profile should reflect the
            // current program set, not the one first entered.
            if account.programID != previousProgramID {
                recordBrandAffinity(for: account.programID)
            }
        } else {
            accounts.append(account)
            // Learning: a newly added loyalty program is a brand-affinity signal.
            recordBrandAffinity(for: account.programID)
        }
        save()
    }

    /// Emits a `.loyaltyAdded` brand-affinity signal for the given program, if
    /// it exists in the catalog.
    private func recordBrandAffinity(for programID: String) {
        guard let program = LoyaltyProgramCatalog.find(id: programID) else { return }
        let brandKind: String
        switch program.kind {
        case .airline:   brandKind = "airline"
        case .hotel:     brandKind = "hotel"
        case .rentalCar: brandKind = "car"
        }
        TravelProfileStore.shared.record(
            .loyaltyAdded,
            value: program.name,
            attributes: ["brandKind": brandKind],
            source: "loyalty"
        )
    }

    func delete(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        // Prefer decrypted data; fall back to plaintext for legacy/seeded blobs
        // written before at-rest encryption (they re-encrypt on next save).
        let json = (try? VaultCrypto.decrypt(data)) ?? data
        guard let decoded = try? decoder.decode([LoyaltyAccount].self, from: json) else { return }
        accounts = decoded.sorted {
            (LoyaltyProgramCatalog.find(id: $0.programID)?.name ?? "")
                < (LoyaltyProgramCatalog.find(id: $1.programID)?.name ?? "")
        }
    }

    private func save() {
        // Member numbers are sensitive PII — encrypt at rest with the same
        // AES-GCM/Keychain key the Document Vault uses.
        guard let data = try? encoder.encode(accounts),
              let encrypted = try? VaultCrypto.encrypt(data) else { return }
        UserDefaults.standard.set(encrypted, forKey: storageKey)
    }

    // MARK: - Computed

    /// The single source of truth for an account's kind. Unknown programs
    /// (e.g. a catalog id renamed/removed in a later build) fall back to
    /// `.airline` so the totals and the grouped sections can never diverge —
    /// the same account is both shown under a section and counted in its total.
    private func kind(for account: LoyaltyAccount) -> LoyaltyKind {
        LoyaltyProgramCatalog.find(id: account.programID)?.kind ?? .airline
    }

    var totalAirlineMiles: Int {
        accounts
            .filter { kind(for: $0) == .airline }
            .map(\.balance)
            .reduce(0, +)
    }

    var totalHotelPoints: Int {
        accounts
            .filter { kind(for: $0) == .hotel }
            .map(\.balance)
            .reduce(0, +)
    }

    var groupedAccounts: [(kind: LoyaltyKind, accounts: [LoyaltyAccount])] {
        let groups = Dictionary(grouping: accounts) { kind(for: $0) }
        return LoyaltyKind.allCases.compactMap { kind in
            guard let entries = groups[kind], !entries.isEmpty else { return nil }
            return (kind, entries)
        }
    }
}
