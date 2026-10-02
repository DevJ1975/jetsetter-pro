// File: UI/Layout/AdaptiveLayout.swift
//
// Small layout helpers for screens that now run at any width: a 320 pt slice
// beside another app, the ~466 pt outer display of the foldable iPhone Ultra,
// its ~890 pt inner display (regular width, like an iPad), and full iPad.
// Layout follows the space the scene is given, never the device model or
// orientation (see docs/HANDOFF.md), so nothing here reads `UIScreen` or the
// interface idiom.
//
// - `readableWidth()` caps text-heavy screens (Settings, Expenses) so a form
//   isn't stretched across a 900 pt line on the inner display, while the
//   screen's background still fills the window.
// - `inSheetNavigation()` gives a screen that is normally pushed onto a
//   navigation stack a stack, title bar and Done button when it is presented
//   as a sheet instead. Screens under More used to carry their own
//   `NavigationStack`, which nested a second stack inside More's (doubled
//   bars, broken back gestures). They no longer do, so sheet call sites wrap
//   them with this.
//
// These live in UI/Layout rather than UI/Components only because another
// change was editing UI/Components at the same time; they can move there.

import SwiftUI

enum JetLayout {
    /// Maximum width for reading and form content on regular-width screens.
    static let readableWidth: CGFloat = 700
}

extension View {

    /// Caps the content at a comfortable reading width and centres it, while
    /// leaving the outer frame free to fill the window. Apply it to the content
    /// *inside* a ScrollView so the scroll indicator stays at the window edge.
    func readableWidth(_ maxWidth: CGFloat = JetLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Wraps a pushed-style screen in its own `NavigationStack` with a Done
    /// button, for use at a `.sheet` / `.fullScreenCover` call site:
    ///
    ///     .sheet(isPresented: $showOptimizer) {
    ///         DepartureOptimizerView().inSheetNavigation()
    ///     }
    ///
    /// Don't use it on a screen pushed inside an existing stack; that recreates
    /// the nested-stack problem this exists to remove.
    func inSheetNavigation() -> some View {
        modifier(InSheetNavigationModifier())
    }
}

private struct InSheetNavigationModifier: ViewModifier {

    // Read outside the stack: this is the sheet's own dismiss action.
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
