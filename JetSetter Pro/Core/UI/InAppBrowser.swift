// File: Core/UI/InAppBrowser.swift
//
// Reusable in-app surfaces that keep every experience inside JetSetter Pro
// (IOS_PARITY_NOTES.md §7.7 — no external app/browser/dialer hand-offs). Any
// feature that used to call UIApplication.shared.open(webURL) presents an
// `InAppWebSheet` instead; mailto: uses `MailComposeSheet`; tel: numbers are
// copied to the clipboard; App Store "rate" uses StoreKit's in-app review.
//
// Why SFSafariViewController and not WKWebView: travelers type airline
// passwords and card numbers on check-in and booking pages opened here. The
// old bare WKWebView had no address bar (no way to see which domain was asking
// for a password), no progress or error page (a hotel captive portal or
// airplane mode showed a blank white sheet), and it kept a cookie store inside
// our process. SFSafariViewController shows the domain, runs out of process so
// the app can't read what's typed or the cookies, offers Safari's AutoFill and
// Apple Pay, and handles offline and error pages itself.

import SwiftUI
import SafariServices
import MessageUI
import StoreKit

// MARK: - In-app web view (SFSafariViewController)

/// SwiftUI wrapper for `SFSafariViewController`. `onFinish` runs when the
/// traveler taps Done, so the presenter can clear its URL binding. Check-in
/// relies on that to move on to its "Did you finish checking in?" step.
struct InAppWebView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (() -> Void)? = nil

    /// SFSafariViewController only accepts http and https; any other scheme
    /// raises an Objective-C exception and crashes. Callers go through
    /// `.inAppWeb`, which routes other schemes elsewhere before we get here.
    static func canPresent(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        // Check-in and booking pages are forms, not articles.
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: (() -> Void)?
        init(onFinish: (() -> Void)?) { self.onFinish = onFinish }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish?()
        }
    }
}

/// A dismissible sheet that renders a web page in-app. `title` is kept for
/// source compatibility but isn't shown: SFSafariViewController puts the
/// page's domain in its bar instead, which is the point. It isn't used as an
/// accessibility label either, because a label on the representable could make
/// VoiceOver treat the whole page as one element and hide the form fields.
struct InAppWebSheet: View {
    let url: URL
    var title: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InAppWebView(url: url) { dismiss() }
            .ignoresSafeArea()
    }
}

// MARK: - Web sheet presentation helper
//
// Drives an `InAppWebSheet` from an optional URL so a tap can just set the URL.
// The binding returns to nil when the sheet closes, by Done or by a swipe, so
// callers that watch it (check-in's hand-off step) keep working unchanged.

private struct InAppWebPresentation: ViewModifier {
    @Binding var url: URL?
    /// Unused on screen (see `InAppWebSheet`); kept so call sites don't change.
    let title: String
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { url.flatMap { InAppWebView.canPresent($0) ? IdentifiableURL(url: $0) : nil } },
                set: { url = $0?.url }
            )) { item in
                InAppWebView(url: item.url) { url = nil }
                    .ignoresSafeArea()
            }
            .onChange(of: url) { _, newValue in
                // A non-web link (an app deep link such as uber://) can't load
                // in Safari View Controller. The old WKWebView silently showed
                // a blank page for these; hand them to the system and clear the
                // binding so the caller sees the "closed" transition.
                guard let newValue, !InAppWebView.canPresent(newValue) else { return }
                openURL(newValue)
                url = nil
            }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {
    /// Presents an in-app web sheet whenever `url` is non-nil.
    func inAppWeb(url: Binding<URL?>, title: String = "") -> some View {
        modifier(InAppWebPresentation(url: url, title: title))
    }
}

// MARK: - In-app mail composer (MFMailComposeViewController)

struct MailComposeSheet: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    var onFinish: (() -> Void)? = nil

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (() -> Void)?
        init(onFinish: (() -> Void)?) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true) { [onFinish] in onFinish?() }
        }
    }
}

// MARK: - In-app helpers (clipboard + StoreKit review)

enum InAppActions {

    /// Copies a phone number to the clipboard (iOS can't place a PSTN call
    /// in-app; §7.7 keeps us from launching the dialer). Callers show a toast.
    static func copyPhoneNumber(_ number: String) {
        UIPasteboard.general.string = number
    }

    /// Requests the native in-app App Store review prompt (replaces a "Rate us"
    /// link that opened the App Store externally).
    @MainActor
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}
