// File: FlightLiveActivityWidget.swift
//
// Live Activity UI (Lock Screen + Dynamic Island) for an active flight. Uses the
// SHARED `FlightActivityAttributes` type — that file (Core/Services/
// FlightActivityAttributes.swift) MUST be a member of both the app target and
// this widget target (Xcode: select the file → File Inspector → Target
// Membership → check "JetSetter Pro Widgets"). Matches SETUP-LIVE-ACTIVITY.md §3.

import ActivityKit
import WidgetKit
import SwiftUI

struct FlightLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            FlightLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.flightNumber)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        Text(context.attributes.originIATA + " → " + context.attributes.destinationIATA)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let gate = context.state.gate {
                            Text("Gate \(gate)").font(.system(size: 13, weight: .bold))
                        }
                        Text(context.state.status.label)
                            .font(.caption)
                            .foregroundStyle(context.state.status.isUrgent ? .red : .green)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "airplane")
                        Text(context.state.estimatedDeparture, style: .relative).font(.caption)
                        Spacer()
                        if let mins = context.state.delayMinutes, mins > 0 {
                            Text("+\(mins)m delay").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "airplane")
            } compactTrailing: {
                Text(context.state.estimatedDeparture, style: .timer).font(.caption2.monospaced())
            } minimal: {
                Image(systemName: "airplane")
            }
        }
    }
}

private struct FlightLockScreenView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.flightNumber)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(context.attributes.airlineName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            HStack(spacing: 6) {
                Text(context.attributes.originIATA)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Image(systemName: "airplane")
                Text(context.attributes.destinationIATA)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.white)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let gate = context.state.gate {
                    Text("Gate \(gate)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                Text(context.state.status.label.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(context.state.status.isUrgent ? .red : .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
