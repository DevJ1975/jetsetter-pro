// File: UI/Components/FlightMapView.swift
//
// MapKit-backed view that draws a real great-circle route between two airports,
// with markers at each endpoint and an animated airplane traveling along the
// path. Falls back to the abstract FlightAnimationView if either airport is
// outside the bundled coordinate table.

import SwiftUI
import MapKit
import CoreLocation

struct FlightMapView: View {

    let originIATA: String
    let destinationIATA: String

    /// 0.0 = at origin, 1.0 = at destination. When nil, the airplane
    /// continuously loops along the route for visual flair.
    var progress: Double? = nil

    /// When provided, the airplane is anchored to this real-world coordinate
    /// (e.g., live GPS from InFlightTrackingService) instead of synthetic
    /// route progress. Overrides `progress`.
    var liveCoordinate: CLLocationCoordinate2D? = nil

    /// Compact (160pt) for cards, hero (260pt) for detail screens.
    var style: Style = .compact

    enum Style {
        case compact, hero

        var height: CGFloat {
            switch self {
            case .compact: return 160
            case .hero:    return 260
            }
        }
    }

    // MARK: - Body

    var body: some View {
        if let origin = AirportCoordinates.coordinate(for: originIATA),
           let destination = AirportCoordinates.coordinate(for: destinationIATA) {
            mapBody(origin: origin, destination: destination)
        } else {
            // Fallback to the abstract animation when we don't have coordinates.
            LabeledFlightAnimation(
                originIATA: originIATA,
                destinationIATA: destinationIATA,
                style: style == .hero ? .hero : .compact
            )
        }
    }

    @ViewBuilder
    private func mapBody(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let route = GreatCircle.points(from: origin, to: destination, samples: 96)
            let normalized = resolvedProgress(date: context.date)
            let planeIndex = max(0, min(Int(Double(route.count - 1) * normalized), route.count - 1))
            // Live GPS coordinate wins; otherwise fall back to the route position.
            let planePos = liveCoordinate ?? route[planeIndex]
            let heading = liveCoordinate != nil
                ? planeHeadingFromRoute(route: route, near: planePos)
                : planeHeading(route: route, index: planeIndex)

            Map(
                initialPosition: .region(framingRegion(for: route)),
                interactionModes: []
            ) {
                Marker(originIATA, systemImage: "airplane.departure", coordinate: origin)
                    .tint(JetsetterTheme.Colors.accent)
                Marker(destinationIATA, systemImage: "airplane.arrival", coordinate: destination)
                    .tint(JetsetterTheme.Colors.success)
                MapPolyline(coordinates: route)
                    .stroke(
                        JetsetterTheme.Colors.accent.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4])
                    )
                Annotation("", coordinate: planePos, anchor: .center) {
                    Image(systemName: "airplane")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(
                            Circle()
                                .fill(JetsetterTheme.Colors.accent)
                                .shadow(color: JetsetterTheme.Colors.accent.opacity(0.5), radius: 6)
                        )
                        .rotationEffect(.radians(heading))
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: style.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .accessibilityLabel("Map showing flight route from \(originIATA) to \(destinationIATA)")
        }
    }

    // MARK: - Progress

    private func resolvedProgress(date: Date) -> Double {
        if let p = progress { return max(0, min(p, 1)) }
        // Decorative loop: 10 seconds per pass with brief pauses at endpoints.
        let cycle = 11.0
        let phase = date.timeIntervalSince1970.truncatingRemainder(dividingBy: cycle) / cycle
        if phase < 0.05 { return 0 }
        if phase > 0.95 { return 1 }
        let t = (phase - 0.05) / 0.9
        return 0.5 - cos(.pi * t) / 2  // smoothstep
    }

    /// Returns the bearing (radians) of the airplane based on the segment it's
    /// crossing. Used to rotate the airplane symbol.
    private func planeHeading(route: [CLLocationCoordinate2D], index: Int) -> Double {
        guard index + 1 < route.count else {
            return planeHeading(route: route, index: index - 1)
        }
        let from = route[index]
        let to   = route[index + 1]
        // The SF Symbol points east at 0 radians; the bearing from north needs
        // to be rotated by -π/2 to align.
        let bearing = atan2(to.longitude - from.longitude, to.latitude - from.latitude)
        return bearing - .pi / 2
    }

    /// For live coordinates, project onto the closest route segment for heading.
    private func planeHeadingFromRoute(route: [CLLocationCoordinate2D], near point: CLLocationCoordinate2D) -> Double {
        // Find the nearest pre-sampled route point and reuse the segment heading.
        var bestIndex = 0
        var bestDist = Double.infinity
        for (i, p) in route.enumerated() {
            let dLat = p.latitude - point.latitude
            let dLon = p.longitude - point.longitude
            let d = dLat * dLat + dLon * dLon
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        return planeHeading(route: route, index: bestIndex)
    }

    /// MKCoordinateRegion that frames the entire route with padding.
    private func framingRegion(for route: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !route.isEmpty else {
            return MKCoordinateRegion(
                center: .init(latitude: 0, longitude: 0),
                span: .init(latitudeDelta: 180, longitudeDelta: 360)
            )
        }
        let lats = route.map { $0.latitude }
        let lons = route.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Add 30% padding around the route.
        let latDelta = max(2, (maxLat - minLat) * 1.3)
        let lonDelta = max(2, (maxLon - minLon) * 1.3)
        return MKCoordinateRegion(
            center: center,
            span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

// MARK: - Great-circle math

private enum GreatCircle {

    /// Returns an array of `samples` coordinates along the shortest path
    /// between two points on Earth's surface (great-circle path). Uses
    /// spherical linear interpolation (slerp).
    static func points(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        samples: Int
    ) -> [CLLocationCoordinate2D] {
        let count = max(samples, 2)
        let s = toCartesian(start)
        let e = toCartesian(end)
        let dot = max(-1, min(1, s.x * e.x + s.y * e.y + s.z * e.z))
        let omega = acos(dot)

        // Endpoints coincide — return both ends.
        guard omega.isFinite, omega > 0.0001 else {
            return [start, end]
        }
        let sinOmega = sin(omega)

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let a = sin((1 - t) * omega) / sinOmega
            let b = sin(t * omega) / sinOmega
            let x = a * s.x + b * e.x
            let y = a * s.y + b * e.y
            let z = a * s.z + b * e.z
            result.append(fromCartesian(x: x, y: y, z: z))
        }
        return result
    }

    private static func toCartesian(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double, z: Double) {
        let lat = c.latitude * .pi / 180
        let lon = c.longitude * .pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }

    private static func fromCartesian(x: Double, y: Double, z: Double) -> CLLocationCoordinate2D {
        let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Preview

#Preview("JFK → NRT (compact)") {
    ZStack {
        Color(white: 0.08).ignoresSafeArea()
        FlightMapView(originIATA: "JFK", destinationIATA: "NRT")
            .padding()
    }
}

#Preview("SFO → LAX (hero)") {
    ZStack {
        Color(white: 0.08).ignoresSafeArea()
        FlightMapView(originIATA: "SFO", destinationIATA: "LAX", progress: 0.4, style: .hero)
            .padding()
    }
}
