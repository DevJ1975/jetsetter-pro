// File: JetSetter ProTests/DocumentVaultLockTests.swift
//
// The Document Vault must re-lock when its scene goes to the background and
// drop every decrypted passport number and photo from memory. The system
// authentication prompt can't run in a test host, so these tests inject an
// authenticator and a loader in place of `LAContext` and the encrypted store.

import Testing
import SwiftUI
import UIKit
@testable import JetSetter_Pro

@MainActor
@Suite struct DocumentVaultLockTests {

    /// Counts how many times the vault asked the device owner to authenticate.
    private final class PromptCounter {
        var count = 0
    }

    private static func passport() -> VaultDocument {
        VaultDocument(
            id: UUID(),
            documentType: .passport,
            issuingCountry: "United States",
            docNumberEncrypted: nil,
            docNumberClear: nil,
            expiryDate: nil,
            photoUrl: nil,
            notes: nil,
            createdAt: Date()
        )
    }

    /// A vault that unlocks without a prompt and holds one decrypted passport.
    private static func unlockedVault() async -> (DocumentVaultViewModel, VaultDocument) {
        let doc = passport()
        let vm = DocumentVaultViewModel(
            authenticator: { _ in true },
            loadContents: {
                .init(documents: [doc], numbers: [doc.id: "X12345678"], photos: [doc.id: UIImage()])
            }
        )
        await vm.authenticate()
        return (vm, doc)
    }

    /// Defect: `DocumentVaultViewModel` never set `isAuthenticated` back to
    /// false, so a passport number decrypted at the check-in desk was still on
    /// screen, and in memory, the next time the phone came out of a pocket.
    @Test func goingToTheBackgroundLocksTheVaultAndClearsEveryDecryptedValue() async {
        let (vm, doc) = await Self.unlockedVault()
        #expect(vm.isAuthenticated)
        #expect(vm.decryptedNumbers[doc.id] == "X12345678")
        #expect(vm.photo(for: doc.id) != nil)

        vm.handleScenePhase(.background)

        #expect(!vm.isAuthenticated)
        #expect(vm.decryptedNumbers.isEmpty)
        #expect(vm.decryptedPhotos.isEmpty)
        #expect(vm.documents.isEmpty)
    }

    /// The Face ID / Touch ID sheet makes the scene inactive, so locking on
    /// `.inactive` would lock the vault the moment it unlocked.
    @Test func becomingInactiveLeavesTheVaultUnlocked() async {
        let (vm, doc) = await Self.unlockedVault()

        vm.handleScenePhase(.inactive)

        #expect(vm.isAuthenticated)
        #expect(vm.decryptedNumbers[doc.id] == "X12345678")
    }

    @Test func comingBackToTheForegroundNeedsAFreshPrompt() async {
        let prompts = PromptCounter()
        let vm = DocumentVaultViewModel(
            authenticator: { _ in prompts.count += 1; return true },
            loadContents: { .init() }
        )
        await vm.authenticate()
        vm.handleScenePhase(.background)
        vm.handleScenePhase(.active)
        #expect(!vm.isAuthenticated)

        await vm.authenticate()
        #expect(prompts.count == 2)
        #expect(vm.isAuthenticated)
    }

    /// `DocumentVaultStore.save` replaces the whole store. An Add Document
    /// sheet left open across a lock would otherwise save its one new document
    /// over the emptied list and erase the rest of the vault.
    @Test func addingADocumentAfterTheVaultLockedIsRefused() async {
        let (vm, _) = await Self.unlockedVault()
        vm.lock()

        await vm.addDocument(Self.passport(), photo: nil)

        #expect(vm.documents.isEmpty)
        #expect(vm.decryptedNumbers.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func aDeviceWithNoPasscodeIsToldToSetUpItsOwnBiometric() async {
        let vm = DocumentVaultViewModel(
            authenticator: { _ in throw VaultAuthError.unavailable(BiometryLabel(biometryType: .touchID)) },
            loadContents: { .init() }
        )

        await vm.authenticate()

        #expect(!vm.isAuthenticated)
        #expect(vm.errorMessage == "Set up Touch ID or a device passcode to use the Document Vault.")
    }
}
