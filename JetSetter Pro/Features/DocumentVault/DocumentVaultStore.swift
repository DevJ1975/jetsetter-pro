// File: Features/DocumentVault/DocumentVaultStore.swift
//
// On-device persistence for the Document Vault. Travel-document numbers are
// encrypted with VaultCrypto (AES-GCM, Keychain-backed key) before being
// written. Clear-text numbers (`docNumberClear`) are never persisted — they are
// excluded from VaultDocument's CodingKeys and only live in memory after
// biometric auth. Document metadata stays on-device (never synced) for privacy.

import Foundation

enum DocumentVaultStore {

    private static let storageKey = "jetsetter_vault_documents"

    /// Persists documents, encrypting each clear-text number into
    /// `docNumberEncrypted`. The in-memory array passed in is not mutated.
    static func save(_ documents: [VaultDocument]) throws {
        let sanitized: [VaultDocument] = try documents.map { doc in
            var copy = doc
            if let clear = doc.docNumberClear, !clear.isEmpty {
                copy.docNumberEncrypted = try VaultCrypto.encryptToBase64(clear)
            }
            copy.docNumberClear = nil   // never persisted (also excluded from CodingKeys)
            return copy
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode(sanitized), forKey: storageKey)
    }

    /// Loads persisted documents. Numbers remain encrypted until `decryptNumbers`.
    static func load() -> [VaultDocument] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([VaultDocument].self, from: data)) ?? []
    }

    /// Decrypts each document's number into an `[id: clearNumber]` map for
    /// in-session display. Falls back to any in-memory clear value (e.g. a
    /// freshly-added, not-yet-persisted document).
    static func decryptNumbers(for documents: [VaultDocument]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for doc in documents {
            if let encrypted = doc.docNumberEncrypted,
               let clear = try? VaultCrypto.decryptFromBase64(encrypted) {
                result[doc.id] = clear
            } else if let clear = doc.docNumberClear {
                result[doc.id] = clear
            }
        }
        return result
    }

    /// Removes all persisted vault documents (used by "Clear Local Data").
    static func wipe() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
