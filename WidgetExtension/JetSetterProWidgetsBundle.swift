// File: JetSetterProWidgetsBundle.swift
//
// @main entry for the "JetSetter Pro Widgets" extension target. Registers both
// the Flight Live Activity and the Home Screen "Next Trip" widget.
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
    }
}
