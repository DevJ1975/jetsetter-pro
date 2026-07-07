// File: Core/Services/Expense/Providers/EmailPDFProvider.swift
//
// The universal fallback. Generates a multi-page PDF expense report and opens
// MFMailComposeViewController with it attached. Works for ANY expense system
// the user's company uses.

import Foundation
import UIKit
import MessageUI

@MainActor
final class EmailPDFProvider: NSObject, ExpenseExportProvider {

    let id = "email_pdf"
    let displayName = "Email Expense Report"
    let tagline = "Send a polished PDF to your approver"
    let brandColorHex = "#3B9EF0"
    let systemImage = "envelope.fill"
    let authKind: ExpenseProviderAuthKind = .none

    static let shared = EmailPDFProvider()
    private override init() {}

    private var pendingContinuation: CheckedContinuation<ExportBatchResult, Error>?
    private var pendingExpenses: [Expense] = []

    func isConnected() async -> Bool { true }    // Always available
    func connect() async throws -> Bool { true }
    func disconnect() async {}

    // MARK: - Submit

    func submit(trip: Trip?, expenses: [Expense]) async throws -> ExportBatchResult {
        let pdfData = PDFExpenseReportRenderer.render(
            trip: trip,
            expenses: expenses
        )
        let fileName = "Expense_Report_\(trip?.name.replacingOccurrences(of: " ", with: "_") ?? "Travel").pdf"

        // PRIMARY PATH: Mail composer when the device can send mail.
        if MFMailComposeViewController.canSendMail() {
            return try await submitViaMail(
                pdfData: pdfData, fileName: fileName,
                trip: trip, expenses: expenses
            )
        }

        // FALLBACK (simulator, no Mail account): share-sheet so the demo still
        // shows the gorgeous PDF — the user can preview, save to Files, AirDrop,
        // or hand off to Mail when it's set up later.
        return try await submitViaShareSheet(
            pdfData: pdfData, fileName: fileName, expenses: expenses
        )
    }

    private func submitViaMail(
        pdfData: Data, fileName: String,
        trip: Trip?, expenses: [Expense]
    ) async throws -> ExportBatchResult {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        composer.setSubject("Expense Report — \(trip?.name ?? "Travel")")
        composer.setMessageBody(messageBody(trip: trip, expenses: expenses), isHTML: false)
        composer.addAttachmentData(pdfData, mimeType: "application/pdf", fileName: fileName)

        // Serialize submits: a second call would clobber `pendingContinuation`
        // (leaking the first — a checked-continuation misuse) and overwrite
        // `pendingExpenses`, so the delegate could resolve the wrong batch.
        guard pendingContinuation == nil else {
            throw ExpenseExportError.providerFailure("A mail composer is already in progress.")
        }

        guard let root = activeRootViewController() else {
            throw ExpenseExportError.providerFailure("Could not present mail composer.")
        }
        root.present(composer, animated: true)

        pendingExpenses = expenses

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
        }
    }

    /// Writes the PDF to a tmp file and presents UIActivityViewController,
    /// resolving only once the user actually completes an activity (share,
    /// save to Files, AirDrop, …). If they dismiss without completing, this is
    /// treated as a cancellation rather than a false success.
    private func submitViaShareSheet(
        pdfData: Data, fileName: String, expenses: [Expense]
    ) async throws -> ExportBatchResult {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        // Propagate write failures instead of swallowing them — presenting a
        // share sheet backed by a missing file would misreport success.
        try pdfData.write(to: tmpURL)

        guard let root = activeRootViewController() else {
            throw ExpenseExportError.providerFailure("Could not present share sheet.")
        }

        let completed: Bool = try await withCheckedThrowingContinuation { continuation in
            let activity = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
            // Guard against the handler firing more than once.
            var didResume = false
            activity.completionWithItemsHandler = { _, completed, _, error in
                guard !didResume else { return }
                didResume = true
                if let error {
                    continuation.resume(throwing: ExpenseExportError.providerFailure(error.localizedDescription))
                } else {
                    continuation.resume(returning: completed)
                }
            }
            root.present(activity, animated: true)
        }

        guard completed else {
            throw ExpenseExportError.userCancelled
        }

        let perExpense: [UUID: ExportOutcome] = Dictionary(
            uniqueKeysWithValues: expenses.map { ($0.id, ExportOutcome.submitted(remoteID: "pdf-generated")) }
        )
        return ExportBatchResult(
            providerID: id, providerName: displayName,
            submittedAt: Date(), perExpense: perExpense
        )
    }

    // MARK: - Helpers

    private func messageBody(trip: Trip?, expenses: [Expense]) -> String {
        // Group by currency — a raw sum across currencies would misstate the
        // total, so present one subtotal per currency.
        let totalsByCurrency = Dictionary(grouping: expenses, by: { $0.currency })
            .map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.currency < $1.currency }
        let totalString = totalsByCurrency.isEmpty
            ? "USD 0.00"
            : totalsByCurrency.map { String(format: "%@ %.2f", $0.currency, $0.amount) }.joined(separator: " · ")
        var lines: [String] = [
            "Hi,",
            "",
            "Attached is my expense report\(trip.map { " for \($0.name)" } ?? "")."
        ]
        if let trip = trip {
            let f = DateFormatter(); f.dateStyle = .medium
            lines.append("Trip dates: \(f.string(from: trip.startDate)) – \(f.string(from: trip.endDate))")
            lines.append("Destination: \(trip.destination)")
        }
        lines.append("")
        lines.append("Total: \(totalString) across \(expenses.count) items")
        lines.append("")
        lines.append("Generated by JetSetter Pro.")
        return lines.joined(separator: "\n")
    }

    private func activeRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresented()
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension EmailPDFProvider: MFMailComposeViewControllerDelegate {

    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        // `dismiss(animated:)` is `@MainActor`-isolated; hop onto the main
        // actor before calling it from this nonisolated delegate callback.
        Task { @MainActor in
            controller.dismiss(animated: true)
            self.handleMailFinish(result: result, error: error)
        }
    }

    private func handleMailFinish(result: MFMailComposeResult, error: Error?) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil

        let now = Date()
        switch result {
        case .sent:
            let perExpense = Dictionary(
                uniqueKeysWithValues: pendingExpenses.map { ($0.id, ExportOutcome.submitted(remoteID: "emailed")) }
            )
            continuation.resume(returning: ExportBatchResult(
                providerID: id, providerName: displayName,
                submittedAt: now, perExpense: perExpense
            ))
        case .saved:
            continuation.resume(throwing: ExpenseExportError.userCancelled)
        case .cancelled:
            continuation.resume(throwing: ExpenseExportError.userCancelled)
        case .failed:
            continuation.resume(throwing: ExpenseExportError.providerFailure(
                error?.localizedDescription ?? "Mail send failed."
            ))
        @unknown default:
            continuation.resume(throwing: ExpenseExportError.providerFailure("Unknown mail result."))
        }
        pendingExpenses = []
    }
}

// MARK: - UIViewController helper

private extension UIViewController {
    func topMostPresented() -> UIViewController {
        if let presented = presentedViewController { return presented.topMostPresented() }
        return self
    }
}
