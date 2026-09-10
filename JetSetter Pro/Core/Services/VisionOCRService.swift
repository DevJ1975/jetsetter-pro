// File: Core/Services/VisionOCRService.swift
//
// Receipt OCR, entirely on device:
//   1. Apple Vision (`RecognizeTextRequest`) reads the receipt text.
//   2. Apple Intelligence (FoundationModels guided generation) pulls out the
//      merchant, total and currency when it's available; the regex parser below
//      is the fallback and the tie-breaker.
// The receipt image never leaves the phone. (The previous implementation
// base64-encoded the photo and sent it to Google Cloud Vision.)

import Foundation
import UIKit
import Vision
import FoundationModels

// MARK: - OCR Error

enum OCRError: LocalizedError {
    case imageEncodingFailed
    case noTextDetected
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:      return "Could not process the image. Please try again."
        case .noTextDetected:           return "No text was detected in this image."
        case .recognitionFailed(let m): return "Couldn't read the receipt: \(m)"
        }
    }
}

// MARK: - VisionOCRService

/// Reads a receipt image on device and extracts text, amount, and merchant.
final class VisionOCRService {

    static let shared = VisionOCRService()
    private init() {}

    // MARK: - Annotate

    /// Runs Vision text recognition on `image` and returns a parsed OCRReceiptResult.
    func annotateReceipt(image: UIImage) async throws -> OCRReceiptResult {
        let rawText = try await recognizeText(in: image)
        guard !rawText.isEmpty else { throw OCRError.noTextDetected }

        var result = parseReceiptText(rawText)

        // Second pass with the on-device model: better at "which number is the
        // total" than a keyword scan, and it knows merchant names when the
        // header line is a logo or an address.
        if let fields = await ReceiptFieldExtractor.shared.extract(from: rawText) {
            let amount = (fields.total > 0) ? fields.total : result.extractedAmount
            let merchant = fields.merchant.isEmpty ? result.extractedMerchant : fields.merchant
            result = OCRReceiptResult(
                extractedAmount: amount,
                extractedMerchant: merchant,
                rawText: rawText
            )
        }
        return result
    }

    // MARK: - Vision

    /// Longest edge handed to Vision. Receipt text is fully legible at this size
    /// and it keeps a 48 MP capture from costing seconds of recognition.
    private static let maxRecognitionEdge: CGFloat = 2_000

    private func recognizeText(in image: UIImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let source = Self.downscaled(image, maxEdge: Self.maxRecognitionEdge)
        let observations: [RecognizedTextObservation]
        do {
            if let cgImage = source.cgImage {
                observations = try await request.perform(on: cgImage, orientation: Self.orientation(for: source))
            } else if let data = source.jpegData(compressionQuality: 0.9) {
                observations = try await request.perform(on: data)
            } else {
                throw OCRError.imageEncodingFailed
            }
        } catch let error as OCRError {
            throw error
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        // Vision returns observations roughly top-to-bottom; keep that order so the
        // merchant heuristic ("first meaningful line") still holds.
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Returns `image` scaled so its longest edge is at most `maxEdge` points,
    /// or the original when it's already small enough. Drawing through a
    /// renderer also bakes in the EXIF orientation, so the result is `.up`.
    static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func orientation(for image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    // MARK: - Receipt Parsing (regex fallback)

    /// Extracts amount and merchant name from raw OCR text using regex patterns.
    /// Regex-only parse of receipt text (exposed for tests; the model pass sits on top).
    func parseReceiptText(_ text: String) -> OCRReceiptResult {
        OCRReceiptResult(
            extractedAmount: extractAmount(from: text),
            extractedMerchant: extractMerchant(from: text),
            rawText: text
        )
    }

    /// Finds the most likely total: the largest currency-looking number on a line
    /// mentioning TOTAL / AMOUNT DUE / BALANCE (but not SUBTOTAL), else the largest
    /// amount anywhere.
    private func extractAmount(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        // Any run of digits, optional thousands groups, optional 1–2 decimals:
        // "1234.56", "$1,250.00", "1.234,56", "¥20,350". The lookarounds stop a
        // match from starting or ending inside a longer number.
        let amountRegex = try? NSRegularExpression(pattern: #"(?<![\d.,])(\d+(?:[.,]\d{3})*(?:[.,]\d{1,2})?)(?![\d])"#)

        /// Amounts on `line`. Whole numbers ("20,350", "45") are only trusted on
        /// a TOTAL line (`allowIntegers`); elsewhere they're usually dates,
        /// phone numbers or item counts.
        func amounts(in line: String, allowIntegers: Bool) -> [Double] {
            guard let amountRegex else { return [] }
            let ns = line as NSString
            return amountRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
                var digits = ns.substring(with: match.range(at: 1))
                // A trailing separator group of exactly three digits is a thousands
                // group ("20,350" → 20350); one or two digits is the fraction.
                if let last = digits.lastIndex(where: { $0 == "." || $0 == "," }) {
                    let fraction = digits[digits.index(after: last)...]
                    let whole = digits[..<last].filter(\.isNumber)
                    if fraction.count == 3 {
                        guard allowIntegers else { return nil }
                        digits = whole + fraction
                    } else {
                        digits = whole + "." + fraction
                    }
                } else if !allowIntegers {
                    return nil
                }
                return Double(digits)
            }
        }

        let totalKeywords = ["grand total", "amount due", "balance due", "total due", "total", "amount paid"]
        var keywordAmounts: [Double] = []
        for line in lines {
            let lower = line.lowercased()
            guard !lower.contains("subtotal"), !lower.contains("sub total"),
                  totalKeywords.contains(where: { lower.contains($0) }) else { continue }
            keywordAmounts.append(contentsOf: amounts(in: line, allowIntegers: true))
        }
        if let best = keywordAmounts.max() { return best }
        return lines.flatMap { amounts(in: $0, allowIntegers: false) }.max()
    }

    /// The first line that reads like a name rather than an address, phone
    /// number, date, or receipt noise.
    private func extractMerchant(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && $0.count <= 40 }
        if let clean = lines.prefix(10).first(where: { !looksLikeReceiptNoise($0) }) {
            return clean
        }
        // Nothing passed the filter: the top line is still the best guess.
        return lines.first(where: { $0.filter(\.isLetter).count >= 3 })
    }

    /// Banner words are matched as whole words, so "Hotel Danieli" (tel),
    /// "Border Grill" (order) and "Timeless Café" (time) still count as names.
    private func looksLikeReceiptNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("www.") || lower.contains(".com") || lower.contains("http") || lower.contains("#") {
            return true
        }
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let bannedWords: Set<String> = ["receipt", "invoice", "thank", "thanks", "welcome", "order", "table",
                                        "server", "cashier", "tel", "phone", "date", "time", "guest", "check"]
        if !words.isDisjoint(with: bannedWords) { return true }
        let digits = line.filter(\.isNumber).count
        let letters = line.filter(\.isLetter).count
        if letters == 0 || digits > letters { return true }
        let streetSuffixes = [" st", " ave", " rd", " blvd", " street", " avenue", " road", " suite", " ste "]
        if streetSuffixes.contains(where: { lower.hasSuffix($0) || lower.contains($0 + " ") }) { return true }
        return false
    }
}

// MARK: - On-device field extraction

/// Pulls structured fields out of receipt text with Apple Intelligence. Returns
/// nil whenever the model is unavailable or declines, so callers fall back to
/// the regex parser without special-casing.
@MainActor
final class ReceiptFieldExtractor {

    static let shared = ReceiptFieldExtractor()
    private init() {}

    struct Fields {
        let merchant: String
        let total: Double
        let currency: String?
    }

    func extract(from text: String) async -> Fields? {
        guard #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        return await extractOnDevice(from: text)
    }

    @available(iOS 26.0, *)
    private func extractOnDevice(from text: String) async -> Fields? {
        let session = LanguageModelSession(instructions: """
        You read the text of a purchase receipt and extract the merchant name, the \
        final amount paid (the grand total, never a subtotal, tax line or change due), \
        and the currency code. Copy numbers exactly as printed.
        """)
        do {
            let response = try await session.respond(
                to: "Receipt text:\n\(text.prefix(1200))",
                generating: ReceiptFields.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let fields = response.content
            return Fields(
                merchant: fields.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                total: fields.total,
                currency: fields.currency
            )
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, *)
@Generable
nonisolated struct ReceiptFields {
    @Guide(description: "Merchant or store name as printed near the top of the receipt")
    var merchant: String
    @Guide(description: "The final total paid, as a decimal number")
    var total: Double
    @Guide(description: "ISO 4217 currency code if it can be inferred, e.g. USD, EUR, JPY")
    var currency: String?
}
