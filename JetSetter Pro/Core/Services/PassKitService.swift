// File: Core/Services/PassKitService.swift
//
// Imports .pkpass boarding passes into the Travel Wallet and presents the
// system "Add to Apple Wallet" sheet.

import Foundation
import PassKit
import SwiftUI
import UIKit

enum PassKitImportError: LocalizedError {
    case invalidData
    case cannotReadFile
    case notABoardingPass

    var errorDescription: String? {
        switch self {
        case .invalidData:      return "This file isn't a valid Apple Wallet pass."
        case .cannotReadFile:   return "Couldn't read the selected file."
        case .notABoardingPass: return "Only boarding passes can be imported here."
        }
    }
}

enum PassKitService {

    /// Parses a `.pkpass` blob into a Travel Wallet item. The raw bytes are stored
    /// as base64 in `rawData["pkpass_data"]` so the user can later add the pass to
    /// Apple Wallet directly from the detail view.
    static func walletItem(from data: Data) throws -> WalletItem {
        let pass: PKPass
        do {
            pass = try PKPass(data: data)
        } catch {
            throw PassKitImportError.invalidData
        }

        // We only surface boarding passes in Travel Wallet for now.
        // Pass type identifiers for boarding passes look like "pass.com.<airline>.boardingpass".
        let isBoardingPass = pass.passTypeIdentifier.lowercased().contains("boardingpass")
            || pass.passTypeIdentifier.lowercased().contains("boarding")
            || pass.localizedName.lowercased().contains("boarding")
        guard isBoardingPass else {
            throw PassKitImportError.notABoardingPass
        }

        let title = pass.localizedDescription.isEmpty
            ? pass.organizationName
            : pass.localizedDescription

        var rawData: [String: String] = [
            "pkpass_data": data.base64EncodedString(),
            "airline": pass.organizationName,
            "serial_number": pass.serialNumber
        ]
        if !pass.passTypeIdentifier.isEmpty {
            rawData["pass_type_identifier"] = pass.passTypeIdentifier
        }

        return WalletItem(
            id: UUID(),
            tripId: nil,
            itemType: .boardingPass,
            title: title,
            confirmationNumber: pass.serialNumber,
            date: relevantDate(for: pass),
            rawData: rawData
        )
    }

    /// PKPass.relevantDate is deprecated in favor of `relevantDates` (iOS 18+).
    /// We try the new accessor reflectively to stay forward-compatible without a
    /// hard dependency on the new type name. Falls back to `Date()`.
    private static func relevantDate(for pass: PKPass) -> Date {
        let mirror = Mirror(reflecting: pass)
        for child in mirror.children where child.label == "relevantDates" {
            if let list = child.value as? [Any], let first = list.first {
                let inner = Mirror(reflecting: first)
                for grand in inner.children where grand.label == "startDate" {
                    if let d = grand.value as? Date { return d }
                }
            }
        }
        return Date()
    }

    /// Convenience: read a file URL (e.g., from `.fileImporter`) and parse.
    /// File URLs from the document picker are security-scoped — caller must
    /// manage the access scope.
    static func walletItem(fromFileAt url: URL) throws -> WalletItem {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw PassKitImportError.cannotReadFile
        }
        return try walletItem(from: data)
    }

    /// Presents the system add-to-wallet sheet on top of the key window's root VC.
    /// Returns true if the sheet was presented successfully.
    @MainActor
    @discardableResult
    static func presentAddPass(_ pass: PKPass) -> Bool {
        guard let vc = PKAddPassesViewController(pass: pass) else { return false }
        guard let root = activeRootViewController() else { return false }
        root.present(vc, animated: true)
        return true
    }

    @MainActor
    private static func activeRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostViewController()
    }
}

// MARK: - UIViewController helper

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }
        if let nav = self as? UINavigationController,
           let visible = nav.visibleViewController {
            return visible.topMostViewController()
        }
        if let tab = self as? UITabBarController,
           let selected = tab.selectedViewController {
            return selected.topMostViewController()
        }
        return self
    }
}
