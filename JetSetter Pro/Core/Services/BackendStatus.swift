// File: Core/Services/BackendStatus.swift
//
// What the app currently knows about the booking backend: whether it is
// configured in this build, and the last `GET /config` answer (flights on or
// off, test mode, legal and support links). Views read it to decide between the
// in-app flight booking flow and the vendor hand-off the app has always had.
//
// The last good config is kept in UserDefaults (a per-device convenience, not a
// record), so a traveler who opens Book in airplane mode still sees the screen
// they used last, with an offline message, rather than a different one.
//
// Before the first successful fetch `flightsEnabled` is false, so a fresh
// install, a build with no backend, or a server that is down all behave
// exactly like the pre-backend app: Kayak hand-off.

import Foundation

@MainActor
@Observable
final class BackendStatus {

    static let shared = BackendStatus()

    private static let cacheKey = "backend_config_v1"
    /// Config is cheap, but there's no reason to fetch it more than this often.
    private static let refreshInterval: TimeInterval = 10 * 60

    /// Legal pages used before the server's config has been fetched (and when
    /// the server omits one). These are the links Settings has always shown.
    static let fallbackPrivacyURL = "https://jetsetterpro.app/privacy"
    static let fallbackTermsURL   = "https://jetsetterpro.app/terms"

    private(set) var config: BackendConfig?
    private(set) var lastFetched: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            config = try? JSONDecoder().decode(BackendConfig.self, from: data)
        }
    }

    // MARK: - Reading

    /// True when this build has a backend URL.
    var isConfigured: Bool { BackendClient.shared.isConfigured }

    /// In-app flight search and booking is available.
    var flightsEnabled: Bool { isConfigured && (config?.flightsEnabled ?? false) }

    /// The server runs on a Duffel test token: bookings are fake and free.
    var isTestMode: Bool { isConfigured && (config?.testMode ?? false) }

    var privacyURL: URL? {
        Self.webURL(config?.privacyUrl) ?? URL(string: Self.fallbackPrivacyURL)
    }

    var termsURL: URL? {
        Self.webURL(config?.termsUrl) ?? URL(string: Self.fallbackTermsURL)
    }

    /// Nil when the server gave no support page; Settings then shows nothing
    /// rather than a guessed address.
    var supportURL: URL? {
        if let page = Self.webURL(config?.supportUrl) { return page }
        if let email = config?.supportEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return URL(string: "mailto:\(email)")
        }
        return nil
    }

    private static func webURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), BackendCoding.isWebURL(url) else { return nil }
        return url
    }

    // MARK: - Refreshing

    /// Fetches `GET /config`. A failure keeps the last known config; this never
    /// throws and never blanks a screen.
    func refresh(force: Bool = false) async {
        guard isConfigured else { return }
        if !force, let lastFetched, Date().timeIntervalSince(lastFetched) < Self.refreshInterval { return }
        do {
            let fresh = try await BackendClient.shared.config()
            config = fresh
            lastFetched = Date()
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } catch {
            // Offline, or the server is down: keep what we knew.
        }
    }

    /// Forgets the cached config (Delete my data).
    func reset() {
        config = nil
        lastFetched = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }
}
