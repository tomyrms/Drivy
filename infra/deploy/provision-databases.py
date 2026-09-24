#!/usr/bin/env python3
"""CT113 uniquement. Crée des bases neuves ; refuse toute collision et ne remplace rien."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

DESTINATION = Path('/root/drivy-refonte-bootstrap.json')
ROLES = ('drivy_app', 'drivy_refonte_owner', 'drivy_refonte_runtime', 'drivy_identity_owner')
DATABASES = ('drivy_refonte', 'drivy_identity')


def psql(sql):
    result = subprocess.run(['runuser', '-u', 'postgres', '--', 'psql', '-X', '-qAt',
                             '-v', 'ON_ERROR_STOP=1', '-d', 'postgres'],
                            input=sql, text=True, capture_output=True)
    if result.returncode:
        # Ni SQL, ni paramètres, ni erreur serveur potentiellement sensible sur stdout/stderr.
        raise RuntimeError('Étape PostgreSQL refusée. Vérifier localement les objets et droits avant toute reprise.')
    return result.stdout.strip()


def scram(password):
    salt = secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac('sha256', password.encode('ascii'), salt, 4096)
    client = hmac.new(salted, b'Client Key', hashlib.sha256).digest()
    stored = hashlib.sha256(client).digest()
    server = hmac.new(salted, b'Server Key', hashlib.sha256).digest()
    encode = lambda value: base64.b64encode(value).decode('ascii')
    return f'SCRAM-SHA-256$4096:{encode(salt)}${encode(stored)}:{encode(server)}'


def main():
    if os.geteuid() != 0 or sys.argv[1:] != ['--apply']:
        raise RuntimeError('Exécuter comme root dans CT113 : provision-databases.py --apply')
    version = int(psql('SHOW server_version_num'))
    if not 160000 <= version < 170000:
        raise RuntimeError('Cette préparation cible PostgreSQL 16.')
    role_names = ','.join("'" + value + "'" for value in ROLES)
    db_names = ','.join("'" + value + "'" for value in DATABASES)
    collisions = psql(f'SELECT rolname FROM pg_roles WHERE rolname IN ({role_names});'
                      f'SELECT datname FROM pg_database WHERE datname IN ({db_names});')
    if collisions or DESTINATION.exists() or DESTINATION.is_symlink():
        raise RuntimeError('Un objet refonte ou son coffre existe déjà. Aucun remplacement automatique.')
    values = {name: secrets.token_hex(32) for name in
              ('apiMigrationPassword', 'apiRuntimePassword', 'identityDatabasePassword',
               'cursorSecret', 'bootstrapAdminPassword')}
    # Conserver les secrets avant le premier DDL : reprise possible même après une panne partielle.
    with os.fdopen(os.open(DESTINATION, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump(values, stream)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    statements = ["SET log_statement='none';", "SET log_min_duration_statement=-1;",
                  "SET log_min_error_statement='panic';", 'BEGIN;',
                  'CREATE ROLE drivy_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;']
    for role, key in [('drivy_refonte_owner', 'apiMigrationPassword'),
                      ('drivy_refonte_runtime', 'apiRuntimePassword'),
                      ('drivy_identity_owner', 'identityDatabasePassword')]:
        # PostgreSQL reçoit un vérificateur SCRAM, jamais le mot de passe en clair.
        statements.append(f"CREATE ROLE {role} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD '{scram(values[key])}';")
    statements += ['GRANT drivy_app TO drivy_refonte_owner WITH ADMIN OPTION;',
                   'GRANT drivy_app TO drivy_refonte_runtime;', 'COMMIT;',
                   "CREATE DATABASE drivy_refonte OWNER drivy_refonte_owner ENCODING 'UTF8' TEMPLATE template0;",
                   "CREATE DATABASE drivy_identity OWNER drivy_identity_owner ENCODING 'UTF8' TEMPLATE template0;",
                   'REVOKE ALL ON DATABASE drivy_refonte FROM PUBLIC;',
                   'REVOKE ALL ON DATABASE drivy_identity FROM PUBLIC;',
                   'GRANT CONNECT ON DATABASE drivy_refonte TO drivy_refonte_runtime;']
    psql('\n'.join(statements))
    print('Deux bases et quatre rôles refonte créés ; coffre root 0600 conservé sur CT113.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Préparation interrompue ; vérifier localement sans afficher le coffre.', file=sys.stderr)
        sys.exit(1)
