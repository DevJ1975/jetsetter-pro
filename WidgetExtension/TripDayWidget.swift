// File: WidgetExtension/TripDayWidget.swift
//
// Trip Day: today's itinerary for the active trip (or a pinned one) as a
// timeline, each item on the clock of the place it happens, with the
// destination's current weather and the next flight underneath.
//
// "Today" is the traveler's today: the phone's calendar, which follows them
// as they fly. When nothing is left today, the widget shows the next day that
// has something, labelled, rather than an empty list. On a trip that hasn't
// started, that's its first day.
//
// systemLarge only. `systemExtraLarge` is iPadOS and macOS (Apple's
// WidgetFamily docs), so iPhone, the iPhone Ultra included, never offers it.

import SwiftUI
import WidgetKit

struct TripDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKinds.tripDay,
            intent: TripWidgetConfiguration.self,
            provider: TripDayProvider()
        ) { entry in
            TripDayView(entry: entry)
        }
        .configurationDisplayName("Trip Day")
        .description("Today's itinerary in local times, with destination weather and your next flight.")
        .supportedFamilies([.systemLarge])
    }
}

struct TripDayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TravelEntry {
        TravelTimeline.placeholder()
    }

    func snapshot(for configuration: TripWidgetConfiguration, in context: Context) async -> TravelEntry {
        TravelTimeline.snapshotEntry(tripID: configuration.tripID, isPreview: context.isPreview)
    }

    func timeline(for configuration: TripWidgetConfiguration, in context: Context) async -> Timeline<TravelEntry> {
        TravelTimeline.timeline(tripID: configuration.tripID, family: context.family, focus: .day)
    }
}

// MARK: - Model

/// Which day the widget shows and what's on it.
struct TripDayModel {
    let heading: String
    let items: [WidgetSnapshot.DayItem]
    /// Shown when the list isn't today's, or is empty.
    let note: String?

    init(trip: WidgetSnapshot.TripSummary, at date: Date, calendar: Calendar = .current) {
        let today = trip.items.filter { calendar.isDate($0.start, inSameDayAs: date) }
        if !today.isEmpty {
            heading = "Today · \(Self.dayText(date, calendar: calendar))"
            items = today
            note = nil
            return
        }
        guard let next = trip.items.first(where: { $0.start > date }) else {
            heading = "Today · \(Self.dayText(date, calendar: calendar))"
            items = []
            let underWay = trip.startDate <= date && date <= trip.endDate
            note = underWay ? "Nothing else scheduled on this trip." : "Add itinerary items to see your day here."
            return
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let label = calendar.isDate(next.start, inSameDayAs: tomorrow) ? "Tomorrow" : "Next"
        heading = "\(label) · \(Self.dayText(next.start, calendar: calendar))"
        items = trip.items.filter { calendar.isDate($0.start, inSameDayAs: next.start) }
        note = "Nothing scheduled for the rest of today."
    }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).month(.abbreviated).day())
    }
}

// MARK: - View

struct TripDayView: View {
    let entry: TravelEntry

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let trip = entry.trip {
                content(for: trip)
            } else {
                NoTripView(family: .systemLarge)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .widgetURL(link)
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func content(for trip: WidgetSnapshot.TripSummary) -> some View {
        let model = TripDayModel(trip: trip, at: entry.date)
        let maxRows = dynamicTypeSize.isAccessibilitySize ? 3 : WidgetSnapshot.maxItemsPerTrip
        return VStack(alignment: .leading, spacing: 8) {
            header(trip: trip, model: model)
            Divider()
            if let note = model.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Rows are built inline with modifiers on the cells: a modified
            // or wrapped GridRow stops being a row, and the time column loses
            // its alignment.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(model.items.prefix(maxRows)) { item in
                    let time = AirportTime(date: item.start, zone: WidgetClock.zone(item.timeZoneID))
                    let isPast = item.start < entry.date
                    GridRow {
                        ItemTimeCell(time: time)
                            .foregroundStyle(isPast ? .secondary : .primary)
                            .gridColumnAlignment(.trailing)
                        Image(systemName: item.kind.systemImage)
                            .font(.subheadline)
                            .widgetTint(WidgetPalette.accent, in: renderingMode)
                            .widgetAccentable()
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(isPast ? .secondary : .primary)
                            .accessibilityLabel("\(item.title)\(isPast ? ", earlier" : "")")
                    }
                }
            }
            Spacer(minLength: 0)
            if let flight = WidgetTimelinePlanner.currentFlight(in: trip.flights, at: entry.date) {
                FlightFooter(flight: flight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(trip: WidgetSnapshot.TripSummary, model: TripDayModel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.heading.uppercased())
                        .font(.caption.weight(.bold))
                        .widgetTint(WidgetPalette.accent, in: renderingMode)
                        .widgetAccentable()
                        .lineLimit(1)
                    SampleBadge(entry: entry)
                }
                Text(trip.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !trip.destination.isEmpty {
                    Text(trip.destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let weather = trip.weather, weather.isCurrent(at: entry.date) {
                WeatherBadge(weather: weather)
            }
        }
    }

    private var link: URL? {
        guard entry.hasTrips else { return WidgetLinks.newTrip }
        if let id = entry.tripID, entry.trip?.id == id { return WidgetLinks.trip(id) }
        return WidgetLinks.nextTrip
    }
}

/// An itinerary item's local time, with the zone when it isn't the phone's.
private struct ItemTimeCell: View {
    let time: AirportTime

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(time.time)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            if let zone = time.zoneLabel {
                Text(zone)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.spoken)
    }
}

/// Current conditions at the destination. WeatherKit data carries the Apple
/// Weather mark, as Apple requires wherever it's displayed; the legal link
/// lives in the app, since a widget can only open the app.
private struct WeatherBadge: View {
    let weather: WidgetSnapshot.Weather

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(renderingMode == .fullColor ? .multicolor : .monochrome)
                Text(temperature)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            Text(weather.condition)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if weather.isAppleWeather {
                Text("\u{F8FF} Weather")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Weather data by Apple Weather")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// In the reader's unit: 74°F in the US, 23°C elsewhere.
    private var temperature: String {
        Measurement(value: weather.temperatureFahrenheit, unit: UnitTemperature.fahrenheit)
            .formatted(.measurement(width: .narrow, usage: .weather,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// "✈︎ DL1423 · LAS → ATL · Gate C22 · 9:05 AM", linking to the flight.
private struct FlightFooter: View {
    let flight: WidgetSnapshot.FlightLeg

    var body: some View {
        let departure = AirportTime.departure(of: flight)
        let row = HStack(spacing: 6) {
            Image(systemName: "airplane")
            Text(flight.flightNumber ?? "Flight").fontWeight(.semibold)
            Text(RouteText(flight: flight).display)
            Text("Gate")
                .foregroundStyle(.secondary)
            Text(dash(flight.gate))
                .privacySensitive()
            Spacer(minLength: 0)
            Text(departure.time).monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next flight \(flight.flightNumber ?? ""), \(RouteText(flight: flight).spoken), gate \(dash(flight.gate)), departs \(departure.spoken)")

        if let number = flight.flightNumber, let url = WidgetLinks.flight(number) {
            Link(destination: url) { row }
        } else {
            row
        }
    }
}
