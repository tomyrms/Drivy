#!/usr/bin/env bash
# Source from the repository root, before either build-for-testing or test-without-building.
# This is the only production list of selected suites. No Apple command runs here.
unit_only=${DRIVY_IOS_UNIT_ONLY:-0}
visual_only=${DRIVY_IOS_VISUAL_ONLY:-0}
unit_test_scope=${DRIVY_IOS_UNIT_TEST_SCOPE:-gps}
ui_test_suite=${DRIVY_IOS_UI_TEST_SUITE:-}
ui_iphone_only=${DRIVY_IOS_UI_IPHONE_ONLY:-0}
test_options=()
ui_test_options=()

[[ "$unit_only" == 0 || "$unit_only" == 1 ]] || { echo 'Mode métier invalide (0 ou 1).' >&2; exit 1; }
[[ "$visual_only" == 0 || "$visual_only" == 1 ]] || { echo 'Mode visuel invalide (0 ou 1).' >&2; exit 1; }
[[ "$ui_iphone_only" == 0 || "$ui_iphone_only" == 1 ]] || { echo 'Mode iPhone seul invalide (0 ou 1).' >&2; exit 1; }
# iPhone seul reste un contrôle intermédiaire ciblé : jamais pour la campagne complète ou finale.
[[ "$ui_iphone_only" == 0 || -n "$ui_test_suite" ]] || { echo 'Le mode iPhone seul exige une sélection UI.' >&2; exit 1; }
[[ "$unit_test_scope" == gps || "$unit_test_scope" == agenda || "$unit_test_scope" == reports || "$unit_test_scope" == all ]] || { echo 'Périmètre métier invalide (gps, agenda, reports ou all).' >&2; exit 1; }
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
  elif [[ "$unit_test_scope" == reports ]]; then
    for suite in SchoolReportFlowTests SchoolLessonFinishTests SchoolLessonHubTests SchoolTrainingRefreshTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  elif [[ "$unit_test_scope" == agenda ]]; then
    # Agenda #144-#146: calendar projection, course reads and their synthetic UI transport.
    for suite in SchoolAgendaMonthTests SchoolAgendaCoursesTests SchoolCourseClientTests SchoolVisualTransportTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  else
    # Nine GPS feature files contain eleven suites: transport and lifecycle are separate Swift suites.
    for suite in SchoolLiveMatchTests SchoolLiveMatchTransportTests SchoolLiveMatchLifecycleTests \
      SchoolCaptureLifecycleTests SchoolCaptureInteropTests SchoolCaptureReplayTests SchoolTrackDisplayTests \
      SchoolMapCourseTests SchoolMapRouteGapTests SchoolLiveHeadingTests SchoolReplayFormattingTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  fi
fi

# The real relay test fails rather than skips when its service is absent.
# Start its disposable service for every selection that can discover it.
relay_required=0
if [[ -f apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift \
      && "$visual_only" == 0 && -z "$ui_test_suite" \
      && ( "$unit_only" == 0 || "$unit_test_scope" == all ) ]]; then
  relay_required=1
fi
