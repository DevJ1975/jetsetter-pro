// File: Core/Services/SITAWorldTracerService.swift

import Foundation

// MARK: - WorldTracer Error

enum WorldTracerError: LocalizedError {
    case invalidTagNumber
    case bagNotFound
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidTagNumber:
            return "Please enter a valid 10-digit bag tag number."
        case .bagNotFound:
            return "No baggage record found for this tag number. It may not have been processed yet."
        case .apiError(let message):
            return "WorldTracer error: \(message)"
        }
    }
}

// MARK: - SITAWorldTracerService

/// Wraps the SITA WorldTracer REST API for airline baggage tracing.
/// NOTE: WorldTracer requires an enterprise partner agreement with SITA.
/// Contact SITA at https://www.sita.aero/solutions/sita-for-aircraft/baggage for access.
final class SITAWorldTracerService {

    static let shared = SITAWorldTracerService()
    private init() {}

    // MARK: - Trace Bag

    /// Looks up a bag by its IATA 10-digit bag tag number and returns the current status.
    func traceBag(tagNumber: String) async throws -> WorldTracerBagResponse {
        let cleaned = tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                               .replacingOccurrences(of: " ", with: "")

        guard cleaned.count >= 7 && cleaned.count <= 10,
              cleaned.allSatisfy(\.isNumber) else {
            throw WorldTracerError.invalidTagNumber
        }

        guard let url = Endpoints.WorldTracer.baggageURL(tagNumber: cleaned) else {
            throw APIError.invalidURL
        }

        do {
            let response: WorldTracerBagResponse = try await APIClient.shared.get(
                url: url,
                headers: Endpoints.WorldTracer.headers
            )
            return response
        } catch APIError.requestFailed(let statusCode) where statusCode == 404 {
            throw WorldTracerError.bagNotFound
        } catch {
            throw error
        }
    }
}
