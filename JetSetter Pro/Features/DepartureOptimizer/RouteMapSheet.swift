// File: Features/DepartureOptimizer/RouteMapSheet.swift
//
// In-app route guidance for the Departure Optimizer (IOS_PARITY_NOTES.md §7.6).
// Draws the drive from the traveler's location to the departure airport on a
// real MapKit map and runs a simulated "Start drive" that moves the position
// marker while remaining time / distance / ETA count down. Fully in-app — no
// hand-off to Apple Maps (§7.7 in-app-only rule).

import SwiftUI
import MapKit
import CoreLocation

struct RouteMapSheet: View {

    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let destinationName: String
    /// Live drive estimate (minutes) from the Departure Optimizer.
    let driveMinutes: Int

    @Environment(\.dismiss) private var dismiss
    private let accent = JetsetterTheme.Colors.accent

    @State private var camera: MapCameraPosition = .automatic
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var totalMeters: CLLocationDistance = 0
    @State private var progress: Double = 0        // 0…1 along the route
    @State private var isDriving = false
    @State private var driveTask: Task<Void, Never>?

    // Simulated run compresses the whole drive into ~24s so a presenter can
    // watch the countdown move without waiting the real drive time.
    private let simulationSeconds: Double = 24

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                map
                    .ignoresSafeArea(edges: .top)
                controlPanel
            }
            .navigationTitle("Route to \(destinationName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { stopDrive(); dismiss() }
                }
            }
            .task { await computeRoute() }
            .onDisappear { driveTask?.cancel() }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            if routeCoords.count > 1 {
                MapPolyline(coordinates: routeCoords)
                    .stroke(accent, lineWidth: 6)
            }
            Marker(destinationName, systemImage: "airplane.departure", coordinate: destination)
                .tint(accent)
            Annotation("You", coordinate: currentPosition) {
                ZStack {
                    Circle().fill(.white).frame(width: 26, height: 26)
                    Image(systemName: "car.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                }
                .shadow(radius: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    // MARK: - Control panel

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                metric(title: "TIME", value: "\(remainingMinutes) min")
                Divider().frame(height: 34)
                metric(title: "DISTANCE", value: remainingDistanceText)
                Divider().frame(height: 34)
                metric(title: "SIM ETA", value: etaText)
            }

            Button {
                isDriving ? stopDrive() : startDrive()
            } label: {
                HStack {
                    Image(systemName: isDriving ? "pause.fill" : "play.fill")
                    Text(isDriving ? "Pause drive" : "Start drive")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(16)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black)).tracking(1.5)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived values

    /// Interpolated position along the route for the current progress.
    private var currentPosition: CLLocationCoordinate2D {
        guard routeCoords.count > 1 else { return origin }
        let clamped = min(max(progress, 0), 1)
        let scaled = clamped * Double(routeCoords.count - 1)
        let i = Int(scaled)
        if i >= routeCoords.count - 1 { return routeCoords.last! }
        let f = scaled - Double(i)
        let a = routeCoords[i], b = routeCoords[i + 1]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * f,
            longitude: a.longitude + (b.longitude - a.longitude) * f
        )
    }

    private var remainingMinutes: Int {
        max(0, Int((Double(driveMinutes) * (1 - progress)).rounded()))
    }

    private var remainingDistanceText: String {
        let miles = (totalMeters / 1609.34) * (1 - progress)
        return String(format: "%.1f mi", max(0, miles))
    }

    /// Arrival time derived from the (compressed) simulated remaining minutes,
    /// so it collapses as the sim runs. Surfaced as "SIM ETA", not a real ETA;
    /// wire to wall-clock start + real travel time if this ever drives live nav.
    private var etaText: String {
        let eta = Date().addingTimeInterval(Double(remainingMinutes) * 60)
        return eta.formatted(.dateTime.hour().minute())
    }

    // MARK: - Route + simulation

    private func computeRoute() async {
        let request = MKDirections.Request()
        request.source = mapItem(for: origin)
        request.destination = mapItem(for: destination)
        request.transportType = .automobile

        guard let route = try? await MKDirections(request: request).calculate().routes.first else {
            // No route (e.g. offline) — fall back to a straight origin→dest line.
            routeCoords = [origin, destination]
            totalMeters = straightLineMeters(origin, destination)
            camera = .region(region(for: routeCoords))
            return
        }
        routeCoords = route.polyline.coordinates
        totalMeters = route.distance
        camera = .region(region(for: routeCoords))
    }

    private func startDrive() {
        guard routeCoords.count > 1 else { return }
        isDriving = true
        driveTask?.cancel()
        driveTask = Task {
            let steps = 120
            let stepDelay = Duration.seconds(simulationSeconds / Double(steps))
            var current = progress
            while current < 1, !Task.isCancelled {
                current = min(1, current + 1.0 / Double(steps))
                let value = current
                await MainActor.run {
                    withAnimation(.linear(duration: simulationSeconds / Double(steps))) {
                        progress = value
                    }
                }
                try? await Task.sleep(for: stepDelay)
            }
            await MainActor.run { isDriving = false }
        }
    }

    private func stopDrive() {
        isDriving = false
        driveTask?.cancel()
    }

    // MARK: - Helpers

    private func mapItem(for c: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: c))
        }
    }

    private func straightLineMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: destination,
                                      span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4 + 0.02,
                                    longitudeDelta: (maxLon - minLon) * 1.4 + 0.02)
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - MKPolyline → coordinates

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
