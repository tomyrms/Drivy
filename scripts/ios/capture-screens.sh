#!/usr/bin/env bash
set -euo pipefail
# Capture the actual app compositor, not UIKit drawHierarchy around MapKit.
# The explicit harness is compiled only in DEBUG simulator builds and uses an
# isolated encrypted database with synthetic coordinates. No school API/login.
app=artifacts/ios/DerivedData/Build/Products/Debug-iphonesimulator/Drivy.app
[[ -d "$app" ]]
for kind in iPhone iPad; do
  device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
kind=sys.argv[1]
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith(kind)]
if not candidates: raise SystemExit("Aucun simulateur disponible")
print(candidates[0]["udid"])
' "$kind")
  xcrun simctl boot "$device_id" || true
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl status_bar "$device_id" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl install "$device_id" "$app"
  for appearance in light dark; do
    xcrun simctl ui "$device_id" appearance "$appearance"
    for screen in home live report without-gps replay; do
      xcrun simctl terminate "$device_id" ch.drivy.qualification 2>/dev/null || true
      SIMCTL_CHILD_DRIVY_VISUAL_SCREEN="$screen" xcrun simctl launch "$device_id" ch.drivy.qualification
      sleep 5
      xcrun simctl io "$device_id" screenshot "artifacts/ios/${kind}-${screen}-${appearance}-synthetic.png"
    done
  done
  xcrun simctl shutdown "$device_id"
done
