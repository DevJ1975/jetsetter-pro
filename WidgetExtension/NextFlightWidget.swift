// File: WidgetExtension/NextFlightWidget.swift
//
// Next Flight: the flight number, route, a countdown and the gate, on the Home
// Screen, the Lock Screen, StandBy and CarPlay (both use the small widget).
//
//   • Small: flight, route, ticking countdown, gate (or "—").
//   • Medium: adds departure and arrival at each airport's own clock, with
//     "+1" when the arrival lands on another calendar day, plus terminal,
//     seat and a link to the saved boarding pass.
//   • Lock Screen: a countdown gauge (circular), "DL1423 · LAS → ATL" with
//     gate and time (rectangular), and "✈︎ DL1423 in 2h 10m" (inline).
//
// Without live status the widget never claims a flight is boarding, delayed
// or in the air. After the scheduled departure it shows the scheduled
// arrival; a flight with no arrival time drops off at departure.

import SwiftUI
import WidgetKit

struct NextFlightWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKinds.nextFlight,
            intent: TripWidgetConfiguration.self,
            provider: NextFlightProvider()
        ) { entry in
            NextFlightView(entry: entry)
        }
        .configurationDisplayName("Next Flight")
        .description("Countdown, gate, and local times at both airports for your next flight.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NextFlightProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TravelEntry {
        TravelTimeline.placeholder()
    }

    func snapshot(for configuration: TripWidgetConfiguration, in context: Context) async -> TravelEntry {
        TravelTimeline.snapshotEntry(tripID: configuration.tripID, isPreview: context.isPreview)
    }

    func timeline(for configuration: TripWidgetConfiguration, in context: Context) async -> Timeline<TravelEntry> {
        TravelTimeline.timeline(tripID: configuration.tripID, family: context.family, focus: .flight)
    }
}

// MARK: - View

struct NextFlightView: View {
    let entry: TravelEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
            .widgetURL(link)
            .containerBackground(for: .widget) { WidgetPalette.background }
    }

    @ViewBuilder
    private var content: some View {
        if let flight = entry.flight {
            let stage = FlightStage(flight: flight, at: entry.date)
            switch family {
            case .systemMedium:
                MediumFlightView(entry: entry, flight: flight, stage: stage)
            case .accessoryRectangular:
                RectangularFlightView(entry: entry, flight: flight, stage: stage)
            case .accessoryCircular:
                CircularFlightView(entry: entry, flight: flight, stage: stage)
            case .accessoryInline:
                InlineFlightView(entry: entry, flight: flight, stage: stage)
            default:
                SmallFlightView(entry: entry, flight: flight, stage: stage)
            }
        } else if entry.hasTrips {
            NoFlightView(entry: entry, family: family)
        } else {
            NoTripView(family: family)
        }
    }

    private var link: URL? {
        guard entry.hasTrips else { return WidgetLinks.newTrip }
        if let number = entry.flight?.flightNumber, let url = WidgetLinks.flight(number) { return url }
        return WidgetLinks.nextTrip
    }
}

/// Where the flight is in its day, from the timetable alone.
struct FlightStage {
    enum Phase {
        /// Before the scheduled departure.
        case departing
        /// Scheduled departure has passed, scheduled arrival hasn't.
        case arriving
    }

    let phase: Phase
    /// Departure or scheduled arrival, whichever comes next.
    let target: Date
    /// That moment at its airport.
    let targetTime: AirportTime

    init(flight: WidgetSnapshot.FlightLeg, at date: Date) {
        if flight.departure > date || flight.arrival == nil {
            phase = .departing
            target = flight.departure
            targetTime = .departure(of: flight)
        } else {
            phase = .arriving
            target = flight.endsAt
            targetTime = AirportTime.arrival(of: flight) ?? .departure(of: flight)
        }
    }

    var caption: String { phase == .departing ? "Departs in" : "Scheduled to land in" }
    var shortVerb: String { phase == .departing ? "departs" : "lands" }
}

// MARK: - Small

private struct SmallFlightView: View {
    let entry: TravelEntry
    let flight: WidgetSnapshot.FlightLeg
    let stage: FlightStage

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: stage.phase == .departing ? "airplane.departure" : "airplane.arrival")
                Text(flight.flightNumber ?? "Flight")
                    .lineLimit(1)
                Spacer(minLength: 0)
                SampleBadge(entry: entry)
            }
            .font(.caption.weight(.bold))
            .widgetTint(WidgetPalette.accent, in: renderingMode)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Flight \(flight.flightNumber ?? "with no flight number"), \(RouteText(flight: flight).spoken)")

            Text(RouteText(flight: flight).display)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(stage.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                CountdownView(entry: entry, target: stage.target, zone: stage.targetTime.zone)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)

            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 4) {
                    Text("Gate")
                        .foregroundStyle(.secondary)
                    Text(dash(flight.gate))
                        .privacySensitive()
                }
                .font(.caption.weight(.semibold))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

private struct MediumFlightView: View {
    let entry: TravelEntry
    let flight: WidgetSnapshot.FlightLeg
    let stage: FlightStage

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SmallFlightView(entry: entry, flight: flight, stage: stage)

            VStack(alignment: .leading, spacing: 6) {
                AirportTimeView(label: departureLabel, time: .departure(of: flight))
                AirportTimeView(label: arrivalLabel, time: AirportTime.arrival(of: flight))
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 10) {
                        FactView(label: "Terminal", value: flight.terminal)
                        FactView(label: "Seat", value: flight.seat, isPrivate: true)
                    }
                }
                if let passID = flight.walletPassID, let url = WidgetLinks.walletPass(passID) {
                    Link(destination: url) {
                        Label("Boarding pass", systemImage: "qrcode")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .widgetTint(WidgetPalette.accent, in: renderingMode)
                    }
                    .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var departureLabel: String {
        "Departs \(flight.originCity ?? flight.originCode ?? "")".trimmingCharacters(in: .whitespaces)
    }

    private var arrivalLabel: String {
        "Arrives \(flight.destinationCity ?? flight.destinationCode ?? "")".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Lock Screen

/// "DL1423 · LAS → ATL" / "Gate C22 · 9:05 AM" / countdown.
private struct RectangularFlightView: View {
    let entry: TravelEntry
    let flight: WidgetSnapshot.FlightLeg
    let stage: FlightStage

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(flight.flightNumber ?? "Flight") · \(RouteText(flight: flight).display)")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
                .accessibilityLabel("Flight \(flight.flightNumber ?? ""), \(RouteText(flight: flight).spoken)")
            HStack(spacing: 3) {
                Text("Gate")
                Text(dash(flight.gate)).privacySensitive()
                Text("·")
                Text(stage.targetTime.time)
                    .accessibilityLabel("\(stage.shortVerb) \(stage.targetTime.spoken)")
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            CountdownView(entry: entry, target: stage.target, zone: stage.targetTime.zone)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A gauge that drains over the last three hours, with the time left inside.
private struct CircularFlightView: View {
    let entry: TravelEntry
    let flight: WidgetSnapshot.FlightLeg
    let stage: FlightStage

    private static let window: TimeInterval = 3 * 3_600

    var body: some View {
        Gauge(value: WidgetClock.remainingFraction(at: entry.countdownAsOf, until: stage.target, window: Self.window)) {
            Image(systemName: "airplane")
        } currentValueLabel: {
            Text(centerText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Time left inside the countdown window; the departure time beyond it.
    private var centerText: String {
        if stage.target.timeIntervalSince(entry.date) > WidgetTimelinePlanner.countdownWindow {
            return stage.targetTime.time
        }
        return WidgetClock.compactCountdown(from: entry.countdownAsOf, to: stage.target) ?? "Now"
    }

    private var spoken: String {
        let flightName = "Flight \(flight.flightNumber ?? "")"
        guard let left = WidgetClock.spokenCountdown(from: entry.countdownAsOf, to: stage.target) else {
            return "\(flightName) \(stage.shortVerb) now"
        }
        return "\(flightName) \(stage.shortVerb) in about \(left)"
    }
}

/// "✈︎ DL1423 in 2h 10m".
private struct InlineFlightView: View {
    let entry: TravelEntry
    let flight: WidgetSnapshot.FlightLeg
    let stage: FlightStage

    var body: some View {
        Text(line)
    }

    private var line: String {
        let number = flight.flightNumber ?? "Flight"
        if stage.target.timeIntervalSince(entry.date) > WidgetTimelinePlanner.countdownWindow {
            return "✈︎ \(number) \(WidgetClock.weekdayTime(stage.target, in: stage.targetTime.zone ?? .current))"
        }
        guard let left = WidgetClock.compactCountdown(from: entry.countdownAsOf, to: stage.target) else {
            return "✈︎ \(number) \(stage.shortVerb) now"
        }
        return stage.phase == .departing ? "✈︎ \(number) in \(left)" : "✈︎ \(number) lands in \(left)"
    }
}

// MARK: - No flight

/// A trip with no upcoming flight: say so, and name the trip.
private struct NoFlightView: View {
    let entry: TravelEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("✈︎ No upcoming flight")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "airplane").font(.title3)
            }
            .accessibilityLabel("No upcoming flight")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("No upcoming flight").font(.headline).widgetAccentable()
                Text(entry.trip?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "airplane").font(.title3).widgetAccentable()
                Text("No upcoming flight").font(.headline)
                Spacer(minLength: 0)
                if let trip = entry.trip {
                    Text(trip.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(dash(trip.destination)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
