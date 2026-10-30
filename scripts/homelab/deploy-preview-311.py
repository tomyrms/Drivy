#!/usr/bin/env python3
"""Publish the synthetic #311 preview only. Dry-run unless --execute is supplied."""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import io
import json
import pathlib
import re
import subprocess
import tarfile

HOST = "root@192.168.1.106"
CONTAINER = "109"
ALLOWED = {".html", ".js", ".css", ".woff", ".woff2", ".svg", ".png", ".jpg", ".jpeg", ".webp", ".ico", ".txt", ".webmanifest"}

# This code runs inside CT109, never on CT114 or the database container.
REMOTE = r"""
import base64, datetime, hashlib, io, json, os, pathlib, re, subprocess, tarfile

ROOT = pathlib.Path('/srv/drivy-preview')
CONFIG = pathlib.Path('/etc/caddy/Caddyfile')
URL = 'https://shulker.ch/drivy-preview/'
BEGIN = '\t# BEGIN DRIVY PREVIEW 311\n'
END = '\t# END DRIVY PREVIEW 311\n'
CSP = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
BLOCK = BEGIN + '''\
\tredir /drivy-preview /drivy-preview/ 308
\thandle_path /drivy-preview/* {
\t\troot * /srv/drivy-preview/current
\t\theader {
\t\t\tContent-Security-Policy "__CSP__"
\t\t\tX-Robots-Tag "noindex, nofollow, noarchive"
\t\t\tX-Content-Type-Options "nosniff"
\t\t\tReferrer-Policy "no-referrer"
\t\t\tPermissions-Policy "camera=(), microphone=(), geolocation=()"
\t\t\tCache-Control "no-store"
\t\t}
\t\t@preview311Root path /
\t\trewrite @preview311Root /preview-311.html
\t\tfile_server
\t}
'''.replace('__CSP__', CSP) + END

def digest(data):
    return hashlib.sha256(data).hexdigest()

def run(argv, label):
    result = subprocess.run(argv, capture_output=True, timeout=45)
    if result.returncode:
        # Do not print Caddy diagnostics: imported configuration may contain secrets.
        raise RuntimeError(label + ' failed (diagnostics suppressed)')
    return result.stdout

def validate(path):
    run(['caddy', 'validate', '--config', str(path), '--adapter', 'caddyfile'], 'Caddy validation')

def reload():
    run(['systemctl', 'reload', 'caddy'], 'Caddy reload')
    run(['systemctl', 'is-active', '--quiet', 'caddy'], 'Caddy service check')

def write_exact(path, data, original=CONFIG):
    path.write_bytes(data)
    stat = original.stat()
    os.chmod(path, stat.st_mode & 0o777)
    os.chown(path, stat.st_uid, stat.st_gid)

def set_current(target):
    current = ROOT / 'current'
    pending = ROOT / '.current-pending'
    if pending.is_symlink():
        pending.unlink()
    if target is None:
        if current.is_symlink():
            current.unlink()
        return
    resolved = pathlib.Path(target).resolve()
    if resolved.parent != (ROOT / 'releases').resolve() or not resolved.is_dir():
        raise RuntimeError('Current link target is outside preview releases')
    pending.symlink_to(resolved, target_is_directory=True)
    pending.replace(current)

def proposed_config(original):
    text = original.decode('utf-8')
    # Host source has been inspected; fail closed if it changes rather than editing broadly.
    anchor = ('\nshulker.ch {\n\timport crowdsec_protect\n\tencode zstd gzip\n'
              '\theader Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"\n')
    if text.count(anchor) != 1:
        raise RuntimeError('Expected shulker.ch host block changed; review required')
    start = text.index(anchor) + len(anchor)
    tail = text[start:]
    if tail.startswith(BEGIN):
        end = tail.find(END)
        if end < 0 or tail[:end + len(END)] != BLOCK:
            raise RuntimeError('Existing preview route differs; review required')
        return original
    if not tail.startswith('\treverse_proxy 192.168.1.146:80\n}'):
        raise RuntimeError('Expected root proxy changed; review required')
    return (text[:start] + BLOCK + text[start:]).encode('utf-8')

def other_hosts(config):
    data = json.loads(run(['caddy', 'adapt', '--config', str(config), '--adapter', 'caddyfile'], 'Caddy adaptation'))
    result = {}
    def walk(value):
        if isinstance(value, dict):
            hosts = [h for m in value.get('match', []) for h in m.get('host', [])]
            if hosts and 'shulker.ch' not in hosts:
                # Caddy numbers route groups globally; their names may shift with insertion.
                def normalize(item):
                    if isinstance(item, dict):
                        return {k: normalize(v) for k, v in item.items() if k != 'group'}
                    if isinstance(item, list):
                        return [normalize(v) for v in item]
                    return item
                result[','.join(hosts)] = normalize(value)
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
    walk(data)
    return result

def check_preview(expected_html):
    headers = run(['curl', '--silent', '--show-error', '--fail', '--max-time', '20',
                   '--resolve', 'shulker.ch:443:127.0.0.1', '--dump-header', '-', '--output', '/dev/null', URL], 'Preview headers').decode()
    lower = headers.lower()
    for expected in ["connect-src 'none'", "script-src 'self'", 'x-robots-tag: noindex',
                     'strict-transport-security:', 'x-content-type-options: nosniff']:
        if expected not in lower:
            raise RuntimeError('Preview security header missing: ' + expected)
    body = run(['curl', '--silent', '--show-error', '--fail', '--max-time', '20',
                '--resolve', 'shulker.ch:443:127.0.0.1', URL], 'Preview content')
    if digest(body) != digest(expected_html):
        raise RuntimeError('Served preview does not match artifact')

def rollback(request):
    identifier = request['rollback']
    if not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}', identifier):
        raise RuntimeError('Invalid rollback identifier')
    directory = ROOT / 'operator' / identifier
    receipt = json.loads((directory / 'receipt.json').read_text())
    if digest(CONFIG.read_bytes()) != receipt['caddyAfter']:
        raise RuntimeError('Caddy changed after publication; do not overwrite later work')
    current = ROOT / 'current'
    if not current.is_symlink() or str(current.resolve()) != receipt['release']:
        raise RuntimeError('A different preview release is active; review rollback order')
    backup = directory / 'Caddyfile.before'
    if digest(backup.read_bytes()) != receipt['caddyBefore']:
        raise RuntimeError('Exact Caddy backup checksum does not match receipt')
    if not request['execute']:
        return {'action': 'rollback-plan', 'id': identifier, 'url': URL, 'previousRelease': receipt['previousRelease']}
    candidate = CONFIG.with_name('Caddyfile.preview311-rollback')
    write_exact(candidate, backup.read_bytes())
    validate(candidate)
    set_current(receipt['previousRelease'])
    candidate.replace(CONFIG)
    reload()
    receipt['rolledBackAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (directory / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return {'action': 'rolled-back', 'id': identifier, 'url': URL, 'caddyRestored': digest(CONFIG.read_bytes()) == receipt['caddyBefore']}

def deploy(request):
    original = CONFIG.read_bytes()
    proposed = proposed_config(original)
    current = ROOT / 'current'
    if current.exists() and not current.is_symlink():
        raise RuntimeError('Preview current path must be a symlink')
    previous = str(current.resolve()) if current.is_symlink() else None
    release = ROOT / 'releases' / request['sha']
    plan = {'action': 'publication-plan', 'url': URL, 'sha': request['sha'],
            'archiveSha256': request['archiveSha256'], 'fileCount': request['fileCount'],
            'caddyBefore': digest(original), 'caddyAfter': digest(proposed),
            'previousRelease': previous, 'release': str(release), 'container': 109}
    if not request['execute']:
        return plan
    if release.exists():
        raise RuntimeError('Immutable release already exists; choose a fresh committed SHA')
    data = base64.b64decode(request['archive'])
    if digest(data) != request['archiveSha256']:
        raise RuntimeError('Archive checksum mismatch')
    identifier = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + request['sha'][:12]
    directory = ROOT / 'operator' / identifier
    directory.mkdir(parents=True, mode=0o700)
    os.chmod(ROOT / 'operator', 0o700)
    backup = directory / 'Caddyfile.before'
    backup.write_bytes(original)
    os.chmod(backup, 0o600)
    candidate = CONFIG.with_name('Caddyfile.preview311-candidate')
    write_exact(candidate, proposed)
    installed = False
    try:
        validate(candidate)
        if other_hosts(CONFIG) != other_hosts(candidate):
            raise RuntimeError('A host other than shulker.ch would change')
        release.mkdir(parents=True, mode=0o755)
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            members = archive.getmembers()
            if len(members) != request['fileCount']:
                raise RuntimeError('Artifact file count mismatch')
            for member in members:
                name = pathlib.PurePosixPath(member.name)
                if not member.isfile() or name.is_absolute() or '..' in name.parts or any(p.startswith('.') for p in name.parts):
                    raise RuntimeError('Unsafe artifact member')
                target = release.joinpath(*name.parts)
                target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                with archive.extractfile(member) as source:
                    target.write_bytes(source.read())
                target.chmod(0o644)
        plan.update({'action': 'published', 'id': identifier,
                     'publishedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()})
        (directory / 'receipt.json').write_text(json.dumps(plan, indent=2) + '\n')
        if CONFIG.read_bytes() != original:
            raise RuntimeError('Caddy changed concurrently; publication stopped')
        set_current(str(release))
        installed = True
        candidate.replace(CONFIG)
        reload()
        check_preview((release / 'preview-311.html').read_bytes())
        return plan
    except Exception:
        # Restore only when this operation installed its candidate or left original intact.
        if installed and CONFIG.read_bytes() in [original, proposed]:
            restore = CONFIG.with_name('Caddyfile.preview311-restore')
            write_exact(restore, original)
            validate(restore)
            set_current(previous)
            restore.replace(CONFIG)
            reload()
        raise
    finally:
        if candidate.exists():
            candidate.unlink()

try:
    result = rollback(REQUEST) if REQUEST.get('rollback') else deploy(REQUEST)
    print(json.dumps(result))
except Exception as error:
    print(json.dumps({'action': 'failed', 'reason': str(error)}))
    raise SystemExit(1)
"""


def pack(dist: pathlib.Path, sha: str) -> tuple[bytes, int]:
    dist = dist.resolve(strict=True)
    if not (dist / "preview-311.html").is_file():
        raise ValueError("Artifact must contain preview-311.html")
    files = sorted(path for path in dist.rglob("*") if path.is_file() or path.is_symlink())
    if not files:
        raise ValueError("Artifact is empty")
    output = io.BytesIO()
    has_sha = False
    with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for path in files:
            relative = path.relative_to(dist)
            permitted = path.suffix.lower() in ALLOWED or relative.as_posix() == "preview-build.json"
            if path.is_symlink() or any(part.startswith(".") for part in relative.parts) or not permitted:
                raise ValueError(f"Unexpected static artifact file: {relative}")
            data = path.read_bytes()
            has_sha |= sha[:12].encode() in data
            info = tarfile.TarInfo(relative.as_posix())
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            archive.addfile(info, io.BytesIO(data))
    if not has_sha:
        raise ValueError("Artifact does not contain the supplied SHA prefix")
    if output.tell() > 20_000_000:
        raise ValueError("Static preview archive exceeds 20 MB")
    return output.getvalue(), len(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", type=pathlib.Path)
    parser.add_argument("--sha")
    parser.add_argument("--rollback", metavar="DEPLOYMENT_ID")
    parser.add_argument("--execute", action="store_true", help="Perform the prepared mutation; absent means read-only plan")
    args = parser.parse_args()
    request = {"execute": args.execute}
    if args.rollback:
        if args.dist or args.sha:
            parser.error("Rollback cannot be combined with an artifact")
        request["rollback"] = args.rollback
    else:
        if not args.dist or not args.sha or not re.fullmatch(r"[a-f0-9]{40}", args.sha):
            parser.error("Supply --dist and a full lowercase 40-character --sha")
        archive, count = pack(args.dist, args.sha)
        request.update({"sha": args.sha, "archiveSha256": hashlib.sha256(archive).hexdigest(), "fileCount": count})
        if args.execute:
            request["archive"] = base64.b64encode(archive).decode()
    encoded = base64.b64encode(json.dumps(request).encode()).decode()
    source = "import base64,json\nREQUEST=json.loads(base64.b64decode('" + encoded + "'))\n" + REMOTE
    result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=yes",
                             HOST, "pct", "exec", CONTAINER, "--", "python3", "-"], input=source.encode(), capture_output=True, timeout=150)
    print(result.stdout.decode(errors="replace").strip())
    if result.returncode:
        raise SystemExit("Preview operation failed; remote stderr intentionally suppressed")


if __name__ == "__main__":
    main()
