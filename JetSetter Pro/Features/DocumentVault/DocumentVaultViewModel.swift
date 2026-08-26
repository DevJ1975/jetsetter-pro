// File: Features/DocumentVault/DocumentVaultViewModel.swift
// ViewModel for the Travel Document Vault (Feature 4).
// Biometric (passcode-fallback) auth + AES-GCM-encrypted on-device persistence
// via DocumentVaultStore / VaultCrypto. Document numbers are encrypted at rest;
// clear text only lives in memory after auth.
// Expiry reminders are scheduled as local notifications on add and cancelled on
// delete. TODO (follow-up): encrypted photo persistence.

import SwiftUI
import LocalAuthentication
import UserNotifications

@MainActor
@Observable
final class DocumentVaultViewModel {

    private(set) var documents: [VaultDocument] = []
    private(set) var isAuthenticated = false
    private(set) var isLoading = false
    var errorMessage: String? = nil

    // Documents loaded after biometric auth — never persisted in clear text
    private(set) var decryptedNumbers: [UUID: String] = [:]

    func authenticate() async {
        let context = LAContext()
        var authError: NSError?
        // .deviceOwnerAuthentication allows a passcode fallback when biometrics
        // aren't enrolled/available — the vault stays usable, but always behind
        // some device authentication.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            isAuthenticated = false
            errorMessage = "Set up Face ID, Touch ID, or a device passcode to use the Document Vault."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to access your Document Vault"
            )
            isAuthenticated = success
            if success { await loadDocuments() }
        } catch {
            // Fail closed — stay locked on cancellation or any auth error.
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    func loadDocuments() async {
        guard isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }

        let loaded = DocumentVaultStore.load()
        documents = loaded
        // Decrypt numbers for in-session display only — never written back clear.
        decryptedNumbers = DocumentVaultStore.decryptNumbers(for: loaded)
    }

    // MARK: - Demo Seed

    /// Four mock travel documents mirroring the AddDocumentSheet factory
    /// logic in DocumentVaultView. Used only when MockDataService.isEnabled
    /// and the vault loads empty from persistence.
    private static func demoSeedDocuments() -> [VaultDocument] {
        let now = Date()
        let oneYear: TimeInterval  = 86_400 * 365
        let fiveYears: TimeInterval = 86_400 * 365 * 5

        return [
            VaultDocument(
                id: UUID(),
                documentType: .passport,
                issuingCountry: "United States",
                docNumberEncrypted: nil,
                docNumberClear: "X12345678",
                expiryDate: now.addingTimeInterval(fiveYears),
                photoUrl: nil,
                notes: nil,
                createdAt: now
            ),
            VaultDocument(
                id: UUID(),
                documentType: .visa,
                issuingCountry: "Japan",
                docNumberEncrypted: nil,
                docNumberClear: "JPV-2026-88421",
                expiryDate: now.addingTimeInterval(fiveYears),
                photoUrl: nil,
                notes: "Tourist visa — multiple entry",
                createdAt: now
            ),
            VaultDocument(
                id: UUID(),
                documentType: .travelInsurance,
                issuingCountry: nil,
                docNumberEncrypted: nil,
                docNumberClear: "AGA-7491-8821",
                expiryDate: now.addingTimeInterval(oneYear),
                photoUrl: nil,
                notes: "Allianz Premium Travel — 24/7 hotline +1 (800) 284-7490",
                createdAt: now
            ),
            VaultDocument(
                id: UUID(),
                documentType: .vaccination,
                issuingCountry: "United States",
                docNumberEncrypted: nil,
                docNumberClear: "CDC-VAX-994127",
                expiryDate: now.addingTimeInterval(oneYear),
                photoUrl: nil,
                notes: "Yellow Fever · COVID-19 · Hepatitis A & B",
                createdAt: now
            )
        ]
    }

    func addDocument(_ document: VaultDocument, photo: Data?) async {
        documents.append(document)
        if let clear = document.docNumberClear {
            decryptedNumbers[document.id] = clear
        }
        do {
            // Encrypts the number into docNumberEncrypted; clear text is dropped.
            try DocumentVaultStore.save(documents)
        } catch {
            errorMessage = "Couldn't securely save the document."
        }
        // Schedule expiry reminders at the 180/90/30-day thresholds so a
        // soon-to-lapse passport/visa warns the traveler before travel even if
        // they never open this screen. Photo persistence remains a follow-up.
        await scheduleExpiryNotifications(for: document)
    }

    func deleteDocument(id: UUID) async {
        documents.removeAll { $0.id == id }
        decryptedNumbers[id] = nil
        try? DocumentVaultStore.save(documents)
        await cancelExpiryNotifications(for: id)
    }

    // MARK: - Expiry Notifications

    /// Day thresholds (before expiry) at which to warn the traveler. Mirrors the
    /// notice/warning/critical bands in `VaultDocument.ExpiryUrgency`.
    private static let expiryThresholdDays = [180, 90, 30]

    /// Schedules local notifications at each threshold before a document's
    /// expiry date. Thresholds already in the past are skipped. Existing
    /// requests for the document are cleared first so re-adds don't duplicate.
    private func scheduleExpiryNotifications(for document: VaultDocument) async {
        await cancelExpiryNotifications(for: document.id)

        guard let expiry = document.expiryDate else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let typeName = document.documentType.displayName

        for days in Self.expiryThresholdDays {
            guard let fireDate = calendar.date(byAdding: .day, value: -days, to: expiry),
                  fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(typeName) expires in \(days) days"
            content.body = "Your \(typeName.lowercased()) expires \(expiry.formatted(date: .abbreviated, time: .omitted)). Renew it before your next trip."
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.expiryNotificationID(documentID: document.id, days: days),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Cancels every pending expiry reminder for a document across all thresholds.
    private func cancelExpiryNotifications(for id: UUID) async {
        let ids = Self.expiryThresholdDays.map { Self.expiryNotificationID(documentID: id, days: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func expiryNotificationID(documentID: UUID, days: Int) -> String {
        "doc_expiry_\(documentID.uuidString)_\(days)"
    }

    /// Returns the entry requirements for the given destination country name.
    func entryRequirements(for destination: String) -> EntryRequirement? {
        // Try an exact match first, then a case-insensitive contains check.
        if let req = EntryRequirement.requirements[destination] { return req }

        let normalized = destination.lowercased()
        // Iterate deterministically, longest key first, so the most specific
        // country name wins (e.g. "South Korea" before a hypothetical "Korea")
        // and the result never depends on Dictionary iteration order.
        return EntryRequirement.requirements
            .sorted { $0.key.count > $1.key.count }
            .first { normalized.contains($0.key.lowercased()) }?
            .value
    }
}
