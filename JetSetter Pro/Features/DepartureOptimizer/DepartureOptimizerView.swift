// File: Features/DepartureOptimizer/DepartureOptimizerView.swift
//
// "When should I leave for the airport?" answered with real-time traffic
// (MapKit) + TSA wait estimates + boarding buffer. One-tap "Order Uber" and
// "Order Lyft" deep links. Optional "Remind me to leave" local notification.

import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

struct DepartureOptimizerView: View {

    @State private var recommendation: DepartureRecommendation?
    @State private var lane: SecurityLane = .standard
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var currentLocation: CLLocationCoordinate2D?
    @State private var trip: Trip?
    @State private var flightItem: ItineraryItem?
    @State private var showRouteSheet = false
    @State private var rideWebURL: URL?   // in-app provider booking (§7.7)

    private let provider = LocationProvider()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let trip, let flightItem {
                    flightCard(trip: trip, item: flightItem)
                } else {
                    noFlightCard
                }

                laneSelector

                if isLoading {
                    loadingCard
                } else if let rec = recommendation {
                    leaveCard(rec: rec)
                    liveConditionsCard(rec: rec)
                    navigateButton
                    breakdownCard(rec: rec)
                    rideshareCard(rec: rec)
                    automationCard(rec: rec)
                } else if let err = errorMessage {
                    errorCard(message: err)
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Departure Optimizer")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadAll() }
        .task {
            // Keep the countdown, urgency, traffic + TSA estimate live while the
            // screen is visible. SwiftUI cancels this .task when the view leaves
            // the hierarchy, so the loop stops automatically off-screen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await refreshRecommendation(showLoading: false)
            }
        }
        .onChange(of: lane) { _, _ in
            Task { await refreshRecommendation() }
        }
        .inAppWeb(url: $rideWebURL, title: "Book a Ride")
        .sheet(isPresented: $showRouteSheet) {
            if let pickup = currentLocation,
               let dest = flightItem.flatMap({ destinationAirportCoord(for: $0) }) {
                RouteMapSheet(
                    origin: pickup,
                    destination: dest,
                    destinationName: flightItem.flatMap(originAirportIATA) ?? "Airport",
                    driveMinutes: recommendation?.driveMinutes ?? 0
                )
            }
        }
    }

    // MARK: - Live conditions (traffic · TSA · weather, §7.6)

    private func liveConditionsCard(rec: DepartureRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.caption.bold())
                Text("LIVE CONDITIONS")
                    .font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            HStack(spacing: 10) {
                conditionChip(icon: "car.fill", label: "Traffic",
                              value: "\(rec.driveMinutes) min",
                              tint: JetsetterTheme.Colors.accent)
                conditionChip(icon: rec.tsaWait.confidence == .low
                                ? "questionmark.circle.fill" : "checkmark.shield.fill",
                              label: "TSA",
                              value: rec.tsaWait.display,
                              subtitle: rec.tsaWait.confidence == .low ? "Low confidence" : nil,
                              tint: rec.tsaWait.confidence == .low
                                ? Color(hex: "#E8A020") : JetsetterTheme.Colors.accent)
                if let w = rec.weather {
                    conditionChip(icon: w.systemIcon,
                                  label: "\(w.temperatureF)°F",
                                  value: w.risk.label,
                                  subtitle: w.conditionLabel,
                                  tint: Color(hex: w.risk.colorHex))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func conditionChip(icon: String, label: String, value: String,
                               subtitle: String? = nil, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Navigate (in-app route sheet, §7.6/§7.7)

    private var navigateButton: some View {
        Button {
            showRouteSheet = true
        } label: {
            HStack {
                Image(systemName: "location.north.line.fill")
                Text("Navigate to the airport")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(JetsetterTheme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(currentLocation == nil)
    }

    // MARK: - Flight card

    private func flightCard(trip: Trip, item: ItineraryItem) -> some View {
        let parts = legs(for: item)
        let origin = parts.first ?? "—"
        let dest = parts.count > 1 ? parts[1] : "—"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "airplane.departure").font(.caption.bold())
                Text("NEXT FLIGHT")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text(item.startDate, format: .dateTime.hour().minute())
                    .font(.subheadline.bold())
            }
            Text("\(origin) → \(dest)  ·  \(item.startDate, format: .dateTime.month().day())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    // MARK: - Lane selector

    private var laneSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.caption.bold())
                Text("YOUR SECURITY LANE")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)
            Picker("Lane", selection: $lane) {
                Text("Standard").tag(SecurityLane.standard)
                Text("PreCheck").tag(SecurityLane.preCheck)
                Text("CLEAR").tag(SecurityLane.clear)
                Text("Both").tag(SecurityLane.clearPlusPreCheck)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Leave card

    private func leaveCard(rec: DepartureRecommendation) -> some View {
        let tint = Color(hex: rec.urgency.colorHex)
        return VStack(spacing: 8) {
            Text(rec.urgency.label.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Leave at")
                    .font(.title3)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                Text(rec.leaveAt, format: .dateTime.hour().minute())
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
            }
            if rec.minutesUntilLeave > 0 {
                Text("in \(rec.minutesUntilLeave) min")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            } else {
                Text("You're \(abs(rec.minutesUntilLeave)) min behind. Go now.")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Breakdown

    private func breakdownCard(rec: DepartureRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.number").font(.caption.bold())
                Text("THE MATH")
                    .font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            row(icon: "car.fill",
                title: "Drive (live traffic)",
                value: "\(rec.driveMinutes) min")
            row(icon: "figure.walk",
                title: "Curb → entrance",
                value: "\(rec.curbBufferMinutes) min")
            row(icon: rec.tsaWait.confidence == .low
                    ? "questionmark.circle.fill" : "checkmark.shield.fill",
                title: "TSA wait estimate",
                value: rec.tsaWait.display,
                subtitle: rec.tsaWait.basis)
            if rec.tsaWait.confidence == .low {
                Text("We don't have a security-wait model for this airport, so this is a rough placeholder — pad extra time and check the airport's official wait times.")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#E8A020"))
                    .padding(.leading, 28)
            }
            row(icon: "airplane.departure",
                title: "Buffer at gate",
                value: "\(rec.boardingBufferMinutes) min")
            Divider().padding(.vertical, 4)
            row(icon: "clock.fill",
                title: "Scheduled departure",
                value: rec.scheduledDeparture.formatted(.dateTime.hour().minute()))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func row(icon: String, title: String, value: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(JetsetterTheme.Colors.textPrimary)
        }
    }

    // MARK: - Rideshare

    private func rideshareCard(rec: DepartureRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "car.2.fill").font(.caption.bold())
                Text("ORDER A RIDE")
                    .font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            Text("Tap to open the rideshare app with your trip pre-filled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                rideshareButton(name: "Uber", iconHex: "#000000", url: uberURL())
                rideshareButton(name: "Lyft", iconHex: "#FF00BF", url: lyftURL())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func rideshareButton(name: String, iconHex: String, url: URL?) -> some View {
        Button {
            // Prefer the native deep link (trip pre-filled) when the provider app
            // is installed; otherwise fall back to the provider's mobile site (§7.7).
            if let url, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                rideWebURL = name == "Uber"
                    ? URL(string: "https://m.uber.com")
                    : URL(string: "https://ride.lyft.com")
            }
        } label: {
            HStack {
                Image(systemName: "car.fill")
                Text("\(name)")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(hex: iconHex))
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(url == nil)
    }

    private func uberURL() -> URL? {
        guard let pickup = currentLocation,
              let dest = flightItem.flatMap({ destinationAirportCoord(for: $0) }),
              let iata = flightItem.flatMap({ destinationAirportIATA(for: $0) }) else { return nil }
        return RideshareDeepLink.uber(pickup: pickup, dropoff: dest, dropoffNickname: "\(iata) Airport")
    }

    private func lyftURL() -> URL? {
        guard let pickup = currentLocation,
              let dest = flightItem.flatMap({ destinationAirportCoord(for: $0) }) else { return nil }
        return RideshareDeepLink.lyft(pickup: pickup, dropoff: dest)
    }

    // MARK: - Automation

    private func automationCard(rec: DepartureRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill").font(.caption.bold())
                Text("AUTOMATE")
                    .font(JetsetterTheme.Typography.label).tracking(1.5)
            }
            .foregroundStyle(JetsetterTheme.Colors.accent)

            Button {
                Task { await scheduleLeaveReminder(rec: rec) }
            } label: {
                HStack {
                    Image(systemName: "bell.fill")
                    Text("Remind me 15 minutes before I should leave")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func scheduleLeaveReminder(rec: DepartureRecommendation) async {
        let center = UNUserNotificationCenter.current()
        guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
              granted else {
            errorMessage = "Enable notifications in Settings to get a leave-time reminder."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Leave for the airport"
        content.body = "Your departure window is in 15 minutes. Open JetSetter for Uber/Lyft."
        content.sound = .default

        let triggerDate = rec.leaveAt.addingTimeInterval(-15 * 60)
        guard triggerDate > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "depart_\(rec.scheduledDeparture.timeIntervalSince1970)",
                                            content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Loading / empty states

    private var loadingCard: some View {
        HStack {
            ProgressView()
            Text("Checking live traffic + TSA estimate…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private var noFlightCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No upcoming flight")
                .font(.headline)
            Text("Add a flight to your itinerary to use the Departure Optimizer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if currentLocation == nil {
                Button {
                    Task { await retryLocation() }
                } label: {
                    Text("Enable location")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(JetsetterTheme.Colors.accent.opacity(0.12))
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .jetCard()
    }

    /// Re-request location in-session (the user may have granted permission
    /// after the initial one-shot fetch failed). Deep-link to Settings when the
    /// request still can't produce a fix (e.g. authorization denied).
    private func retryLocation() async {
        currentLocation = (try? await provider.requestLocationIfPossible())?.coordinate
        if currentLocation != nil {
            await refreshRecommendation()
        } else if let settingsURL = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(settingsURL) {
            await UIApplication.shared.open(settingsURL)
        }
    }

    // MARK: - Load logic

    private func loadAll() async {
        // Load next flight
        loadNextFlight()
        // Get current location
        currentLocation = (try? await provider.requestLocationIfPossible())?.coordinate
        // Compute recommendation
        await refreshRecommendation()
    }

    /// - Parameter showLoading: When `true` (initial load, lane change) we show
    ///   the spinner. The periodic keep-alive refresh passes `false` so the live
    ///   numbers update in place without flashing the loading card.
    private func refreshRecommendation(showLoading: Bool = true) async {
        guard let flightItem = flightItem else {
            errorMessage = "Couldn't read flight details."
            return
        }
        guard let originIATA = originAirportIATA(for: flightItem) else {
            let shown = legs(for: flightItem).first.map { "“\($0)”" } ?? "the itinerary"
            errorMessage = "We couldn't recognize your departure airport from \(shown). The optimizer needs a valid airport code (e.g. JFK)."
            return
        }
        let iata = destinationAirportIATA(for: flightItem)
        // For the departure leg, we use the user's CURRENT location → ORIGIN airport.
        guard let pickup = currentLocation else {
            errorMessage = "Location needed to estimate drive time."
            return
        }

        if showLoading { isLoading = true }
        errorMessage = nil
        recommendation = await DepartureOptimizerService.shared.recommend(
            currentLocation: pickup,
            airportIATA: originIATA,
            scheduledDeparture: flightItem.startDate,
            lane: lane
        )
        if showLoading { isLoading = false }
        _ = iata
    }

    private func loadNextFlight() {
        guard let trips = CodableDefaults.load([Trip].self, forKey: "jetsetter_trips") else { return }
        let now = Date()
        let upcoming = trips.flatMap { trip in
            trip.items
                .filter { $0.type == .flight && $0.startDate > now }
                .map { (trip: trip, item: $0) }
        }
        if let earliest = upcoming.min(by: { $0.item.startDate < $1.item.startDate }) {
            self.trip = earliest.trip
            self.flightItem = earliest.item
        }
    }

    // MARK: - Helpers

    /// Splits a flight's display location into its two legs, tolerating the
    /// several arrow/dash separators the itinerary source may use (" → ",
    /// "->", "–", "—", "-") instead of assuming a single rigid delimiter.
    private func legs(for item: ItineraryItem) -> [String] {
        let raw = item.location ?? ""
        for separator in [" → ", " -> ", " – ", " — ", " - ", "→", "->", "–", "—"] {
            if raw.contains(separator) {
                return raw
                    .components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    /// Returns the parsed origin IATA only when it resolves to a known airport,
    /// so an unparseable/full-name location surfaces a clear error instead of a
    /// bad code that silently fails coordinate lookup.
    private func originAirportIATA(for item: ItineraryItem) -> String? {
        guard let code = legs(for: item).first else { return nil }
        return AirportCoordinates.isKnown(code) ? code.uppercased() : nil
    }

    private func destinationAirportIATA(for item: ItineraryItem) -> String? {
        let parts = legs(for: item)
        guard parts.count > 1 else { return nil }
        let code = parts[1]
        return AirportCoordinates.isKnown(code) ? code.uppercased() : nil
    }

    private func destinationAirportCoord(for item: ItineraryItem) -> CLLocationCoordinate2D? {
        guard let iata = originAirportIATA(for: item) else { return nil }
        return AirportCoordinates.coordinate(for: iata)
    }
}

#Preview {
    NavigationStack { DepartureOptimizerView() }
}
