#!/bin/bash
# File: Scripts/simulator-preview.sh
#
# Installs a Debug simulator build of JetSetter Pro, loads the demo trip
# (LAS → ATL on DL1423, 75 minutes out), and captures screenshots of the main
# screens, the Dynamic Island, and a short walkthrough video. Used by
# .github/workflows/simulator-preview.yml; runs on any Mac with Xcode too:
#
#   xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
#     -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
#     -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
#   Scripts/simulator-preview.sh
#
# Screens are opened with the demo-only `-demoScreen <name>` launch argument
# (Core/Services/Demo/DemoScreen.swift), so no UI-test target is needed.

set -uo pipefail

BUNDLE_ID="DevJ.JetSetter-Pro"
OUT="${OUT:-preview}"
APP="${APP:-$(find build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' | head -1)}"
LAS_LAT_LON="36.0840,-115.1537"   # Harry Reid International, so leave-by is realistic
LAUNCH_WAIT="${LAUNCH_WAIT:-10}"    # splash + demo seeding + first weather fetch

mkdir -p "$OUT"
[ -d "$APP" ] || { echo "No simulator .app found (APP=$APP). Build first."; exit 1; }
echo "App: $APP"

# Newest iOS runtime's UDID for a device name, or empty.
udid_for() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"] == name:
            print(d["udid"]); sys.exit()
' "$1"
}

prepare() {
  local udid="$1"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$APP"
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork 5g \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 || true
  xcrun simctl location "$udid" set "$LAS_LAT_LON" || true
  for service in location motion photos-add; do
    xcrun simctl privacy "$udid" grant "$service" "$BUNDLE_ID" || true
  done
}

# shot <udid> <file-name> <demo-screen> [wait-seconds]
shot() {
  local udid="$1" name="$2" screen="$3" wait="${4:-$LAUNCH_WAIT}"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -seedDemoData -demoScreen "$screen" >/dev/null
  sleep "$wait"
  xcrun simctl io "$udid" screenshot "$OUT/$name.png" >/dev/null && echo "  ✓ $name"
}

# ---------------------------------------------------------------- iPhone
PHONE_NAME="${PHONE_NAME:-iPhone 18 Pro}"
PHONE="$(udid_for "$PHONE_NAME")"
[ -n "$PHONE" ] || { echo "No '$PHONE_NAME' simulator available."; xcrun simctl list devices available; exit 1; }
echo "iPhone: $PHONE_NAME ($PHONE)"
prepare "$PHONE"

for appearance in light dark; do
  xcrun simctl ui "$PHONE" appearance "$appearance"
  echo "$appearance mode"
  shot "$PHONE" "iphone-$appearance-01-home"           home
  shot "$PHONE" "iphone-$appearance-02-boarding-pass"  boardingPass
  shot "$PHONE" "iphone-$appearance-03-wallet"         wallet
  shot "$PHONE" "iphone-$appearance-04-itinerary"      itinerary
  if [ "$appearance" = light ]; then
    shot "$PHONE" "iphone-$appearance-05-expenses"        expenses
    shot "$PHONE" "iphone-$appearance-06-more"            more
    shot "$PHONE" "iphone-$appearance-07-flight-tracker"  flightTracker
    shot "$PHONE" "iphone-$appearance-08-disruption"      disruption
    shot "$PHONE" "iphone-$appearance-09-packing-list"    packingList
    shot "$PHONE" "iphone-$appearance-10-document-vault"  documentVault
    shot "$PHONE" "iphone-$appearance-11-siri"            assistant
  fi
done

# Dynamic Island: the demo trip starts the flight Live Activity. Send the app
# to the background (open Settings) so the island shows it.
xcrun simctl ui "$PHONE" appearance light
shot "$PHONE" "iphone-light-00-launch" home
xcrun simctl launch "$PHONE" com.apple.Preferences >/dev/null || true
sleep 4
xcrun simctl io "$PHONE" screenshot "$OUT/iphone-light-12-dynamic-island.png" >/dev/null && echo "  ✓ dynamic island"

# Walkthrough video: Home → Wallet → Itinerary → flight card → island.
echo "Recording walkthrough"
xcrun simctl terminate "$PHONE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl io "$PHONE" recordVideo --codec h264 --force "$OUT/iphone-walkthrough.mp4" &
REC=$!
sleep 2
xcrun simctl launch "$PHONE" "$BUNDLE_ID" -seedDemoData >/dev/null
sleep "$LAUNCH_WAIT"
xcrun simctl openurl "$PHONE" "jetsetterpro://wallet";  sleep 4
xcrun simctl openurl "$PHONE" "jetsetterpro://trip/00000000-0000-0000-0000-000000000000"; sleep 4
xcrun simctl openurl "$PHONE" "jetsetterpro://flight/DL1423"; sleep 5
xcrun simctl launch "$PHONE" com.apple.Preferences >/dev/null || true; sleep 5
kill -INT "$REC"; wait "$REC" 2>/dev/null || true
echo "  ✓ walkthrough video"

# ---------------------------------------------------------------- iPad mini
# Regular width in both directions, the closest simulator to the foldable
# iPhone Ultra's inner display.
WIDE="$(udid_for "${WIDE_NAME:-iPad mini (A17 Pro)}")"
if [ -n "$WIDE" ]; then
  echo "Wide screen: iPad mini ($WIDE)"
  prepare "$WIDE"
  xcrun simctl ui "$WIDE" appearance light
  shot "$WIDE" "wide-01-home"   home
  shot "$WIDE" "wide-02-more"   more
  shot "$WIDE" "wide-03-wallet" wallet
else
  echo "No iPad mini simulator; skipping wide-screen shots."
fi

# The build itself, so it can be dragged onto any Apple Silicon Mac's Simulator.
ditto -c -k --keepParent "$APP" "$OUT/JetSetterPro-Simulator.app.zip"
echo "Done: $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
