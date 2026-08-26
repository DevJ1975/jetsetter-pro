// File: Core/Services/VisionOCRService.swift

import Foundation
import UIKit

// MARK: - Vision Request / Response Models

private struct VisionAnnotateRequest: Encodable {
    let requests: [VisionImageRequest]
}

private struct VisionImageRequest: Encodable {
    let image: VisionImage
    let features: [VisionFeature]
}

private struct VisionImage: Encodable {
    let content: String  // base64-encoded image data
}

private struct VisionFeature: Encodable {
    let type: String
    let maxResults: Int
}

private struct VisionAnnotateResponse: Decodable {
    let responses: [VisionImageResponse]
}

private struct VisionImageResponse: Decodable {
    let textAnnotations: [VisionTextAnnotation]?
    let fullTextAnnotation: VisionFullText?
    let error: VisionError?
}

private struct VisionTextAnnotation: Decodable {
    let description: String
    let locale: String?
}

private struct VisionFullText: Decodable {
    let text: String
}

private struct VisionError: Decodable {
    let message: String
}

// MARK: - OCR Error

enum OCRError: LocalizedError {
    case imageEncodingFailed
    case noTextDetected
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Could not process the image. Please try again."
        case .noTextDetected:      return "No text was detected in this image."
        case .apiError(let msg):   return "OCR failed: \(msg)"
        }
    }
}

// MARK: - VisionOCRService

/// Sends a receipt image to the Google Vision API and extracts text, amount, and merchant.
final class VisionOCRService {

    static let shared = VisionOCRService()
    private init() {}

    // MARK: - Annotate

    /// Submits a UIImage to Google Vision TEXT_DETECTION and returns a parsed OCRReceiptResult.
    func annotateReceipt(image: UIImage) async throws -> OCRReceiptResult {
        // Receipt OCR requires the Google Vision credential. Without it, surface a
        // clear error so the caller can route to manual entry rather than fail
        // opaquely mid-scan.
        guard AppSecrets.isConfigured(.googleVision) else {
            throw OCRError.apiError("Receipt scanning isn't configured. Enter the amount manually.")
        }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw OCRError.imageEncodingFailed
        }

        let base64String = imageData.base64EncodedString()

        let requestBody = VisionAnnotateRequest(requests: [
            VisionImageRequest(
                image: VisionImage(content: base64String),
                features: [VisionFeature(type: "TEXT_DETECTION", maxResults: 1)]
            )
        ])

        guard let url = Endpoints.GoogleVision.annotateURL else {
            throw APIError.invalidURL
        }

        let response: VisionAnnotateResponse = try await APIClient.shared.post(
            url: url,
            body: requestBody,
            headers: Endpoints.GoogleVision.headers
        )

        guard let firstResponse = response.responses.first else {
            throw OCRError.noTextDetected
        }

        if let error = firstResponse.error {
            throw OCRError.apiError(error.message)
        }

        // Prefer fullTextAnnotation for complete text, fall back to first textAnnotation
        let rawText = firstResponse.fullTextAnnotation?.text
            ?? firstResponse.textAnnotations?.first?.description
            ?? ""

        guard !rawText.isEmpty else {
            throw OCRError.noTextDetected
        }

        return parseReceiptText(rawText)
    }

    // MARK: - Receipt Parsing

    /// Extracts amount and merchant name from raw OCR text using regex patterns.
    private func parseReceiptText(_ text: String) -> OCRReceiptResult {
        let extractedAmount = extractAmount(from: text)
        let extractedMerchant = extractMerchant(from: text)

        return OCRReceiptResult(
            extractedAmount: extractedAmount,
            extractedMerchant: extractedMerchant,
            rawText: text
        )
    }

    /// Extracts the receipt total. Prefers a line containing "TOTAL",
    /// "AMOUNT DUE", or "GRAND TOTAL" (case-insensitive) — otherwise falls
    /// back to the largest dollar amount found in the text.
    private func extractAmount(from text: String) -> Double? {
        // Match patterns like $12.34, $1,234.56, 12.34, 1234.56, and
        // integer-only currencies like ¥20,350 / ₩30000 (optional decimals).
        let pattern = #"(?:\$\s?)?((?:\d{1,3}(?:,\d{3})*|\d+)(?:\.\d{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        func amounts(in fragment: String) -> [Double] {
            let range = NSRange(fragment.startIndex..., in: fragment)
            return regex.matches(in: fragment, range: range).compactMap { match in
                guard let matchRange = Range(match.range(at: 1), in: fragment) else { return nil }
                let valueString = fragment[matchRange].replacingOccurrences(of: ",", with: "")
                return Double(valueString)
            }
        }

        // First pass — find a "total" line. "GRAND TOTAL" is checked first so
        // it wins over a plain "TOTAL" / "SUBTOTAL" line on the same receipt.
        // We explicitly skip lines containing "SUBTOTAL" so the regex below
        // (which matches "TOTAL" as a substring) doesn't accidentally grab it.
        let lines = text.components(separatedBy: .newlines)
        let totalKeywords = ["GRAND TOTAL", "AMOUNT DUE", "TOTAL"]

        for keyword in totalKeywords {
            for line in lines {
                let upper = line.uppercased()
                guard upper.contains(keyword) else { continue }
                if keyword == "TOTAL" && upper.contains("SUBTOTAL") { continue }
                if let value = amounts(in: line).max() { return value }
            }
        }

        // Fallback — largest amount anywhere in the text.
        return amounts(in: text).max()
    }

    /// Extracts the merchant name from the top of the receipt.
    ///
    /// The very first lines are often noise — a tagline, a street address, a
    /// phone number, a date, or a "CUSTOMER COPY" banner — rather than the
    /// business name. We skip lines that clearly look like one of those and
    /// return the first remaining candidate. The result is still only a best
    /// guess and is presented to the user as an editable field before saving.
    private func extractMerchant(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }

        // Prefer the first line that reads like a business name; if every
        // candidate looks like noise, fall back to the original first line so
        // we never regress to returning nothing when we used to return something.
        return lines.first(where: { !looksLikeReceiptNoise($0) }) ?? lines.first
    }

    /// Heuristic: does this line look like something other than a merchant name
    /// (address, phone number, date, or a boilerplate banner)?
    private func looksLikeReceiptNoise(_ line: String) -> Bool {
        let upper = line.uppercased()

        // Boilerplate banners printed on many receipts.
        let banners = ["CUSTOMER COPY", "MERCHANT COPY", "RECEIPT", "INVOICE",
                       "THANK YOU", "WELCOME", "ORDER", "TABLE", "SERVER"]
        if banners.contains(where: { upper.contains($0) }) { return true }

        let digitCount = line.filter { $0.isNumber }.count
        let letterCount = line.filter { $0.isLetter }.count

        // Phone numbers / mostly-numeric lines (address street numbers, dates,
        // totals): more digits than letters means this isn't a name.
        if digitCount > 0 && digitCount >= letterCount { return true }

        // Street addresses: a leading street number plus a common suffix.
        let addressKeywords = [" ST", " ST.", " AVE", " AVENUE", " RD", " ROAD",
                               " BLVD", " STREET", " SUITE", " STE ", " FLOOR",
                               " LANE", " LN", " DR", " DRIVE", " HWY"]
        if (line.first?.isNumber ?? false),
           addressKeywords.contains(where: { upper.contains($0) }) {
            return true
        }

        // Dates like 07/06/2026 or 2026-07-06.
        if line.range(of: #"\b\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\b"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
