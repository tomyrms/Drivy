"""Tests locaux sans réseau ni PostgreSQL : python -m unittest discover -s infra/deploy -p test_provision_course_worker.py."""
import base64
import hashlib
import hmac
import importlib.util
import io
from pathlib import Path
import stat
import subprocess
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import Mock, call, mock_open, patch

SPEC = importlib.util.spec_from_file_location('course_provision', Path(__file__).with_name('provision-course-worker.py'))
provision = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provision)


class ProvisionTests(unittest.TestCase):
    def setUp(self):
        self.patches = [
            patch.object(provision.os, 'geteuid', return_value=0, create=True),
            patch.object(provision.sys, 'argv', ['provision-course-worker.py', '--apply']),
            patch.object(provision.os.path, 'lexists', return_value=False),
            patch.object(provision, 'psql', return_value=''),
            patch.object(provision, 'write_vault'),
            patch.object(provision.secrets, 'token_hex', return_value='a' * 64),
            patch.object(provision, 'scram', return_value='SCRAM-SHA-256$mock'),
        ]
        (self.uid, self.argv, self.exists, self.psql, self.vault,
         self.random, self.scram) = [p.start() for p in self.patches]
        for p in self.patches:
            self.addCleanup(p.stop)
        self.output = io.StringIO()
        redirect = redirect_stdout(self.output)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)

    def test_check_is_read_only_and_does_not_generate_secret(self):
        provision.sys.argv[1] = '--check'
        provision.main()
        self.psql.assert_called_once_with(provision.GUARD)
        self.vault.assert_not_called()
        self.random.assert_not_called()
        self.assertNotIn('ALTER ROLE', self.psql.call_args.args[0])

    def test_apply_persists_before_alter_and_rechecks_guard(self):
        order = Mock()
        order.attach_mock(self.psql, 'psql')
        order.attach_mock(self.vault, 'vault')
        provision.main()
        self.assertEqual([c[0] for c in order.mock_calls], ['psql', 'vault', 'psql'])
        self.vault.assert_called_once_with({'courseWorkerPassword': 'a' * 64})
        sql = self.psql.call_args.args[0]
        self.assertTrue(sql.startswith('BEGIN ISOLATION LEVEL READ COMMITTED;\n'))
        self.assertIn('SHARE ROW EXCLUSIVE MODE NOWAIT;', sql)
        self.assertLess(sql.index('LOCK TABLE pg_catalog.pg_authid'), sql.index(provision.GUARD))
        self.assertLess(sql.index(provision.GUARD), sql.index('ALTER ROLE'))
        self.assertTrue(sql.endswith('COMMIT;\n'))
        self.assertIn("ALTER ROLE drivy_refonte_course_worker PASSWORD 'SCRAM-SHA-256$mock'", sql)
        self.assertNotIn('a' * 64, sql)
        self.assertNotIn('a' * 64, self.output.getvalue())
        self.assertNotIn('SCRAM', self.output.getvalue())

    def test_existing_vault_or_dangling_link_refuses_without_db_access(self):
        self.exists.return_value = True
        with self.assertRaisesRegex(provision.Refused, 'reprise manuelle'):
            provision.main()
        self.exists.assert_called_once_with(provision.VAULT)
        self.psql.assert_not_called()
        self.vault.assert_not_called()

    def test_nonroot_or_invalid_mode_refuses(self):
        for uid, argv in [(1000, ['--apply']), (0, []), (0, ['--reset']), (0, ['--apply', '--force'])]:
            with self.subTest(uid=uid, argv=argv):
                self.uid.return_value = uid
                provision.sys.argv = ['script'] + argv
                with self.assertRaisesRegex(provision.Refused, 'Usage root'):
                    provision.main()
        self.psql.assert_not_called()

    def test_guard_refusal_never_generates_or_writes_password(self):
        self.psql.side_effect = provision.Refused('Préparation PostgreSQL refusée')
        with self.assertRaises(provision.Refused):
            provision.main()
        self.vault.assert_not_called()
        self.random.assert_not_called()

    def test_vault_failure_never_alters_and_requires_manual_recovery(self):
        self.vault.side_effect = OSError('private detail')
        with self.assertRaisesRegex(provision.Refused, 'reprise manuelle') as caught:
            provision.main()
        self.assertNotIn('private detail', str(caught.exception))
        self.psql.assert_called_once_with(provision.GUARD)
        self.assertNotIn('créé', self.output.getvalue())

    def test_db_failure_after_vault_never_retries(self):
        self.psql.side_effect = ['', provision.Refused('private detail')]
        with self.assertRaisesRegex(provision.Refused, 'partiel') as caught:
            provision.main()
        self.assertNotIn('private detail', str(caught.exception))
        self.assertEqual(self.psql.call_count, 2)
        self.vault.assert_called_once()
        self.assertEqual(self.output.getvalue(), '')

    def test_guard_covers_constraints_without_selecting_password_value(self):
        for fragment in ('rolpassword IS NOT NULL', 'rolsuper', 'rolbypassrls', 'rolcreatedb',
                         'rolcreaterole', 'rolinherit', 'rolreplication', 'rolcanlogin',
                         'm.set_option', 'NOT m.inherit_option', 'NOT m.admin_option',
                         'has_database_privilege', "parent.rolname='drivy_refonte_course_worker'"):
            self.assertIn(fragment, provision.GUARD)
        self.assertNotIn('SELECT rolpassword', provision.GUARD)


class PrimitiveTests(unittest.TestCase):
    def test_scram_matches_independent_derivation(self):
        salt = bytes(range(16))
        with patch.object(provision.secrets, 'token_bytes', return_value=salt):
            verifier = provision.scram('test-password')
        algorithm, salt_field, key_field = verifier.split('$')
        rounds, encoded_salt = salt_field.split(':')
        stored, server = [base64.b64decode(part) for part in key_field.split(':')]
        self.assertEqual(algorithm, 'SCRAM-SHA-256')
        self.assertEqual(int(rounds), 4096)
        self.assertEqual(base64.b64decode(encoded_salt), salt)
        salted = hashlib.pbkdf2_hmac('sha256', b'test-password', salt, 4096)
        self.assertEqual(stored, hashlib.sha256(hmac.digest(salted, b'Client Key', 'sha256')).digest())
        self.assertEqual(server, hmac.digest(salted, b'Server Key', 'sha256'))

    def test_subprocess_has_no_secret_argv_or_env_and_captures_output(self):
        with patch.object(provision.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='ok\n')) as run:
            self.assertEqual(provision.psql('private sql'), 'ok')
        args, kwargs = run.call_args
        self.assertNotIn('private sql', repr(args))
        self.assertNotIn('private sql', repr(kwargs['env']))
        self.assertEqual(kwargs['input'], 'private sql')
        self.assertTrue(kwargs['capture_output'])
        self.assertIn('-X', args[0])
        self.assertIn('-w', args[0])
        self.assertIn('/var/run/postgresql', args[0])
        for option in ('log_statement=none', 'log_duration=off', 'log_min_error_statement=panic',
                       'log_min_duration_statement=-1', 'log_min_duration_sample=-1',
                       'log_transaction_sample_rate=0', 'log_min_messages=panic'):
            self.assertIn(option, ' '.join(args[0]))

    def test_subprocess_failures_are_redacted(self):
        for result, error in [(SimpleNamespace(returncode=1, stdout='secret', stderr='secret'), None),
                              (None, subprocess.TimeoutExpired('secret', 30, output='secret')),
                              (None, OSError('secret'))]:
            with self.subTest(error=type(error).__name__):
                with patch.object(provision.subprocess, 'run', return_value=result, side_effect=error):
                    with self.assertRaises(provision.Refused) as caught:
                        provision.psql('secret')
                    self.assertNotIn('secret', str(caught.exception))

    def test_vault_exclusive_root_0600_and_both_fsyncs(self):
        file = mock_open()
        file.return_value.fileno.return_value = 10
        info = SimpleNamespace(st_uid=0, st_mode=stat.S_IFREG | 0o600)
        with patch.object(provision.os, 'O_NOFOLLOW', 0x20000, create=True), \
             patch.object(provision.os, 'O_DIRECTORY', 0x10000, create=True), \
             patch.object(provision.os, 'open', side_effect=[10, 11]) as opened, \
             patch.object(provision.os, 'fdopen', file), \
             patch.object(provision.os, 'fchmod', create=True) as chmod, \
             patch.object(provision.os, 'fstat', return_value=info), \
             patch.object(provision.os, 'fsync') as sync, \
             patch.object(provision.os, 'close') as close:
            provision.write_vault({'courseWorkerPassword': 'synthetic'})
        flags = opened.call_args_list[0].args[1]
        self.assertTrue(flags & provision.os.O_EXCL)
        self.assertTrue(flags & provision.os.O_CREAT)
        self.assertEqual(opened.call_args_list[0].args[2], 0o600)
        chmod.assert_called_once_with(10, 0o600)
        self.assertEqual(sync.call_args_list, [call(10), call(11)])
        close.assert_called_once_with(11)
        file.return_value.flush.assert_called_once()

    def test_exclusive_open_collision_does_not_write(self):
        with patch.object(provision.os, 'O_NOFOLLOW', 0x20000, create=True), \
             patch.object(provision.os, 'open', side_effect=FileExistsError), \
             patch.object(provision.os, 'fdopen') as fdopen:
            with self.assertRaises(FileExistsError):
                provision.write_vault({'courseWorkerPassword': 'synthetic'})
            fdopen.assert_not_called()


if __name__ == '__main__':
    unittest.main()
