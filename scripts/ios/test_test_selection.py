#!/usr/bin/env python3
"""Selection/argument tests with fake Apple commands. No simulator or Swift build."""
from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASH = os.environ.get('DRIVY_TEST_BASH') or (r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else 'bash')
GPS_SUITES = [
    'SchoolLiveMatchTests', 'SchoolLiveMatchTransportTests', 'SchoolLiveMatchLifecycleTests',
    'SchoolCaptureLifecycleTests', 'SchoolCaptureInteropTests', 'SchoolCaptureReplayTests', 'SchoolTrackDisplayTests',
    'SchoolMapCourseTests', 'SchoolMapRouteGapTests', 'SchoolLiveHeadingTests', 'SchoolReplayFormattingTests',
]
GPS_OPTIONS = ['-only-testing:DrivyTests/' + suite for suite in GPS_SUITES]
AGENDA_SUITES = ['SchoolAgendaMonthTests', 'SchoolAgendaCoursesTests', 'SchoolCourseClientTests', 'SchoolVisualTransportTests']
AGENDA_OPTIONS = ['-only-testing:DrivyTests/' + suite for suite in AGENDA_SUITES]
REPORT_SUITES = ['SchoolReportFlowTests', 'SchoolLessonFinishTests', 'SchoolLessonHubTests', 'SchoolTrainingRefreshTests']
REPORT_OPTIONS = ['-only-testing:DrivyTests/' + suite for suite in REPORT_SUITES]
REACTIVITY_SUITES = ['SchoolNotificationSettingsTests', 'AccountIntentStorageTests', 'SchoolCommandSchedulingTests',
                     'SchoolNotificationTests', 'SchoolCommandOutboxTests', 'SchoolPlanningDefaultsTests', 'SchoolInvitationWorkspaceTests']
REACTIVITY_OPTIONS = ['-only-testing:DrivyTests/' + suite for suite in REACTIVITY_SUITES]
MESSAGING_SUITES = ['MessagingOptimisticMutationTests', 'MessagingProtectedStoreTests', 'MessagingCoreTests', 'MessagingHTTPTransportTests',
                    'MessagingExyteThreadTests']
MESSAGING_OPTIONS = ['-only-testing:DrivyTests/' + suite for suite in MESSAGING_SUITES]


def environment(**overrides):
    env = {key: value for key, value in os.environ.items() if not key.startswith('DRIVY_IOS_')}
    env.update(overrides)
    return env


class TestSelection(unittest.TestCase):
    def selection(self, **overrides):
        return subprocess.run([BASH, '-c', 'set -euo pipefail; source scripts/ios/test-selection.sh; '
                               'printf "%s\\n" ${test_options[@]+"${test_options[@]}"}'],
                              cwd=ROOT, env=environment(**overrides), text=True, capture_output=True, timeout=10)

    def assert_options(self, expected, **overrides):
        result = self.selection(**overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), expected)

    def test_unit_defaults_to_all_gps_suites_including_transport_and_lifecycle(self):
        self.assert_options(GPS_OPTIONS, DRIVY_IOS_UNIT_ONLY='1')

    def test_explicit_gps_matches_default(self):
        self.assert_options(GPS_OPTIONS, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='gps')

    def test_explicit_all_keeps_old_full_unit_target(self):
        self.assert_options(['-only-testing:DrivyTests'], DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='all')

    def test_agenda_selects_only_its_projection_reading_and_fixture_suites(self):
        self.assert_options(AGENDA_OPTIONS, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='agenda')

    def test_reports_selects_durable_draft_and_lesson_scope_suites(self):
        self.assert_options(REPORT_OPTIONS, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='reports')

    def test_reactivity_selects_preferences_and_domain_scheduling_regressions(self):
        self.assert_options(REACTIVITY_OPTIONS, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='reactivity')

    def test_messaging_selects_mutation_and_protected_storage_regressions(self):
        self.assert_options(MESSAGING_OPTIONS, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='messaging')

    def test_agenda_does_not_require_the_unrelated_crypto_relay(self):
        result = subprocess.run([BASH, '-c', 'set -euo pipefail; source scripts/ios/test-selection.sh; '
                                 'printf "%s" "$relay_required"'], cwd=ROOT,
                                env=environment(DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='agenda'),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '0')

    def test_full_campaign_and_visual_mode_remain_unfiltered(self):
        self.assert_options([], DRIVY_IOS_FULL_CAMPAIGN='1')
        self.assert_options([], DRIVY_IOS_FULL_CAMPAIGN='1', DRIVY_IOS_BUILD_IPA='1')
        self.assert_options([], DRIVY_IOS_VISUAL_ONLY='1')

    def run_ipad(self, **overrides):
        result = subprocess.run([BASH, '-c', 'set -euo pipefail; source scripts/ios/test-selection.sh; printf "%s" "$run_ipad"'],
                                cwd=ROOT, env=environment(**overrides), text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_ipad_only_for_the_full_campaign_or_an_explicit_request(self):
        suite = 'VisualOrientationTests'
        self.assertEqual(self.run_ipad(DRIVY_IOS_FULL_CAMPAIGN='1'), '1')
        self.assertEqual(self.run_ipad(DRIVY_IOS_UI_TEST_SUITE=suite), '0')
        self.assertEqual(self.run_ipad(DRIVY_IOS_UI_TEST_SUITE=suite, DRIVY_IOS_UI_IPHONE_ONLY='1'), '0')
        self.assertEqual(self.run_ipad(DRIVY_IOS_UI_TEST_SUITE=suite, DRIVY_IOS_UI_IPAD='1'), '1')
        self.assertEqual(self.run_ipad(DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='all'), '0')
        self.assertEqual(self.run_ipad(DRIVY_IOS_VISUAL_ONLY='1'), '0')

    def test_no_mode_is_refused_before_any_work(self):
        result = self.selection()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Aucun mode choisi', result.stderr)

    def test_selected_suite_names_exist_in_real_swift_sources(self):
        sources = '\n'.join(path.read_text(encoding='utf-8') for path in (ROOT / 'apps/ios/DrivyTests').glob('*.swift'))
        for suite in GPS_SUITES + AGENDA_SUITES + REPORT_SUITES + REACTIVITY_SUITES + MESSAGING_SUITES:
            self.assertIsNotNone(re.search(r'\b(?:struct|class)\s+' + suite + r'\b', sources), f'Suite Swift absente : {suite}')

    def test_ui_suite_and_method_are_preserved(self):
        self.assert_options(['-only-testing:DrivyUITests/VisualOrientationTests/testRequestedScreensAtRealOrientations'],
                            DRIVY_IOS_UI_TEST_SUITE='VisualOrientationTests/testRequestedScreensAtRealOrientations')

    def test_invalid_scopes_flags_and_mode_combinations_fail(self):
        cases = [
            {'DRIVY_IOS_UNIT_TEST_SCOPE': 'everything'}, {'DRIVY_IOS_UNIT_TEST_SCOPE': 'gps\nall'},
            {'DRIVY_IOS_UNIT_ONLY': 'true'}, {'DRIVY_IOS_VISUAL_ONLY': 'yes'},
            {'DRIVY_IOS_UNIT_ONLY': '1', 'DRIVY_IOS_VISUAL_ONLY': '1'},
            {'DRIVY_IOS_UNIT_ONLY': '1', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_VISUAL_ONLY': '1', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_UI_TEST_SUITE': 'UnknownTests'},
            {'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests/testUnknown'},
            {'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests;echo unsafe'},
            {'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests\nVisualOrientationTests'},
            {'DRIVY_IOS_UI_TEST_SUITE': ' '.join(['VisualOrientationTests'] * 9)},
            {'DRIVY_IOS_UI_IPHONE_ONLY': '1'},
            {'DRIVY_IOS_UI_IPHONE_ONLY': 'yes', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {},
            {'DRIVY_IOS_FULL_CAMPAIGN': '2'},
            {'DRIVY_IOS_FULL_CAMPAIGN': '1', 'DRIVY_IOS_UNIT_ONLY': '1'},
            {'DRIVY_IOS_FULL_CAMPAIGN': '1', 'DRIVY_IOS_VISUAL_ONLY': '1'},
            {'DRIVY_IOS_FULL_CAMPAIGN': '1', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_UI_IPAD': 'yes', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_UI_IPAD': '1', 'DRIVY_IOS_FULL_CAMPAIGN': '1'},
            {'DRIVY_IOS_UI_IPAD': '1', 'DRIVY_IOS_UNIT_ONLY': '1'},
            {'DRIVY_IOS_UI_IPAD': '1', 'DRIVY_IOS_UI_IPHONE_ONLY': '1', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_BUILD_IPA': '1', 'DRIVY_IOS_UNIT_ONLY': '1'},
            {'DRIVY_IOS_BUILD_IPA': '1', 'DRIVY_IOS_UI_TEST_SUITE': 'VisualOrientationTests'},
            {'DRIVY_IOS_BUILD_IPA': 'yes', 'DRIVY_IOS_FULL_CAMPAIGN': '1'},
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertNotEqual(self.selection(**case).returncode, 0)


class SimulatorArguments(unittest.TestCase):
    def run_script(self, *, build=False, **overrides):
        directory = tempfile.TemporaryDirectory(prefix='drivy-test-selection-')
        self.addCleanup(directory.cleanup)
        root = pathlib.Path(directory.name)
        shutil.copytree(ROOT / 'scripts/ios', root / 'scripts/ios', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(ROOT / 'apps/ios/DrivyUITests', root / 'apps/ios/DrivyUITests')
        (root / 'artifacts/ios').mkdir(parents=True)
        # Functions are inherited by the actual workflow build snippet / simulator script.
        harness = r'''
set -euo pipefail
xcodebuild() { printf 'xcodebuild'; printf ' <%s>' "$@"; printf '\n'; return "${MOCK_TEST_STATUS:-0}"; }
xcrun() { printf 'xcrun'; printf ' <%s>' "$@"; printf '\n'; }
python3() { if [[ "$*" == *'startswith("iPhone")'* ]]; then echo PHONE; else echo IPAD; fi; }
sleep() { :; }
export -f xcodebuild xcrun python3 sleep
'''
        if build:
            workflow = (ROOT / '.github/workflows/refonte-ios.yml').read_text(encoding='utf-8')
            block = workflow.split('- name: Compiler l\'application et les cibles nécessaires', 1)[1]
            block = block.split('        run: |\n', 1)[1].split("          python3 - <<'PY'", 1)[0]
            harness += '\n'.join(line[10:] for line in block.splitlines())
        else:
            harness += 'bash scripts/ios/test-simulator.sh\n'
        env = environment(VISUAL_ONLY='false', VISUAL_ORIENTATIONS='', VISUAL_SCREENS='home-tabs')
        env.update(overrides)
        return subprocess.run([BASH, '-c', harness], cwd=root, env=env, text=True, capture_output=True, timeout=15)

    def test_unit_build_and_test_share_exact_selection_and_never_run_ui_or_ipad(self):
        for scope, expected in [('gps', GPS_OPTIONS), ('agenda', AGENDA_OPTIONS), ('reports', REPORT_OPTIONS), ('reactivity', REACTIVITY_OPTIONS), ('messaging', MESSAGING_OPTIONS), ('all', ['-only-testing:DrivyTests'])]:
            with self.subTest(scope=scope):
                outputs = []
                for build in [True, False]:
                    result = self.run_script(build=build, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE=scope)
                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    calls = [line for line in result.stdout.splitlines() if line.startswith('xcodebuild')]
                    self.assertEqual(len(calls), 1, result.stdout)
                    selected = re.findall(r'<(-only-testing:[^>]+)>', calls[0])
                    self.assertEqual(selected, expected)
                    outputs.append(selected)
                    self.assertNotIn('<IPAD>', result.stdout)
                    self.assertNotIn('<screenshot>', result.stdout)
                    self.assertNotIn('<-only-testing:DrivyUITests', calls[0])
                self.assertEqual(*outputs)

    def test_invalid_scope_fails_before_any_apple_command(self):
        for build in [True, False]:
            result = self.run_script(build=build, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='invalid')
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('xcodebuild <', result.stdout)
            self.assertNotIn('xcrun <', result.stdout)

    def test_ui_mode_shares_selection_and_adds_the_ipad_only_on_request(self):
        expected = ['-only-testing:DrivyUITests/VisualOrientationTests/testRequestedScreensAtRealOrientations']
        suite = 'VisualOrientationTests/testRequestedScreensAtRealOrientations'
        for ipad in [False, True]:
            for build in [True, False]:
                with self.subTest(ipad=ipad, build=build):
                    extra = {'DRIVY_IOS_UI_IPAD': '1'} if ipad else {}
                    result = self.run_script(build=build, DRIVY_IOS_UI_TEST_SUITE=suite, **extra)
                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    calls = [line for line in result.stdout.splitlines() if line.startswith('xcodebuild')]
                    self.assertEqual(len(calls), 1 if build or not ipad else 2)
                    for call in calls:
                        self.assertEqual(re.findall(r'<(-only-testing:[^>]+)>', call), expected)
                    if not build:
                        self.assertEqual('<IPAD>' in result.stdout, ipad)
                        self.assertEqual('<screenshot>' in result.stdout, ipad)

    def test_ui_iphone_only_runs_selection_once_without_ipad_or_capture(self):
        expected = ['-only-testing:DrivyUITests/VisualOrientationTests/testRequestedScreensAtRealOrientations']
        for status in ['0', '65']:
            with self.subTest(status=status):
                result = self.run_script(DRIVY_IOS_UI_TEST_SUITE='VisualOrientationTests/testRequestedScreensAtRealOrientations',
                                         DRIVY_IOS_UI_IPHONE_ONLY='1', MOCK_TEST_STATUS=status)
                self.assertEqual(result.returncode, int(status), result.stderr + result.stdout)
                calls = [line for line in result.stdout.splitlines() if line.startswith('xcodebuild')]
                self.assertEqual(len(calls), 1, result.stdout)
                self.assertEqual(re.findall(r'<(-only-testing:[^>]+)>', calls[0]), expected)
                self.assertNotIn('<IPAD>', result.stdout)
                self.assertNotIn('<screenshot>', result.stdout)

    def test_visual_build_action_is_unchanged(self):
        for orientations, action in [('', 'build'), ('portrait', 'build-for-testing')]:
            result = self.run_script(build=True, DRIVY_IOS_VISUAL_ONLY='1', VISUAL_ONLY='true', VISUAL_ORIENTATIONS=orientations)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn('xcodebuild <' + action + '>', result.stdout)
            self.assertNotIn('-only-testing:', result.stdout)

    def test_unit_failure_is_preserved_without_other_device_or_capture(self):
        result = self.run_script(DRIVY_IOS_UNIT_ONLY='1', MOCK_TEST_STATUS='65')
        self.assertEqual(result.returncode, 65, result.stderr + result.stdout)
        self.assertNotIn('<IPAD>', result.stdout)
        self.assertNotIn('<screenshot>', result.stdout)

    def test_full_campaign_retains_ipad_and_ui_coverage(self):
        result = self.run_script(DRIVY_IOS_FULL_CAMPAIGN='1')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('<IPAD>', result.stdout)
        self.assertIn('<-only-testing:DrivyUITests>', result.stdout)
        self.assertIn('<screenshot>', result.stdout)

    def test_no_mode_never_reaches_an_apple_command(self):
        for build in [True, False]:
            result = self.run_script(build=build)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('xcodebuild <', result.stdout)
            self.assertNotIn('xcrun <', result.stdout)

    def test_simulator_build_compiles_arm64_only_and_skips_unused_coverage(self):
        result = self.run_script(build=True, DRIVY_IOS_FULL_CAMPAIGN='1')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        call = [line for line in result.stdout.splitlines() if line.startswith('xcodebuild')][0]
        for option in ['<ARCHS=arm64>', '<ONLY_ACTIVE_ARCH=NO>', '<COMPILER_INDEX_STORE_ENABLE=NO>', '<-enableCodeCoverage> <NO>']:
            self.assertIn(option, call)
        self.assertNotIn('x86_64', call)
        # Les captures qui ne compilent que l'app n'ont pas d'action de test.
        visual = self.run_script(build=True, DRIVY_IOS_VISUAL_ONLY='1', VISUAL_ONLY='true')
        self.assertIn('<ARCHS=arm64>', visual.stdout)
        self.assertNotIn('<-enableCodeCoverage>', visual.stdout)

    def test_workflow_validates_before_setup_and_prevents_unit_ipa_or_visual_capture(self):
        workflow = (ROOT / '.github/workflows/refonte-ios.yml').read_text(encoding='utf-8')
        self.assertLess(workflow.index('- name: Valider le mode et la sélection des tests'), workflow.index('- name: Installer XcodeGen'))
        self.assertIn("unit_test_scope:\n", workflow)
        self.assertIn("options: [gps, agenda, reports, reactivity, messaging, all]", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertIn("inputs.visual_only != true && inputs.unit_only != true && inputs.ui_test_suite == ''", workflow)
        self.assertIn('if: inputs.visual_only == true', workflow)

    def test_workflow_no_longer_queues_dispatches_and_builds_no_ipa_by_default(self):
        workflow = (ROOT / '.github/workflows/refonte-ios.yml').read_text(encoding='utf-8')
        group = re.search(r'^  group: (refonte-ios-.*)$', workflow, re.MULTILINE)
        self.assertIsNotNone(group)
        # Un groupe par branche faisait attendre 51 minutes derrière une exécution dépassée.
        self.assertNotIn('github.ref', group.group(1))
        self.assertIn('inputs.qualification_sha || github.run_id', group.group(1))
        for name in ['full_campaign', 'build_ipa', 'ui_ipad']:
            self.assertRegex(workflow, name + r':\n        description: .*\n        type: boolean\n        default: false')
        self.assertEqual(workflow.count('if: inputs.build_ipa == true && '), 2)
        # Une qualification est la campagne complète, sans que la finale ait à le dire.
        self.assertIn("DRIVY_IOS_FULL_CAMPAIGN: ${{ (inputs.full_campaign || inputs.qualification_sha != '') && '1' || '0' }}", workflow)


if __name__ == '__main__':
    unittest.main()
