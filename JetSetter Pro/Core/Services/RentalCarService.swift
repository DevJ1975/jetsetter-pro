// File: Core/Services/RentalCarService.swift
//
// Finds rental-car counters near a pickup point with MapKit local search.
// The previous implementation called `api.enterprise.com`, `api.hertz.com`
// and `api.nationalcar.com` — hosts that were never real — so every search
// failed. MapKit's point-of-interest data needs no partner contract and no
// key, and Apple Maps already knows every counter at every airport.

import Foundation
import CoreLocation
import MapKit

// MARK: - Errors

enum RentalCarError: LocalizedError {
    case invalidLocation
    case invalidDateRange
    case locationNotFound(String)
    case noCountersFound

    var errorDescription: String? {
        switch self {
        case .invalidLocation:
            return "Please enter a pickup location."
        case .invalidDateRange:
            return "Drop-off date must be after pickup date."
        case .locationNotFound(let query):
            return "Couldn't find \"\(query)\". Try an airport code like ORD or a city name."
        case .noCountersFound:
            return "No rental counters found near there. Try a larger city or the nearest airport."
        }
    }
}

// MARK: - Service

@MainActor
final class RentalCarService {

    static let shared = RentalCarService()
    private init() {}

    /// Search radius around the pickup point. Airport rental lots are often a
    /// shuttle ride away from the terminal, so this is deliberately generous.
    private let searchRadiusMeters: CLLocationDistance = 15_000

    /// Finds rental counters near `params.pickupLocation`, nearest first.
    func searchCounters(params: RentalCarSearchParams) async throws -> [RentalCounter] {
        let query = params.pickupLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RentalCarError.invalidLocation }
        guard params.dropoffDate > params.pickupDate else { throw RentalCarError.invalidDateRange }

        let center = try await resolve(query)
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "car rental"
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadiusMeters * 2,
            longitudinalMeters: searchRadiusMeters * 2
        )
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.carRental])

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            // MapKit reports zero hits as an error; that's our "none nearby".
            throw RentalCarError.noCountersFound
        }
        var seenIDs = Set<String>()
        let counters = response.mapItems.compactMap { item -> RentalCounter? in
            let coordinate = item.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= searchRadiusMeters * 2 else { return nil }
            let name = item.name ?? "Car rental"
            let id = "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
            guard seenIDs.insert(id).inserted else { return nil }
            return RentalCounter(
                id: id,
                brand: RentalBrand.detect(from: name),
                name: name,
                address: item.placemark.title ?? "",
                coordinate: coordinate,
                distanceMeters: distance,
                phoneNumber: item.phoneNumber,
                websiteURL: item.url,
                mapItem: item
            )
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        guard !counters.isEmpty else { throw RentalCarError.noCountersFound }
        return counters
    }

    // MARK: - Location resolution

    /// Airport codes resolve from the bundled table (no network); anything else
    /// goes through the system geocoder.
    private func resolve(_ query: String) async throws -> CLLocationCoordinate2D {
        guard let coordinate = await AirportCoordinates.resolve(query) else {
            throw RentalCarError.locationNotFound(query)
        }
        return coordinate
    }
}
