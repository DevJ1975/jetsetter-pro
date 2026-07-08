// File: Core/Services/EmailIntelligence/TravelEmailIngestService.swift
//
// Gets raw text into the Email Intelligence pipeline from every supported
// source:
//   • pasted text / .eml / .txt / .ics  → passed through (with light cleanup)
//   • PDF attachments                   → PDFKit text extraction (on-device)
//   • images / screenshots              → Vision OCR (on-device, keyless —
//                                         the cloud VisionOCRService is for
//                                         receipts and stays untouched)
//   • forwarding inbox                  → unprocessed rows in Supabase
//                                         `inbound_emails`, deleted after parse

import Foundation
import PDFKit
import UIKit
import Vision

@MainActor
final class TravelEmailIngestService {

    static let shared = TravelEmailIngestService()
    private init() {}

    enum IngestError: LocalizedError {
        case unreadableFile
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadableFile: return "Couldn't read that file."
            case .noTextFound:    return "No text could be extracted from that file."
            }
        }
    }

    // MARK: - Files

    /// Extracts text from a user-picked file (.pdf, .eml, .txt, .ics).
    func text(fromFileAt url: URL) async throws -> String {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        switch url.pathExtension.lowercased() {
        case "pdf":
            return try textFromPDF(at: url)
        default:
            guard let data = try? Data(contentsOf: url) else {
                throw IngestError.unreadableFile
            }
            guard let string = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw IngestError.unreadableFile
            }
            return string
        }
    }

    private func textFromPDF(at url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw IngestError.unreadableFile
        }
        guard let text = document.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IngestError.noTextFound
        }
        return text
    }

    // MARK: - Images (on-device OCR)

    /// Recognizes text in a screenshot/photo of an email or boarding pass.
    /// Runs entirely on-device via Vision — no API key, nothing uploaded.
    func text(fromImage image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw IngestError.unreadableFile }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                guard !lines.isEmpty else {
                    continuation.resume(throwing: IngestError.noTextFound)
                    return
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Forwarding inbox (Supabase)

    /// Pulls unprocessed forwarded emails, parses each, and deletes the raw
    /// email server-side after a successful parse (privacy: raw mail is not
    /// retained once processed). Returns the merged parse result and how many
    /// emails were consumed.
    func fetchAndParseInbox() async throws -> (parsed: ParsedTravelEmail, emailCount: Int) {
        let rows = try await SupabaseService.shared.fetchInboundEmails()
        var merged = ParsedTravelEmail()
        var consumed = 0

        for row in rows {
            let result = try await TravelEmailParsingService.shared.parse(emailText: row.rawEmail)
            merged.merge(result)
            try? await SupabaseService.shared.deleteInboundEmail(id: row.id)
            consumed += 1
        }
        return (merged, consumed)
    }

    /// The user's forwarding alias (creating one on first use). Nil when not
    /// signed in to Supabase.
    func forwardingAlias() async -> String? {
        let signedIn = await SupabaseService.shared.isSignedIn
        guard signedIn else { return nil }
        return try? await SupabaseService.shared.ensureEmailAlias()
    }
}
