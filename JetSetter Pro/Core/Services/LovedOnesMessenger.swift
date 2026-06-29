// File: Core/Services/LovedOnesMessenger.swift
//
// Presents a PRE-FILLED Messages composer (recipients + body) that the user
// sends with one tap. iOS does not allow apps to send SMS silently, so this is
// the native, no-backend path for "IRIS texts my loved ones on takeoff/landing":
// IRIS (or a tapped notification) opens the composer; the human hits Send.

import UIKit
import MessageUI

@MainActor
final class LovedOnesMessenger: NSObject, MFMessageComposeViewControllerDelegate {

    static let shared = LovedOnesMessenger()
    private override init() { super.init() }

    /// Whether this device can send text messages (false on most simulators).
    var canSend: Bool { MFMessageComposeViewController.canSendText() }

    /// Presents the system Messages composer pre-populated with `recipients`
    /// and `body`. No-op if the device can't send texts.
    func presentComposer(recipients: [String], body: String) {
        guard canSend, !recipients.isEmpty else { return }
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = body
        composer.messageComposeDelegate = self
        topViewController()?.present(composer, animated: true)
    }

    // MARK: - Message templates

    /// Builds the message body for a flight event, woven with flight context.
    static func message(for event: LovedOnesEvent,
                        flightNumber: String?,
                        destinationCity: String?) -> String {
        let flight = flightNumber.map { " on \($0)" } ?? ""
        switch event {
        case .takeoff:
            return "✈️ Wheels up\(flight) — I'll text you when I land."
        case .landing:
            let place = destinationCity.map { " in \($0)" } ?? ""
            return "🛬 Just landed safely\(place). Talk soon!"
        }
    }

    // MARK: - MFMessageComposeViewControllerDelegate

    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    // MARK: - Top view controller lookup

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene?.windows.first?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
