// File: Features/DepartureOptimizer/DepartureRouteMap.swift
//
// The drive from the traveler to the departure airport, drawn beside the
// Departure Optimizer's numbers when the window is regular width (the iPhone
// Ultra's inner display, iPad). On a phone the same route opens full screen
// in `RouteMapSheet`, which adds the simulated drive.
//
// `DepartureRoute` is the one place either view asks MapKit for that route,
// so the inline map and the sheet can't draw two different drives.

import SwiftUI
import MapKit
import CoreLocation

/// Route geometry shared by `DepartureRouteMap` and `RouteMapSheet`.
enum DepartureRoute {

    struct Path {
        var coordinates: [CLLocationCoordinate2D]
        var meters: CLLocationDistance
    }

    /// The driving route, or a straight origin-to-airport line when MapKit
    /// can't route (offline, roaming with data off), so the map still shows
    /// where the airport is rather than nothing.
    static func path(from origin: CLLocationCoordinate2D,
                     to destination: CLLocationCoordinate2D) async -> Path {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile

        guard let route = try? await MKDirections(request: request).calculate().routes.first else {
            return Path(coordinates: [origin, destination],
                        meters: straightLineMeters(origin, destination))
        }
        return Path(coordinates: route.polyline.coordinates, meters: route.distance)
    }

    /// A region that fits the whole route with a margin.
    static func region(for coords: [CLLocationCoordinate2D],
                       fallbackCenter: CLLocationCoordinate2D) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(center: fallbackCenter,
                                      span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4 + 0.02,
                                    longitudeDelta: (maxLon - minLon) * 1.4 + 0.02)
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func mapItem(for c: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
    }

    private static func straightLineMeters(_ a: CLLocationCoordinate2D,
                                           _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// A static map of the drive to the airport: route, airport marker and the
/// traveler's own location. No simulated drive; that stays in the sheet.
struct DepartureRouteMap: View {

    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let destinationName: String

    @State private var camera: MapCameraPosition = .automatic
    @State private var routeCoords: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(position: $camera) {
            if routeCoords.count > 1 {
                MapPolyline(coordinates: routeCoords)
                    .stroke(JetsetterTheme.Colors.accent, lineWidth: 5)
            }
            Marker(destinationName, systemImage: "airplane.departure", coordinate: destination)
                .tint(JetsetterTheme.Colors.accent)
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat))
        // Recomputed only when an end of the route moves, such as a fresh
        // location fix, not on every 60-second refresh of the numbers.
        .task(id: routeKey) {
            let path = await DepartureRoute.path(from: origin, to: destination)
            routeCoords = path.coordinates
            camera = .region(DepartureRoute.region(for: path.coordinates, fallbackCenter: destination))
        }
    }

    private var routeKey: String {
        "\(origin.latitude),\(origin.longitude)>\(destination.latitude),\(destination.longitude)"
    }
}
