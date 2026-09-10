// File: Core/Services/FlightStatusService.swift
//
// The single FlightAware AeroAPI status client for the whole app. Before this
// existed there were two: FlightTrackerViewModel routed through Endpoints +
// APIClient, while DisruptionMonitorService hand-rolled its own baseURL, API-key
// read, and JSONDecoder. Two clients against one API drift apart (different
// decoders decode the same payload differently — the exact class of bug the
// audit documents), so gate/time/status parsing must live in ONE place that the
// foreground tracker, the background disruption monitor, and IRIS all call.
//
// `@MainActor` because `Flight` / `FlightSearchResponse` inherit MainActor
// isolation from the project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
// default. Their `Codable` inits are nonisolated protocol witnesses (so APIClient
// can decode them off the main actor), but reading their properties is
// MainActor-isolated — keeping this service on the main actor lets callers use
// the returned `Flight` immediately. The two existing call sites already interop
// with these types exactly this way (the VM is @MainActor; the monitor/IRIS hop
// to MainActor), so nothing about their isolation changes.

import Foundation

@MainActor
enum FlightStatusService {

    /// Every flight instance AeroAPI returns for an ident. "AA100" resolves to
    /// an array of instances across dates; an empty array is a valid "no
    /// matches" result, not an error. Throws `APIError` (incl. `.notConfigured`
    /// when the AeroAPI key is missing) so callers surface honest failures
    /// instead of silently persisting nothing.
    static func flights(forIdent ident: String) async throws -> [Flight] {
        guard let url = Endpoints.FlightAware.flightStatus(ident: ident) else {
            throw APIError.invalidURL
        }
        let response: FlightSearchResponse = try await APIClient.shared.get(
            url: url,
            headers: Endpoints.FlightAware.headers
        )
        return response.flights
    }

    /// The single most-relevant instance for an ident — the first result AeroAPI
    /// returns. Throws `APIError.requestFailed(statusCode: 404)` when the ident
    /// resolves to no instances, so callers can distinguish "not found" from a
    /// transport/credential failure.
    static func status(forIdent ident: String) async throws -> Flight {
        guard let first = try await flights(forIdent: ident).first else {
            throw APIError.requestFailed(statusCode: 404)
        }
        return first
    }

    /// Re-fetches a specific flight *instance* by `faFlightId`, falling back to
    /// the first result if that instance is no longer returned. Best-effort:
    /// returns nil on any failure so callers keep showing their last-known
    /// snapshot rather than blanking the UI.
    static func status(forIdent ident: String, matching faFlightId: String) async -> Flight? {
        guard let flights = try? await flights(forIdent: ident) else { return nil }
        return flights.first { $0.faFlightId == faFlightId } ?? flights.first
    }

    /// Live position track for an airborne flight. Throws so the caller can
    /// distinguish "no new samples" from a failure and keep the last-known trail.
    static func positions(forIdent ident: String) async throws -> [FlightPosition] {
        guard let url = Endpoints.FlightAware.flightTrack(ident: ident) else {
            throw APIError.invalidURL
        }
        let response: FlightTrackResponse = try await APIClient.shared.get(
            url: url,
            headers: Endpoints.FlightAware.headers
        )
        return response.positions
    }
}
