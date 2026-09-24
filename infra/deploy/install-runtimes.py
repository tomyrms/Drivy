#!/usr/bin/env python3
"""CT114 uniquement. Installe trois runtimes privés vérifiés, sans toucher Node/PM2 existants."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path('/opt/drivy-refonte')


def main():
    if os.geteuid() != 0 or sys.argv[1:] != ['--apply'] or platform.machine() != 'x86_64':
        raise RuntimeError('Exécuter sur CT114 x86_64 comme root : install-runtimes.py --apply')
    lock = json.loads(Path(__file__).with_name('runtime-lock.json').read_text())
    if ROOT.is_symlink() or (ROOT / 'runtime').is_symlink():
        raise RuntimeError('Chemin runtime inattendu.')
    runtime = ROOT / 'runtime'
    runtime.mkdir(parents=True, exist_ok=True)
    os.chmod(ROOT, 0o755)
    os.chmod(runtime, 0o755)
    for name in ('node', 'java', 'keycloak'):
        spec = lock[name]
        target = runtime / name
        if target.exists():
            if target.is_symlink() or (target / '.drivy-source-sha256').read_text().strip() != spec['sha256']:
                raise RuntimeError('Runtime existant différent ; aucune mise à niveau implicite.')
            continue
        with tempfile.TemporaryDirectory(prefix='.runtime-', dir=runtime) as temporary:
            archive = Path(temporary) / 'archive'
            digest = hashlib.sha256()
            with urllib.request.urlopen(spec['url'], timeout=60) as response, archive.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    digest.update(chunk)
                    output.write(chunk)
            if digest.hexdigest() != spec['sha256']:
                raise RuntimeError('Empreinte du runtime incorrecte.')
            extracted = Path(temporary) / 'extracted'
            extracted.mkdir()
            os.chmod(extracted, 0o755)
            # L'archive authentifiée doit avoir une racine unique, sans chemin absolu/traversée.
            with tarfile.open(archive) as bundle:
                names = bundle.getnames()
                if any(Path(member).is_absolute() or '..' in Path(member).parts for member in names):
                    raise RuntimeError('Structure archive incorrecte.')
                roots = {Path(member).parts[0] for member in names if Path(member).parts}
                if len(roots) != 1:
                    raise RuntimeError('Archive runtime sans racine unique.')
            subprocess.run(['tar', '-xf', str(archive), '-C', str(extracted), '--strip-components=1'], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (extracted / '.drivy-source-sha256').write_text(spec['sha256'] + '\n')
            extracted.rename(target)
    print('Node 24, JDK 21 et Keycloak installés dans /opt/drivy-refonte/runtime ; aucun service démarré.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error) if isinstance(error, RuntimeError) else 'Installation runtime interrompue ; vérifier localement.', file=sys.stderr)
        sys.exit(1)
