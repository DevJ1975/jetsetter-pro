// File: Core/Services/NotificationManager.swift
//
// Schedules the app's local notifications and is the notification center's
// delegate. Taps and action buttons are decided by `NotificationRouting` (pure,
// tested) and applied through `AppRouter`, so a tap that cold-launches the app
// still reaches its screen. Alert sounds come from `AnnouncementCenter`, which
// applies the traveler's Voice Announcements setting; interruption levels come
// from `TravelAlertKind`.

import UserNotifications
import SwiftUI
import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()
    private override init() { super.init() }

    /// Registers the action buttons for every category. Call once at launch,
    /// before any notification can be shown, alongside setting the delegate.
    func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(NotificationRouting.categories())
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Foreground presentation — show banner + sound + badge even when the app is foregrounded.
    /// Without this, iOS silently drops notifications while the app is open, which would hide
    /// disruption alerts that the user needs to see immediately. The system plays the
    /// notification's own sound (the spoken announcement when that's the setting), so nothing
    /// here calls `AnnouncementCenter.play` as well; that would say it twice.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Tap and action-button routing. The decision is made here, off the main actor, from
    /// the response's plain values; only the resulting `NotificationRoute` (Sendable) crosses
    /// to the main actor, where `AppRouter` holds it until the destination screen consumes it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let route = NotificationRouting.route(
            category: request.content.categoryIdentifier,
            action: response.actionIdentifier,
            requestIdentifier: request.identifier,
            userInfo: request.content.userInfo
        )

        // Snooze runs in the background without opening the app: re-add the same
        // alert, then tell the system we're done.
        if case .snooze(let minutes) = route {
            guard let snoozed = NotificationRouting.snoozedRequest(from: request, minutes: minutes) else {
                completionHandler()
                return
            }
            UNUserNotificationCenter.current().add(snoozed) { _ in completionHandler() }
            return
        }

        Task { @MainActor in
            NotificationManager.shared.perform(route)
            completionHandler()
        }
    }

    /// Applies a route. In-app navigation is the router's; the effects outside
    /// the app (a ride app, Messages) are handled here.
    func perform(_ route: NotificationRoute) {
        switch route {
        case .ride(let airport):
            if let url = NotificationRouting.rideURL(toAirport: airport) {
                // Rests Home's "pre-book your ride" nudge, as opening a ride from
                // Ground Transport does.
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: GroundTransportViewModel.rideOpenedAtKey)
                UIApplication.shared.open(url)
            } else {
                AppRouter.shared.open(.groundTransport)
            }
        case .lovedOnes(let recipients, let body):
            // Tapping the prompt opens a pre-filled Messages composer.
            LovedOnesMessenger.shared.presentComposer(recipients: recipients, body: body)
        default:
            AppRouter.shared.handle(route)
        }
    }

    @Published var isAuthorized = false

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            // If permission was just granted, schedule reminders for any trips
            // that already exist. Users commonly add trips first and enable
            // notifications later — without this, no `.jetSetterTripsChanged`
            // fires afterward, so nothing would be scheduled until the next edit.
            if granted {
                await TravelNotificationScheduler.shared.rescheduleAll()
            }
        } catch {
            isAuthorized = false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Resolves permission right before something is scheduled: asks once if
    /// the user has never been prompted, otherwise reports the current state.
    /// Schedulers call this so a reminder is never silently dropped on a fresh
    /// install that hasn't saved a trip yet.
    func ensureAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            await requestAuthorization()
            return isAuthorized
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
            return true
        default:
            isAuthorized = false
            return false
        }
    }

    // MARK: - Flight Alerts

    /// Schedules the "time to head to the airport" alert 2 hours before departure.
    ///
    /// Time-sensitive, with the spoken time-to-leave announcement and
    /// "Snooze 10 min" (LEAVE_BY_ALERT). The departure time in the body is the
    /// wall-clock time at the origin airport, not the phone's: a traveler whose
    /// phone is still on home time must read the time on the departures board.
    /// It fires at a fixed instant, so a time-zone change before it fires can't
    /// move it (a calendar trigger would re-read its components in the new zone).
    func scheduleFlightDepartureAlert(
        flightNumber: String,
        departureTime: Date,
        airportName: String,
        originIATA: String? = nil
    ) async {
        guard isAuthorized else { return }
        let fireDate = departureTime.addingTimeInterval(-2 * 3600)
        guard fireDate > Date() else { return }

        let departs = AppDateFormatters.airportTime(departureTime, iata: originIATA, style: .time)
        let content = UNMutableNotificationContent()
        content.title = "Flight \(flightNumber) in 2 hours"
        content.body = "Departs \(airportName) at \(departs). Time to head to the airport."
        content.sound = await AnnouncementCenter.sound(for: .timeToLeave, firesAt: fireDate)
        content.interruptionLevel = TravelAlertKind.leaveNow.interruptionLevel
        content.categoryIdentifier = NotificationRouting.Category.leaveByAlert
        var info: [String: Any] = [
            NotificationRouting.Key.flightNumber: flightNumber,
            NotificationRouting.Key.departure: departureTime.timeIntervalSince1970,
            NotificationRouting.Key.alertType: TravelAlertKind.leaveNow.rawValue
        ]
        if let originIATA, !originIATA.isEmpty { info[NotificationRouting.Key.rideAirport] = originIATA }
        content.userInfo = info

        // Measured after the sound is composed, which can take a moment.
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "flight_\(flightNumber)_\(Int(departureTime.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedules the boarding reminder 30 minutes before `boardingTime`.
    ///
    /// Time-sensitive, with the boarding chime and the spoken boarding-soon
    /// announcement naming the gate. FLIGHT_ALERT, so it offers "View boarding
    /// pass", and a plain tap opens the pass too.
    func scheduleGateReminder(flightNumber: String, boardingTime: Date, gate: String) async {
        guard isAuthorized else { return }
        let fireDate = boardingTime.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Boarding starts in 30 min — Gate \(gate)"
        content.body = "Flight \(flightNumber) boards at gate \(gate). Make your way now."
        content.sound = await AnnouncementCenter.sound(for: .boardingSoon(gate: gate), firesAt: fireDate)
        content.interruptionLevel = TravelAlertKind.boarding.interruptionLevel
        content.categoryIdentifier = NotificationRouting.Category.flightAlert
        content.userInfo = [
            NotificationRouting.Key.flightNumber: flightNumber,
            NotificationRouting.Key.departure: boardingTime.timeIntervalSince1970,
            NotificationRouting.Key.alertType: TravelAlertKind.boarding.rawValue
        ]

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "gate_\(flightNumber)_\(gate)_\(Int(boardingTime.timeIntervalSince1970))"
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

    /// Cancels every scheduled flight alert (2h-before-departure and gate
    /// reminders) across all flights, leaving trip reminders and the weekly
    /// expense review untouched. Used by the Flight Alerts settings toggle so
    /// disabling one category doesn't wipe the others.
    func cancelFlightAlerts() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending
            .filter { $0.identifier.hasPrefix("flight_") || $0.identifier.hasPrefix("gate_") }
            .map { $0.identifier }
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Loved Ones (takeoff / landing)

    /// Fires an immediate prompt asking the traveler to text their loved ones
    /// about a flight milestone. Tapping it opens a pre-filled Messages composer
    /// (recipients + body live in `userInfo`). No-op when there are no opted-in
    /// contacts for the event. iOS can't send SMS silently, so this is the
    /// native, user-confirmed path.
    func notifyLovedOnes(
        event: LovedOnesEvent,
        flightNumber: String?,
        destinationCity: String?
    ) async {
        guard isAuthorized else { return }
        let contacts = LovedOnesStore.shared.contacts(for: event)
        guard !contacts.isEmpty else { return }

        let body = LovedOnesMessenger.message(
            for: event,
            flightNumber: flightNumber,
            destinationCity: destinationCity
        )
        let names = contacts.map(\.name).joined(separator: ", ")

        let content = UNMutableNotificationContent()
        content.title = event == .takeoff ? "Let your people know you're off" : "Tell your people you've landed"
        content.body = "Tap to text \(names): \"\(body)\""
        content.sound = .default
        content.interruptionLevel = TravelAlertKind.lovedOnes.interruptionLevel
        content.categoryIdentifier = event == .takeoff
            ? NotificationRouting.Category.lovedOnesTakeoff
            : NotificationRouting.Category.lovedOnesLanding
        content.userInfo = [
            NotificationRouting.Key.recipients: contacts.map(\.phoneNumber),
            NotificationRouting.Key.body: body
        ]

        let id = "loved_ones_\(event.rawValue)_\(Int(Date().timeIntervalSince1970))"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    // MARK: - Trip Reminders

    /// Schedules a morning-of notification on the first day of a trip.
    func scheduleTripDayReminder(tripName: String, startDate: Date) async {
        guard isAuthorized else { return }

        var comps = Calendar.current.dateComponents([.year,.month,.day], from: startDate)
        comps.hour = 7
        comps.minute = 30
        // A non-repeating calendar trigger whose components are already in the past
        // is accepted by add() but never delivers. Skip when 7:30am has passed
        // (e.g. a trip that starts later the same day), mirroring the other schedulers.
        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Today's the day — \(tripName)"
        content.body = "Your journey begins today. Open JetSetter Pro to review your itinerary."
        content.sound = .default
        content.interruptionLevel = TravelAlertKind.tripReminder.interruptionLevel

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
        content.interruptionLevel = TravelAlertKind.tripReminder.interruptionLevel

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
        content.interruptionLevel = TravelAlertKind.expenseReminder.interruptionLevel
        content.categoryIdentifier = NotificationRouting.Category.expenseReminder

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "weekly_expense", content: content, trigger: trigger)
        )
    }

    func cancelWeeklyExpenseReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weekly_expense"])
    }

    // MARK: - Cabin chime

    /// The bundled two-tone cabin chime (Resources/Sounds/cabin_chime.caf, in
    /// the app target). Alerts don't use this directly: they ask
    /// `AnnouncementCenter.sound(for:)`, which plays this chime under "Chime
    /// only", puts it before the spoken words under "Chime and voice", and uses
    /// the system sound under "Off". Use it only for a sound that must ignore
    /// the traveler's Voice Announcements setting.
    static var cabinChimeSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName("\(AnnouncementScript.alertChime).caf"))
    }

    #if DEMO_ENABLED
    // MARK: - Demo scripted disruption push (Debug and Beta only)

    static let demoDisruptionIdentifier = "demo_disruption_dl1423"

    /// Fires a scripted DL 1423 weather-hold delay push ~25s after demo mode is
    /// enabled, so a presenter gets the "traveler notified" beat on cue. Uses
    /// the disruption category (routes to the dashboard) and the spoken delay.
    ///
    /// The times are computed from the demo flight's real (relative) departure
    /// in the LAS zone, so the written and spoken times agree with each other
    /// and with the boarding pass. They used to be a fixed "7:00 → 8:35 AM".
    func scheduleDemoDisruptionPush(
        afterSeconds seconds: TimeInterval = 25,
        departure: Date = Date().addingTimeInterval(TimeInterval(DemoDataSeeder.minutesToDeparture * 60)),
        delayMinutes: Int = 95
    ) async {
        guard isAuthorized else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.demoDisruptionIdentifier])

        let origin = DemoDataSeeder.origin
        let newDeparture = departure.addingTimeInterval(TimeInterval(delayMinutes * 60))
        let was = AppDateFormatters.airportTime(departure, iata: origin, style: .time)
        let now = AppDateFormatters.airportTime(newDeparture, iata: origin, style: .time)

        let content = UNMutableNotificationContent()
        content.title = "Delay — DL 1423 to Atlanta"
        content.body  = "Weather hold at ATL. Departure pushed \(was) → \(now). Tap to see same-day alternatives."
        content.sound = await AnnouncementCenter.sound(for: .delay(
            airline: "", flight: DemoDataSeeder.flightNumber, newDeparture: newDeparture,
            timeZone: AppDateFormatters.airportTimeZone(for: origin)
        ))
        content.interruptionLevel = TravelAlertKind.delay.interruptionLevel
        content.categoryIdentifier = NotificationRouting.Category.disruptionAlert
        content.userInfo = [
            NotificationRouting.Key.legacyFlightNumber: DemoDataSeeder.flightNumber,
            NotificationRouting.Key.flightNumber: DemoDataSeeder.flightNumber,
            NotificationRouting.Key.alertType: DisruptionType.majorDelay.rawValue,
            "disruption_type": DisruptionType.majorDelay.rawValue
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.demoDisruptionIdentifier,
                                  content: content, trigger: trigger)
        )
    }
    #endif

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
