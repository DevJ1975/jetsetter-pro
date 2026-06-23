// File: Core/Services/FirebaseService.swift
//
// Firebase backend integration using the public REST APIs — no Firebase SDK
// required. This keeps the SPM dependency surface minimal and avoids needing
// to wire up `GoogleService-Info.plist` for the MVP.
//
// AUTH:  https://identitytoolkit.googleapis.com/v1/accounts:*
// DATA:  https://firestore.googleapis.com/v1/projects/{projectID}/databases/(default)/documents/*
//
// Each Firestore document stores a single `payload` field with the JSON-encoded
// model. This keeps the migration simple — the Firebase console will show the
// docs but won't decompose individual fields. Future iteration can break out
// proper Firestore field types if rich queries are needed.

import Foundation

// MARK: - Configuration

private enum FirebaseConfig {
    // Statics are `nonisolated` so the actor methods on FirebaseService
    // (and any other actor context) can read them without crossing an
    // actor boundary. The project defaults to `@MainActor` isolation,
    // which is why these would otherwise inherit MainActor isolation.
    nonisolated static let projectID: String = readFirebaseSecret("API_FIREBASE_PROJECT_ID")
    nonisolated static let apiKey: String    = readFirebaseSecret("API_FIREBASE_API_KEY")

    nonisolated static let authBase    = "https://identitytoolkit.googleapis.com/v1/accounts"
    nonisolated static let refreshBase = "https://securetoken.googleapis.com/v1/token"

    nonisolated static var firestoreBase: String {
        "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents"
    }
}

/// Bundle-level secret reader. Mirrors `AppSecrets.value(for:)` but is
/// `nonisolated` so it can be referenced from any actor context.
private nonisolated func readFirebaseSecret(_ key: String) -> String {
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
// the `FirebaseService` actor (and from `nonisolated` decoder callbacks).

nonisolated struct FirebaseUser: Codable, Identifiable {
    let id: String          // Firebase localId / UID
    let email: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, createdAt
    }
}

nonisolated struct FirebaseSession: Codable {
    let accessToken: String   // idToken from Firebase
    let refreshToken: String
    let expiresAt: Date
    let user: FirebaseUser
}

nonisolated struct FirebaseAPIError: Codable, LocalizedError {
    let message: String
    let code: Int?

    var errorDescription: String? { message }
}

// MARK: - Service

actor FirebaseService {

    static let shared = FirebaseService()
    private init() {}

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: - Session cache (UserDefaults)

    private var cachedSession: FirebaseSession? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "firebase_session"),
                  let session = try? JSONDecoder().decode(FirebaseSession.self, from: data)
            else { return nil }
            return session
        }
        set {
            if let s = newValue, let data = try? JSONEncoder().encode(s) {
                UserDefaults.standard.set(data, forKey: "firebase_session")
            } else {
                UserDefaults.standard.removeObject(forKey: "firebase_session")
            }
        }
    }

    var currentUser: FirebaseUser? { cachedSession?.user }
    var isSignedIn: Bool { cachedSession != nil }
    var accessToken: String? { cachedSession?.accessToken }

    // MARK: - Authentication

    func signUp(email: String, password: String) async throws -> FirebaseSession {
        try ensureConfigured()
        let url = URL(string: "\(FirebaseConfig.authBase):signUp?key=\(FirebaseConfig.apiKey)")!
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]
        let response: FirebaseAuthResponse = try await postJSON(url: url, body: body, authenticated: false)
        let session = makeSession(from: response, email: email)
        cachedSession = session
        return session
    }

    func signIn(email: String, password: String) async throws -> FirebaseSession {
        try ensureConfigured()
        let url = URL(string: "\(FirebaseConfig.authBase):signInWithPassword?key=\(FirebaseConfig.apiKey)")!
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ]
        let response: FirebaseAuthResponse = try await postJSON(url: url, body: body, authenticated: false)
        let session = makeSession(from: response, email: email)
        cachedSession = session
        return session
    }

    func signOut() async {
        cachedSession = nil
    }

    func refreshSession() async throws {
        guard let refresh = cachedSession?.refreshToken else {
            throw FirebaseAPIError(message: "No active session", code: nil)
        }
        let url = URL(string: "\(FirebaseConfig.refreshBase)?key=\(FirebaseConfig.apiKey)")!
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh)
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        struct RefreshResponse: Decodable {
            let id_token: String
            let refresh_token: String
            let user_id: String
            let expires_in: String
        }
        let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
        let expires = Date().addingTimeInterval(TimeInterval(decoded.expires_in) ?? 3600)
        let user = cachedSession?.user ?? FirebaseUser(id: decoded.user_id, email: nil, createdAt: nil)
        cachedSession = FirebaseSession(
            accessToken: decoded.id_token,
            refreshToken: decoded.refresh_token,
            expiresAt: expires,
            user: user
        )
    }

    // MARK: - Expenses

    func syncExpenses(_ expenses: [Expense]) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        for expense in expenses {
            try await upsertDoc(
                path: "users/\(uid)/expenses/\(expense.id.uuidString)",
                model: expense
            )
        }
    }

    func fetchExpenses() async throws -> [Expense] {
        try ensureAuthenticated()
        let uid = currentUser!.id
        return try await listDocs(path: "users/\(uid)/expenses", as: Expense.self)
    }

    // MARK: - Trips

    func syncTrips(_ trips: [Trip]) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        for trip in trips {
            try await upsertDoc(
                path: "users/\(uid)/trips/\(trip.id.uuidString)",
                model: trip
            )
        }
    }

    func fetchTrips() async throws -> [Trip] {
        try ensureAuthenticated()
        let uid = currentUser!.id
        return try await listDocs(path: "users/\(uid)/trips", as: Trip.self)
    }

    // MARK: - Wallet

    func fetchWalletItems() async throws -> [WalletItem] {
        try ensureAuthenticated()
        let uid = currentUser!.id
        return try await listDocs(path: "users/\(uid)/walletItems", as: WalletItem.self)
    }

    func upsertWalletItem(_ item: WalletItem) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertDoc(
            path: "users/\(uid)/walletItems/\(item.id.uuidString)",
            model: item
        )
    }

    func deleteWalletItem(id: UUID) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await deleteDoc(path: "users/\(uid)/walletItems/\(id.uuidString)")
    }

    // MARK: - Packing lists

    func fetchPackingList(tripId: UUID) async throws -> PackingListResult? {
        try ensureAuthenticated()
        let uid = currentUser!.id
        return try? await getDoc(
            path: "users/\(uid)/packingLists/\(tripId.uuidString)",
            as: PackingListResult.self
        )
    }

    func upsertPackingList(_ list: PackingListResult) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertDoc(
            path: "users/\(uid)/packingLists/\(list.id.uuidString)",
            model: list
        )
    }

    // MARK: - Disruption events

    func fetchDisruptionEvents() async throws -> [DisruptionEvent] {
        try ensureAuthenticated()
        let uid = currentUser!.id
        return try await listDocs(path: "users/\(uid)/disruptionEvents", as: DisruptionEvent.self)
    }

    func upsertDisruptionEvent(_ event: DisruptionEvent) async throws {
        try ensureAuthenticated()
        let uid = currentUser!.id
        try await upsertDoc(
            path: "users/\(uid)/disruptionEvents/\(event.id.uuidString)",
            model: event
        )
    }

    // MARK: - Firestore primitives

    private func upsertDoc<T: Encodable>(path: String, model: T) async throws {
        let json = try encoder.encode(model)
        guard let payload = String(data: json, encoding: .utf8) else {
            throw FirebaseAPIError(message: "Couldn't encode model", code: nil)
        }
        let url = URL(string: "\(FirebaseConfig.firestoreBase)/\(path)")!
        let body: [String: Any] = [
            "fields": [
                "payload": ["stringValue": payload],
                "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())]
            ]
        ]
        _ = try await sendJSON(url: url, method: "PATCH", body: body, authenticated: true)
    }

    private func getDoc<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let url = URL(string: "\(FirebaseConfig.firestoreBase)/\(path)")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = doc["fields"] as? [String: Any],
              let payloadField = fields["payload"] as? [String: Any],
              let payloadString = payloadField["stringValue"] as? String,
              let payloadData = payloadString.data(using: .utf8) else {
            throw FirebaseAPIError(message: "Couldn't decode document at \(path)", code: nil)
        }
        return try decoder.decode(T.self, from: payloadData)
    }

    private func listDocs<T: Decodable>(path: String, as type: T.Type) async throws -> [T] {
        let url = URL(string: "\(FirebaseConfig.firestoreBase)/\(path)")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let documents = response["documents"] as? [[String: Any]] else { return [] }

        var results: [T] = []
        for doc in documents {
            guard let fields = doc["fields"] as? [String: Any],
                  let payloadField = fields["payload"] as? [String: Any],
                  let payloadString = payloadField["stringValue"] as? String,
                  let payloadData = payloadString.data(using: .utf8),
                  let decoded = try? decoder.decode(T.self, from: payloadData) else { continue }
            results.append(decoded)
        }
        return results
    }

    private func deleteDoc(path: String) async throws {
        let url = URL(string: "\(FirebaseConfig.firestoreBase)/\(path)")!
        _ = try await sendJSON(url: url, method: "DELETE", body: nil, authenticated: true)
    }

    // MARK: - HTTP helpers

    private func postJSON<Response: Decodable>(
        url: URL, body: [String: Any], authenticated: Bool
    ) async throws -> Response {
        let data = try await sendJSON(url: url, method: "POST", body: body, authenticated: authenticated)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendJSON(
        url: URL, method: String, body: [String: Any]?, authenticated: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
            throw FirebaseAPIError(message: "Invalid server response", code: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            // Firebase returns errors as { "error": { "code": ..., "message": "..." }}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw FirebaseAPIError(message: msg, code: err["code"] as? Int)
            }
            throw FirebaseAPIError(
                message: "HTTP \(http.statusCode)",
                code: http.statusCode
            )
        }
    }

    private func makeSession(from response: FirebaseAuthResponse, email: String) -> FirebaseSession {
        let expires = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? "3600") ?? 3600)
        let user = FirebaseUser(
            id: response.localId,
            email: email,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        return FirebaseSession(
            accessToken: response.idToken,
            refreshToken: response.refreshToken,
            expiresAt: expires,
            user: user
        )
    }

    private func ensureConfigured() throws {
        guard !FirebaseConfig.projectID.isEmpty, !FirebaseConfig.apiKey.isEmpty else {
            throw FirebaseAPIError(
                message: "Firebase isn't configured. Add API_FIREBASE_PROJECT_ID and API_FIREBASE_API_KEY in Secrets.xcconfig.",
                code: nil
            )
        }
    }

    private func ensureAuthenticated() throws {
        guard isSignedIn else {
            throw FirebaseAPIError(message: "Sign in to sync your data.", code: nil)
        }
    }
}

// MARK: - Firebase Auth response shape

private nonisolated struct FirebaseAuthResponse: Decodable {
    let idToken: String
    let refreshToken: String
    let localId: String
    let expiresIn: String?
    let email: String?
}
