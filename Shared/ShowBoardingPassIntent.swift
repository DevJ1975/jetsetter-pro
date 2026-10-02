// File: Shared/ShowBoardingPassIntent.swift
//
// "Show my boarding pass": the Siri phrase, the Shortcuts action, and the
// action behind the Boarding Pass control in Control Center, on the Lock
// Screen and on the Action button. It's the thing a traveler reaches for at
// the security line with a bag in one hand, so it has to be one tap or one
// sentence away.
//
// Why this file is in Shared/: Apple opens the app from a control only when
// the control's OpenIntent is compiled into BOTH the app and the widget
// extension ("Creating controls to perform actions across the system",
// WidgetKit docs), and Shared/ is the one folder both targets build. The
// declaration lives here so the two copies can never drift; each target
// supplies its own `perform()`:
//   • app:    Core/Intents/BoardingPassIntents.swift picks the right pass and
//             routes to it
//   • widget: WidgetExtension/BoardingPassControl.swift only returns, because
//             the system runs the app's copy and only the app can read the wallet
// Keep this file free of app-only types so the widget target still compiles.

import AppIntents

/// What the intent opens. An enum rather than an entity because the widget
/// extension can't read the wallet; the app picks the actual pass when it runs.
enum BoardingPassTarget: String, AppEnum {
    case next

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Boarding Pass")
    static let caseDisplayRepresentations: [BoardingPassTarget: DisplayRepresentation] = [
        .next: "Next boarding pass"
    ]
}

struct ShowBoardingPassIntent: OpenIntent {
    static let title: LocalizedStringResource = "Show Boarding Pass"
    static let description = IntentDescription("Opens your next boarding pass in JetSetter Pro.")

    /// The pass carries the traveler's name and booking reference, so a
    /// locked phone asks for Face ID or Touch ID first. The app has to come to
    /// the foreground to show the pass anyway, so this costs no extra step.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Boarding Pass", default: .next)
    var target: BoardingPassTarget

    init() {}

    init(target: BoardingPassTarget) {
        self.target = target
    }
}
