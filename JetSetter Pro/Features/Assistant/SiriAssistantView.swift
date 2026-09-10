// File: Features/Assistant/SiriAssistantView.swift
//
// The assistant tab. JetSetter Pro's assistant is Siri: every action is an App
// Intent, so travelers ask Siri (or Spotlight, Shortcuts, the Action button)
// and the app answers or opens the right screen. This screen teaches the
// phrases, surfaces the app's proactive suggestions, and shows what the app has
// learned — all of which stays on this iPhone.
//
// Presented inside a NavigationStack by its caller (the tab in ContentView, or
// a push from More), so it declares none of its own.

import SwiftUI
import AppIntents

struct SiriAssistantView: View {

    @Environment(UserPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router
    @State private var suggestions = ProactiveSuggestions.shared
    @State private var active: [TravelSuggestion] = []
    @State private var showLearningPrompt = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if !active.isEmpty { suggestionsSection }
                phrasesSection
                knowledgeSection
                onDeviceSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Siri")
        .navigationBarTitleDisplayMode(.large)
        .task {
            active = suggestions.evaluateAll()
            // One-time opt-in for on-device learning, shown here (where it's
            // relevant) rather than over the first Home screen.
            if preferences.hasCompletedOnboarding && !preferences.hasSeenLearningPrompt {
                showLearningPrompt = true
            }
        }
        .refreshable { active = suggestions.evaluateAll() }
        .sheet(isPresented: $showLearningPrompt) { LearningPromptView() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(JetsetterTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just ask Siri")
                        .font(JetsetterTheme.Typography.pageTitle)
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("Every JetSetter action works by voice, from the Lock Screen too.")
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RIGHT NOW", icon: "bolt.fill")
            ForEach(active) { suggestion in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: suggestion.kind.systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .frame(width: 36, height: 36)
                        .background(JetsetterTheme.Colors.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text(suggestion.body)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        HStack(spacing: 10) {
                            Button("Open") {
                                TravelProfileStore.shared.recordSuggestionFeedback(kind: suggestion.kind.rawValue, accepted: true)
                                router.navigate(to: suggestion.action)
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(JetsetterTheme.Colors.accent)
                            Button("Not now") {
                                suggestions.dismiss(suggestion)
                                TravelProfileStore.shared.recordSuggestionFeedback(kind: suggestion.kind.rawValue, accepted: false)
                                active = suggestions.evaluateAll()
                            }
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .jetCard()
            }
        }
    }

    // MARK: - Phrases

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("THINGS TO ASK", icon: "waveform")
            VStack(spacing: 10) {
                SiriTipView(intent: NextFlightIntent())
                SiriTipView(intent: CheckInIntent())
                SiriTipView(intent: LogExpenseIntent())
                SiriTipView(intent: DepartureBriefingIntent())
                SiriTipView(intent: GeneratePackingListIntent())
                SiriTipView(intent: DestinationWeatherIntent())
                SiriTipView(intent: BagStatusIntent())
                SiriTipView(intent: ConvertCurrencyIntent())
            }
            Text("Siri also understands “Remember that I prefer aisle seats in JetSetter Pro” and “Text my loved ones that I've landed in JetSetter Pro.”")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
    }

    // MARK: - What the app knows

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("WHAT JETSETTER KNOWS", icon: "brain.head.profile")
            VStack(spacing: 0) {
                NavigationLink { LearnedProfileView() } label: {
                    row("Learned travel style", subtitle: preferences.learningEnabled ? "From your own trips, on this iPhone" : "Learning is off", icon: "sparkles.rectangle.stack")
                }
                Divider().padding(.leading, 44)
                NavigationLink { TravelerMemoryView() } label: {
                    row("Saved preferences", subtitle: "Seats, diet, hotels — things you asked it to remember", icon: "bookmark.fill")
                }
            }
            .padding(.vertical, 4)
            .jetCard()
        }
    }

    // MARK: - On-device intelligence

    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ON THIS IPHONE", icon: "lock.shield.fill")
            VStack(alignment: .leading, spacing: 8) {
                bullet("Packing lists written by Apple Intelligence from the forecast and your plans.")
                bullet("Local picks ranked for you from Apple Maps.")
                bullet("Receipts read and categorized without leaving the phone.")
                bullet("No account, no cloud copy of your trips.")
            }
            .padding(14)
            .jetCard()
        }
    }

    // MARK: - Pieces

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.bold())
            Text(title).font(JetsetterTheme.Typography.label).tracking(1.5)
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
        .padding(.leading, 4)
    }

    private func row(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(JetsetterTheme.Colors.success)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { SiriAssistantView() }
        .environment(UserPreferences.shared)
        .environment(AppRouter.shared)
}
