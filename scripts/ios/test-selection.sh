#!/usr/bin/env bash
# Source from the repository root, before either build-for-testing or test-without-building.
# This is the only production list of selected suites. No Apple command runs here.
unit_only=${DRIVY_IOS_UNIT_ONLY:-0}
visual_only=${DRIVY_IOS_VISUAL_ONLY:-0}
unit_test_scope=${DRIVY_IOS_UNIT_TEST_SCOPE:-gps}
ui_test_suite=${DRIVY_IOS_UI_TEST_SUITE:-}
test_options=()
ui_test_options=()

[[ "$unit_only" == 0 || "$unit_only" == 1 ]] || { echo 'Mode métier invalide (0 ou 1).' >&2; exit 1; }
[[ "$visual_only" == 0 || "$visual_only" == 1 ]] || { echo 'Mode visuel invalide (0 ou 1).' >&2; exit 1; }
[[ "$unit_test_scope" == gps || "$unit_test_scope" == all ]] || { echo 'Périmètre métier invalide (gps ou all).' >&2; exit 1; }
[[ "$visual_only" != 1 || ( "$unit_only" == 0 && -z "$ui_test_suite" ) ]] || { echo 'Choisir les captures visuelles ou les tests, pas les deux.' >&2; exit 1; }

if [[ -n "$ui_test_suite" ]]; then
  [[ "$unit_only" != 1 ]] || { echo 'Choisir soit les tests métier, soit une suite UI.' >&2; exit 1; }
  [[ "$ui_test_suite" != *$'\n'* && "$ui_test_suite" != *$'\r'* && ${#ui_test_suite} -le 1200 ]] || { echo 'Sélection UI invalide.' >&2; exit 1; }
  read -r -a ui_test_selections <<< "$ui_test_suite"
  [[ ${#ui_test_selections[@]} -ge 1 && ${#ui_test_selections[@]} -le 8 ]] || { echo 'Choisir entre une et huit suites ou méthodes UI.' >&2; exit 1; }
  for selection in "${ui_test_selections[@]}"; do
    [[ "$selection" =~ ^[A-Za-z][A-Za-z0-9_]*(/test[A-Za-z0-9_]+)?$ ]] || { echo 'Sélection UI invalide.' >&2; exit 1; }
    suite=${selection%%/*}
    [[ -f "apps/ios/DrivyUITests/$suite.swift" ]] || { echo 'Suite UI inconnue.' >&2; exit 1; }
    if [[ "$selection" == */* ]]; then
      method=${selection#*/}
      grep -Eq "^[[:space:]]*func $method\\(" "apps/ios/DrivyUITests/$suite.swift" || { echo 'Méthode UI inconnue.' >&2; exit 1; }
    fi
    ui_test_options+=("-only-testing:DrivyUITests/$selection")
  done
  test_options=("${ui_test_options[@]}")
elif [[ "$unit_only" == 1 ]]; then
  if [[ "$unit_test_scope" == all ]]; then
    test_options=(-only-testing:DrivyTests)
  else
    # Nine GPS feature files contain eleven suites: transport and lifecycle are separate Swift suites.
    for suite in SchoolLiveMatchTests SchoolLiveMatchTransportTests SchoolLiveMatchLifecycleTests \
      SchoolCaptureLifecycleTests SchoolCaptureInteropTests SchoolCaptureReplayTests SchoolTrackDisplayTests \
      SchoolMapCourseTests SchoolMapRouteGapTests SchoolLiveHeadingTests SchoolReplayFormattingTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  fi
fi
