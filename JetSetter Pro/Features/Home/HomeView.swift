// File: Features/Home/HomeView.swift

import SwiftUI

struct HomeView: View {

    @State private var viewModel = HomeViewModel()
    @State private var intelligence = TravelIntelligenceViewModel()
    @State private var walletViewModel = WalletViewModel()
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLearningPrompt = false
    @State private var showFlightTracker = false
    @State private var showCheckInFlow = false
    @State private var showDisruption = false
    @State private var showExpenses = false
    @State private var showDepartureOptimizer = false
    @State private var checkInRefreshTick: Int = 0  // force re-eval after sheet dismiss

    private let accent = JetsetterTheme.Colors.accent

    var body: some View {
        ZStack {
            // ── Dark gradient background ──────────────────────────────────────
            // Appearance-aware deep-navy field (recolors to Cabin red / Heritage
            // gold). Stays dark in Light mode too — Home renders white text on a
            // permanently dark backdrop by design.
            JetsetterTheme.Colors.heroGradient
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
                    if viewModel.topIRISSuggestion == nil {
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

                    if let dep = viewModel.departureInfo {
                        departureCard(dep)
                            .cardAppear(delay: 0.28)
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
        .sheet(isPresented: $showLearningPrompt) {
            IRISLearningPromptView()
        }
        .task {
            // First-run opt-in for IRIS learning, shown once after onboarding.
            if preferences.hasCompletedOnboarding && !preferences.hasSeenLearningPrompt {
                showLearningPrompt = true
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
        .sheet(isPresented: $showDepartureOptimizer) {
            DepartureOptimizerView()
        }
        .fullScreenCover(isPresented: $showCheckInFlow, onDismiss: {
            checkInRefreshTick &+= 1
            // A completed check-in flips the check-in-window trigger off, which can
            // change whether the top IRIS suggestion is nil. Refresh the cached queue
            // here rather than re-decoding UserDefaults on every body evaluation.
            viewModel.reloadIRISSuggestions()
        }) {
            if let item = viewModel.nextFlightItem {
                CheckInFlowView(
                    flightNumber: viewModel.parsedFlightNumber,
                    route: routeString(from: item),
                    departureLabel: "\(viewModel.flightDepartureDate) · \(viewModel.flightDepartureTime)",
                    gate: fabricatedIfMissing(viewModel.parsedGate),
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
        .onChange(of: scenePhase) { _, newPhase in
            // Reopening the app should always show the *current* location and
            // up-to-date upcoming bookings — not the snapshot from the last cold
            // launch. `.task` runs only once while this view stays alive, so
            // refresh whenever the app returns to the foreground.
            guard newPhase == .active else { return }
            Task {
                await viewModel.loadAll()
                intelligence.evaluate(trips: viewModel.loadedTrips)
            }
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
                    .font(.system(.title, weight: .bold))
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

            VStack(alignment: .trailing, spacing: 8) {
                if let weather = viewModel.currentWeather {
                    weatherMiniCard(weather)
                } else if viewModel.isLoading {
                    ProgressView().tint(.white).frame(width: 70, height: 70)
                }
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
                    Text(displayValue(viewModel.parsedFlightNumber, label: "Flight"))
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
        .homeCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Departure ("time to leave") Card

    /// Surfaces DepartureOptimizerService's "leave-by" answer on Home for the
    /// next flight. Taps through to the full Departure Optimizer screen.
    private func departureCard(_ dep: HomeViewModel.HomeDepartureInfo) -> some View {
        Button {
            showDepartureOptimizer = true
        } label: {
            // Compact single-row strip rather than a full third card — keeps the
            // actionable "leave by" time and urgency prominent without adding a
            // tall card above the fold (design audit §12).
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Leave by \(dep.leaveBy)")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let urgency = dep.urgencyLabel {
                            Text(urgency)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(accent)
                        }
                    }
                    Text(dep.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .homeCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time to leave for the airport. Leave by \(dep.leaveBy). \(dep.detail).")
    }

    @ViewBuilder
    private var routeRow: some View {
        if let location = viewModel.nextFlightItem?.location {
            let parts = location.components(separatedBy: " → ")
            if parts.count == 2 {
                VStack(spacing: 10) {
                    HStack {
                        Text(parts[0])
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.title3)
                            .foregroundStyle(accent)
                        Spacer()
                        Text(parts[1])
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
        let display = displayValue(value, label: label)
        return VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(display)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label): \(display)")
    }

    /// Sanitizes a parsed field for display. The view model returns the literal
    /// placeholders "Flight" / "Airline" (and "—" for gate) when it can't parse a
    /// value from the itinerary — rendering those verbatim leaks a field label
    /// where real data belongs, which reads as broken. Collapse them to a tasteful
    /// em dash instead.
    private func displayValue(_ value: String, label: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let placeholders: Set<String> = ["Flight", "Airline", "Unknown", "N/A", ""]
        if placeholders.contains(trimmed)
            || trimmed.caseInsensitiveCompare(label) == .orderedSame {
            return "—"
        }
        return trimmed
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
        .homeCard()
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
        .homeCard()
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

    /// Returns `parsed` when it holds a real value. When it's the unparseable
    /// placeholder ("—" or empty), returns the polished demo stand-in ONLY for
    /// the seeded DEMO persona; otherwise passes "—" through so live/beta mode
    /// never fabricates a gate/seat/etc. on a real boarding pass.
    private func fabricatedIfMissing(_ parsed: String) -> String {
        let trimmed = parsed.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "—" : trimmed
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
        // Only fabricate gate/seat/confirmation for the seeded DEMO persona. In
        // live/beta mode a real flight with no parsed assignment must NOT be shown
        // a fake gate/seat — that could send a traveler to the wrong gate. Pass the
        // neutral em-dash placeholder through instead (BoardingPassCard renders it
        // cleanly and the check-in flow treats "—" as "no gate assigned").
        let gateValue = fabricatedIfMissing(viewModel.parsedGate)
        let seatValue = "—"
        let confirmationValue = "—"

        return WalletItem(
            itemType: .boardingPass,
            title: item.title,
            confirmationNumber: confirmationValue,
            date: item.startDate,
            rawData: [
                "airline": viewModel.parsedAirlineName,
                "flight_number": flightNumber,
                "iata_code": iataPrefix,
                "departure_airport": origin,
                "arrival_airport": destination,
                "seat_number": seatValue,
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

// MARK: - Home Card Chrome

/// Appearance-aware dark card background for Home. Uses fixed *dark* fills (never
/// the adaptive `surface` token or `.jetCard()`) because Home renders white text on
/// a permanently dark backdrop even when the user selects Light mode — an adaptive
/// surface would turn white and hide the text. Recolors subtly for Cabin / Heritage
/// and unifies the card radius on the design-system value.
private struct HomeCardChrome: ViewModifier {
    private var fill: Color {
        switch JetActiveAppearance.current {
        case .executive: return Color(hex: "#161929").opacity(0.92)
        case .cabin:     return Color(hex: "#170809").opacity(0.92)
        case .heritage:  return Color(hex: "#1A130C").opacity(0.92)
        }
    }

    func body(content: Content) -> some View {
        let radius = JetsetterTheme.Card.cornerRadius
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

private extension View {
    func homeCard() -> some View { modifier(HomeCardChrome()) }
}

#Preview {
    HomeView()
        .environment(UserPreferences.shared)
}
