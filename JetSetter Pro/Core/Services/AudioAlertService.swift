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
    private init() {}

    /// Tracks alerts we've already played in this session so the ding doesn't
    /// retrigger every time Travel Intelligence re-evaluates (every 60s).
    private var firedAlerts: Set<String> = []

    /// Plays the configured ding for the given alert key, but only once per
    /// session unless explicitly reset. The key is opaque — typically a
    /// composite of alert type + flight number.
    func playOnce(key: String, kind: AlertSound = .gateClosing) {
        guard !firedAlerts.contains(key) else { return }
        firedAlerts.insert(key)
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
        firedAlerts.remove(key)
    }

    func resetAll() {
        firedAlerts.removeAll()
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
