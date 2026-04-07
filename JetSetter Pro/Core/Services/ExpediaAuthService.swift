// File: Core/Services/ExpediaAuthService.swift

import Foundation

// MARK: - ExpediaAuthService

/// Manages Expedia OAuth 2.0 client-credentials token lifecycle.
/// Automatically requests a new token when the cached one has expired.
final class ExpediaAuthService {

    static let shared = ExpediaAuthService()

    // MARK: - Cached Token State

    private var cachedToken: String? = nil
    private var tokenExpiryDate: Date? = nil

    private init() {}

    // MARK: - Public Access

    /// Returns a valid Bearer token, requesting a new one from Expedia if necessary.
    func validToken() async throws -> String {
        // Return cached token if it's still valid (with a 60-second buffer)
        if let token = cachedToken,
           let expiry = tokenExpiryDate,
           expiry > Date().addingTimeInterval(60) {
            return token
        }

        return try await fetchNewToken()
    }

    // MARK: - Token Request

    /// Fetches a fresh token from the Expedia OAuth endpoint using client credentials.
    private func fetchNewToken() async throws -> String {
        guard let url = Endpoints.Expedia.tokenURL else {
            throw APIError.invalidURL
        }

        // Expedia token endpoint requires application/x-www-form-urlencoded body
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=client_credentials",
            "client_id=\(APIKeys.expediaClientID)",
            "client_secret=\(APIKeys.expediaClientSecret)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.unknown(error)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let tokenResponse: ExpediaTokenResponse
        do {
            tokenResponse = try decoder.decode(ExpediaTokenResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }

        // Cache the new token with its expiry time
        cachedToken = tokenResponse.accessToken
        tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        return tokenResponse.accessToken
    }
}
