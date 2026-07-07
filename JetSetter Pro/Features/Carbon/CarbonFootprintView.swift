// File: Features/Carbon/CarbonFootprintView.swift
//
// CO₂ emissions calculator for the user's flights, plus a deep link to offset
// providers (Cool Effect / Wren / Terrapass). Uses ICAO-style emissions math:
// distance × fuel-per-km × class-multiplier × passenger-share.

import SwiftUI
import CoreLocation

struct CarbonFootprintView: View {

    @State private var origin: String = "SFO"
    @State private var destination: String = "NRT"
    @State private var travelClass: TravelClass = .economy
    @State private var passengers: Int = 1
    @State private var offsetURL: URL?   // in-app web sheet target (§7.7)

    private var distanceKm: Double? {
        // Treat identical origin/destination as invalid input rather than a valid
        // 0 km journey (which would render a nonsensical "0 kg CO₂e" result).
        guard origin.uppercased() != destination.uppercased(),
              let from = AirportCoordinates.coordinate(for: origin),
              let to = AirportCoordinates.coordinate(for: destination) else { return nil }
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        // Great-circle distance under-reports real routed distance (airways, holding,
        // detours). Apply an ICAO-style distance-correction factor (~8%) so emissions
        // and offset cost aren't systematically under-estimated.
        let greatCircleKm = fromLoc.distance(from: toLoc) / 1000.0
        return greatCircleKm * CarbonMath.routingCorrectionFactor
    }

    /// Warming-equivalent emissions (includes radiative-forcing uplift). Used for the
    /// headline CO₂e figure only.
    private var co2eKg: Double? {
        guard let km = distanceKm else { return nil }
        return CarbonMath.co2e(distanceKm: km, travelClass: travelClass, passengers: passengers)
    }

    /// Physical CO₂ mass actually emitted (no radiative-forcing uplift). Used for
    /// offset pricing, tree-years, and driving comparisons, which describe real CO₂.
    private var co2MassKg: Double? {
        guard let km = distanceKm else { return nil }
        return CarbonMath.co2Mass(distanceKm: km, travelClass: travelClass, passengers: passengers)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputCard
                if let co2e = co2eKg, let mass = co2MassKg, let km = distanceKm {
                    resultCard(co2e: co2e, km: km)
                    comparisonCard(co2Mass: mass)
                    offsetCard(co2Mass: mass)
                } else if !origin.isEmpty && !destination.isEmpty {
                    unknownAirportCard
                }
                methodologyCard
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .inAppWeb(url: $offsetURL, title: "Carbon Offset")
        .navigationTitle("Carbon Footprint")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Cards

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("FLIGHT", systemImage: "airplane")

            HStack(spacing: 8) {
                airportField(label: "FROM", text: $origin)
                Image(systemName: "arrow.right")
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                airportField(label: "TO", text: $destination)
            }

            Picker("Travel class", selection: $travelClass) {
                ForEach(TravelClass.allCases, id: \.self) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)

            Stepper("\(passengers) \(passengers == 1 ? "passenger" : "passengers")", value: $passengers, in: 1...10)
                .font(.subheadline)
        }
        .padding(16)
        .jetCard()
    }

    private func resultCard(co2e: Double, km: Double) -> some View {
        VStack(spacing: 10) {
            Text("\(String(format: "%.0f", co2e))")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text("kg CO₂e")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .tracking(1.5)

            HStack(spacing: 16) {
                statColumn(label: "DISTANCE", value: "\(Int(km)) km")
                Divider().frame(height: 30)
                statColumn(label: "PER PERSON", value: "\(Int(co2e / Double(passengers))) kg")
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    // Comparisons describe physical CO₂ processes (sequestration, tailpipe, grid),
    // so they're fed the un-inflated physical CO₂ mass, not the RF-adjusted CO₂e.
    private func comparisonCard(co2Mass: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("IN PERSPECTIVE", systemImage: "scalemass.fill")
            VStack(spacing: 12) {
                comparisonRow(
                    icon: "tree.fill",
                    text: "\(Int(co2Mass / 21)) tree-years of sequestration to offset",
                    tint: JetsetterTheme.Colors.success
                )
                comparisonRow(
                    icon: "car.fill",
                    text: "Same as driving \(Int(co2Mass * 5)) km in an average car",
                    tint: JetsetterTheme.Colors.accent
                )
                comparisonRow(
                    icon: "bolt.fill",
                    text: "Powers \(Int(co2Mass / 0.4)) hours of typical US home electricity",
                    tint: .orange
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    // Offset providers retire actual CO₂ tonnage, so pricing is based on the physical
    // CO₂ mass rather than the RF-inflated warming-equivalent (CO₂e).
    private func offsetCard(co2Mass: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("OFFSET THIS FLIGHT", systemImage: "leaf.fill")

            Text("Verified offset providers retire carbon credits in the same year you fly. Typical cost: $0.40–$1.20 per 100 kg CO₂.")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)

            let estCost = co2Mass / 100 * 0.80
            Text(String(format: "Estimated cost: $%.2f", estCost))
                .font(.subheadline.bold())
                .padding(.top, 2)

            VStack(spacing: 8) {
                offsetButton(name: "Cool Effect",
                             url: "https://www.cooleffect.org/business/fly-clean",
                             tagline: "Gold-standard, retired in your name")
                offsetButton(name: "Wren",
                             url: "https://www.wren.co/calculator/flight",
                             tagline: "Monthly subscription for total emissions")
                offsetButton(name: "Terrapass",
                             url: "https://www.terrapass.com/carbon-footprint-calculator-flights",
                             tagline: "US-based projects, custom volumes")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private var unknownAirportCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Airport not recognized")
                .font(.headline)
            Text("Try a 3-letter IATA code like SFO, JFK, LHR, NRT.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("METHODOLOGY", systemImage: "info.circle")
            Text("Based on ICAO Carbon Emissions Calculator methodology. Distance × jet fuel consumption × class-of-service multiplier × passenger share. Includes radiative forcing factor for high-altitude emissions.")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    // MARK: - Reusable bits

    private func airportField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.5)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            TextField("IATA", text: text)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(1.3)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
    }

    private func comparisonRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func offsetButton(name: String, url: String, tagline: String) -> some View {
        Button {
            offsetURL = URL(string: url)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(tagline)
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemFill).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.caption.bold())
            Text(text)
                .font(JetsetterTheme.Typography.label)
                .tracking(1.5)
        }
        .foregroundStyle(JetsetterTheme.Colors.accent)
    }
}

// MARK: - Math + types

enum TravelClass: String, CaseIterable {
    case economy, premium, business, first

    var label: String {
        switch self {
        case .economy:   return "Economy"
        case .premium:   return "Premium"
        case .business:  return "Business"
        case .first:     return "First"
        }
    }

    /// ICAO class-of-service multiplier — premium passengers consume more
    /// fuel per seat due to larger cabin footprint.
    var multiplier: Double {
        switch self {
        case .economy:   return 1.0
        case .premium:   return 1.5
        case .business:  return 2.9
        case .first:     return 4.0
        }
    }
}

enum CarbonMath {

    /// ICAO-style distance correction: great-circle distance under-reports the real
    /// routed distance (airways, holding, detours) by roughly 5–10%.
    static let routingCorrectionFactor: Double = 1.08

    /// Radiative-forcing uplift for high-altitude emissions. Converts physical CO₂
    /// mass into a warming-equivalent (CO₂e) figure.
    private static let radiativeForcingFactor: Double = 1.9

    /// Returns the physical CO₂ mass (kg) actually emitted for the journey — no
    /// radiative-forcing uplift. Use this for anything describing real CO₂: offset
    /// pricing, tree-year sequestration, tailpipe/driving comparisons.
    /// Formula: (climb burn + distance × cruise factor) × class multiplier × passengers.
    static func co2Mass(distanceKm: Double, travelClass: TravelClass, passengers: Int) -> Double {
        // Model per-passenger CO₂ as a fixed climb component plus a per-km cruise
        // component, so total emissions are strictly monotonic in distance. This
        // replaces the old hard 0.255→0.150 step at 1500 km, which made a slightly
        // longer flight report dramatically LESS CO₂ across the boundary.
        // Climb fuel is amortized over distance, so the effective per-km factor
        // decays smoothly from ~0.255 (short-haul) toward the 0.150 cruise floor.
        let climbCO2: Double = 105.0          // fixed climb-out burn, kg CO₂/passenger
        let cruiseFactor: Double = 0.150      // kg CO₂/passenger-km at cruise
        let baseCO2 = climbCO2 + distanceKm * cruiseFactor
        return baseCO2
            * travelClass.multiplier
            * Double(passengers)
    }

    /// Returns the warming-equivalent emissions (kg CO₂e) — physical CO₂ mass scaled
    /// by the radiative-forcing factor. Use this only for the headline CO₂e figure.
    static func co2e(distanceKm: Double, travelClass: TravelClass, passengers: Int) -> Double {
        co2Mass(distanceKm: distanceKm, travelClass: travelClass, passengers: passengers)
            * radiativeForcingFactor
    }
}

#Preview {
    NavigationStack { CarbonFootprintView() }
}
