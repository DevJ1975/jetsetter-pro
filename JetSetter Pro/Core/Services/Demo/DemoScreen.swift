// File: Core/Services/Demo/DemoScreen.swift
//
// COMPILED ONLY INTO Debug AND Beta (DEMO_ENABLED), like the rest of demo mode.
//
// Opens a named screen on launch so a script can drive the simulator through
// the app without UI tests, for example to capture screenshots:
//
//   xcrun simctl launch <device> DevJ.JetSetter-Pro -seedDemoData -demoScreen wallet
//
// The value comes from the launch arguments' UserDefaults domain, which is
// never persisted, so a normal launch afterwards opens Home as usual. Unknown
// names are ignored. Scripts/simulator-preview.sh is the main caller.

#if DEMO_ENABLED
import Foundation

enum DemoScreen {

    /// The launch-argument key: `-demoScreen <name>`.
    static let argumentKey = "demoScreen"

    /// The demo trip's flight, so `boardingPass` opens its pass.
    static let demoFlightNumber = "DL1423"

    /// The destination for a screen name, or nil for an unknown name.
    static func destination(named name: String) -> AppRouter.Destination? {
        switch name.lowercased() {
        case "home":            return .home
        case "itinerary":       return .itinerary
        case "wallet":          return .wallet
        case "expenses":        return .expenses
        case "more":            return .more
        case "assistant":       return .assistant
        case "checkin":         return .checkIn
        case "disruption":      return .disruption
        case "flighttracker":   return .flightTracker
        case "documentvault":   return .documentVault
        case "packinglist":     return .packingList
        case "groundtransport": return .groundTransport
        case "currency":        return .currency
        case "newtrip":         return .newTrip
        case "boardingpass":    return .boardingPass(flightNumber: demoFlightNumber, departure: nil)
        default:                return nil
        }
    }

    /// The screen requested by `-demoScreen`, if any.
    static func requestedDestination(in defaults: UserDefaults = .standard) -> AppRouter.Destination? {
        defaults.string(forKey: argumentKey).flatMap(destination(named:))
    }
}
#endif
