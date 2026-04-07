// File: Core/Network/APIClient.swift

import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case .requestFailed(let statusCode):
            return "Request failed with status code \(statusCode)."
        case .decodingFailed(let error):
            return "Failed to decode the response: \(error.localizedDescription)"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Client

/// Shared HTTP client for all Jetsetter network requests.
/// All methods are async/await and throw typed APIErrors.
final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        // FlightAware and most APIs return snake_case keys
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Parse ISO 8601 date strings automatically
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - GET Request

    /// Performs a GET request and decodes the JSON response into the specified type.
    func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await perform(request: request)
    }

    // MARK: - POST Request

    /// Performs a POST request with a JSON body and decodes the JSON response.
    func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.unknown(error)
        }

        return try await perform(request: request)
    }

    // MARK: - Core Request Executor

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unknown(error)
        }

        // Validate HTTP status code
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        // Decode the response body
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}
