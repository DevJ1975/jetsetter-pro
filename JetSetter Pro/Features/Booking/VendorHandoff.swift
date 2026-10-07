// File: Features/Booking/VendorHandoff.swift
//
// Vendor hand-off: the app sends the traveler to a vendor's own site (Kayak,
// Delta, Hertz...) in the in-app browser. Two things hang off that moment.
//
// 1. CAPTURE. When the browser closes, the traveler may have just booked. A
//    small sheet asks "Did you book?" and, on yes, opens the EXISTING Add a
//    Booking flow (`AddItineraryItemView` with its paste / screenshot capture
//    through `BookingCapture`) already switched to the right booking type.
//    Nothing is rebuilt here; this only decides when to ask.
//
//    "Never nagging" is enforced by `VendorHandoffPolicy`, which has tests:
//     * once per hand-off: one open-and-close is at most one sheet;
//     * not when the browser was open for only a few seconds (a bounce);
//     * not again within 15 minutes of the last ask (comparing three hotel
//       sites is one shopping session, not three bookings);
//     * not for links that cannot be a reservation (Apple Maps, ride apps);
//     * never again once the traveler turns it off (Settings, or "Don't ask
//       again" on the sheet itself).
//
// 2. MORE VENDORS. When the backend is configured, `HandoffProvidersSection`
//    lists extra buttons ("Book on Delta", "Reserve with Hertz") from
//    `GET /handoff/*`. If the backend is unreachable the section is simply
//    absent, and the screen's own Kayak / brand button remains as the local
//    fallback, so the vendor route never depends on the server being up.

import SwiftUI

// MARK: - Kinds

nonisolated enum VendorHandoffKind: String, Sendable, Equatable {
    case flight, hotel, car

    /// The booking type the capture form opens with.
    var itemType: ItineraryItemType {
        switch self {
        case .flight: return .flight
        case .hotel:  return .hotel
        case .car:    return .transport
        }
    }

    /// "flight", "hotel", "rental car": reads in "Did you book a …?"
    var noun: String {
        switch self {
        case .flight: return "flight"
        case .hotel:  return "hotel"
        case .car:    return "rental car"
        }
    }

    var systemImage: String {
        switch self {
        case .flight: return "airplane"
        case .hotel:  return "bed.double.fill"
        case .car:    return "car.fill"
        }
    }
}

// MARK: - Policy

nonisolated enum VendorHandoffPolicy {

    /// Shortest time in the browser that counts as having tried to book.
    static let minimumDwell: TimeInterval = 10
    /// Shortest gap between two asks.
    static let cooldown: TimeInterval = 15 * 60

    static let enabledKey = "vendor_handoff_prompt_enabled"

    /// Hosts that open in the same browser but can never be a reservation.
    private static let nonBookingHosts = [
        "maps.apple.com", "uber.com", "lyft.com", "weather.com", "apple.com"
    ]

    /// On unless the traveler turned it off.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func isBookingLink(_ url: URL) -> Bool {
        guard BackendCoding.isWebURL(url), let host = url.host?.lowercased() else { return false }
        return !nonBookingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether closing the browser should offer to save a reservation.
    static func shouldPrompt(
        url: URL, openedFor dwell: TimeInterval,
        sinceLastPrompt: TimeInterval?, enabled: Bool
    ) -> Bool {
        guard enabled, isBookingLink(url), dwell >= minimumDwell else { return false }
        if let sinceLastPrompt, sinceLastPrompt < cooldown { return false }
        return true
    }

    /// "delta.com" from "https://www.delta.com/flights", or nil.
    static func displayHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

// MARK: - Hand-off queries

/// Query strings for `GET /handoff/{kind}`; nil when the form isn't filled in
/// enough to ask. Dates are device-calendar days, as picked.
nonisolated enum HandoffQuery {

    static func flights(origin: String, destination: String, depart: Date, return returnDate: Date?, adults: Int) -> [URLQueryItem]? {
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard AirportCoordinates.isKnown(from), AirportCoordinates.isKnown(to), from != to else { return nil }
        var items = [
            URLQueryItem(name: "origin", value: from),
            URLQueryItem(name: "destination", value: to),
            URLQueryItem(name: "depart", value: BackendDates.dateOnlyString(depart)),
            URLQueryItem(name: "adults", value: String(max(1, adults)))
        ]
        if let returnDate { items.append(URLQueryItem(name: "return", value: BackendDates.dateOnlyString(returnDate))) }
        return items
    }

    static func hotels(destination: String, checkIn: Date, checkOut: Date, guests: Int) -> [URLQueryItem]? {
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return nil }
        return [
            URLQueryItem(name: "destination", value: place),
            URLQueryItem(name: "check_in", value: BackendDates.dateOnlyString(checkIn)),
            URLQueryItem(name: "check_out", value: BackendDates.dateOnlyString(checkOut)),
            URLQueryItem(name: "guests", value: String(max(1, guests)))
        ]
    }

    static func cars(pickup: String, pickupDate: Date, dropoffDate: Date) -> [URLQueryItem]? {
        let place = pickup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return nil }
        return [
            URLQueryItem(name: "pickup", value: place),
            URLQueryItem(name: "pickup_date", value: BackendDates.dateOnlyString(pickupDate)),
            URLQueryItem(name: "dropoff_date", value: BackendDates.dateOnlyString(dropoffDate))
        ]
    }

    /// "Book on Delta Air Lines", "Reserve with Hertz", "Compare on Kayak".
    static func buttonTitle(for provider: BackendHandoffProvider) -> String {
        switch provider.kind {
        case "airline", "hotel": return "Book on \(provider.name)"
        case "car_rental":       return "Reserve with \(provider.name)"
        default:                 return "Compare on \(provider.name)"
        }
    }
}

// MARK: - Presenting with capture

/// Remembers the last time the "Did you book?" sheet was shown, across
/// screens, so the cooldown in `VendorHandoffPolicy` spans a whole session.
@MainActor
final class VendorHandoffCoordinator {
    static let shared = VendorHandoffCoordinator()
    private init() {}
    var lastPromptAt: Date?
}

private struct VendorHandoffPrompt: Identifiable {
    let id = UUID()
    let kind: VendorHandoffKind
    let vendor: String?
}

private struct VendorHandoffModifier: ViewModifier {
    @Binding var url: URL?
    let kind: VendorHandoffKind
    let title: String
    let destinationHint: String?

    @State private var openedURL: URL?
    @State private var openedAt: Date?
    @State private var prompt: VendorHandoffPrompt?

    func body(content: Content) -> some View {
        content
            .inAppWeb(url: $url, title: title)
            .onChange(of: url) { _, newValue in
                if let newValue {
                    // Only a page that really opens in the browser counts; an
                    // app deep link is handed to the system and cleared.
                    if InAppWebView.canPresent(newValue) {
                        openedURL = newValue
                        openedAt = Date()
                    }
                    return
                }
                guard let closed = openedURL, let started = openedAt else { return }
                openedURL = nil
                openedAt = nil

                let coordinator = VendorHandoffCoordinator.shared
                let shouldAsk = VendorHandoffPolicy.shouldPrompt(
                    url: closed,
                    openedFor: Date().timeIntervalSince(started),
                    sinceLastPrompt: coordinator.lastPromptAt.map { Date().timeIntervalSince($0) },
                    enabled: VendorHandoffPolicy.isEnabled
                )
                guard shouldAsk else { return }
                coordinator.lastPromptAt = Date()
                let vendor = VendorHandoffPolicy.displayHost(closed)
                // A sheet requested in the same update as another's dismissal
                // is dropped, so wait out the browser's dismissal first.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(AppRouter.dismissalSettleTime + 0.15))
                    prompt = VendorHandoffPrompt(kind: kind, vendor: vendor)
                }
            }
            .sheet(item: $prompt) { item in
                SaveReservationSheet(kind: item.kind, vendor: item.vendor, destinationHint: destinationHint)
            }
    }
}

extension View {
    /// `.inAppWeb`, plus a one-time "Did you book? Save your reservation" sheet
    /// when the browser closes after a visit long enough to have been a booking.
    /// `destinationHint` names the place if a holder trip has to be created.
    func vendorHandoffWeb(
        url: Binding<URL?>, kind: VendorHandoffKind,
        title: String = "", destinationHint: String? = nil
    ) -> some View {
        modifier(VendorHandoffModifier(url: url, kind: kind, title: title, destinationHint: destinationHint))
    }
}

// MARK: - Save sheet

/// "Did you book?" -> the existing Add a Booking capture, in a trip.
private struct SaveReservationSheet: View {
    let kind: VendorHandoffKind
    let vendor: String?
    let destinationHint: String?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ItineraryViewModel()
    @State private var captureTripID: UUID?
    /// Medium for the question; large once the booking form takes over.
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        content
            .presentationDetents([.medium, .large], selection: $detent)
    }

    @ViewBuilder
    private var content: some View {
        if let captureTripID {
            // The whole Add a Booking form, opened on its paste / screenshot
            // step. Everything it recovers is shown for the traveler to check
            // before anything is saved.
            AddItineraryItemView(tripID: captureTripID, viewModel: viewModel,
                                 initialType: kind.itemType, startWithCapture: true)
        } else {
            prompt
        }
    }

    private var prompt: some View {
        VStack(spacing: JetsetterTheme.Spacing.medium) {
            Image(systemName: kind.systemImage)
                .font(.largeTitle)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.top, JetsetterTheme.Spacing.large)
                .accessibilityHidden(true)

            Text("Did you book a \(kind.noun)?")
                .font(JetsetterTheme.Typography.pageTitle)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: JetsetterTheme.Spacing.small)

            Button {
                startCapture()
            } label: {
                Text("Save my reservation")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(JetsetterTheme.Colors.accentFill)
                    .clipShape(.rect(cornerRadius: 12))
            }

            Button("Not now") { dismiss() }
                .font(.subheadline)
                .padding(.vertical, JetsetterTheme.Spacing.xsmall)

            Button("Don't ask me again") {
                VendorHandoffPolicy.isEnabled = false
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.bottom, JetsetterTheme.Spacing.medium)
        .background(JetsetterTheme.Colors.background.ignoresSafeArea())
    }

    private var message: String {
        let place = vendor.map { " on \($0)" } ?? ""
        return "If you finished booking\(place), save the confirmation so it's in your itinerary and wallet. Paste the confirmation email or choose a screenshot; you check the details before anything is saved."
    }

    /// Opens the capture form in the trip that is active or next. With no trip
    /// at all, a holder trip is created now (the traveler just asked to save a
    /// reservation, so it needs somewhere to live), named only from what we
    /// actually know.
    private func startCapture() {
        detent = .large
        if let trip = TravelStore.activeOrNextTrip() {
            captureTripID = trip.id
            return
        }
        let hint = destinationHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let start = Calendar.current.startOfDay(for: Date())
        let trip = Trip(
            name: hint.isEmpty ? "My trip" : "Trip to \(hint)",
            destination: hint,
            startDate: start,
            endDate: Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        )
        viewModel.addTrip(trip)
        captureTripID = trip.id
    }
}

// MARK: - More vendors from the backend

/// Extra vendor buttons from `GET /handoff/{kind}`. Hidden until there is
/// something to show: no backend, no filled-in search, or the server is down.
struct HandoffProvidersSection: View {
    let kind: BackendHandoffKind
    /// Nil until the search form is complete enough to ask.
    let query: [URLQueryItem]?
    @Binding var webURL: URL?

    @State private var providers: [BackendHandoffProvider] = []

    var body: some View {
        Group {
            if !providers.isEmpty {
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
                    Text("More places to book")
                        .font(JetsetterTheme.Typography.label)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)

                    ForEach(providers) { provider in
                        Button {
                            webURL = provider.link
                        } label: {
                            HStack {
                                Text(HandoffQuery.buttonTitle(for: provider))
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(JetsetterTheme.Colors.accent)
                            .padding(JetsetterTheme.Spacing.small)
                            .frame(maxWidth: .infinity)
                            .background(JetsetterTheme.Colors.accent.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 10))
                        }
                        .disabled(provider.link == nil)
                    }
                }
            }
        }
        .task(id: query) { await load() }
    }

    private func load() async {
        providers = []
        guard BackendStatus.shared.isConfigured, let query else { return }
        // Debounce typing: the id changes on every keystroke in the form.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let found = try await BackendClient.shared.handoff(kind, query: query)
            guard !Task.isCancelled else { return }
            providers = found.filter { $0.link != nil }
        } catch {
            // Backend down or offline: the screen's own vendor button remains.
            providers = []
        }
    }
}
