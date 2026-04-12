// File: Features/AirportMap/AirportMapView.swift

import SwiftUI
import MapKit

// MARK: - AirportMapView

/// Interactive airport map with indoor positioning and gate-to-gate wayfinding.
/// Requires the user's flight itinerary data (airport IATA code, terminal, gate).
struct AirportMapView: View {

    let airportIATA: String
    let terminal: String
    let gate: String
    /// Optional: set when the user has a connecting flight arriving at this airport.
    let arrivalGate: String?

    @StateObject private var viewModel = AirportMapViewModel()
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedPOI: MKMapItem? = nil
    @State private var showLayoverSheet: Bool = false

    init(
        airportIATA: String,
        terminal: String = "",
        gate: String,
        arrivalGate: String? = nil
    ) {
        self.airportIATA = airportIATA
        self.terminal    = terminal
        self.gate        = gate
        self.arrivalGate = arrivalGate
    }

    var body: some View {
        Group {
            switch viewModel.authorizationStatus {
            case .notDetermined:
                permissionRequestView
            case .denied, .restricted:
                permissionDeniedView
            default:
                if viewModel.supportsIndoorMaps {
                    indoorMapView
                } else {
                    unsupportedAirportView
                }
            }
        }
        .navigationTitle("\(airportIATA) — Gate \(gate)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.airportIATA       = airportIATA
            viewModel.departureTerminal = terminal
            viewModel.departureGate     = gate
            viewModel.arrivalGate       = arrivalGate
            viewModel.requestLocationPermission()
        }
        .onDisappear { viewModel.stopTracking() }
    }

    // MARK: - Indoor Map

    private var indoorMapView: some View {
        ZStack(alignment: .bottom) {
            // MapKit map with indoor levels enabled
            Map(position: $mapPosition) {
                // Blue dot — user location
                UserAnnotation()

                // Route polyline overlay
                if let route = viewModel.wayfindingRoute {
                    MapPolyline(route.polyline)
                        .stroke(JetsetterTheme.Colors.accent, lineWidth: 4)
                }

                // Nearby POI markers
                ForEach(viewModel.nearbyPOIs, id: \.self) { poi in
                    if let coord = poi.placemark.location?.coordinate {
                        Annotation(poi.name ?? "POI", coordinate: coord) {
                            POIMarker(poi: poi)
                                .onTapGesture { selectedPOI = poi }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([
                .airport, .restaurant, .cafe, .hotel, .publicTransport
            ])))
            // Show indoor floor selector when inside a supported airport
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .top)

            // Bottom wayfinding card
            VStack(spacing: 0) {
                wayfindingCard
                    .padding(JetsetterTheme.Spacing.medium)

                if let poi = selectedPOI {
                    POIDetailCard(poi: poi) {
                        selectedPOI = nil
                    }
                    .padding(.horizontal, JetsetterTheme.Spacing.medium)
                    .padding(.bottom, JetsetterTheme.Spacing.medium)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: selectedPOI)
        }
        .task { await viewModel.calculateWayfindingRoute() }
        .alert("Map Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Wayfinding Card

    private var wayfindingCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            HStack(spacing: JetsetterTheme.Spacing.medium) {
                // Current location pill
                locationPill(
                    icon: "location.fill",
                    label: "Your Location",
                    value: viewModel.isInsideSupportedAirport
                        ? "Floor \(viewModel.indoorLevelIndex)"
                        : "Outside terminal",
                    color: JetsetterTheme.Colors.success
                )

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                // Destination gate pill
                locationPill(
                    icon: "airplane.departure",
                    label: terminal.isEmpty ? airportIATA : terminal,
                    value: "Gate \(gate)",
                    color: JetsetterTheme.Colors.accent
                )
            }

            Divider()

            HStack {
                // Estimated walk time
                if viewModel.isLoadingRoute {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Calculating route…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let minutes = viewModel.estimatedWalkMinutes {
                    Label("\(minutes) min walk", systemImage: "figure.walk")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                } else {
                    Text("Route unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Layover button — shown when a connecting flight exists
                if let arrivalGate {
                    Button {
                        showLayoverSheet = true
                    } label: {
                        Label("Layover Route", systemImage: "arrow.triangle.swap")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(JetsetterTheme.Colors.warning.opacity(0.15))
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                            .clipShape(Capsule())
                    }
                    .sheet(isPresented: $showLayoverSheet) {
                        LayoverWayfindingSheet(
                            airportIATA: airportIATA,
                            arrivalGate: arrivalGate,
                            departureGate: gate,
                            viewModel: viewModel
                        )
                    }
                    .accessibilityLabel("Show layover walking route from gate \(arrivalGate) to gate \(gate)")
                }
            }

            // Indoor floor indicator badge
            if viewModel.isInsideSupportedAirport {
                HStack(spacing: 4) {
                    Image(systemName: "building.fill")
                        .font(.caption2)
                    Text("Indoor positioning active · Floor \(viewModel.indoorLevelIndex)")
                        .font(.caption2)
                }
                .foregroundStyle(JetsetterTheme.Colors.success)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private func locationPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Permission Views

    private var permissionRequestView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))
            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("Location Access Needed")
                    .font(.title3).fontWeight(.semibold)
                Text("To show your position inside the airport and guide you to your gate, JetSetter Pro needs access to your location.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }
            Button("Enable Location") {
                viewModel.requestLocationPermission()
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, JetsetterTheme.Spacing.large)
            .padding(.vertical, JetsetterTheme.Spacing.small)
            .background(JetsetterTheme.Colors.accent)
            .cornerRadius(12)
            Spacer()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.danger.opacity(0.5))
            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("Location Disabled")
                    .font(.title3).fontWeight(.semibold)
                Text("Enable Location Services for JetSetter Pro in Settings to use airport wayfinding.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.xlarge)
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, JetsetterTheme.Spacing.large)
            .padding(.vertical, JetsetterTheme.Spacing.small)
            .background(JetsetterTheme.Colors.accent)
            .cornerRadius(12)
            Spacer()
        }
    }

    // MARK: - Unsupported Airport Fallback

    private var unsupportedAirportView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            Image(systemName: "map.fill")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.4))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("\(airportIATA) — Indoor Maps Unavailable")
                    .font(.title3).fontWeight(.semibold)
                Text("Apple Maps does not yet have indoor map data for \(airportIATA). Use the airport's official app or terminal diagram signs to find gate \(gate).")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
            }

            // Still show a standard outdoor map centred on the airport
            Map(position: $mapPosition) {
                UserAnnotation()
            }
            .mapStyle(.standard)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, JetsetterTheme.Spacing.medium)
            .task {
                await centreOnAirport()
            }

            Spacer()
        }
    }

    private func centreOnAirport() async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(airportIATA) airport"
        do {
            let search = MKLocalSearch(request: req)
            let response = try await search.start()
            if let coord = response.mapItems.first?.placemark.coordinate {
                mapPosition = .region(
                    MKCoordinateRegion(center: coord, latitudinalMeters: 3_000, longitudinalMeters: 3_000)
                )
            }
        } catch {}
    }
}

// MARK: - POIMarker

private struct POIMarker: View {
    let poi: MKMapItem

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(radius: 3)
                .frame(width: 32, height: 32)
            Image(systemName: poiIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JetsetterTheme.Colors.accent)
        }
    }

    private var poiIcon: String {
        guard let category = poi.pointOfInterestCategory else { return "mappin" }
        switch category {
        case .restaurant, .cafe, .bakery: return "fork.knife"
        case .hotel:                      return "bed.double.fill"
        default:                          return "mappin"
        }
    }
}

// MARK: - POIDetailCard

private struct POIDetailCard: View {
    let poi: MKMapItem
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: JetsetterTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name ?? "Point of Interest")
                    .font(.subheadline).fontWeight(.semibold)
                if let addr = poi.placemark.thoroughfare {
                    Text(addr)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .padding(JetsetterTheme.Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LayoverWayfindingSheet

/// Sheet shown when the user has a connecting flight and needs to walk from arrival to departure gate.
private struct LayoverWayfindingSheet: View {
    let airportIATA: String
    let arrivalGate: String
    let departureGate: String
    @ObservedObject var viewModel: AirportMapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: JetsetterTheme.Spacing.large) {
                // Route summary header
                HStack(spacing: JetsetterTheme.Spacing.large) {
                    gateLabel(title: "Arriving", gate: arrivalGate, icon: "airplane.arrival", color: JetsetterTheme.Colors.success)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    gateLabel(title: "Departing", gate: departureGate, icon: "airplane.departure", color: JetsetterTheme.Colors.accent)
                }
                .padding(JetsetterTheme.Spacing.large)
                .jetCard()
                .padding(.horizontal, JetsetterTheme.Spacing.medium)

                if viewModel.isLoadingRoute {
                    ProgressView("Calculating layover route…")
                } else if let minutes = viewModel.estimatedWalkMinutes {
                    VStack(spacing: JetsetterTheme.Spacing.small) {
                        Text("\(minutes) min")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(minutes > 30 ? JetsetterTheme.Colors.danger : JetsetterTheme.Colors.success)
                        Text("estimated walk time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, JetsetterTheme.Spacing.large)
                }

                Spacer()
            }
            .navigationTitle("Layover Wayfinding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
        }
        .task {
            await viewModel.calculateLayoverRoute(from: arrivalGate)
        }
    }

    private func gateLabel(title: String, gate: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Gate \(gate)")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AirportMapView(
            airportIATA: "SFO",
            terminal: "International Terminal",
            gate: "A12",
            arrivalGate: "G4"
        )
    }
}
