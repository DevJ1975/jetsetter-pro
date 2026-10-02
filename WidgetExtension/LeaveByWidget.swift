// File: WidgetExtension/LeaveByWidget.swift
//
// Leave By: "Leave by 7:40" with a countdown, on the Lock Screen and as a small
// widget (which StandBy and CarPlay also use).
//
// The time is the one the Departure Optimizer last computed from live traffic,
// the same one Home and Siri quote, never a number made up for the widget.
// Once that traffic reading is more than 30 minutes old, the time stays but is
// marked "est.": the roads have moved on since. After six hours it's dropped,
// as it is in the app. With no leave-by the Lock Screen widgets draw nothing,
// and the small widget says how to get one.
//
// The time is shown on the departure airport's clock, since leave-by times are
// relative to where the traveler is flying from.

import SwiftUI
import WidgetKit

struct LeaveByWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.leaveBy, provider: LeaveByProvider()) { entry in
            LeaveByView(entry: entry)
        }
        .configurationDisplayName("Leave By")
        .description("When to leave for the airport, from live traffic.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall])
    }
}

struct LeaveByProvider: TimelineProvider {
    func placeholder(in context: Context) -> TravelEntry {
        TravelTimeline.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelEntry) -> Void) {
        completion(TravelTimeline.snapshotEntry(tripID: nil, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelEntry>) -> Void) {
        completion(TravelTimeline.timeline(tripID: nil, family: context.family, focus: .leaveBy))
    }
}

// MARK: - View

struct LeaveByView: View {
    let entry: TravelEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
            .widgetURL(WidgetLinks.nextTrip)
            .containerBackground(for: .widget) { WidgetPalette.background }
    }

    @ViewBuilder
    private var content: some View {
        if let leaveBy = entry.leaveBy, let flight = entry.flight {
            let model = LeaveByModel(leaveBy: leaveBy, flight: flight, at: entry.date)
            switch family {
            case .accessoryRectangular:
                RectangularLeaveByView(entry: entry, model: model)
            case .accessoryCircular:
                CircularLeaveByView(entry: entry, model: model)
            default:
                SmallLeaveByView(entry: entry, model: model)
            }
        } else if family == .systemSmall {
            NoLeaveByView()
        }
        // Lock Screen widgets with no leave-by stay empty.
    }
}

/// What every Leave By layout shows, worked out once.
struct LeaveByModel {
    let leaveAt: Date
    let flight: WidgetSnapshot.FlightLeg
    /// "7:40 AM" on the departure airport's clock.
    let time: String
    let zone: TimeZone?
    /// The traffic reading is recent enough to call live.
    let isLive: Bool
    /// The leave-by time has passed but the flight hasn't left.
    let isOverdue: Bool

    init(leaveBy: WidgetSnapshot.LeaveBy, flight: WidgetSnapshot.FlightLeg, at date: Date) {
        leaveAt = leaveBy.leaveAt
        self.flight = flight
        zone = WidgetClock.zone(flight.originTimeZoneID)
        time = WidgetClock.time(leaveBy.leaveAt, in: zone ?? .current)
        isLive = leaveBy.isLive(at: date)
        isOverdue = date >= leaveBy.leaveAt
    }

    var flightLine: String {
        "\(flight.flightNumber ?? "Flight") from \(dash(flight.originCode))"
    }

    var spoken: String {
        let estimate = isLive ? "from live traffic" : "estimated"
        if isOverdue { return "Time to leave for \(flightLine). Planned leave time was \(time), \(estimate)." }
        return "Leave by \(time) for \(flightLine), \(estimate)."
    }
}

// MARK: - Small

private struct SmallLeaveByView: View {
    let entry: TravelEntry
    let model: LeaveByModel

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Label(model.isOverdue ? "LEAVE NOW" : "LEAVE BY", systemImage: "car.fill")
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
                SampleBadge(entry: entry)
            }
            .font(.caption.weight(.bold))
            .widgetTint(model.isOverdue ? WidgetPalette.danger : WidgetPalette.accent, in: renderingMode)
            .widgetAccentable()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.time)
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if !model.isLive {
                    Text("est.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !model.isOverdue {
                CountdownView(entry: entry, target: model.leaveAt, zone: model.zone)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(model.flightLine)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(model.isLive ? "Live traffic" : "Traffic estimate")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.spoken)
    }
}

// MARK: - Lock Screen

private struct RectangularLeaveByView: View {
    let entry: TravelEntry
    let model: LeaveByModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "car.fill")
                Text(model.isOverdue ? "Leave now" : "Leave by \(model.time)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !model.isLive {
                    Text("est.").foregroundStyle(.secondary)
                }
            }
            .font(.headline)
            .widgetAccentable()

            if model.isOverdue {
                Text("Planned for \(model.time)")
                    .font(.caption)
            } else {
                CountdownView(entry: entry, target: model.leaveAt, zone: model.zone)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(model.flightLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.spoken)
    }
}

/// The leave-by time inside a gauge that drains over the last two hours.
private struct CircularLeaveByView: View {
    let entry: TravelEntry
    let model: LeaveByModel

    private static let window: TimeInterval = 2 * 3_600

    var body: some View {
        Gauge(value: WidgetClock.remainingFraction(at: entry.countdownAsOf, until: model.leaveAt, window: Self.window)) {
            Image(systemName: "car.fill")
        } currentValueLabel: {
            Text(model.isOverdue ? "Now" : model.time)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spoken)
    }
}

// MARK: - None

private struct NoLeaveByView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "car")
                .font(.title2)
                .widgetTint(WidgetPalette.accent, in: renderingMode)
                .widgetAccentable()
            Text("No leave-by time yet")
                .font(.headline)
            Spacer(minLength: 0)
            Text("Open your next flight in JetSetter Pro to plan the drive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
