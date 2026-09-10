// File: Core/Services/ExpediaAuthService.swift

import Foundation

// MARK: - ExpediaAuthService

/// Fetches the EAN signature `Authorization` header required by Expedia Rapid
/// Lodging from the server-side proxy.
///
/// Rapid Lodging authenticates with a signature header:
///
///   Authorization: EAN APIKey=<key>,Signature=<sig>,timestamp=<unix seconds>
///
/// where `<sig>` is the unsalted SHA-512 hex hash of `apiKey + sharedSecret +
/// timestamp`. The API key **and** shared secret are full-account credentials,
/// so — like the Duffel token — they live only on the proxy (env vars) and are
/// never compiled into the app. The app authenticates to the proxy with the
/// shared `PROXY_APP_KEY` and forwards the returned header on its Rapid requests.
final class ExpediaAuthService {

    static let shared = ExpediaAuthService()

    private init() {}

    private struct AuthHeaderResponse: Decodable {
        let authorization: String
    }

    // MARK: - Public Access

    /// Returns the `Authorization` header dictionary for a Rapid Lodging request,
    /// fetched from the proxy's `/expedia/auth-header` endpoint. Returns `nil`
    /// when the proxy isn't configured or is unreachable, so callers fall back to
    /// mock data / an unconfigured message instead of sending an invalid request.
    func authorizationHeaders() async -> [String: String]? {
        guard let base = AppSecrets.value(for: .duffelProxyURL),
              let key = AppSecrets.value(for: .duffelProxyKey),
              let url = URL(string: "\(base)/expedia/auth-header") else {
            return nil
        }

        do {
            let response: AuthHeaderResponse = try await APIClient.shared.get(
                url: url,
                headers: ["Authorization": "Bearer \(key)"]
            )
            return ["Authorization": response.authorization]
        } catch {
            return nil
        }
    }
}
