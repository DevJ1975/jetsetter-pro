# Widget Extension — final wiring (Xcode, ~5 min)

The app side is already done and shipped (commit `3208566`): `WidgetBridge`
publishes a `NextTripSnapshot` to the App Group and reloads the widget timeline
on every trip change. All the widget source lives here, ready to drop in. The
only remaining steps require Xcode's GUI (creating a target and toggling a file's
target membership can't be done safely by hand-editing the objectVersion-77
synchronized-folder `project.pbxproj`).

## 1. Create the target
File → New → Target → **Widget Extension**
- Product Name: **JetSetter Pro Widgets**
- Include Live Activity: ✅
- Include Configuration Intent: ✗
- Finish → Activate.

## 2. Replace the generated sources with these
Delete the sample files Xcode created in the new target and add the files from
this folder to the **JetSetter Pro Widgets** target:
- `JetSetterProWidgetsBundle.swift`  (the `@main` bundle — replaces the sample bundle)
- `FlightLiveActivityWidget.swift`   (Lock Screen + Dynamic Island)
- `NextTripWidget.swift`             (Home Screen widget)

(You can drag them into the target's group, or move them into the target's
folder and ensure Target Membership = JetSetter Pro Widgets.)

## 3. Share the ActivityKit attributes with BOTH targets
Select `JetSetter Pro/Core/Services/FlightActivityAttributes.swift` →
File Inspector → **Target Membership** → check **JetSetter Pro Widgets** (leave
the app checked too). This is what a hand-edited pbxproj can't do reliably — the
app and widget must compile the *same* `FlightActivityAttributes` type or the
Live Activity won't match.

## 4. App Group (for the Next Trip widget's shared data)
Add capability **App Groups → `group.DevJ.JetSetter-Pro`** to BOTH:
- the **JetSetter Pro** app target, and
- the **JetSetter Pro Widgets** target.
An entitlements file for the widget is provided here
(`JetSetterProWidgets.entitlements`) — either point the widget target's
`CODE_SIGN_ENTITLEMENTS` at it, or just use the capability UI (which writes its
own). The id must be exactly `group.DevJ.JetSetter-Pro` to match `WidgetBridge`.

## 5. Info.plist
The provided `Info.plist` sets `NSSupportsLiveActivities = YES` and the WidgetKit
extension point. If you let Xcode generate the Info.plist instead, add
`NSSupportsLiveActivities = YES` to it.

## Verify
- Build the app (the extension builds + embeds).
- Add the **Next Trip** widget to the Home Screen → shows the active/next trip;
  add/change a trip in the app → widget updates within a few seconds.
- Trigger `FlightLiveActivityService.shared.start(...)` → Dynamic Island / Lock
  Screen render on a Live-Activity-capable simulator or device.
