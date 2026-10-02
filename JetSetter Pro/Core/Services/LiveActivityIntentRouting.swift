// File: Core/Services/LiveActivityIntentRouting.swift
//
// App-side half of `OpenBoardingPassIntent` (Shared/). The system performs a
// Live Activity's intent in this process and brings the app forward, so the
// request goes through `AppRouter.open(_:)` like any other outside entry
// point: modals close, the Wallet tab opens, and the tab shows the pass for
// that flight (or its list when the traveler hasn't saved one). The widget
// extension has its own empty stub with the same name.

import Foundation

enum LiveActivityIntentRouting {
    static func openBoardingPass(flightNumber: String, departure: Date) {
        AppRouter.shared.open(.boardingPass(flightNumber: flightNumber, departure: departure))
    }
}
