// File: Features/Booking/MyBookingsView.swift
//
// "My Bookings": every flight booked through the app, retrieved from the
// backend and cached on the phone. Opening it syncs (which also upserts the
// itinerary and wallet via `BookingSync`); pull to refresh syncs again, and on
// a detail screen it re-reads that order from the airline (`refresh=true`) for
// schedule changes, tickets and baggage.
//
// Offline-first: the cached list shows immediately, with "Updated 12 min ago",
// and a failed refresh adds a note instead of blanking the screen. A booking's
// reference (PNR) is the thing a traveler needs at the airport with no signal,
// so it is always shown from the cache.
//
// Cancelling is a two-step flow the airline's own rules require: ask for a
// quote (how much comes back, possibly nothing), show it, and only then confirm.
//
// No NavigationStack here: this screen is pushed (onto More's stack, or onto the
// booking flow's); a sheet call site wraps it with `.inSheetNavigation()`.

import SwiftUI
import UIKit

// MARK: - List

struct MyBookingsView: View {

    @State private var sync = BookingSync.shared
    @State private var backend = BackendStatus.shared
    @State private var hasAttemptedSync = false

    var body: some View {
        Group {
            if !backend.isConfigured {
                ContentUnavailableView(
                    "Bookings aren't available",
                    systemImage: "ticket",
                    description: Text("This build isn't connected to the booking service. Trips you add yourself are in the Itinerary tab.")
                )
            } else {
                content
            }
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("My Bookings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await sync.loadCacheIfNeeded()
            await sync.sync(force: true)
            hasAttemptedSync = true
        }
        .refreshable { await sync.sync(force: true) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if sync.bookings.isEmpty {
            if sync.isSyncing || !hasAttemptedSync {
                ProgressView("Loading your bookings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: JetsetterTheme.Spacing.medium) {
                        statusLine
                        ContentUnavailableView(
                            "No bookings yet",
                            systemImage: "ticket",
                            description: Text("Flights you book in JetSetter Pro appear here, with your airline booking reference.")
                        )
                    }
                    .padding(JetsetterTheme.Spacing.medium)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: JetsetterTheme.Spacing.medium) {
                    statusLine
                    ForEach(sync.bookings) { booking in
                        NavigationLink {
                            BackendBookingDetailView(bookingID: booking.id)
                        } label: {
                            BookingRowCard(booking: booking)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
                .readableWidth()
            }
        }
    }

    /// "Updated 12 min. ago", plus why a refresh failed. Never a blank screen.
    @ViewBuilder
    private var statusLine: some View {
        VStack(spacing: JetsetterTheme.Spacing.xsmall) {
            if let error = sync.lastError {
                Label(error.isConnectivity ? "You're offline. Showing your saved bookings." : error.userMessage,
                      systemImage: error.isConnectivity ? "wifi.slash" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
            if let updated = sync.lastSynced {
                Text(BookingsText.updated(updated))
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Text helpers

nonisolated enum BookingsText {

    /// "Updated 12 min. ago", in the user's language.
    static func updated(_ date: Date, now: Date = Date(), locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return "Updated " + formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Status chip

struct BookingStatusChip: View {
    let status: BackendBookingStatus

    var body: some View {
        Text(BookingStatusCopy.title(status))
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, JetsetterTheme.Spacing.small)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .confirmed:                      return JetsetterTheme.Colors.success
        case .pendingPayment, .processing:    return JetsetterTheme.Colors.warning
        case .failed:                         return JetsetterTheme.Colors.danger
        case .cancelled, .expired, .unknown:  return JetsetterTheme.Colors.textSecondary
        }
    }
}

// MARK: - Row

struct BookingRowCard: View {
    let booking: BackendBooking

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(booking.airline?.name ?? "Flight")
                    .font(.headline)
                Spacer(minLength: JetsetterTheme.Spacing.small)
                BookingStatusChip(status: booking.status)
            }

            ForEach(Array(booking.slices.enumerated()), id: \.offset) { _, slice in
                let display = FlightDisplay.slice(slice)
                VStack(alignment: .leading, spacing: 0) {
                    Text(display.routeLabel)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel(display.spokenRoute)
                    Text("\(display.departureDate) · \(display.timeRange)")
                        .font(.caption)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }

            HStack {
                Label(booking.bookingReference ?? "—", systemImage: "number")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .accessibilityLabel("Booking reference \(booking.bookingReference ?? "not issued yet")")
                Spacer()
                Text(BackendMoney.display(booking.totalAmount, currency: booking.totalCurrency))
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            if booking.testMode {
                Text("Test booking")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JetsetterTheme.Colors.warning)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

struct BackendBookingDetailView: View {

    let bookingID: String

    @State private var sync = BookingSync.shared
    @State private var refreshMessage: String?
    @State private var cancel: CancelState = .idle
    @State private var webURL: URL?
    @State private var copied = false

    private enum CancelState: Equatable {
        case idle
        case quoting
        case quoted(BackendCancelQuote)
        case cancelling
        case failed(String)
        case done(String)
    }

    private var booking: BackendBooking? {
        sync.bookings.first { $0.id == bookingID }
    }

    var body: some View {
        ScrollView {
            if let booking {
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.medium) {
                    if booking.testMode { TestModeBanner() }
                    header(booking)
                    if booking.hasAirlineChanges { changesBanner }
                    if let message = refreshMessage { messageLabel(message) }
                    flights(booking)
                    travelers(booking)
                    fareRules(booking)
                    payment(booking)
                    cancellation(booking)
                    support
                }
                .padding(JetsetterTheme.Spacing.medium)
                .readableWidth()
            } else {
                ContentUnavailableView("Booking not found", systemImage: "ticket",
                                       description: Text("Go back and pull down to refresh your bookings."))
                    .padding(.top, JetsetterTheme.Spacing.xlarge)
            }
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .inAppWeb(url: $webURL)
        .refreshable { await refresh() }
        .alert("Cancel this booking?", isPresented: quoteBinding, presenting: quote) { quote in
            Button("Cancel booking", role: .destructive) { Task { await confirmCancel(quote) } }
            Button("Keep booking", role: .cancel) {}
        } message: { quote in
            Text(cancelMessage(for: quote))
        }
    }

    // MARK: Sections

    private func header(_ booking: BackendBooking) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack {
                BookingStatusChip(status: booking.status)
                Spacer()
                Text(BackendMoney.display(booking.totalAmount, currency: booking.totalCurrency))
                    .font(.headline)
            }
            Text(BookingStatusCopy.explanation(booking))
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            if let refund = BookingStatusCopy.refundLine(booking) {
                Text(refund).font(.subheadline.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Airline booking reference")
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                HStack {
                    Text(booking.bookingReference ?? "—")
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                    Spacer()
                    if let reference = booking.bookingReference {
                        Button {
                            UIPasteboard.general.string = reference
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityLabel("Copy booking reference")
                    }
                }
                Text("Use this to check in and manage your trip on the airline's site.")
                    .font(.caption2)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .padding(.top, JetsetterTheme.Spacing.xsmall)
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private var changesBanner: some View {
        Label("The airline changed your schedule. Check the times below.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(JetsetterTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JetsetterTheme.Spacing.small)
            .background(JetsetterTheme.Colors.warning.opacity(0.14))
            .clipShape(.rect(cornerRadius: 10))
    }

    private func messageLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(JetsetterTheme.Colors.warning)
    }

    private func flights(_ booking: BackendBooking) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text("Flights").font(.headline)
            ForEach(Array(booking.slices.enumerated()), id: \.offset) { index, slice in
                if index > 0 { Divider() }
                SliceSummaryView(slice: slice, showSegments: true)
            }
            if booking.slices.isEmpty {
                Text("Flight details not provided yet.")
                    .font(.subheadline)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func travelers(_ booking: BackendBooking) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text("Travelers").font(.headline)
            ForEach(Array(booking.passengers.enumerated()), id: \.offset) { index, passenger in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(passenger.displayName ?? "Traveler \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                    Text("Ticket: \(FlightDisplay.nonEmpty(passenger.ticketNumber) ?? "—")")
                        .font(.footnote)
                    Text("Seat: \(FlightDisplay.nonEmpty(passenger.seat) ?? "—")")
                        .font(.footnote)
                }
            }
            if booking.passengers.isEmpty {
                Text("—").font(.subheadline)
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func fareRules(_ booking: BackendBooking) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            Text("Baggage and fare rules").font(.headline)
            FareConditionsView(conditions: booking.conditions, baggage: booking.baggage)
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func payment(_ booking: BackendBooking) -> some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
            Text("Payment").font(.headline)
            row("Total", BackendMoney.display(booking.totalAmount, currency: booking.totalCurrency))
            if let fee = booking.feeAmount, !BackendMoney.isZero(fee) {
                row("Service fee (included)", BackendMoney.display(fee, currency: booking.totalCurrency))
            }
            if let refund = booking.refund {
                row("Refunded", BackendMoney.display(refund.amount, currency: refund.currency))
            }
            if let created = booking.createdDate {
                row("Booked", created.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(JetsetterTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jetCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(JetsetterTheme.Colors.textSecondary)
            Spacer()
            Text(value).font(.subheadline)
        }
    }

    // MARK: Cancellation

    @ViewBuilder
    private func cancellation(_ booking: BackendBooking) -> some View {
        switch cancel {
        case .done(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.success)
        case .failed(let message):
            messageLabel(message)
            if booking.status == .confirmed { cancelButton }
        case .quoting, .cancelling:
            HStack(spacing: JetsetterTheme.Spacing.small) {
                ProgressView()
                Text(cancel == .quoting ? "Asking the airline what you'd get back…" : "Cancelling…")
                    .font(.subheadline)
            }
        case .idle, .quoted:
            if booking.status == .confirmed { cancelButton }
        }
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            Task { await requestQuote() }
        } label: {
            Text("Cancel booking")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    private var quote: BackendCancelQuote? {
        if case .quoted(let quote) = cancel { return quote }
        return nil
    }

    private var quoteBinding: Binding<Bool> {
        Binding(
            get: { quote != nil },
            set: { shown in if !shown, case .quoted = cancel { cancel = .idle } }
        )
    }

    private func cancelMessage(for quote: BackendCancelQuote) -> String {
        if BackendMoney.isZero(quote.refundAmount) {
            return "This fare is non-refundable, so nothing comes back to you. Cancelling can't be undone."
        }
        let amount = BackendMoney.display(quote.refundAmount, currency: quote.refundCurrency)
        return "You'll get \(amount) back on your original payment method. Cancelling can't be undone."
    }

    private func requestQuote() async {
        guard let booking else { return }
        cancel = .quoting
        do {
            cancel = .quoted(try await BackendClient.shared.cancelQuote(bookingID: booking.id))
        } catch let error as BackendError {
            cancel = .failed(error.userMessage)
        } catch {
            cancel = .idle
        }
    }

    private func confirmCancel(_ quote: BackendCancelQuote) async {
        guard let booking else { return }
        // A quote is only good for a few minutes; ask again rather than send a
        // stale one, so the traveler confirms the amount they will really get.
        if let expires = quote.expiresDate, expires <= Date() {
            await requestQuote()
            return
        }
        cancel = .cancelling
        do {
            let updated = try await BackendClient.shared.cancelConfirm(
                bookingID: booking.id, cancellationID: quote.cancellationId)
            await sync.record(updated)
            let refund = BackendMoney.isZero(quote.refundAmount)
                ? "Your booking is cancelled."
                : "Your booking is cancelled. \(BackendMoney.display(quote.refundAmount, currency: quote.refundCurrency)) is on its way back to you."
            cancel = .done(refund)
        } catch let error as BackendError {
            cancel = .failed(error.userMessage)
        } catch {
            cancel = .idle
        }
    }

    // MARK: Refresh and support

    private func refresh() async {
        refreshMessage = nil
        do {
            try await sync.refreshBooking(id: bookingID)
        } catch let error as BackendError {
            refreshMessage = error.isConnectivity
                ? "You're offline. Showing what was saved on this phone."
                : error.userMessage
        } catch {
            // Cancelled.
        }
    }

    @ViewBuilder
    private var support: some View {
        if let url = BackendStatus.shared.supportURL {
            Button {
                webURL = url
            } label: {
                Label("Contact support", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}
