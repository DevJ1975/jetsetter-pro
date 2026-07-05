// File: Core/UI/InAppBrowser.swift
//
// Reusable in-app surfaces that keep every experience inside JetSetter Pro
// (IOS_PARITY_NOTES.md §7.7 — no external app/browser/dialer hand-offs). Any
// feature that used to call UIApplication.shared.open(webURL) presents an
// `InAppWebSheet` instead; mailto: uses `MailComposeSheet`; tel: numbers are
// copied to the clipboard; App Store "rate" uses StoreKit's in-app review.

import SwiftUI
import WebKit
import MessageUI
import StoreKit

// MARK: - In-app web view (WKWebView)

struct InAppWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// A titled, dismissible sheet that renders a web page in-app.
struct InAppWebSheet: View {
    let url: URL
    var title: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InAppWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Web sheet presentation helper
//
// Drives an `InAppWebSheet` from an optional URL so a tap can just set the URL.

private struct InAppWebPresentation: ViewModifier {
    @Binding var url: URL?
    let title: String

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { url.map(IdentifiableURL.init) },
            set: { url = $0?.url }
        )) { item in
            InAppWebSheet(url: item.url, title: title)
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
