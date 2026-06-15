// File: Core/Utilities/QRCodeGenerator.swift
//
// Generates scannable QR code UIImages from arbitrary strings. Used by the
// boarding pass detail view to render the iconic bottom-of-pass QR.

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {

    private static let context = CIContext()

    /// Returns a black-and-white QR code UIImage scaled to the requested side length.
    /// `errorCorrection`: "L"=7%, "M"=15%, "Q"=25%, "H"=30% (default "M" — works for most demos).
    static func image(from string: String, size: CGFloat, errorCorrection: String = "M") -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue(errorCorrection, forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }

        // Scale to the requested size. CI returns ~23×23 native; we scale up cleanly.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
