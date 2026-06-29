// File: Features/LuggageTracker/BagDetailView.swift

import SwiftUI

// MARK: - BagDetailView

/// Live detail screen for a single piece of luggage.
/// Shows a status-aware animated header (belt / aircraft loader / static badge)
/// plus a chronological timeline of scan events.
struct BagDetailView: View {

    let bag: Bag

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                carouselETACard
                animationHeader
                findMyHandoffCard
                scanTimeline
                bottomCTAs
            }
            .padding(16)
        }
        .navigationTitle(bag.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .background(JetsetterTheme.Colors.background)
    }

    // MARK: Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(hex: bag.status.colorHex))
                    .frame(width: 52, height: 52)
                    .background(
                        Color(hex: bag.status.colorHex).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(bag.nickname)
                        .font(.headline)
                    if !bag.description.isEmpty {
                        Text(bag.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let tag = bag.bagTagNumber {
                        Text("Tag #\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                statusBadge
                if let airline = bag.airline, let flight = bag.flightNumber {
                    Label("\(airline) · \(flight)", systemImage: "airplane")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: bag.status.systemImage)
                .font(.caption2)
            Text(bag.status.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: bag.status.colorHex).opacity(0.14))
        .foregroundStyle(Color(hex: bag.status.colorHex))
        .cornerRadius(8)
    }

    // MARK: Carousel ETA (phase-derived)

    /// Estimated wait from landing to the bag reaching the carousel — shown for
    /// checked bags that are en route or have just arrived. IRIS uses the same
    /// estimator to time a ride at the destination.
    @ViewBuilder
    private var carouselETACard: some View {
        if let estimate = carouselEstimate {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.title2)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated at baggage claim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("~\(estimate.display) after landing")
                        .font(.headline)
                    Text(estimate.basis)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var carouselEstimate: BagDeliveryEstimator.Estimate? {
        guard bag.bagTagNumber != nil else { return nil }   // checked bags only
        switch bag.status {
        case .inTransit, .loading, .onAircraft, .arrived, .onBelt:
            return BagDeliveryEstimator.estimate(
                airportIATA: destinationIATA ?? "",
                hasCheckedBag: true
            )
        default:
            return nil
        }
    }

    /// Best-effort IATA code parsed from the bag's last reported location
    /// (e.g. "Chicago O'Hare (ORD)" or "NRT — Carousel 4").
    private var destinationIATA: String? {
        guard let loc = bag.lastLocation,
              let range = loc.range(of: "\\b[A-Z]{3}\\b", options: .regularExpression)
        else { return nil }
        return String(loc[range])
    }

    // MARK: Find My Handoff

    /// Honest framing of what's possible: third-party apps cannot read an
    /// AirTag's location (Apple keeps that private to Find My), so we hand off
    /// to Find My and point to Apple's Share Item Location for delayed bags.
    @ViewBuilder
    private var findMyHandoffCard: some View {
        if bag.hasAirTag {
            VStack(alignment: .leading, spacing: 10) {
                Label("Find My Handoff", systemImage: "airtag")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("JetSetter can't read your AirTag's location directly — Apple keeps that private to the Find My app. Open Find My to see this bag, or use Share Item Location there to share it with the airline if it's delayed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    if let url = Endpoints.FindMy.appURL {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open in Find My", systemImage: "location.fill.viewfinder")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Animation Header

    @ViewBuilder
    private var animationHeader: some View {
        Group {
            switch bag.status {
            case .onBelt, .atCarousel:
                BeltAnimationView()
            case .loading, .onAircraft:
                AircraftLoadingView()
            default:
                StaticStatusHeader(status: bag.status)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Scan Timeline

    private var scanTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scan Timeline")
                    .font(.headline)
                Spacer()
                Text("\(bag.scanHistory.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if bag.scanHistory.isEmpty {
                Text("No scan events recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                let sorted = bag.scanHistory.sorted { $0.timestamp > $1.timestamp }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, event in
                        ScanTimelineRow(event: event, isLast: index == sorted.count - 1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Bottom CTAs

    private var bottomCTAs: some View {
        // Find My handoff lives in its own card above; this is the report path.
        Button {
            // Stub — report missing
        } label: {
            Label("Report Missing", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "#CC3B1E").opacity(0.12))
                .foregroundStyle(Color(hex: "#CC3B1E"))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ScanTimelineRow

private struct ScanTimelineRow: View {
    let event: BagScanEvent
    let isLast: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline rail (circle + connecting line)
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(hex: event.scanType.colorHex).opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: event.scanType.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: event.scanType.colorHex))
                }

                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.scanType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: event.scanType.colorHex))
                    Spacer()
                    Text(Self.timeFormatter.string(from: event.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(event.location)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let note = event.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

// MARK: - StaticStatusHeader

private struct StaticStatusHeader: View {
    let status: BagStatus

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: status.colorHex).opacity(0.85),
                    Color(hex: status.colorHex).opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
                Text(status.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - BeltAnimationView

/// Conveyor belt animation: rotating rollers + a suitcase translating
/// left-to-right on a repeating linear loop.
private struct BeltAnimationView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                // Belt translation period (seconds)
                let period: Double = 3.0
                let phase = (t.truncatingRemainder(dividingBy: period)) / period   // 0...1

                ZStack {
                    // Dark backdrop
                    LinearGradient(
                        colors: [Color(hex: "#0F1A2B"), Color(hex: "#1B2942")],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Belt deck
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "#2A3B5A"))
                        .frame(width: width - 24, height: 18)
                        .offset(y: height * 0.30)

                    // Belt surface stripes (motion lines)
                    HStack(spacing: 18) {
                        ForEach(0..<8) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 14, height: 4)
                        }
                    }
                    .offset(x: -CGFloat(phase) * 32, y: height * 0.30)
                    .mask(
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: width - 24, height: 18)
                            .offset(y: height * 0.30)
                    )

                    // Rollers
                    HStack(spacing: (width - 24 - 3 * 22) / 2) {
                        ForEach(0..<3) { _ in
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(hex: "#8FA4C4"), Color(hex: "#4A5C7E")],
                                        center: .topLeading,
                                        startRadius: 2,
                                        endRadius: 20
                                    )
                                )
                                .frame(width: 22, height: 22)
                        }
                    }
                    .frame(width: width - 24)
                    .offset(y: height * 0.30 + 18)

                    // Travelling suitcase (left -> right)
                    let travelWidth = width - 80
                    let suitcaseX = -travelWidth / 2 + travelWidth * CGFloat(phase)
                    Image(systemName: "suitcase.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .offset(x: suitcaseX, y: height * 0.30 - 22)

                    // "Live" pill
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: "#3B9EF0"))
                                    .frame(width: 8, height: 8)
                                    .opacity(0.5 + 0.5 * sin(t * 3))
                                Text("LIVE — BELT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
    }
}

// MARK: - AircraftLoadingView

/// Aircraft loading animation: angled conveyor on the left feeds suitcases
/// upward into a parked aircraft on the right.
private struct AircraftLoadingView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let period: Double = 2.4
                let phase = (t.truncatingRemainder(dividingBy: period)) / period   // 0...1

                ZStack {
                    // Dusk gradient sky
                    LinearGradient(
                        colors: [Color(hex: "#241A3E"), Color(hex: "#3D2A5C")],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Tarmac
                    Rectangle()
                        .fill(Color(hex: "#1A1230"))
                        .frame(height: height * 0.22)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    // Angled conveyor (left side, angling up to aircraft door)
                    let conveyorStart = CGPoint(x: 24, y: height * 0.82)
                    let conveyorEnd   = CGPoint(x: width * 0.55, y: height * 0.42)

                    Path { path in
                        path.move(to: CGPoint(x: conveyorStart.x, y: conveyorStart.y + 6))
                        path.addLine(to: CGPoint(x: conveyorEnd.x, y: conveyorEnd.y + 6))
                        path.addLine(to: CGPoint(x: conveyorEnd.x, y: conveyorEnd.y - 6))
                        path.addLine(to: CGPoint(x: conveyorStart.x, y: conveyorStart.y - 6))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "#7B3FBF").opacity(0.8))

                    // Conveyor support legs
                    Path { path in
                        path.move(to: CGPoint(x: conveyorStart.x + 30, y: conveyorStart.y + 6))
                        path.addLine(to: CGPoint(x: conveyorStart.x + 30, y: height * 0.92))
                        path.move(to: CGPoint(x: (conveyorStart.x + conveyorEnd.x) / 2,
                                              y: (conveyorStart.y + conveyorEnd.y) / 2 + 6))
                        path.addLine(to: CGPoint(x: (conveyorStart.x + conveyorEnd.x) / 2,
                                                 y: height * 0.92))
                    }
                    .stroke(Color(hex: "#5A2E8E"), lineWidth: 3)

                    // Aircraft body (right side)
                    let aircraftCenterX = width * 0.78
                    let aircraftCenterY = height * 0.45
                    Image(systemName: "airplane")
                        .font(.system(size: 90, weight: .regular))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))
                        .position(x: aircraftCenterX, y: aircraftCenterY)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                    // Cargo door glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "#1DB97D").opacity(0.7), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                        .position(x: conveyorEnd.x + 4, y: conveyorEnd.y)
                        .opacity(0.6 + 0.4 * sin(t * 4))

                    // Two suitcases climbing the conveyor in staggered phase
                    ForEach(0..<2) { i in
                        let localPhase = (phase + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        let x = conveyorStart.x + (conveyorEnd.x - conveyorStart.x) * CGFloat(localPhase)
                        let y = conveyorStart.y + (conveyorEnd.y - conveyorStart.y) * CGFloat(localPhase) - 12

                        Image(systemName: "suitcase.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(-30))
                            .position(x: x, y: y)
                            .opacity(localPhase > 0.97 ? 0 : 1)
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                    }

                    // "Live" pill
                    VStack {
                        HStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: "#1DB97D"))
                                    .frame(width: 8, height: 8)
                                    .opacity(0.5 + 0.5 * sin(t * 3))
                                Text("LOADING AIRCRAFT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("On Belt") {
    NavigationStack {
        BagDetailView(bag: Bag(
            nickname: "Brioni Suit Carrier",
            description: "Navy garment bag",
            airline: "American Airlines",
            flightNumber: "AA169",
            bagTagNumber: "0012345679",
            hasAirTag: true,
            status: .onBelt,
            lastLocation: "NRT — Carousel 4",
            lastChecked: Date(),
            scanHistory: [
                BagScanEvent(timestamp: Date().addingTimeInterval(-1500),
                             location: "NRT Cargo Offload — Belt A",
                             scanType: .onBelt),
                BagScanEvent(timestamp: Date().addingTimeInterval(-180),
                             location: "NRT — Carousel 4",
                             scanType: .onBelt,
                             note: "Now on carousel")
            ]
        ))
    }
}

#Preview("Loading Aircraft") {
    NavigationStack {
        BagDetailView(bag: Bag(
            nickname: "Bottega Veneta Weekender",
            description: "Tan leather weekender",
            airline: "American Airlines",
            flightNumber: "AA169",
            bagTagNumber: "0012345680",
            hasAirTag: true,
            status: .loading,
            lastLocation: "JFK Loader B12",
            lastChecked: Date(),
            scanHistory: []
        ))
    }
}
