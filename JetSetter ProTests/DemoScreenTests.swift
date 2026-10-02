// File: JetSetter ProTests/DemoScreenTests.swift
//
// `-demoScreen <name>` drives the simulator-preview script. If a name stops
// resolving, the screenshot for that screen silently shows Home instead, so
// every name the script uses is pinned here.

#if DEMO_ENABLED

import Testing
import Foundation
@testable import JetSetter_Pro

@MainActor
struct DemoScreenTests {

    /// The names Scripts/simulator-preview.sh passes.
    @Test func everyScriptedScreenNameResolves() {
        let names = ["home", "boardingPass", "wallet", "itinerary", "expenses", "more",
                     "flightTracker", "disruption", "packingList", "documentVault", "assistant"]
        for name in names {
            #expect(DemoScreen.destination(named: name) != nil, "\(name) should resolve")
        }
    }

    @Test func boardingPassOpensTheDemoFlightsPass() {
        #expect(DemoScreen.destination(named: "boardingPass")
                == .boardingPass(flightNumber: "DL1423", departure: nil))
        #expect(DemoScreen.destination(named: "WALLET") == .wallet)
    }

    @Test func unknownOrMissingNamesOpenNothing() throws {
        #expect(DemoScreen.destination(named: "settings-secret") == nil)
        let defaults = try #require(UserDefaults(suiteName: "DemoScreenTests-\(UUID().uuidString)"))
        #expect(DemoScreen.requestedDestination(in: defaults) == nil)
        defaults.set("more", forKey: DemoScreen.argumentKey)
        #expect(DemoScreen.requestedDestination(in: defaults) == .more)
    }
}

#endif
