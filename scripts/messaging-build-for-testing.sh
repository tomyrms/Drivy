#!/usr/bin/env bash
# Compile les cibles de tests Messages sans exécuter de test ni démarrer de simulateur.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
command -v xcodegen >/dev/null || { echo 'XcodeGen 2.46.0 requis (voir refonte-ios.yml).' >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo 'Xcode/macOS requis.' >&2; exit 1; }
[[ "$(xcodegen --version)" == *'2.46.0'* ]] || { echo 'XcodeGen 2.46.0 requis.' >&2; exit 1; }

# Les dossiers sont volontairement locaux : ne pas exporter des données utilisateur.
mkdir -p artifacts/ios
xcodegen generate --spec apps/ios/project.yml
resolved=apps/ios/Drivy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
mkdir -p "$(dirname "$resolved")"
cp apps/ios/Package.resolved "$resolved"
xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy
xcodebuild build-for-testing -onlyUsePackageVersionsFromResolvedFile \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath artifacts/ios/MessagingDerivedData \
  -only-testing:DrivyTests/MessagingCoreTests \
  -only-testing:DrivyTests/MessagingHTTPTransportTests \
  -only-testing:DrivyTests/MessagingProtectedStoreTests \
  -only-testing:DrivyTests/MessagingEntryTests \
  2>&1 | tee artifacts/ios/messaging-build-for-testing.log
printf '%s\n' 'Compilation des fixtures Messages terminée. Aucune suite de tests exécutée.'
