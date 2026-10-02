// File: Features/Home/HomeView.swift
//
// The trip-day screen: greeting and weather, the next flight's card (check in,
// boarding pass, live tracking), the leave-by strip and the destination card.
//
// Routed requests (Siri, notification taps, deep links, suggestion cards)
// arrive as `AppRouter.pendingAction` and are handled in `.task`, so a cold
// launch can't lose them. When the router asks every screen to close its
// modals, Home closes its own and presents the next one only after the
// dismissal settles; SwiftUI drops a presentation requested in the same update.
//
// Type sizes are text styles, or `@ScaledMetric` for the few labels smaller
// than the smallest text style, so Home follows Dynamic Type.

import SwiftUI

struct HomeView: View {

    @State private var viewModel = HomeViewModel()
    @State private var intelligence = TravelIntelligenceViewModel()
    @State private var walletViewModel = WalletViewModel()
    @Environment(UserPreferences.self) private var preferences
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFlightTracker = false
    @State private var showCheckInFlow = false
    @State private var showDisruption = false
    @State private var showDepartureOptimizer = false
    @State private var checkInRefreshTick: Int = 0  // force re-eval after sheet dismiss

    // Labels smaller than `.caption2` (11 pt) scale with Dynamic Type through these.
    @ScaledMetric(relativeTo: .caption2) private var microLabelSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption2) private var smallLabelSize: CGFloat = 10
    @ScaledMetric(relativeTo: .largeTitle) private var emptyStateIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var leaveIconFrame: CGFloat = 30

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

                    if viewModel.isShowingCachedData {
                        cachedDataStamp
                    }

                    SuggestionCardView()
                        .cardAppear(delay: 0.08)

                    // Hide the Travel Intelligence card whenever the app already
                    // has a higher-priority suggestion to surface — otherwise
                    // both stack on top of each other and fight for attention
                    // (e.g. dual "check in" prompts inside the 12–24h window).
                    if viewModel.topSuggestion == nil {
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
        .sheet(isPresented: $showFlightTracker) {
            FlightTrackerView()
        }
        .sheet(isPresented: $showDisruption) {
            DisruptionDashboardView()
        }
        .sheet(isPresented: $showDepartureOptimizer) {
            DepartureOptimizerView()
        }
        .fullScreenCover(isPresented: $showCheckInFlow, onDismiss: {
            checkInRefreshTick &+= 1
            // A completed check-in flips the check-in-window trigger off, which can
            // change whether the top the app suggestion is nil. Refresh the cached queue
            // here rather than re-decoding UserDefaults on every body evaluation.
            viewModel.reloadSuggestions()
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
                CheckInUnavailableView()
            }
        }
        .task {
            await viewModel.loadAll()
            // On screen and in the foreground: the one place ActivityKit lets
            // the app start the flight's Live Activity.
            viewModel.startLiveActivityIfDue()
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
                viewModel.startLiveActivityIfDue()
                intelligence.evaluate(trips: viewModel.loadedTrips)
            }
        }
        // Routed actions from Siri, notifications, deep links and suggestion
        // cards. Checked on first appearance (cold launch) and whenever the
        // router changes.
        .task { handlePendingAction() }
        .onChange(of: router.pendingAction) { _, _ in handlePendingAction() }
        .onChange(of: router.modalDismissalRequest) { _, _ in closeOwnModals() }
        // Posted by the Travel Intelligence card (not a notification tap).
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterInvokeCheckInFlow)) { _ in
            showCheckInFlow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .jetSetterCheckInPosted)) { _ in
            // A check-in just completed elsewhere. Reload so the next-flight
            // snapshot pushed to the watch reflects isCheckedIn = true, and start
            // the Live Activity if the flight is already inside its window.
            Task {
                await viewModel.loadAll()
                viewModel.startLiveActivityIfDue()
            }
        }
        .onDisappear { intelligence.stopAutoRefresh() }
    }

    // MARK: - Routed actions

    /// Performs whatever an intent, notification or card asked Home to do,
    /// then clears it. Actions for other screens are left for them.
    private func handlePendingAction() {
        guard let action = router.pendingAction else { return }
        switch action {
        case .checkIn:
            router.consume(action)
            // On a cold launch from Siri the next flight may not be loaded yet;
            // presenting before that shows "no upcoming flight" by mistake.
            Task {
                if viewModel.nextFlightItem == nil { await viewModel.loadAll() }
                await presentAfterDismissals { showCheckInFlow = true }
            }
        case .disruption:
            router.consume(action)
            Task { await presentAfterDismissals { showDisruption = true } }
        case .showFlight(let number):
            router.consume(action)
            Task {
                if viewModel.nextFlightItem == nil { await viewModel.loadAll() }
                // The next flight's card is right here. Any other flight is
                // listed in its trip on the Itinerary tab.
                let next = BoardingPassMatcher.canonicalFlightNumber(viewModel.parsedFlightNumber)
                if next == nil || next != BoardingPassMatcher.canonicalFlightNumber(number) {
                    router.navigate(to: .itinerary)
                }
            }
        case .notifyLovedOnes(let event):
            router.consume(action)
            let contacts = LovedOnesStore.shared.contacts(for: event)
            guard !contacts.isEmpty, LovedOnesMessenger.shared.canSend else { return }
            LovedOnesMessenger.shared.presentComposer(
                recipients: contacts.map(\.phoneNumber),
                body: LovedOnesMessenger.message(for: event, flightNumber: viewModel.parsedFlightNumber, destinationCity: viewModel.nextFlightTrip?.destination)
            )
        case .generatePackingList, .showWalletPass, .showBoardingPass:
            break   // consumed by the packing list screen and the Wallet tab
        }
    }

    /// Closes the sheets and covers Home presents itself. The router closes its
    /// own sheet; these it can't reach.
    private func closeOwnModals() {
        showFlightTracker = false
        showCheckInFlow = false
        showDisruption = false
        showDepartureOptimizer = false
    }

    /// Runs `present` once any dismissal the router just asked for has settled.
    private func presentAfterDismissals(_ present: @escaping () -> Void) async {
        try? await Task.sleep(for: router.presentationDelay())
        present()
    }

    /// Opens the wallet pass for the next flight, matched by flight number or
    /// date in the Wallet tab, or the wallet list when there's no saved pass.
    private func openBoardingPass() {
        router.navigate(to: .boardingPass(
            flightNumber: viewModel.flightNumberIfKnown,
            departure: viewModel.nextFlightItem?.startDate
        ))
    }

    // MARK: - Demo badge

    #if DEMO_ENABLED
    /// Shown whenever demo mode is on, so nobody mistakes the sample trip for a
    /// real booking. Compiled out of App Store builds along with the seeder.
    private var demoBadgeVisible: Bool { DemoMode.isOn }

    private var demoBadge: some View {
        Text("SAMPLE DATA")
            .font(.system(size: microLabelSize, weight: .black, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(JetsetterTheme.Colors.warning, in: Capsule())
            .accessibilityLabel("Sample data. Demo mode is on.")
    }
    #endif

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(todayDateString)
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(2)
                        .foregroundStyle(accent)
                    #if DEMO_ENABLED
                    // Seeded data must never be mistakable for the traveler's own.
                    if demoBadgeVisible { demoBadge }
                    #endif
                }

                Text("\(viewModel.greeting)\(viewModel.displayName)")
                    .font(.system(.title, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !viewModel.cityName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
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
                    WeatherAttributionView(source: weather.source)
                } else if viewModel.isLoading {
                    ProgressView().tint(.white).frame(width: 70, height: 70)
                }
            }
        }
    }

    private func weatherMiniCard(_ weather: WeatherData) -> some View {
        VStack(spacing: 4) {
            Image(systemName: weather.systemIcon)
                .font(.title)
                .symbolRenderingMode(.multicolor)
            Text("\(Int(weather.temperatureFahrenheit))°F")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(weather.conditionDescription)
                .font(.system(size: smallLabelSize, weight: .medium))
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

    // MARK: - Cached data stamp

    /// "Updated 12 min ago", shown while Home is displaying weather or a
    /// leave-by time it couldn't refresh (offline, roaming, captive portal).
    /// Re-renders each minute so the age stays true while the screen is open.
    private var cachedDataStamp: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .accessibilityHidden(true)
                Text(cachedDataText(now: context.date))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private func cachedDataText(now: Date) -> String {
        guard let updated = viewModel.liveDataUpdatedAt else { return "Showing saved info" }
        // Under a minute reads "Updated just now", not "in 0 sec".
        guard now.timeIntervalSince(updated) >= 60 else { return "Updated just now" }
        return "Updated \(updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
    }

    // MARK: - Next Flight Card

    private var nextFlightCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("NEXT FLIGHT", systemImage: "airplane")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                Spacer()
                Text(viewModel.timeUntilFlight)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.2))
                    .clipShape(Capsule())
                    .accessibilityLabel(viewModel.timeUntilFlightAccessibilityLabel)
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
                        .font(.caption)
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

                divider
            }

            // One tap to the pass: the matching wallet pass when there is one,
            // otherwise the wallet, where the traveler can add or scan it.
            Button(action: openBoardingPass) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .foregroundStyle(accent)
                    Text("Boarding pass")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Show boarding pass for flight \(displayValue(viewModel.parsedFlightNumber, label: "Flight"))")
            .accessibilityHint("Opens the pass in your wallet")

            // Live tracking needs the optional FlightAware key; without it the
            // button would only lead to a "not switched on" screen.
            if DisruptionMonitorService.isLiveStatusConfigured {
                divider

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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: leaveIconFrame, height: leaveIconFrame)
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
                                .font(.caption2.bold())
                                .foregroundStyle(accent)
                        }
                    }
                    Text(dep.detail)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .accessibilityHidden(true)
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
                    routeMap(origin: parts[0], destination: parts[1])
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Route: \(viewModel.routeAccessibilityLabel)")
            } else {
                Text(location)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    /// The route map. Its plane loops along the route; with Reduce Motion on it
    /// sits still at the share of the scheduled block time flown (at the
    /// origin before departure), the same fill the Live Activity's route
    /// line uses.
    @ViewBuilder
    private func routeMap(origin: String, destination: String) -> some View {
        if reduceMotion {
            let progress = FlightActivityFormatting.routeProgress(
                departure: viewModel.nextFlightItem?.startDate ?? Date(),
                arrival: viewModel.nextFlightItem?.endDate,
                now: Date()
            )
            if AirportCoordinates.isKnown(origin) && AirportCoordinates.isKnown(destination) {
                FlightMapView(originIATA: origin, destinationIATA: destination, progress: progress, style: .compact)
            } else {
                // FlightMapView's fallback for unknown airports loops on its
                // own, so draw the still version directly.
                LabeledFlightAnimation(originIATA: origin, destinationIATA: destination,
                                       progress: progress, style: .compact)
            }
        } else {
            FlightMapView(originIATA: origin, destinationIATA: destination, style: .compact)
        }
    }

    private func flightDetailColumn(_ label: String, _ value: String) -> some View {
        let display = displayValue(value, label: label)
        return VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: microLabelSize, weight: .bold))
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
                .font(.system(size: emptyStateIconSize))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)

            Text("No Upcoming Flights")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Add a flight to your itinerary to see it here.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)

            if DisruptionMonitorService.isLiveStatusConfigured {
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
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .homeCard()
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AT DESTINATION", systemImage: "mappin.and.ellipse")
                .font(.system(.caption2, design: .rounded, weight: .black))
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
                    WeatherAttributionView(source: weather.source)
                } else if viewModel.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().tint(accent).scaleEffect(0.7)
                        Text("Loading weather…")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                } else {
                    // Offline with no earlier forecast: say so rather than spin.
                    Text("Weather unavailable")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
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
                    .font(.system(size: smallLabelSize, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(value)
                    .font(.subheadline.weight(.semibold))
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
        item.location ?? "—"
    }

    /// Returns `parsed` when it holds a real value. When it's the unparseable
    /// placeholder ("—" or empty), returns the polished demo stand-in ONLY for
    /// the seeded DEMO persona; otherwise passes "—" through so live/beta mode
    /// never fabricates a gate/seat/etc. on a real boarding pass.
    private func fabricatedIfMissing(_ parsed: String) -> String {
        // Never invent a gate or seat: an unparseable value stays "—".
        let trimmed = parsed.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "—" : trimmed
    }

    /// Returns a WalletItem suitable for rendering an embedded boarding pass
    /// on the Check-In success step. Prefers a matching boarding pass already
    /// in the wallet (matched by flight number); otherwise synthesizes one
    /// from the itinerary item's parsed fields so the pass still renders.
    /// The wallet boarding pass for the next flight, if the traveler saved one.
    /// Nil means the check-in flow offers its barcode scanner instead of
    /// rendering a pass full of "—" placeholders.
    private func boardingPassWalletItem(for item: ItineraryItem) -> WalletItem? {
        BoardingPassMatcher.match(
            in: walletViewModel.boardingPasses,
            flightNumber: viewModel.flightNumberIfKnown,
            departure: item.startDate
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


// MARK: - Check-in unavailable

/// Shown if the check-in cover is opened with no upcoming flight on file.
private struct CheckInUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.departure")
                .font(.system(size: iconSize))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .accessibilityHidden(true)
            Text("No upcoming flight")
                .font(.title3.bold())
            Text("Add a flight to your itinerary and check-in will appear here 24 hours before departure.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(JetsetterTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JetsetterTheme.Colors.background)
    }
}
