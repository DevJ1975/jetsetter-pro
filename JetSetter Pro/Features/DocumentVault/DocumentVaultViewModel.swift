// File: Features/DocumentVault/DocumentVaultViewModel.swift
// ViewModel for the Travel Document Vault (Feature 4).
// Biometric (passcode-fallback) auth + AES-GCM-encrypted on-device persistence
// via DocumentVaultStore / VaultCrypto. Document numbers are encrypted at rest;
// clear text only lives in memory after auth.
// TODO (follow-up): encrypted photo persistence + expiry notification scheduling.

import SwiftUI
import Combine
import LocalAuthentication

@MainActor
final class DocumentVaultViewModel: ObservableObject {

    @Published private(set) var documents: [VaultDocument] = []
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String? = nil

    // Documents loaded after biometric auth — never persisted in clear text
    @Published private(set) var decryptedNumbers: [UUID: String] = [:]

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

        var loaded = DocumentVaultStore.load()

        // Demo-mode preseed: if the vault is empty after loading from
        // persistence, drop in four realistic mock documents so the investor
        // never sees an empty-state screen.
        if loaded.isEmpty && MockDataService.isEnabled {
            loaded = Self.demoSeedDocuments()
        }

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
        // NOTE: encrypted photo persistence + expiry notifications are a follow-up.
    }

    func deleteDocument(id: UUID) async {
        documents.removeAll { $0.id == id }
        decryptedNumbers[id] = nil
        try? DocumentVaultStore.save(documents)
    }

    /// Returns the entry requirements for the given destination country name.
    func entryRequirements(for destination: String) -> EntryRequirement? {
        // Try an exact match first, then a contains check
        if let req = EntryRequirement.requirements[destination] { return req }
        return EntryRequirement.requirements.first { destination.contains($0.key) }?.value
    }
}
