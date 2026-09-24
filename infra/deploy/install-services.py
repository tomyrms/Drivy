#!/usr/bin/env python3
"""CT114. Prépare utilisateurs, fichiers secrets et unités, sans démarrer ni activer les services."""
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys

ROOT = Path('/opt/drivy-refonte')
ETC = Path('/etc/drivy-refonte')


def write_private(path, text):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        stream.write(text)


def main():
    if os.geteuid() != 0 or len(sys.argv) != 4 or sys.argv[1] != '--apply':
        raise RuntimeError('Usage root CT114 : install-services.py --apply /root/drivy-refonte-bootstrap.json /root/drivy-db-ca.crt')
    source = Path(sys.argv[2])
    info = source.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError('Le coffre doit être un fichier root sans permission de groupe/autres.')
    values = json.loads(source.read_text())
    for key in ('apiMigrationPassword', 'apiRuntimePassword', 'identityDatabasePassword', 'cursorSecret', 'bootstrapAdminPassword'):
        if len(values[key]) != 64 or any(character not in '0123456789abcdef' for character in values[key]):
            raise RuntimeError('Format du coffre invalide.')
    if ROOT.is_symlink() or ETC.exists() or ETC.is_symlink():
        raise RuntimeError('Installation existante ou chemin inattendu ; aucune réécriture implicite.')
    if not Path('/usr/sbin/nft').is_file():
        raise RuntimeError('Installer nftables avant de préparer les unités avec leur filtrage obligatoire.')
    for executable in ('node/bin/node', 'java/bin/java', 'keycloak/bin/kc.sh'):
        if not (ROOT / 'runtime' / executable).is_file():
            raise RuntimeError('Installer les runtimes vérifiés avant les services.')
    ca = Path(sys.argv[3])
    if not ca.is_file() or b'PRIVATE KEY' in ca.read_bytes():
        raise RuntimeError('Certificat public PostgreSQL absent ou incorrect.')
    verification = subprocess.run(['openssl', 'verify', '-CAfile', str(ca), '-verify_hostname',
        'drivy-db.tailb60275.ts.net', str(ca)], capture_output=True)
    if verification.returncode:
        raise RuntimeError('Certificat PostgreSQL non valide pour le nom attendu.')
    hosts = Path('/etc/hosts').read_text()
    addresses = [parts[0] for line in hosts.splitlines()
                 if len(parts := line.split('#', 1)[0].split()) > 1 and 'drivy-db.tailb60275.ts.net' in parts[1:]]
    if any(address != '192.168.1.151' for address in addresses):
        raise RuntimeError('Collision dans /etc/hosts pour le serveur PostgreSQL.')
    for account in ('drivy-refonte', 'drivy-identity'):
        try:
            pwd.getpwnam(account)
            raise RuntimeError('Un compte de service existe déjà ; examiner une reprise manuelle.')
        except KeyError:
            pass
    files = Path(__file__).parent
    for name in ('drivy-refonte-api.service', 'drivy-refonte-identity.service', 'drivy-refonte-ingress.service'):
        if (Path('/etc/systemd/system') / name).exists():
            raise RuntimeError('Une unité refonte existe déjà ; ne pas la remplacer implicitement.')
    for account in ('drivy-refonte', 'drivy-identity'):
        subprocess.run(['useradd', '--system', '--user-group', '--no-create-home', '--shell', '/usr/sbin/nologin', account], check=True)
    ETC.mkdir(mode=0o755)
    os.chmod(ETC, 0o755)
    shutil.copyfile(ca, ETC / 'db-ca.crt')
    os.chmod(ETC / 'db-ca.crt', 0o644)
    shutil.copyfile(files / 'ingress-refonte.nft', ETC / 'ingress.nft')
    os.chmod(ETC / 'ingress.nft', 0o644)
    if not addresses:
        with Path('/etc/hosts').open('a') as stream:
            stream.write('\n192.168.1.151 drivy-db.tailb60275.ts.net # Drivy refonte : certificat PostgreSQL vérifié\n')
    tls = '?sslmode=verify-full&sslrootcert=/etc/drivy-refonte/db-ca.crt'
    write_private(ETC / 'api.env',
        'NODE_ENV=production\nHOST=192.168.1.153\nPORT=3001\n'
        + 'DATABASE_URL=postgresql://drivy_refonte_runtime:' + values['apiRuntimePassword'] + '@drivy-db.tailb60275.ts.net:5432/drivy_refonte' + tls + '\n'
        + 'OIDC_ISSUER=https://drivy.shulker.ch/identity/realms/drivy\nOIDC_AUDIENCE=drivy-api\n'
        + 'OIDC_JWKS_URL=https://drivy.shulker.ch/identity/realms/drivy/protocol/openid-connect/certs\n'
        + 'CURSOR_SECRET=' + values['cursorSecret'] + '\n')
    write_private(ETC / 'migration.env', 'NODE_ENV=production\nMIGRATION_DATABASE_URL=postgresql://drivy_refonte_owner:'
        + values['apiMigrationPassword'] + '@drivy-db.tailb60275.ts.net:5432/drivy_refonte' + tls + '\n')
    write_private(ETC / 'identity.env', 'KC_DB_PASSWORD=' + values['identityDatabasePassword'] + '\n')
    write_private(ETC / 'identity-bootstrap.env',
        'KC_BOOTSTRAP_ADMIN_USERNAME=refonte-bootstrap\nKC_BOOTSTRAP_ADMIN_PASSWORD=' + values['bootstrapAdminPassword'] + '\n')
    keycloak = ROOT / 'runtime/keycloak'
    shutil.copyfile(files / 'keycloak.conf', keycloak / 'conf/keycloak.conf')
    imports = keycloak / 'data/import'
    imports.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(files / 'drivy-realm.json', imports / 'drivy-realm.json')
    account = pwd.getpwnam('drivy-identity')
    for directory, dirs, names in os.walk(keycloak / 'data'):
        os.chown(directory, account.pw_uid, account.pw_gid)
        for name in names:
            os.chown(Path(directory) / name, account.pw_uid, account.pw_gid)
    environment = os.environ | {'JAVA_HOME': str(ROOT / 'runtime/java'),
        'JAVA_OPTS_KC_HEAP': '-Xms128m -Xmx512m -XX:MaxMetaspaceSize=192m',
        'JAVA_OPTS_APPEND': '-XX:ActiveProcessorCount=2'}
    build = subprocess.run([str(keycloak / 'bin/kc.sh'), 'build', '--db=postgres', '--health-enabled=true'],
                           env=environment, capture_output=True)
    if build.returncode:
        raise RuntimeError('Optimisation Keycloak échouée ; services non démarrés.')
    for name in ('drivy-refonte-api.service', 'drivy-refonte-identity.service', 'drivy-refonte-ingress.service'):
        shutil.copyfile(files / name, Path('/etc/systemd/system') / name)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    print('Unités et configuration préparées, secrets root 0600 ; services NON démarrés, NON activés.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Préparation interrompue ; reprise locale nécessaire, aucun secret affiché.', file=sys.stderr)
        sys.exit(1)
