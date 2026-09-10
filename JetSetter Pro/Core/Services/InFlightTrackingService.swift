// File: Core/Services/InFlightTrackingService.swift
//
// Fuses CMAltimeter (barometric altitude), CMMotionManager (accelerometer),
// and CLLocationManager (GPS) to produce a live in-flight snapshot. Detects
// flight phase transitions on-device — works in airplane mode for altitude
// + acceleration; GPS lights up when the user has a window seat.

import Foundation
import CoreMotion
import CoreLocation
import Combine

// MARK: - Live snapshot

struct InFlightSnapshot {
    /// Altitude above takeoff in meters. Derived from barometric pressure delta
    /// (more accurate than GPS at high altitudes).
    var altitudeMeters: Double
    /// Ground speed in m/s. Only valid when GPS is locked.
    var groundSpeedMps: Double
    /// Heading in degrees (0–360). Only valid when GPS is locked.
    var heading: Double?
    /// Current location. Only present when GPS is locked.
    var coordinate: CLLocationCoordinate2D?
    /// True when CLLocationManager has a recent fix (< 30s old).
    var hasGPSFix: Bool
    /// Vertical speed in m/s (positive = climbing).
    var verticalSpeedMps: Double
    /// Current detected phase.
    var phase: FlightPhase
    /// Time at which `phase` was entered.
    var phaseEnteredAt: Date

    static let initial = InFlightSnapshot(
        altitudeMeters: 0,
        groundSpeedMps: 0,
        heading: nil,
        coordinate: nil,
        hasGPSFix: false,
        verticalSpeedMps: 0,
        phase: .parked,
        phaseEnteredAt: Date()
    )

    // MARK: - Display helpers

    var altitudeFeet: Int { Int(altitudeMeters * 3.28084) }
    var groundSpeedKnots: Int { Int(groundSpeedMps * 1.94384) }
    var groundSpeedMph: Int { Int(groundSpeedMps * 2.23694) }
    var verticalSpeedFpm: Int { Int(verticalSpeedMps * 196.85) }
}

// MARK: - Flight phase

enum FlightPhase: String, Codable {
    case parked, taxi, takeoffRoll, climb, cruise, descent, finalApproach, landing, arrived

    var label: String {
        switch self {
        case .parked:        return "At gate"
        case .taxi:          return "Taxiing"
        case .takeoffRoll:   return "Takeoff roll"
        case .climb:         return "Climbing"
        case .cruise:        return "Cruising"
        case .descent:       return "Descending"
        case .finalApproach: return "Final approach"
        case .landing:       return "Landing"
        case .arrived:       return "Arrived"
        }
    }

    var systemImage: String {
        switch self {
        case .parked, .arrived: return "airplane"
        case .taxi:             return "airplane.up.right"
        case .takeoffRoll:      return "airplane.departure"
        case .climb:            return "airplane.up.right"
        case .cruise:           return "airplane"
        case .descent:          return "airplane.up.right"
        case .finalApproach:    return "airplane.arrival"
        case .landing:          return "airplane.arrival"
        }
    }

    var isAirborne: Bool {
        switch self {
        case .climb, .cruise, .descent, .finalApproach: return true
        default: return false
        }
    }
}

// MARK: - Service

@MainActor
final class InFlightTrackingService: NSObject, ObservableObject {

    static let shared = InFlightTrackingService()

    @Published private(set) var snapshot: InFlightSnapshot = .initial
    @Published private(set) var isTracking: Bool = false
    @Published var lastError: String?

    /// Optional flight context, set by the screen that starts tracking. Lets the
    /// takeoff/landing phase transitions prompt the traveler to text loved ones
    /// with the right flight number and destination woven in.
    var activeFlightNumber: String?
    var activeDestinationCity: String?

    // Hardware
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    // State
    private var baselinePressure: Double?
    private var lastAltitudeSample: (altitude: Double, at: Date)?
    private var accelMagnitudeAverage: Double = 1.0  // 1 g at rest
    private var lastLocationAt: Date = .distantPast

    // One-shot latches so milestone side effects (chime + loved-ones prompt) fire at
    // most once per tracking session, even if noisy sensor data bounces the phase.
    private var didFireTakeoff = false
    private var didFireArrival = false

    /// A GPS fix is considered "live" for this long after the last update. Once it
    /// ages out we stop advertising GPS LOCKED and treat coordinate/groundSpeed as stale.
    private let gpsFixMaxAge: TimeInterval = 30

    /// Re-emits the snapshot on a cadence so `hasGPSFix` flips to false (and GPS-derived
    /// fields go stale) when CLLocation stops delivering updates, e.g. after signal loss.
    private var freshnessTimer: Task<Void, Never>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100  // ~328 ft — plenty at cruise speed
    }

    // MARK: - Capability

    var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    // MARK: - Start / stop

    func start() {
        guard !isTracking else { return }
        isTracking = true
        lastError = nil

        // Reset baseline so this trip starts at "0m above takeoff".
        baselinePressure = nil
        snapshot = .initial
        didFireTakeoff = false
        didFireArrival = false

        startAltimeter()
        startMotion()
        startLocation()
        startFreshnessTimer()
    }

    // MARK: - GPS freshness

    /// Lightweight repeating tick that ages out a stale GPS fix. Without this,
    /// `hasGPSFix` would stay true forever after the last location update — the
    /// old position/speed would keep reading as a live "GPS LOCKED" fix.
    private func startFreshnessTimer() {
        freshnessTimer?.cancel()
        freshnessTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await MainActor.run { [weak self] in
                    guard let self, self.isTracking else { return }
                    self.refreshGPSFreshness()
                }
            }
        }
    }

    /// Recomputes `hasGPSFix` from the age of the last location update and re-runs
    /// phase detection so GPS-derived transitions don't rely on stale speed.
    private func refreshGPSFreshness() {
        let fresh = Date().timeIntervalSince(lastLocationAt) < gpsFixMaxAge
        if snapshot.hasGPSFix != fresh {
            snapshot.hasGPSFix = fresh
        }
        // When the fix has aged out, GPS ground speed is no longer trustworthy.
        // Zero it so phase detection falls back to the barometer/accelerometer path.
        if !fresh && snapshot.groundSpeedMps != 0 {
            snapshot.groundSpeedMps = 0
        }
        recomputePhase()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopAccelerometerUpdates()
        locationManager.stopUpdatingLocation()
        freshnessTimer?.cancel()
        freshnessTimer = nil
    }

    // MARK: - Altimeter

    private func startAltimeter() {
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            Task { @MainActor in self.processAltitude(data) }
        }
    }

    private func processAltitude(_ data: CMAltitudeData) {
        let pressure = data.pressure.doubleValue
        if baselinePressure == nil { baselinePressure = pressure }

        // Relative altitude from CMAltimeter is already "above start"
        let altitude = data.relativeAltitude.doubleValue

        // Vertical speed via derivative.
        let now = Date()
        let vSpeed: Double
        if let last = lastAltitudeSample {
            let dt = now.timeIntervalSince(last.at)
            // Clustered/back-to-back altimeter samples (dt <= 0.1s) yield an unstable
            // derivative. Skip them entirely rather than latching a stale vSpeed, which
            // would keep feeding a phantom climb/descent reading into phase detection.
            guard dt > 0.1 else { return }
            vSpeed = (altitude - last.altitude) / dt
        } else {
            vSpeed = 0
        }
        lastAltitudeSample = (altitude, now)

        snapshot.altitudeMeters = altitude
        snapshot.verticalSpeedMps = vSpeed
        recomputePhase()
    }

    // MARK: - Motion (accelerometer)

    private func startMotion() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.5
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in self.processAcceleration(data) }
        }
    }

    private func processAcceleration(_ data: CMAccelerometerData) {
        // Total acceleration magnitude in g; at rest this is ~1.0 due to gravity.
        let mag = sqrt(data.acceleration.x * data.acceleration.x
                       + data.acceleration.y * data.acceleration.y
                       + data.acceleration.z * data.acceleration.z)
        // Low-pass filter so transient bumps don't trigger takeoff detection.
        accelMagnitudeAverage = accelMagnitudeAverage * 0.85 + mag * 0.15
        // Acceleration is a phase cue (taxi -> takeoffRoll keys off `acceleratingHard`),
        // so re-run detection here too. Otherwise, on a device with no altimeter and no
        // GPS fix, phase would never advance despite live accelerometer data.
        recomputePhase()
    }

    // MARK: - Location

    private func startLocation() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }

    // MARK: - Phase detection

    private func recomputePhase() {
        let alt = snapshot.altitudeMeters
        let vs = snapshot.verticalSpeedMps
        let oldPhase = snapshot.phase

        // GPS ground speed is only trustworthy when we have a live fix. In airplane
        // mode (a supported scenario) GPS is off, so `groundSpeedMps` stays 0 and must
        // NOT gate any transition — otherwise the phase stays `.parked` forever and the
        // takeoff/landing chimes + loved-ones prompts never fire. Treat speed as an
        // optional refinement and drive climb/descent from the barometer + accelerometer.
        let hasSpeed = snapshot.hasGPSFix
        let speed = snapshot.groundSpeedMps

        // Barometer/accelerometer-derived motion cues (work without GPS).
        let climbing = vs > 2.0
        let descending = vs < -2.0
        let leveling = abs(vs) < 1.0
        let acceleratingHard = accelMagnitudeAverage > 1.15

        let newPhase: FlightPhase
        switch oldPhase {
        case .parked:
            // Leave the gate on GPS taxi speed, or on a sustained altitude/climb cue
            // when GPS is unavailable (airplane mode straight into pushback + takeoff).
            if hasSpeed && speed > 2.5 { newPhase = .taxi }
            else if alt > 3 || climbing { newPhase = .taxi }
            else { newPhase = .parked }
        case .taxi:
            // Takeoff: prefer GPS (speed + forward accel) when locked; otherwise use the
            // barometer — a real climb (rising altitude + positive vertical speed),
            // corroborated by sustained forward acceleration.
            if hasSpeed && speed > 22 && acceleratingHard { newPhase = .takeoffRoll }
            else if (climbing || alt > 15) && acceleratingHard { newPhase = .takeoffRoll }
            else if hasSpeed && speed < 1 && alt < 5 { newPhase = .parked }
            else if !hasSpeed && alt < 2 && leveling { newPhase = .parked }
            else { newPhase = .taxi }
        case .takeoffRoll:
            if vs > 2.0 || alt > 30 { newPhase = .climb }
            else { newPhase = .takeoffRoll }
        case .climb:
            if alt > 7500 && abs(vs) < 1.5 { newPhase = .cruise }
            else if descending && alt < 5000 { newPhase = .descent }
            else { newPhase = .climb }
        case .cruise:
            if descending { newPhase = .descent }
            else { newPhase = .cruise }
        case .descent:
            // Once descending, don't silently revert to .cruise on a brief level-off:
            // real descents step down and hold at intermediate altitudes, where vSpeed
            // momentarily hits ~0 above 5000m. Reverting would flap descent<->cruise,
            // resetting phaseEnteredAt and corrupting time-in-phase. Progress forward only.
            if alt < 1500 { newPhase = .finalApproach }
            else { newPhase = .descent }
        case .finalApproach:
            // Touchdown: GPS confirms high ground speed when available; without GPS,
            // a low, still-descending altitude drives the landing transition.
            if alt < 30 && hasSpeed && speed > 22 { newPhase = .landing }
            else if alt < 30 && !hasSpeed && (descending || vs < 0) { newPhase = .landing }
            else { newPhase = .finalApproach }
        case .landing:
            // Arrival: GPS shows the aircraft slowing to a stop; without GPS, a settled
            // (leveled) low altitude marks rollout complete.
            if hasSpeed && speed < 8 && alt < 10 { newPhase = .arrived }
            else if !hasSpeed && alt < 10 && leveling { newPhase = .arrived }
            else { newPhase = .landing }
        case .arrived:
            newPhase = .arrived
        }

        if newPhase != oldPhase {
            snapshot.phase = newPhase
            snapshot.phaseEnteredAt = Date()
            handlePhaseTransition(from: oldPhase, to: newPhase)
        }
    }

    private func handlePhaseTransition(from old: FlightPhase, to new: FlightPhase) {
        // Hook for analytics / notifications. Audio chime on takeoff and landing,
        // plus a prompt to text loved ones at each milestone.
        switch new {
        case .takeoffRoll:
            // Latch: fire the chime + loved-ones prompt only once per session so a
            // spurious re-entry (sensor noise near the threshold) can't re-notify family.
            guard !didFireTakeoff else { break }
            didFireTakeoff = true
            AudioAlertService.shared.play(.generic)
            promptLovedOnes(.takeoff)
            // Reflect departure on any running flight Live Activity (no-op if none).
            FlightLiveActivityService.shared.update(status: .departed, estimatedDeparture: Date())
        case .arrived:
            guard !didFireArrival else { break }
            didFireArrival = true
            AudioAlertService.shared.play(.checkInOpen)
            promptLovedOnes(.landing)
            // Flight's done — dismiss the Live Activity from the Lock Screen.
            FlightLiveActivityService.shared.end()
        default: break
        }
    }

    private func promptLovedOnes(_ event: LovedOnesEvent) {
        // Require valid flight context. If the tracking screen isn't active (context
        // was cleared on navigate-away, or tracking started elsewhere), we'd otherwise
        // send a milestone with a nil flight number/destination — a spurious, context-
        // free message. Better to stay silent than text family the wrong thing.
        guard let flightNumber = activeFlightNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !flightNumber.isEmpty else { return }
        let destinationCity = activeDestinationCity?.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await NotificationManager.shared.notifyLovedOnes(
                event: event,
                flightNumber: flightNumber,
                destinationCity: destinationCity
            )
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension InFlightTrackingService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // A negative horizontalAccuracy means the coordinate is invalid — ignore it
        // so we never advertise a bogus fix.
        guard location.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            self.snapshot.coordinate = location.coordinate
            self.snapshot.groundSpeedMps = max(0, location.speed)
            self.snapshot.heading = location.course >= 0 ? location.course : nil
            self.lastLocationAt = Date()
            // Derive freshness from the timestamp rather than latching true forever.
            self.snapshot.hasGPSFix = Date().timeIntervalSince(self.lastLocationAt) < self.gpsFixMaxAge
            self.recomputePhase()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "GPS unavailable. Window seat needed for live position."
        }
    }
}
