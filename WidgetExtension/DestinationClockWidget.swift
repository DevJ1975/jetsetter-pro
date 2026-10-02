// File: WidgetExtension/DestinationClockWidget.swift
//
// Destination Clock: the time where the traveler is going next to the time at
// home, with the destination city, the offset ("+3h") and a day badge when
// the destination is already on tomorrow (or still on yesterday).
//
// "Home" is the home airport from Settings. Without one the second clock is
// labelled "Here" and follows the phone, which is honest about what it shows.
// The destination's zone comes from the trip's outbound flight; a trip without
// airport codes shows "—" for its time rather than guessing from the city.
//
// Both clocks tick on their own (`Text(.currentDate, format:)`, iOS 18), so
// the timeline only needs entries at midnight in each zone, when the day badge
// can change, and when trips start or end.

import SwiftUI
import WidgetKit

struct DestinationClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.destinationClock, provider: DestinationClockProvider()) { entry in
            DestinationClockView(entry: entry)
        }
        .configurationDisplayName("Destination Clock")
        .description("Your destination's time beside home time, with the day difference.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct DestinationClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> TravelEntry {
        TravelTimeline.placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (TravelEntry) -> Void) {
        completion(TravelTimeline.snapshotEntry(tripID: nil, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TravelEntry>) -> Void) {
        completion(TravelTimeline.timeline(tripID: nil, family: context.family, focus: .clock))
    }
}

// MARK: - Model

struct ClockModel {
    /// "Atlanta" from "Atlanta, GA".
    let city: String
    let destinationZone: TimeZone?
    let homeZone: TimeZone
    /// "Home" with a home airport set, "Here" (the phone's zone) without.
    let homeLabel: String

    init(trip: WidgetSnapshot.TripSummary, homeTimeZoneID: String?) {
        let typed = trip.destination.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        city = typed.isEmpty ? (trip.destinationCode ?? "Destination") : typed
        destinationZone = WidgetClock.zone(trip.destinationTimeZoneID)
        if let home = WidgetClock.zone(homeTimeZoneID) {
            homeZone = home
            homeLabel = "Home"
        } else {
            homeZone = .current
            homeLabel = "Here"
        }
    }

    func dayBadge(at date: Date) -> (label: String, spoken: String)? {
        guard let destinationZone else { return nil }
        let days = WidgetClock.dayDifference(at: date, home: homeZone, destination: destinationZone)
        guard let label = WidgetClock.dayOffsetLabel(days), let spoken = WidgetClock.spokenDayOffset(days) else { return nil }
        return (label, spoken)
    }

    /// "+3h from home", "Same time as home", or the same against "here".
    func offsetText(at date: Date) -> String? {
        guard let destinationZone else { return nil }
        let offset = WidgetClock.offsetLabel(home: homeZone, destination: destinationZone, at: date)
        let reference = homeLabel.lowercased()
        return offset == "Same time" ? "Same time as \(reference)" : "\(offset) from \(reference)"
    }
}

/// A clock that keeps time in `zone` by itself, in the reader's 12- or 24-hour style.
struct LiveClockText: View {
    let zone: TimeZone

    var body: some View {
        Text(.currentDate, format: style)
            .monospacedDigit()
    }

    private var style: Date.FormatStyle {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = zone
        return Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: zone)
    }
}

// MARK: - View

struct DestinationClockView: View {
    let entry: TravelEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let trip = entry.trip {
                let model = ClockModel(trip: trip, homeTimeZoneID: entry.snapshot?.homeTimeZoneID)
                if family == .accessoryRectangular {
                    RectangularClockView(entry: entry, model: model)
                } else {
                    SmallClockView(entry: entry, model: model)
                }
            } else {
                NoTripView(family: family)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .widgetURL(entry.hasTrips ? WidgetLinks.nextTrip : WidgetLinks.newTrip)
        .containerBackground(for: .widget) { WidgetPalette.background }
    }
}

private struct SmallClockView: View {
    let entry: TravelEntry
    let model: ClockModel

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(model.city.uppercased())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                SampleBadge(entry: entry)
            }
            .font(.caption.weight(.bold))
            .widgetTint(WidgetPalette.accent, in: renderingMode)
            .widgetAccentable()

            if let zone = model.destinationZone {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    LiveClockText(zone: zone)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                    if let badge = model.dayBadge(at: entry.date) {
                        Text(badge.label)
                            .font(.caption.weight(.bold))
                            .accessibilityLabel(badge.spoken)
                    }
                }
                if let offset = model.offsetText(at: entry.date) {
                    Text(offset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityLabel("Local time unknown")
                Text("Add the flight's airport codes to see local time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline) {
                Text(model.homeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                LiveClockText(zone: model.homeZone)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Atlanta 4:12 PM +1" over "Home 1:12 PM · +3h".
private struct RectangularClockView: View {
    let entry: TravelEntry
    let model: ClockModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.city)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let zone = model.destinationZone {
                    LiveClockText(zone: zone)
                    if let badge = model.dayBadge(at: entry.date) {
                        Text(badge.label).accessibilityLabel(badge.spoken)
                    }
                } else {
                    Text("—").accessibilityLabel("Local time unknown")
                }
            }
            .font(.headline)
            .widgetAccentable()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.homeLabel)
                LiveClockText(zone: model.homeZone)
            }
            .font(.caption)
            if let offset = model.offsetText(at: entry.date) {
                Text(offset)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
