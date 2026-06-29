// File: Core/Services/SupabaseService.swift
//
// Supabase backend integration using the public REST APIs — no Supabase SDK
// required. This keeps the SPM dependency surface minimal and mirrors the
// prior FirebaseService design (which this file replaces).
//
// AUTH:  {SUPABASE_URL}/auth/v1/*          (GoTrue)
// DATA:  {SUPABASE_URL}/rest/v1/{table}    (PostgREST)
//
// Each row stores the JSON-encoded model in a single `payload` jsonb column,
// keyed by the model's UUID `id` and scoped to `user_id` (enforced by RLS).
// This keeps the migration simple — Postgres holds an opaque blob per model,
// exactly like the previous Firestore `payload` field. See SETUP-SUPABASE.md
// for the schema, RLS policies, and the `delete-user` Edge Function.

import Foundation

// MARK: - Configuration

private enum SupabaseConfig {
    // Statics are `nonisolated` so the actor methods on SupabaseService
    // (and any other actor context) can read them without crossing an
    // actor boundary. The project defaults to `@MainActor` isolation,
    // which is why these would otherwise inherit MainActor isolation.
    nonisolated static let url: String     = readSupabaseSecret("API_SUPABASE_URL")
    nonisolated static let anonKey: String = readSupabaseSecret("API_SUPABASE_ANON_KEY")

    nonisolated static var authBase: String { "\(url)/auth/v1" }
    nonisolated static var restBase: String { "\(url)/rest/v1" }
    nonisolated static var functionsBase: String { "\(url)/functions/v1" }
}

/// Bundle-level secret reader. Mirrors `AppSecrets.value(for:)` but is
/// `nonisolated` so it can be referenced from any actor context.
private nonisolated func readSupabaseSecret(_ key: String) -> String {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return "" }
    if trimmed.hasPrefix("YOUR_") || trimmed == "REPLACE_ME" { return "" }
    return trimmed
}

// MARK: - Auth models
//
// These wire-format types are marked `nonisolated` so their synthesized
// `Codable` conformances are also nonisolated and can be used from inside
// the `SupabaseService` actor (and from `nonisolated` decoder callbacks).

nonisolated struct SupabaseUser: Codable, Identifiable {
    let id: String          // Supabase auth user UID (JWT `sub`)
    let email: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, createdAt
    }
}

nonisolated struct SupabaseSession: Codable {
    let accessToken: String   // GoTrue access_token (JWT)
    let refreshToken: String
    let expiresAt: Date
    let user: SupabaseUser
}

nonisolated struct SupabaseAPIError: Codable, LocalizedError {
    let message: String
    let code: Int?

    var errorDescription: String? { message }
}

// MARK: - Service

actor SupabaseService {

    static let shared = SupabaseService()
    private init() {}

    /// Per-user collections, as Postgres table names (snake_case). Used by the
    /// account-deletion sweep.
    private static let tables = ["expenses", "trips", "wallet_items", "packing_lists", "disruption_events"]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Session cache (Keychain, device-only)

    private static let sessionService = "com.jetsetter.supabase.session"

    private var cachedSession: SupabaseSession? {
        get { KeychainCredentials.load(SupabaseSession.self, service: Self.sessionService) }
        set {
            if let s = newValue {
                try? KeychainCredentials.store(s, service: Self.sessionService,
                                               accessibility: .whenUnlockedThisDeviceOnly)
            } else {
                KeychainCredentials.delete(service: Self.sessionService)
            }
        }
    }

    var currentUser: SupabaseUser? { cachedSession?.user }
    var isSignedIn: Bool { cachedSession != nil }
    var accessToken: String? { cachedSession?.accessToken }

    // MARK: - Authentication

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        try ensureConfigured()
        let url = URL(string: "\(SupabaseConfig.authBase)/signup")!
        let data = try await sendJSON(
            url: url, method: "POST",
            body: ["email": email, "password": password],
            authenticated: false
        )
        // When email confirmation is disabled, GoTrue returns a full session.
        // When it's enabled, it returns only the user object (no tokens).
        if let session = try? makeSession(from: data) {
            cachedSession = session
            return session
        }
        throw SupabaseAPIError(
            message: "Account created. Check your email to confirm, then sign in.",
            code: nil
        )
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        try ensureConfigured()
        let url = URL(string: "\(SupabaseConfig.authBase)/token?grant_type=password")!
        let data = try await sendJSON(
            url: url, method: "POST",
            body: ["email": email, "password": password],
            authenticated: false
        )
        let session = try makeSession(from: data)
        cachedSession = session
        return session
    }

    func signOut() async {
        // Best-effort token revocation; the local session is always cleared.
        if accessToken != nil {
            let url = URL(string: "\(SupabaseConfig.authBase)/logout")!
            _ = try? await sendJSON(url: url, method: "POST", body: nil, authenticated: true)
        }
        cachedSession = nil
    }

    func refreshSession() async throws {
        guard let refresh = cachedSession?.refreshToken else {
            throw SupabaseAPIError(message: "No active session", code: nil)
        }
        let url = URL(string: "\(SupabaseConfig.authBase)/token?grant_type=refresh_token")!
        let data = try await sendJSON(
            url: url, method: "POST",
            body: ["refresh_token": refresh],
            authenticated: false
        )
        cachedSession = try makeSession(from: data)
    }

    // MARK: - Account deletion (App Store Guideline 5.1.1(v))

    /// Permanently deletes the user's synced data and auth account. RLS lets the
    /// signed-in user delete their own rows; the auth user itself is removed by
    /// the `delete-user` Edge Function (service-role), invoked with the user's JWT.
    func deleteAccount() async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id

        for table in Self.tables {
            try? await deleteRows(table: table, userId: uid)
        }

        let url = URL(string: "\(SupabaseConfig.functionsBase)/delete-user")!
        _ = try await sendJSON(url: url, method: "POST", body: [:], authenticated: true)

        cachedSession = nil
    }

    // MARK: - Expenses

    func syncExpenses(_ expenses: [Expense]) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        for expense in expenses {
            try await upsertRow(table: "expenses", id: expense.id, userId: uid, model: expense)
        }
    }

    func fetchExpenses() async throws -> [Expense] {
        try ensureAuthenticated()
        return try await listRows(table: "expenses", as: Expense.self)
    }

    // MARK: - Trips

    func syncTrips(_ trips: [Trip]) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        for trip in trips {
            try await upsertRow(table: "trips", id: trip.id, userId: uid, model: trip)
        }
    }

    func fetchTrips() async throws -> [Trip] {
        try ensureAuthenticated()
        return try await listRows(table: "trips", as: Trip.self)
    }

    // MARK: - Wallet

    func fetchWalletItems() async throws -> [WalletItem] {
        try ensureAuthenticated()
        return try await listRows(table: "wallet_items", as: WalletItem.self)
    }

    func upsertWalletItem(_ item: WalletItem) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertRow(table: "wallet_items", id: item.id, userId: uid, model: item)
    }

    func deleteWalletItem(id: UUID) async throws {
        try ensureAuthenticated()
        try await deleteRow(table: "wallet_items", id: id)
    }

    // MARK: - Packing lists

    func fetchPackingList(tripId: UUID) async throws -> PackingListResult? {
        try ensureAuthenticated()
        return try? await getRow(table: "packing_lists", id: tripId, as: PackingListResult.self)
    }

    func upsertPackingList(_ list: PackingListResult) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertRow(table: "packing_lists", id: list.id, userId: uid, model: list)
    }

    // MARK: - Disruption events

    func fetchDisruptionEvents() async throws -> [DisruptionEvent] {
        try ensureAuthenticated()
        return try await listRows(table: "disruption_events", as: DisruptionEvent.self)
    }

    func upsertDisruptionEvent(_ event: DisruptionEvent) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertRow(table: "disruption_events", id: event.id, userId: uid, model: event)
    }

    // MARK: - PostgREST primitives

    private func upsertRow<T: Encodable>(table: String, id: UUID, userId: String, model: T) async throws {
        let payloadData = try encoder.encode(model)
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
        let row: [String: Any] = [
            "id": id.uuidString,
            "user_id": userId,
            "payload": payloadObject,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)")!
        // POST + merge-duplicates = upsert on the primary key (`id`).
        _ = try await sendJSON(
            url: url, method: "POST", body: row, authenticated: true,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    private func getRow<T: Decodable>(table: String, id: UUID, as type: T.Type) async throws -> T {
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)?id=eq.\(id.uuidString)&select=payload&limit=1")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let payload = rows.first?["payload"] as? [String: Any],
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw SupabaseAPIError(message: "Not found in \(table)", code: nil)
        }
        return try decoder.decode(T.self, from: payloadData)
    }

    private func listRows<T: Decodable>(table: String, as type: T.Type) async throws -> [T] {
        // RLS scopes the result to the signed-in user automatically.
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)?select=payload")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var results: [T] = []
        for row in rows {
            guard let payload = row["payload"] as? [String: Any],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let decoded = try? decoder.decode(T.self, from: payloadData) else { continue }
            results.append(decoded)
        }
        return results
    }

    private func deleteRow(table: String, id: UUID) async throws {
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)?id=eq.\(id.uuidString)")!
        _ = try await sendJSON(url: url, method: "DELETE", body: nil, authenticated: true)
    }

    private func deleteRows(table: String, userId: String) async throws {
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)?user_id=eq.\(userId)")!
        _ = try await sendJSON(url: url, method: "DELETE", body: nil, authenticated: true)
    }

    // MARK: - HTTP helpers

    private func sendJSON(
        url: URL, method: String, body: [String: Any]?, authenticated: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        // Authenticated calls carry the user's JWT so Postgres RLS applies;
        // unauthenticated (auth) calls fall back to the anon/publishable key.
        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError(message: "Invalid server response", code: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            // GoTrue / PostgREST surface errors under several keys.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = (json["message"] as? String)
                    ?? (json["error_description"] as? String)
                    ?? (json["msg"] as? String)
                    ?? (json["error"] as? String)
                if let message {
                    throw SupabaseAPIError(message: message, code: http.statusCode)
                }
            }
            throw SupabaseAPIError(message: "HTTP \(http.statusCode)", code: http.statusCode)
        }
    }

    private func makeSession(from data: Data) throws -> SupabaseSession {
        let response = try decoder.decode(GoTrueTokenResponse.self, from: data)
        let user = SupabaseUser(
            id: response.user.id,
            email: response.user.email,
            createdAt: response.user.created_at
        )
        return SupabaseSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in)),
            user: user
        )
    }

    private func ensureConfigured() throws {
        guard !SupabaseConfig.url.isEmpty, !SupabaseConfig.anonKey.isEmpty else {
            throw SupabaseAPIError(
                message: "Supabase isn't configured. Add API_SUPABASE_URL and API_SUPABASE_ANON_KEY in Secrets.xcconfig.",
                code: nil
            )
        }
    }

    private func ensureAuthenticated() throws {
        guard isSignedIn else {
            throw SupabaseAPIError(message: "Sign in to sync your data.", code: nil)
        }
    }
}

// MARK: - GoTrue token response shape

private nonisolated struct GoTrueTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: GoTrueUser
}

private nonisolated struct GoTrueUser: Decodable {
    let id: String
    let email: String?
    let created_at: String?
}
