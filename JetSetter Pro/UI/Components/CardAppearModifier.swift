// File: UI/Components/CardAppearModifier.swift
//
// Fade + slide-up entrance animation. Applied to cards on Home so the screen
// "blooms" into view. Use `.cardAppear(delay: 0.1)`.

import SwiftUI

struct CardAppearModifier: ViewModifier {

    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 18)
            .onAppear {
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
