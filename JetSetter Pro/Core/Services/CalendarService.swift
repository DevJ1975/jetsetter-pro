// File: Core/Services/CalendarService.swift

import Foundation
import EventKit

// MARK: - Calendar Error

enum CalendarError: LocalizedError {
    case accessDenied
    case accessRestricted
    case eventSaveFailed(Error)
    case eventRemoveFailed(Error)
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Please enable it in Settings > Privacy > Calendars."
        case .accessRestricted:
            return "Calendar access is restricted on this device."
        case .eventSaveFailed(let error):
            return "Failed to save the event: \(error.localizedDescription)"
        case .eventRemoveFailed(let error):
            return "Failed to remove the event: \(error.localizedDescription)"
        case .eventNotFound:
            return "The calendar event could not be found."
        }
    }
}

// MARK: - CalendarService

/// Wraps EventKit to request calendar access and add/remove events.
/// All methods are async/await and throw typed CalendarErrors.
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Request Access

    /// Requests full-access calendar permission from the user.
    /// Returns true if access was granted, throws if denied or restricted.
    func requestAccess() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            if !granted { throw CalendarError.accessDenied }
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if !granted {
                        continuation.resume(throwing: CalendarError.accessDenied)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Authorization Check

    /// Returns true if the app already has calendar access (no prompt shown).
    var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    // MARK: - Add Event

    /// Creates a calendar event from an ItineraryItem and saves it to the default calendar.
    /// Returns the EventKit event identifier, which should be stored on the ItineraryItem.
    @discardableResult
    func addEvent(for item: ItineraryItem) async throws -> String {
        if !isAuthorized { try await requestAccess() }

        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.startDate = item.startDate
        // Use endDate if provided, otherwise make a 1-hour event
        event.endDate = item.endDate ?? item.startDate.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents

        if let location = item.location {
            event.location = location
        }
        if let notes = item.notes {
            event.notes = notes
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            throw CalendarError.eventSaveFailed(error)
        }
    }

    // MARK: - Remove Event

    /// Removes a previously synced calendar event by its EventKit identifier.
    func removeEvent(identifier: String) async throws {
        if !isAuthorized { try await requestAccess() }

        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw CalendarError.eventNotFound
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            throw CalendarError.eventRemoveFailed(error)
        }
    }
}
