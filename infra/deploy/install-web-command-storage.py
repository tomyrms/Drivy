#!/usr/bin/env python3
"""CT114 : prépare les accès privés au journal BFF, sans migrer ni redémarrer."""
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import sys
from urllib.parse import urlencode

ETC = Path('/etc/drivy-refonte')


def private_root_file(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('Fichier privé absent ou lien symbolique interdit.')
    stat = path.stat()
    if stat.st_uid != 0 or stat.st_mode & 0o077:
        raise RuntimeError('Le fichier privé doit appartenir à root et être en mode 0600.')
    return path.read_text()


def atomic_write(path, content, mode=0o600, group=0):
    if path.is_symlink():
        raise RuntimeError('Lien de configuration interdit.')
    temporary = path.with_name(path.name + '.next')
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode), 'w') as stream:
        os.fchown(stream.fileno(), 0, group)
        os.fchmod(stream.fileno(), mode)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3 or sys.argv[1] != '--apply':
        raise RuntimeError('Usage root CT114 : install-web-command-storage.py --apply /root/drivy-web-commands-bootstrap.json')
    vault = Path(sys.argv[2])
    if vault.parent != Path('/root'):
        raise RuntimeError('Le coffre doit être placé dans /root.')
    values = json.loads(private_root_file(vault))
    if set(values) != {'webMigrationPassword', 'webRuntimePassword'} or any(
            not isinstance(value, str) or not re.fullmatch('[a-f0-9]{64}', value) for value in values.values()):
        raise RuntimeError('Coffre du journal web invalide.')
    account = pwd.getpwnam('drivy-web')
    if account.pw_uid == 0 or account.pw_shell not in ('/usr/sbin/nologin', '/sbin/nologin'):
        raise RuntimeError('Compte de service web incorrect.')
    ca = ETC / 'db-ca.crt'
    if not ca.is_file() or ca.is_symlink():
        raise RuntimeError('Certificat PostgreSQL privé de confiance absent.')
    current = private_root_file(ETC / 'web.env')
    config = dict(line.split('=', 1) for line in current.splitlines() if line and not line.startswith('#'))
    if config.get('NODE_ENV') != 'production' or config.get('WEB_ORIGIN') != 'https://drivy.shulker.ch':
        raise RuntimeError('Le service web existant ne correspond pas à cette installation.')
    query = urlencode({'sslmode': 'verify-full', 'sslrootcert': str(ca)})
    connection = lambda role, key: 'postgresql://' + role + ':' + values[key] + '@drivy-db.tailb60275.ts.net:5432/drivy_web?' + query
    keyring_path = ETC / 'web-command-keys.json'
    if keyring_path.exists() or keyring_path.is_symlink():
        if keyring_path.is_symlink() or not keyring_path.is_file():
            raise RuntimeError('Keyring invalide.')
        stat = keyring_path.stat()
        if stat.st_uid != 0 or stat.st_gid != account.pw_gid or stat.st_mode & 0o777 != 0o640:
            raise RuntimeError('Permissions du keyring existant incorrectes ; aucune clé remplacée.')
        keyring = json.loads(keyring_path.read_text())
        keys = keyring.get('keys', {})
        if not isinstance(keys, dict) or keyring.get('activeKeyId') not in keys or any(
                not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', key) or not isinstance(value, str) or
                not re.fullmatch('[a-f0-9]{64}', value) for key, value in keys.items()):
            raise RuntimeError('Keyring existant incorrect ; aucune clé remplacée.')
    else:
        keyring = {'activeKeyId': 'initial', 'keys': {'initial': secrets.token_hex(32)}}
        atomic_write(keyring_path, json.dumps(keyring) + '\n', 0o640, account.pw_gid)
    additions = {
        'WEB_COMMAND_DATABASE_URL': connection('drivy_web_runtime', 'webRuntimePassword'),
        'WEB_COMMAND_KEYRING_FILE': str(keyring_path), 'WEB_COMMAND_RETENTION_DAYS': '30'
    }
    if any(key in config and config[key] != value for key, value in additions.items()):
        raise RuntimeError('Une configuration différente du journal existe ; aucune substitution automatique.')
    backup = ETC / 'web.before-command-journal.env'
    if backup.exists():
        private_root_file(backup)
    else:
        atomic_write(backup, current)
    atomic_write(ETC / 'web-migration.env', 'NODE_ENV=production\nWEB_COMMAND_MIGRATION_DATABASE_URL=' +
                 connection('drivy_web_owner', 'webMigrationPassword') + '\n')
    config.update(additions)
    atomic_write(ETC / 'web.env', ''.join(key + '=' + value + '\n' for key, value in config.items()))
    print('Configuration du journal préparée : runtime distinct, keyring root/groupe privé, migration séparée. Aucun service redémarré.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Configuration du journal interrompue ; aucun secret affiché.', file=sys.stderr)
        sys.exit(1)
