// File: Features/Booking/FlightBookingFlowView.swift
//
// The in-app flight booking flow, presented as a sheet from the Flights form
// when the backend has flights enabled: results, offer detail, then (in
// `FlightTravelerFormView.swift`) traveler details and review, and finally the
// payment/status screen. All state lives in `FlightBookingModel`.
//
// The sheet owns its own NavigationStack, the pattern `inSheetNavigation` uses
// for screens that are normally pushed. A "Compare on Kayak" route is on the
// results and failure screens so the traveler always has the vendor route.
//
// Payment is Stripe's hosted page in the in-app browser (`.inAppWeb`), not
// PassKit. When the browser closes the status screen polls the booking.

import SwiftUI

// MARK: - Container

struct FlightBookingFlowView: View {

    @Bindable var model: FlightBookingModel
    /// The pre-filled Kayak search for the same trip, for the fallback route.
    let kayakURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var kayakWebURL: URL?

    var body: some View {
        NavigationStack(path: $model.path) {
            FlightResultsView(model: model, onCompare: openKayak)
                .navigationDestination(for: FlightFlowStep.self) { step in
                    switch step {
                    case .detail:     OfferDetailView(model: model, onCompare: openKayak)
                    case .travelers:  FlightTravelerFormView(model: model)
                    case .review:     FlightReviewView(model: model, onCompare: openKayak)
                    case .status:     BookingStatusView(model: model, onClose: { dismiss() })
                    case .myBookings: MyBookingsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .inAppWeb(url: $model.paymentURL, title: "Payment")
        .vendorHandoffWeb(url: $kayakWebURL, kind: .flight, title: "Flights")
        .onChange(of: model.paymentURL) { old, new in
            // The traveler closed the payment page (paid or not): start waiting
            // on the server. Stripe's webhook completes the booking either way.
            if old != nil, new == nil { model.paymentBrowserClosed() }
        }
        .alert("The price changed", isPresented: priceChangeBinding, presenting: model.priceChange) { change in
            Button("Continue at \(change.newDisplay)") { model.acceptPriceChange() }
            Button("Go back", role: .cancel) { model.declinePriceChange() }
        } message: { change in
            Text("This fare moved from \(change.oldDisplay) to \(change.newDisplay) since you searched. You'll only be charged the new price if you continue.")
        }
    }

    private var priceChangeBinding: Binding<Bool> {
        Binding(
            get: { model.priceChange != nil },
            set: { if !$0 { model.declinePriceChange() } }
        )
    }

    private func openKayak() {
        guard let kayakURL else { return }
        kayakWebURL = kayakURL
    }
}

// MARK: - Results

struct FlightResultsView: View {

    @Bindable var model: FlightBookingModel
    let onCompare: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                if model.isTestMode { TestModeBanner() }

                switch model.searchPhase {
                case .searching:
                    VStack(spacing: JetsetterTheme.Spacing.medium) {
                        ProgressView()
                        Text("Searching airlines…")
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, JetsetterTheme.Spacing.xlarge)

                case .failed(let message, let isConnectivity):
                    messageCard(
                        icon: isConnectivity ? "wifi.slash" : "exclamationmark.triangle.fill",
                        title: isConnectivity ? "You're offline" : "Search didn't work",
                        message: message
                    )
                    Button("Try again") { Task { await model.search() } }
                        .buttonStyle(.borderedProminent)
                    compareButton

                case .loaded:
                    if model.offers.isEmpty {
                        messageCard(
                            icon: "airplane.circle",
                            title: "No flights found",
                            message: "No airline returned fares for that route and date. Try nearby dates or another airport."
                        )
                        compareButton
                    } else {
                        sortPicker
                        ForEach(model.sortedOffers) { offer in
                            Button { model.select(offer) } label: { OfferCardView(offer: offer) }
                                .buttonStyle(.plain)
                        }
                        Text("Fares are live from the airlines and can change. Prices include all taxes and fees shown at payment.")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        compareButton
                    }
                }
            }
            .padding(JetsetterTheme.Spacing.medium)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.routeLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.searchIfNeeded() }
        .refreshable { await model.search() }
    }

    private var sortPicker: some View {
        Picker("Sort by", selection: $model.sort) {
            ForEach(OfferSort.allCases) { sort in
                Text(sort.label).tag(sort)
            }
        }
        .pickerStyle(.segmented)
    }

    private var compareButton: some View {
        Button(action: onCompare) {
            Label("Compare on Kayak", systemImage: "safari")
                .font(.subheadline.weight(.medium))
        }
    }

    private func messageCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(JetsetterTheme.Colors.warning)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Offer detail

struct OfferDetailView: View {

    @Bindable var model: FlightBookingModel
    let onCompare: () -> Void

    var body: some View {
        ScrollView {
            if let offer = model.selectedOffer {
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.medium) {
                    if model.isTestMode { TestModeBanner() }

                    header(offer)

                    ForEach(Array(offer.slices.enumerated()), id: \.offset) { _, slice in
                        VStack(alignment: .leading) {
                            SliceSummaryView(slice: slice, showSegments: true)
                            if let brand = FlightDisplay.nonEmpty(slice.fareBrandName) {
                                Text("Fare: \(brand)")
                                    .font(.caption)
                                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                            }
                        }
                        .padding(JetsetterTheme.Card.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jetCard()
                    }

                    VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
                        Text("Fare rules")
                            .font(.headline)
                        FareConditionsView(conditions: offer.conditions, baggage: offer.baggage)
                    }
                    .padding(JetsetterTheme.Card.padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .jetCard()

                    if offer.requiresIdentityDocuments {
                        Label("This fare needs passport details for each traveler.", systemImage: "person.text.rectangle")
                            .font(.footnote)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }

                    if let message = model.offerMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(JetsetterTheme.Colors.warning)
                    }

                    Button {
                        Task { await model.continueToTravelers() }
                    } label: {
                        HStack {
                            if model.isRefreshingOffer { ProgressView().tint(.white) }
                            Text(model.isRefreshingOffer ? "Checking the latest price…" : "Continue")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(JetsetterTheme.Colors.accentFill)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(model.isRefreshingOffer)

                    Button(action: onCompare) {
                        Label("Compare on Kayak", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(JetsetterTheme.Spacing.medium)
                .readableWidth()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your flight")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ offer: BackendOffer) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            AirlineBadge(carrier: offer.airline)
            VStack(alignment: .leading, spacing: 0) {
                Text(offer.airline.name ?? "Airline not provided")
                    .font(.headline)
                Text([FlightDisplay.cabinName(offer.cabinClass), FlightDisplay.passengerSummary(offer.passengers)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            Spacer(minLength: JetsetterTheme.Spacing.small)
            VStack(alignment: .trailing, spacing: 0) {
                Text(BackendMoney.display(offer.totalAmount, currency: offer.totalCurrency))
                    .font(.title2.weight(.bold))
                if let fee = offer.feeAmount, !BackendMoney.isZero(fee) {
                    Text("includes \(BackendMoney.display(fee, currency: offer.totalCurrency)) service fee")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}

// MARK: - Status

/// After checkout: waiting for payment, ticketing, and the final result.
struct BookingStatusView: View {

    @Bindable var model: FlightBookingModel
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: JetsetterTheme.Spacing.medium) {
                if model.isTestMode { TestModeBanner() }
                statusCard
                if let booking = model.booking {
                    BookingSummaryCard(booking: booking)
                }
                actions
            }
            .padding(JetsetterTheme.Spacing.medium)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        // Money is in flight: no swiping back into the form to pay twice.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Always a way out: the booking carries on server-side and shows up
            // in My Bookings whether or not this screen stays open.
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        .task(id: model.checkoutPhase) { await model.pollUntilSettled() }
    }

    // MARK: Status

    private var statusCard: some View {
        let content = statusContent
        return VStack(spacing: JetsetterTheme.Spacing.small) {
            if content.isWorking {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: content.icon)
                    .font(.system(.largeTitle))
                    .foregroundStyle(content.color)
                    .accessibilityHidden(true)
            }
            Text(content.title)
                .font(JetsetterTheme.Typography.pageTitle)
                .multilineTextAlignment(.center)
            Text(content.message)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if let refund = content.refundLine {
                Text(refund)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            if let reference = model.booking?.bookingReference, model.booking?.status == .confirmed {
                VStack(spacing: 2) {
                    Text("Airline booking reference")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    Text(reference)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                }
                .padding(.top, JetsetterTheme.Spacing.small)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }

    private struct StatusContent {
        var icon: String
        var color: Color
        var title: String
        var message: String
        var refundLine: String?
        var isWorking = false
    }

    private var statusContent: StatusContent {
        let danger = JetsetterTheme.Colors.danger
        let warning = JetsetterTheme.Colors.warning
        let success = JetsetterTheme.Colors.success

        switch model.checkoutPhase {
        case .unconfirmed(let message):
            return StatusContent(
                icon: "questionmark.circle.fill", color: warning,
                title: "We couldn't confirm your booking",
                message: message + " Don't pay again yet: your booking may still have been created. Check My Bookings in a minute."
            )
        case .editing, .submitting:
            return StatusContent(icon: "hourglass", color: warning, title: "Reserving your fare…",
                                 message: "This can take up to a minute.", isWorking: true)
        case .awaitingPayment:
            return StatusContent(icon: "creditcard", color: warning, title: "Waiting for payment",
                                 message: "Finish paying on the secure payment page. We'll confirm here as soon as it clears.")
        case .polling:
            let status = model.booking?.status ?? .pendingPayment
            return StatusContent(
                icon: "hourglass", color: warning,
                title: BookingStatusCopy.title(status),
                message: model.booking.map { BookingStatusCopy.explanation($0) } ?? "Checking your booking…",
                isWorking: true
            )
        case .stillProcessing:
            let waitingOnPayment = model.booking?.status == .pendingPayment
            return StatusContent(
                icon: "clock.badge.exclamationmark.fill", color: warning,
                title: waitingOnPayment ? "Payment not received yet" : "Still working on it",
                message: waitingOnPayment
                    ? "We haven't seen your payment. If you finished paying, it can take a few minutes to clear. If you didn't, reopen the payment page."
                    : "The airline is taking longer than usual. You don't need to stay here: your booking will appear in My Bookings."
            )
        case .settled:
            guard let booking = model.booking else {
                return StatusContent(icon: "questionmark.circle", color: warning, title: "Booking", message: "")
            }
            let icon: String
            let color: Color
            switch booking.status {
            case .confirmed: icon = "checkmark.seal.fill"; color = success
            case .cancelled: icon = "xmark.circle.fill";   color = warning
            default:         icon = "exclamationmark.triangle.fill"; color = danger
            }
            return StatusContent(
                icon: icon, color: color,
                title: BookingStatusCopy.title(booking.status),
                message: BookingStatusCopy.explanation(booking),
                refundLine: BookingStatusCopy.refundLine(booking)
            )
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: JetsetterTheme.Spacing.small) {
            switch model.checkoutPhase {
            case .awaitingPayment, .stillProcessing:
                if model.booking?.status == .pendingPayment, model.checkoutURL != nil {
                    primaryButton("Reopen payment page") { model.reopenPayment() }
                }
                if model.checkoutPhase == .stillProcessing {
                    secondaryButton("Check again") { model.checkAgain() }
                }
                myBookingsButton
                Button("Close", action: onClose).font(.subheadline)

            case .settled:
                if model.booking?.status == .confirmed {
                    primaryButton("View in My Bookings") { model.path.append(.myBookings) }
                    Button("Done", action: onClose).font(.subheadline)
                } else {
                    primaryButton("Done", action: onClose)
                    myBookingsButton
                }

            case .unconfirmed:
                primaryButton("Check My Bookings") { model.path.append(.myBookings) }
                Button("Close", action: onClose).font(.subheadline)

            case .polling, .submitting, .editing:
                EmptyView()
            }
        }
    }

    private var myBookingsButton: some View {
        secondaryButton("My Bookings") { model.path.append(.myBookings) }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(JetsetterTheme.Colors.accentFill)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(JetsetterTheme.Colors.accent.opacity(0.12))
                .clipShape(.rect(cornerRadius: 12))
        }
    }
}

// MARK: - Booking summary

/// A compact record of a booking: reference, route(s), travelers, total.
struct BookingSummaryCard: View {
    let booking: BackendBooking

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack {
                Text(booking.airline?.name ?? "Flight")
                    .font(.headline)
                Spacer()
                Text(BackendMoney.display(booking.totalAmount, currency: booking.totalCurrency))
                    .font(.headline)
            }
            ForEach(Array(booking.slices.enumerated()), id: \.offset) { _, slice in
                Divider()
                SliceSummaryView(slice: slice)
            }
            let names = booking.passengers.compactMap(\.displayName)
            if !names.isEmpty {
                Divider()
                Label(names.joined(separator: ", "), systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
    }
}
