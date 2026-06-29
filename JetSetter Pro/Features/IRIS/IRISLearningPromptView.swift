// File: Features/IRIS/IRISLearningPromptView.swift
//
// First-run opt-in for the learning layer. Shown once (gated by
// UserPreferences.hasSeenLearningPrompt). Accepting turns on learning + all
// sources; declining leaves everything off. Either way the prompt won't reappear.

import SwiftUI

struct IRISLearningPromptView: View {

    @EnvironmentObject private var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(JetsetterTheme.Colors.goldGradient)
                .padding(.bottom, 20)

            Text("Let IRIS learn your travel style")
                .font(JetsetterTheme.Typography.pageTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                .padding(.horizontal, 24)

            Text("With your permission, IRIS notices the seats you pick, the airlines you fly, the receipts you scan, and the places you go — to anticipate what you need and personalize every trip.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                bullet("lock.fill", "Stays on your device — never shared.")
                bullet("slider.horizontal.3", "Turn any source on or off in Settings.")
                bullet("trash", "Wipe everything anytime.")
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    preferences.learnFromReceipts = true
                    preferences.learnFromTrips = true
                    preferences.learnFromCheckIns = true
                    preferences.learningEnabled = true
                    preferences.hasSeenLearningPrompt = true
                    TravelProfileStore.shared.recompute()
                    dismiss()
                } label: {
                    Text("Enable Learning")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    preferences.hasSeenLearningPrompt = true
                    dismiss()
                } label: {
                    Text("Not Now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(JetsetterTheme.Colors.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Spacer()
        }
    }
}

#Preview {
    IRISLearningPromptView().environmentObject(UserPreferences.shared)
}
