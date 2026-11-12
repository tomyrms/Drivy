"""Tests locaux sans réseau : python -m unittest discover -s infra/deploy -p test_configure_identity_smtp.py."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import unittest
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('configure_smtp', Path(__file__).with_name('configure-identity-smtp.py'))
smtp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smtp)

# Valeurs de test non secrètes, construites à l'exécution pour ne laisser aucun motif d'identifiant dans le dépôt.
SECRET = 'valeur-' + 'de-test-' + '0123456789'
GOOD = {'host': 'relais.exemple-ecole.ch', 'port': 587, 'security': 'starttls', 'auth': True,
        'from': 'identite@exemple-ecole.ch', 'fromDisplayName': 'Drivy', 'user': 'envoi', 'password': SECRET}


def args(**over):
    base = dict(params='p.json', token_file='t.token', keycloak='http://127.0.0.1:8081/identity', realm='drivy',
                apply=False, allow_placeholder=False)
    base.update(over)
    return SimpleNamespace(**base)


class ValidateTests(unittest.TestCase):
    def test_valid_starttls_with_auth(self):
        result = smtp.validate(dict(GOOD))
        self.assertEqual(result['starttls'], 'true')
        self.assertEqual(result['ssl'], 'false')
        self.assertEqual(result['auth'], 'true')
        self.assertEqual(result['port'], '587')

    def test_valid_ssl_without_auth(self):
        result = smtp.validate({'host': 'relais.exemple-ecole.ch', 'port': 465, 'security': 'ssl', 'auth': False,
                                'from': 'identite@exemple-ecole.ch'})
        self.assertEqual((result['ssl'], result['starttls'], result['auth']), ('true', 'false', 'false'))
        self.assertNotIn('password', result)

    def test_rejects_placeholder_hosts_and_senders(self):
        for host in ('localhost', 'smtp.example.com', 'mail.invalid', 'relais.test', 'example.org'):
            with self.subTest(host=host), self.assertRaises(smtp.ConfigError):
                smtp.validate({**GOOD, 'host': host})
        with self.assertRaises(smtp.ConfigError):
            smtp.validate({**GOOD, 'from': 'identite@exemple.invalid'})
        # Recette synthétique : explicitement permise.
        smtp.validate({**GOOD, 'host': 'host.invalid', 'from': 'identite@exemple.invalid'}, allow_placeholder=True)

    def test_rejects_bad_shapes(self):
        cases = [
            {**GOOD, 'host': 'https://relais.exemple-ecole.ch'},
            {**GOOD, 'host': 'relais.exemple-ecole.ch/chemin'},
            {**GOOD, 'port': 0}, {**GOOD, 'port': 70000}, {**GOOD, 'port': '587'}, {**GOOD, 'port': True},
            {**GOOD, 'security': 'tls'}, {**GOOD, 'auth': 'oui'},
            {**GOOD, 'from': 'pas-une-adresse'}, {**GOOD, 'replyTo': 'invalide'},
            {**GOOD, 'fromDisplayName': 'a\nb'}, {**GOOD, 'inconnu': 1},
            {**GOOD, 'user': ''}, {k: v for k, v in GOOD.items() if k != 'password'},
        ]
        for case in cases:
            with self.subTest(case=sorted(case)), self.assertRaises(smtp.ConfigError):
                smtp.validate(dict(case))
        with self.assertRaises(smtp.ConfigError):
            smtp.validate([])

    def test_auth_without_encryption_only_on_loopback(self):
        with self.assertRaises(smtp.ConfigError):
            smtp.validate({**GOOD, 'security': 'none'})
        smtp.validate({**GOOD, 'security': 'none', 'host': '127.0.0.1'})

    def test_credentials_refused_when_auth_is_false(self):
        with self.assertRaises(smtp.ConfigError):
            smtp.validate({**GOOD, 'auth': False})

    def test_errors_never_quote_values(self):
        for case in ({**GOOD, 'host': 'https://secret-host-' + SECRET}, {**GOOD, 'port': 99999}, {**GOOD, 'from': SECRET}):
            with self.assertRaises(smtp.ConfigError) as caught:
                smtp.validate(case)
            self.assertNotIn(SECRET, str(caught.exception))

    def test_redaction_hides_user_and_password(self):
        shown = json.dumps(smtp.redacted(smtp.validate(dict(GOOD))))
        self.assertNotIn(SECRET, shown)
        self.assertNotIn('envoi', shown)
        self.assertIn('(fourni)', shown)


class FileTests(unittest.TestCase):
    def fake_stat(self, mode, uid=0):
        return SimpleNamespace(st_mode=mode, st_uid=uid)

    def test_refuses_group_readable_symlink_and_foreign_owner(self):
        for mode in (stat.S_IFREG | 0o640, stat.S_IFLNK | 0o600, stat.S_IFDIR | 0o600):
            with self.subTest(mode=oct(mode)), patch.object(smtp.os, 'lstat', return_value=self.fake_stat(mode)), \
                    self.assertRaises(smtp.ConfigError):
                smtp.read_private_file('x')
        if hasattr(smtp.os, 'geteuid'):
            with patch.object(smtp.os, 'lstat', return_value=self.fake_stat(stat.S_IFREG | 0o600, uid=smtp.os.geteuid() + 1)), \
                    self.assertRaises(smtp.ConfigError):
                smtp.read_private_file('x')

    def test_reads_private_regular_file(self):
        owner = smtp.os.geteuid() if hasattr(smtp.os, 'geteuid') else 0
        with patch.object(smtp.os, 'lstat', return_value=self.fake_stat(stat.S_IFREG | 0o600, uid=owner)), \
                patch.object(smtp.Path, 'read_text', return_value='{"a":1}'):
            self.assertEqual(smtp.read_private_file('x'), '{"a":1}')


class RunTests(unittest.TestCase):
    def run_main(self, arguments, files, requests):
        """files : chemin -> contenu ; requests : réponses (statut, corps) servies dans l'ordre."""
        sent = []

        def fake_request(base, method, path, token, body=None, opener=None):
            sent.append((method, path, body))
            return requests.pop(0)

        out, err = io.StringIO(), io.StringIO()
        with patch.object(smtp, 'read_private_file', side_effect=lambda path: files[path]), \
                patch.object(smtp, 'admin_request', side_effect=fake_request), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = smtp.run(arguments)
        return code, out.getvalue(), err.getvalue(), sent

    def test_dry_run_writes_nothing_and_hides_secret(self):
        code, out, err, sent = self.run_main(args(), {'p.json': json.dumps(GOOD)}, [])
        self.assertEqual((code, sent), (0, []))
        self.assertNotIn(SECRET, out + err)
        self.assertIn('Simulation', out)

    def test_apply_writes_only_smtp_and_keeps_recovery_closed(self):
        code, out, err, sent = self.run_main(args(apply=True), {'p.json': json.dumps(GOOD), 't.token': 'jeton\n'},
                                             [(200, {'resetPasswordAllowed': False}), (204, None)])
        self.assertEqual(code, 0, err)
        self.assertEqual([s[0] for s in sent], ['GET', 'PUT'])
        self.assertEqual(sent[1][2], {'smtpServer': smtp.validate(dict(GOOD))})
        self.assertNotIn('resetPasswordAllowed', sent[1][2])
        self.assertNotIn(SECRET, out + err)
        self.assertIn('resetPasswordAllowed est resté faux', out)

    def test_apply_refuses_when_recovery_already_open(self):
        code, _, err, sent = self.run_main(args(apply=True), {'p.json': json.dumps(GOOD), 't.token': 'jeton'},
                                           [(200, {'resetPasswordAllowed': True})])
        self.assertEqual(code, 1)
        self.assertEqual([s[0] for s in sent], ['GET'])
        self.assertIn('déjà autorisée', err)

    def test_apply_stops_when_realm_unreadable_or_write_fails(self):
        files = {'p.json': json.dumps(GOOD), 't.token': 'jeton'}
        code, _, _, sent = self.run_main(args(apply=True), files, [(0, None)])
        self.assertEqual((code, len(sent)), (1, 1))
        code, _, err, sent = self.run_main(args(apply=True), files, [(200, {'resetPasswordAllowed': False}), (403, None)])
        self.assertEqual((code, len(sent)), (1, 2))
        self.assertNotIn(SECRET, err)

    def test_invalid_parameters_stop_before_any_request(self):
        code, _, err, sent = self.run_main(args(apply=True), {'p.json': json.dumps({**GOOD, 'port': 0})}, [])
        self.assertEqual((code, sent), (2, []))
        self.assertNotIn(SECRET, err)
        code, _, err, sent = self.run_main(args(apply=True), {'p.json': '{pas du json'}, [])
        self.assertEqual((code, sent), (2, []))

    def test_bad_keycloak_url_is_refused(self):
        code, _, _, sent = self.run_main(args(apply=True, keycloak='ftp://hote'), {'p.json': json.dumps(GOOD), 't.token': 'j'}, [])
        self.assertEqual((code, sent), (2, []))


if __name__ == '__main__':
    unittest.main()
