import importlib.util
import copy
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / 'ios/configure-relay-tests.py'
spec = importlib.util.spec_from_file_location('relay_plan', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ROOT = Path(__file__).resolve().parents[2]
BASH = r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else 'bash'


class RelayPlanTests(unittest.TestCase):
    def test_modern_plan_preserves_other_targets_and_variables(self):
        target = dict(BlueprintName='DrivyTests', TestBundlePath='__TESTROOT__/test.xctest', EnvironmentVariables={'KEEP': 'yes'})
        ui = dict(BlueprintName='DrivyUITests')
        source = dict(TestConfigurations=[dict(TestTargets=[target, ui])])
        result = module.configure(source, 'https://127.0.0.1:18443')
        changed = result['TestConfigurations'][0]['TestTargets'][0]
        self.assertEqual(changed['EnvironmentVariables'], {'KEEP': 'yes', 'DRIVY_RELAY_QUALIFICATION_URL': 'https://127.0.0.1:18443'})
        self.assertEqual(changed['TestBundlePath'], target['TestBundlePath'])
        self.assertEqual(result['TestConfigurations'][0]['TestTargets'][1], ui)
        self.assertEqual(target['EnvironmentVariables'], {'KEEP': 'yes'})

    def test_legacy_plan_and_missing_target(self):
        result = module.configure({'DrivyTests': {}}, 'https://localhost:18443')
        self.assertIn('DRIVY_RELAY_QUALIFICATION_URL', result['DrivyTests']['EnvironmentVariables'])
        for source in [{}, {'TestConfigurations': []}, {'TestConfigurations': [dict(IsEnabled=False, TestTargets=[dict(BlueprintName='DrivyTests')])]}]:
            with self.assertRaises(ValueError):
                module.configure(source, 'https://localhost:18443')

    def test_rejects_remote_cleartext_and_credential_urls(self):
        for url in ['http://localhost:18443', 'https://real.example:18443', 'https://localhost',
                    'https://user:secret@localhost:18443', 'https://localhost:18443/path',
                    'https://localhost:18443?token=x', 'https://localhost:18443#x']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                module.configure({'DrivyTests': {}}, url)


class RelaySelectionTests(unittest.TestCase):
    def temporary_root(self):
        temporary = tempfile.TemporaryDirectory(prefix='drivy-relay-script-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        shutil.copytree(ROOT / 'scripts/ios', root / 'scripts/ios', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(ROOT / 'apps/ios/DrivyUITests', root / 'apps/ios/DrivyUITests')
        (root / 'apps/ios/DrivyTests').mkdir(parents=True)
        (root / 'apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift').write_text('// marker')
        return root

    def run_bash(self, root, command, **overrides):
        environment = {key: value for key, value in os.environ.items() if not key.startswith('DRIVY_IOS_')}
        environment.update(overrides)
        return subprocess.run([BASH, '-c', command], cwd=root, env=environment,
                              capture_output=True, text=True, encoding='utf-8', timeout=15)

    def test_service_required_for_full_and_all_but_not_gps_visual_or_ui(self):
        root = self.temporary_root()
        cases = [(1, {}), (1, dict(DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='all')),
                 (0, dict(DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='gps')),
                 (0, dict(DRIVY_IOS_VISUAL_ONLY='1')),
                 (0, dict(DRIVY_IOS_UI_TEST_SUITE='VisualOrientationTests'))]
        for expected, environment in cases:
            result = self.run_bash(root, 'set -euo pipefail; source scripts/ios/test-selection.sh; echo "$relay_required"', **environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(expected))
        (root / 'apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift').unlink()
        result = self.run_bash(root, 'source scripts/ios/test-selection.sh; echo "$relay_required"')
        self.assertEqual(result.stdout.strip(), '0')

    def test_real_tls_fixture_chain_hostname_and_usage(self):
        root = self.temporary_root()
        script = (ROOT / 'scripts/ios/relay-qualification.sh').read_text(encoding='utf-8')
        block = script.split('  cat > "$relay_directory/tls.cnf"', 1)[1].split('  relay_start_server\n', 1)[0]
        command = 'set -euo pipefail; export MSYS2_ARG_CONV_EXCL=/CN=localhost; relay_directory="$PWD"\n'
        command += 'cat > "$relay_directory/tls.cnf"' + block
        command += '\nopenssl verify -CAfile ca.crt -purpose sslserver -verify_hostname localhost server.crt\n'
        command += 'openssl verify -CAfile ca.crt -purpose sslserver -verify_ip 127.0.0.1 server.crt\n'
        result = self.run_bash(root, command)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('server.crt: OK'), 2)

    def test_simulator_uses_injected_plan_and_trust_for_both_devices(self):
        root = self.temporary_root()
        (root / 'scripts/ios/relay-qualification.sh').write_text('''
relay_url=https://127.0.0.1:18443
relay_start() { echo RELAY_START; }
relay_trust_simulator() { echo "TRUST_$1"; }
relay_reset_fixture() { echo RELAY_RESET; }
''', encoding='utf-8')
        harness = r'''
set -euo pipefail
xcodebuild() { printf 'xcodebuild'; printf ' <%s>' "$@"; printf '\n'; return "${MOCK_TEST_STATUS:-0}"; }
xcrun() { printf 'xcrun'; printf ' <%s>' "$@"; printf '\n'; }
python3() { if [[ "$*" == *configure-relay-tests.py* ]]; then echo PLAN; elif [[ "$*" == *'startswith("iPhone")'* ]]; then echo PHONE; else echo IPAD; fi; }
node() { echo node-version; }
postgres() { echo postgres-version; }
openssl() { echo openssl-version; }
sleep() { :; }
export -f xcodebuild xcrun python3 node postgres openssl sleep
bash scripts/ios/test-simulator.sh
'''
        result = self.run_bash(root, harness)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('RELAY_START', result.stdout)
        self.assertIn('TRUST_PHONE', result.stdout)
        self.assertIn('TRUST_IPAD', result.stdout)
        self.assertIn('RELAY_RESET', result.stdout)
        self.assertEqual(result.stdout.count('<-xctestrun> <PLAN>'), 2)
        self.assertIn('<-only-testing:DrivyTests/MatrixMessagingRelayIntegrationTests>', result.stdout)
        result = self.run_bash(root, harness, DRIVY_IOS_UNIT_ONLY='1', DRIVY_IOS_UNIT_TEST_SCOPE='all', MOCK_TEST_STATUS='65')
        self.assertEqual(result.returncode, 65)
        self.assertIn('RELAY_START', result.stdout)
        self.assertNotIn('TRUST_IPAD', result.stdout)


class RelayExecutionEvidenceTests(unittest.TestCase):
    def fixture(self):
        spec = importlib.util.spec_from_file_location('relay_evidence', ROOT / 'scripts/messaging-relay-qualification.py')
        evidence = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(evidence)
        summary = dict(totalTestCount=1, passedTests=1, failedTests=0, skippedTests=0, expectedFailures=0, result='Passed')
        case = dict(nodeType='Test Case', name=evidence.METHOD + '()', result='Passed')
        suite = dict(nodeType='Test Suite', name=evidence.SUITE, children=[case])
        tree = dict(testNodes=[dict(nodeType='Unit test bundle', name='DrivyTests', children=[suite])])
        return evidence, summary, tree

    def test_accepts_exact_relay_scenario(self):
        evidence, summary, tree = self.fixture()
        evidence.validate(summary, tree)

    def test_rejects_missing_skipped_failed_duplicate_or_wrong_relay(self):
        evidence, summary, tree = self.fixture()
        with self.assertRaises(ValueError):
            evidence.validate(summary, {'testNodes': []})
        for result in ['Skipped', 'Failed', 'Expected Failure']:
            changed = copy.deepcopy(tree)
            changed['testNodes'][0]['children'][0]['children'][0]['result'] = result
            with self.assertRaises(ValueError):
                evidence.validate(summary, changed)
        changed = copy.deepcopy(tree)
        cases = changed['testNodes'][0]['children'][0]['children']
        cases.append(copy.deepcopy(cases[0]))
        with self.assertRaises(ValueError):
            evidence.validate(summary, changed)
        for key, value in [('totalTestCount', 0), ('skippedTests', 1), ('result', 'Failed')]:
            with self.assertRaises(ValueError):
                evidence.validate({**summary, key: value}, tree)
        changed = copy.deepcopy(tree)
        changed['testNodes'][0]['name'] = 'DrivyUITests'
        with self.assertRaises(ValueError):
            evidence.validate(summary, changed)
        changed = copy.deepcopy(tree)
        changed['testNodes'][0]['children'][0]['children'][0]['name'] = 'testMock()'
        with self.assertRaises(ValueError):
            evidence.validate(summary, changed)


if __name__ == '__main__':
    unittest.main()
