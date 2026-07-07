// File: Features/FlightTracker/FlightDetailView.swift

import SwiftUI

// MARK: - FlightDetailView

/// Full detail screen for a single flight, showing gate, terminal, timing, and status.
struct FlightDetailView: View {

    let flight: Flight

    @State private var showCheckInFlow = false
    @State private var checkInRefreshTick: Int = 0
    @State private var walletViewModel = WalletViewModel()

    /// Drives the live moving plane + flown-path trail on the hero map.
    @State private var liveVM = FlightTrackerViewModel()
    @State private var originWeather: WeatherData?
    @State private var destinationWeather: WeatherData?

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Formats an AeroAPI UTC `Date` in the given airport's local time zone,
    /// appending the zone abbreviation (e.g. "3:42 PM EDT") so the user knows
    /// which local time they're reading. Falls back to the device zone when the
    /// airport's IANA zone is unknown.
    private func localTimeString(_ date: Date, in timeZone: TimeZone?) -> String {
        let zone = timeZone ?? .current
        timeFormatter.timeZone = zone
        let time = timeFormatter.string(from: date)
        let abbreviation = zone.abbreviation(for: date) ?? zone.identifier
        return "\(time) \(abbreviation)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                headerCard
                mapCard
                routeCard
                timingCard
                gateCard

                // Show baggage claim only if available
                if let baggageClaim = flight.baggageClaim {
                    baggageCard(claim: baggageClaim)
                }

                if flight.isAirborne {
                    inFlightModeLink
                }

                if shouldShowCheckInButton {
                    checkInButton
                } else if isCheckedIn {
                    checkedInBadge
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
            .id(checkInRefreshTick)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(flight.identIata ?? flight.ident)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadWeather()
            if flight.isAirborne { liveVM.startLivePolling(for: flight) }
        }
        .onDisappear { liveVM.stopLivePolling() }
        .fullScreenCover(isPresented: $showCheckInFlow, onDismiss: {
            checkInRefreshTick &+= 1
        }) {
            CheckInFlowView(
                flightNumber: flight.identIata ?? flight.ident,
                route: "\(flight.origin.codeIata ?? "—") → \(flight.destination.codeIata ?? "—")",
                departureLabel: localTimeString(flight.bestDepartureTime ?? Date(), in: flight.origin.timeZone),
                gate: flight.gateOrigin ?? "B14",
                departure: flight.bestDepartureTime ?? Date(),
                walletItem: matchingBoardingPass,
                walletViewModel: walletViewModel
            )
        }
    }

    /// Looks for a wallet boarding pass whose flight number matches this
    /// flight. When none is found, returns nil so Step 3 falls back to the
    /// simple e-ticket badge.
    private var matchingBoardingPass: WalletItem? {
        let id = (flight.identIata ?? flight.ident).uppercased()
        return walletViewModel.boardingPasses.first {
            ($0.flightNumber ?? "").uppercased() == id
        }
    }

    // MARK: - Check-in

    /// True when scheduled departure is within 24h and user hasn't checked in.
    private var shouldShowCheckInButton: Bool {
        guard let dep = flight.bestDepartureTime else { return false }
        let hours = dep.timeIntervalSinceNow / 3600
        guard hours > 0, hours <= 24 else { return false }
        return !CheckInStateStore.isCheckedIn(
            flightNumber: flight.identIata ?? flight.ident,
            departure: dep
        )
    }

    private var isCheckedIn: Bool {
        guard let dep = flight.bestDepartureTime else { return false }
        return CheckInStateStore.isCheckedIn(
            flightNumber: flight.identIata ?? flight.ident,
            departure: dep
        )
    }

    private var checkInButton: some View {
        Button {
            showCheckInFlow = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                Text("Check in now")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(JetsetterTheme.Colors.accent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Check in for flight \(flight.identIata ?? flight.ident)")
    }

    private var checkedInBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("Checked in")
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(JetsetterTheme.Colors.success)
        .background(JetsetterTheme.Colors.success.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - In-Flight Mode Link

    /// Shown while the flight is airborne — opens the live in-flight tracker
    /// (phase animation, on-device telemetry, destination local time).
    private var inFlightModeLink: some View {
        NavigationLink {
            InFlightView(
                originIATA: flight.origin.codeIata,
                destinationIATA: flight.destination.codeIata,
                destinationTimeZoneID: flight.destination.timezone,
                flightNumber: flight.identIata ?? flight.ident,
                destinationCity: flight.destination.city
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "airplane.circle.fill")
                Text("Enter in-flight mode")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, JetsetterTheme.Spacing.medium)
            .foregroundStyle(.white)
            .background(JetsetterTheme.Colors.accent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Enter in-flight mode for \(flight.identIata ?? flight.ident)")
    }

    // MARK: - Map Card

    /// Hero map showing the live great-circle route. When the flight is airborne
    /// and a live position has arrived, the plane is anchored to the real
    /// coordinate and a solid trail traces the flown path; otherwise progress is
    /// driven by `flight.progressPercent` (or loops decoratively).
    private var mapCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            FlightMapView(
                originIATA: flight.origin.codeIata ?? "",
                destinationIATA: flight.destination.codeIata ?? "",
                progress: flight.isAirborne
                    ? flight.progressPercent.map { Double($0) / 100.0 }
                    : nil,
                liveCoordinate: liveVM.livePosition?.coordinate,
                flownPath: liveVM.track.map(\.coordinate),
                style: .hero
            )
            weatherStrip
        }
    }

    /// Origin / destination current-conditions chips shown beneath the map.
    private var weatherStrip: some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            weatherChip(code: flight.origin.codeIata, weather: originWeather)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            weatherChip(code: flight.destination.codeIata, weather: destinationWeather)
        }
    }

    @ViewBuilder
    private func weatherChip(code: String?, weather: WeatherData?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: weather?.systemIcon ?? "cloud.fill")
                .foregroundStyle(JetsetterTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(code ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let weather {
                    Text("\(Int(weather.temperatureFahrenheit))° · \(weather.conditionDescription)")
                        .font(.caption)
                        .fontWeight(.medium)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, JetsetterTheme.Spacing.small)
        .padding(.vertical, 6)
        .background(JetsetterTheme.Colors.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadWeather() async {
        if let iata = flight.origin.codeIata,
           let coord = AirportCoordinates.coordinate(for: iata) {
            originWeather = try? await WeatherService.shared.fetch(
                latitude: coord.latitude, longitude: coord.longitude
            )
        }
        if let iata = flight.destination.codeIata,
           let coord = AirportCoordinates.coordinate(for: iata) {
            destinationWeather = try? await WeatherService.shared.fetch(
                latitude: coord.latitude, longitude: coord.longitude
            )
        }
    }

    // MARK: - Header Card (Airline + Status)

    private var headerCard: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            Text(flight.operatorName ?? "Unknown Airline")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(flight.identIata ?? flight.ident)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Status pill
            Text(flight.status)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, JetsetterTheme.Spacing.small)
                .background(flight.status.flightStatusColor.opacity(0.15))
                .foregroundStyle(flight.status.flightStatusColor)
                .cornerRadius(20)

            // Progress bar (shown when flight is airborne)
            if flight.isAirborne, let progress = flight.progressPercent {
                flightProgressBar(percent: progress)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Route Card (ORD → JFK)

    private var routeCard: some View {
        HStack(alignment: .top) {
            airportColumn(
                code: flight.origin.codeIata ?? "—",
                city: flight.origin.displayName,
                alignment: .leading
            )

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                if let aircraftType = flight.aircraftType {
                    Text(aircraftType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            airportColumn(
                code: flight.destination.codeIata ?? "—",
                city: flight.destination.displayName,
                alignment: .trailing
            )
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Timing Card

    private var timingCard: some View {
        VStack(spacing: 0) {
            timingRow(
                label: "Departs",
                scheduled: flight.scheduledOut,
                estimated: flight.estimatedOut,
                actual: flight.actualOut,
                delayMinutes: flight.departureDelayMinutes,
                timeZone: flight.origin.timeZone
            )

            Divider().padding(.horizontal, JetsetterTheme.Spacing.medium)

            timingRow(
                label: "Arrives",
                scheduled: flight.scheduledIn,
                estimated: flight.estimatedIn,
                actual: flight.actualIn,
                delayMinutes: flight.arrivalDelayMinutes,
                timeZone: flight.destination.timeZone
            )
        }
        .jetCard()
    }

    // MARK: - Gate Card

    private var gateCard: some View {
        HStack {
            gateColumn(
                label: "Departure Gate",
                gate: flight.gateOrigin,
                terminal: flight.terminalOrigin
            )

            Divider()
                .frame(height: 60)

            gateColumn(
                label: "Arrival Gate",
                gate: flight.gateDestination,
                terminal: flight.terminalDestination
            )
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Baggage Card

    private func baggageCard(claim: String) -> some View {
        HStack {
            Image(systemName: "suitcase.fill")
                .font(.title2)
                .foregroundStyle(JetsetterTheme.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Baggage Claim")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Carousel \(claim)")
                    .font(.headline)
            }

            Spacer()
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    // MARK: - Subviews

    private func airportColumn(code: String, city: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(code)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(city)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timingRow(
        label: String,
        scheduled: Date?,
        estimated: Date?,
        actual: Date?,
        delayMinutes: Int?,
        timeZone: TimeZone?
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Show actual or estimated time as the primary time
                if let displayTime = actual ?? estimated ?? scheduled {
                    Text(localTimeString(displayTime, in: timeZone))
                        .font(.headline)
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // Show scheduled time struck through if there is a delay
                if let scheduled = scheduled, let delay = delayMinutes, delay > 0 {
                    HStack(spacing: 4) {
                        Text(localTimeString(scheduled, in: timeZone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .strikethrough()

                        Text("+\(delay)m")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                    }
                }
            }
        }
        .padding(JetsetterTheme.Card.padding)
    }

    private func gateColumn(label: String, gate: String?, terminal: String?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(gate ?? "TBD")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let terminal = terminal {
                Text("Terminal \(terminal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func flightProgressBar(percent: Int) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(JetsetterTheme.Colors.accent)
                        .frame(width: geometry.size.width * CGFloat(percent) / 100, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(percent)% complete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, JetsetterTheme.Spacing.small)
    }
}

// MARK: - Preview

#Preview("On-Time Flight") {
    NavigationStack {
        FlightDetailView(flight: .sample)
    }
}

#Preview("Delayed Flight") {
    NavigationStack {
        FlightDetailView(flight: .sampleDelayed)
    }
}
