#!/usr/bin/env bash
# Source from the repository root, before either build-for-testing or test-without-building.
# This is the only production list of selected suites. No Apple command runs here.
unit_only=${DRIVY_IOS_UNIT_ONLY:-0}
visual_only=${DRIVY_IOS_VISUAL_ONLY:-0}
unit_test_scope=${DRIVY_IOS_UNIT_TEST_SCOPE:-gps}
ui_test_suite=${DRIVY_IOS_UI_TEST_SUITE:-}
ui_iphone_only=${DRIVY_IOS_UI_IPHONE_ONLY:-0}
# Campagne complète (toute la suite métier, toute l'UI, puis l'iPad) : jamais implicite, ou imposée par une qualification.
full_campaign=${DRIVY_IOS_FULL_CAMPAIGN:-0}
# L'iPad d'une suite UI ciblée est une demande explicite : le contrôle courant tourne sur l'iPhone seul.
ui_ipad=${DRIVY_IOS_UI_IPAD:-0}
build_ipa=${DRIVY_IOS_BUILD_IPA:-0}
test_options=()
ui_test_options=()

[[ "$unit_only" == 0 || "$unit_only" == 1 ]] || { echo 'Mode métier invalide (0 ou 1).' >&2; exit 1; }
[[ "$visual_only" == 0 || "$visual_only" == 1 ]] || { echo 'Mode visuel invalide (0 ou 1).' >&2; exit 1; }
[[ "$ui_iphone_only" == 0 || "$ui_iphone_only" == 1 ]] || { echo 'Mode iPhone seul invalide (0 ou 1).' >&2; exit 1; }
[[ "$full_campaign" == 0 || "$full_campaign" == 1 ]] || { echo 'Campagne complète invalide (0 ou 1).' >&2; exit 1; }
[[ "$ui_ipad" == 0 || "$ui_ipad" == 1 ]] || { echo 'Mode iPad invalide (0 ou 1).' >&2; exit 1; }
[[ "$build_ipa" == 0 || "$build_ipa" == 1 ]] || { echo 'Demande d’IPA invalide (0 ou 1).' >&2; exit 1; }
# iPhone seul reste un contrôle intermédiaire ciblé : jamais pour la campagne complète ou finale.
[[ "$ui_iphone_only" == 0 || -n "$ui_test_suite" ]] || { echo 'Le mode iPhone seul exige une sélection UI.' >&2; exit 1; }
[[ "$ui_ipad" == 0 || -n "$ui_test_suite" ]] || { echo 'L’iPad ne s’ajoute qu’à une sélection UI ; la campagne complète le lance déjà.' >&2; exit 1; }
[[ "$ui_ipad" == 0 || "$ui_iphone_only" == 0 ]] || { echo 'iPhone seul et iPad s’excluent.' >&2; exit 1; }
[[ "$build_ipa" == 0 || "$full_campaign" == 1 ]] || { echo 'L’IPA ne se construit qu’avec la campagne complète ; sinon, utiliser le workflow « IPA d’essai · iLoader ».' >&2; exit 1; }
# Aucun mode implicite : sans choix, un lancement sans paramètre rejouait toute la campagne puis construisait une IPA.
[[ "$unit_only" == 1 || "$visual_only" == 1 || -n "$ui_test_suite" || "$full_campaign" == 1 ]] || {
  echo 'Aucun mode choisi. Préciser unit_only=true (avec unit_test_scope), ui_test_suite="Suite ...", visual_only=true ou, pour tout rejouer, full_campaign=true.' >&2
  exit 1
}
[[ "$full_campaign" == 0 || ( "$unit_only" == 0 && "$visual_only" == 0 && -z "$ui_test_suite" ) ]] || { echo 'La campagne complète exclut les modes ciblés.' >&2; exit 1; }
# iPad : campagne complète, ou suite UI ciblée qui le demande. Jamais pour le métier seul ni les captures.
run_ipad=0
if [[ "$full_campaign" == 1 || ( -n "$ui_test_suite" && "$ui_ipad" == 1 ) ]]; then run_ipad=1; fi
[[ "$unit_test_scope" == gps || "$unit_test_scope" == agenda || "$unit_test_scope" == reports || "$unit_test_scope" == reactivity || "$unit_test_scope" == messaging || "$unit_test_scope" == consent || "$unit_test_scope" == drafts || "$unit_test_scope" == profile || "$unit_test_scope" == all ]] || { echo 'Périmètre métier invalide (gps, agenda, reports, reactivity, messaging, consent, drafts, profile ou all).' >&2; exit 1; }
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
  elif [[ "$unit_test_scope" == consent ]]; then
    test_options=(-only-testing:DrivyTests/SchoolStartNowConsentTests)
  elif [[ "$unit_test_scope" == profile ]]; then
    test_options=(-only-testing:DrivyTests/SchoolSelfProfileIntentTests)
  elif [[ "$unit_test_scope" == drafts ]]; then
    for suite in SchoolLessonPreparationReactivityTests SchoolLessonWishReactivityTests SchoolReportFlowTests SchoolLessonTextDraftTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  elif [[ "$unit_test_scope" == messaging ]]; then
    # Signalements (#77) : scellement pour les administrateurs, boîte, transport, puis le même parcours contre le vrai relais.
    for suite in MessagingOptimisticMutationTests MessagingProtectedStoreTests MessagingCoreTests MessagingHTTPTransportTests \
      MessagingExyteThreadTests MatrixMessagingReportSealingTests MessagingReportInboxTests MessagingReportTransportTests \
      MatrixMessagingRelayIntegrationTests MatrixMessagingSealedReportRelayTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
  elif [[ "$unit_test_scope" == reactivity ]]; then
    for suite in SchoolNotificationSettingsTests AccountIntentStorageTests SchoolCommandSchedulingTests \
      SchoolNotificationTests SchoolCommandOutboxTests SchoolPlanningDefaultsTests SchoolInvitationWorkspaceTests; do
      test_options+=("-only-testing:DrivyTests/$suite")
    done
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
      && ( "$unit_only" == 0 || "$unit_test_scope" == all || "$unit_test_scope" == messaging ) ]]; then
  relay_required=1
fi
