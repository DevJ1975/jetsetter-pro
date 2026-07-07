// File: Core/Services/WatchConnectivityService.swift
//
// Bridges JetSetter Pro with the paired Apple Watch app via WCSession.
//
// Architecture:
//   • iPhone (this file) pushes a NextFlightSnapshot to the watch as
//     application context whenever the flight data changes. Application
//     context survives launches and gets the latest state when the watch
//     wakes — perfect for a "current trip glance".
//   • Watch sends a single message back: "checked_in" with a flight ID, which
//     this service forwards to CheckInStateStore so the gate-closing ding
//     doesn't fire after the user checks in from their wrist.
//
// To wire up the Watch side, see SETUP-WATCH.md for the full template.

import Foundation
import WatchConnectivity

// MARK: - Shared payload

/// Snapshot of the user's next flight, encoded into the watch's application
/// context dictionary. Kept small — application context is delivered in full
/// whenever it changes.
struct NextFlightSnapshot: Codable, Equatable {
    let flightNumber: String
    let airlineName: String
    let originIATA: String
    let destinationIATA: String
    let gate: String?
    let terminal: String?
    let departure: Date
    let isCheckedIn: Bool

    static let userInfoKey = "next_flight_snapshot_v1"

    /// Sentinel key sent (set to `true`) when there is no next flight, so the
    /// paired watch can actively clear its glance. An empty application context
    /// gives the watch no observable signal that the previous snapshot is gone.
    static let clearedKey = "next_flight_snapshot_v1_cleared"
}

// MARK: - Notification

extension Notification.Name {
    /// Posted after a check-in completes (success screen appears) so that other
    /// surfaces — notably HomeView — can refresh their state and re-push the
    /// updated NextFlightSnapshot to the paired watch.
    static let jetSetterCheckInPosted = Notification.Name("jetSetterCheckInPosted")
}

// MARK: - WatchConnectivityService

final class WatchConnectivityService: NSObject, WCSessionDelegate {

    static let shared = WatchConnectivityService()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Activates the WCSession if the device supports it. Safe to call multiple
    /// times — repeated activation is a no-op once the session is active.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    // MARK: - Push to watch

    /// Sends the latest flight snapshot to the paired watch. Uses application
    /// context so the watch always shows the freshest data — older values are
    /// overwritten in transit.
    func updateNextFlight(_ snapshot: NextFlightSnapshot?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        do {
            let context: [String: Any]
            if let snapshot {
                let data = try encoder.encode(snapshot)
                context = [NextFlightSnapshot.userInfoKey: data]
            } else {
                // Clear via an explicit sentinel. An empty dictionary is
                // indistinguishable from "no update" for a watch that keys off
                // userInfoKey, so it would keep rendering the stale snapshot.
                context = [NextFlightSnapshot.clearedKey: true]
            }
            try session.updateApplicationContext(context)
        } catch {
            // Non-fatal: next change attempt will retry.
        }
    }

    // MARK: - WCSessionDelegate (iOS-only callbacks)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No-op. Activation completion just enables further calls.
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Required for iOS — fires when transitioning between watches.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so we can pair with a different watch if needed.
        WCSession.default.activate()
    }

    /// Watch → iPhone: the user tapped "Checked in" on their wrist.
    /// Forward to CheckInStateStore so the iPhone stops nagging.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String, action == "checked_in",
              let flightNumber = message["flight_number"] as? String,
              let timestamp = message["departure_timestamp"] as? TimeInterval
        else { return }
        let departure = Date(timeIntervalSince1970: timestamp)
        Task { @MainActor in
            CheckInStateStore.markCheckedIn(flightNumber: flightNumber, departure: departure)
        }
    }
}
