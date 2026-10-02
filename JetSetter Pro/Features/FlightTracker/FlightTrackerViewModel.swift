// File: Features/FlightTracker/FlightTrackerViewModel.swift
//
// Flight Tracker state: search a flight number, show FlightAware's status, and
// keep it useful when the network isn't.
//
// The defect this file fixes: `fetch` used to clear `flights` before every
// request, so a refresh at a gate with bad Wi-Fi replaced the gate and times
// the traveler had just been looking at with an error screen. Now:
//   • results stay on screen through a failed refresh, and a banner says what
//     went wrong, with Retry;
//   • every successful result is saved per flight (`FlightStatusCache`), so
//     searching a flight offline shows its last status at once;
//   • `showsLiveBadge` hides "LIVE" once the data is more than 10 minutes old
//     or came from the saved copy, and "Updated 12 min ago" says how old it is.
//
// Without a FlightAware key the screen still shows one plain sentence
// (`noKeyMessage`) and no Retry, as before.

import Foundation
import CoreLocation

// MARK: - FlightTrackerViewModel

@MainActor
@Observable
final class FlightTrackerViewModel {

    /// Fetches the flights for a flight number. Injectable so tests can make a
    /// refresh fail without a network.
    typealias FlightFetcher = @MainActor (String) async throws -> [Flight]

    // MARK: - Observable State

    var flights: [Flight] = []
    var isLoading: Bool = false
    /// Shown as a banner over results when there are some, or full screen when
    /// there aren't.
    var errorMessage: String? = nil
    var searchText: String = ""

    /// When the flights on screen were fetched: just now for a live result,
    /// or the saved time for a cached one. Drives "Updated X ago".
    var lastUpdated: Date? = nil

    /// True when the flights on screen aren't from the latest attempt: they
    /// were loaded from the saved copy, or the last refresh failed.
    private(set) var isShowingSavedResults = false

    /// True when this build has no FlightAware key. The screen then shows
    /// `noKeyMessage` without a Retry button, since retrying can't help.
    private(set) var isLiveStatusUnavailable = false

    /// The flight number whose results are on screen (or being fetched).
    private(set) var currentIdent: String = ""

    /// The most recent live position of the tracked flight (drives the moving
    /// plane on the map). Nil until the first position sample arrives.
    var livePosition: FlightPosition? = nil

    /// The flown path so far — rendered as a solid trail behind the planned route.
    var track: [FlightPosition] = []

    // MARK: - Private State

    /// The last flight number fetched successfully; repeating that exact
    /// search is a no-op (Refresh and Retry bypass this).
    private var lastSearchedIdent: String = ""

    /// Background loop that refreshes `livePosition`/`track` while a detail
    /// screen for an airborne flight is on screen.
    private var livePollingTask: Task<Void, Never>?

    private let cache: FlightStatusCache
    private let isLiveStatusConfigured: @MainActor () -> Bool
    private let fetchFlights: FlightFetcher
    private let now: @MainActor () -> Date

    init(
        cache: FlightStatusCache = FlightStatusCache(),
        isLiveStatusConfigured: @escaping @MainActor () -> Bool = { AppSecrets.isConfigured(.flightAware) },
        fetchFlights: @escaping FlightFetcher = { try await FlightTrackerViewModel.fetchFromFlightAware(ident: $0) },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.cache = cache
        self.isLiveStatusConfigured = isLiveStatusConfigured
        self.fetchFlights = fetchFlights
        self.now = now
    }

    // MARK: - Freshness

    /// How long a fetched status may be called "LIVE".
    static let liveFreshness: TimeInterval = 10 * 60

    /// "LIVE" only for a result fetched in the last `liveFreshness`, and never
    /// for a saved copy or after a failed refresh. A timestamp slightly in the
    /// future (the timeline clock lagging the fetch) still counts as fresh.
    static func showsLiveBadge(lastUpdated: Date?, isShowingSavedResults: Bool, now: Date) -> Bool {
        guard let lastUpdated, !isShowingSavedResults else { return false }
        return now.timeIntervalSince(lastUpdated) <= liveFreshness
    }

    func showsLiveBadge(now: Date) -> Bool {
        Self.showsLiveBadge(lastUpdated: lastUpdated, isShowingSavedResults: isShowingSavedResults, now: now)
    }

    /// "Updated just now" / "Updated 12 min. ago" in the user's locale. Pass
    /// `.full` for VoiceOver ("12 minutes ago"), since "12m" is read as metres.
    static func updatedText(
        since date: Date,
        now: Date,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .short,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = unitsStyle
        formatter.dateTimeStyle = .numeric
        return "Updated \(formatter.localizedString(for: date, relativeTo: now))"
    }

    // MARK: - Search

    /// Searches for flights. Skips duplicate requests to avoid unnecessary API calls.
    func searchFlight(ident: String) async {
        let normalizedIdent = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !normalizedIdent.isEmpty else {
            errorMessage = "Please enter a flight number."
            return
        }
        guard normalizedIdent != lastSearchedIdent else { return }

        await fetch(ident: normalizedIdent)
    }

    /// Refreshes the flight on screen, keeping its results visible while it
    /// loads and if it fails. Also what Retry calls.
    func refresh() async {
        guard !currentIdent.isEmpty else { return }
        await fetch(ident: currentIdent)
    }

    /// Reopens the tracker on the flight fetched most recently (within
    /// `maxAge`), from the saved copy, so opening it in airplane mode shows
    /// the last known gate and times. Returns true when it restored one; the
    /// caller then refreshes.
    @discardableResult
    func restoreLastSearch(maxAge: TimeInterval = 24 * 3_600) -> Bool {
        guard currentIdent.isEmpty, flights.isEmpty,
              let saved = cache.mostRecent(),
              now().timeIntervalSince(saved.fetchedAt) <= maxAge else { return false }
        currentIdent = saved.ident
        searchText = saved.ident
        flights = saved.flights
        lastUpdated = saved.fetchedAt
        isShowingSavedResults = true
        return true
    }

    // MARK: - Internal Fetch

    /// Live status needs a FlightAware AeroAPI key. Without one the screen says
    /// so plainly instead of sending an unauthenticated request and surfacing
    /// a raw HTTP error.
    static let noKeyMessage = "Live flight status isn't switched on in this build yet. Your flights still show on Home and in your itinerary."

    static let offlineMessage = "Can't reach flight status right now. Check your connection and try again."
    static let captivePortalMessage = "Flight status didn't load. On hotel or airport Wi-Fi, open a web page to finish signing in, then try again."
    static let unavailableMessage = "Flight status isn't available right now. Try again in a few minutes."

    private func fetch(ident: String) async {
        // A different flight: show its saved status straight away (or nothing),
        // never the previous flight's results under the new number.
        if ident != currentIdent {
            currentIdent = ident
            if let saved = cache.load(ident: ident) {
                flights = saved.flights
                lastUpdated = saved.fetchedAt
                isShowingSavedResults = true
            } else {
                flights = []
                lastUpdated = nil
                isShowingSavedResults = false
            }
        }

        isLoading = true
        errorMessage = nil
        isLiveStatusUnavailable = false
        // Only the newest search clears the spinner; a slower, superseded one
        // finishing later mustn't.
        defer { if ident == currentIdent { isLoading = false } }

        guard isLiveStatusConfigured() else {
            isLiveStatusUnavailable = true
            errorMessage = Self.noKeyMessage
            return
        }

        do {
            let result = try await fetchFlights(ident)
            guard ident == currentIdent else { return }   // superseded
            lastSearchedIdent = ident

            if result.isEmpty {
                // Keep any saved status for this number on screen, marked as
                // not live, rather than blanking it.
                errorMessage = "No flights found for \"\(ident)\"."
                isShowingSavedResults = !flights.isEmpty
                return
            }

            let fetchedAt = now()
            flights = result
            lastUpdated = fetchedAt
            isShowingSavedResults = false
            cache.save(result, ident: ident, fetchedAt: fetchedAt)
        } catch {
            guard ident == currentIdent, !Self.isCancellation(error) else { return }
            errorMessage = Self.message(for: error)
            // The flights already on screen stay; they're just no longer current.
            isShowingSavedResults = !flights.isEmpty
        }
    }

    /// The network call behind the default `FlightFetcher`.
    static func fetchFromFlightAware(ident: String) async throws -> [Flight] {
        guard let url = Endpoints.FlightAware.flightStatus(ident: ident) else {
            throw APIError.invalidURL
        }
        let response: FlightSearchResponse = try await APIClient.shared.get(
            url: url,
            headers: Endpoints.FlightAware.headers
        )
        return response.flights
    }

    /// One plain sentence for a failed fetch. Raw `APIError` text ("An
    /// unexpected error occurred: The Internet connection appears to be
    /// offline.") isn't something to show a traveler.
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unknown(let underlying):
                return isConnectivity(underlying) ? offlineMessage : unavailableMessage
            case .decodingFailed:
                // A captive portal answers with an HTML login page.
                return captivePortalMessage
            case .rateLimited:
                return apiError.errorDescription ?? unavailableMessage
            case .notConfigured:
                return noKeyMessage
            default:
                return unavailableMessage
            }
        }
        return isConnectivity(error) ? offlineMessage : unavailableMessage
    }

    private static func isConnectivity(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// A search replaced by a newer one, or a view that went away, isn't an
    /// error to show.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if let apiError = error as? APIError, case .unknown(let underlying) = apiError {
            return underlying is CancellationError || (underlying as? URLError)?.code == .cancelled
        }
        return false
    }

    // MARK: - Single-Flight Status Refresh

    /// Fetches the latest status for a single flight and returns the entry
    /// matching `faFlightId` (falling back to the first result). Used by the
    /// detail screen to keep gate/times/status/progress fresh without disturbing
    /// the shared list state (`flights`, `isLoading`, `errorMessage`). Returns
    /// nil on any failure so callers can keep showing the last-known snapshot.
    /// A fresh result also updates the saved copy, so the next offline open
    /// shows the newer gate.
    func fetchFlightStatus(ident: String, matching faFlightId: String) async -> Flight? {
        guard isLiveStatusConfigured() else { return nil }
        do {
            let result = try await fetchFlights(ident)
            let match = result.first { $0.faFlightId == faFlightId } ?? result.first
            if let match { cache.update(match, ident: ident) }
            return match
        } catch {
            // Best-effort refresh: keep the last-known snapshot on failure.
            return nil
        }
    }

    // MARK: - Live Position Polling

    /// Begins refreshing the live position/track for an airborne flight. Safe to
    /// call repeatedly — restarts cleanly. Call `stopLivePolling()` on disappear.
    func startLivePolling(for flight: Flight, interval: TimeInterval = 45) {
        stopLivePolling()
        livePollingTask = Task { [weak self] in
            // First fetch happens immediately, then on the interval.
            while !Task.isCancelled {
                await self?.fetchPosition(for: flight)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = nil
    }

    private func fetchPosition(for flight: Flight) async {
        guard AppSecrets.isConfigured(.flightAware),
              let url = Endpoints.FlightAware.flightTrack(ident: flight.faFlightId) else { return }
        do {
            let response: FlightTrackResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.FlightAware.headers
            )
            track = response.positions
            livePosition = response.positions.last
        } catch {
            // Position is best-effort; keep the last known sample and stay quiet.
        }
    }

    // MARK: - Clear

    /// Clears the screen. The saved statuses stay, so searching the same
    /// flight again offline still finds them.
    func clearSearch() {
        stopLivePolling()
        flights = []
        searchText = ""
        errorMessage = nil
        lastSearchedIdent = ""
        currentIdent = ""
        lastUpdated = nil
        isShowingSavedResults = false
        isLiveStatusUnavailable = false
        livePosition = nil
        track = []
    }
}
