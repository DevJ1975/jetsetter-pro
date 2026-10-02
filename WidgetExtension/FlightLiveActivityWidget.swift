// File: FlightLiveActivityWidget.swift
//
// Live Activity UI for an active flight: Lock Screen and StandBy (a boarding-
// pass card), the Dynamic Island, and the small family that Apple Watch's
// Smart Stack and CarPlay use. Uses the SHARED `FlightActivityAttributes`
// (Shared/), which both targets compile. The text rules (zones, "+1" days,
// the 45-minute gate swap, "—" for unknowns) live in the shared
// `FlightActivityFormatting` so the app's tests cover them.
//
// What each surface shows:
//   • Compact: a plane and the flight number; a live countdown to departure
//     that becomes "Gate C22" in the last 45 minutes once the gate is known.
//     On iOS 27, when the island is width-limited (landscape), just the plane
//     and the countdown.
//   • Minimal: a ring filling over the four hours before departure.
//   • Expanded: origin and local departure time, destination and local
//     arrival time (with "+1"), flight number and status pill, a route line,
//     gate / terminal / seat, and a "Boarding pass" button.
//
// Rules that came from real complaints: a status is colour *and* symbol,
// never colour alone; "Scheduled" means no live status yet, not "on time";
// an unknown gate or seat is "—", never a guess; times are the airports'
// wall-clock times, never the phone's.
//
// Live Activity text re-renders only when the activity updates (or a timer
// `Text` ticks), so the gate swap appears at the first render inside the
// 45-minute window: a status or gate update, or the app coming forward.

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct FlightLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            FlightActivityContentView(context: context)
                .activityBackgroundTint(FlightPalette.cardBackground)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.flightLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedEndpoint(context: context, end: .departure)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedEndpoint(context: context, end: .arrival)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(context: context)
                }
            } compactLeading: {
                CompactLeading(context: context)
            } compactTrailing: {
                CompactTrailing(context: context)
            } minimal: {
                MinimalRing(context: context)
            }
            .widgetURL(context.flightLink)
            .keylineTint(FlightPalette.accent)
        }
        // A custom layout for Apple Watch's Smart Stack and CarPlay. Buttons
        // don't act in CarPlay, so that layout has none.
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Palette

private enum FlightPalette {
    /// App accent (#3B9EF0), matching JetsetterTheme.Colors.accent.
    static let accent = Color(red: 59 / 255, green: 158 / 255, blue: 240 / 255)
    /// Deep navy, like Home's cards; the Lock Screen card sits on it.
    static let cardBackground = Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.92)
}

// MARK: - Status presentation

private extension FlightActivityState.FlightStatus {
    /// Sentence-case text for the pill.
    var pillLabel: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .onTime:    return "On time"
        case .boarding:  return "Boarding"
        case .finalCall: return "Final call"
        case .delayed:   return "Delayed"
        case .departed:  return "Departed"
        case .cancelled: return "Cancelled"
        case .diverted:  return "Diverted"
        }
    }

    /// Every status carries a symbol so colour is never the only signal.
    var symbolName: String {
        switch self {
        case .scheduled: return "clock"
        case .onTime:    return "checkmark.circle.fill"
        case .boarding:  return "figure.walk"
        case .finalCall: return "exclamationmark.circle.fill"
        case .delayed:   return "clock.badge.exclamationmark.fill"
        case .departed:  return "airplane.departure"
        case .cancelled: return "xmark.circle.fill"
        case .diverted:  return "arrow.triangle.branch"
        }
    }

    /// Green means the airline says it's fine, so the neutral `.scheduled`
    /// (no live data yet) is a muted white, never green.
    var tint: Color {
        switch self {
        case .scheduled:            return Color.white.opacity(0.75)
        case .onTime:               return .green
        case .boarding, .departed:  return FlightPalette.accent
        case .finalCall, .delayed:  return .orange
        case .cancelled, .diverted: return .red
        }
    }

    /// The flight won't leave as planned; a countdown to it would mislead.
    var endsCountdown: Bool { self == .cancelled || self == .diverted }
}

// MARK: - Context helpers

private extension ActivityViewContext where Attributes == FlightActivityAttributes {
    var flightLink: URL? { JetSetterDeepLink.flight(attributes.flightNumber).url }

    var originZone: TimeZone { FlightActivityFormatting.timeZone(identifier: attributes.originTimeZoneID) }
    var destinationZone: TimeZone { FlightActivityFormatting.timeZone(identifier: attributes.destinationTimeZoneID) }

    var departureTime: String { FlightActivityFormatting.time(state.estimatedDeparture, in: originZone) }

    var arrivalTime: String {
        guard let arrival = state.estimatedArrival else { return FlightActivityFormatting.unknown }
        return FlightActivityFormatting.time(arrival, in: destinationZone)
    }

    /// Calendar days between departure and arrival at their airports; 0 when
    /// the arrival time isn't known.
    var arrivalDays: Int {
        guard let arrival = state.estimatedArrival else { return 0 }
        return FlightActivityFormatting.arrivalDayOffset(
            departure: state.estimatedDeparture, in: originZone, arrival: arrival, in: destinationZone
        )
    }

    /// "+1" / "−1" when arrival lands on another calendar day.
    var arrivalDayOffset: String? { FlightActivityFormatting.dayOffsetLabel(arrivalDays) }

    /// What VoiceOver says for the arrival, including the day change.
    var spokenArrival: String {
        guard state.estimatedArrival != nil else { return "Arrives \(spokenDestination), time unknown" }
        let base = "Arrives \(spokenDestination) at \(arrivalTime)"
        switch arrivalDays {
        case 0:  return base
        case 1:  return base + ", next day"
        case -1: return base + ", previous day"
        case let days where days > 1: return base + ", \(days) days later"
        default: return base + ", \(-arrivalDays) days earlier"
        }
    }

    var spokenOrigin: String {
        attributes.originSpokenName ?? FlightActivityFormatting.spelledCode(attributes.originIATA)
    }

    var spokenDestination: String {
        attributes.destinationSpokenName ?? FlightActivityFormatting.spelledCode(attributes.destinationIATA)
    }

    var spokenFlight: String { "Flight \(attributes.flightNumber)" }

    var displayCode: (origin: String, destination: String) {
        (FlightActivityFormatting.display(attributes.originIATA),
         FlightActivityFormatting.display(attributes.destinationIATA))
    }
}

// MARK: - Dynamic Island width (iOS 27)

/// Hands its content whether the island is width-limited (iOS 27, e.g. the
/// phone in landscape). Always false on iOS 26, which has no such island.
private struct IslandWidthReader<Content: View>: View {
    @ViewBuilder let content: (_ isLimited: Bool) -> Content

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthEnvironment(content: content)
        } else {
            content(false)
        }
    }
}

@available(iOS 27.0, *)
private struct LimitedWidthEnvironment<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited
    let content: (_ isLimited: Bool) -> Content

    var body: some View { content(isLimited) }
}

// MARK: - Compact

private struct CompactLeading: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        IslandWidthReader { isLimited in
            HStack(spacing: 4) {
                Image(systemName: "airplane")
                    .foregroundStyle(FlightPalette.accent)
                if !isLimited {
                    Text(context.attributes.flightNumber)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(context.spokenFlight)
        }
    }
}

private struct CompactTrailing: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        IslandWidthReader { isLimited in
            let state = context.state
            let now = Date()
            Group {
                if state.status.endsCountdown || state.estimatedDeparture <= now {
                    // No countdown to a flight that won't leave as planned, or
                    // whose departure time has passed: show where it stands.
                    Image(systemName: state.status.symbolName)
                        .foregroundStyle(state.status.tint)
                } else if !isLimited,
                          FlightActivityFormatting.showsGateInCompact(
                              gate: state.gate, departure: state.estimatedDeparture, now: now),
                          let gate = FlightActivityFormatting.knownValue(state.gate) {
                    Text("Gate \(gate)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FlightPalette.accent)
                } else {
                    Text(timerInterval: FlightActivityFormatting.countdownRange(to: state.estimatedDeparture, now: now),
                         countsDown: true)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        // A timer Text otherwise claims the island's full width.
                        .frame(maxWidth: 52)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(compactLabel(now: now))
        }
    }

    private func compactLabel(now: Date) -> String {
        let state = context.state
        if state.status.endsCountdown { return "\(context.spokenFlight) \(state.status.pillLabel)" }
        if let gate = FlightActivityFormatting.knownValue(state.gate),
           FlightActivityFormatting.showsGateInCompact(gate: gate, departure: state.estimatedDeparture, now: now) {
            return "Gate \(gate). Departs at \(context.departureTime)"
        }
        return "Departs at \(context.departureTime)"
    }
}

// MARK: - Minimal

private struct MinimalRing: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        let state = context.state
        Group {
            if state.status.endsCountdown {
                Image(systemName: state.status.symbolName)
                    .foregroundStyle(state.status.tint)
            } else {
                ZStack {
                    ProgressView(timerInterval: FlightActivityFormatting.ringRange(to: state.estimatedDeparture),
                                 countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .tint(FlightPalette.accent)

                    Image(systemName: "airplane")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(context.spokenFlight). \(state.status.pillLabel). Departs at \(context.departureTime)")
    }
}

// MARK: - Expanded

private struct ExpandedEndpoint: View {
    enum End { case departure, arrival }

    let context: ActivityViewContext<FlightActivityAttributes>
    let end: End

    var body: some View {
        let isDeparture = end == .departure
        VStack(alignment: isDeparture ? .leading : .trailing, spacing: 2) {
            Text(isDeparture ? context.displayCode.origin : context.displayCode.destination)
                .font(.title3.weight(.bold))
                .monospaced()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(isDeparture ? context.departureTime : context.arrivalTime)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                if !isDeparture, let offset = context.arrivalDayOffset {
                    Text(offset)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            if isDeparture, let delay = context.state.delayMinutes, delay > 0 {
                Text("+\(delay) min")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(isDeparture ? .leading : .trailing, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(isDeparture: isDeparture))
    }

    private func accessibilityText(isDeparture: Bool) -> String {
        guard isDeparture else { return context.spokenArrival }
        var text = "Departs \(context.spokenOrigin) at \(context.departureTime)"
        if let delay = context.state.delayMinutes, delay > 0 { text += ", \(delay) minutes late" }
        return text
    }
}

private struct ExpandedCenter: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        VStack(spacing: 4) {
            Text(context.attributes.flightNumber)
                .font(.headline)
                .monospacedDigit()
                .accessibilityLabel(context.spokenFlight)
            StatusPill(status: context.state.status)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct ExpandedBottom: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            RouteLine(departure: context.state.estimatedDeparture, arrival: context.state.estimatedArrival)
            HStack(alignment: .bottom, spacing: 12) {
                DetailCell(label: "Gate", value: context.state.gate)
                DetailCell(label: "Terminal", value: context.state.terminal)
                DetailCell(label: "Seat", value: context.state.seat)
                Spacer(minLength: 4)
                Button(intent: OpenBoardingPassIntent(flightNumber: context.attributes.flightNumber,
                                                      departure: context.attributes.scheduledDeparture)) {
                    Label("Boarding pass", systemImage: "qrcode")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(FlightPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show boarding pass for \(context.spokenFlight)")
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Lock Screen and StandBy

/// Picks the layout for the family the system is rendering: the boarding-pass
/// card on the iPhone Lock Screen and in StandBy, the small layout on Apple
/// Watch and in CarPlay.
private struct FlightActivityContentView: View {
    let context: ActivityViewContext<FlightActivityAttributes>
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        if activityFamily == .small {
            SmallFlightView(context: context)
        } else {
            BoardingPassCardView(context: context)
        }
    }
}

private struct BoardingPassCardView: View {
    let context: ActivityViewContext<FlightActivityAttributes>
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let state = context.state
        VStack(spacing: 8) {
            // Airline and flight, status on the right.
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .foregroundStyle(FlightPalette.accent)
                    .accessibilityHidden(true)
                Text(context.attributes.airlineName.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.7))
                Text(context.attributes.flightNumber)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel(context.spokenFlight)
                Spacer(minLength: 4)
                StatusPill(status: state.status)
            }

            // Route: codes, local times, and the line between them.
            HStack(alignment: .center, spacing: 10) {
                CardEndpoint(code: context.displayCode.origin, time: context.departureTime,
                             dayOffset: nil, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Departs \(context.spokenOrigin) at \(context.departureTime)")
                RouteLine(departure: state.estimatedDeparture, arrival: state.estimatedArrival)
                CardEndpoint(code: context.displayCode.destination, time: context.arrivalTime,
                             dayOffset: context.arrivalDayOffset, alignment: .trailing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(context.spokenArrival)
            }

            TearLine()

            // Gate, terminal, seat, and the countdown.
            HStack(alignment: .bottom, spacing: 14) {
                DetailCell(label: "Gate", value: state.gate)
                DetailCell(label: "Terminal", value: state.terminal)
                DetailCell(label: "Seat", value: state.seat)
                Spacer(minLength: 4)
                countdown
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            // In StandBy and other contexts where the system drops the
            // container background, the card draws no fill of its own.
            if showsBackground {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isLuminanceReduced ? 0.02 : 0.05))
                    .padding(4)
            }
        }
        // The Lock Screen card has a fixed height; very large type would clip
        // the details row, so it stops growing at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var countdown: some View {
        let state = context.state
        let now = Date()
        VStack(alignment: .trailing, spacing: 1) {
            if state.status.endsCountdown || state.estimatedDeparture <= now {
                Text("DEPARTURE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(context.departureTime)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .strikethrough(state.status.endsCountdown)
            } else {
                Text("DEPARTS IN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(timerInterval: FlightActivityFormatting.countdownRange(to: state.estimatedDeparture, now: now),
                     countsDown: true)
                    .font(.headline)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isLuminanceReduced ? .white.opacity(0.8) : .white)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Departs at \(context.departureTime)")
    }
}

// MARK: - Small family (Apple Watch Smart Stack, CarPlay)

private struct SmallFlightView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        let state = context.state
        let now = Date()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "airplane")
                    .foregroundStyle(FlightPalette.accent)
                Text(context.attributes.flightNumber)
                    .font(.headline)
                    .monospacedDigit()
                Spacer(minLength: 2)
                Image(systemName: state.status.symbolName)
                    .foregroundStyle(state.status.tint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(context.spokenFlight), \(state.status.pillLabel)")

            Text("\(context.displayCode.origin) → \(context.displayCode.destination)")
                .font(.caption.weight(.semibold))
                .monospaced()
                .accessibilityLabel("\(context.spokenOrigin) to \(context.spokenDestination)")

            HStack {
                Text("Gate \(FlightActivityFormatting.display(state.gate))")
                    .font(.caption)
                Spacer(minLength: 2)
                if state.status.endsCountdown || state.estimatedDeparture <= now {
                    Text(state.status.pillLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.status.tint)
                } else {
                    Text(timerInterval: FlightActivityFormatting.countdownRange(to: state.estimatedDeparture, now: now),
                         countsDown: true)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .accessibilityLabel("Departs at \(context.departureTime)")
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(10)
    }
}

// MARK: - Pieces

private struct StatusPill: View {
    let status: FlightActivityState.FlightStatus

    var body: some View {
        Label(status.pillLabel, systemImage: status.symbolName)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(status.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.18), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(status.pillLabel)")
    }
}

private struct DetailCell: View {
    let label: String
    let value: String?

    var body: some View {
        let shown = FlightActivityFormatting.display(value)
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(shown)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(shown == FlightActivityFormatting.unknown ? "not known yet" : shown)")
    }
}

private struct CardEndpoint: View {
    let code: String
    let time: String
    let dayOffset: String?
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(code)
                .font(.title2.weight(.bold))
                .monospaced()
                .foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(time)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                if let dayOffset {
                    Text(dayOffset)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Origin dot, a line that fills as the scheduled block time passes, and a
/// plane at the destination end. With Reduce Motion on (or no arrival time)
/// the line is drawn once at its current fill and doesn't move.
private struct RouteLine: View {
    let departure: Date
    let arrival: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(FlightPalette.accent)
                .frame(width: 6, height: 6)
            if !reduceMotion, let arrival, arrival > departure {
                ProgressView(timerInterval: departure...arrival, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: FlightActivityFormatting.routeProgress(
                    departure: departure, arrival: arrival, now: Date()))
            }
            Image(systemName: "airplane")
                .font(.caption2)
                .foregroundStyle(FlightPalette.accent)
        }
        .progressViewStyle(.linear)
        .tint(FlightPalette.accent)
        .accessibilityHidden(true)
    }
}

/// The dotted tear line of a paper boarding pass.
private struct TearLine: View {
    var body: some View {
        Line()
            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
