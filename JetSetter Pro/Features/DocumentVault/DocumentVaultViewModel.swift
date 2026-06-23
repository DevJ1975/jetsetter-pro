// File: Features/DocumentVault/DocumentVaultViewModel.swift
// ViewModel for the Travel Document Vault (Feature 4).
// TODO: Full implementation in Feature 4 sprint.
// Key responsibilities: biometric auth, CryptoKit AES-GCM encryption/decryption,
// Firebase Storage photo upload, expiry notification scheduling.

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
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            errorMessage = "Biometric authentication not available on this device."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access your Document Vault"
            )
            isAuthenticated = success
            if success { await loadDocuments() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDocuments() async {
        guard isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        // TODO: Fetch from Firebase vault_documents, decrypt numbers with CryptoKit

        // Demo-mode preseed: if the vault is empty after attempting to load
        // from persistence, drop in four realistic mock documents so the
        // investor never sees an empty-state screen.
        if documents.isEmpty && MockDataService.isEnabled {
            documents = Self.demoSeedDocuments()
        }
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
        // TODO: Encrypt doc number with AES-GCM, upload photo to Firebase Storage,
        // upsert metadata to vault_documents, schedule expiry notifications
        documents.append(document)
    }

    func deleteDocument(id: UUID) async {
        documents.removeAll { $0.id == id }
        // TODO: Delete from Firebase Storage + vault_documents
    }

    /// Returns the entry requirements for the given destination country name.
    func entryRequirements(for destination: String) -> EntryRequirement? {
        // Try an exact match first, then a contains check
        if let req = EntryRequirement.requirements[destination] { return req }
        return EntryRequirement.requirements.first { destination.contains($0.key) }?.value
    }
}
