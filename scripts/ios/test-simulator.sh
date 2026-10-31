#!/usr/bin/env bash
set -euo pipefail
source scripts/ios/test-selection.sh
mkdir -p artifacts/ios
test_plan_options=(-project apps/ios/Drivy.xcodeproj -scheme Drivy)
if [[ "$relay_required" == 1 ]]; then
  source scripts/ios/relay-qualification.sh
  relay_start
  {
    node --version
    postgres --version
    openssl version
  } > artifacts/ios/relay-environment.txt
  relay_plan=$(python3 scripts/ios/configure-relay-tests.py artifacts/ios/DerivedData/Build/Products "$relay_url")
  test_plan_options=(-xctestrun "$relay_plan")
fi
device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not candidates: raise SystemExit("Aucun simulateur iPhone disponible")
print(candidates[0]["udid"])
')
boot_started=$SECONDS
xcrun simctl boot "$device_id" || true
xcrun simctl bootstatus "$device_id" -b
if [[ "$relay_required" == 1 ]]; then
  relay_mark phone_boot_seconds "$((SECONDS - boot_started))"
  relay_trust_simulator "$device_id"
  relay_mark phone_suite_scope "${DRIVY_IOS_UNIT_TEST_SCOPE:-default}"
  relay_probe phone_before_xcodebuild
fi
phone_status=0
xcodebuild test-without-building \
  "${test_plan_options[@]}" \
  -destination "platform=iOS Simulator,id=$device_id" \
  -skip-testing:DrivyUITests/VisualOrientationTests \
  ${test_options[@]+"${test_options[@]}"} \
  -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/Tests.xcresult \
  2>&1 | tee artifacts/ios/simulator-test.log || phone_status=$?
if [[ "$relay_required" == 1 ]]; then
  relay_mark phone_xcodebuild_status "$phone_status"
  if (( phone_status != 0 )); then relay_probe phone_after_failure; fi
fi
# Métier seul, ou suite UI ciblée sans demande d'iPad : l'iPhone suffit, sans captures de contrôle ni second simulateur.
if [[ "$run_ipad" != 1 ]]; then exit "$phone_status"; fi
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
boot_started=$SECONDS
xcrun simctl boot "$ipad_id" || true
xcrun simctl bootstatus "$ipad_id" -b
if [[ "$relay_required" == 1 ]]; then
  relay_mark ipad_boot_seconds "$((SECONDS - boot_started))"
  relay_reset_fixture
  relay_trust_simulator "$ipad_id"
  relay_probe ipad_before_xcodebuild
fi
ipad_status=0
ipad_test_options=(-only-testing:DrivyUITests -only-testing:DrivyTests/SchoolPresentationTests)
if [[ "$relay_required" == 1 ]]; then ipad_test_options+=(-only-testing:DrivyTests/MatrixMessagingRelayIntegrationTests); fi
if [[ -n "$ui_test_suite" ]]; then ipad_test_options=("${ui_test_options[@]}"); fi
xcodebuild test-without-building \
  "${test_plan_options[@]}" \
  -destination "platform=iOS Simulator,id=$ipad_id" \
  -skip-testing:DrivyUITests/VisualOrientationTests \
  "${ipad_test_options[@]}" -parallel-testing-enabled NO \
  -derivedDataPath artifacts/ios/DerivedData \
  -resultBundlePath artifacts/ios/iPadTests.xcresult \
  2>&1 | tee artifacts/ios/ipad-test.log || ipad_status=$?
if [[ "$relay_required" == 1 ]]; then
  relay_mark ipad_xcodebuild_status "$ipad_status"
  if (( ipad_status != 0 )); then relay_probe ipad_after_failure; fi
fi
xcrun simctl launch "$ipad_id" ch.drivy.qualification || true
sleep 2
xcrun simctl io "$ipad_id" screenshot artifacts/ios/ipad-light.png || true
if (( phone_status != 0 || ipad_status != 0 )); then
  echo "Échec des essais natifs : iPhone=$phone_status iPad=$ipad_status"
  exit 1
fi
