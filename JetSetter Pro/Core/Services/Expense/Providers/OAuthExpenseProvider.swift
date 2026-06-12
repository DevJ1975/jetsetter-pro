// File: Core/Services/Expense/Providers/OAuthExpenseProvider.swift
//
// Shared OAuth 2.0 plumbing for Ramp, Brex, and Divvy. Each subclass overrides
// `endpoints` and `submitMapping`. The OAuth flow uses ASWebAuthenticationSession.

import Foundation
import AuthenticationServices
import UIKit

// MARK: - Token

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { expiresAt < Date().addingTimeInterval(60) }
}

// MARK: - Provider endpoints

struct OAuthProviderEndpoints {
    let authorizationURL: String         // user-facing auth URL
    let tokenURL: String                 // backchannel token exchange
    let createExpenseURL: String         // POST to create a single expense
    let scope: String
    let redirectScheme: String           // app URL scheme registered for callback
    let clientID: String                 // from AppSecrets
    let clientSecret: String?            // some providers use PKCE only; nil ok
}

// MARK: - Base class

@MainActor
class OAuthExpenseProvider: NSObject, ExpenseExportProvider, ASWebAuthenticationPresentationContextProviding {

    var id: String { fatalError("override") }
    var displayName: String { fatalError("override") }
    var tagline: String { fatalError("override") }
    var brandColorHex: String { fatalError("override") }
    var systemImage: String { "creditcard.fill" }
    var authKind: ExpenseProviderAuthKind { .oauth2 }

    var keychainService: String { fatalError("override") }
    var endpoints: OAuthProviderEndpoints { fatalError("override") }

    // MARK: - Connection

    func isConnected() async -> Bool {
        KeychainCredentials.exists(service: keychainService)
    }

    func disconnect() async {
        KeychainCredentials.delete(service: keychainService)
    }

    func connect() async throws -> Bool {
        // 1. Build auth URL with state + PKCE challenge.
        let state = UUID().uuidString
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = sha256Base64URL(codeVerifier)

        var components = URLComponents(string: endpoints.authorizationURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: endpoints.clientID),
            URLQueryItem(name: "redirect_uri", value: "\(endpoints.redirectScheme)://oauth-callback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: endpoints.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else {
            throw ExpenseExportError.providerFailure("Could not build auth URL.")
        }

        // 2. Present web auth session.
        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: endpoints.redirectScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let returnedCode = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                      comps.queryItems?.first(where: { $0.name == "state" })?.value == state
                else {
                    continuation.resume(throwing: ExpenseExportError.providerFailure("Bad OAuth callback."))
                    return
                }
                continuation.resume(returning: returnedCode)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: ExpenseExportError.providerFailure("Couldn't start auth session."))
            }
        }

        // 3. Exchange code for tokens.
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        try KeychainCredentials.store(tokens, service: keychainService)
        return true
    }

    // MARK: - Submit

    func submit(trip: Trip?, expenses: [Expense]) async throws -> ExportBatchResult {
        var tokens = KeychainCredentials.load(OAuthTokens.self, service: keychainService)
        guard tokens != nil else { throw ExpenseExportError.notConnected }

        if tokens!.isExpired {
            tokens = try await refreshTokens(tokens!)
            try KeychainCredentials.store(tokens!, service: keychainService)
        }

        var per: [UUID: ExportOutcome] = [:]
        for expense in expenses {
            do {
                let remoteID = try await postExpense(expense, accessToken: tokens!.accessToken)
                per[expense.id] = .submitted(remoteID: remoteID)
            } catch {
                per[expense.id] = .failed(error: error.localizedDescription)
            }
        }
        return ExportBatchResult(
            providerID: id, providerName: displayName,
            submittedAt: Date(), perExpense: per
        )
    }

    // MARK: - Overridable for per-provider payload shape

    /// Returns the JSON dict for one expense in the provider's format.
    /// Default uses a generic shape; subclasses should override.
    func payload(for expense: Expense) -> [String: Any] {
        [
            "merchant": expense.merchant,
            "amount_cents": Int(round(expense.amount * 100)),
            "currency": expense.currency,
            "category": expense.category.displayName,
            "date": ISO8601DateFormatter().string(from: expense.date),
            "notes": expense.notes ?? "",
            "external_id": expense.id.uuidString
        ]
    }

    /// Sends one expense via POST; returns the provider's remote ID on success.
    private func postExpense(_ expense: Expense, accessToken: String) async throws -> String {
        guard let url = URL(string: endpoints.createExpenseURL) else {
            throw ExpenseExportError.providerFailure("Bad create URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(for: expense))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExpenseExportError.providerFailure("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = dict["id"] as? String {
            return id
        }
        return expense.id.uuidString
    }

    // MARK: - OAuth token exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> OAuthTokens {
        guard let url = URL(string: endpoints.tokenURL) else {
            throw ExpenseExportError.providerFailure("Bad token URL.")
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: "\(endpoints.redirectScheme)://oauth-callback"),
            URLQueryItem(name: "client_id", value: endpoints.clientID),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ]
        if let secret = endpoints.clientSecret {
            components.queryItems?.append(URLQueryItem(name: "client_secret", value: secret))
        }
        let formBody = (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExpenseExportError.providerFailure("Token exchange failed: \(body.prefix(200))")
        }
        return try decodeTokens(from: data)
    }

    private func refreshTokens(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refresh = tokens.refreshToken,
              let url = URL(string: endpoints.tokenURL) else {
            throw ExpenseExportError.notConnected
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "client_id", value: endpoints.clientID)
        ]
        if let secret = endpoints.clientSecret {
            components.queryItems?.append(URLQueryItem(name: "client_secret", value: secret))
        }
        let body = (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExpenseExportError.providerFailure("Token refresh failed.")
        }
        return try decodeTokens(from: data)
    }

    private func decodeTokens(from data: Data) throws -> OAuthTokens {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresIn = TimeInterval(decoded.expires_in ?? 3600)
        return OAuthTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    // MARK: - PKCE helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func sha256Base64URL(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { raw in
            _ = CC_SHA256(raw.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        DispatchQueue.main.sync {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Base64URL

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - CommonCrypto shim

import CommonCrypto
