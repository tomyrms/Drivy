import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = r'C:\Program Files\Git\bin\bash.exe' if os.name == 'nt' else 'bash'


class MessagingBuildTests(unittest.TestCase):
    def options(self, flag=None):
        env = {key: value for key, value in os.environ.items() if key != 'DRIVY_MESSAGING_QUALIFICATION'}
        if flag is not None:
            env['DRIVY_MESSAGING_QUALIFICATION'] = flag
        return subprocess.run([BASH, '-c', 'set -euo pipefail; source scripts/ios/messaging-qualification.sh; '
                               'printf "%s\\n" ${messaging_build_options[@]+"${messaging_build_options[@]}"}'],
                              cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf-8', timeout=10)

    def test_default_and_explicit_zero_do_not_enable_messages(self):
        for flag in [None, '0']:
            result = self.options(flag)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), '')

    def test_opt_in_is_one_literal_build_argument(self):
        result = self.options('1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DRIVY_MESSAGING_QUALIFICATION')

    def test_invalid_flag_cannot_silently_enable_or_disable(self):
        for flag in ['true', 'yes', '2', '1\n0', '$(echo unsafe)']:
            with self.subTest(flag=flag):
                self.assertNotEqual(self.options(flag).returncode, 0)


if __name__ == '__main__':
    unittest.main()
