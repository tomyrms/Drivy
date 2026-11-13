"""Tests locaux sans réseau ni PostgreSQL : python -m unittest discover -s infra/deploy -p test_install_api_release.py.

Garantie visée (R01-T01, #453) : une release dont l'équipe d'opérateurs de la plateforme est vide ne remplace jamais le lien `current`,
au lieu de bloquer silencieusement l'ouverture d'école une fois en production.
"""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('install_api_release', Path(__file__).with_name('install-api-release.py'))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)

NODE, NPM, RELEASE = '/runtime/node', '/runtime/npm', Path('/release')
ENVIRONMENT = {'PATH': '/bin'}
MIGRATION = {'MIGRATION_DATABASE_URL': 'postgres://migration.invalid/db'}
RUNTIME = {'DATABASE_URL': 'postgres://runtime.invalid/db', 'CURSOR_SECRET': 'secret-value',
           'SCHOOL_OPENING_OPERATORS_JSON': '[]'}


class ArgumentTests(unittest.TestCase):
    def test_accepts_apply_with_or_without_bootstrap_flag(self):
        self.assertEqual(installer.parse_arguments(['x', '--apply', '/r']), (Path('/r'), False))
        self.assertEqual(installer.parse_arguments(['x', '--apply', '/r', '--bootstrap-operators']), (Path('/r'), True))

    def test_refuses_any_other_shape(self):
        for argv in (['x'], ['x', '--apply'], ['x', '--check', '/r'], ['x', '--apply', '/r', '--other'],
                     ['x', '--apply', '/r', '--bootstrap-operators', 'extra']):
            with self.assertRaises(RuntimeError, msg=argv):
                installer.parse_arguments(argv)


class BootstrapEnvironmentTests(unittest.TestCase):
    def test_passes_only_the_two_bootstrap_keys_never_the_whole_runtime_environment(self):
        values = installer.bootstrap_environment(MIGRATION, RUNTIME)
        self.assertEqual(values, {'SCHOOL_OPENING_OPERATORS_JSON': '[]'})
        self.assertNotIn('DATABASE_URL', values)
        self.assertNotIn('CURSOR_SECRET', values)

    def test_private_bootstrap_list_wins_over_runtime_when_both_exist(self):
        migration = MIGRATION | {'PLATFORM_OPERATORS_BOOTSTRAP_JSON': '[{"x":1}]', 'SCHOOL_OPENING_OPERATORS_JSON': '[{"y":2}]'}
        values = installer.bootstrap_environment(migration, RUNTIME)
        self.assertEqual(values['PLATFORM_OPERATORS_BOOTSTRAP_JSON'], '[{"x":1}]')
        self.assertEqual(values['SCHOOL_OPENING_OPERATORS_JSON'], '[{"y":2}]')


class TeamCheckTests(unittest.TestCase):
    def ensure(self, bootstrap=False, check_code=0, bootstrap_stdout=b'Op\xc3\xa9rateurs de la plateforme : 1 ajout\xc3\xa9(s), 0 d\xc3\xa9j\xc3\xa0 actif(s).\n'):
        with patch.object(installer, 'execute', return_value=bootstrap_stdout) as execute, \
                patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=check_code)) as run, \
                redirect_stdout(io.StringIO()):
            installer.ensure_platform_team(NODE, NPM, RELEASE, ENVIRONMENT, MIGRATION, RUNTIME, bootstrap)
        return execute, run

    def refused(self, **options):
        with self.assertRaises(RuntimeError) as raised:
            self.ensure(**options)
        return str(raised.exception)

    def test_passes_when_an_operator_is_active(self):
        execute, run = self.ensure(check_code=0)
        execute.assert_not_called()
        run.assert_called_once()

    def test_refuses_the_release_when_the_team_is_empty_and_says_how_to_continue(self):
        message = self.refused(check_code=installer.NO_ACTIVE_OPERATOR)
        self.assertIn('Aucun opérateur de plateforme actif', message)
        self.assertIn('--bootstrap-operators', message)
        self.assertIn('Lien courant inchangé', message)

    def test_an_unexpected_failure_is_not_reported_as_an_empty_team(self):
        message = self.refused(check_code=1)
        self.assertNotIn('Aucun opérateur de plateforme actif', message)
        self.assertIn('a échoué', message)
        self.assertNotIn('postgres://', message)

    def test_check_runs_with_the_owner_connection_only(self):
        _, run = self.ensure(check_code=0)
        environment = run.call_args.kwargs['env']
        self.assertEqual(environment['MIGRATION_DATABASE_URL'], MIGRATION['MIGRATION_DATABASE_URL'])
        self.assertNotIn('DATABASE_URL', environment)
        self.assertIn('platform_operator', run.call_args.args[0][-1])
        self.assertIn("status='ACTIVE'", run.call_args.args[0][-1])

    def test_bootstrap_runs_before_the_check_with_the_legacy_option(self):
        order = []
        with patch.object(installer, 'execute', side_effect=lambda *a, **k: order.append('bootstrap') or b'') as execute, \
                patch.object(installer.subprocess, 'run', side_effect=lambda *a, **k: order.append('check') or SimpleNamespace(returncode=0)):
            installer.ensure_platform_team(NODE, NPM, RELEASE, ENVIRONMENT, MIGRATION, RUNTIME, True)
        self.assertEqual(order, ['bootstrap', 'check'])
        arguments, directory, environment, description = execute.call_args.args
        self.assertEqual(arguments[:3], [NPM, 'run', 'operators:bootstrap'])
        self.assertEqual(arguments[-2:], ['--', '--legacy-opening-operators'])
        self.assertEqual(environment['MIGRATION_DATABASE_URL'], MIGRATION['MIGRATION_DATABASE_URL'])
        self.assertNotIn('DATABASE_URL', environment)
        self.assertNotIn('CURSOR_SECRET', environment)
        self.assertEqual(directory, RELEASE)

    def test_still_refuses_when_bootstrap_ran_but_the_team_stays_empty(self):
        self.assertIn('Aucun opérateur de plateforme actif', self.refused(bootstrap=True, check_code=installer.NO_ACTIVE_OPERATOR))

    def test_only_counters_are_printed_by_bootstrap(self):
        with patch('builtins.print') as printed:
            self.ensure(bootstrap=True)
        printed.assert_called_once()
        self.assertNotIn('postgres://', str(printed.call_args))


class WiringTests(unittest.TestCase):
    """main() ne se rejoue pas sans CT114 : l'ordre des étapes est donc gardé sur le texte du script."""

    source = Path(__file__).with_name('install-api-release.py').read_text(encoding='utf-8')

    def test_team_is_verified_after_migration_and_before_prune_and_link_switch(self):
        text = self.source
        migrate = text.index("'migrate'")
        team = text.index('ensure_platform_team(node, npm, release', migrate)
        prune = text.index("'prune'")
        switch = text.index('temporary.symlink_to(release)')
        self.assertLess(migrate, team)
        self.assertLess(team, prune)
        self.assertLess(prune, switch)

    def test_deployment_record_states_the_team_was_verified(self):
        self.assertIn("'platformTeamVerified': True", self.source)


if __name__ == '__main__':
    unittest.main()
