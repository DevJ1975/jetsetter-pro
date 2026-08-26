// File: NextTripWidget.swift
//
// Home Screen widget showing the active/next trip with a countdown. Reads a tiny
// snapshot the app publishes to the shared App Group UserDefaults (written by
// `WidgetBridge` in the app target). The App Group id + key must match
// `WidgetBridge` exactly.

import WidgetKit
import SwiftUI

// Kept in sync with WidgetBridge in the app target (decoupled so this target
// doesn't compile TravelStore/SwiftData).
private let appGroupID = "group.DevJ.JetSetter-Pro"
private let nextTripKey = "jetsetter_next_trip_snapshot"

private struct NextTripSnapshot: Codable {
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
}

private struct NextTripEntry: TimelineEntry {
    let date: Date
    let trip: NextTripSnapshot?
}

private struct NextTripProvider: TimelineProvider {
    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    private func load() -> NextTripSnapshot? {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard let data = defaults.data(forKey: nextTripKey) else { return nil }
        return try? decoder.decode(NextTripSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> NextTripEntry {
        NextTripEntry(date: Date(), trip: NextTripSnapshot(
            name: "Tokyo Product Summit", destination: "Tokyo, Japan",
            startDate: Date().addingTimeInterval(86_400 * 12),
            endDate: Date().addingTimeInterval(86_400 * 18)))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextTripEntry) -> Void) {
        completion(NextTripEntry(date: Date(), trip: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTripEntry>) -> Void) {
        // Refresh at next midnight; the app force-reloads immediately on trip changes.
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0),
                                             matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [NextTripEntry(date: Date(), trip: load())], policy: .after(next)))
    }
}

private struct NextTripView: View {
    var entry: NextTripEntry
    private let accent = Color(red: 59/255, green: 158/255, blue: 240/255) // #3B9EF0

    var body: some View {
        if let trip = entry.trip {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "airplane.departure").font(.caption2)
                    Text("NEXT TRIP").font(.system(size: 10, weight: .black)).tracking(1.5)
                }
                .foregroundStyle(accent)
                Text(trip.name).font(.headline).lineLimit(2)
                Text(trip.destination).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(trip.startDate, style: .relative).font(.caption).foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "airplane").foregroundStyle(.secondary)
                Text("No upcoming trips").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTripWidget", provider: NextTripProvider()) { entry in
            NextTripView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Trip")
        .description("Your active or upcoming trip with a countdown.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
