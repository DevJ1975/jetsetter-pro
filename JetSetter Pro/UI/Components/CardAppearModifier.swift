// File: UI/Components/CardAppearModifier.swift
//
// Fade + slide-up entrance animation. Applied to cards on Home so the screen
// "blooms" into view. Use `.cardAppear(delay: 0.1)`.
//
// With Reduce Motion on, cards are simply there: no slide, no fade, no delay.

import SwiftUI

struct CardAppearModifier: ViewModifier {

    let delay: Double
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reading `reduceMotion` here as well as in `onAppear` means a card is
    /// never left invisible if the setting changes while it's on screen.
    private var shown: Bool { visible || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                guard !reduceMotion else {
                    visible = true
                    return
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    /// Fades + slides this view in from below after `delay` seconds.
    func cardAppear(delay: Double = 0) -> some View {
        modifier(CardAppearModifier(delay: delay))
    }
}
