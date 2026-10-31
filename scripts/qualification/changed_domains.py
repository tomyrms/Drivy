"""Choisit les suites Ubuntu à lancer d'après les fichiers réellement modifiés.

Règle de sûreté : au moindre doute (différence illisible ou vide, chemin transverse, entrée inconnue),
toutes les suites tournent. Seul un ensemble de fichiers entièrement étranger à une suite la dispense.
Une qualification (campagne finale) ne passe jamais par ici : elle exige toutes les suites.
"""
from __future__ import annotations

import os
import pathlib
import subprocess
import sys

CONCEPTION = 'Drivy_Conception_v3_17_2026-09-20/'
OPENAPI = CONCEPTION + '04-technique/openapi.yaml'

# Changements transverses : ils peuvent modifier le comportement de n'importe quelle suite.
# Workflows et outillage de qualification, dépendances verrouillées, version de Node, contrat OpenAPI canonique,
# migrations. Un fichier de dépendances de n'importe quel dossier compte aussi.
TRANSVERSE_PREFIXES = ('.github/', 'scripts/qualification/', 'apps/api/migrations/')
TRANSVERSE_FILES = {'.node-version', 'package.json', 'package-lock.json', 'infra/deploy/runtime-lock.json',
                    'apps/ios/Package.resolved', OPENAPI}
TRANSVERSE_NAMES = {'package.json', 'package-lock.json', 'Package.resolved'}

# Dossiers sans effet sur le serveur ni sur le web : application iOS, documents, plans, outillage iOS, prototypes,
# et le dossier de conception (la vérification documentaire reste toujours lancée).
FOREIGN_TO_BOTH = ('apps/ios/', 'docs/', 'design-plans/', '.claude/', 'scripts/ios/', 'prototypes/', CONCEPTION)
# Les tests web lisent apps/api/contracts : tout le serveur reste donc pertinent pour le web.
# Les tests serveur ne lisent rien dans apps/web.
FOREIGN_TO_SERVER = FOREIGN_TO_BOTH + ('apps/web/',)
FOREIGN_TO_WEB = FOREIGN_TO_BOTH
ROOT_INERT = {'.gitignore', '.gitattributes'}


def transverse(path: str) -> bool:
    return (path in TRANSVERSE_FILES or path.startswith(TRANSVERSE_PREFIXES)
            or pathlib.PurePosixPath(path).name in TRANSVERSE_NAMES)


def foreign(path: str, prefixes: tuple[str, ...]) -> bool:
    if path.startswith(prefixes) or path in ROOT_INERT:
        return True
    return '/' not in path and path.endswith('.md')


def classify(files: list[str]) -> dict[str, object]:
    """Retourne les suites à lancer et la raison, lisible dans le résumé du job."""
    cleaned = sorted({f.strip().replace('\\', '/') for f in files if f.strip()})
    if not cleaned:
        return dict(server=True, web=True, reason='aucun fichier lu : tout est lancé')
    moving = [f for f in cleaned if transverse(f)]
    if moving:
        return dict(server=True, web=True, reason='changement transverse : ' + moving[0])
    server = any(not foreign(f, FOREIGN_TO_SERVER) for f in cleaned)
    web = any(not foreign(f, FOREIGN_TO_WEB) for f in cleaned)
    return dict(server=server, web=web, reason=f'{len(cleaned)} fichier(s) modifié(s)')


def git(*args: str) -> str:
    return subprocess.run(['git', *args], check=True, text=True, capture_output=True).stdout


def changed_files(base: str, head: str) -> list[str] | None:
    """Fichiers modifiés entre la base et la tête, renommages comptés des deux côtés ; None si illisible."""
    zero = set('0')
    candidates = []
    if base and not set(base) <= zero:
        candidates.append(base)
    candidates.append('origin/master')
    for candidate in candidates:
        try:
            git('cat-file', '-e', candidate + '^{commit}')
            origin = candidate if candidate == base else git('merge-base', candidate, head).strip()
            return git('diff', '--name-only', '--no-renames', origin, head).splitlines()
        except subprocess.CalledProcessError:
            continue
    return None


def write(path: str | None, text: str) -> None:
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write(text)


def main() -> int:
    select = os.environ.get('SELECT_BY_PATHS') == 'true'
    if not select:
        decision = dict(server=True, web=True, reason='sélection par chemins désactivée : tout est lancé')
    else:
        try:
            head = git('rev-parse', 'HEAD').strip()
            files = changed_files(os.environ.get('BASE_SHA', ''), head)
        except (OSError, subprocess.CalledProcessError):
            files = None
        decision = classify(files) if files is not None else dict(server=True, web=True, reason='différence illisible : tout est lancé')
    flag = lambda value: 'true' if value else 'false'
    write(os.environ.get('GITHUB_OUTPUT'), f"server={flag(decision['server'])}\nweb={flag(decision['web'])}\n")
    summary = (f"## Suites Ubuntu\n\nContrats, droits et PostgreSQL : {'lancé' if decision['server'] else 'dispensé'}\n\n"
               f"Web et BFF : {'lancé' if decision['web'] else 'dispensé'}\n\nMotif : {decision['reason']}\n")
    write(os.environ.get('GITHUB_STEP_SUMMARY'), summary)
    print(summary)
    return 0


if __name__ == '__main__':
    sys.exit(main())
