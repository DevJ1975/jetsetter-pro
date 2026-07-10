// File: Core/Services/ExpediaAuthService.swift

import Foundation
import CommonCrypto

// MARK: - ExpediaAuthService

/// Builds the EAN signature `Authorization` header required by Expedia Rapid
/// Lodging (availability/content/booking).
///
/// Rapid Lodging does NOT use OAuth2 — it uses signature authentication:
///
///   Authorization: EAN APIKey=<key>,Signature=<sig>,timestamp=<unix seconds>
///
/// where `<sig>` is the unsalted SHA-512 hex hash of the concatenation
/// `apiKey + sharedSecret + timestamp`. The timestamp must be the same value
/// used to build the signature, and Rapid accepts ±5 minutes of clock drift.
///
/// Because the signature is cheap to compute and each request needs a fresh
/// timestamp, we build the header per request rather than caching a token.
final class ExpediaAuthService {

    static let shared = ExpediaAuthService()

    private init() {}

    // MARK: - Public Access

    /// Returns the `Authorization` header dictionary for a Rapid Lodging request,
    /// computed from the configured API key + shared secret and the current time.
    func authorizationHeaders() -> [String: String] {
        let apiKey = APIKeys.expediaClientID
        let secret = APIKeys.expediaClientSecret
        // A blank API key produces an "EAN APIKey=,Signature=…" header whose
        // APIKey field APIClient inspects and treats as `.notConfigured` — the
        // mock fallback path in the view models handles the unconfigured case
        // before we ever get here.
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = Self.sha512Hex(apiKey + secret + timestamp)
        return [
            "Authorization": "EAN APIKey=\(apiKey),Signature=\(signature),timestamp=\(timestamp)"
        ]
    }

    // MARK: - SHA-512

    /// Lowercase hex SHA-512 of a UTF-8 string.
    private static func sha512Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { raw in
            _ = CC_SHA512(raw.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
