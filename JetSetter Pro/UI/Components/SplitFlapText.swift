// File: UI/Components/SplitFlapText.swift
//
// Solari-style split-flap text: each character cycles through an alphabet
// before settling on its target value. Used by the FlightBoardView to mimic
// real airport departure boards.

import SwiftUI

struct SplitFlapText: View {

    let text: String
    var characterWidth: CGFloat = 18
    var characterHeight: CGFloat = 26
    var fontSize: CGFloat = 18
    var tint: Color = .yellow
    var background: Color = Color(white: 0.06)
    /// Staggered delay between adjacent character animations.
    var staggerDelay: Double = 0.05
    /// Time between each "flap" within a single character.
    var stepDuration: Double = 0.045

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                SplitFlapCharacter(
                    target: char,
                    delay: Double(index) * staggerDelay,
                    stepDuration: stepDuration,
                    width: characterWidth,
                    height: characterHeight,
                    fontSize: fontSize,
                    tint: tint,
                    background: background
                )
            }
        }
    }
}

// MARK: - Single character

private struct SplitFlapCharacter: View {

    let target: Character
    let delay: Double
    let stepDuration: Double
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let tint: Color
    let background: Color

    @State private var displayed: Character = " "

    /// Characters the flap rolls through. Order matters — it cycles in this
    /// sequence until landing on the target.
    private static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 :-+./")

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(background)
            // Hairline split through the middle gives it the Solari aesthetic
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 0.5)

            Text(String(displayed))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .id(displayed)  // re-renders on change for a snappier feel
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: target) { await runFlip() }
    }

    /// Cycles `displayed` through the alphabet until it matches `target`.
    /// `task(id: target)` automatically cancels and restarts when the
    /// target changes (e.g., status update on the row).
    private func runFlip() async {
        try? await Task.sleep(for: .seconds(delay))

        let normalized = normalize(target)
        guard let targetIndex = Self.alphabet.firstIndex(of: normalized) else {
            withAnimation { displayed = normalized }
            return
        }

        // If we're already there (e.g., re-entering view), skip the spin.
        if displayed == normalized { return }

        // Start from current position and walk forward to target, wrapping
        // around so all characters always end on the target.
        var current = Self.alphabet.firstIndex(of: displayed) ?? 0
        while current != targetIndex {
            current = (current + 1) % Self.alphabet.count
            withAnimation(.easeInOut(duration: stepDuration * 0.8)) {
                displayed = Self.alphabet[current]
            }
            try? await Task.sleep(for: .seconds(stepDuration))
        }
    }

    private func normalize(_ c: Character) -> Character {
        let upper = String(c).uppercased().first ?? " "
        if Self.alphabet.contains(upper) { return upper }
        return " "
    }
}

// MARK: - Preview

#Preview("Single row") {
    ZStack {
        Color(white: 0.02).ignoresSafeArea()
        VStack(spacing: 8) {
            SplitFlapText(text: "AA169  NRT  B22  18:25  ON TIME")
            SplitFlapText(text: "UA837  LHR  C14  20:10  BOARDING", tint: .orange)
            SplitFlapText(text: "DL400  CDG  A7   21:00  DELAYED 25", tint: .red)
        }
        .padding()
    }
}
