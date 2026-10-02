// File: WidgetExtension/BoardingPassControl.swift
//
// A "Boarding Pass" button for Control Center, the Lock Screen and the Action
// button. One press at the security line opens the next boarding pass in the
// app, without hunting for the app icon with a bag in the other hand.
//
// The button's action is `ShowBoardingPassIntent` (Shared/), an OpenIntent
// compiled into both the app and this extension, which is what Apple requires
// for a control to open its app. The control is static: it shows no flight
// details, so nothing personal is visible on a locked phone, and it needs no
// App Group data. The intent requires authentication, so a locked phone asks
// for Face ID or Touch ID before the pass appears.

import AppIntents
import SwiftUI
import WidgetKit

struct BoardingPassControl: ControlWidget {
    static let kind = "BoardingPassControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ShowBoardingPassIntent(target: .next)) {
                Label("Boarding Pass", systemImage: "wallet.pass.fill")
            }
        }
        .displayName("Boarding Pass")
        .description("Opens your next boarding pass in JetSetter Pro.")
    }
}

// The widget extension's copy of the intent never shows anything itself: for
// an OpenIntent the system brings the app forward and runs the app's
// `perform()` (Core/Intents/BoardingPassIntents.swift). The result type
// matches the app's so both targets describe the same intent.
extension ShowBoardingPassIntent {
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Opening your boarding pass.")
    }
}
