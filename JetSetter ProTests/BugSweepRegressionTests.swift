// File: JetSetter ProTests/BugSweepRegressionTests.swift
// Regression tests for bugs fixed in the code-review sweep. Pure and
// deterministic (no I/O) so they're safe to run anywhere.

import Testing
import Foundation
@testable import JetSetter_Pro

struct BugSweepRegressionTests {

    private static let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * Self.day) }
    private func daysAhead(_ d: Double) -> Date { now.addingTimeInterval(d * Self.day) }

    // MARK: - Recency weighting: future-dated signals must not dominate
    //
    // Bug: recencyWeight clamped age with `max(0, now - date)`, so a signal dated
    // in the future collapsed to age 0 and received the maximum weight of 1.0 —
    // letting one bogus/clock-skewed timestamp outrank all genuine history.

    @Test func futureDatedSignalGetsZeroWeight() {
        // Well beyond the clock-skew tolerance -> treated as invalid (neutral 0).
        #expect(TravelProfileEngine.recencyWeight(daysAhead(30), now: now) == 0)
    }

    @Test func benignClockSkewStillCountsAsRecent() {
        // A couple of minutes ahead (within the tolerance) should stay near full
        // weight, not be zeroed out.
        let slightlyAhead = now.addingTimeInterval(120) // 2 minutes
        #expect(TravelProfileEngine.recencyWeight(slightlyAhead, now: now) > 0.99)
    }

    @Test func genuineRecentSignalOutranksFutureBogusEntry() {
        // "AA" flown twice recently vs. a single far-future bogus "ZZ" entry.
        let entries = [
            ("AA", daysAgo(2)),
            ("AA", daysAgo(5)),
            ("ZZ", daysAhead(365))
        ]
        let ranked = TravelProfileEngine.weightedRanking(entries, now: now)
        #expect(ranked.first?.value == "AA")
        #expect(ranked.first?.count == 2)
    }
}
