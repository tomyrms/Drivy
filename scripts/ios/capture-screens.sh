#!/usr/bin/env bash
set -euo pipefail
# Capture the actual app compositor, not UIKit drawHierarchy around MapKit.
# The explicit harness is compiled only in DEBUG simulator builds. No school
# API/login: school screens (agenda, learners, learner, dossier, home-tabs…) read
# fictional fixtures through an in-memory transport restricted to visual.drivy.invalid.
app=artifacts/ios/DerivedData/Build/Products/Debug-iphonesimulator/Drivy.app
[[ -d "$app" ]]
read -r -a screens <<< "${DRIVY_VISUAL_SCREENS:-home-tabs agenda learners learner dossier}"
read -r -a devices <<< "${DRIVY_VISUAL_DEVICES:-iPhone iPad}"
read -r -a appearances <<< "${DRIVY_VISUAL_APPEARANCES:-light dark}"
read -r -a orientations <<< "${DRIVY_VISUAL_ORIENTATIONS:-portrait}"
use_xctest=0
# Interactive variants require XCTest even when no orientation was specified.
if [[ -n "${DRIVY_VISUAL_ORIENTATIONS:-}" || " ${screens[*]} " =~ [[:space:]](live-signal|signal-status)[[:space:]] ]]; then
  use_xctest=1
fi
for screen in "${screens[@]}"; do
  [[ "$screen" =~ ^(dossier|progression|home-tabs|agenda|learners|learner|lesson|lesson-planned|invitation-code|trips|replay|design-system|gps-choice|signal|live-signal|signal-status|observations|capture-preparation|live|live-waiting|planning|invitations|invitation-create|invitation-detail|lesson-finish|lesson-modal|lesson-tariff|sign-in|sign-in-error|sign-in-loading|sign-in-unconfigured|account|app-lock|join-code|join-code-preview|join-code-error|join-code-pending|join-code-confirmed|join-link|join-link-preview|profile|profile-error|onboarding-welcome|onboarding-information|onboarding-formation|onboarding-gps|onboarding-review|onboarding-ready)$ ]] || { echo 'Écran de capture inconnu.' >&2; exit 1; }
done
for kind in "${devices[@]}"; do
  [[ "$kind" == iPhone || "$kind" == iPad ]] || { echo 'Appareil de capture inconnu.' >&2; exit 1; }
done
for appearance in "${appearances[@]}"; do
  [[ "$appearance" == light || "$appearance" == dark ]] || { echo 'Apparence de capture inconnue.' >&2; exit 1; }
done
for orientation in "${orientations[@]}"; do
  [[ "$orientation" == portrait || "$orientation" == landscape ]] || { echo 'Orientation de capture inconnue.' >&2; exit 1; }
done
xcrun simctl help ui > artifacts/ios/simctl-ui-help.txt 2>&1
active_device_id=""
cleanup_device() {
  if [[ -n "$active_device_id" ]]; then
    xcrun simctl ui "$active_device_id" content_size large || true
    xcrun simctl shutdown "$active_device_id" || true
  fi
}
trap cleanup_device EXIT

capture_oriented() {
  local kind=$1 appearance=$2 device_id=$3 xctestrun test_status=0
  # Copy beside the original: __TESTROOT__ paths must keep resolving to Products.
  xctestrun=$(python3 - "$kind" "$appearance" "${screens[*]}" "${orientations[*]}" "${DRIVY_VISUAL_LARGE_TEXT:-0}" <<'PY'
import pathlib, plistlib, sys
kind, appearance, screens, orientations, large_text = sys.argv[1:]
products = pathlib.Path('artifacts/ios/DerivedData/Build/Products')
sources = [p for p in products.glob('*.xctestrun') if not p.name.startswith('Drivy-Visual-')]
if len(sources) != 1:
    raise SystemExit('Une unique configuration build-for-testing est requise pour les captures orientées.')
data = plistlib.loads(sources[0].read_bytes())
targets = []
for configuration in data.get('TestConfigurations', []):
    targets.extend(t for t in configuration.get('TestTargets', []) if t.get('BlueprintName') == 'DrivyUITests')
if not targets and isinstance(data.get('DrivyUITests'), dict):
    targets = [data['DrivyUITests']]
if len(targets) != 1:
    raise SystemExit('Cible DrivyUITests absente ou ambiguë dans le fichier xctestrun.')
environment = targets[0].setdefault('EnvironmentVariables', {})
environment.update(DRIVY_VISUAL_ORIENTATION_TEST='1', DRIVY_VISUAL_DEVICE=kind,
                   DRIVY_VISUAL_APPEARANCE=appearance, DRIVY_VISUAL_SCREENS=screens,
                   DRIVY_VISUAL_ORIENTATIONS=orientations, DRIVY_VISUAL_LARGE_TEXT=large_text)
destination = products / f'Drivy-Visual-{kind}-{appearance}.xctestrun'
destination.write_bytes(plistlib.dumps(data))
print(destination)
PY
  )
  local result="artifacts/ios/Visual-${kind}-${appearance}.xcresult"
  xcodebuild test-without-building \
    -xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$device_id" \
    -only-testing:DrivyUITests/VisualOrientationTests \
    -parallel-testing-enabled NO -resultBundlePath "$result" \
    2>&1 | tee "artifacts/ios/visual-${kind}-${appearance}-test.log" || test_status=$?
  if (( test_status != 0 )); then return "$test_status"; fi
  local exported="artifacts/ios/oriented-exports/${kind}-${appearance}"
  mkdir -p "$exported"
  xcrun xcresulttool export attachments --path "$result" --output-path "$exported"
  python3 - "$exported" "$kind" "$appearance" "${screens[*]}" "${orientations[*]}" <<'PY'
import hashlib, json, pathlib, shutil, sys

from scripts.ios.png_geometry import png_geometry

exported = pathlib.Path(sys.argv[1]).resolve()
kind, appearance, screens, orientations = sys.argv[2:]
expected = {f'{kind}-{screen}-{appearance}-{orientation}-synthetic': orientation
            for screen in screens.split() for orientation in orientations.split()}
manifest = json.loads((exported / 'manifest.json').read_text())
found = {}
for test in manifest:
    if not test.get('testIdentifier', '').startswith('VisualOrientationTests/'):
        continue
    for item in test.get('attachments', []):
        readable = item.get('suggestedHumanReadableName', '')
        matches = [name for name in expected if readable.startswith(name + '_') or readable == name + '.png']
        if not matches:
            continue
        if len(matches) != 1 or matches[0] in found:
            raise SystemExit('Capture orientée absente ou dupliquée : association ambiguë.')
        name = matches[0]
        source = (exported / item['exportedFileName']).resolve()
        if source.parent != exported:
            raise SystemExit('Chemin de capture exportée hors du répertoire prévu.')
        payload = source.read_bytes()
        try:
            width, height, display_width, display_height, exif_orientation = png_geometry(payload)
        except ValueError as error:
            raise SystemExit(str(error)) from error
        if display_width == display_height or min(width, height) <= 0 or (display_width > display_height) != (expected[name] == 'landscape'):
            raise SystemExit(f'Dimensions incompatibles avec l’orientation demandée : {name}.')
        destination = pathlib.Path('artifacts/ios') / (name + '.png')
        shutil.copyfile(source, destination)  # Original attachment bytes; never rotate or re-encode.
        found[name] = dict(file=destination.name, storedWidthPixels=width, storedHeightPixels=height,
                           displayWidthPixels=display_width, displayHeightPixels=display_height,
                           exifOrientation=exif_orientation, orientation=expected[name],
                           sha256=hashlib.sha256(payload).hexdigest())
if set(found) != set(expected):
    raise SystemExit('Captures orientées manquantes : ' + ', '.join(sorted(set(expected) - set(found))))
proof = dict(deviceFamily=kind, appearance=appearance, capture='XCUIScreen.main.screenshot',
             orientation='XCUIDevice.shared.orientation', appleLanguages=['fr'], appleLocale='fr_CH',
             imageRotationApplied=False, files=[found[name] for name in sorted(found)])
path = pathlib.Path('artifacts/ios') / f'visual-orientation-{kind}-{appearance}.json'
path.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'{len(found)} captures orientées originales exportées et dimensions vérifiées.')
PY
}

for kind in "${devices[@]}"; do
  device_id=$(xcrun simctl list devices available -j | python3 -c '
import json,pathlib,re,sys
kind=sys.argv[1]
compact=sys.argv[2] == "1"
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith(kind)]
if kind == "iPad" and compact:
    groups = [
        [d for d in candidates if re.search(r"^iPad Air 11-inch", d["name"])],
        [d for d in candidates if re.search(r"^iPad Air.*(10[.,]9|\((4th|5th) generation\))", d["name"])],
        [d for d in candidates if re.search(r"^iPad Pro 11-inch", d["name"])]
    ]
    candidates = next((group for group in groups if group), [])
    if not candidates:
        raise SystemExit("Aucun iPad Air 11/10,9 ou Pro 11 disponible ; aucun repli vers un iPad 13 pouces.")
if not candidates: raise SystemExit("Aucun simulateur disponible")
selected = candidates[0]
proof = dict(deviceFamily=kind, simulatorName=selected["name"], compactIPadRequested=kind == "iPad" and compact)
pathlib.Path(f"artifacts/ios/visual-device-{kind}.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(selected["udid"])
' "$kind" "${DRIVY_VISUAL_COMPACT_IPAD:-0}")
  active_device_id="$device_id"
  xcrun simctl boot "$device_id" || true
  xcrun simctl bootstatus "$device_id" -b
  content_size=large
  if [[ "${DRIVY_VISUAL_LARGE_TEXT:-0}" == 1 ]]; then content_size=accessibility-extra-large; fi
  # System Dynamic Type also reaches sheets/popovers outside the fixture environment.
  # Unsupported commands or values fail explicitly: no claim from a source flag alone.
  xcrun simctl ui "$device_id" content_size "$content_size"
  reported_content_size=$(xcrun simctl ui "$device_id" content_size)
  python3 - "$kind" "$content_size" "$reported_content_size" <<'PY'
import json, pathlib, sys
kind, requested, actual = sys.argv[1:]
actual = actual.strip()
if actual != requested:
    raise SystemExit(f'Taille système non confirmée : demandé {requested}, reçu {actual}.')
path = pathlib.Path(f'artifacts/ios/visual-device-{kind}.json')
proof = json.loads(path.read_text(encoding='utf-8'))
proof.update(requestedContentSize=requested, reportedContentSize=actual)
path.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY
  xcrun simctl status_bar "$device_id" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl install "$device_id" "$app"
  for appearance in "${appearances[@]}"; do
    xcrun simctl ui "$device_id" appearance "$appearance"
    if (( use_xctest )); then
      capture_oriented "$kind" "$appearance" "$device_id"
      continue
    fi
    for screen in "${screens[@]}"; do
      xcrun simctl terminate "$device_id" ch.drivy.qualification 2>/dev/null || true
      SIMCTL_CHILD_DRIVY_VISUAL_SCREEN="$screen" SIMCTL_CHILD_DRIVY_VISUAL_LARGE_TEXT="${DRIVY_VISUAL_LARGE_TEXT:-0}" xcrun simctl launch "$device_id" ch.drivy.qualification -AppleLanguages '(fr)' -AppleLocale fr_CH
      sleep 10
      xcrun simctl io "$device_id" screenshot "artifacts/ios/${kind}-${screen}-${appearance}-synthetic.png"
    done
  done
  xcrun simctl ui "$device_id" content_size large
  xcrun simctl shutdown "$device_id"
  active_device_id=""
done
