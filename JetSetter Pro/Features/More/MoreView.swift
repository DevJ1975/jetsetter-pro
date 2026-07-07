// File: Features/More/MoreView.swift

import SwiftUI

struct MoreView: View {

    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Quick-access profile card ────────────────────────────
                    profileBanner

                    // ── AI & Intelligence ─────────────────────────────────────
                    moreSection(title: "AI FEATURES", icon: "sparkles") {
                        moreCard(
                            title: "IRIS — Travel Agent",
                            subtitle: "Your proactive AI agent (Pro)",
                            icon: "sparkles",
                            iconColorHex: "#7B3FBF",
                            destination: IRISChatView().premiumGate(feature: "IRIS — your AI travel agent")
                        )
                        moreCard(
                            title: "Trip Disruption AI",
                            subtitle: "Real-time alerts & automatic rebooking",
                            icon: "exclamationmark.triangle.fill",
                            iconColorHex: "#E84040",
                            destination: DisruptionDashboardView()
                        )
                        moreCard(
                            title: "Proactive Intelligence",
                            subtitle: "Live on Home — leave-now & check-in cards",
                            icon: "brain.head.profile",
                            iconColorHex: "#7B3FBF",
                            destination: IntelligenceHistoryView()
                        )
                    }

                    // ── Trip Tools ────────────────────────────────────────────
                    moreSection(title: "TRIP TOOLS", icon: "briefcase.fill") {
                        moreCard(
                            title: "Smart Packing List",
                            subtitle: "AI-generated based on weather & activities",
                            icon: "checklist",
                            iconColorHex: "#3B9EF0",
                            destination: PackingListRouterView()
                        )
                        moreCard(
                            title: "Document Vault",
                            subtitle: "Encrypted passport, visa & insurance storage",
                            icon: "lock.shield.fill",
                            iconColorHex: "#0055CC",
                            destination: DocumentVaultView()
                        )
                        moreCard(
                            title: "Local Experiences",
                            subtitle: "AI-ranked restaurants, events & hidden gems",
                            icon: "sparkles",
                            iconColorHex: "#E8A020",
                            destination: LocalExperienceRouterView()
                        )
                    }

                    // ── Finance ───────────────────────────────────────────────
                    moreSection(title: "FINANCE", icon: "dollarsign.circle.fill") {
                        moreCard(
                            title: "Currency & Expenses",
                            subtitle: "Live rates, spend tracking & budget chart",
                            icon: "arrow.left.arrow.right.circle.fill",
                            iconColorHex: "#1DB97D",
                            destination: CurrencyExpenseRouterView()
                        )
                    }

                    // ── Transport ────────────────────────────────────────────
                    moreSection(title: "TRANSPORT", icon: "car.fill") {
                        moreCard(
                            title: "Ground Transport",
                            subtitle: "Uber & Lyft ride estimates",
                            icon: "car.fill",
                            iconColorHex: "#4E8FD4",
                            destination: GroundTransportView()
                        )
                        moreCard(
                            title: "Rental Cars",
                            subtitle: "Enterprise, Hertz, National",
                            icon: "steeringwheel",
                            iconColorHex: "#C8860A",
                            destination: RentalCarView()
                        )
                    }

                    // ── Before You Fly ───────────────────────────────────────
                    moreSection(title: "BEFORE YOU FLY", icon: "airplane.departure") {
                        moreCard(
                            title: "Departure Optimizer",
                            subtitle: "Live traffic + TSA wait → when to leave",
                            icon: "clock.badge.checkmark.fill",
                            iconColorHex: "#3B9EF0",
                            destination: DepartureOptimizerView()
                        )
                        moreCard(
                            title: "Book Flights & Hotels",
                            subtitle: "Live availability via Expedia",
                            icon: "ticket.fill",
                            iconColorHex: "#1DB97D",
                            destination: BookingView()
                        )
                        moreCard(
                            title: "Offline Kit",
                            subtitle: "Pre-cache trip data for in-flight & abroad",
                            icon: "icloud.and.arrow.down.fill",
                            iconColorHex: "#0A7A5E",
                            destination: OfflineKitView()
                        )
                    }

                    // ── At the Airport ───────────────────────────────────────
                    moreSection(title: "AT THE AIRPORT", icon: "signpost.right.fill") {
                        moreCard(
                            title: "Departure Board",
                            subtitle: "Live split-flap display of airport departures",
                            icon: "rectangle.stack.fill",
                            iconColorHex: "#E8A020",
                            destination: FlightBoardView()
                        )
                        moreCard(
                            title: "Airport Map",
                            subtitle: "Indoor navigation & gate wayfinding",
                            icon: "map.fill",
                            iconColorHex: "#7B3FBF",
                            destination: AirportMapRouterView()
                        )
                        moreCard(
                            title: "Identity & Trusted Traveler",
                            subtitle: "Digital ID, CLEAR, PreCheck & Global Entry",
                            icon: "person.text.rectangle.fill",
                            iconColorHex: "#0066CC",
                            destination: IdentityVaultView()
                        )
                        moreCard(
                            title: "Luggage Tracker",
                            subtitle: "AirTag & WorldTracer",
                            icon: "suitcase.fill",
                            iconColorHex: "#E8A020",
                            destination: LuggageTrackerView()
                        )
                    }

                    // ── Wallet & Documents ───────────────────────────────────
                    moreSection(title: "WALLET & DOCUMENTS", icon: "wallet.pass.fill") {
                        moreCard(
                            title: "Travel Wallet",
                            subtitle: "Boarding passes, hotels, car rentals",
                            icon: "wallet.pass.fill",
                            iconColorHex: "#0066CC",
                            destination: TravelWalletView()
                        )
                        moreCard(
                            title: "Miles & Loyalty",
                            subtitle: "Airline miles, hotel points & status tiers",
                            icon: "star.circle.fill",
                            iconColorHex: "#C8860A",
                            destination: LoyaltyVaultView()
                        )
                        moreCard(
                            title: "Visa Requirements",
                            subtitle: "Entry rules for US passport holders",
                            icon: "doc.text.fill",
                            iconColorHex: "#0066CC",
                            destination: VisaLookupView()
                        )
                        moreCard(
                            title: "Submit Expenses",
                            subtitle: "Email PDF, Expensify, Ramp, Brex, Divvy",
                            icon: "paperplane.fill",
                            iconColorHex: "#3B9EF0",
                            destination: ExpenseExportView().premiumGate(feature: "Expense Submission")
                        )
                    }

                    // ── In the Air & Abroad ──────────────────────────────────
                    moreSection(title: "IN THE AIR & ABROAD", icon: "airplane") {
                        moreCard(
                            title: "In-Flight Tracker",
                            subtitle: "Live altitude, GPS position & phase detection",
                            icon: "antenna.radiowaves.left.and.right",
                            iconColorHex: "#3B9EF0",
                            destination: InFlightView()
                        )
                        moreCard(
                            title: "Translator",
                            subtitle: "On-device translation with live camera scan",
                            icon: "character.bubble.fill",
                            iconColorHex: "#7B3FBF",
                            destination: TranslatorView()
                        )
                        moreCard(
                            title: "Travel Essentials",
                            subtitle: "Emergency #s, tipping, plugs, water & phrases",
                            icon: "globe.americas.fill",
                            iconColorHex: "#1DB97D",
                            destination: TravelEssentialsView()
                        )
                        moreCard(
                            title: "Trip Journal",
                            subtitle: "Auto-built photo scrapbook from your library",
                            icon: "book.pages.fill",
                            iconColorHex: "#7B3FBF",
                            destination: TripJournalRouterView()
                        )
                        moreCard(
                            title: "Carbon Footprint",
                            subtitle: "Calculate flight emissions & offset",
                            icon: "leaf.fill",
                            iconColorHex: "#0A7A5E",
                            destination: CarbonFootprintView()
                        )
                    }

                    // ── App ──────────────────────────────────────────────────
                    moreSection(title: "APP", icon: "gearshape.fill") {
                        moreCard(
                            title: "Settings",
                            subtitle: "Preferences, account, notifications",
                            icon: "gearshape.2.fill",
                            iconColorHex: "#8B92A8",
                            destination: SettingsView()
                        )
                        moreCard(
                            title: "About JetSetter Pro",
                            subtitle: "Take the tour & meet the founder",
                            icon: "airplane.circle.fill",
                            iconColorHex: "#3B9EF0",
                            destination: AboutView()
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(JetsetterTheme.Colors.background)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Profile Banner

    private var profileBanner: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(JetsetterTheme.Colors.goldGradient)
                    .frame(width: 52, height: 52)
                Text(preferences.hasProfile ? preferences.initials : "JS")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(preferences.hasProfile ? preferences.displayName : "JetSetter Traveler")
                    .font(.headline)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                Text(preferences.homeAirport.isEmpty
                     ? "Set your home airport in Settings"
                     : "Home: \(preferences.homeAirport) · \(preferences.currency)")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                    .frame(width: 36, height: 36)
                    .background(JetsetterTheme.Colors.accent.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .jetCard()
    }

    // MARK: - Section Builder

    private func moreSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption).bold()
                Text(title)
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .padding(.leading, 4)

            VStack(spacing: 1) {
                content()
            }
            .jetCard()
        }
    }

    // MARK: - Row Card

    private func moreCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        iconColorHex: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: iconColorHex).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: iconColorHex))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption).bold()
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LocalExperience Router

struct LocalExperienceRouterView: View {
    var body: some View {
        if let trip = nextOrLatestTrip() {
            LocalExperienceView(trip: trip)
        } else {
            ContentUnavailableView(
                "No trip selected",
                systemImage: "sparkles",
                description: Text("Create a trip in the Itinerary tab to see local recommendations.")
            )
        }
    }

    private func nextOrLatestTrip() -> Trip? { MoreTripResolver.nextOrLatestTrip() }
}

// MARK: - Trip Resolution

/// Shared trip resolution for the More menu's contextual routers. Reads through
/// `TravelStore` (the single source of truth for the `jetsetter_trips` key and
/// its ISO-8601 coding) so these menus can't drift from the writers if the
/// storage key or encoding ever changes.
private enum MoreTripResolver {

    /// The next upcoming trip (still active through its final day), falling back
    /// to the most-recently-ended trip.
    static func nextOrLatestTrip(now: Date = Date()) -> Trip? {
        let trips = TravelStore.loadTrips()
        // Compare against the start of today so a trip whose `endDate` sits at
        // midnight of its return day stays "active" for that entire final day
        // rather than dropping out the moment the clock passes midnight.
        let today = Calendar.current.startOfDay(for: now)
        let upcoming = trips
            .filter { $0.endDate >= today }
            .sorted { $0.startDate < $1.startDate }
        if let next = upcoming.first { return next }
        return trips.sorted { $0.endDate > $1.endDate }.first
    }

    struct DepartureAirport {
        let iata: String
        let terminal: String
        let gate: String
    }

    /// Resolves the departure airport (with terminal/gate when the itinerary
    /// states them) for the user's next upcoming flight. Falls back to the saved
    /// home airport, then `nil` when neither is available.
    static func nextDepartureAirport(homeAirport: String, now: Date = Date()) -> DepartureAirport? {
        let allItems: [ItineraryItem] = TravelStore.loadTrips().flatMap { $0.items }
        let flights: [ItineraryItem] = allItems.filter { $0.type == .flight && $0.startDate > now }
        let nextFlight: ItineraryItem? = flights.min { $0.startDate < $1.startDate }

        if let flight = nextFlight,
           let iata = originIATA(location: flight.location, title: flight.title) {
            let gate = gate(from: flight.notes) ?? ""
            let terminal = terminal(from: flight.notes) ?? terminalFromGate(gate) ?? ""
            return DepartureAirport(iata: iata, terminal: terminal, gate: gate)
        }

        let home = homeAirport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !home.isEmpty else { return nil }
        return DepartureAirport(iata: home, terminal: "", gate: "")
    }

    // MARK: Free-text parsing

    /// Best-effort departure (origin) IATA. Itineraries are free-text, so accept
    /// the common "ORIGIN <sep> DEST" separators and take the first leg; fall back
    /// to the first standalone 3-letter uppercase token in the location.
    private static func originIATA(location: String?, title: String?) -> String? {
        if let location, !location.isEmpty {
            let separators: [String] = [" → ", "→", " -> ", "->", " to ", " – ", " — ", " - "]
            for separator in separators {
                let parts = location.components(separatedBy: separator)
                if parts.count > 1,
                   let origin = parts.first?.trimmingCharacters(in: .whitespaces),
                   !origin.isEmpty {
                    return firstIATAToken(in: origin) ?? origin
                }
            }
            if let iata = firstIATAToken(in: location) { return iata }
        }
        if let title, let iata = firstIATAToken(in: title) { return iata }
        return nil
    }

    /// The first standalone 3-letter uppercase token (a plausible IATA code).
    private static func firstIATAToken(in text: String) -> String? {
        guard let range = text.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    private static func gate(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Gate\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range])
            .replacingOccurrences(of: #"^Gate\s+"#, with: "", options: .regularExpression)
    }

    private static func terminal(from notes: String?) -> String? {
        guard let notes,
              let range = notes.range(of: #"Terminal\s+([A-Z0-9]+)"#, options: .regularExpression)
        else { return nil }
        return String(notes[range])
            .replacingOccurrences(of: #"^Terminal\s+"#, with: "", options: .regularExpression)
    }

    /// Infers a terminal from a lettered gate (e.g. "B14" → "B"); `nil` for
    /// numeric-only or empty gates.
    private static func terminalFromGate(_ gate: String) -> String? {
        guard let first = gate.first, first.isLetter else { return nil }
        return String(first)
    }
}

// MARK: - Airport Map Router

/// Opens the airport map at the departure airport of the user's next upcoming
/// flight (deriving terminal/gate from the itinerary), rather than a fixed demo
/// location. Falls back to the user's saved home airport when no flight is
/// scheduled, and finally to a generic empty-state when neither is known.
struct AirportMapRouterView: View {

    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        if let ctx = MoreTripResolver.nextDepartureAirport(homeAirport: preferences.homeAirport) {
            AirportMapView(airportIATA: ctx.iata, terminal: ctx.terminal, gate: ctx.gate)
        } else {
            ContentUnavailableView(
                "No Airport Selected",
                systemImage: "map",
                description: Text("Set your home airport in Settings, or add a flight in the Itinerary tab, to open indoor navigation.")
            )
        }
    }
}

// MARK: - Preview

#Preview {
    MoreView()
        .environment(UserPreferences.shared)
        .environmentObject(NotificationManager.shared)
        .environment(SubscriptionManager.shared)
}
