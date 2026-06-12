# Live Activity Setup

The iOS app side is wired:
- `FlightActivityAttributes` and `FlightActivityState` define the shared payload (in `Core/Services/FlightLiveActivityService.swift`).
- `FlightLiveActivityService.shared` exposes `start(...)`, `update(...)`, and `end()`. Currently safe to call but no UI will render until the Widget Extension is added.

This guide covers the Widget Extension target you need to add (~5 min).

## 1. Add the Widget Extension target

1. **File → New → Target…**
2. Choose **Widget Extension**. Click Next.
3. Configure:
   - **Product Name:** `JetSetter Pro Widgets`
   - **Include Live Activity:** ✅ check this
   - **Include Configuration Intent:** unchecked
4. Click **Finish**, then **Activate** when prompted.

Xcode generates a sample `JetSetter_Pro_WidgetsLiveActivity.swift` in the new target.

## 2. Share the attributes file

Open the **JetSetter Pro Widgets** target → Build Phases → Compile Sources → add `Core/Services/FlightLiveActivityService.swift` (or just the attribute struct file if you split it out). The same Swift file can be in both targets — the `ActivityKit` import works in both.

## 3. Replace the auto-generated Live Activity UI

In the widget extension, replace `JetSetter_Pro_WidgetsLiveActivity.swift` with:

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct FlightLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            FlightLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
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
                            Text("Gate \(gate)")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(context.state.status.label)
                            .font(.caption)
                            .foregroundStyle(context.state.status.isUrgent ? .red : .green)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "airplane")
                        Text(context.state.estimatedDeparture, style: .relative)
                            .font(.caption)
                        Spacer()
                        if let mins = context.state.delayMinutes, mins > 0 {
                            Text("+\(mins)m delay")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "airplane")
            } compactTrailing: {
                Text(context.state.estimatedDeparture, style: .timer)
                    .font(.caption2.monospaced())
            } minimal: {
                Image(systemName: "airplane")
            }
        }
    }
}

// Lock Screen
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
                    Text("Gate \(gate)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
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

// Register in the Widget Bundle (already created by Xcode)
@main
struct JetSetterProWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlightLiveActivityWidget()
    }
}
```

## 4. Enable Live Activities in Info.plist

The auto-generated widget extension already has `NSSupportsLiveActivities = YES`. Verify on the **JetSetter Pro** app target's Build Settings → add a User-Defined Setting:
- `INFOPLIST_KEY_NSSupportsLiveActivities` = `YES`

## 5. Trigger a Live Activity from the app

Already wired in the main app via `FlightLiveActivityService.shared`. To start one from anywhere (e.g., when DisruptionMonitorService sees a day-of flight):

```swift
FlightLiveActivityService.shared.start(
    flightNumber: "AA169",
    airline: "American",
    originIATA: "JFK",
    destinationIATA: "NRT",
    scheduledDeparture: trip.startDate,
    gate: "B22",
    terminal: "8",
    initialStatus: .onTime
)
```

To update gate or status:

```swift
FlightLiveActivityService.shared.update(
    gate: "B14",   // gate changed
    status: .boarding,
    estimatedDeparture: trip.startDate
)
```

To dismiss after departure:

```swift
FlightLiveActivityService.shared.end()
```

## 6. Recommended integration

In `DisruptionMonitorService.processDisruption(...)`, after persisting the disruption event, call `FlightLiveActivityService.shared.update(...)` with the new state. Start the activity when a flight enters its 8-hour-before-departure window.
