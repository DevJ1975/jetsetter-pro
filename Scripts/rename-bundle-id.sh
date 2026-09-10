#!/bin/sh
# Renames the app's bundle identifier everywhere it is baked in: the project
# file, both entitlements files, the widget's App Group, the StoreKit product
# IDs, and the docs. Run once, before the first TestFlight upload.
#
#   Scripts/rename-bundle-id.sh com.trainovations.jetsetterpro
#
# Afterwards: register the new App ID (with App Groups, WeatherKit, Time
# Sensitive Notifications, Background Modes, In-App Purchase) in the developer
# portal, and create the subscription products with the new IDs in App Store
# Connect.
set -eu
NEW="${1:?usage: rename-bundle-id.sh <new.bundle.id>}"
OLD="DevJ.JetSetter-Pro"
cd "$(dirname "$0")/.."
case "$NEW" in *[!A-Za-z0-9.-]*) echo "bundle id may only contain letters, digits, dots and hyphens" >&2; exit 1;; esac

files="JetSetter Pro.xcodeproj/project.pbxproj
JetSetter Pro/JetSetter Pro.entitlements
JetSetter Pro/JetSetter Pro/JetSetterPro.entitlements
WidgetExtension/JetSetterProWidgets.entitlements
WidgetExtension/NextTripWidget.swift
WidgetExtension/README.md
JetSetter Pro/Core/Services/Persistence/WidgetBridge.swift
JetSetter Pro/Core/Services/SubscriptionManager.swift
Config/Products.storekit
SETUP.md
SETUP-WATCH.md
docs/HANDOFF.md"

printf '%s\n' "$files" | while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -q "$OLD" "$f"; then
    sed -i '' "s/$OLD/$NEW/g" "$f"
    echo "updated  $f"
  fi
done
echo
echo "Bundle id is now $NEW. App Group: group.$NEW. Products: $NEW.subscription.pro.monthly / .annual."
