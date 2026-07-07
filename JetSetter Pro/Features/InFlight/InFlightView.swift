// File: Features/InFlight/InFlightView.swift
//
// Live in-flight tracker. Big-readable altitude/speed/heading numbers, a
// phase pill, and (when GPS locks) the live route map with the airplane at
// the actual GPS coordinate.

import SwiftUI
import CoreLocation

struct InFlightView: View {

    @StateObject private var tracker = InFlightTrackingService.shared

    /// True when this view auto-started demo tracking in onAppear, so
    /// onDisappear knows to stop only the tracking it started itself.
    @State private var didAutoStartDemoTracking = false

    /// Optional flight context — when provided, the map shows the planned
    /// great-circle route between these two airports.
    let originIATA: String?
    let destinationIATA: String?

    /// IANA identifier for the arrival airport's time zone (e.g. "Asia/Tokyo").
    /// When resolvable, the screen shows the current local time at the
    /// destination so the traveler knows what time it'll be when they land.
    let destinationTimeZoneID: String?

    /// Flight context used for the takeoff/landing loved-ones prompts.
    let flightNumber: String?
    let destinationCity: String?

    init(originIATA: String? = nil,
         destinationIATA: String? = nil,
         destinationTimeZoneID: String? = nil,
         flightNumber: String? = nil,
         destinationCity: String? = nil) {
        self.originIATA = originIATA
        self.destinationIATA = destinationIATA
        self.destinationTimeZoneID = destinationTimeZoneID
        self.flightNumber = flightNumber
        self.destinationCity = destinationCity
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !tracker.isAvailable && MockDataService.isEnabled {
                    demoBanner
                }
                phasePill
                FlightPhaseAnimationView(phase: tracker.snapshot.phase, height: 170)
                destinationClock
                if let origin = displayOriginIATA, let dest = displayDestinationIATA {
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
        .onAppear {
            // Provide flight context so takeoff/landing milestones can prompt the
            // traveler to text loved ones with the right details.
            tracker.activeFlightNumber = flightNumber
            tracker.activeDestinationCity = destinationCity ?? displayDestinationIATA
            // Auto-start in demo mode so the screen shows live values immediately.
            if !tracker.isTracking && !tracker.isAvailable && MockDataService.isEnabled {
                tracker.start()
                didAutoStartDemoTracking = true
            }
        }
        .onDisappear {
            // Clear the flight context we set so stale details don't drive
            // later loved-ones prompts after navigating away.
            tracker.activeFlightNumber = nil
            tracker.activeDestinationCity = nil
            // Stop only the demo tracking this view auto-started.
            if didAutoStartDemoTracking {
                tracker.stop()
                didAutoStartDemoTracking = false
            }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.yellow)
            Text("DEMO MODE — simulated cruise data")
                .font(.system(size: 10, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 0.5)
        )
    }

    /// In demo mode, fall back to the seeded Tokyo trip's route (JFK → NRT)
    /// when no explicit origin/destination was passed in.
    private var displayOriginIATA: String? {
        originIATA ?? (MockDataService.isEnabled ? "JFK" : nil)
    }
    private var displayDestinationIATA: String? {
        destinationIATA ?? (MockDataService.isEnabled ? "NRT" : nil)
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

    // MARK: - Destination local time

    /// The arrival airport's time zone. Falls back to the seeded Tokyo demo
    /// route (NRT → Asia/Tokyo) when nothing explicit was passed in.
    private var resolvedDestinationTimeZone: TimeZone? {
        if let id = destinationTimeZoneID, let tz = TimeZone(identifier: id) { return tz }
        if MockDataService.isEnabled { return TimeZone(identifier: "Asia/Tokyo") }
        return nil
    }

    /// Ticks once a second, showing the current wall-clock time at the
    /// destination. Hidden when no time zone can be resolved.
    @ViewBuilder
    private var destinationClock: some View {
        if let tz = resolvedDestinationTimeZone {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 14) {
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LOCAL TIME · \(displayDestinationIATA ?? "ARRIVAL")")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.5)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        Text(destinationTimeString(at: context.date, in: tz))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text(timeZoneDifferenceNote(tz, at: context.date))
                            .font(.caption2)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .jetCard()
            }
        }
    }

    private func destinationTimeString(at date: Date, in tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        formatter.timeZone = tz
        return formatter.string(from: date)
    }

    /// "+13h vs home" style note comparing destination zone to the device zone.
    ///
    /// Both offsets are evaluated at `date` (the clock's current tick) via
    /// `secondsFromGMT(for:)` so the two zones are compared at the same instant.
    /// This keeps the difference correct across a DST boundary in either zone
    /// instead of silently using two independent "right now" offsets.
    private func timeZoneDifferenceNote(_ tz: TimeZone, at date: Date) -> String {
        let diffSeconds = tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard diffSeconds != 0 else { return "Same time zone as home" }
        let hours = Double(diffSeconds) / 3600
        let sign = hours > 0 ? "+" : "−"
        let absHours = abs(hours)
        let formatted = absHours == absHours.rounded()
            ? String(format: "%.0f", absHours)
            : String(format: "%.1f", absHours)
        return "\(sign)\(formatted)h vs home"
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
                    Text("Move to a window seat for live GPS position. A lock can take a few minutes at altitude, and may not be possible away from a window.")
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
            // A manual toggle takes ownership of tracking away from the
            // auto-started demo lifecycle, so onDisappear must no longer
            // stop tracking on the user's behalf.
            didAutoStartDemoTracking = false
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
            Label("Continuous GPS tracking is battery-intensive — expect noticeably faster drain, varying by device.", systemImage: "battery.50")
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
