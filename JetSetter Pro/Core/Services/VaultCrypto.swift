// File: Core/Services/VaultCrypto.swift
//
// App-wide symmetric encryption primitive. A 256-bit AES key is generated once
// and stored in the Keychain (device-only, available only when the device is
// unlocked). Used to encrypt sensitive PII at rest — e.g. travel-document
// numbers in the Document Vault.

import Foundation
import CryptoKit
import Security

enum VaultCrypto {

    private static let keyService = "com.jetsetter.vault.masterkey"
    private static let keyAccount = "default"

    enum CryptoError: LocalizedError {
        case keyStorageFailed(OSStatus)
        case sealFailed
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .keyStorageFailed(let status): return "Secure key storage failed (\(status))."
            case .sealFailed:                   return "Couldn't encrypt the data."
            case .decodeFailed:                 return "Couldn't decrypt the protected data."
            }
        }
    }

    // MARK: - Data

    static func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: try loadOrCreateKey())
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: try loadOrCreateKey())
    }

    // MARK: - String → base64 ciphertext convenience

    /// Encrypts a UTF-8 string and returns base64-encoded ciphertext.
    static func encryptToBase64(_ string: String) throws -> String {
        try encrypt(Data(string.utf8)).base64EncodedString()
    }

    /// Decrypts base64-encoded ciphertext back into a UTF-8 string.
    static func decryptFromBase64(_ base64: String) throws -> String {
        guard let cipher = Data(base64Encoded: base64) else { throw CryptoError.decodeFailed }
        guard let string = String(data: try decrypt(cipher), encoding: .utf8) else {
            throw CryptoError.decodeFailed
        }
        return string
    }

    // MARK: - Key management (Keychain, device-only)

    private static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let identity: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount
        ]
        SecItemDelete(identity as CFDictionary)   // clear any stale entry first

        var addQuery = identity
        addQuery[kSecValueData as String]   = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoError.keyStorageFailed(status) }
    }
}
