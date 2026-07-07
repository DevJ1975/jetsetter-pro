// File: Core/Services/AudioAlertService.swift
//
// Plays short attention-grabbing sounds for time-critical travel events
// (gate closing soon, missed check-in window, disruption alerts). Uses
// AudioServices for system-provided "alert" sounds so no bundled audio
// resources are required.

import AudioToolbox
import AVFoundation
import Foundation

@MainActor
final class AudioAlertService {

    static let shared = AudioAlertService()

    /// Tracks alerts we've already played, keyed by the opaque alert key and
    /// stamped with the time we fired it. Persisted to `UserDefaults` so a
    /// genuinely once-only alert (e.g. a dismissed "gate closing" ding or a
    /// missed check-in window) does NOT re-alarm the user on a cold start /
    /// singleton recreation for an event they already acknowledged this trip.
    ///
    /// Entries older than `retention` are pruned on load so the store can't grow
    /// without bound and stale flights eventually stop suppressing new alerts.
    private var firedAlerts: [String: Date] = [:]

    /// How long a fired-alert record stays authoritative. Sized to comfortably
    /// cover a single itinerary's window without permanently muting a reused key.
    private let retention: TimeInterval = 48 * 60 * 60

    private let storageKey = "jetsetter_audio_fired_alerts"

    private init() {
        loadFiredAlerts()
    }

    /// Plays the configured ding for the given alert key, but only once
    /// unless explicitly reset — now including across app relaunches. The key is
    /// opaque — typically a composite of alert type + flight number.
    func playOnce(key: String, kind: AlertSound = .gateClosing) {
        guard firedAlerts[key] == nil else { return }
        firedAlerts[key] = Date()
        persistFiredAlerts()
        play(kind)
    }

    /// Forces playback regardless of dedup state.
    func play(_ kind: AlertSound) {
        configureAudioSession()
        // Use alert-style playback: vibrates and respects ringer/silent rules.
        AudioServicesPlayAlertSound(kind.systemSoundID)
    }

    /// Clears the played-alert cache so the same key can fire again.
    func reset(key: String) {
        firedAlerts.removeValue(forKey: key)
        persistFiredAlerts()
    }

    func resetAll() {
        firedAlerts.removeAll()
        persistFiredAlerts()
    }

    // MARK: - Persistence

    /// Loads fired-alert keys, dropping any that have aged past `retention`.
    private func loadFiredAlerts() {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        firedAlerts = raw.reduce(into: [:]) { result, entry in
            let date = Date(timeIntervalSince1970: entry.value)
            if date >= cutoff { result[entry.key] = date }
        }
        // If pruning dropped anything, rewrite the compacted store.
        if firedAlerts.count != raw.count { persistFiredAlerts() }
    }

    private func persistFiredAlerts() {
        let encoded = firedAlerts.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    // MARK: - Audio Session

    private var sessionConfigured = false

    private func configureAudioSession() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        // .ambient + mixWithOthers means we don't pause the user's music.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

// MARK: - Alert sound catalog

enum AlertSound {
    case gateClosing      // urgent ding — boarding window closing
    case checkInOpen      // friendly chime — check-in just opened
    case disruption       // serious alert — flight cancelled/delayed
    case generic          // lightweight tap

    /// Built-in iOS system sound IDs. Each is short (< 1s) and audible without
    /// shipping a custom audio file.
    var systemSoundID: SystemSoundID {
        switch self {
        case .gateClosing:  return 1304  // Sherwood Forest — attention-grabbing alert
        case .checkInOpen:  return 1013  // Tweet — friendly chime
        case .disruption:   return 1005  // New Mail — distinctive
        case .generic:      return 1057  // Tink — light tap
        }
    }
}
