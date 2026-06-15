// File: Features/Intelligence/IntelligenceHistoryView.swift

import SwiftUI

struct IntelligenceHistoryView: View {

    @State private var active: [IRISSuggestion] = []
    private let history: [HistoryEntry] = HistoryEntry.demoHistory

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

                section(title: "RECENT ACTIONS") {
                    ForEach(history) { entry in
                        historyRow(entry)
                    }
                }
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Proactive Intelligence")
        .navigationBarTitleDisplayMode(.large)
        .task { active = IRISTriggers.shared.evaluateAll() }
    }

    private func activeRow(_ suggestion: IRISSuggestion) -> some View {
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

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: entry.colorHex).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: entry.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: entry.colorHex))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Spacer()
                    Text(entry.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Text(entry.outcome)
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

private struct HistoryEntry: Identifiable {
    let id = UUID()
    let icon: String
    let colorHex: String
    let title: String
    let outcome: String
    let timeAgo: String

    static let demoHistory: [HistoryEntry] = [
        HistoryEntry(icon: "checkmark.seal.fill", colorHex: "#1DB97D",
                     title: "Check-in reminder",
                     outcome: "You checked into DL2241 BOS→ORD",
                     timeAgo: "Yesterday"),
        HistoryEntry(icon: "exclamationmark.triangle.fill", colorHex: "#E84040",
                     title: "Gate change detected",
                     outcome: "AA169 moved B22 → B14 · acknowledged",
                     timeAgo: "2h ago"),
        HistoryEntry(icon: "cloud.rain.fill", colorHex: "#3B9EF0",
                     title: "Rain in destination",
                     outcome: "Added compact umbrella to packing list",
                     timeAgo: "3d ago"),
        HistoryEntry(icon: "clock.badge.checkmark.fill", colorHex: "#7B3FBF",
                     title: "Leave-now alert",
                     outcome: "Departed for BOS 12 min before optimal window",
                     timeAgo: "2d ago"),
        HistoryEntry(icon: "doc.text.fill", colorHex: "#0066CC",
                     title: "Visa check",
                     outcome: "Japan eVisa confirmed valid until 2027",
                     timeAgo: "1w ago"),
        HistoryEntry(icon: "crown.fill", colorHex: "#C8860A",
                     title: "Tier-at-risk alert",
                     outcome: "Booked Park Hyatt Tokyo to renew Marriott Titanium",
                     timeAgo: "1w ago")
    ]
}

#Preview {
    NavigationStack {
        IntelligenceHistoryView()
    }
}
