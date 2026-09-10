// File: Features/Itinerary/BoardingPassScannerView.swift

import SwiftUI
import VisionKit
import Vision

// MARK: - BoardingPassScannerView

/// Full-screen live-camera scanner for the PDF417 barcode on a boarding pass.
/// Wraps VisionKit's `DataScannerViewController` (barcode mode) and fires
/// `onScan` with the raw BCBP payload the first time a barcode is recognized.
///
/// Mirrors the `CameraTextScanner` pattern in TranslatorView.swift, but recognizes
/// barcode symbologies instead of text and auto-captures rather than waiting for a tap.
struct BoardingPassScannerView: UIViewControllerRepresentable {

    let onScan: (String) -> Void
    let onFailure: (String) -> Void

    // Boarding passes are PDF417; include a few common fallbacks in case an
    // airline prints Aztec/QR/Code128 instead.
    private static let symbologies: [VNBarcodeSymbology] = [.pdf417, .aztec, .qr, .code128]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            let message = "Couldn't start the camera scanner: \(error.localizedDescription)"
            DispatchQueue.main.async { onFailure(message) }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BoardingPassScannerView
        // Fire onScan only once; the scanner keeps recognizing until dismissed.
        private var didCapture = false

        init(parent: BoardingPassScannerView) { self.parent = parent }

        // Auto-capture the first barcode that appears in frame.
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            capture(from: addedItems)
        }

        // Also honor an explicit tap, in case highlighting requires it.
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            capture(from: [item])
        }

        private func capture(from items: [RecognizedItem]) {
            guard !didCapture else { return }
            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue, !payload.isEmpty {
                    didCapture = true
                    parent.onScan(payload)
                    return
                }
            }
        }
    }
}
