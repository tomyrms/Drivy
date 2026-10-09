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
phone_status=0
test_options=()
if [[ "${DRIVY_IOS_UNIT_ONLY:-0}" == 1 ]]; then test_options+=(-only-testing:DrivyTests); fi
xcodebuild test-without-building \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination "platform=iOS Simulator,id=$device_id" \
  -skip-testing:DrivyUITests/VisualOrientationTests \
  "${test_options[@]}" \
  -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/Tests.xcresult \
  2>&1 | tee artifacts/ios/simulator-test.log || phone_status=$?
if [[ "${DRIVY_IOS_UNIT_ONLY:-0}" == 1 ]]; then exit "$phone_status"; fi
xcrun simctl launch "$device_id" ch.drivy.qualification || true
sleep 2
xcrun simctl io "$device_id" screenshot artifacts/ios/iphone-light.png || true
xcrun simctl ui "$device_id" appearance dark
sleep 1
xcrun simctl io "$device_id" screenshot artifacts/ios/iphone-dark.png || true
ipad_id=$(xcrun simctl list devices available -j | python3 -c '
import json,pathlib,re,sys
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPad")]
groups = [[d for d in candidates if re.search(r"^iPad Air 11-inch", d["name"])],
          [d for d in candidates if re.search(r"^iPad Pro 11-inch", d["name"])]]
candidates = next((group for group in groups if group), [])
if not candidates: raise SystemExit("Aucun iPad Air 11 ou Pro 11 disponible pour la campagne native ; aucun repli sur 13 pouces.")
selected = candidates[0]
pathlib.Path("artifacts/ios/test-device-iPad.json").write_text(json.dumps(dict(deviceFamily="iPad", simulatorName=selected["name"]), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(selected["udid"])
')
xcrun simctl shutdown "$device_id"
xcrun simctl boot "$ipad_id" || true
xcrun simctl bootstatus "$ipad_id" -b
ipad_status=0
xcodebuild test-without-building \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination "platform=iOS Simulator,id=$ipad_id" \
  -skip-testing:DrivyUITests/VisualOrientationTests \
  -only-testing:DrivyUITests -only-testing:DrivyTests/SchoolPresentationTests -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/iPadTests.xcresult \
  2>&1 | tee artifacts/ios/ipad-test.log || ipad_status=$?
xcrun simctl launch "$ipad_id" ch.drivy.qualification || true
sleep 2
xcrun simctl io "$ipad_id" screenshot artifacts/ios/ipad-light.png || true
if (( phone_status != 0 || ipad_status != 0 )); then
  echo "Échec des essais natifs : iPhone=$phone_status iPad=$ipad_status"
  exit 1
fi
