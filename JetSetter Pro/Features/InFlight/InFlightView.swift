// File: Features/InFlight/InFlightView.swift
//
// Live in-flight tracker. Big-readable altitude/speed/heading numbers, a
// phase pill, and (when GPS locks) the live route map with the airplane at
// the actual GPS coordinate.

import SwiftUI
import CoreLocation

struct InFlightView: View {

    @StateObject private var tracker = InFlightTrackingService.shared

    /// Optional flight context — when provided, the map shows the planned
    /// great-circle route between these two airports.
    let originIATA: String?
    let destinationIATA: String?

    init(originIATA: String? = nil, destinationIATA: String? = nil) {
        self.originIATA = originIATA
        self.destinationIATA = destinationIATA
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                phasePill
                if let origin = originIATA, let dest = destinationIATA {
                    routeMap(origin: origin, destination: dest)
                }
                statsGrid
                gpsCard
                controls
                if let error = tracker.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                disclaimers
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("In-Flight")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Phase pill

    private var phasePill: some View {
        HStack(spacing: 10) {
            Image(systemName: tracker.snapshot.phase.systemImage)
                .font(.title3.bold())
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT PHASE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Text(tracker.snapshot.phase.label)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if tracker.isTracking {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("LIVE").font(.system(size: 10, weight: .black)).tracking(1.2)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0A0A1E"), Color(hex: "#1A3040")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Map

    private func routeMap(origin: String, destination: String) -> some View {
        FlightMapView(
            originIATA: origin,
            destinationIATA: destination,
            liveCoordinate: tracker.snapshot.hasGPSFix ? tracker.snapshot.coordinate : nil,
            style: .hero
        )
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile(
                icon: "arrow.up.right",
                label: "ALTITUDE",
                value: "\(tracker.snapshot.altitudeFeet)",
                unit: "ft"
            )
            statTile(
                icon: "speedometer",
                label: "GROUND SPEED",
                value: "\(tracker.snapshot.groundSpeedKnots)",
                unit: "kts"
            )
            statTile(
                icon: "arrow.up.arrow.down",
                label: "VERTICAL SPEED",
                value: signed(tracker.snapshot.verticalSpeedFpm),
                unit: "fpm"
            )
            statTile(
                icon: "location.north.fill",
                label: "HEADING",
                value: tracker.snapshot.heading.map { "\(Int($0))°" } ?? "—",
                unit: ""
            )
        }
    }

    private func statTile(icon: String, label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.3)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .jetCard()
    }

    // MARK: - GPS / Position

    private var gpsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: tracker.snapshot.hasGPSFix ? "location.fill" : "location.slash.fill")
                    .font(.caption.bold())
                Text(tracker.snapshot.hasGPSFix ? "GPS LOCKED" : "GPS SEARCHING")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(tracker.snapshot.hasGPSFix
                             ? JetsetterTheme.Colors.success
                             : JetsetterTheme.Colors.textSecondary)
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 6) {
                if let coord = tracker.snapshot.coordinate {
                    detailRow("Latitude",  String(format: "%.4f°", coord.latitude))
                    detailRow("Longitude", String(format: "%.4f°", coord.longitude))
                } else {
                    Text("Move to a window seat for live GPS position. Locking typically takes 2–5 minutes at altitude.")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemFill).opacity(0.4))
            )
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        Button {
            if tracker.isTracking {
                tracker.stop()
            } else {
                tracker.start()
            }
        } label: {
            HStack {
                Image(systemName: tracker.isTracking ? "stop.circle.fill" : "play.circle.fill")
                Text(tracker.isTracking ? "Stop Tracking" : "Start Tracking")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tracker.isTracking ? Color.red : JetsetterTheme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
    }

    private var disclaimers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Altitude uses the iPhone barometer — accurate even in airplane mode.", systemImage: "barometer")
            Label("Ground speed and position need GPS — window seat recommended.", systemImage: "antenna.radiowaves.left.and.right")
            Label("Continuous tracking uses ~15% battery per hour.", systemImage: "battery.50")
        }
        .font(.caption2)
        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func signed(_ n: Int) -> String { n >= 0 ? "+\(n)" : "\(n)" }
}

#Preview {
    NavigationStack {
        InFlightView(originIATA: "SFO", destinationIATA: "NRT")
    }
}
