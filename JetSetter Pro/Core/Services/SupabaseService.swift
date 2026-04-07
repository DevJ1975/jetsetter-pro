// File: Core/Services/SupabaseService.swift
//
// Supabase integration using raw REST — no third-party SDK required.
//
// SETUP:
// 1. Create a project at https://supabase.com
// 2. Go to Settings → API and copy your Project URL and anon key below.
// 3. Create the following tables in the Supabase SQL editor:
//
//    CREATE TABLE expenses (
//      id uuid PRIMARY KEY,
//      user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
//      title text, amount float8, category text,
//      date timestamptz, receipt_text text, created_at timestamptz DEFAULT now()
//    );
//    ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
//    CREATE POLICY "user_expenses" ON expenses FOR ALL USING (auth.uid() = user_id);
//
//    CREATE TABLE trips (
//      id uuid PRIMARY KEY,
//      user_id uuid REFERENCES auth.users NOT NULL DEFAULT auth.uid(),
//      name text, destination text, start_date timestamptz, end_date timestamptz,
//      items jsonb, created_at timestamptz DEFAULT now()
//    );
//    ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
//    CREATE POLICY "user_trips" ON trips FOR ALL USING (auth.uid() = user_id);

import Foundation

// MARK: - Supabase Configuration

private enum SupabaseConfig {
    // TODO: Replace with your Supabase project values
    static let projectURL = "https://YOUR_PROJECT_ID.supabase.co"
    static let anonKey    = "YOUR_SUPABASE_ANON_KEY"
}

// MARK: - Auth Models

struct SupabaseUser: Codable, Identifiable {
    let id: String
    let email: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
    }
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
        case tokenType    = "token_type"
        case user
    }

    var expiresAt: Date { Date().addingTimeInterval(Double(expiresIn)) }
}

struct SupabaseAPIError: Codable, LocalizedError {
    let message: String
    let error: String?
    var errorDescription: String? { message }
}

// MARK: - Supabase Service

actor SupabaseService {

    static let shared = SupabaseService()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Session Management

    private var cachedSession: SupabaseSession? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "supabase_session"),
                  let session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
            else { return nil }
            return session
        }
        set {
            if let s = newValue, let data = try? JSONEncoder().encode(s) {
                UserDefaults.standard.set(data, forKey: "supabase_session")
            } else {
                UserDefaults.standard.removeObject(forKey: "supabase_session")
            }
        }
    }

    var currentUser: SupabaseUser? { cachedSession?.user }
    var isSignedIn: Bool { cachedSession != nil }
    var accessToken: String? { cachedSession?.accessToken }

    // MARK: - Authentication

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let body = ["email": email, "password": password]
        let session: SupabaseSession = try await post(path: "/auth/v1/signup", body: body)
        cachedSession = session
        return session
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body = ["email": email, "password": password, "grant_type": "password"]
        let session: SupabaseSession = try await post(path: "/auth/v1/token?grant_type=password", body: body)
        cachedSession = session
        return session
    }

    func signOut() async {
        if let token = accessToken {
            try? await post(path: "/auth/v1/logout", body: EmptyBody(), token: token) as EmptyResponse
        }
        cachedSession = nil
    }

    func refreshSession() async throws {
        guard let refresh = cachedSession?.refreshToken else {
            throw SupabaseAPIError(message: "No active session", error: "no_session")
        }
        let body = ["refresh_token": refresh, "grant_type": "refresh_token"]
        let session: SupabaseSession = try await post(path: "/auth/v1/token?grant_type=refresh_token", body: body)
        cachedSession = session
    }

    // MARK: - Data Sync

    /// Upserts local expenses to the `expenses` table.
    /// Each expense must have a stable `id` (UUID) for upsert deduplication.
    func syncExpenses(_ expenses: [Expense]) async throws {
        guard let token = accessToken else {
            throw SupabaseAPIError(message: "Sign in to sync your expenses.", error: "unauthenticated")
        }
        // Convert to dictionaries for the REST API
        let payload = try expenses.map { expense -> [String: Any] in
            let data = try encoder.encode(expense)
            return (try JSONSerialization.jsonObject(with: data)) as! [String: Any]
        }
        try await upsert(table: "expenses", rows: payload, token: token)
    }

    func fetchExpenses() async throws -> [Expense] {
        guard let token = accessToken else {
            throw SupabaseAPIError(message: "Sign in to fetch your expenses.", error: "unauthenticated")
        }
        return try await select(table: "expenses", token: token)
    }

    /// Upserts local trips to the `trips` table.
    func syncTrips(_ trips: [Trip]) async throws {
        guard let token = accessToken else {
            throw SupabaseAPIError(message: "Sign in to sync your trips.", error: "unauthenticated")
        }
        let payload = try trips.map { trip -> [String: Any] in
            let data = try encoder.encode(trip)
            return (try JSONSerialization.jsonObject(with: data)) as! [String: Any]
        }
        try await upsert(table: "trips", rows: payload, token: token)
    }

    func fetchTrips() async throws -> [Trip] {
        guard let token = accessToken else {
            throw SupabaseAPIError(message: "Sign in to fetch your trips.", error: "unauthenticated")
        }
        return try await select(table: "trips", token: token)
    }

    // MARK: - REST Helpers

    @discardableResult
    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        token: String? = nil
    ) async throws -> Response {
        guard let url = URL(string: SupabaseConfig.projectURL + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func upsert(table: String, rows: [[String: Any]], token: String) async throws {
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: rows)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response, data: data)
    }

    private func select<T: Decodable>(table: String, token: String, filter: String = "*") async throws -> [T] {
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)?select=\(filter)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response, data: data)
        return try decoder.decode([T].self, from: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? decoder.decode(SupabaseAPIError.self, from: data) { throw err }
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Helpers

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}
