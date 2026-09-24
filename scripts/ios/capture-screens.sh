#!/usr/bin/env bash
set -euo pipefail
# Render actual SwiftUI views with synthetic data using the existing screenshot host.
# This is a visual review, not the functional simulator campaign.
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
  xcodebuild test-without-building -project apps/ios/Drivy.xcodeproj -scheme Drivy \
    -destination "platform=iOS Simulator,id=$device_id" -parallel-testing-enabled NO \
    -derivedDataPath artifacts/ios/DerivedData -resultBundlePath "artifacts/ios/${kind}Visual.xcresult" \
    -only-testing:DrivyTests/SchoolPresentationTests/testNativeSchoolViewsWithSyntheticServerResponses \
    2>&1 | tee "artifacts/ios/${kind}-visual-test.log"
  xcrun simctl shutdown "$device_id"
done
