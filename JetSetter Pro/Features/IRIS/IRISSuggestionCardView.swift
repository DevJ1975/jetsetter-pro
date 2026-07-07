// File: Features/IRIS/IRISSuggestionCardView.swift
//
// The proactive card surfaced on Home when IRIS has something to say. Tapping
// "Talk to IRIS" opens her chat pre-loaded with the suggested prompt.

import SwiftUI

struct IRISSuggestionCardView: View {

    @State var triggers = IRISTriggers.shared
    @State private var suggestion: IRISSuggestion?
    @State private var openChat = false
    @State private var pendingPrompt: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let card = suggestion {
                cardBody(card)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .onAppear { refresh() }
        // Triggers are time-sensitive (check-in windows open, rides become relevant,
        // tier expiry approaches), so a card evaluated once on appear goes stale while
        // Home stays on screen. Re-evaluate on a low-frequency loop (no Combine) as
        // well as on foreground so a newly-eligible nudge surfaces without a manual
        // navigation. The task is cancelled automatically when the view disappears.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .navigationDestination(isPresented: $openChat) {
            IRISChatView(initialPrompt: pendingPrompt)
        }
    }

    private func refresh() {
        let next = triggers.evaluate()
        // Compare on the stable dismissalKey, not `id` (a fresh UUID minted on every
        // evaluate()), so re-evaluating the *same* underlying nudge doesn't re-run
        // the insertion transition on an unchanged card.
        guard next?.dismissalKey != suggestion?.dismissalKey else { return }
        withAnimation { suggestion = next }
    }

    // MARK: - Card

    private func cardBody(_ card: IRISSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Rainbow IRIS orb
            ZStack {
                Circle()
                    .fill(rainbowGradient)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color(hex: "#7B3FBF").opacity(0.5), radius: 6)
                Image(systemName: card.kind.systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Body
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("IRIS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(rainbowGradient)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("SUGGESTION")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text(card.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(card.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Button {
                        pendingPrompt = card.promptToIRIS
                        openChat = true
                        // Feedback loop: the user welcomed this nudge.
                        TravelProfileStore.shared.recordSuggestionFeedback(kind: card.kind.rawValue, accepted: true)
                    } label: {
                        Text("Talk to IRIS")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(rainbowGradient)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    Button {
                        if let s = suggestion {
                            triggers.dismiss(s)
                            // Feedback loop: the user waved this nudge away.
                            TravelProfileStore.shared.recordSuggestionFeedback(kind: s.kind.rawValue, accepted: false)
                            // Re-evaluate rather than just hiding: dismiss() has added
                            // this nudge's key to the dismissal set, so refresh() now
                            // surfaces the next-priority suggestion (or clears the card
                            // if there isn't one) instead of leaving Home nudge-less.
                            refresh()
                        }
                    } label: {
                        Text("Not now")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.06), Color(white: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(rainbowGradient.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }

    private var rainbowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#E84040"), Color(hex: "#E8A020"), Color(hex: "#FFEB00"),
                Color(hex: "#1DB97D"), Color(hex: "#3B9EF0"), Color(hex: "#7B3FBF")
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
