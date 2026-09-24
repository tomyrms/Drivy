#!/usr/bin/env python3
"""Prépare le service web CT114 ; ne configure pas l'IdP et ne démarre aucun service."""
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3 or sys.argv[1] != '--apply':
        raise RuntimeError('Usage root CT114 : install-web-service.py --apply /root/drivy-web-bootstrap.json')
    source = Path(sys.argv[2]).resolve()
    if source.parent != Path('/root') or source.stat().st_uid != 0 or source.stat().st_mode & 0o077:
        raise RuntimeError('Le fichier bootstrap doit être privé et appartenir à root.')
    values = json.loads(source.read_text())
    credential = values.get('oidcClientSecret', '')
    if not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', credential):
        raise RuntimeError('Configuration du client web invalide.')
    try:
        account = pwd.getpwnam('drivy-web')
        if account.pw_uid == 0 or account.pw_shell not in ('/usr/sbin/nologin', '/sbin/nologin'):
            raise RuntimeError('Compte système web incohérent.')
    except KeyError:
        subprocess.run(['useradd', '--system', '--no-create-home', '--shell', '/usr/sbin/nologin', 'drivy-web'], check=True)
    directory = Path('/etc/drivy-refonte')
    if not directory.is_dir():
        raise RuntimeError('Installer la refonte API/identité avant le service web.')
    # Conserver le journal déjà configuré : une réinstallation OIDC ne doit pas
    # désactiver sa durabilité ni changer ses clés.
    config = directory / 'web.env'
    retained = {}
    if config.exists() or config.is_symlink():
        if config.is_symlink() or config.stat().st_uid != 0 or config.stat().st_mode & 0o077:
            raise RuntimeError('Configuration web existante non privée.')
        previous = dict(line.split('=', 1) for line in config.read_text().splitlines() if line and not line.startswith('#'))
        retained = {key: previous[key] for key in ('WEB_COMMAND_DATABASE_URL', 'WEB_COMMAND_KEYRING_FILE',
                    'WEB_COMMAND_RETENTION_DAYS') if key in previous}
    temporary = config.with_name(config.name + '.next')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        os.fchmod(stream.fileno(), 0o600)
        os.fchown(stream.fileno(), 0, 0)
        stream.write('NODE_ENV=production\nWEB_ORIGIN=https://drivy.shulker.ch\n'
                     'API_BASE_URL=https://drivy.shulker.ch/refonte\n'
                     'OIDC_ISSUER=https://drivy.shulker.ch/identity/realms/drivy\n'
                     'OIDC_WEB_CLIENT_ID=drivy-web\nOIDC_WEB_CLIENT_SECRET=' + credential + '\n'
                     'WEB_HOST=192.168.1.153\nWEB_PORT=3002\nWEB_DEVELOPMENT=false\n' +
                     ''.join(key + '=' + value + '\n' for key, value in retained.items()))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, config)
    service = 'drivy-refonte-web.service'
    shutil.copyfile(Path(__file__).resolve().parent / service, Path('/etc/systemd/system') / service)
    subprocess.run(['systemctl', 'daemon-reload'], check=True, capture_output=True)
    subprocess.run(['systemd-analyze', 'verify', service], check=True, capture_output=True)
    print('Configuration web privée et unité préparées. Aucun démarrage, client OIDC, proxy ou firewall modifié.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Installation web interrompue ; aucun secret affiché.', file=sys.stderr)
        sys.exit(1)
