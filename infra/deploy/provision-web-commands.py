#!/usr/bin/env python3
"""CT113 : base neuve pour les intentions BFF, sans accès aux données métier."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

VAULT = Path('/root/drivy-web-commands-bootstrap.json')
ROLES = ('drivy_web_owner', 'drivy_web_runtime', 'drivy_web_commands', 'drivy_web_maintenance')


def psql(sql):
    result = subprocess.run(['runuser', '-u', 'postgres', '--', 'psql', '-X', '-qAt',
        '-v', 'ON_ERROR_STOP=1', '-d', 'postgres'], input=sql, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('Préparation PostgreSQL refusée ; détails privés non affichés.')
    return result.stdout.strip()


def scram(password):
    salt = secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac('sha256', password.encode('ascii'), salt, 4096)
    stored = hashlib.sha256(hmac.new(salted, b'Client Key', hashlib.sha256).digest()).digest()
    server = hmac.new(salted, b'Server Key', hashlib.sha256).digest()
    encode = lambda value: base64.b64encode(value).decode('ascii')
    return f'SCRAM-SHA-256$4096:{encode(salt)}${encode(stored)}:{encode(server)}'


def main():
    if os.geteuid() != 0 or sys.argv[1:] not in (['--check'], ['--apply']):
        raise RuntimeError('Usage root CT113 : provision-web-commands.py --check ou --apply')
    if not 160000 <= int(psql('SHOW server_version_num')) < 170000:
        raise RuntimeError('Cette préparation cible le PostgreSQL 16 du CT113.')
    if psql("SELECT count(*) FROM pg_database WHERE datname IN ('drivy_refonte','drivy_identity')") != '2':
        raise RuntimeError('Les deux bases de la refonte doivent déjà exister.')
    names = ','.join("'" + role + "'" for role in ROLES)
    collisions = psql(f'SELECT rolname FROM pg_roles WHERE rolname IN ({names});'
                      "SELECT datname FROM pg_database WHERE datname='drivy_web';")
    if collisions or VAULT.exists() or VAULT.is_symlink():
        raise RuntimeError('Un objet web ou son coffre existe déjà. Aucun remplacement automatique.')
    if sys.argv[1] == '--check':
        print('Prérequis CT113 vérifiés ; aucune base, rôle ou configuration modifiés.')
        return
    values = {'webMigrationPassword': secrets.token_hex(32), 'webRuntimePassword': secrets.token_hex(32)}
    with os.fdopen(os.open(VAULT, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump(values, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    statements = ["SET log_statement='none';", 'SET log_min_duration_statement=-1;',
                  "SET log_min_error_statement='panic';", 'BEGIN;']
    for role in ('drivy_web_commands', 'drivy_web_maintenance'):
        statements.append(f'CREATE ROLE {role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;')
    for role, key in [('drivy_web_owner', 'webMigrationPassword'), ('drivy_web_runtime', 'webRuntimePassword')]:
        statements.append(f"CREATE ROLE {role} LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD '{scram(values[key])}';")
    statements += [
        'GRANT drivy_web_commands TO drivy_web_owner WITH ADMIN OPTION;',
        'GRANT drivy_web_maintenance TO drivy_web_owner WITH ADMIN OPTION;',
        'GRANT drivy_web_commands TO drivy_web_runtime;', 'COMMIT;',
        "CREATE DATABASE drivy_web OWNER drivy_web_owner ENCODING 'UTF8' TEMPLATE template0;",
        'REVOKE ALL ON DATABASE drivy_web FROM PUBLIC;',
        'GRANT CONNECT ON DATABASE drivy_web TO drivy_web_runtime;'
    ]
    psql('\n'.join(statements))
    print('Base web UTF8 et rôles distincts créés ; coffre root/0600 conservé. Aucun droit métier, HBA ou service modifié.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Préparation web interrompue ; aucun secret affiché.', file=sys.stderr)
        sys.exit(1)
