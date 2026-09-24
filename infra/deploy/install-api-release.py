#!/usr/bin/env python3
"""Construit et migre une release préparée, puis change uniquement le lien de la nouvelle API."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path('/opt/drivy-refonte')


def environment_file(path):
    values = {}
    for line in path.read_text().splitlines():
        if line and not line.startswith('#'):
            key, value = line.split('=', 1)
            values[key] = value
    return values


def execute(arguments, directory, environment, description):
    result = subprocess.run(arguments, cwd=directory, env=environment, capture_output=True)
    if result.returncode:
        raise RuntimeError(description + ' a échoué. Aucun détail de connexion affiché ; vérifier localement.')


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3 or sys.argv[1] != '--apply':
        raise RuntimeError('Usage root CT114 : install-api-release.py --apply /opt/drivy-refonte/releases/<SHA>')
    release = Path(sys.argv[2]).resolve()
    if release.parent != ROOT / 'releases' or not re.fullmatch('[0-9a-f]{40,64}', release.name):
        raise RuntimeError('Chemin de release incorrect.')
    if not (release / 'package-lock.json').is_file() or not (release / 'apps/api/src/main.ts').is_file():
        raise RuntimeError('Snapshot incomplet.')
    os.chmod(ROOT / 'releases', 0o755)
    current = ROOT / 'current'
    if current.exists() or current.is_symlink():
        if not current.is_symlink() or current.resolve().parent != ROOT / 'releases':
            raise RuntimeError('Lien de release existant hors périmètre.')
    node = str(ROOT / 'runtime/node/bin/node')
    npm = str(ROOT / 'runtime/node/bin/npm')
    environment = os.environ | {'PATH': str(ROOT / 'runtime/node/bin') + ':' + os.environ.get('PATH', ''),
                                'npm_config_cache': str(ROOT / 'npm-cache'), 'NODE_OPTIONS': '--max-old-space-size=256'}
    migration = environment_file(Path('/etc/drivy-refonte/migration.env'))
    runtime = environment_file(Path('/etc/drivy-refonte/api.env'))
    for url, role in [(migration['MIGRATION_DATABASE_URL'], 'drivy_refonte_owner'),
                      (runtime['DATABASE_URL'], 'drivy_refonte_runtime')]:
        parts = urlsplit(url)
        if parts.hostname != 'drivy-db.tailb60275.ts.net' or parts.path != '/drivy_refonte' or parts.username != role:
            raise RuntimeError('Connexion de migration/runtime hors base ou rôle refonte.')
    execute([npm, 'ci', '--ignore-scripts', '--include=dev'], release, environment, 'Installation verrouillée')
    execute([npm, 'run', 'build', '--workspace', '@drivy/api'], release, environment, 'Compilation API')
    web = release / 'apps/web'
    if web.exists():
        if not (web / 'package-lock.json').is_file():
            raise RuntimeError('Snapshot web incomplet.')
        execute([npm, 'ci', '--ignore-scripts', '--include=dev'], web, environment, 'Installation web verrouillée')
        execute([npm, 'run', 'build'], web, environment, 'Compilation web et BFF')
    execute([npm, 'run', 'migrate', '--workspace', '@drivy/api'], release, environment | migration, 'Migration API')
    # Vérifier le rôle réel et l'efficacité de RLS sans contexte, avec la vraie connexion runtime.
    validation = """
import pg from 'pg';
const client = new pg.Client({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 5000 });
try {
  await client.connect();
  const { rows } = await client.query('SELECT rolsuper,rolbypassrls,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user');
  if (!rows[0] || Object.values(rows[0]).some(Boolean)) throw new Error('runtime_privilege');
  const tables = await client.query("SELECT relname,relrowsecurity,relforcerowsecurity FROM pg_class WHERE relnamespace='drivy'::regnamespace AND relkind='r'");
  const required = ['person','identity_link','school','membership','learner_profile','offering_version','training','instructor_assignment'];
  if (required.some(name => !tables.rows.some(row => row.relname === name)) ||
      tables.rows.some(r => !r.relrowsecurity || !r.relforcerowsecurity)) throw new Error('rls_missing');
  await client.query('BEGIN READ ONLY');
  await client.query('SET LOCAL ROLE drivy_app');
  const result = await client.query('SELECT count(*) AS total FROM drivy.person');
  if (result.rows[0].total !== '0') throw new Error('rls_context');
  await client.query('ROLLBACK');
} finally { await client.end(); }
"""
    execute([node, '--input-type=module', '-e', validation], release, environment | runtime, 'Contrôle runtime/RLS')
    execute([npm, 'prune', '--omit=dev', '--ignore-scripts'], release, environment, 'Réduction des dépendances runtime')
    if web.exists():
        execute([npm, 'prune', '--omit=dev', '--ignore-scripts'], web, environment, 'Réduction des dépendances web')
    # Le compte runtime n'est jamais propriétaire du code ni du lien actif.
    for directory, dirs, names in os.walk(release):
        os.chmod(directory, 0o755)
        for name in names:
            path = Path(directory) / name
            if not path.is_symlink():
                os.chmod(path, 0o755 if path.stat().st_mode & 0o111 else 0o644)
    temporary = ROOT / '.current-next'
    if temporary.exists() or temporary.is_symlink():
        raise RuntimeError('Lien transitoire déjà présent ; vérifier avant reprise.')
    temporary.symlink_to(release)
    os.replace(temporary, current)
    (release / 'deployment.json').write_text(json.dumps({'commit': release.name,
        'database': 'drivy_refonte', 'runtimeRoleVerified': True, 'serviceStarted': False}) + '\n')
    print('Release compilée, migrations vérifiées et lien current installé ; aucun service démarré/redémarré.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Préparation release interrompue ; aucun secret affiché.', file=sys.stderr)
        sys.exit(1)
