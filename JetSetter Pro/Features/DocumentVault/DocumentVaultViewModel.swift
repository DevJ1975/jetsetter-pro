// File: Features/DocumentVault/DocumentVaultViewModel.swift
// ViewModel for the Travel Document Vault (Feature 4).
// TODO: Full implementation in Feature 4 sprint.
// Key responsibilities: biometric auth, CryptoKit AES-GCM encryption/decryption,
// Supabase Storage photo upload, expiry notification scheduling.

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
        // TODO: Fetch from Supabase vault_documents, decrypt numbers with CryptoKit
    }

    func addDocument(_ document: VaultDocument, photo: Data?) async {
        // TODO: Encrypt doc number with AES-GCM, upload photo to Supabase Storage,
        // upsert metadata to vault_documents, schedule expiry notifications
        documents.append(document)
    }

    func deleteDocument(id: UUID) async {
        documents.removeAll { $0.id == id }
        // TODO: Delete from Supabase Storage + vault_documents
    }

    /// Returns the entry requirements for the given destination country name.
    func entryRequirements(for destination: String) -> EntryRequirement? {
        // Try an exact match first, then a contains check
        if let req = EntryRequirement.requirements[destination] { return req }
        return EntryRequirement.requirements.first { destination.contains($0.key) }?.value
    }
}
