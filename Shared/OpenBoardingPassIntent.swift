// File: Shared/OpenBoardingPassIntent.swift
//
// The "Boarding pass" button on the expanded Live Activity. Tapping it opens
// JetSetter Pro straight to the pass for that flight, which is what a traveler
// at the security line actually wants from the Dynamic Island.
//
// Why both targets compile it: the widget extension needs the type to build
// `Button(intent:)`, and the app needs it because a `LiveActivityIntent` is
// performed in the app's process, never the extension's. The perform body
// calls `LiveActivityIntentRouting`, which each target defines for itself:
// the app's version routes through `AppRouter`, the widget's is an empty stub
// that never runs. That keeps `AppRouter` out of the widget.
//
// `supportedModes = .foreground` (iOS 26) brings the app forward to show the
// pass; a plain LiveActivityIntent would run in the background and change
// nothing on screen. `isDiscoverable = false` keeps it out of Siri, Spotlight
// and Shortcuts: it's a Live Activity button, not an assistant action, and
// the App Shortcuts list is already at its cap.

import AppIntents
import Foundation

struct OpenBoardingPassIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Show Boarding Pass"
    static let description = IntentDescription("Opens JetSetter Pro to the boarding pass for the flight on the Live Activity.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Flight Number")
    var flightNumber: String

    @Parameter(title: "Departure")
    var departure: Date

    init() {}

    init(flightNumber: String, departure: Date) {
        self.flightNumber = flightNumber
        self.departure = departure
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityIntentRouting.openBoardingPass(flightNumber: flightNumber, departure: departure)
        return .result()
    }
}
