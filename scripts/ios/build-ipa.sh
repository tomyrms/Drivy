#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/ios/Payload
xcodebuild build \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath artifacts/ios/DeviceBuild \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  2>&1 | tee artifacts/ios/device-build.log
cp -R artifacts/ios/DeviceBuild/Build/Products/Release-iphoneos/Drivy.app artifacts/ios/Payload/
test -f artifacts/ios/Payload/Drivy.app/Drivy
(cd artifacts/ios && zip -q -r Drivy.ipa Payload)
(cd artifacts/ios && shasum -a 256 Drivy.ipa > SHA256SUMS.txt)
python3 - <<'PY'
import datetime,json,os,pathlib,subprocess
info={
  "commit":os.environ.get("GITHUB_SHA",subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()),
  "run":os.environ.get("GITHUB_RUN_ID"),
  "build":os.environ.get("GITHUB_RUN_NUMBER","1"),
  "builtAt":datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "configuration":"Release", "signed":False,
  "distribution":"Signature locale avec iLoader", "minimumOS":"26.0",
  "scope":"G0 : séances d'essai locales ; aucun serveur scolaire connecté",
  "physicalQualification":"NOT_EXECUTED"
}
pathlib.Path("artifacts/ios/build-info.json").write_text(json.dumps(info,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
PY
