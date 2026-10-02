// File: Core/Services/Announcements/AnnouncementCenter.swift
//
// The one place notification and in-app code ask for an announcement's sound.
// It applies the traveler's Voice Announcements setting, so callers never
// branch on it themselves:
//
//     content.sound = await AnnouncementCenter.sound(for: .gateChange(airline: "DL", flight: "1423", gate: "C22"))
//
//   • Chime and voice: the composed file from `AnnouncementComposer`, falling
//     back to the plain chime if composing fails.
//   • Chime only: `cabin_chime.caf`, or `boarding.caf` for boarding events.
//   • Off: the system default sound.
//
// `play(_:)` speaks the same file in the app, for an alert the app raises while
// it's open. It uses the `.ambient` session category with `.mixWithOthers`, so
// the ring/silent switch silences it and the traveler's podcast keeps playing
// underneath. It is debounced, because a disruption poll and a foreground
// refresh can report the same gate change seconds apart.

import AVFoundation
import Foundation
import OSLog
import UserNotifications

@MainActor
enum AnnouncementCenter {

    private static let log = Logger(subsystem: "com.jetsetter.pro", category: "announcements")

    // MARK: - Notification sounds

    /// The notification sound for `announcement` under the current setting.
    ///
    /// - Parameter firesAt: when the notification will be delivered. Pass the
    ///   trigger date for alerts scheduled ahead (check-in opens, boarding in
    ///   30 minutes) so the composed file is kept until then. Nil for alerts
    ///   delivered now.
    ///
    /// `nonisolated` so an actor such as `CheckInService` can call it and get
    /// the (non-Sendable) sound back on its own executor.
    nonisolated static func sound(for announcement: Announcement, firesAt: Date? = nil) async -> UNNotificationSound {
        guard let name = await soundName(for: announcement, firesAt: firesAt) else { return .default }
        return UNNotificationSound(named: name)
    }

    /// The sound file name for `announcement`, or nil when the setting is Off
    /// and the system default should play.
    nonisolated static func soundName(for announcement: Announcement, firesAt: Date? = nil) async -> UNNotificationSoundName? {
        let chime = UNNotificationSoundName(AnnouncementScript.chimeSoundName(for: announcement))
        switch AnnouncementSettings.voiceAnnouncements() {
        case .off:
            return nil
        case .chimeOnly:
            return chime
        case .chimeAndVoice:
            let clips = AnnouncementScript.resolvedClips(for: announcement)
            guard let file = await AnnouncementComposer.shared.soundFileName(for: clips, neededUntil: firesAt) else {
                return chime
            }
            return UNNotificationSoundName(file)
        }
    }

    // MARK: - In-app playback

    /// How long the same announcement is suppressed after it plays.
    static let debounceWindow: TimeInterval = 120

    /// What the Settings "Play sample" button says: the demo trip's gate change.
    static let sampleAnnouncement = Announcement.gateChange(airline: "DL", flight: "1423", gate: "C22")

    private static var player: AVAudioPlayer?
    private static var recentlyPlayed: [String: Date] = [:]

    /// Plays `announcement` in the app under the current setting, at most once
    /// per `debounceWindow` for the same `dedupeKey`.
    ///
    /// - Parameter dedupeKey: identifies the alert, for example the disruption
    ///   event id. Defaults to the spoken words, so the same sentence can't play
    ///   twice in a row but a second delay with a new time still does.
    ///
    /// Don't call this for a notification the system is already presenting
    /// with `.sound`, or the traveler hears it twice.
    static func play(_ announcement: Announcement, dedupeKey: String? = nil) {
        let mode = AnnouncementSettings.voiceAnnouncements()
        guard mode != .off else { return }

        let clips = AnnouncementScript.resolvedClips(for: announcement)
        let key = dedupeKey ?? clips.joined(separator: ",")
        let now = Date()
        recentlyPlayed = recentlyPlayed.filter { now.timeIntervalSince($0.value) < debounceWindow }
        // Recorded before any await, so two calls in the same instant can't
        // both get through.
        guard recentlyPlayed[key] == nil else { return }
        recentlyPlayed[key] = now

        Task { await start(announcement, clips: clips, mode: mode) }
    }

    /// Plays the sample immediately, cutting off anything already playing.
    /// Not debounced, so the traveler can compare settings back to back.
    static func playSample() {
        let mode = AnnouncementSettings.voiceAnnouncements()
        player?.stop()
        guard mode != .off else { return }
        let clips = AnnouncementScript.resolvedClips(for: sampleAnnouncement)
        Task { await start(sampleAnnouncement, clips: clips, mode: mode) }
    }

    private static func start(_ announcement: Announcement, clips: [String], mode: VoiceAnnouncementMode) async {
        var url: URL?
        if mode == .chimeAndVoice {
            url = await AnnouncementComposer.shared.soundFileURL(for: clips)
        }
        if url == nil {
            let chime = AnnouncementScript.chime(for: announcement)
            url = Bundle.main.url(forResource: chime, withExtension: AnnouncementScript.fileExtension(for: chime))
        }
        guard let url else {
            log.error("No announcement or chime file to play")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            player?.stop()
            next.prepareToPlay()
            next.play()
            player = next
        } catch {
            log.error("Announcement playback failed: \(String(describing: error), privacy: .public)")
        }
    }
}
