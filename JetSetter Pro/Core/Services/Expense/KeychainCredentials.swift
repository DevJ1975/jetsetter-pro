// File: Core/Services/Expense/KeychainCredentials.swift
//
// Minimal Keychain wrapper for storing per-provider credentials. Each
// provider has a unique `service` identifier and stores a JSON-encoded blob
// of its fields (API key+secret, OAuth refresh token, etc.).

import Foundation
import Security

enum KeychainCredentials {

    /// Keychain item accessibility. Defaults to the system default when unset.
    enum Accessibility {
        /// Readable only while the device is unlocked, and never migrated to a
        /// new device or iCloud Keychain — appropriate for session tokens.
        case whenUnlockedThisDeviceOnly

        var cfValue: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }

    /// Stores a Codable credentials object under the given service identifier.
    static func store<T: Codable>(
        _ value: T,
        service: String,
        account: String = "default",
        accessibility: Accessibility? = nil
    ) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var attributes: [String: Any] = [kSecValueData as String: data]
        if let accessibility { attributes[kSecAttrAccessible as String] = accessibility.cfValue }

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            if let accessibility { newItem[kSecAttrAccessible as String] = accessibility.cfValue }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw error(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw error(updateStatus)
        }
    }

    /// Loads previously-stored credentials, or nil if none exist.
    static func load<T: Codable>(_ type: T.Type, service: String, account: String = "default") -> T? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Wipes the entry for a service.
    static func delete(service: String, account: String = "default") {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Returns true when an entry exists for the service.
    static func exists(service: String, account: String = "default") -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  false,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Service identifiers used by providers

    enum Service {
        static let expensify = "com.jetsetter.expense.expensify"
        static let ramp      = "com.jetsetter.expense.ramp"
        static let brex      = "com.jetsetter.expense.brex"
        static let divvy     = "com.jetsetter.expense.divvy"
    }

    // MARK: - Error helper

    private static func error(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}
