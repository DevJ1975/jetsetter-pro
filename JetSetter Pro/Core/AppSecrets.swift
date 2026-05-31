// File: Core/AppSecrets.swift
//
// Centralized, runtime-loaded configuration for all third-party credentials and
// service endpoints.
//
// Values are read from `Secrets.plist`, which is bundled into the app at build
// time (the file-system-synchronized project automatically includes any file
// placed under "JetSetter Pro/") but kept OUT of version control via .gitignore.
//
// ── Setup ─────────────────────────────────────────────────────────────────
//   1. Copy "Secrets.example.plist" → "Secrets.plist" (same folder).
//   2. Fill in your real values.
//   3. "Secrets.plist" is git-ignored, so your keys never get committed.
//
// In demo mode (`MockDataService.isEnabled == true`) no network calls are made,
// so a missing `Secrets.plist` is harmless — every accessor falls back to an
// empty string and the build still succeeds.
//
// SECURITY NOTE: Only keys that are safe to ship in a client binary belong here
// (e.g. the Supabase anon key, which is protected by Row-Level Security). Truly
// secret server credentials — like the Anthropic API key — must NOT live in the
// app at all; they belong in a server-side proxy (see supabase/functions).

import Foundation

enum AppSecrets {

    /// Backing dictionary, loaded once from `Secrets.plist`.
    /// Empty if the file is absent (e.g. a fresh checkout running in demo mode).
    private static let values: [String: String] = {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: String]
        else {
            return [:]
        }
        return dict
    }()

    /// Returns the trimmed value for `key`. Unfilled template placeholders
    /// (anything starting with "YOUR_") are treated as empty so callers can
    /// reliably check `isEmpty` to decide whether a credential is configured.
    private static func value(_ key: String) -> String {
        let raw = (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("YOUR_") ? "" : raw
    }

    // MARK: - Supabase

    static var supabaseURL: String { value("SUPABASE_URL") }
    static var supabaseAnonKey: String { value("SUPABASE_ANON_KEY") }

    // MARK: - Claude proxy (Supabase Edge Function)

    /// Full URL of the server-side Claude proxy. The Anthropic API key lives in
    /// the edge function's environment — never in this app. If not set
    /// explicitly, it is derived from `SUPABASE_URL`.
    static var claudeProxyURL: String {
        let explicit = value("CLAUDE_PROXY_URL")
        if !explicit.isEmpty { return explicit }
        let base = supabaseURL
        return base.isEmpty ? "" : "\(base)/functions/v1/claude-proxy"
    }

    // MARK: - Third-party API keys
    //
    // NOTE: Keys that grant access to paid/sensitive services should ideally be
    // proxied server-side too (see the Claude proxy as the reference pattern).
    // They are surfaced here for now so they are at least out of source control.

    static var flightAware: String { value("FLIGHTAWARE_API_KEY") }
    static var expediaClientID: String { value("EXPEDIA_CLIENT_ID") }
    static var expediaClientSecret: String { value("EXPEDIA_CLIENT_SECRET") }
    static var uberServerToken: String { value("UBER_SERVER_TOKEN") }
    static var lyftClientID: String { value("LYFT_CLIENT_ID") }
    static var lyftClientSecret: String { value("LYFT_CLIENT_SECRET") }
    static var googleVision: String { value("GOOGLE_VISION_API_KEY") }
    static var sitaWorldTracer: String { value("SITA_WORLDTRACER_PARTNER_KEY") }
    static var enterpriseApiKey: String { value("ENTERPRISE_API_KEY") }
    static var hertzApiKey: String { value("HERTZ_API_KEY") }
    static var nationalApiKey: String { value("NATIONAL_API_KEY") }

    // MARK: - Flight data & rebooking

    /// FlightAware AeroAPI key used by the background disruption monitor.
    static var flightAwareAeroAPI: String { value("FLIGHTAWARE_AEROAPI_KEY") }

    static var amadeusClientID: String { value("AMADEUS_CLIENT_ID") }
    static var amadeusClientSecret: String { value("AMADEUS_CLIENT_SECRET") }
    static var duffelAPIToken: String { value("DUFFEL_API_TOKEN") }
}
