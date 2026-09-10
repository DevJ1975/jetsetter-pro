// File: Features/Intelligence/IntelligenceHistoryView.swift

import SwiftUI

struct IntelligenceHistoryView: View {

    @State private var active: [TravelSuggestion] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                if !active.isEmpty {
                    section(title: "ACTIVE NOW") {
                        ForEach(active) { suggestion in
                            activeRow(suggestion)
                        }
                    }
                }

                if active.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                        Text("Nothing to suggest right now")
                            .font(.headline)
                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                        Text("Check-in windows, leave-by times, packing and visa reminders appear here and on Home as your trips approach.")
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Proactive Intelligence")
        .navigationBarTitleDisplayMode(.large)
        .task { active = ProactiveSuggestions.shared.evaluateAll() }
    }

    private func activeRow(_ suggestion: TravelSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.accent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: suggestion.kind.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(JetsetterTheme.Colors.success)
                        .clipShape(Capsule())
                }
                Text(suggestion.body)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(JetsetterTheme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.leading, 4)
            VStack(spacing: 10) { content() }
        }
    }
}
