// File: Core/Services/Announcements/AnnouncementSettings.swift
//
// The traveler's choice of how flight alerts sound: a chime plus a spoken
// announcement (the default), the chime alone, or the standard iOS sound.
//
// Stored in UserDefaults under one key so `AnnouncementSettingsView` can bind
// to it with `@AppStorage`, and notification code can read it off the main
// actor while it schedules alerts. An unknown or missing value reads as the
// default, so a value written by a future build never silences alerts.

import Foundation

nonisolated enum VoiceAnnouncementMode: String, CaseIterable, Identifiable, Sendable {
    case chimeAndVoice
    case chimeOnly
    case off

    static let `default`: VoiceAnnouncementMode = .chimeAndVoice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chimeAndVoice: return "Chime and voice"
        case .chimeOnly:     return "Chime only"
        case .off:           return "Off"
        }
    }

    /// One line under the picker saying what the traveler will hear.
    var detail: String {
        switch self {
        case .chimeAndVoice:
            return "A cabin chime, then a spoken announcement such as “Your gate has changed. Delta flight fourteen twenty-three now departs from gate C twenty-two.”"
        case .chimeOnly:
            return "A cabin chime for alerts and a boarding chime for boarding, with no voice."
        case .off:
            return "Flight alerts use the standard iOS notification sound."
        }
    }
}

nonisolated enum AnnouncementSettings {

    /// UserDefaults key for `VoiceAnnouncementMode.rawValue`.
    static let voiceAnnouncementsKey = "pref_voiceAnnouncements"

    /// The stored mode, or `.chimeAndVoice` when nothing valid is stored.
    static func voiceAnnouncements(in defaults: UserDefaults = .standard) -> VoiceAnnouncementMode {
        defaults.string(forKey: voiceAnnouncementsKey)
            .flatMap(VoiceAnnouncementMode.init(rawValue:)) ?? .default
    }

    static func setVoiceAnnouncements(_ mode: VoiceAnnouncementMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: voiceAnnouncementsKey)
    }
}
