"""Sélection des suites Ubuntu par fichiers modifiés : la sûreté prime, le doute lance tout."""
from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('changed_domains', ROOT / 'scripts/qualification/changed_domains.py')
changed_domains = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changed_domains)
classify = changed_domains.classify
CONCEPTION = changed_domains.CONCEPTION


class ClassificationTests(unittest.TestCase):
    def decide(self, *files):
        decision = classify(list(files))
        return decision['server'], decision['web']

    def test_documents_and_ios_alone_skip_server_and_web(self):
        for files in [['docs/implementation/STATUS.md'], ['apps/ios/Drivy/Home.swift'], ['README.md'], ['DESIGN.md', 'AGENTS.md'],
                      ['apps/ios/DrivyTests/A.swift', 'docs/x.md', 'scripts/ios/test-simulator.sh'],
                      [CONCEPTION + '01-produit/regle.md'], ['.claude/skills/x/SKILL.md'], ['design-plans/a.md'],
                      ['prototypes/messaging-crypto/src/lib.rs']]:
            with self.subTest(files=files):
                self.assertEqual(self.decide(*files), (False, False))

    def test_web_alone_skips_the_server_but_the_server_always_triggers_the_web(self):
        self.assertEqual(self.decide('apps/web/client/app.tsx'), (False, True))
        # apps/web/test/learner-course-facts.test.ts lit apps/api/contracts.
        self.assertEqual(self.decide('apps/api/contracts/learner-course-facts.json'), (True, True))
        self.assertEqual(self.decide('apps/api/src/server.ts'), (True, True))

    def test_transverse_changes_always_run_everything(self):
        for path in ['.github/workflows/refonte-checks.yml', 'scripts/qualification/evidence.py', 'package.json',
                     'package-lock.json', 'apps/web/package-lock.json', 'infra/dev/package-lock.json', '.node-version',
                     'infra/deploy/runtime-lock.json', 'apps/ios/Package.resolved', CONCEPTION + '04-technique/openapi.yaml',
                     'apps/api/migrations/059_example.sql']:
            with self.subTest(path=path):
                self.assertEqual(self.decide(path), (True, True))
                self.assertEqual(self.decide('docs/a.md', path), (True, True))

    def test_unknown_or_unclassified_paths_run_everything(self):
        for path in ['infra/deploy/caddy-refonte.caddy', 'scripts/dev/setup.ts', 'compose.yaml', 'unknown/file.bin']:
            with self.subTest(path=path):
                self.assertEqual(self.decide(path), (True, True))

    def test_one_relevant_file_among_foreign_ones_runs_the_suite(self):
        self.assertEqual(self.decide('docs/a.md', 'apps/ios/A.swift', 'apps/web/client/b.ts'), (False, True))
        self.assertEqual(self.decide('docs/a.md', 'apps/api/src/b.ts'), (True, True))

    def test_empty_or_blank_input_runs_everything(self):
        self.assertEqual(self.decide(), (True, True))
        self.assertEqual(self.decide('', '  '), (True, True))

    def test_windows_separators_are_normalised(self):
        self.assertEqual(self.decide('docs\\a.md'), (False, False))
        self.assertEqual(self.decide('.github\\workflows\\x.yml'), (True, True))

    def test_the_documentation_directory_is_not_a_server_input_except_the_contract(self):
        self.assertEqual(self.decide(CONCEPTION + 'annexes/verifier-documentation.py'), (False, False))
        self.assertEqual(self.decide(CONCEPTION + '04-technique/openapi.yaml'), (True, True))


class GitSelectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='drivy-domains-')
        self.addCleanup(self.directory.cleanup)
        # Les sorties du job ne doivent pas se retrouver committées dans le dépôt d'essai.
        self.outputs = tempfile.TemporaryDirectory(prefix='drivy-domains-out-')
        self.addCleanup(self.outputs.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.git('init', '-q', '-b', 'master')

    def git(self, *args):
        return subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false', *args],
                              cwd=self.root, check=True, text=True, capture_output=True).stdout.strip()

    def commit(self, path, content='x'):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        self.git('add', '-A')
        self.git('commit', '-q', '-m', path)
        return self.git('rev-parse', 'HEAD')

    def run_main(self, **environment):
        output = pathlib.Path(self.outputs.name) / 'github-output.txt'
        summary = pathlib.Path(self.outputs.name) / 'github-summary.txt'
        for path in (output, summary):
            path.unlink(missing_ok=True)
        env = {key: value for key, value in os.environ.items() if key not in {'SELECT_BY_PATHS', 'BASE_SHA'}}
        env.update(GITHUB_OUTPUT=str(output), GITHUB_STEP_SUMMARY=str(summary), **environment)
        code = subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/qualification/changed_domains.py')], cwd=self.root, env=env,
                              text=True, capture_output=True, encoding='utf-8')
        self.assertEqual(code.returncode, 0, code.stderr)
        values = dict(line.split('=', 1) for line in output.read_text(encoding='utf-8').split())
        return values

    def test_disabled_selection_runs_everything(self):
        self.commit('docs/a.md')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='false'), dict(server='true', web='true'))
        self.assertEqual(self.run_main(), dict(server='true', web='true'))

    def test_push_range_is_read_from_the_base_sha(self):
        first = self.commit('apps/api/src/a.ts')
        self.commit('docs/b.md')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA=first), dict(server='false', web='false'))
        before = self.commit('apps/ios/Drivy/C.swift')
        self.commit('apps/web/client/d.ts')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA=before), dict(server='false', web='true'))
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA=first), dict(server='false', web='true'))

    def test_renames_count_on_both_sides(self):
        first = self.commit('apps/api/src/a.ts')
        (self.root / 'docs').mkdir()
        self.git('mv', 'apps/api/src/a.ts', 'docs/a.md')
        self.git('commit', '-q', '-m', 'rename')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA=first), dict(server='true', web='true'))

    def test_unreadable_base_without_master_runs_everything(self):
        self.commit('docs/a.md')
        for base in ['', '0' * 40, 'f' * 40]:
            with self.subTest(base=base):
                self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA=base), dict(server='true', web='true'))

    def test_new_branch_falls_back_to_the_merge_base_with_origin_master(self):
        self.commit('apps/api/src/a.ts')
        self.git('update-ref', 'refs/remotes/origin/master', 'HEAD')
        self.git('checkout', '-q', '-b', 'claude/feature')
        self.commit('docs/b.md')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA='0' * 40), dict(server='false', web='false'))
        self.commit('apps/api/src/c.ts')
        self.assertEqual(self.run_main(SELECT_BY_PATHS='true', BASE_SHA='0' * 40), dict(server='true', web='true'))


if __name__ == '__main__':
    unittest.main()
