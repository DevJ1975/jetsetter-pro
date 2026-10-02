// File: WidgetExtension/TripWidgetConfiguration.swift
//
// The "Trip" option on the Next Flight and Trip Day widgets: follow the next
// trip automatically (the default), or pin one trip, say next week's
// conference, while a different trip is under way.
//
// The choices come from the shared `WidgetSnapshot`, read inside the widget
// process, so editing a widget never has to launch the app. A pinned trip
// that has since ended or been deleted is no longer in the snapshot; the
// widget then quietly follows the next trip instead of showing nothing.

import AppIntents
import WidgetKit

struct TripChoiceEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trip")
    static var defaultQuery = TripChoiceQuery()

    static let automaticID = "automatic"
    static let automatic = TripChoiceEntity(
        id: automaticID,
        name: "Next trip (automatic)",
        detail: "Follows your active or next trip"
    )

    /// A trip's UUID string, or `automaticID`.
    let id: String
    let name: String
    let detail: String?

    var displayRepresentation: DisplayRepresentation {
        if let detail {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    /// The pinned trip's id; nil for the automatic choice.
    var tripID: UUID? { UUID(uuidString: id) }

    init(id: String, name: String, detail: String?) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    init(_ trip: WidgetSnapshot.TripSummary) {
        let dates = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        self.init(
            id: trip.id.uuidString,
            name: trip.name,
            detail: trip.destination.isEmpty ? dates : "\(trip.destination) · \(dates)"
        )
    }
}

struct TripChoiceQuery: EntityQuery {

    func entities(for identifiers: [TripChoiceEntity.ID]) async throws -> [TripChoiceEntity] {
        let choices = Self.choices()
        return identifiers.compactMap { id in choices.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [TripChoiceEntity] {
        Self.choices()
    }

    func defaultResult() async -> TripChoiceEntity? {
        .automatic
    }

    /// "Next trip (automatic)" first, then up to three trips from the snapshot.
    private static func choices() -> [TripChoiceEntity] {
        let trips = WidgetSnapshotStore.load(from: WidgetSnapshotStore.sharedDefaults())?.trips ?? []
        return [.automatic] + trips.map(TripChoiceEntity.init)
    }
}

struct TripWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Trip"
    static var description = IntentDescription("Follow your next trip automatically, or pin one trip.")

    @Parameter(title: "Trip")
    var trip: TripChoiceEntity?

    /// Nil follows the active-or-next trip.
    var tripID: UUID? { trip?.tripID }
}
