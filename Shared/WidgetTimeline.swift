// File: Shared/WidgetTimeline.swift
//
// The time arithmetic behind the widgets, kept free of SwiftUI and WidgetKit
// so it can be tested from the app's test target (`Shared/` compiles into the
// app as well as the widget extension).
//
// Two halves:
//   • `WidgetClock` formats what a traveler reads: a time in an airport's own
//     zone, the "+1" on an arrival that lands the next day, a compact
//     countdown, and home-versus-destination offsets. Every function takes its
//     zones explicitly; the device zone is only ever passed in, never assumed,
//     which is how a red-eye once showed the wrong arrival day.
//   • `WidgetTimelinePlanner` decides when a widget's content changes, so the
//     timeline carries entries at those moments instead of polling: check-in
//     opening, leave-by, boarding, departure, arrival, trip end and midnight.
//
// Widgets have a daily reload budget, but entries inside one timeline are
// free, so the planner front-loads every known moment for the next 48 hours
// and the app reloads timelines only when its data actually changes.

import Foundation

// MARK: - Clock and formatting

nonisolated enum WidgetClock {

    /// The zone for a stored IANA identifier, or nil when it's missing or the
    /// OS doesn't know it. Callers decide the fallback; this never guesses.
    static func zone(_ identifier: String?) -> TimeZone? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// The wall-clock time of `date` in `zone`: "9:05 AM", or "09:05" for a
    /// 24-hour locale.
    ///
    /// The same output as `AppDateFormatters.airportTime(_:in:style: .time)`
    /// in the app, which the widget extension can't link. A test pins the two
    /// together so they can't drift.
    static func time(_ date: Date, in zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        // The calendar's zone decides which day the instant falls on, so it
        // has to match the format zone.
        var calendar = locale.calendar
        calendar.timeZone = zone
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                               locale: locale, calendar: calendar, timeZone: zone))
    }

    /// Weekday and time in `zone`, e.g. "Tue 9:05 AM", for moments more than
    /// a countdown away.
    static func weekdayTime(_ date: Date, in zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = locale.calendar
        calendar.timeZone = zone
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: zone)
            .weekday(.abbreviated).hour().minute()
        return date.formatted(style)
    }

    /// The zone's abbreviation ("PDT") when its offset differs from
    /// `reference` at `date`, so a reader knows whose clock a time is on.
    /// Nil when both zones agree, which keeps the common case uncluttered.
    static func zoneLabel(_ zone: TimeZone, differingFrom reference: TimeZone, at date: Date) -> String? {
        guard zone.secondsFromGMT(for: date) != reference.secondsFromGMT(for: date),
              let abbreviation = zone.abbreviation(for: date), !abbreviation.isEmpty
        else { return nil }
        return abbreviation
    }

    // MARK: Day offsets

    /// Calendar days from the local date of `start` in `startZone` to the
    /// local date of `end` in `endZone`. A 23:30 Las Vegas departure landing
    /// at 06:45 in Atlanta is +1; Auckland to Honolulu across the date line
    /// can be −1.
    static func dayOffset(from start: Date, in startZone: TimeZone, to end: Date, in endZone: TimeZone) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = startZone
        let startDay = gregorian.dateComponents([.year, .month, .day], from: start)
        gregorian.timeZone = endZone
        let endDay = gregorian.dateComponents([.year, .month, .day], from: end)
        // Compare the two local dates as plain dates in one fixed zone.
        gregorian.timeZone = .gmt
        guard let startMidnight = gregorian.date(from: startDay),
              let endMidnight = gregorian.date(from: endDay)
        else { return 0 }
        return gregorian.dateComponents([.day], from: startMidnight, to: endMidnight).day ?? 0
    }

    /// "+1", "+2" or "−1" (a true minus sign); nil for the same day.
    static func dayOffsetLabel(_ days: Int) -> String? {
        if days == 0 { return nil }
        return days > 0 ? "+\(days)" : "\u{2212}\(-days)"
    }

    /// The VoiceOver phrase for a day offset; nil for the same day.
    static func spokenDayOffset(_ days: Int) -> String? {
        switch days {
        case 0:  return nil
        case 1:  return "the next day"
        case -1: return "the previous day"
        default: return days > 0 ? "\(days) days later" : "\(-days) days earlier"
        }
    }

    // MARK: Countdowns

    /// "2h 10m", "45m", "3d 4h", or "<1m" in the final minute; nil once
    /// `target` has passed. Whole units are floored, the same shape as the
    /// countdown capsule on Home.
    static func compactCountdown(from now: Date, to target: Date) -> String? {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        guard totalMinutes > 0 else { return "<1m" }
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// The VoiceOver form of `compactCountdown`: "2 hours 10 minutes".
    static func spokenCountdown(from now: Date, to target: Date) -> String? {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let totalMinutes = Int(seconds / 60)
        guard totalMinutes > 0 else { return "less than a minute" }
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        func unit(_ value: Int, _ name: String) -> String? {
            value == 0 ? nil : "\(value) \(name)\(value == 1 ? "" : "s")"
        }
        let parts = days > 0
            ? [unit(days, "day"), unit(hours, "hour")]
            : [unit(hours, "hour"), unit(minutes, "minute")]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// How much of `window` is left before `target`: 1 when `target` is
    /// further away than the window, 0 once it has passed. Drives the
    /// circular countdown gauges.
    static func remainingFraction(at now: Date, until target: Date, window: TimeInterval) -> Double {
        guard window > 0 else { return 0 }
        return min(1, max(0, target.timeIntervalSince(now) / window))
    }

    // MARK: Home vs destination

    /// The destination's offset from home at `date`: "+3h", "−5h 30m" or
    /// "Same time". Measured at the instant, so DST on either side counts.
    static func offsetLabel(home: TimeZone, destination: TimeZone, at date: Date) -> String {
        let seconds = destination.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)
        guard seconds != 0 else { return "Same time" }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours)h \(remainder)m"
    }

    /// Whether it's already tomorrow (+1) or still yesterday (−1) at the
    /// destination compared with home, at the same instant.
    static func dayDifference(at date: Date, home: TimeZone, destination: TimeZone) -> Int {
        dayOffset(from: date, in: home, to: date, in: destination)
    }
}

// MARK: - Timeline planning

nonisolated enum WidgetTimelinePlanner {

    /// Ticking countdowns start this long before their target. Further out,
    /// widgets show the weekday and time instead, which is both more useful
    /// ("Tue 9:05 AM" beats "62:14:09") and needs no refreshing.
    static let countdownWindow: TimeInterval = 12 * 3_600

    /// How far ahead a timeline plans. The policy reloads at its end.
    static let horizon: TimeInterval = 48 * 3_600

    nonisolated enum MomentKind: String, Sendable {
        case checkInOpens, leaveBy, leaveByBecomesEstimate, leaveByExpires
        case countdownStarts, boarding, departure, arrival
        case itemStarts, tripStarts, tripEnds, midnight
    }

    nonisolated struct Moment: Equatable, Sendable {
        let date: Date
        let kind: MomentKind
    }

    // MARK: What to show

    /// The flight a widget shows at `date`: the earliest one that hasn't
    /// landed yet. A flight without a scheduled arrival drops off at its
    /// departure, because without live status we can't say it's in the air.
    static func currentFlight(in flights: [WidgetSnapshot.FlightLeg], at date: Date) -> WidgetSnapshot.FlightLeg? {
        flights.filter { $0.endsAt > date }.min { $0.departure < $1.departure }
    }

    /// The leave-by to show alongside `flight` at `date`: only one computed
    /// for that flight, not yet expired, and only before departure.
    static func leaveBy(
        _ leaveBy: WidgetSnapshot.LeaveBy?,
        for flight: WidgetSnapshot.FlightLeg?,
        at date: Date
    ) -> WidgetSnapshot.LeaveBy? {
        guard let leaveBy, let flight, leaveBy.flightID == flight.id,
              date < leaveBy.expiresAt, date < flight.departure
        else { return nil }
        return leaveBy
    }

    // MARK: When it changes

    /// The moments at which a widget showing `flight` looks different, sorted.
    /// Not filtered against "now"; `entryDates` does that.
    static func moments(for flight: WidgetSnapshot.FlightLeg, leaveBy: WidgetSnapshot.LeaveBy?) -> [Moment] {
        var moments: [Moment] = []
        if let opens = flight.checkInOpensAt {
            moments.append(Moment(date: opens, kind: .checkInOpens))
        }
        if let leaveBy, leaveBy.flightID == flight.id {
            moments.append(Moment(date: leaveBy.leaveAt, kind: .leaveBy))
            // After departure the leave-by is hidden anyway, so its later
            // changes don't need entries.
            let becomesEstimate = leaveBy.computedAt.addingTimeInterval(WidgetSnapshot.LeaveBy.liveReadingLifetime)
            if leaveBy.usesLiveTraffic, becomesEstimate < flight.departure {
                moments.append(Moment(date: becomesEstimate, kind: .leaveByBecomesEstimate))
            }
            if leaveBy.expiresAt < flight.departure {
                moments.append(Moment(date: leaveBy.expiresAt, kind: .leaveByExpires))
            }
        }
        moments.append(Moment(date: flight.departure.addingTimeInterval(-countdownWindow), kind: .countdownStarts))
        if let boarding = flight.boardingEstimate {
            moments.append(Moment(date: boarding, kind: .boarding))
        }
        moments.append(Moment(date: flight.departure, kind: .departure))
        if let arrival = flight.arrival {
            // A long-haul's arrival countdown starts mid-flight.
            let arrivalCountdown = arrival.addingTimeInterval(-countdownWindow)
            if arrivalCountdown > flight.departure {
                moments.append(Moment(date: arrivalCountdown, kind: .countdownStarts))
            }
            moments.append(Moment(date: arrival, kind: .arrival))
        }
        return moments.sorted { $0.date < $1.date }
    }

    /// Every date a timeline needs an entry for: `now` first, then each moment
    /// within `horizon`, sorted and without duplicates.
    ///
    /// `tripID` scopes the flights and trips to one configured trip (nil means
    /// automatic). `calendar` supplies the device's zone for "today"; midnight
    /// is also added in the home and destination zones, where the clock
    /// widget's day badge changes.
    static func entryDates(
        for snapshot: WidgetSnapshot?,
        tripID: UUID?,
        now: Date,
        calendar: Calendar,
        horizon: TimeInterval = horizon
    ) -> [Date] {
        guard let snapshot, !snapshot.trips.isEmpty else { return [now] }
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]

        for flight in snapshot.flights(forTrip: tripID) {
            for moment in moments(for: flight, leaveBy: snapshot.leaveBy) {
                dates.insert(moment.date)
            }
        }

        let scopedTrips = snapshot.trips.filter { $0.id == tripID }
        let trips = scopedTrips.isEmpty ? snapshot.trips : scopedTrips
        for trip in trips {
            dates.insert(trip.startDate)
            dates.insert(trip.endDate)
            for item in trip.items { dates.insert(item.start) }
        }

        var zones = [calendar.timeZone]
        if let home = WidgetClock.zone(snapshot.homeTimeZoneID) { zones.append(home) }
        zones += trips.compactMap { WidgetClock.zone($0.destinationTimeZoneID) }
        for zone in zones {
            for midnight in midnights(after: now, through: end, in: zone, calendar: calendar) {
                dates.insert(midnight)
            }
        }

        return dates.filter { $0 >= now && $0 <= end }.sorted()
    }

    /// Extra entries for widgets whose countdown is plain text rather than a
    /// ticking timer (inline and circular Lock Screen widgets): every 5
    /// minutes in the last 2 hours, every 10 up to 6 hours, every 20 up to the
    /// 12-hour countdown window. Anchored on `target` so each lands on a round
    /// remaining time.
    static func countdownRefreshDates(until target: Date, after now: Date) -> [Date] {
        let bands: [(within: TimeInterval, every: TimeInterval)] = [
            (2 * 3_600, 5 * 60),
            (6 * 3_600, 10 * 60),
            (countdownWindow, 20 * 60)
        ]
        var dates: [Date] = []
        var offset: TimeInterval = 0
        for band in bands {
            while offset + band.every <= band.within {
                offset += band.every
                let date = target.addingTimeInterval(-offset)
                if date > now { dates.append(date) }
            }
        }
        return dates.sorted()
    }

    private static func midnights(after start: Date, through end: Date, in zone: TimeZone, calendar: Calendar) -> [Date] {
        var zoned = calendar
        zoned.timeZone = zone
        var result: [Date] = []
        var cursor = start
        // `.nextTime` handles zones where a DST change skips midnight itself.
        while let next = zoned.nextDate(after: cursor, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                        matchingPolicy: .nextTime),
              next <= end {
            result.append(next)
            cursor = next
        }
        return result
    }
}
