// File: Features/Booking/FlightSliceViews.swift
//
// Building blocks shared by the flight booking flow and My Bookings: the test
// banner, a slice (one direction of travel) as a summary or a full itinerary,
// fare-condition rows, and the airline badge. All text comes from
// `FlightDisplay`, so the zone rules (airport time, "+1", "—" for unknown) are
// applied in one place.
//
// Layout follows the width it is given (`ViewThatFits`), not the device, and
// every font is a text style so Dynamic Type scales it.

import SwiftUI

// MARK: - Test banner

/// Shown wherever a booking can be made or viewed while the server is on a
/// Duffel test token: the flights are fake and nothing is charged.
struct TestModeBanner: View {
    var body: some View {
        Label("Test booking — no charge", systemImage: "testtube.2")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(JetsetterTheme.Colors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JetsetterTheme.Spacing.small)
            .background(JetsetterTheme.Colors.warning.opacity(0.14))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Airline badge

/// The carrier's two-character code in a rounded square. (The server's logo
/// URLs are SVG, which `AsyncImage` can't draw, and a blank box while it loads
/// would be worse than a code.)
struct AirlineBadge: View {
    let carrier: BackendCarrier?

    var body: some View {
        Text(code)
            .font(.footnote.weight(.bold))
            .foregroundStyle(JetsetterTheme.Colors.accent)
            .frame(width: 40, height: 40)
            .background(JetsetterTheme.Colors.accent.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var code: String {
        FlightDisplay.nonEmpty(carrier?.iataCode)?.uppercased() ?? "✈︎"
    }
}

// MARK: - Slice summary

/// One direction of an offer or booking.
struct SliceSummaryView: View {
    let slice: BackendSlice
    /// Show every segment with terminals, aircraft and layovers.
    var showSegments = false

    var body: some View {
        let display = FlightDisplay.slice(slice)
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack {
                Text(display.routeLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(display.spokenRoute)
                Spacer(minLength: JetsetterTheme.Spacing.small)
                Text(display.departureDate)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: JetsetterTheme.Spacing.medium) {
                    timeBlock(display.departureTime, caption: slice.origin.iataCode)
                    middle(display)
                    timeBlock(display.arrivalTime, caption: slice.destination.iataCode, dayLabel: display.arrivalDayLabel)
                }
                VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.xsmall) {
                    timeBlock(display.departureTime, caption: slice.origin.iataCode)
                    middle(display)
                    timeBlock(display.arrivalTime, caption: slice.destination.iataCode, dayLabel: display.arrivalDayLabel)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timesAccessibilityLabel(display))

            if showSegments {
                segmentList
            }
        }
    }

    private func timeBlock(_ time: String, caption: String, dayLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(time).font(.title3.weight(.semibold))
                if let dayLabel {
                    Text(dayLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JetsetterTheme.Colors.warning)
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(JetsetterTheme.Colors.textSecondary)
        }
    }

    private func middle(_ display: SliceDisplay) -> some View {
        VStack(spacing: 2) {
            Text(display.durationText ?? "—")
                .font(.caption)
            Text(display.stopsText)
                .font(.caption2)
                .foregroundStyle(display.segments.count > 1 ? JetsetterTheme.Colors.warning : JetsetterTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timesAccessibilityLabel(_ display: SliceDisplay) -> String {
        var text = "Departs \(display.departureTime), arrives \(display.arrivalTime)"
        if let label = display.arrivalDayLabel { text += " (\(label) day)" }
        text += ". \(display.durationText ?? "Duration not provided"). \(display.stopsText)."
        return text
    }

    // MARK: Segments

    @ViewBuilder
    private var segmentList: some View {
        let segments = slice.segments
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 { layover(from: segments[index - 1], to: segment) }
                segmentRow(FlightDisplay.segment(segment, id: index))
            }
        }
        .padding(.top, JetsetterTheme.Spacing.xsmall)
    }

    private func segmentRow(_ segment: SegmentDisplay) -> some View {
        let heading = [segment.flightNumber, segment.carrierName].compactMap { $0 }.joined(separator: " · ")
        let dayMark = segment.arrivalDayLabel.map { " \($0)" } ?? ""
        let from = "\(segment.departureTime) \(segment.originCode)\(terminal(segment.originTerminal))"
        let to = "\(segment.arrivalTime)\(dayMark) \(segment.destinationCode)\(terminal(segment.destinationTerminal))"
        let detail = [segment.durationText, segment.aircraft].compactMap { $0 }.joined(separator: " · ")
        let fromName = AirportNames.spokenNameOrCode(for: segment.originCode)
        let toName = AirportNames.spokenNameOrCode(for: segment.destinationCode)
        let dayWords = segment.arrivalDayLabel.map { ", \($0) day" } ?? ""
        let spoken = "\(heading). Departs \(fromName) at \(segment.departureTime), arrives \(toName) at \(segment.arrivalTime)\(dayWords)."
        return VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.footnote.weight(.semibold))
            Text("\(from) → \(to)")
                .font(.footnote)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
        }
        .padding(.leading, JetsetterTheme.Spacing.small)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(JetsetterTheme.Colors.accent.opacity(0.4))
                .frame(width: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func terminal(_ value: String?) -> String {
        value.map { " T\($0)" } ?? ""
    }

    @ViewBuilder
    private func layover(from previous: BackendSegment, to next: BackendSegment) -> some View {
        if let minutes = FlightDisplay.layoverMinutes(from: previous, to: next), minutes >= 0 {
            let tight = minutes < FlightDisplay.tightConnectionMinutes
            let duration = BackendDuration.display("PT\(minutes)M") ?? "\(minutes)m"
            let place = previous.destination.cityName ?? previous.destination.iataCode
            let suffix = tight ? " · tight connection" : ""
            Label(
                "Layover in \(place) · \(duration)\(suffix)",
                systemImage: tight ? "exclamationmark.triangle.fill" : "clock"
            )
            .font(.caption)
            .foregroundStyle(tight ? JetsetterTheme.Colors.warning : JetsetterTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Fare conditions

/// Refund, change and baggage terms, each saying "not provided" when the
/// airline didn't say.
struct FareConditionsView: View {
    let conditions: BackendConditions?
    let baggage: [BackendBaggage]

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            row("arrow.uturn.backward.circle", FlightDisplay.refundSummary(conditions))
            row("arrow.left.arrow.right.circle", FlightDisplay.changeSummary(conditions))
            row("suitcase", FlightDisplay.baggageSummary(baggage))
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(JetsetterTheme.Colors.accent)
        }
    }
}

// MARK: - Offer card

/// One search result.
struct OfferCardView: View {
    let offer: BackendOffer

    var body: some View {
        VStack(alignment: .leading, spacing: JetsetterTheme.Spacing.small) {
            HStack(spacing: JetsetterTheme.Spacing.small) {
                AirlineBadge(carrier: offer.airline)
                VStack(alignment: .leading, spacing: 0) {
                    Text(offer.airline.name ?? "Airline not provided")
                        .font(.headline)
                    if let cabin = FlightDisplay.cabinName(offer.cabinClass) {
                        Text(cabin)
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: JetsetterTheme.Spacing.small)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(BackendMoney.display(offer.totalAmount, currency: offer.totalCurrency))
                        .font(.title3.weight(.bold))
                    Text(offer.passengers.count > 1 ? "total, \(offer.passengers.count) travelers" : "total")
                        .font(.caption2)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                }
            }

            ForEach(Array(offer.slices.enumerated()), id: \.offset) { _, slice in
                Divider()
                SliceSummaryView(slice: slice)
            }

            Divider()
            HStack(spacing: JetsetterTheme.Spacing.small) {
                Text(FlightDisplay.refundSummary(offer.conditions))
                Text("·")
                Text(FlightDisplay.baggageSummary(offer.baggage))
            }
            .font(.caption)
            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            .lineLimit(2)
        }
        .padding(JetsetterTheme.Card.padding)
        .jetCard()
        .accessibilityElement(children: .combine)
    }
}
