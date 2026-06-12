// File: Features/LoyaltyVault/LoyaltyViewModel.swift

import Foundation
import Combine

@MainActor
final class LoyaltyViewModel: ObservableObject {

    @Published private(set) var accounts: [LoyaltyAccount] = []

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
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        save()
    }

    func delete(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([LoyaltyAccount].self, from: data) else { return }
        accounts = decoded.sorted {
            (LoyaltyProgramCatalog.find(id: $0.programID)?.name ?? "")
                < (LoyaltyProgramCatalog.find(id: $1.programID)?.name ?? "")
        }
    }

    private func save() {
        guard let data = try? encoder.encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Computed

    var totalAirlineMiles: Int {
        accounts
            .filter { LoyaltyProgramCatalog.find(id: $0.programID)?.kind == .airline }
            .map(\.balance)
            .reduce(0, +)
    }

    var totalHotelPoints: Int {
        accounts
            .filter { LoyaltyProgramCatalog.find(id: $0.programID)?.kind == .hotel }
            .map(\.balance)
            .reduce(0, +)
    }

    var groupedAccounts: [(kind: LoyaltyKind, accounts: [LoyaltyAccount])] {
        let groups = Dictionary(grouping: accounts) {
            LoyaltyProgramCatalog.find(id: $0.programID)?.kind ?? .airline
        }
        return LoyaltyKind.allCases.compactMap { kind in
            guard let entries = groups[kind], !entries.isEmpty else { return nil }
            return (kind, entries)
        }
    }
}
