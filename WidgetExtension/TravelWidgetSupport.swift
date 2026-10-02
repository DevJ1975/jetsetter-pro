// File: WidgetExtension/TravelWidgetSupport.swift
//
// What the Next Flight, Leave By, Trip Day and Destination Clock widgets
// share: the timeline entry, the provider logic that turns the app's
// `WidgetSnapshot` into entries at the moments that matter, the palette, and
// the small views every widget uses (the empty state, "—" for unknowns, airport
// times with their zone and day offset).
//
// Rules every widget follows:
//   • Unknown gate, terminal, seat or route shows "—". Nothing is guessed.
//   • Times are wall-clock times at the airport, in that airport's zone, with
//     the zone named when it differs from the phone's.
//   • Sample data (the LAS → ATL demo journey) is only ever drawn redacted as
//     a loading placeholder, or labelled SAMPLE in the widget gallery.
//   • Colour only in full-colour rendering. In accented (tinted and clear
//     Home Screens) and vibrant (Lock Screen, StandBy night mode) rendering,
//     hierarchy comes from weight and `.secondary`, and the key figure in each
//     widget is marked `widgetAccentable()`.

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Palette

/// The Executive appearance's tokens from `JetsetterTheme`, which lives in
/// the app target. Light and dark values are the theme's own.
enum WidgetPalette {
    static let accent = dynamic(light: 0x0055CC, dark: 0x3B9EF0)
    static let background = dynamic(light: 0xFFFFFF, dark: 0x161929)
    static let warning = dynamic(light: 0xB07010, dark: 0xE8A020)
    static let danger = dynamic(light: 0xC42020, dark: 0xFF5C5C)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

extension View {
    /// Palette colour in full-colour rendering; the system's primary style
    /// otherwise, so tinted, clear, vibrant and StandBy night rendering stay
    /// legible.
    func widgetTint(_ color: Color, in mode: WidgetRenderingMode) -> some View {
        foregroundStyle(mode == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(HierarchicalShapeStyle.primary))
    }
}

// MARK: - Entry

struct TravelEntry: TimelineEntry {

    enum Presentation {
        /// The traveler's own data.
        case live
        /// Loading placeholder: sample data, always drawn redacted.
        case placeholder
        /// Widget gallery with no trips yet: sample data, labelled SAMPLE.
        case sample
    }

    let date: Date
    let snapshot: WidgetSnapshot?
    /// The trip this widget was configured to follow; nil follows the
    /// active-or-next trip.
    let tripID: UUID?
    let presentation: Presentation
    /// When plain-text countdowns are computed for: the end of this entry's
    /// short display window, so a countdown that can't tick understates the
    /// time left by a few minutes rather than ever overstating it.
    let countdownAsOf: Date
    var relevance: TimelineEntryRelevance?

    var trip: WidgetSnapshot.TripSummary? { snapshot?.trip(preferring: tripID) }

    var flight: WidgetSnapshot.FlightLeg? {
        guard let snapshot else { return nil }
        return WidgetTimelinePlanner.currentFlight(in: snapshot.flights(forTrip: tripID), at: date)
    }

    var leaveBy: WidgetSnapshot.LeaveBy? {
        WidgetTimelinePlanner.leaveBy(snapshot?.leaveBy, for: flight, at: date)
    }

    var hasTrips: Bool { !(snapshot?.trips.isEmpty ?? true) }
    var isPlaceholder: Bool { presentation == .placeholder }
}

// MARK: - Timelines

/// Builds entries for every travel widget from the shared snapshot.
enum TravelTimeline {

    enum Focus {
        case flight, leaveBy, day, clock
    }

    /// A plain-text countdown is never computed for more than this past its
    /// entry, which is also the refresh step in the last two hours.
    private static let countdownLookahead: TimeInterval = 5 * 60

    static func loadSnapshot() -> WidgetSnapshot? {
        WidgetSnapshotStore.load(from: WidgetSnapshotStore.sharedDefaults())
    }

    static func placeholder(now: Date = Date()) -> TravelEntry {
        TravelEntry(date: now, snapshot: .sample(now: now), tripID: nil, presentation: .placeholder,
                    countdownAsOf: now, relevance: nil)
    }

    /// The gallery and transient snapshot: the traveler's data when there is
    /// any, otherwise the labelled sample in the gallery.
    static func snapshotEntry(tripID: UUID?, isPreview: Bool, now: Date = Date()) -> TravelEntry {
        let snapshot = loadSnapshot()
        if isPreview, snapshot?.trips.isEmpty ?? true {
            return TravelEntry(date: now, snapshot: .sample(now: now), tripID: nil, presentation: .sample,
                               countdownAsOf: now, relevance: nil)
        }
        return TravelEntry(date: now, snapshot: snapshot, tripID: tripID, presentation: .live,
                           countdownAsOf: now, relevance: nil)
    }

    static func timeline(tripID: UUID?, family: WidgetFamily, focus: Focus, now: Date = Date()) -> Timeline<TravelEntry> {
        let snapshot = loadSnapshot()
        var dates = WidgetTimelinePlanner.entryDates(for: snapshot, tripID: tripID, now: now, calendar: .current)

        // Inline and circular widgets show their countdown as plain text,
        // which doesn't tick, so they get extra entries as the target nears.
        if family == .accessoryInline || family == .accessoryCircular,
           let target = countdownTarget(snapshot: snapshot, tripID: tripID, focus: focus, at: now) {
            let end = now.addingTimeInterval(WidgetTimelinePlanner.horizon)
            dates = Array(Set(dates + WidgetTimelinePlanner.countdownRefreshDates(until: target, after: now)
                .filter { $0 <= end })).sorted()
        }

        let entries = dates.enumerated().map { index, date -> TravelEntry in
            let next = index + 1 < dates.count ? dates[index + 1] : date
            let asOf = min(next, date.addingTimeInterval(countdownLookahead))
            var entry = TravelEntry(date: date, snapshot: snapshot, tripID: tripID, presentation: .live,
                                    countdownAsOf: asOf, relevance: nil)
            entry.relevance = relevance(for: entry, focus: focus)
            return entry
        }
        // With nothing ahead there's nothing to reload for; the app reloads
        // timelines itself when a trip changes.
        return Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never)
    }

    /// What a plain-text countdown counts down to right now.
    private static func countdownTarget(snapshot: WidgetSnapshot?, tripID: UUID?, focus: Focus, at date: Date) -> Date? {
        guard let snapshot else { return nil }
        let flight = WidgetTimelinePlanner.currentFlight(in: snapshot.flights(forTrip: tripID), at: date)
        switch focus {
        case .leaveBy:
            return WidgetTimelinePlanner.leaveBy(snapshot.leaveBy, for: flight, at: date)?.leaveAt
        case .flight:
            guard let flight else { return nil }
            return flight.departure > date ? flight.departure : flight.arrival
        case .day, .clock:
            return nil
        }
    }

    /// Smart Stack ranking: a flight in the next few hours, or a leave-by
    /// coming up, rises to the top; a widget with nothing to say sinks.
    private static func relevance(for entry: TravelEntry, focus: Focus) -> TimelineEntryRelevance {
        let hour: TimeInterval = 3_600
        switch focus {
        case .leaveBy:
            guard let leaveBy = entry.leaveBy else { return TimelineEntryRelevance(score: 0) }
            let until = leaveBy.leaveAt.timeIntervalSince(entry.date)
            return TimelineEntryRelevance(score: until < 2 * hour ? 100 : 40)
        case .flight:
            guard let flight = entry.flight else { return TimelineEntryRelevance(score: 0) }
            let until = flight.departure.timeIntervalSince(entry.date)
            if until <= 0 { return TimelineEntryRelevance(score: 60) }
            if until < 3 * hour { return TimelineEntryRelevance(score: 90) }
            return TimelineEntryRelevance(score: until < 24 * hour ? 50 : 10)
        case .day:
            guard let trip = entry.trip else { return TimelineEntryRelevance(score: 0) }
            let underWay = trip.startDate <= entry.date && entry.date <= trip.endDate
            return TimelineEntryRelevance(score: underWay ? 50 : 10)
        case .clock:
            guard let trip = entry.trip else { return TimelineEntryRelevance(score: 0) }
            let underWay = trip.startDate <= entry.date && entry.date <= trip.endDate
            return TimelineEntryRelevance(score: underWay ? 30 : 5)
        }
    }
}

// MARK: - Sample

extension WidgetSnapshot {

    /// The LAS → ATL journey from the demo seeder, relative to `now`. Only
    /// ever drawn redacted (placeholders) or labelled SAMPLE (gallery).
    static func sample(now: Date) -> WidgetSnapshot {
        let departure = now.addingTimeInterval(75 * 60)
        let arrival = departure.addingTimeInterval(4 * 3_600 + 7 * 60)
        let flight = FlightLeg(
            id: UUID(), flightNumber: "DL1423", airline: "Delta Air Lines",
            originCode: "LAS", originCity: "Las Vegas", destinationCode: "ATL", destinationCity: "Atlanta",
            departure: departure, arrival: arrival,
            originTimeZoneID: "America/Los_Angeles", destinationTimeZoneID: "America/New_York",
            gate: "C22", terminal: "1", seat: "3A", walletPassID: nil,
            checkInOpensAt: nil, boardingEstimate: departure.addingTimeInterval(-30 * 60))
        let items = [
            DayItem(id: flight.id, kind: .flight, title: "Delta DL1423 to Atlanta", start: departure,
                    timeZoneID: "America/Los_Angeles"),
            DayItem(id: UUID(), kind: .transport, title: "Hertz pickup", start: arrival.addingTimeInterval(30 * 60),
                    timeZoneID: "America/New_York"),
            DayItem(id: UUID(), kind: .hotel, title: "The Ritz-Carlton, Atlanta", start: arrival.addingTimeInterval(90 * 60),
                    timeZoneID: "America/New_York")
        ]
        let trip = TripSummary(
            id: UUID(), name: "Atlanta Board Meeting", destination: "Atlanta, GA",
            startDate: departure, endDate: departure.addingTimeInterval(3 * 86_400),
            destinationCode: "ATL", destinationTimeZoneID: "America/New_York",
            flights: [flight], items: items,
            weather: Weather(temperatureFahrenheit: 74, symbolName: "sun.max.fill", condition: "Clear",
                             isAppleWeather: false, observedAt: now))
        let leaveBy = LeaveBy(flightID: flight.id, leaveAt: now.addingTimeInterval(15 * 60),
                              usesLiveTraffic: true, computedAt: now, expiresAt: now.addingTimeInterval(6 * 3_600))
        return WidgetSnapshot(schemaVersion: currentSchemaVersion, generatedAt: now,
                              homeTimeZoneID: "America/Los_Angeles", trips: [trip], leaveBy: leaveBy)
    }
}

// MARK: - Shared views

/// "—" for an unknown value, never a guess.
func dash(_ value: String?) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "—" }
    return value
}

/// A small caps label over a value: "GATE" / "C22".
struct FactView: View {
    let label: String
    let value: String?
    var isPrivate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(dash(value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive(isPrivate)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "LAS → ATL", with unknown codes as "—", and a spoken form that uses city
/// names: "Las Vegas to Atlanta", not "L A S arrow A T L".
struct RouteText {
    let flight: WidgetSnapshot.FlightLeg

    var display: String { "\(dash(flight.originCode)) → \(dash(flight.destinationCode))" }

    var spoken: String {
        let from = flight.originCity ?? flight.originCode ?? "an unknown airport"
        let to = flight.destinationCity ?? flight.destinationCode ?? "an unknown airport"
        return "\(from) to \(to)"
    }
}

/// A flight time at its airport: the wall-clock time in the airport's zone,
/// the zone's abbreviation when the phone is on a different clock, and the
/// day offset ("+1") for an arrival on another calendar day.
struct AirportTime {
    let date: Date
    let zone: TimeZone?
    var dayOffset: Int = 0

    private var resolvedZone: TimeZone { zone ?? .current }

    var time: String { WidgetClock.time(date, in: resolvedZone) }

    var zoneLabel: String? {
        guard let zone else { return nil }
        return WidgetClock.zoneLabel(zone, differingFrom: .current, at: date)
    }

    var dayLabel: String? { WidgetClock.dayOffsetLabel(dayOffset) }

    var spoken: String {
        var phrase = time
        if let zoneLabel { phrase += " \(zoneLabel)" }
        if let day = WidgetClock.spokenDayOffset(dayOffset) { phrase += ", \(day)" }
        return phrase
    }

    /// Departure in the origin's zone; arrival in the destination's, with the
    /// day offset measured between the two local calendars.
    static func departure(of flight: WidgetSnapshot.FlightLeg) -> AirportTime {
        AirportTime(date: flight.departure, zone: WidgetClock.zone(flight.originTimeZoneID))
    }

    static func arrival(of flight: WidgetSnapshot.FlightLeg) -> AirportTime? {
        guard let arrival = flight.arrival else { return nil }
        let originZone = WidgetClock.zone(flight.originTimeZoneID)
        let destinationZone = WidgetClock.zone(flight.destinationTimeZoneID)
        // Without both zones the offset could be wrong, so it isn't shown.
        let offset = originZone.flatMap { origin in
            destinationZone.map { WidgetClock.dayOffset(from: flight.departure, in: origin, to: arrival, in: $0) }
        } ?? 0
        return AirportTime(date: arrival, zone: destinationZone, dayOffset: offset)
    }
}

/// The time row used by the medium flight widget: "9:05 AM PDT +1".
struct AirportTimeView: View {
    let label: String
    let time: AirportTime?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let time {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(time.time)
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let zone = time.zoneLabel {
                        Text(zone).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let day = time.dayLabel {
                        Text(day).font(.caption2.weight(.bold))
                    }
                }
            } else {
                Text("—").font(.headline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(time?.spoken ?? "time unknown")")
    }
}

/// A countdown to `target`: a ticking timer inside the 12-hour window, the
/// weekday and time beyond it. Always On (reduced luminance) can't tick, so it
/// gets the plain-text form.
struct CountdownView: View {
    let entry: TravelEntry
    let target: Date
    let zone: TimeZone?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let remaining = target.timeIntervalSince(entry.date)
        if remaining > WidgetTimelinePlanner.countdownWindow {
            Text(WidgetClock.weekdayTime(target, in: zone ?? .current))
        } else if remaining > 0, !isLuminanceReduced {
            Text(timerInterval: entry.date...target, countsDown: true, showsHours: true)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        } else {
            Text(WidgetClock.compactCountdown(from: entry.countdownAsOf, to: target) ?? "Now")
                .monospacedDigit()
        }
    }
}

/// "SAMPLE" over gallery previews built from sample data.
struct SampleBadge: View {
    let entry: TravelEntry

    var body: some View {
        if entry.presentation == .sample {
            Text("SAMPLE")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sample data")
        }
    }
}

/// No upcoming trip: one sentence and the way to add one.
struct NoTripView: View {
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("✈︎ No upcoming trip")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("No upcoming trip. Add a trip.")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("No upcoming trip", systemImage: "airplane")
                    .font(.headline)
                    .widgetAccentable()
                Text("Tap to add a trip").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "airplane.departure")
                    .font(.title2)
                    .widgetTint(WidgetPalette.accent, in: renderingMode)
                    .widgetAccentable()
                Text("No upcoming trip")
                    .font(.headline)
                Spacer(minLength: 0)
                if let url = WidgetLinks.newTrip {
                    Link(destination: url) {
                        Label("Add a trip", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .widgetTint(WidgetPalette.accent, in: renderingMode)
                    }
                    .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
