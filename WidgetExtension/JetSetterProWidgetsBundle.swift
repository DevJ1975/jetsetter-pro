// File: JetSetterProWidgetsBundle.swift
//
// @main entry for the "JetSetter Pro Widgets" extension target. Registers the
// Flight Live Activity, the Home Screen / Lock Screen / StandBy widgets (Next
// Trip, Next Flight, Leave By, Trip Day, Destination Clock) and the Boarding
// Pass control for Control Center, the Lock Screen and the Action button.
//
// SETUP (see WidgetExtension/README.md): these files belong to the Widget
// Extension target you create in Xcode — NOT the app target.

import WidgetKit
import SwiftUI

@main
struct JetSetterProWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivityWidget()
        NextTripWidget()
        NextFlightWidget()
        LeaveByWidget()
        TripDayWidget()
        DestinationClockWidget()
        BoardingPassControl()
    }
}
