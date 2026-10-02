// File: UI/Layout/PrivacyCover.swift
//
// Hides sensitive screens whenever their scene isn't active, so the
// app-switcher snapshot, the side-by-side window switcher on the foldable
// iPhone Ultra, and a glance over someone's shoulder while Control Centre is
// down never show a passport number or loyalty account.
//
// The system takes the snapshot as the scene leaves the foreground, so the
// cover must already be drawn by then: it appears on `.inactive` (which comes
// first), not `.background`, and it appears without animation, because a
// half-faded cover in the snapshot would still show the document underneath.
//
// Sheets are presented above the view that owns them, so a cover on the
// screen does not reach its sheets. Apply `.privacyCover()` to each sheet's
// content as well.

import SwiftUI

extension View {
    /// Covers this view with an opaque placeholder while the scene is not
    /// `.active`. Use on anything that shows vault, identity or loyalty data.
    func privacyCover() -> some View {
        modifier(PrivacyCoverModifier())
    }
}

private struct PrivacyCoverModifier: ViewModifier {

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if scenePhase != .active {
                    PrivacyCoverView()
                }
            }
            // No fade: the snapshot must never catch the cover half-drawn.
            .animation(nil, value: scenePhase)
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            // Opaque in every appearance (Executive, Cabin, Heritage). A
            // material would blur, not hide, large type like a passport number.
            JetsetterTheme.Colors.background
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Text("JetSetter Pro")
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hidden while JetSetter Pro is in the background")
        }
        .ignoresSafeArea()
    }
}
