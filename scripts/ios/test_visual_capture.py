#!/usr/bin/env python3
"""Regression tests for capture orchestration; Apple commands are mocked.

Run from any directory: python3 scripts/ios/test_visual_capture.py
These tests do NOT compile the iOS app or run an iOS simulator.
"""
from __future__ import annotations

import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/ios/capture-screens.sh'
SWIFT = ROOT / 'apps/ios/DrivyUITests/VisualOrientationTests.swift'

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, struct, sys, zlib
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open('mock-calls.jsonl', 'a') as log:
    log.write(json.dumps([name] + args) + '\n')
if name == 'xcodebuild':
    result = pathlib.Path(args[args.index('-resultBundlePath') + 1])
    if os.environ.get('MOCK_BUNDLE', '1') == '1':
        result.mkdir(parents=True)
    print('Mock xcodebuild; no Apple test executed.')
    sys.exit(int(os.environ.get('MOCK_TEST_STATUS', '0')))
if args[:3] == ['simctl', 'list', 'devices']:
    print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-test': [
        {'name': 'iPhone test', 'isAvailable': True, 'udid': 'TEST-DEVICE'}]}}))
elif args[:2] == ['simctl', 'ui'] and args[3:] == ['content_size']:
    print('large')
elif args[:3] == ['xcresulttool', 'export', 'attachments']:
    status = int(os.environ.get('MOCK_EXPORT_STATUS', '0'))
    if status:
        sys.exit(status)
    out = pathlib.Path(args[args.index('--output-path') + 1])
    out.mkdir(parents=True, exist_ok=True)
    mode = os.environ.get('MOCK_MATRIX', 'complete')
    def chunk(kind, data):
        return (struct.pack('>I', len(data)) + kind + data +
                struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))
    width, height = (2, 1) if mode == 'wrong-orientation' else (1, 2)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress((b'\0' + b'\0' * (3 * width)) * height))
           + chunk(b'IEND', b''))
    (out / 'attachment.png').write_bytes(png)
    readable = 'iPhone-dossier-dark-portrait-synthetic.png'
    if mode == 'failure-only':
        readable = 'FAILED-' + readable
    attachments = [] if mode == 'missing' else [
        {'suggestedHumanReadableName': readable, 'exportedFileName': 'attachment.png'}]
    (out / 'manifest.json').write_text(json.dumps([{
        'testIdentifier': 'VisualOrientationTests/testRequestedScreensAtRealOrientations()',
        'attachments': attachments}]))
'''


class VisualCaptureScriptTests(unittest.TestCase):
    def run_capture(self, **overrides: str):
        directory = tempfile.TemporaryDirectory(prefix='drivy-visual-test-')
        self.addCleanup(directory.cleanup)
        root = pathlib.Path(directory.name)
        products = root / 'artifacts/ios/DerivedData/Build/Products'
        (products / 'Debug-iphonesimulator/Drivy.app').mkdir(parents=True)
        (products / 'Drivy-test.xctestrun').write_bytes(plistlib.dumps({
            'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'DrivyUITests'}]}]
        }))
        support = root / 'scripts/ios'
        support.mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/ios/png_geometry.py', support)
        binaries = root / 'bin'
        binaries.mkdir()
        for command in ('xcrun', 'xcodebuild'):
            path = binaries / command
            path.write_text(MOCK, encoding='utf-8')
            path.chmod(0o755)
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(('DRIVY_VISUAL_', 'MOCK_'))}
        environment.update(PATH=str(binaries) + os.pathsep + os.environ.get('PATH', ''),
                           DRIVY_VISUAL_SCREENS='dossier', DRIVY_VISUAL_DEVICES='iPhone',
                           DRIVY_VISUAL_APPEARANCES='dark', DRIVY_VISUAL_ORIENTATIONS='portrait')
        environment.update(overrides)
        result = subprocess.run(['bash', str(SCRIPT)], cwd=root, env=environment,
                                text=True, capture_output=True, timeout=20)
        log = root / 'mock-calls.jsonl'
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, root, calls

    def assert_no_proof(self, root):
        self.assertFalse((root / 'artifacts/ios/visual-orientation-iPhone-dark.json').exists())

    def test_success_preserves_original_png_and_validates_matrix(self):
        result, root, calls = self.run_capture()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        proof = json.loads((root / 'artifacts/ios/visual-orientation-iPhone-dark.json').read_text())
        self.assertEqual(len(proof['files']), 1)
        self.assertFalse(proof['imageRotationApplied'])
        capture = root / 'artifacts/ios/iPhone-dossier-dark-portrait-synthetic.png'
        export = root / 'artifacts/ios/test-reports/Visual-iPhone-dark/capture-attachments/attachment.png'
        self.assertEqual(capture.read_bytes(), export.read_bytes())
        plan = plistlib.loads((root / 'artifacts/ios/DerivedData/Build/Products/Drivy-Visual-iPhone-dark.xctestrun').read_bytes())
        env = plan['TestConfigurations'][0]['TestTargets'][0]['EnvironmentVariables']
        self.assertEqual(env['DRIVY_VISUAL_SCREENS'], 'dossier')
        self.assertEqual(env['DRIVY_VISUAL_ORIENTATION_TEST'], '1')

    def test_exit_65_exports_attachments_before_returning_failure(self):
        result, root, calls = self.run_capture(MOCK_TEST_STATUS='65')
        self.assertEqual(result.returncode, 65, result.stderr)
        build = next(i for i, call in enumerate(calls) if call[0] == 'xcodebuild')
        export = next(i for i, call in enumerate(calls) if call[:4] == ['xcrun', 'xcresulttool', 'export', 'attachments'])
        self.assertGreater(export, build)
        self.assertTrue((root / 'artifacts/ios/test-reports/Visual-iPhone-dark/capture-attachments/manifest.json').exists())
        self.assertIn(['xcrun', 'simctl', 'shutdown', 'TEST-DEVICE'], calls)
        self.assert_no_proof(root)

    def test_export_failure_does_not_mask_exit_65(self):
        result, root, _ = self.run_capture(MOCK_TEST_STATUS='65', MOCK_EXPORT_STATUS='7')
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIn('Export des diagnostics incomplet', result.stderr)
        self.assert_no_proof(root)

    def test_missing_result_does_not_mask_exit_65(self):
        result, root, calls = self.run_capture(MOCK_TEST_STATUS='65', MOCK_BUNDLE='0')
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIn('Résultat XCTest absent', result.stderr)
        self.assertFalse(any(c[:2] == ['xcrun', 'xcresulttool'] for c in calls))
        self.assert_no_proof(root)

    def test_export_failure_after_test_success_is_still_failure(self):
        result, root, _ = self.run_capture(MOCK_EXPORT_STATUS='7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assert_no_proof(root)

    def test_missing_captures_cannot_pass(self):
        result, root, _ = self.run_capture(MOCK_MATRIX='missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Captures orientées manquantes', result.stderr)
        self.assert_no_proof(root)

    def test_failure_screenshot_cannot_count_as_success(self):
        result, root, _ = self.run_capture(MOCK_MATRIX='failure-only')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Captures orientées manquantes', result.stderr)
        self.assert_no_proof(root)

    def test_wrong_orientation_cannot_pass(self):
        result, root, _ = self.run_capture(MOCK_MATRIX='wrong-orientation')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Dimensions incompatibles', result.stderr)
        self.assert_no_proof(root)

    def test_unknown_screen_is_named_before_any_simulator_command(self):
        result, root, calls = self.run_capture(DRIVY_VISUAL_SCREENS='student-file')
        self.assertEqual(result.returncode, 1)
        self.assertIn('student-file', result.stderr)
        self.assertEqual(calls, [])
        self.assert_no_proof(root)

    def test_swift_and_shell_supported_screens_match(self):
        shell = re.search(r'\[\[ "\$screen" =~ \^\(([^\n]+?)\)\$ \]\]', SCRIPT.read_text()).group(1)
        swift = re.search(r'private let supportedScreens: Set<String> = \[(.*?)\]', SWIFT.read_text(), re.S).group(1)
        self.assertEqual(set(shell.split('|')), set(re.findall(r'"([a-z-]+)"', swift)))

    def test_visual_checks_save_diagnostics_before_failure(self):
        source = SWIFT.read_text()
        helper = source.split('private func requireVisual(', 1)[1]
        self.assertLess(helper.index('add(screenshot)'), helper.index('XCTFail('))
        self.assertLess(helper.index('add(details)'), helper.index('XCTFail('))
        self.assertIn('screenshot.name = "FAILED-', helper)
        self.assertLess(source.index('guard unknownScreens.isEmpty'), source.index('app.launch()'))
        activity = source.split('XCTContext.runActivity', 1)[1].split('private func requireVisual', 1)[0]
        self.assertNotIn('XCTAssert', activity)
        self.assertIn('matchesOrientation(screenshot.image.size', activity)
        self.assertIn('app.descendants(matching: .any)[readyIdentifier]', activity)


if __name__ == '__main__':
    unittest.main(verbosity=2)
