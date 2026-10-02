// File: Features/Settings/AnnouncementSettingsView.swift
//
// Voice Announcements: choose whether flight alerts play a chime and a spoken
// announcement, the chime alone, or the standard iOS sound, and hear a sample.
//
// Self-contained so it can be linked from SettingsView with one
// NavigationLink. It binds straight to the UserDefaults key that
// `AnnouncementCenter` reads, so a change applies to the next alert scheduled.
// Alerts already scheduled keep the sound they were scheduled with.

import SwiftUI

struct AnnouncementSettingsView: View {

    @AppStorage(AnnouncementSettings.voiceAnnouncementsKey)
    private var mode: VoiceAnnouncementMode = .default

    var body: some View {
        Form {
            Section {
                Picker("Flight alert sound", selection: $mode) {
                    ForEach(VoiceAnnouncementMode.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .tint(JetsetterTheme.Colors.accent)
            } header: {
                Text("Flight alert sound")
            } footer: {
                Text(mode.detail)
            }

            Section {
                Button {
                    AnnouncementCenter.playSample()
                } label: {
                    Label("Play sample", systemImage: "speaker.wave.2.fill")
                        .foregroundStyle(mode == .off
                                         ? JetsetterTheme.Colors.textSecondary
                                         : JetsetterTheme.Colors.accent)
                }
                .disabled(mode == .off)
                .accessibilityHint("Plays a sample gate-change announcement")
            } footer: {
                Text(mode == .off
                     ? "There's no sample for the standard iOS sound."
                     : "The sample follows your ring/silent switch. Alerts that arrive with the phone on silent vibrate without sound.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Voice Announcements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AnnouncementSettingsView()
    }
}
