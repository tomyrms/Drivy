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

    def test_full_campaign_and_visual_mode_remain_unfiltered(self):
        self.assert_options([])
        self.assert_options([], DRIVY_IOS_VISUAL_ONLY='1')

    def test_gps_suite_names_exist_in_real_swift_sources(self):
        sources = '\n'.join(path.read_text(encoding='utf-8') for path in (ROOT / 'apps/ios/DrivyTests').glob('*.swift'))
        for suite in GPS_SUITES:
            self.assertRegex(sources, r'\bstruct\s+' + suite + r'\b')

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
        for scope, expected in [('gps', GPS_OPTIONS), ('all', ['-only-testing:DrivyTests'])]:
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

    def test_ui_mode_shares_selection_and_still_runs_both_devices(self):
        expected = ['-only-testing:DrivyUITests/VisualOrientationTests/testRequestedScreensAtRealOrientations']
        for build in [True, False]:
            result = self.run_script(build=build, DRIVY_IOS_UI_TEST_SUITE='VisualOrientationTests/testRequestedScreensAtRealOrientations')
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            calls = [line for line in result.stdout.splitlines() if line.startswith('xcodebuild')]
            self.assertEqual(len(calls), 1 if build else 2)
            for call in calls:
                self.assertEqual(re.findall(r'<(-only-testing:[^>]+)>', call), expected)
            if not build:
                self.assertIn('<IPAD>', result.stdout)

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
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('<IPAD>', result.stdout)
        self.assertIn('<-only-testing:DrivyUITests>', result.stdout)
        self.assertIn('<screenshot>', result.stdout)

    def test_workflow_validates_before_setup_and_prevents_unit_ipa_or_visual_capture(self):
        workflow = (ROOT / '.github/workflows/refonte-ios.yml').read_text(encoding='utf-8')
        self.assertLess(workflow.index('- name: Valider le mode et la sélection des tests'), workflow.index('- name: Installer XcodeGen'))
        self.assertIn("unit_test_scope:\n", workflow)
        self.assertIn("options: [gps, all]", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertIn("inputs.visual_only != true && inputs.unit_only != true && inputs.ui_test_suite == ''", workflow)
        self.assertIn('if: inputs.visual_only == true', workflow)


if __name__ == '__main__':
    unittest.main()
