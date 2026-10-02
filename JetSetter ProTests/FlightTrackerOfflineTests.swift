// File: JetSetter ProTests/FlightTrackerOfflineTests.swift
//
// The Flight Tracker at a gate with bad Wi-Fi: the last status has to stay on
// screen, survive a relaunch through the saved copy, and stop calling itself
// "LIVE" once it's stale or came from that copy.
//
// No network: the view model takes its fetcher and clock as closures, and each
// test writes to its own throwaway UserDefaults suite.

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
@Suite struct FlightTrackerOfflineTests {

    // MARK: - Fixtures

    /// Stands in for FlightAware. A class, so the test can change the next
    /// answer after the view model has captured it.
    @MainActor
    final class StubFlightAware {
        var next: Result<[Flight], Error> = .success([])
        private(set) var calls = 0

        func fetch(_ ident: String) throws -> [Flight] {
            calls += 1
            return try next.get()
        }
    }

    @MainActor
    final class TestClock {
        /// A whole second, so it survives the cache's ISO-8601 round trip exactly.
        var now = Date(timeIntervalSince1970: 1_789_000_000)
    }

    private static let offline = APIError.unknown(URLError(.notConnectedToInternet))

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "FlightTrackerOfflineTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func makeViewModel(
        cache: FlightStatusCache,
        stub: StubFlightAware,
        clock: TestClock,
        configured: Bool = true
    ) -> FlightTrackerViewModel {
        FlightTrackerViewModel(
            cache: cache,
            isLiveStatusConfigured: { configured },
            fetchFlights: { try stub.fetch($0) },
            now: { clock.now }
        )
    }

    // MARK: - Failed refresh

    /// The defect this covers: `fetch` cleared `flights` before every request,
    /// so a refresh that failed at the gate replaced the gate and times the
    /// traveler was reading with an error screen.
    @Test func aFailedRefreshKeepsTheLastResultsOnScreenAndMarksThemNotLive() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = StubFlightAware()
        let clock = TestClock()
        let vm = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: stub, clock: clock)

        stub.next = .success([Flight.sample])
        await vm.searchFlight(ident: "UA2391")
        let fetchedAt = clock.now
        #expect(vm.flights.map(\.gateOrigin) == ["B12"])
        #expect(vm.showsLiveBadge(now: clock.now))

        clock.now = fetchedAt.addingTimeInterval(120)
        stub.next = .failure(Self.offline)
        await vm.refresh()

        #expect(stub.calls == 2)
        #expect(vm.flights.map(\.gateOrigin) == ["B12"])
        #expect(vm.errorMessage == FlightTrackerViewModel.offlineMessage)
        #expect(vm.isShowingSavedResults)
        #expect(vm.lastUpdated == fetchedAt)
        #expect(!vm.showsLiveBadge(now: clock.now))
        #expect(!vm.isLoading)
    }

    /// After a relaunch with no connection, searching the same flight shows the
    /// saved status straight away, with its original time and no LIVE badge.
    @Test func theSavedStatusSurvivesARelaunchAndAFailedRefresh() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock()

        let online = StubFlightAware()
        online.next = .success([Flight.sample])
        let firstLaunch = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: online, clock: clock)
        await firstLaunch.searchFlight(ident: "UA2391")
        let fetchedAt = clock.now

        clock.now = fetchedAt.addingTimeInterval(40 * 60)
        let offline = StubFlightAware()
        offline.next = .failure(Self.offline)
        let relaunch = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: offline, clock: clock)
        await relaunch.searchFlight(ident: "ua2391")

        #expect(offline.calls == 1)
        #expect(relaunch.flights.map(\.faFlightId) == [Flight.sample.faFlightId])
        #expect(relaunch.flights.first?.gateOrigin == "B12")
        #expect(relaunch.lastUpdated == fetchedAt)
        #expect(relaunch.isShowingSavedResults)
        #expect(relaunch.errorMessage == FlightTrackerViewModel.offlineMessage)
        #expect(!relaunch.showsLiveBadge(now: clock.now))
    }

    @Test func reopeningTheTrackerRestoresTheLastFlightFromTheSavedCopy() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock()
        let stub = StubFlightAware()
        stub.next = .success([Flight.sample])
        await makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: stub, clock: clock)
            .searchFlight(ident: "UA2391")

        clock.now = clock.now.addingTimeInterval(3_600)
        let reopened = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: stub, clock: clock)
        #expect(reopened.restoreLastSearch())
        #expect(reopened.currentIdent == "UA2391")
        #expect(reopened.searchText == "UA2391")
        #expect(reopened.flights.count == 1)
        #expect(!reopened.showsLiveBadge(now: clock.now))
    }

    /// "No flights found" must not overwrite the last good status: FlightAware
    /// drops a flight from its window a day or two after it lands.
    @Test func anEmptyResultNeverOverwritesTheSavedStatus() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = FlightStatusCache(defaults: defaults)
        let clock = TestClock()
        let stub = StubFlightAware()
        let vm = makeViewModel(cache: cache, stub: stub, clock: clock)

        stub.next = .success([Flight.sample])
        await vm.searchFlight(ident: "UA2391")
        stub.next = .success([])
        await vm.refresh()

        #expect(cache.load(ident: "UA2391")?.flights.count == 1)
        #expect(vm.flights.count == 1)
        #expect(vm.isShowingSavedResults)
    }

    // MARK: - LIVE badge

    @Test func liveIsShownOnlyForAFreshNetworkResult() {
        let fetched = Date(timeIntervalSince1970: 1_789_000_000)

        #expect(FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: fetched, isShowingSavedResults: false, now: fetched.addingTimeInterval(9 * 60)))
        #expect(FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: fetched, isShowingSavedResults: false, now: fetched.addingTimeInterval(10 * 60)))
        // A timeline tick that lags the fetch by a moment still counts as fresh.
        #expect(FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: fetched, isShowingSavedResults: false, now: fetched.addingTimeInterval(-5)))
    }

    @Test func liveIsHiddenWhenStaleSavedOrUnknown() {
        let fetched = Date(timeIntervalSince1970: 1_789_000_000)

        #expect(!FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: fetched, isShowingSavedResults: false, now: fetched.addingTimeInterval(10 * 60 + 1)))
        #expect(!FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: fetched, isShowingSavedResults: true, now: fetched))
        #expect(!FlightTrackerViewModel.showsLiveBadge(
            lastUpdated: nil, isShowingSavedResults: false, now: fetched))
    }

    @Test func liveDropsOffTenMinutesAfterASuccessfulFetch() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock()
        let stub = StubFlightAware()
        stub.next = .success([Flight.sample])
        let vm = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: stub, clock: clock)
        await vm.searchFlight(ident: "UA2391")

        #expect(vm.showsLiveBadge(now: clock.now.addingTimeInterval(5 * 60)))
        #expect(!vm.showsLiveBadge(now: clock.now.addingTimeInterval(11 * 60)))
    }

    @Test func theUpdatedStampSaysHowOldTheStatusIs() {
        let fetched = Date(timeIntervalSince1970: 1_789_000_000)
        let english = Locale(identifier: "en_US")
        #expect(FlightTrackerViewModel.updatedText(since: fetched, now: fetched.addingTimeInterval(30), locale: english)
                == "Updated just now")
        #expect(FlightTrackerViewModel.updatedText(
            since: fetched, now: fetched.addingTimeInterval(12 * 60), unitsStyle: .full, locale: english)
                == "Updated 12 minutes ago")
    }

    // MARK: - Messages

    /// Without a FlightAware key the tracker still shows its one plain sentence,
    /// offers no Retry, and never touches the network.
    @Test func withoutAKeyThePlainSentenceSurvivesAndNothingIsFetched() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let stub = StubFlightAware()
        let vm = makeViewModel(cache: FlightStatusCache(defaults: defaults), stub: stub,
                               clock: TestClock(), configured: false)

        await vm.searchFlight(ident: "UA2391")

        #expect(vm.errorMessage == FlightTrackerViewModel.noKeyMessage)
        #expect(vm.isLiveStatusUnavailable)
        #expect(stub.calls == 0)
    }

    @Test func networkFailuresBecomePlainSentences() {
        #expect(FlightTrackerViewModel.message(for: Self.offline) == FlightTrackerViewModel.offlineMessage)
        #expect(FlightTrackerViewModel.message(for: APIError.decodingFailed(URLError(.cannotParseResponse)))
                == FlightTrackerViewModel.captivePortalMessage)
        #expect(FlightTrackerViewModel.message(for: APIError.requestFailed(statusCode: 503))
                == FlightTrackerViewModel.unavailableMessage)
    }

    // MARK: - Cache bounds

    @Test func theCacheKeepsTheNewestTwentyAndDropsOldEntries() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        var entries: [String: CachedFlightStatus] = [:]
        for i in 0..<25 {
            let ident = "XX\(i)"
            entries[ident] = CachedFlightStatus(ident: ident, flights: [Flight.sample],
                                                fetchedAt: now.addingTimeInterval(TimeInterval(-i * 60)))
        }
        entries["OLD1"] = CachedFlightStatus(ident: "OLD1", flights: [Flight.sample],
                                             fetchedAt: now.addingTimeInterval(-4 * 86_400))

        let pruned = FlightStatusCache.pruned(entries, now: now)
        #expect(pruned.count == FlightStatusCache.maxEntries)
        #expect(pruned["XX0"] != nil)
        #expect(pruned["XX24"] == nil)
        #expect(pruned["OLD1"] == nil)
    }
}
