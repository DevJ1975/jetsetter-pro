// File: Core/Services/NotificationManager.swift

import UserNotifications
import SwiftUI
import Combine

@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()
    private init() {}

    @Published var isAuthorized = false

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Flight Alerts

    /// Schedules a push notification 2 hours before departure.
    func scheduleFlightDepartureAlert(
        flightNumber: String,
        departureTime: Date,
        airportName: String
    ) async {
        guard isAuthorized else { return }
        let fireDate = departureTime.addingTimeInterval(-2 * 3600)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Flight \(flightNumber) in 2 hours"
        content.body = "Departs \(airportName) at \(departureTime.formatted(.dateTime.hour().minute())). Time to head to the airport."
        content.sound = .default
        content.categoryIdentifier = "FLIGHT_ALERT"
        content.userInfo = ["flightNumber": flightNumber]

        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "flight_\(flightNumber)_\(Int(departureTime.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedules a push notification 30 minutes before departure (gate reminder).
    func scheduleGateReminder(flightNumber: String, boardingTime: Date, gate: String) async {
        guard isAuthorized else { return }
        let fireDate = boardingTime.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Boarding starts in 30 min — Gate \(gate)"
        content.body = "Flight \(flightNumber) boards at gate \(gate). Make your way now."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("boarding.caf"))

        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "gate_\(flightNumber)_\(gate)"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    func cancelFlightAlerts(flightNumber: String) async {
        // Fetch pending requests and cancel any whose ID starts with this flight's prefix
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending
            .filter {
                $0.identifier.hasPrefix("flight_\(flightNumber)_") ||
                $0.identifier.hasPrefix("gate_\(flightNumber)_")
            }
            .map { $0.identifier }
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Trip Reminders

    /// Schedules a morning-of notification on the first day of a trip.
    func scheduleTripDayReminder(tripName: String, startDate: Date) async {
        guard isAuthorized else { return }

        var comps = Calendar.current.dateComponents([.year,.month,.day], from: startDate)
        comps.hour = 7
        comps.minute = 30

        let content = UNMutableNotificationContent()
        content.title = "Today's the day — \(tripName)"
        content.body = "Your journey begins today. Open JetSetter Pro to review your itinerary."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // Use start date timestamp so two trips with the same name don't collide
        let id = "trip_start_\(Int(startDate.timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// Schedules an evening-before reminder 18 hours before a trip starts.
    func scheduleTripEveReminder(tripName: String, startDate: Date) async {
        guard isAuthorized else { return }
        let fireDate = startDate.addingTimeInterval(-18 * 3600)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Trip tomorrow — \(tripName)"
        content.body = "Your trip starts tomorrow. Check your itinerary and make sure you're packed."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // Use eve fire date timestamp so IDs remain stable and unique per trip
        let id = "trip_eve_\(Int(fireDate.timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    // MARK: - Expense Reminders

    /// Schedules a weekly Sunday evening expense review notification.
    func scheduleWeeklyExpenseReminder() async {
        guard isAuthorized else { return }

        // Remove existing first to avoid duplication
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weekly_expense"])

        var comps = DateComponents()
        comps.weekday = 1   // Sunday
        comps.hour    = 20
        comps.minute  = 0

        let content = UNMutableNotificationContent()
        content.title = "Weekly Expense Review"
        content.body  = "Don't let receipts slip through. Scan and log any expenses from this week."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "weekly_expense", content: content, trigger: trigger)
        )
    }

    func cancelWeeklyExpenseReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weekly_expense"])
    }

    // MARK: - Global Control

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - Pending List (for Settings display)

    func pendingNotifications() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}
