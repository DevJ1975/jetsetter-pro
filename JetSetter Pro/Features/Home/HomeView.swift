// File: Features/Home/HomeView.swift

import SwiftUI

struct HomeView: View {

    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var intelligence = TravelIntelligenceViewModel()
    @StateObject private var walletViewModel = WalletViewModel()
    @State private var showFlightTracker = false
    @State private var showCheckInFlow = false
    @State private var showDisruption = false
    @State private var showExpenses = false
    @State private var checkInRefreshTick: Int = 0  // force re-eval after sheet dismiss

    private let accent = JetsetterTheme.Colors.accent

    var body: some View {
        ZStack {
            // ── Dark gradient background ──────────────────────────────────────
            LinearGradient(
                colors: [Color(hex: "#0A0A1E"), Color(hex: "#0D1B2A"), Color(hex: "#1A3040")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // ── Scrollable content ───────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                        .cardAppear(delay: 0.0)

                    IRISSuggestionCardView()
                        .cardAppear(delay: 0.08)

                    // Hide the Travel Intelligence card whenever IRIS already
                    // has a higher-priority suggestion to surface — otherwise
                    // both stack on top of each other and fight for attention
                    // (e.g. dual "check in" prompts inside the 12–24h window).
                    if IRISTriggers.shared.evaluate() == nil {
                        TravelIntelligenceCardView(vm: intelligence)
                            .padding(.horizontal, -20)
                            .cardAppear(delay: 0.16)
                    }

                    if viewModel.nextFlightItem != nil {
                        nextFlightCard
                            .cardAppear(delay: 0.24)
                    } else {
                        noFlightCard
                            .cardAppear(delay: 0.24)
                    }

                    if viewModel.nextFlightTrip != nil {
                        destinationCard
                            .cardAppear(delay: 0.32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showFlightTracker) {
            FlightTrackerView()
        }
        .sheet(isPresented: $showDisruption) {
            DisruptionDashboardView()
        }
        .sheet(isPresented: $showExpenses) {
            ExpenseExportView()
        }
        .fullScreenCover(isPresented: $showCheckInFlow, onDismiss: {
            checkInRefreshTick &+= 1
        }) {
            if let item = viewModel.nextFlightItem {
                CheckInFlowView(
                    flightNumber: viewModel.parsedFlightNumber,
                    route: routeString(from: item),
                    departureLabel: "\(viewModel.flightDepartureDate) · \(viewModel.flightDepartureTime)",
                    gate: viewModel.parsedGate == "—" ? "B14" : viewModel.parsedGate,
                    departure: item.startDate,
                    walletItem: boardingPassWalletItem(for: item),
                    walletViewModel: walletViewModel
                )
            } else {
                CheckInFlowView()
            }
        }
        .task {
            await viewModel.loadAll()
            intelligence.evaluate(trips: viewModel.loadedTrips)
            intelligence.startAutoRefresh { viewModel.loadedTrips }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterInvokeCheckInFlow)) { _ in
            showCheckInFlow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterOpenDisruption)) { _ in
            showDisruption = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterOpenExpenses)) { _ in
            showExpenses = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterCheckInPosted)) { _ in
            // A check-in just completed elsewhere. Reload so the next-flight
            // snapshot pushed to the watch reflects isCheckedIn = true.
            Task { await viewModel.loadAll() }
        }
        .onDisappear { intelligence.stopAutoRefresh() }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(todayDateString)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(accent)

                Text("\(viewModel.greeting)\(viewModel.displayName)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !viewModel.cityName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accent.opacity(0.8))
                        Text(viewModel.cityName)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.greeting)\(viewModel.displayName). Located in \(viewModel.cityName).")

            Spacer()

            if let weather = viewModel.currentWeather {
                weatherMiniCard(weather)
            } else if viewModel.isLoading {
                ProgressView().tint(.white).frame(width: 70, height: 70)
            }
        }
    }

    private func weatherMiniCard(_ weather: WeatherData) -> some View {
        VStack(spacing: 4) {
            Image(systemName: weather.systemIcon)
                .font(.system(size: 28))
                .symbolRenderingMode(.multicolor)
            Text("\(Int(weather.temperatureFahrenheit))°F")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
            Text(weather.conditionDescription)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        .accessibilityLabel("Current weather: \(Int(weather.temperatureFahrenheit)) degrees, \(weather.conditionDescription)")
    }

    // Static formatter — DateFormatter is expensive to allocate; reuse across renders
    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var todayDateString: String {
        Self.todayFormatter.string(from: Date()).uppercased()
    }

    // MARK: - Next Flight Card

    private var nextFlightCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("NEXT FLIGHT", systemImage: "airplane")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                Spacer()
                Text(viewModel.timeUntilFlight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.2))
                    .clipShape(Capsule())
                    .accessibilityLabel("Departs in \(viewModel.timeUntilFlight)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            divider

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.parsedFlightNumber)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(viewModel.flightDepartureDate)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                routeRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            divider

            HStack(spacing: 0) {
                flightDetailColumn("Gate",    viewModel.parsedGate)
                thinDivider
                flightDetailColumn("Airline", viewModel.parsedAirlineName)
                thinDivider
                flightDetailColumn("Departs", viewModel.flightDepartureTime)
            }
            .padding(.vertical, 14)

            divider

            if shouldShowCheckInButton {
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
                    .background(accent)
                }
                .accessibilityLabel("Check in for flight \(viewModel.parsedFlightNumber)")
            } else if isCheckedInForNextFlight {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Checked in")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(JetsetterTheme.Colors.success)
            }

            Button {
                showFlightTracker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Track This Flight")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(accent)
            }
            .accessibilityLabel("Track flight \(viewModel.parsedFlightNumber) in real time")
        }
        .id(checkInRefreshTick)
        .background(Color(white: 0.08, opacity: 0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var routeRow: some View {
        if let location = viewModel.nextFlightItem?.location {
            let parts = location.components(separatedBy: " → ")
            if parts.count == 2 {
                VStack(spacing: 10) {
                    HStack {
                        Text(parts[0])
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.title3)
                            .foregroundStyle(accent)
                        Spacer()
                        Text(parts[1])
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    FlightMapView(
                        originIATA: parts[0],
                        destinationIATA: parts[1],
                        style: .compact
                    )
                }
                .accessibilityLabel("Route: \(parts[0]) to \(parts[1])")
            } else {
                Text(location)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func flightDetailColumn(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - No Flight Card

    private var noFlightCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 40))
                .foregroundStyle(Color.white.opacity(0.35))

            Text("No Upcoming Flights")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Add a flight to your itinerary to see it here.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button {
                showFlightTracker = true
            } label: {
                Text("Search Flights")
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Open flight search")
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(white: 0.08, opacity: 0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AT DESTINATION", systemImage: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(accent)

            Text(viewModel.nextFlightTrip?.destination ?? "—")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .accessibilityLabel("Destination: \(viewModel.nextFlightTrip?.destination ?? "unknown")")

            HStack(alignment: .top, spacing: 20) {
                if !viewModel.destinationLocalTimeString.isEmpty {
                    destinationInfoItem(
                        icon: "clock.fill",
                        label: "Local Time",
                        value: viewModel.destinationLocalTimeString
                    )
                }

                if let weather = viewModel.destinationWeather {
                    destinationInfoItem(
                        icon: weather.systemIcon,
                        label: "Weather",
                        value: "\(Int(weather.temperatureFahrenheit))°F · \(weather.conditionDescription)"
                    )
                } else {
                    HStack(spacing: 6) {
                        ProgressView().tint(accent).scaleEffect(0.7)
                        Text("Loading weather…")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08, opacity: 0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func destinationInfoItem(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(accent)
                .symbolRenderingMode(.multicolor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Check-in Helpers

    /// True when the next flight is within 24h of departure and the user is not yet checked in.
    private var shouldShowCheckInButton: Bool {
        guard let item = viewModel.nextFlightItem else { return false }
        let hours = item.startDate.timeIntervalSinceNow / 3600
        guard hours > 0, hours <= 24 else { return false }
        return !CheckInStateStore.isCheckedIn(
            flightNumber: viewModel.parsedFlightNumber,
            departure: item.startDate
        )
    }

    private var isCheckedInForNextFlight: Bool {
        guard let item = viewModel.nextFlightItem else { return false }
        return CheckInStateStore.isCheckedIn(
            flightNumber: viewModel.parsedFlightNumber,
            departure: item.startDate
        )
    }

    private func routeString(from item: ItineraryItem) -> String {
        item.location ?? "JFK → NRT"
    }

    /// Returns a WalletItem suitable for rendering an embedded boarding pass
    /// on the Check-In success step. Prefers a matching boarding pass already
    /// in the wallet (matched by flight number); otherwise synthesizes one
    /// from the itinerary item's parsed fields so the pass still renders.
    private func boardingPassWalletItem(for item: ItineraryItem) -> WalletItem {
        let flightNumber = viewModel.parsedFlightNumber
        if let match = walletViewModel.boardingPasses.first(where: {
            ($0.flightNumber ?? "").uppercased() == flightNumber.uppercased()
        }) {
            return match
        }

        // Synthesize a stand-in from parsed itinerary fields. This keeps the
        // boarding-pass UI fully populated even when the user hasn't manually
        // added a pass to their wallet.
        let parts = (item.location ?? "").components(separatedBy: " → ")
        let origin = parts.first?.trimmingCharacters(in: .whitespaces) ?? "—"
        let destination = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "—"
        let iataPrefix = flightNumber.prefix(while: { $0.isLetter }).uppercased()
        let gateValue = viewModel.parsedGate == "—" ? "B14" : viewModel.parsedGate

        return WalletItem(
            itemType: .boardingPass,
            title: item.title,
            confirmationNumber: "XBZP4Q",
            date: item.startDate,
            rawData: [
                "airline": viewModel.parsedAirlineName,
                "flight_number": flightNumber,
                "iata_code": iataPrefix,
                "departure_airport": origin,
                "arrival_airport": destination,
                "seat_number": "3A",
                "gate": gateValue,
                "terminal": "—"
            ]
        )
    }

    // MARK: - Shared Dividers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 0.5)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 0.5, height: 36)
    }
}

#Preview {
    HomeView()
        .environmentObject(UserPreferences.shared)
}
