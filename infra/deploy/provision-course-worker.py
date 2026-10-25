#!/usr/bin/env python3
"""CT113 uniquement, après prepare-course-worker.sql. Aucun déploiement implicite.

Ne remplace jamais un coffre ni un mot de passe. Après une interruption, conserver
le coffre et faire examiner l'état PostgreSQL par l'administrateur, sans relancer
une réinitialisation. Les tests mocks ne qualifient pas la base réelle.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

VAULT = Path('/root/drivy-course-worker-bootstrap.json')
LOGIN = 'drivy_refonte_course_worker'
PASSWORD_KEY = 'courseWorkerPassword'
# Options non secrètes appliquées dès la connexion, avant tout SQL sensible.
OPTIONS = {
    'synchronous_commit': 'on', 'search_path': 'pg_catalog',
    'log_statement': 'none', 'log_duration': 'off',
    'log_min_duration_statement': '-1', 'log_min_duration_sample': '-1',
    'log_statement_sample_rate': '0', 'log_transaction_sample_rate': '0',
    'log_min_error_statement': 'panic', 'log_min_messages': 'panic',
    'log_error_verbosity': 'terse', 'log_parameter_max_length': '0',
    'log_parameter_max_length_on_error': '0',
    'debug_print_parse': 'off', 'debug_print_rewritten': 'off', 'debug_print_plan': 'off',
}
GUARD = """
DO $guard$
BEGIN
  IF current_setting('server_version_num')::integer NOT BETWEEN 160000 AND 169999
     OR NOT EXISTS (SELECT FROM pg_database WHERE datname='drivy_refonte') THEN
    RAISE EXCEPTION 'course_worker_environment_invalid';
  END IF;
  IF (SELECT count(*) FROM pg_authid
      WHERE rolname IN ('drivy_course_worker','drivy_refonte_course_worker')) <> 2
     OR EXISTS (SELECT FROM pg_authid
       WHERE rolname IN ('drivy_course_worker','drivy_refonte_course_worker')
       AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolinherit
            OR rolreplication OR rolpassword IS NOT NULL
            OR rolcanlogin <> (rolname='drivy_refonte_course_worker'))) THEN
    RAISE EXCEPTION 'course_worker_roles_invalid_or_password_exists';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_auth_members m
       JOIN pg_roles member ON member.oid=m.member
       JOIN pg_roles parent ON parent.oid=m.roleid
       WHERE member.rolname='drivy_refonte_course_worker'
         AND parent.rolname='drivy_course_worker'
         AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option)
     OR EXISTS (SELECT FROM pg_auth_members m
       JOIN pg_roles member ON member.oid=m.member
       JOIN pg_roles parent ON parent.oid=m.roleid
       WHERE (member.rolname IN ('drivy_course_worker','drivy_refonte_course_worker')
         AND NOT (member.rolname='drivy_refonte_course_worker'
           AND parent.rolname='drivy_course_worker'
           AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option))
         OR parent.rolname='drivy_refonte_course_worker') THEN
    RAISE EXCEPTION 'course_worker_membership_invalid';
  END IF;
  IF NOT has_database_privilege('drivy_refonte_course_worker','drivy_refonte','CONNECT')
     OR EXISTS (SELECT FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba
       WHERE r.rolname IN ('drivy_course_worker','drivy_refonte_course_worker')) THEN
    RAISE EXCEPTION 'course_worker_database_privileges_invalid';
  END IF;
END;
$guard$;
"""


class Refused(RuntimeError):
    """Message fixe pouvant être affiché sans dévoiler les erreurs PostgreSQL."""


def psql(sql):
    options = ' '.join(f'-c {key}={value}' for key, value in OPTIONS.items())
    # Environnement client nettoyé : aucun PGHOST/PGSERVICE/PSQL_ECHO hérité.
    command = ['/usr/sbin/runuser', '-u', 'postgres', '--', '/usr/bin/env', '-i',
               'PATH=/usr/bin:/bin', 'LC_ALL=C', f'PGOPTIONS={options}',
               '/usr/bin/psql', '-X', '-w', '-qAt', '-v', 'ON_ERROR_STOP=1',
               '-h', '/var/run/postgresql', '-p', '5432', '-U', 'postgres', '-d', 'postgres']
    try:
        result = subprocess.run(command, input=sql, text=True, capture_output=True,
                                timeout=30, env={'PATH': '/usr/sbin:/usr/bin:/bin', 'LC_ALL': 'C'})
    except (OSError, subprocess.SubprocessError):
        raise Refused('Préparation PostgreSQL interrompue ; détails privés non affichés.') from None
    if result.returncode:
        raise Refused('Préparation PostgreSQL refusée ; détails privés non affichés.')
    return result.stdout.strip()


def scram(password):
    salt = secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac('sha256', password.encode('ascii'), salt, 4096)
    stored = hashlib.sha256(hmac.new(salted, b'Client Key', hashlib.sha256).digest()).digest()
    server = hmac.new(salted, b'Server Key', hashlib.sha256).digest()
    encode = lambda value: base64.b64encode(value).decode('ascii')
    return f'SCRAM-SHA-256$4096:{encode(salt)}${encode(stored)}:{encode(server)}'


def write_vault(values):
    # O_EXCL refuse aussi un lien symbolique, y compris pendant une course.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    with os.fdopen(os.open(VAULT, flags, 0o600), 'w', encoding='utf-8') as stream:
        os.fchmod(stream.fileno(), 0o600)
        info = os.fstat(stream.fileno())
        if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600 or not stat.S_ISREG(info.st_mode):
            raise Refused('Propriétaire ou permissions du coffre invalides.')
        json.dump(values, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    directory = os.open(VAULT.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def main():
    if getattr(os, 'geteuid', lambda: -1)() != 0 or sys.argv[1:] not in (['--check'], ['--apply']):
        raise Refused('Usage root CT113 : provision-course-worker.py --check ou --apply')
    if os.path.lexists(VAULT):
        raise Refused('Coffre déjà présent. Aucun remplacement ; reprise manuelle nécessaire.')
    psql(GUARD)
    if sys.argv[1] == '--check':
        print('Prérequis du worker cours vérifiés ; aucune modification persistante.')
        return
    # Génération uniquement sur le serveur qui exécute ce script root.
    password = secrets.token_hex(32)
    verifier = scram(password)
    try:
        write_vault({PASSWORD_KEY: password})
        # Réexaminer rôles, memberships et absence de mot de passe juste avant ALTER.
        # Le coffre exclusif empêche deux instances de ce provisionneur de modifier le login.
        # Verrous brefs NOWAIT : aucune modification concurrente des rôles entre
        # le contrôle et ALTER. Si occupé, conserver le coffre pour reprise manuelle.
        sql = ('BEGIN ISOLATION LEVEL READ COMMITTED;\n'
               'LOCK TABLE pg_catalog.pg_authid, pg_catalog.pg_auth_members, '
               'pg_catalog.pg_database IN SHARE ROW EXCLUSIVE MODE NOWAIT;\n' + GUARD +
               f"ALTER ROLE {LOGIN} PASSWORD '{verifier}';\nCOMMIT;\n")
        psql(sql)
    except BaseException:
        # Le coffre peut être incomplet, ou COMMIT effectué malgré une rupture du client.
        # Ne jamais supprimer le coffre ni tenter un nouvel ALTER automatiquement.
        raise Refused('Provisionnement interrompu ou partiel. Conserver le coffre ; '
                      'reprise manuelle nécessaire, aucune réinitialisation automatique.') from None
    print('Mot de passe initial du worker cours créé ; coffre root/0600 synchronisé. Aucun service démarré.')


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        print(str(error) if isinstance(error, Refused) else
              'Préparation interrompue ; reprise manuelle nécessaire, aucun détail privé affiché.', file=sys.stderr)
        sys.exit(1)
