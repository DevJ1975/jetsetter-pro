// File: WidgetExtension/LiveActivityIntentRouting.swift
//
// Widget-side half of `OpenBoardingPassIntent` (Shared/). The extension only
// needs the intent type to build the Live Activity's button; the system runs a
// `LiveActivityIntent` in the app's process, where the real
// `LiveActivityIntentRouting` (JetSetter Pro/Core/Services) routes through
// `AppRouter`. This stub exists so the shared intent compiles here and is
// never called.

import Foundation

enum LiveActivityIntentRouting {
    @MainActor
    static func openBoardingPass(flightNumber: String, departure: Date) {}
}
