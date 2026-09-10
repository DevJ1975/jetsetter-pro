// File: Features/DocumentVault/DocumentVaultStore.swift
//
// On-device persistence for the Document Vault. The entire serialized document
// set — including metadata such as issuing country, expiry, and notes — is
// encrypted with VaultCrypto (AES-GCM, Keychain-backed key) before being written
// to UserDefaults, so nothing sensitive sits in clear text at rest. Document
// numbers are additionally encrypted at the field level; clear-text numbers
// (`docNumberClear`) are never persisted — they are excluded from VaultDocument's
// CodingKeys and only live in memory after biometric auth. Document metadata
// stays on-device (never synced) for privacy.

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
        // Encrypt the entire serialized blob — not just the doc number — so that
        // metadata (issuing country, expiry, notes, photo URL) is also protected
        // at rest rather than sitting in clear text in the UserDefaults plist.
        let plaintext = try JSONCoding.iso8601Encoder.encode(sanitized)
        UserDefaults.standard.set(try VaultCrypto.encrypt(plaintext), forKey: storageKey)
    }

    /// Loads persisted documents. Numbers remain encrypted until `decryptNumbers`.
    static func load() -> [VaultDocument] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        // Current format is an encrypted blob (see `save`). Fall back to decoding
        // the raw bytes so any documents persisted before whole-blob encryption
        // was introduced still load.
        if let plaintext = try? VaultCrypto.decrypt(data),
           let docs = try? JSONCoding.iso8601Decoder.decode([VaultDocument].self, from: plaintext) {
            return docs
        }
        return (try? JSONCoding.iso8601Decoder.decode([VaultDocument].self, from: data)) ?? []
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

    /// Removes all persisted vault documents and photos (used by "Clear Local Data").
    static func wipe() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: photosDirectory)
    }

    // MARK: - Photos (encrypted at rest)

    /// Document photos are AES-GCM encrypted with the same Keychain-backed key
    /// as the numbers, written under Application Support with complete file
    /// protection, and referenced from `VaultDocument.photoUrl` by file name.
    private static var photosDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("vault-photos", isDirectory: true)
    }

    /// Encrypts and stores `data` for the document; returns the file name to keep
    /// in `photoUrl`.
    static func savePhoto(_ data: Data, for documentID: UUID) throws -> String {
        let dir = photosDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let name = "\(documentID.uuidString).enc"
        let encrypted = try VaultCrypto.encrypt(data)
        try encrypted.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Decrypts the stored photo, or nil when there isn't one.
    static func loadPhoto(named name: String?) -> Data? {
        guard let name, !name.isEmpty else { return nil }
        let url = photosDirectory.appendingPathComponent(name)
        guard let encrypted = try? Data(contentsOf: url) else { return nil }
        return try? VaultCrypto.decrypt(encrypted)
    }

    static func deletePhoto(named name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(name))
    }
}
