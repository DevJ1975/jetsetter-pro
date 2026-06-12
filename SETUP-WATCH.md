# Apple Watch Companion — Setup

The iPhone side is already wired:
- `Core/Services/WatchConnectivityService.swift` activates `WCSession` at launch and pushes a `NextFlightSnapshot` whenever the next flight changes.
- When the watch sends back a "checked_in" message, the iPhone marks the flight as checked in via `CheckInStateStore`, which silences the gate-closing ding.

This document covers the **Watch target** you need to add in Xcode (one-time, ~10 minutes), and a complete watch-app source file you can paste in.

---

## 1. Add the Watch App target

1. In Xcode, **File → New → Target…**
2. Select **watchOS → App**. Click Next.
3. Configure:
   - **Product Name:** `JetSetter Pro Watch`
   - **Bundle identifier:** auto-derived (e.g. `DevJ.JetSetter-Pro.watchkitapp`)
   - **Interface:** SwiftUI
   - **Include Notification Scene:** unchecked (you can add later)
4. Click **Finish**, and choose **Activate** when Xcode prompts.

Xcode creates two new targets (the watchKit App and Extension on older OSes; a single Watch App target on watchOS 9+). Verify both bundle IDs share your iOS app's prefix.

## 2. Add WatchConnectivity capability

Already enabled for the iPhone via `WCSession.isSupported()` — no entitlement needed. The Watch target gets it automatically when you `import WatchConnectivity`.

## 3. Paste the Watch app source

In the new Watch target, replace the auto-generated `ContentView.swift` and `*App.swift` with this single file:

```swift
// File: JetSetter_Pro_WatchApp.swift  (in the Watch target)

import SwiftUI
import WatchConnectivity

@main
struct JetSetterProWatchApp: App {
    @StateObject private var connectivity = WatchSideConnectivity.shared

    init() {
        WatchSideConnectivity.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NextFlightWatchView()
                .environmentObject(connectivity)
        }
    }
}

// MARK: - Shared payload (must match the iOS side)

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
}

// MARK: - Connectivity (watch side)

final class WatchSideConnectivity: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSideConnectivity()

    @Published private(set) var snapshot: NextFlightSnapshot? = nil

    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Pick up the most recent context if the watch was woken
        applyContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        applyContext(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyContext(applicationContext)
    }

    private func applyContext(_ context: [String: Any]) {
        guard let data = context[NextFlightSnapshot.userInfoKey] as? Data,
              let decoded = try? decoder.decode(NextFlightSnapshot.self, from: data) else {
            DispatchQueue.main.async { self.snapshot = nil }
            return
        }
        DispatchQueue.main.async { self.snapshot = decoded }
    }

    /// Sends "checked in" back to the iPhone so it stops nagging.
    func markCheckedIn() {
        guard let snap = snapshot else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.sendMessage([
            "action": "checked_in",
            "flight_number": snap.flightNumber,
            "departure_timestamp": snap.departure.timeIntervalSince1970
        ], replyHandler: nil)
    }
}

// MARK: - Next Flight watch view

struct NextFlightWatchView: View {
    @EnvironmentObject private var connectivity: WatchSideConnectivity

    var body: some View {
        Group {
            if let snap = connectivity.snapshot {
                flightCard(snap)
            } else {
                emptyState
            }
        }
        .navigationTitle("Next Flight")
    }

    @ViewBuilder
    private func flightCard(_ snap: NextFlightSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(snap.flightNumber)
                    .font(.title3).bold()
                    .monospaced()

                Text(snap.airlineName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(snap.originIATA).font(.headline).bold()
                    Image(systemName: "airplane")
                    Text(snap.destinationIATA).font(.headline).bold()
                }
                .monospaced()
                .padding(.top, 6)

                Text(snap.departure, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let gate = snap.gate {
                    Text("Gate \(gate)")
                        .font(.callout).bold()
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }

                if snap.isCheckedIn {
                    Label("Checked in", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 6)
                } else {
                    Button {
                        connectivity.markCheckedIn()
                    } label: {
                        Label("I've checked in", systemImage: "checkmark.circle")
                    }
                    .padding(.top, 6)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No upcoming flight")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

## 4. Test it

1. Pair an Apple Watch with the simulator (or use real hardware).
2. Build & run the iOS scheme — the iPhone sends an initial flight snapshot when Home loads.
3. Switch to the Watch scheme and run — the watch view should populate.
4. Tap "I've checked in" on the watch → the iPhone receives the message, marks the flight checked in, and the gate-closing ding will not fire.

## 5. Optional: Complications

For Lock Screen complications, add a `WidgetBundle` to the Watch target. The widget can read the same `NextFlightSnapshot` from `WCSession.default.receivedApplicationContext`. Apple's `AccessoryRectangular`, `AccessoryCircular`, and `AccessoryCorner` families all work well for a flight glance — leave this for a future v1.2 release.
