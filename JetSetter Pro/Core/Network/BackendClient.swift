// File: Core/Network/BackendClient.swift
//
// HTTP client for the JetSetter booking backend (docs/BACKEND_API.md). This is
// the only code in the app that talks to a server the owner runs, and it is
// optional: with no `API_BACKEND_URL` the client reports `isConfigured == false`
// and every screen falls back to the vendor hand-off the app has always had.
//
// Design notes
//  * An `actor`: it owns mutable state (the cached device token and the
//    in-flight registration) that is used off the main actor.
//  * Anonymous device identity. The first authenticated call registers the
//    device (`POST /devices/register`) and keeps `device_id` + `token` in the
//    Keychain (after-first-unlock, this device only). A 401 re-registers ONCE
//    and replays the request. Caveat the owner should know: a re-registered
//    device is a new anonymous traveler, so bookings made under the old token
//    are no longer listed. That only happens when the server has forgotten the
//    token (account deleted, database reset), which is when they're gone anyway.
//  * Timeouts are per request: reads 15 s, search 40 s (Duffel can be slow),
//    checkout 60 s. Reads and searches retry transient failures with backoff;
//    a checkout and a cancel are NEVER retried, because a second POST could
//    charge or cancel twice. After an ambiguous checkout failure the caller
//    fetches the booking list instead (`BackendError.mayHaveCreatedBooking`).
//  * Ephemeral URLSession with no cache: responses carry names and tickets.
//  * Nothing here logs tokens, bodies or traveler details.

import Foundation

// MARK: - Credentials

nonisolated struct BackendDeviceCredentials: Codable, Sendable, Equatable {
    var deviceId: String
    var token: String
}

/// The device identity in the Keychain. Cleared by "Delete my data".
nonisolated enum BackendCredentialStore {

    static let service = "com.jetsetter.backend.device"

    static func load() -> BackendDeviceCredentials? {
        KeychainCredentials.load(BackendDeviceCredentials.self, service: service)
    }

    static func save(_ credentials: BackendDeviceCredentials) {
        try? KeychainCredentials.store(credentials, service: service,
                                       accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    static func clear() {
        KeychainCredentials.delete(service: service)
    }

    static var exists: Bool { load() != nil }
}

// MARK: - Configuration

nonisolated enum BackendConfiguration {

    /// The Info.plist key (mirrors `AppSecrets.Key.backendURL`; `AppSecrets` is
    /// main-actor isolated, and the client is not).
    static let infoPlistKey = "API_BACKEND_URL"

    /// The configured base URL, or nil when the build has none.
    static var baseURL: URL? {
        normalizedBaseURL(Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// Cleans a configured value into a base URL (no trailing slash, no
    /// `/api/v1` suffix). Returns nil for anything unusable, so a half-set
    /// build degrades to "not configured" instead of failing requests:
    ///  * empty, a placeholder, or an unexpanded `$(API_BACKEND_URL)`;
    ///  * the `https:` that an xcconfig leaves after truncating at `//`;
    ///  * a non-HTTPS URL, except localhost for local development.
    static func normalizedBaseURL(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("YOUR_") || text == "REPLACE_ME" || text.contains("$(") { return nil }
        if text.hasSuffix(":") { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api/v1") { text = String(text.dropLast("/api/v1".count)) }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", host == "localhost" || host == "127.0.0.1" { return url }
        return nil
    }

    /// `<base>/api/v1<path>` with the query attached. `path` starts with "/".
    static func endpointURL(base: URL, path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/api/v1" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }
}

// MARK: - Hand-off kinds

nonisolated enum BackendHandoffKind: String, Sendable, CaseIterable {
    case flights, hotels, cars
}

// MARK: - Client

actor BackendClient {

    static let shared = BackendClient()

    /// Nil when the build has no `API_BACKEND_URL`.
    nonisolated let baseURL: URL?

    /// True when this build can reach a backend at all.
    nonisolated var isConfigured: Bool { baseURL != nil }

    private let session: URLSession
    private let decoder = BackendCoding.makeDecoder()
    private let encoder = BackendCoding.makeEncoder()

    private var cachedCredentials: BackendDeviceCredentials?
    private var registrationTask: Task<BackendDeviceCredentials, Error>?

    init(baseURL: URL? = BackendConfiguration.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: Public API

    /// `GET /config` (no auth).
    func config() async throws -> BackendConfig {
        try await send(Request(method: "GET", path: "/config", authenticated: false, timeout: 10, retries: 1))
    }

    /// `POST /flights/search`. Sorted cheapest first by the server.
    func searchFlights(_ request: BackendSearchRequest) async throws -> BackendSearchResponse {
        try await send(Request(method: "POST", path: "/flights/search", body: try encode(request),
                               timeout: 40, retries: 1))
    }

    /// `GET /flights/offers/{id}`: the fresh offer, straight from Duffel.
    func offer(id: String) async throws -> BackendOffer {
        try await send(Request(method: "GET", path: "/flights/offers/\(Self.segment(id))", timeout: 20, retries: 1))
    }

    /// `POST /flights/offers/{id}/checkout`. Never retried.
    func checkout(offerID: String, request: BackendCheckoutRequest) async throws -> BackendCheckoutResponse {
        try await send(Request(method: "POST", path: "/flights/offers/\(Self.segment(offerID))/checkout",
                               body: try encode(request), timeout: 60, retries: 0))
    }

    /// `GET /bookings`, newest first, this device only.
    func bookings() async throws -> [BackendBooking] {
        let response: BackendBookingsResponse = try await send(
            Request(method: "GET", path: "/bookings", timeout: 20, retries: 2))
        return response.bookings
    }

    /// `GET /bookings/{id}`. `refresh` re-reads the order from Duffel first
    /// (schedule changes, tickets, baggage), which is slower.
    func booking(id: String, refresh: Bool = false) async throws -> BackendBooking {
        try await send(Request(method: "GET", path: "/bookings/\(Self.segment(id))",
                               query: refresh ? [URLQueryItem(name: "refresh", value: "true")] : [],
                               timeout: refresh ? 30 : 15, retries: 2))
    }

    /// `POST /bookings/{id}/cancel/quote`.
    func cancelQuote(bookingID: String) async throws -> BackendCancelQuote {
        try await send(Request(method: "POST", path: "/bookings/\(Self.segment(bookingID))/cancel/quote",
                               body: Data("{}".utf8), timeout: 30, retries: 0))
    }

    /// `POST /bookings/{id}/cancel/confirm`. Never retried.
    func cancelConfirm(bookingID: String, cancellationID: String) async throws -> BackendBooking {
        try await send(Request(method: "POST", path: "/bookings/\(Self.segment(bookingID))/cancel/confirm",
                               body: try encode(BackendCancelConfirmRequest(cancellationId: cancellationID)),
                               timeout: 45, retries: 0))
    }

    /// `GET /handoff/{kind}?…`: vendor links for searches that finish on the
    /// vendor's own site.
    func handoff(_ kind: BackendHandoffKind, query: [URLQueryItem]) async throws -> [BackendHandoffProvider] {
        let response: BackendHandoffResponse = try await send(
            Request(method: "GET", path: "/handoff/\(kind.rawValue)", query: query, timeout: 10, retries: 1))
        return response.providers
    }

    /// `DELETE /account`, then forget the device. Does nothing when this device
    /// never registered: there is nothing on the server to erase, and
    /// registering just to delete would create a record.
    func deleteAccount() async throws {
        guard isConfigured else { throw BackendError.notConfigured }
        guard cachedCredentials != nil || BackendCredentialStore.exists else { return }
        _ = try await perform(Request(method: "DELETE", path: "/account", timeout: 30, retries: 0))
        forgetDevice()
    }

    /// Drops the cached and stored device identity without a network call.
    func forgetDevice() {
        cachedCredentials = nil
        registrationTask = nil
        BackendCredentialStore.clear()
    }

    /// True once this device has registered.
    var isRegistered: Bool { cachedCredentials != nil || BackendCredentialStore.exists }

    // MARK: Request plumbing

    private struct Request: Sendable {
        var method: String
        var path: String
        var query: [URLQueryItem] = []
        var body: Data? = nil
        var authenticated = true
        var timeout: TimeInterval = 20
        /// Extra attempts after the first, for transient failures only.
        var retries = 0
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try encoder.encode(value) } catch { throw BackendError.invalidResponse }
    }

    /// Percent-encodes one path segment, so an id can never add a component.
    private static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func send<T: Decodable>(_ request: Request) async throws -> T {
        let (data, _) = try await perform(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }

    /// Runs a request through auth, the single 401 re-registration and the
    /// retry policy; returns the body of a 2xx.
    private func perform(_ request: Request) async throws -> (Data, HTTPURLResponse) {
        guard let baseURL else { throw BackendError.notConfigured }
        var attempt = 0
        var reRegistered = false

        while true {
            attempt += 1
            do {
                var token: String?
                if request.authenticated { token = try await credentials().token }
                let urlRequest = try makeURLRequest(request, base: baseURL, token: token)
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }

                if (200...299).contains(http.statusCode) { return (data, http) }

                let error = BackendError.make(status: http.statusCode, body: data,
                                              retryAfter: Self.retryAfter(http))
                if case .notAuthenticated = error, request.authenticated, !reRegistered {
                    reRegistered = true
                    forgetDevice()
                    continue
                }
                if attempt <= request.retries, let delay = Self.retryDelay(for: error, attempt: attempt) {
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw error
            } catch let error as BackendError {
                throw error
            } catch let urlError as URLError {
                if urlError.code == .cancelled { throw CancellationError() }
                if attempt <= request.retries, Self.isTransient(urlError) {
                    try await Task.sleep(for: .seconds(Self.backoff(attempt)))
                    continue
                }
                throw BackendError.make(urlError: urlError)
            }
        }
    }

    private func makeURLRequest(_ request: Request, base: URL, token: String?) throws -> URLRequest {
        guard let url = BackendConfiguration.endpointURL(base: base, path: request.path, query: request.query) else {
            throw BackendError.notConfigured
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            urlRequest.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    // MARK: Device registration

    /// The stored identity, registering the device the first time.
    private func credentials() async throws -> BackendDeviceCredentials {
        if let cachedCredentials { return cachedCredentials }
        if let stored = BackendCredentialStore.load() {
            cachedCredentials = stored
            return stored
        }
        return try await register()
    }

    /// One registration at a time: concurrent first calls (a sync and a config
    /// refresh at launch) share a single `POST /devices/register`.
    private func register() async throws -> BackendDeviceCredentials {
        if let registrationTask { return try await registrationTask.value }
        let task = Task { try await self.performRegistration() }
        registrationTask = task
        defer { registrationTask = nil }
        return try await task.value
    }

    private func performRegistration() async throws -> BackendDeviceCredentials {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let body = try encode(BackendRegisterRequest(appVersion: version, platform: "ios"))
        let (data, _) = try await perform(Request(method: "POST", path: "/devices/register", body: body,
                                                  authenticated: false, timeout: 15, retries: 1))
        let registration: BackendDeviceRegistration
        do {
            registration = try decoder.decode(BackendDeviceRegistration.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
        let credentials = BackendDeviceCredentials(deviceId: registration.deviceId, token: registration.token)
        BackendCredentialStore.save(credentials)
        cachedCredentials = credentials
        return credentials
    }

    // MARK: Retry policy

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    /// Seconds to wait before retrying `error`, or nil when it isn't worth
    /// retrying. A throttle is only waited out when the wait is short.
    private static func retryDelay(for error: BackendError, attempt: Int) -> TimeInterval? {
        switch error {
        case .upstream:
            return backoff(attempt)
        case .throttled(_, let retryAfter):
            guard let retryAfter, retryAfter <= 5 else { return nil }
            return retryAfter
        case .server(let status, _, _) where status >= 500:
            return backoff(attempt)
        default:
            return nil
        }
    }

    private static func backoff(_ attempt: Int) -> TimeInterval {
        min(0.5 * pow(2, Double(attempt - 1)), 4)
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        return max(seconds, 0)
    }
}
