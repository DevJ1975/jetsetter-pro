// File: Features/Disruption/DisruptionDashboardView.swift
// Premium Disruption AI dashboard — shows active disruption cards, alternative
// flights with price/duration, one-tap rebook CTA, hotel notification status,
// Uber reroute button, and insurance doc quick-access.
//
// Accessibility: every text uses a text style (this screen had 17 fixed point
// sizes, the most of any trip-day screen), white-on-blue buttons use
// `accentFill` (4.87:1, where the plain dark accent gave 2.86:1), routes are
// spoken as city names, and the response strip reads "Hotel notified" rather
// than "Hotel" in a colour VoiceOver can't see.

import SwiftUI

// MARK: - DisruptionDashboardView

struct DisruptionDashboardView: View {

    @State private var vm = DisruptionViewModel()
    @State private var showingAllResolved = false
    @Environment(SubscriptionManager.self) private var subscriptions
    @ScaledMetric(relativeTo: .largeTitle) private var emptyBadgeSize: CGFloat = 88
    @ScaledMetric(relativeTo: .largeTitle) private var emptyIconSize: CGFloat = 44

    /// Resolved history is collapsed to the most recent few by default; the user
    /// can expand to see the rest (useful for later insurance / reimbursement
    /// claims) so history is never silently truncated.
    private static let resolvedCollapsedLimit = 5

    // No NavigationStack here: this screen is pushed onto More's stack, and its
    // own stack nested a second one inside it (doubled bars, broken back
    // swipe). Home's sheet wraps it with `.inSheetNavigation()`.
    var body: some View {
        ZStack {
            JetsetterTheme.Colors.background.ignoresSafeArea()

            if vm.isLoading && vm.activeDisruptions.isEmpty && vm.resolvedDisruptions.isEmpty {
                loadingView
            } else if vm.activeDisruptions.isEmpty && vm.resolvedDisruptions.isEmpty {
                emptyView
            } else {
                disruptionList
            }
        }
        .navigationTitle("Disruption Monitor")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .vendorHandoffWeb(url: $vm.externalWebURL, kind: .flight, title: "Rebooking")
        .sheet(item: $vm.mailRequest) { req in
            if MailComposeSheet.canSend {
                MailComposeSheet(recipients: req.recipients, subject: req.subject, body: req.body)
            } else {
                ContentUnavailableView("Mail not set up",
                                       systemImage: "envelope",
                                       description: Text("Add a Mail account to send the hotel notification."))
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("Dismiss") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .premiumGate(feature: "Trip Disruption AI")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await vm.manualPoll() }
            } label: {
                if vm.isPolling {
                    ProgressView().tint(JetsetterTheme.Colors.accent)
                } else {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
            .disabled(vm.isPolling)
            .accessibilityLabel("Refresh disruptions")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(JetsetterTheme.Colors.accent)
            Text("Checking your flights…")
                .font(JetsetterTheme.Typography.bodyMedium)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.success.opacity(0.12))
                    .frame(width: emptyBadgeSize, height: emptyBadgeSize)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: emptyIconSize))
                    .foregroundStyle(JetsetterTheme.Colors.success)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("All Flights On Track")
                    .font(JetsetterTheme.Typography.pageTitle)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(DisruptionMonitorService.isLiveStatusConfigured
                    ? "No disruptions detected. We check your active trips periodically in the background, and you can refresh anytime with Check Now."
                    : "Live disruption checks aren't switched on in this build yet. Your flights, check-in and leave-by times still work from your itinerary.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { Task { await vm.manualPoll() } } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Disruption List

    private var disruptionList: some View {
        let active = dedupedActiveDisruptions
        return ScrollView {
            LazyVStack(spacing: 16, pinnedViews: []) {
                if !active.isEmpty {
                    sectionHeader(
                        "\(active.count) ACTIVE DISRUPTION\(active.count == 1 ? "" : "S")",
                        icon: "exclamationmark.triangle.fill",
                        color: JetsetterTheme.Colors.danger
                    )
                    ForEach(active) { event in
                        DisruptionEventCard(event: event, vm: vm)
                    }
                }

                if !vm.resolvedDisruptions.isEmpty {
                    sectionHeader("RESOLVED", icon: "checkmark.circle.fill",
                                  color: JetsetterTheme.Colors.success)
                    let resolved = vm.resolvedDisruptions
                    let visible = showingAllResolved
                        ? Array(resolved)
                        : Array(resolved.prefix(Self.resolvedCollapsedLimit))
                    ForEach(visible) { event in
                        ResolvedDisruptionRow(event: event)
                    }
                    if resolved.count > Self.resolvedCollapsedLimit {
                        Button {
                            withAnimation { showingAllResolved.toggle() }
                        } label: {
                            Text(showingAllResolved
                                 ? "Show less"
                                 : "Show all \(resolved.count) resolved")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .tripDayReadableWidth()
        }
    }

    /// Collapses multiple active events for the *same* flight into one card,
    /// keeping the most severe (cancellation > diversion > missed connection >
    /// major delay > gate change; ties broken by most recent). Two large
    /// near-identical cards for one flight read
    /// as a bug to the user — one authoritative card per flight is clearer.
    private var dedupedActiveDisruptions: [DisruptionEvent] {
        func rank(_ t: DisruptionType) -> Int {
            switch t {
            case .cancellation:     return 5
            case .diversion:        return 4
            case .missedConnection: return 3
            case .majorDelay:       return 2
            case .gateChange:       return 1
            }
        }
        // Fold same-flight actionable data (response-action flags + the fields
        // those flags unlock) from the discarded siblings into the surviving
        // card. Otherwise the winning card can lack, say, the updated gate /
        // Uber link that only a gate-change sibling carried, even though the more
        // severe delay event is the one shown.
        func merge(winner: DisruptionEvent, other: DisruptionEvent) -> DisruptionEvent {
            var w = winner
            let a = w.responseActions, b = other.responseActions
            w.responseActions = ResponseActions(
                alternativesFound: a.alternativesFound || b.alternativesFound,
                rebookingChecked:  a.rebookingChecked  || b.rebookingChecked,
                rebookingEligible: a.rebookingEligible ?? b.rebookingEligible,
                hotelNotified:     a.hotelNotified     || b.hotelNotified,
                uberRerouteReady:  a.uberRerouteReady  || b.uberRerouteReady,
                insuranceSurfaced: a.insuranceSurfaced || b.insuranceSurfaced
            )
            w.rebookingUrl        = w.rebookingUrl        ?? other.rebookingUrl
            w.hotelContact        = w.hotelContact        ?? other.hotelContact
            w.uberDeepLink        = w.uberDeepLink        ?? other.uberDeepLink
            w.insuranceDocumentId = w.insuranceDocumentId ?? other.insuranceDocumentId
            if w.alternatives.isEmpty { w.alternatives = other.alternatives }
            return w
        }

        var byFlight: [String: DisruptionEvent] = [:]
        for event in vm.activeDisruptions {
            let f = event.originalFlight
            let key = "\(f.flightNumber)|\(f.origin)|\(f.destination)"
            if let existing = byFlight[key] {
                let isMoreSevere = rank(event.eventType) > rank(existing.eventType)
                    || (rank(event.eventType) == rank(existing.eventType)
                        && event.createdAt > existing.createdAt)
                // Keep the more-severe event as the card identity, but carry over
                // the loser's actionable data either way.
                byFlight[key] = isMoreSevere
                    ? merge(winner: event, other: existing)
                    : merge(winner: existing, other: event)
            } else {
                byFlight[key] = event
            }
        }
        return byFlight.values.sorted {
            rank($0.eventType) != rank($1.eventType)
                ? rank($0.eventType) > rank($1.eventType)
                : $0.createdAt > $1.createdAt
        }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.bold())
                .accessibilityHidden(true)
            Text(title).font(JetsetterTheme.Typography.label).tracking(1.5)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - DisruptionEventCard

struct DisruptionEventCard: View {

    let event: DisruptionEvent
    @Bindable var vm: DisruptionViewModel

    @State private var isExpanded = false
    @State private var selectedAlt: AlternativeFlight? = nil
    @State private var isShowingInsurance = false
    @State private var rebookSuccess: RebookSuccess? = nil

    private struct RebookSuccess: Identifiable {
        let id = UUID()
        let flightNumber: String
        let referenceNumber: String
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection.padding(16)

            if isExpanded {
                Divider().overlay(JetsetterTheme.Colors.separator)
                expandedSection.padding(16)
            }
        }
        .jetCard()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .overlay {
            if let success = rebookSuccess {
                SuccessAnimationView(
                    title: "Rebooked on \(success.flightNumber)",
                    subtitle: "Confirmation sent to your email",
                    referenceNumber: success.referenceNumber,
                    onDismiss: { rebookSuccess = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: rebookSuccess?.id)
    }

    /// The alternative to pre-select for the rebook CTA. For cancellations and
    /// missed-connection risks speed matters most, so prefer the earliest
    /// departure; for other disruptions prefer the cheapest fare.
    private var defaultAlternative: AlternativeFlight? {
        switch event.eventType {
        case .cancellation, .missedConnection, .diversion:
            return event.earliestAlternative
        case .majorDelay, .gateChange:
            return event.bestAlternative
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type badge + timestamp
            HStack {
                disruptionBadge
                Spacer()
                Text(event.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            // Flight row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.originalFlight.flightNumber)
                        .font(JetsetterTheme.Typography.pageTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text("\(event.originalFlight.origin)  →  \(event.originalFlight.destination)")
                        .font(.subheadline)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .accessibilityLabel(spokenRoute)
                    Text(event.originalFlight.airline)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
                Spacer()
                // Delay badge
                if let delay = event.originalFlight.delayMinutes, delay > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(delay)m")
                            .font(JetsetterTheme.Typography.pageTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                        Text("delay")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Delayed \(delay) minutes")
                }
            }

            // Response-action status strip
            responseActionsStrip

            // Expand toggle
            Button {
                withAnimation {
                    isExpanded.toggle()
                    // Pre-select a sensible alternative the first time the card
                    // opens so the rebook CTA is immediately actionable (the
                    // "one-tap rebook" the model documents). Time-critical events
                    // default to the earliest departure; otherwise the cheapest.
                    if isExpanded, selectedAlt == nil {
                        selectedAlt = defaultAlternative
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "Hide Options" : "View Options & Actions")
                        .font(.system(.subheadline, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .accessibilityHidden(true)
                }
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Las Vegas to Atlanta" for VoiceOver, instead of "L A S arrow A T L".
    private var spokenRoute: String {
        TripSpeech.spokenRoute([event.originalFlight.origin, event.originalFlight.destination])
    }

    private var disruptionBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: event.eventType.systemImage).font(.caption.bold())
                .accessibilityHidden(true)
            Text(event.eventType.displayName.uppercased())
                .font(JetsetterTheme.Typography.label)
                .tracking(0.5)
        }
        .foregroundStyle(Color(hex: event.eventType.colorHex))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(hex: event.eventType.colorHex).opacity(0.12))
        .clipShape(Capsule())
    }

    private var responseActionsStrip: some View {
        HStack(spacing: 14) {
            responseIcon("airplane.departure",  active: event.responseActions.alternativesFound,  label: "Alts",
                         spoken: "Alternative flights", spokenState: ("found", "not found"))
            responseIcon("building.2.fill",     active: event.responseActions.hotelNotified,      label: "Hotel",
                         spoken: "Hotel", spokenState: ("notified", "not notified"))
            responseIcon("car.fill",            active: event.responseActions.uberRerouteReady,   label: "Uber",
                         spoken: "Uber reroute", spokenState: ("ready", "not ready"))
            responseIcon("shield.fill",         active: event.responseActions.insuranceSurfaced,  label: "Insure",
                         spoken: "Travel insurance", spokenState: ("found", "not found"))
        }
    }

    /// The on/off state is shown only by colour, so VoiceOver gets it as words.
    private func responseIcon(
        _ icon: String,
        active: Bool,
        label: String,
        spoken: String,
        spokenState: (on: String, off: String)
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(active
                    ? JetsetterTheme.Colors.success
                    : JetsetterTheme.Colors.textSecondary.opacity(0.35))
            Text(label)
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(active
                    ? JetsetterTheme.Colors.success
                    : JetsetterTheme.Colors.textSecondary.opacity(0.35))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(active ? spokenState.on : spokenState.off)
    }

    // MARK: Expanded Section

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Alternative flights
            if !event.alternatives.isEmpty {
                alternativeFlightsSection
            } else if event.rebookingUrl != nil {
                alternativeSearchSection
            }

            // Action buttons
            actionButtonsSection

            // Resolve button
            Button { Task { await vm.resolveDisruption(event) } } label: {
                Text("Mark as Resolved")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(JetsetterTheme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Alternative Flight Search

    /// Pre-filled same-route search the traveler opens in-app. The app holds no
    /// carrier inventory, so it never lists fares or seats it can't verify.
    private var alternativeSearchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALTERNATIVE FLIGHTS")
                .font(JetsetterTheme.Typography.label)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .tracking(1.5)

            Text("Live options on \(event.originalFlight.origin) → \(event.originalFlight.destination) for the same day. Check with \(event.originalFlight.airline) first if you want your existing ticket changed instead of a new fare.")
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                vm.openRebookingURL(for: event)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                        .accessibilityHidden(true)
                    Text("Find Flights \(event.originalFlight.origin) → \(event.originalFlight.destination)")
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(JetsetterTheme.Colors.accentFill)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: JetsetterTheme.Colors.accent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Find flights, \(spokenRoute)")
        }
    }

    // MARK: Alternative Flights

    private var alternativeFlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALTERNATIVE FLIGHTS")
                .font(JetsetterTheme.Typography.label)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .tracking(1.5)

            // Fare-change eligibility note — shown when the airline won't allow a
            // change to the original ticket, so alternatives book as NEW fares.
            if event.responseActions.rebookingEligible == false {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.warning)
                        .accessibilityHidden(true)
                    Text("Your current fare can't be changed. The options below are new bookings, not changes to your existing ticket.")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JetsetterTheme.Colors.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ForEach(event.alternatives) { alt in
                AlternativeFlightCard(
                    flight: alt,
                    isSelected: selectedAlt?.id == alt.id
                ) { selectedAlt = (selectedAlt?.id == alt.id) ? nil : alt }
            }

            // Rebook CTA — only shown when user has tapped an alternative
            if let chosen = selectedAlt {
                Button {
                    vm.openRebookingURL(for: event, alternative: chosen)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                        // "Book" (new fare) when the original ticket isn't changeable,
                        // "Rebook" (change existing ticket) otherwise.
                        Text("\(event.responseActions.rebookingEligible == false ? "Book" : "Rebook") \(chosen.flightNumber) — \(chosen.priceFormatted)")
                            .font(.system(.subheadline, weight: .bold))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(JetsetterTheme.Colors.accentFill)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: JetsetterTheme.Colors.accent.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedAlt?.id)
    }

    // MARK: Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            if event.responseActions.uberRerouteReady {
                DisruptionActionButton(
                    title: "Open Uber to Updated Gate",
                    icon: "car.fill",
                    colorHex: "#1C2B3A"
                ) { vm.openUberReroute(for: event) }
            }

            if event.responseActions.hotelNotified, event.hotelContact != nil {
                DisruptionActionButton(
                    title: "Email Hotel About Late Arrival",
                    icon: "envelope.fill",
                    colorHex: "#0A7A5E"
                ) { vm.openHotelEmail(for: event) }
            }

            if event.responseActions.insuranceSurfaced {
                DisruptionActionButton(
                    title: "View Travel Insurance",
                    icon: "shield.fill",
                    colorHex: "#7B3FBF"
                ) {
                    isShowingInsurance = true
                }
            }
        }
        .sheet(isPresented: $isShowingInsurance) {
            InsurancePolicySheet()
        }
    }
}

// MARK: - InsurancePolicySheet

/// The traveler's own travel-insurance wallet item (title, date and any details
/// they saved), surfaced from a disruption card. Nothing is invented: with no
/// insurance item in the wallet the sheet says so.
private struct InsurancePolicySheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var policies: [WalletItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else if policies.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "shield.slash")
                                .font(.largeTitle)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                .accessibilityHidden(true)
                            Text("No policy in your wallet")
                                .font(.headline)
                                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                            Text("Add your travel insurance to the Travel Wallet and it will appear here when a flight is disrupted.")
                                .font(.subheadline)
                                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 24)
                    } else {
                        ForEach(policies) { policy in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(policy.title, systemImage: "shield.fill")
                                    .font(.headline)
                                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                                Text("Valid from \(policy.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                ForEach(policy.rawData.keys.sorted(), id: \.self) { key in
                                    HStack {
                                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.caption)
                                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                                        Spacer()
                                        Text(policy.rawData[key] ?? "")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .jetCard()
                        }
                    }
                }
                .padding(16)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("Travel Insurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                policies = await LocalDataService.shared.fetchWalletItems().filter { $0.itemType == .travelInsurance }
                isLoading = false
            }
        }
    }
}

// MARK: - AlternativeFlightCard

struct AlternativeFlightCard: View {

    let flight: AlternativeFlight
    let isSelected: Bool
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var carrierBadgeSize: CGFloat = 44

    // AlternativeFlight carries only IATA codes for its origin/destination
    // airports, so departure/arrival must be rendered in each airport's local
    // zone (a Date is an absolute instant — only the formatter's timeZone changes
    // the displayed wall clock). We resolve the zone from the IATA code via
    // AirportCoordinates.timeZone(for:) and append the zone abbreviation (e.g.
    // "07:20 PDT"). Unknown codes fall back to the device zone rather than crash.
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func timeString(_ date: Date, iata: String) -> String {
        let zone = AirportCoordinates.timeZone(for: iata) ?? .current
        timeFmt.timeZone = zone
        let time = timeFmt.string(from: date)
        let abbreviation = zone.abbreviation(for: date) ?? zone.identifier
        return abbreviation.isEmpty ? time : "\(time) \(abbreviation)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Carrier code badge
                Text(flight.airline)
                    .font(.system(.footnote, design: .monospaced, weight: .bold))
                    .frame(width: carrierBadgeSize, height: carrierBadgeSize)
                    .background(JetsetterTheme.Colors.surfaceElevated)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.flightNumber)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    HStack(spacing: 4) {
                        Text(Self.timeString(flight.departure, iata: flight.origin))
                        Text("→")
                        Text(Self.timeString(flight.arrival, iata: flight.destination))
                        Text("·")
                        Text(flight.durationFormatted)
                    }
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.priceFormatted)
                        .font(.system(.callout, weight: .bold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(flight.cabinClass)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? JetsetterTheme.Colors.accent.opacity(0.10)
                          : JetsetterTheme.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? JetsetterTheme.Colors.accent : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "Flight DL 402, departs 07:20 PDT, arrives 15:05 EDT, 4h 45m, $420,
    /// Economy". Times stay in each airport's own zone, as on screen.
    private var accessibilityText: String {
        [
            "Flight \(flight.flightNumber)",
            "departs \(Self.timeString(flight.departure, iata: flight.origin))",
            "arrives \(Self.timeString(flight.arrival, iata: flight.destination))",
            flight.durationFormatted,
            flight.priceFormatted,
            flight.cabinClass
        ].joined(separator: ", ")
    }
}

// MARK: - ResolvedDisruptionRow

struct ResolvedDisruptionRow: View {

    let event: DisruptionEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(JetsetterTheme.Colors.success)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.eventType.displayName)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(event.originalFlight.flightNumber + "  ·  "
                     + event.originalFlight.origin + " → " + event.originalFlight.destination)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .accessibilityLabel("\(event.originalFlight.flightNumber), "
                        + TripSpeech.spokenRoute([event.originalFlight.origin, event.originalFlight.destination]))
            }

            Spacer()

            Text(event.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(14)
        .jetCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - DisruptionActionButton

private struct DisruptionActionButton: View {

    let title: String
    let icon: String
    let colorHex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(title).font(.system(.subheadline, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.bold())
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(hex: colorHex))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DisruptionDashboardView()
            .environment(SubscriptionManager.shared)
    }
}
