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

    // Hardware
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    // State
    private var baselinePressure: Double?
    private var lastAltitudeSample: (altitude: Double, at: Date)?
    private var accelMagnitudeAverage: Double = 1.0  // 1 g at rest
    private var lastLocationAt: Date = .distantPast

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
        guard isAvailable else {
            lastError = "Barometric altitude not available on this device."
            return
        }
        isTracking = true
        lastError = nil

        // Reset baseline so this trip starts at "0m above takeoff".
        baselinePressure = nil
        snapshot = .initial

        startAltimeter()
        startMotion()
        startLocation()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopAccelerometerUpdates()
        locationManager.stopUpdatingLocation()
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

        // Vertical speed via derivative
        let now = Date()
        let vSpeed: Double
        if let last = lastAltitudeSample {
            let dt = now.timeIntervalSince(last.at)
            vSpeed = dt > 0.1 ? (altitude - last.altitude) / dt : snapshot.verticalSpeedMps
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
        let speed = snapshot.groundSpeedMps
        let vs = snapshot.verticalSpeedMps
        let oldPhase = snapshot.phase

        let newPhase: FlightPhase
        switch oldPhase {
        case .parked:
            if speed > 2.5 { newPhase = .taxi } else { newPhase = .parked }
        case .taxi:
            // Forward acceleration sustained + speed > 22 m/s (~50 mph) → takeoff
            if speed > 22 && accelMagnitudeAverage > 1.15 { newPhase = .takeoffRoll }
            else if speed < 1 && alt < 5 { newPhase = .parked }
            else { newPhase = .taxi }
        case .takeoffRoll:
            if vs > 2.0 || alt > 30 { newPhase = .climb }
            else { newPhase = .takeoffRoll }
        case .climb:
            if alt > 7500 && abs(vs) < 1.5 { newPhase = .cruise }
            else if vs < -2.0 && alt < 5000 { newPhase = .descent }
            else { newPhase = .climb }
        case .cruise:
            if vs < -2.0 { newPhase = .descent }
            else { newPhase = .cruise }
        case .descent:
            if alt < 1500 { newPhase = .finalApproach }
            else if abs(vs) < 1.0 && alt > 5000 { newPhase = .cruise }
            else { newPhase = .descent }
        case .finalApproach:
            if alt < 30 && speed > 22 { newPhase = .landing }
            else { newPhase = .finalApproach }
        case .landing:
            if speed < 8 && alt < 10 { newPhase = .arrived }
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
        // Hook for analytics / notifications. Audio chime on takeoff and landing.
        switch new {
        case .takeoffRoll: AudioAlertService.shared.play(.generic)
        case .arrived:     AudioAlertService.shared.play(.checkInOpen)
        default: break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension InFlightTrackingService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.snapshot.coordinate = location.coordinate
            self.snapshot.groundSpeedMps = max(0, location.speed)
            self.snapshot.heading = location.course >= 0 ? location.course : nil
            self.snapshot.hasGPSFix = true
            self.lastLocationAt = Date()
            self.recomputePhase()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "GPS unavailable. Window seat needed for live position."
        }
    }
}
