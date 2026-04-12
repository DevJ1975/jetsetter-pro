// File: Features/Intelligence/TravelIntelligenceCardView.swift
// The proactive intelligence card surfaced at the top of HomeView.
// One card at a time, dismissible, context-aware (Feature 6).

import SwiftUI

struct TravelIntelligenceCardView: View {

    @ObservedObject var vm: TravelIntelligenceViewModel

    var body: some View {
        if let card = vm.activeCard {
            intelligenceCard(card)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
        }
    }

    private func intelligenceCard(_ card: ProactiveTrigger) -> some View {
        HStack(spacing: 14) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(Color(hex: card.type.colorHex).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: card.type.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: card.type.colorHex))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(card.body)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Action / Dismiss
            VStack(spacing: 6) {
                if let actionLabel = card.actionLabel {
                    Button { vm.actOnCard() } label: {
                        Text(actionLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(hex: card.type.colorHex))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button { vm.dismissActiveCard() } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .jetCard()
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    let vm = TravelIntelligenceViewModel()
    // Inject a sample trigger for preview
    return TravelIntelligenceCardView(vm: vm)
        .padding(.top, 20)
}
