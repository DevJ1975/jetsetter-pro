// File: Core/Services/SupabaseService.swift
//
// Supabase backend integration using the public REST + GoTrue APIs — no
// `supabase-swift` SDK required. This mirrors the previous `FirebaseService`
// pattern (a hand-rolled REST actor) to keep the SPM dependency surface minimal.
// Supabase replaces Firebase as the shared cross-platform data + auth backend.
// See IOS_PARITY_NOTES.md §1–3.
//
// AUTH:  {url}/auth/v1/*   (GoTrue — anonymous-first, email upgrade links the uid)
// DATA:  {url}/rest/v1/*   (PostgREST — RLS keys off auth.uid())
//
// Only `public.trips` and `public.expenses` are part of the shared schema-v1
// contract, so those sync to Supabase. Wallet items, packing lists, and
// disruption events have no schema-v1 table and are persisted device-locally
// here (intentional divergence — cross-device sync for them awaits a schema bump).

import Foundation

// MARK: - Configuration

private enum SupabaseConfig {
    // `nonisolated` so the SupabaseService actor can read these without an
    // actor hop (the project defaults to @MainActor isolation).
    nonisolated static let baseURL: String = readSupabaseSecret("API_SUPABASE_URL")
    nonisolated static let anonKey: String = readSupabaseSecret("API_SUPABASE_ANON_KEY")

    nonisolated static var authBase: String { "\(baseURL)/auth/v1" }
    nonisolated static var restBase: String { "\(baseURL)/rest/v1" }
}

/// Bundle-level secret reader — mirrors `AppSecrets.value(for:)` but is
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
// `nonisolated` so the synthesized Codable conformances can be used from inside
// the actor and from nonisolated decoder callbacks.

nonisolated struct SupabaseUser: Codable, Identifiable {
    let id: String              // Supabase auth.uid()
    let email: String?
    let isAnonymous: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email
        case isAnonymous = "is_anonymous"
    }
}

nonisolated struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: SupabaseUser
}

nonisolated struct SupabaseAPIError: Codable, LocalizedError {
    let message: String
    let code: Int?

    var errorDescription: String? { message }
}

// MARK: - Wire rows (exact schema-v1 column shapes, IOS_PARITY_NOTES.md §2)

/// One `public.trips` row. Top-level columns are snake_case; the JSON keys
/// *inside* `items`/`packing_list` stay camelCase (nested model Codable).
/// `user_id` is omitted — Postgres defaults it to `auth.uid()`.
private nonisolated struct TripRow: Codable {
    let id: String
    let name: String
    let destination: String
    let start_date: String        // ISO-8601 date-only, e.g. "2026-07-14"
    let end_date: String
    let items: [ItineraryItem]     // native jsonb array
    let packing_list: [PackingItem]
}

/// One `public.expenses` row. iOS-only fields (receiptText, mileageDistance)
/// are not part of schema v1 and are dropped on the wire.
private nonisolated struct ExpenseRow: Codable {
    let id: String
    let amount: Double
    let currency: String
    let category: ExpenseCategory  // encodes UPPERCASE ("FOOD", …)
    let merchant: String
    let date: String               // ISO-8601 date-only
    let notes: String?
}

// MARK: - Service

actor SupabaseService {

    static let shared = SupabaseService()
    private init() {}

    // Coders for jsonb bodies: ISO-8601 for nested dates, default (camelCase) keys.
    private let rowEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let rowDecoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    /// Date-only formatter for the `start_date` / `end_date` / `date` text columns.
    private nonisolated static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
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

    /// Anonymous-first sign-in (IOS_PARITY_NOTES.md §3). Reuses an existing
    /// session when present so the same uid is kept across launches.
    func ensureSignedIn() async throws {
        if isSignedIn { return }
        try await signInAnonymously()
    }

    func signInAnonymously() async throws {
        try ensureConfigured()
        let url = URL(string: "\(SupabaseConfig.authBase)/signup")!
        let body: [String: Any] = ["data": [String: String](),
                                    "gotrue_meta_security": [String: String]()]
        let response: AuthResponse = try await postAuth(url: url, body: body)
        cachedSession = response.session
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        try ensureConfigured()
        // If already anonymous, upgrade (link) the existing uid; else fresh signup.
        if isSignedIn {
            try await updateUser(email: email, password: password)
            return cachedSession!
        }
        let url = URL(string: "\(SupabaseConfig.authBase)/signup")!
        let response: AuthResponse = try await postAuth(url: url,
                                                        body: ["email": email, "password": password])
        let session = response.session
        cachedSession = session
        return session
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        try ensureConfigured()
        let url = URL(string: "\(SupabaseConfig.authBase)/token?grant_type=password")!
        let response: AuthResponse = try await postAuth(url: url,
                                                        body: ["email": email, "password": password])
        let session = response.session
        cachedSession = session
        return session
    }

    func signOut() async {
        cachedSession = nil
    }

    func refreshSession() async throws {
        guard let refresh = cachedSession?.refreshToken else {
            throw SupabaseAPIError(message: "No active session", code: nil)
        }
        let url = URL(string: "\(SupabaseConfig.authBase)/token?grant_type=refresh_token")!
        let response: AuthResponse = try await postAuth(url: url, body: ["refresh_token": refresh])
        cachedSession = response.session
    }

    /// Links an email/password to the current (anonymous) user, preserving the uid.
    private func updateUser(email: String, password: String) async throws {
        let url = URL(string: "\(SupabaseConfig.authBase)/user")!
        _ = try await sendJSON(url: url, method: "PUT",
                               body: ["email": email, "password": password], authenticated: true)
    }

    // MARK: - Account deletion (App Store Guideline 5.1.1(v))

    /// Deletes the user's synced rows (RLS-scoped) and clears the local session.
    /// NOTE: GoTrue has no self-serve auth-account delete over the anon key; a
    /// true account delete needs a server-side function. Data + session are
    /// wiped here so nothing lingers on-device or in the user's rows.
    func deleteAccount() async throws {
        try ensureAuthenticated()
        try? await deleteAllRows(table: "trips")
        try? await deleteAllRows(table: "expenses")
        clearLocalStores()
        cachedSession = nil
    }

    private func deleteAllRows(table: String) async throws {
        guard let uid = currentUser?.id else { return }
        // RLS already restricts to the caller, but scope explicitly for safety.
        let url = URL(string: "\(SupabaseConfig.restBase)/\(table)?user_id=eq.\(uid)")!
        _ = try await sendJSON(url: url, method: "DELETE", body: nil, authenticated: true)
    }

    // MARK: - Trips (shared schema-v1, remote)

    func syncTrips(_ trips: [Trip]) async throws {
        try ensureAuthenticated()
        guard !trips.isEmpty else { return }
        let rows = trips.map(Self.row(from:))
        let url = URL(string: "\(SupabaseConfig.restBase)/trips")!
        let payload = try rowEncoder.encode(rows)
        _ = try await sendRaw(url: url, method: "POST", jsonBody: payload,
                              authenticated: true, upsert: true)
    }

    func fetchTrips() async throws -> [Trip] {
        try ensureAuthenticated()
        let url = URL(string: "\(SupabaseConfig.restBase)/trips?select=*")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        let rows = try rowDecoder.decode([TripRow].self, from: data)
        return rows.compactMap(Self.trip(from:))
    }

    // MARK: - Expenses (shared schema-v1, remote)

    func syncExpenses(_ expenses: [Expense]) async throws {
        try ensureAuthenticated()
        guard !expenses.isEmpty else { return }
        let rows = expenses.map(Self.row(from:))
        let url = URL(string: "\(SupabaseConfig.restBase)/expenses")!
        let payload = try rowEncoder.encode(rows)
        _ = try await sendRaw(url: url, method: "POST", jsonBody: payload,
                              authenticated: true, upsert: true)
    }

    func fetchExpenses() async throws -> [Expense] {
        try ensureAuthenticated()
        let url = URL(string: "\(SupabaseConfig.restBase)/expenses?select=*")!
        let data = try await sendJSON(url: url, method: "GET", body: nil, authenticated: true)
        let rows = try rowDecoder.decode([ExpenseRow].self, from: data)
        return rows.map(Self.expense(from:))
    }

    // MARK: - Row <-> model mapping

    private nonisolated static func row(from trip: Trip) -> TripRow {
        TripRow(
            id: trip.id.uuidString,
            name: trip.name,
            destination: trip.destination,
            start_date: dateOnly.string(from: trip.startDate),
            end_date: dateOnly.string(from: trip.endDate),
            items: trip.items,
            packing_list: trip.packingList
        )
    }

    private nonisolated static func trip(from row: TripRow) -> Trip? {
        guard let id = UUID(uuidString: row.id),
              let start = dateOnly.date(from: row.start_date),
              let end = dateOnly.date(from: row.end_date) else { return nil }
        return Trip(id: id, name: row.name, destination: row.destination,
                    startDate: start, endDate: end,
                    items: row.items, packingList: row.packing_list)
    }

    private nonisolated static func row(from expense: Expense) -> ExpenseRow {
        ExpenseRow(
            id: expense.id.uuidString,
            amount: expense.amount,
            currency: expense.currency,
            category: expense.category,
            merchant: expense.merchant,
            date: dateOnly.string(from: expense.date),
            notes: expense.notes
        )
    }

    private nonisolated static func expense(from row: ExpenseRow) -> Expense {
        Expense(
            id: UUID(uuidString: row.id) ?? UUID(),
            amount: row.amount,
            currency: row.currency,
            category: row.category,
            merchant: row.merchant,
            date: dateOnly.date(from: row.date) ?? Date(),
            notes: row.notes
        )
    }

    // MARK: - Wallet / Packing / Disruption (device-local; no schema-v1 table)

    private static let walletKey        = "supabase_local_wallet_items"
    private static let packingPrefix    = "supabase_local_packing_"
    private static let disruptionKey    = "supabase_local_disruption_events"
    private static let travelSignalsKey = "supabase_local_travel_signals"

    func fetchWalletItems() async throws -> [WalletItem] {
        loadLocal([WalletItem].self, key: Self.walletKey) ?? []
    }

    func upsertWalletItem(_ item: WalletItem) async throws {
        var items = (loadLocal([WalletItem].self, key: Self.walletKey) ?? [])
        items.removeAll { $0.id == item.id }
        items.append(item)
        saveLocal(items, key: Self.walletKey)
    }

    func deleteWalletItem(id: UUID) async throws {
        var items = (loadLocal([WalletItem].self, key: Self.walletKey) ?? [])
        items.removeAll { $0.id == id }
        saveLocal(items, key: Self.walletKey)
    }

    func fetchPackingList(tripId: UUID) async throws -> PackingListResult? {
        loadLocal(PackingListResult.self, key: Self.packingPrefix + tripId.uuidString)
    }

    func upsertPackingList(_ list: PackingListResult) async throws {
        saveLocal(list, key: Self.packingPrefix + list.tripId.uuidString)
    }

    func fetchDisruptionEvents() async throws -> [DisruptionEvent] {
        loadLocal([DisruptionEvent].self, key: Self.disruptionKey) ?? []
    }

    func upsertDisruptionEvent(_ event: DisruptionEvent) async throws {
        var events = (loadLocal([DisruptionEvent].self, key: Self.disruptionKey) ?? [])
        events.removeAll { $0.id == event.id }
        events.append(event)
        saveLocal(events, key: Self.disruptionKey)
    }

    // MARK: - Travel signals (IRIS learning layer)

    /// Upserts the given learning signals. Consent is enforced by the caller
    /// (TravelProfileStore only calls this when learning is enabled).
    func syncTravelSignals(_ signals: [TravelSignal]) async throws {
        var all = loadLocal([TravelSignal].self, key: Self.travelSignalsKey) ?? []
        for signal in signals {
            all.removeAll { $0.id == signal.id }
            all.append(signal)
        }
        saveLocal(all, key: Self.travelSignalsKey)
    }

    func fetchTravelSignals() async throws -> [TravelSignal] {
        loadLocal([TravelSignal].self, key: Self.travelSignalsKey) ?? []
    }

    private func loadLocal<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? rowDecoder.decode(T.self, from: data)
    }

    private func saveLocal<T: Encodable>(_ value: T, key: String) {
        if let data = try? rowEncoder.encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func clearLocalStores() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.walletKey)
        d.removeObject(forKey: Self.disruptionKey)
        d.removeObject(forKey: Self.travelSignalsKey)
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(Self.packingPrefix) {
            d.removeObject(forKey: key)
        }
    }

    // MARK: - HTTP helpers

    /// GoTrue auth POST — carries only the `apikey` header (no bearer).
    private func postAuth(url: URL, body: [String: Any]) async throws -> AuthResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try AuthResponse.decode(data)
    }

    /// PostgREST / GoTrue request with a JSON dictionary (or nil) body.
    @discardableResult
    private func sendJSON(url: URL, method: String,
                          body: [String: Any]?, authenticated: Bool) async throws -> Data {
        let jsonBody = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await sendRaw(url: url, method: method, jsonBody: jsonBody,
                                 authenticated: authenticated, upsert: false)
    }

    /// PostgREST request with a pre-encoded JSON body.
    @discardableResult
    private func sendRaw(url: URL, method: String, jsonBody: Data?,
                         authenticated: Bool, upsert: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        if upsert {
            request.setValue("resolution=merge-duplicates,return=minimal",
                             forHTTPHeaderField: "Prefer")
        }
        request.httpBody = jsonBody
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError(message: "Invalid server response", code: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            // Supabase errors look like { "message": "...", "error": "...", "msg": "..." }.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let msg = (json["message"] ?? json["msg"] ?? json["error_description"]
                           ?? json["error"]) as? String
                throw SupabaseAPIError(message: msg ?? "HTTP \(http.statusCode)", code: http.statusCode)
            }
            throw SupabaseAPIError(message: "HTTP \(http.statusCode)", code: http.statusCode)
        }
    }

    private func ensureConfigured() throws {
        guard !SupabaseConfig.baseURL.isEmpty, !SupabaseConfig.anonKey.isEmpty else {
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

// MARK: - GoTrue auth response shape

private nonisolated struct AuthResponse {
    let session: SupabaseSession

    /// Parses the `{ access_token, refresh_token, expires_in, user }` payload.
    static func decode(_ data: Data) throws -> AuthResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseAPIError(message: "Malformed auth response", code: nil)
        }
        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let userDict = json["user"] as? [String: Any],
              let uid = userDict["id"] as? String else {
            throw SupabaseAPIError(message: "Auth response missing session fields", code: nil)
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let email = userDict["email"] as? String
        let isAnon = userDict["is_anonymous"] as? Bool
        let user = SupabaseUser(id: uid, email: (email?.isEmpty == true ? nil : email),
                                isAnonymous: isAnon)
        let session = SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            user: user
        )
        return AuthResponse(session: session)
    }
}
