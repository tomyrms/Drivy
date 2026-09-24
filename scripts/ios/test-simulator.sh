#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/ios
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not candidates: raise SystemExit("Aucun simulateur iPhone disponible")
print(candidates[0]["udid"])
')
xcrun simctl boot "$device_id" || true
xcrun simctl bootstatus "$device_id" -b
xcodebuild test-without-building \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination "platform=iOS Simulator,id=$device_id" \
  -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/Tests.xcresult \
  2>&1 | tee artifacts/ios/simulator-test.log
xcrun simctl launch "$device_id" ch.drivy.qualification
sleep 2
xcrun simctl io "$device_id" screenshot artifacts/ios/iphone-light.png
xcrun simctl ui "$device_id" appearance dark
sleep 1
xcrun simctl io "$device_id" screenshot artifacts/ios/iphone-dark.png
ipad_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPad")]
if not candidates: raise SystemExit("Aucun simulateur iPad disponible")
print(candidates[0]["udid"])
')
xcrun simctl shutdown "$device_id"
xcrun simctl boot "$ipad_id" || true
xcrun simctl bootstatus "$ipad_id" -b
xcodebuild test-without-building \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination "platform=iOS Simulator,id=$ipad_id" \
  -only-testing:DrivyUITests -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/iPadTests.xcresult \
  2>&1 | tee artifacts/ios/ipad-test.log
xcrun simctl launch "$ipad_id" ch.drivy.qualification
sleep 2
xcrun simctl io "$ipad_id" screenshot artifacts/ios/ipad-light.png
