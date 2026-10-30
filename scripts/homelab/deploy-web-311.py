#!/usr/bin/env python3
"""Frontend-only #311 release. Read-only plan by default; backup precedes --execute.

Keeps the running BFF's compiled code and locked dependencies. No migration, DNS,
identity or API changes. Private configuration and database contents never leave CTs.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

WEB = r'''
import base64,datetime,fcntl,hashlib,io,json,os,pathlib,re,shutil,subprocess,tarfile,time
ROOT=pathlib.Path('/opt/drivy-refonte')
OVERRIDE=pathlib.Path('/etc/systemd/system/drivy-refonte-web.service.d/95-epic311-web.conf')
def run(args):
    r=subprocess.run(args,capture_output=True,timeout=60)
    if r.returncode: raise RuntimeError('Server check failed; private diagnostics suppressed')
    return r.stdout
def digest(data): return hashlib.sha256(data).hexdigest()
def services(require_active=True):
    result={}
    for label in ['api','web','course-worker','identity','ingress']:
        data=run(['systemctl','show','drivy-refonte-'+label,'--property=ActiveState,SubState,Type,MainPID,WorkingDirectory,NRestarts']).decode()
        v=dict(line.split('=',1) for line in data.splitlines() if '=' in line)
        completed_ingress=label=='ingress' and v['Type']=='oneshot' and v['SubState']=='exited'
        if require_active and (v['ActiveState']!='active' or v['MainPID']=='0' and not completed_ingress): raise RuntimeError('Required service is inactive: '+label)
        if v['MainPID']!='0': v['processDirectory']=os.readlink('/proc/'+v['MainPID']+'/cwd')
        result[label]=v
    return result
def private_state():
    return {p.name:(p.stat().st_mode & 0o777,digest(p.read_bytes())) for p in pathlib.Path('/etc/drivy-refonte').glob('*.env')}
def check_release(path):
    if path.name!='web' or path.parent.name!='apps' or path.parent.parent.parent not in [ROOT/'releases',ROOT/'web-releases']:
        raise RuntimeError('Web process directory outside release roots')
def restart():
    run(['systemctl','daemon-reload']); run(['systemctl','restart','drivy-refonte-web'])
def health(expected):
    for attempt in range(20):
        r=subprocess.run(['curl','--silent','--fail','--max-time','5','http://192.168.1.153:3002/app/'],capture_output=True)
        if r.returncode==0 and digest(r.stdout)==expected: return
        time.sleep(.5)
    raise RuntimeError('Served frontend does not match release')
def restore_override(directory,existed):
    if existed:
        temporary=OVERRIDE.with_suffix('.pending'); temporary.write_bytes((directory/'override.before').read_bytes()); temporary.chmod(0o644); temporary.replace(OVERRIDE)
    elif OVERRIDE.exists(): OVERRIDE.unlink()
    restart()
def execute(req):
    before=services(require_active=not bool(req.get('rollback')))
    previous=pathlib.Path(before['web'].get('processDirectory',before['web']['WorkingDirectory'])).resolve(); check_release(previous)
    config_before=private_state()
    if req.get('rollback'):
        identifier=req['rollback']
        if not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}',identifier): raise RuntimeError('Invalid rollback id')
        directory=ROOT/'web-operator'/identifier
        receipt=json.loads((directory/'receipt.json').read_text())
        if str(previous)!=receipt['release'] or not OVERRIDE.exists() or digest(OVERRIDE.read_bytes())!=receipt['overrideAfter']:
            raise RuntimeError('Deployment changed; rollback order must be reviewed')
        old=pathlib.Path(receipt['previousRelease']); check_release(old)
        if digest((old/'dist/client/index.html').read_bytes())!=receipt['previousHtml']:
            raise RuntimeError('Previous frontend changed')
        if not req['execute']: return {'action':'rollback-plan','id':identifier,'previousRelease':str(old)}
        restore_override(directory,receipt['overrideExisted'])
        health(receipt['previousHtml'])
        after=services(require_active=False)
        if after['web']['processDirectory']!=str(old): raise RuntimeError('Rollback directory mismatch')
        return {'action':'rolled-back','id':identifier,'webDirectory':str(old)}
    if str(previous)!=req['expectedPrevious']: raise RuntimeError('Current web changed since review')
    for filename,key in [('package.json','packageHash'),('package-lock.json','lockHash')]:
        if digest((previous/filename).read_bytes())!=req[key]: raise RuntimeError('BFF dependencies changed')
    if not (previous/'node_modules').is_dir() or not (previous/'dist/server/main.js').is_file(): raise RuntimeError('Previous BFF unavailable')
    if any(p.is_symlink() for p in (previous/'dist').rglob('*')): raise RuntimeError('Unexpected dist symlink')
    release=ROOT/'web-releases'/req['sha']/'apps/web'
    if release.exists(): raise RuntimeError('Immutable release already exists')
    if os.statvfs(ROOT).f_bavail*os.statvfs(ROOT).f_frsize < 500*1024*1024: raise RuntimeError('Insufficient disk space')
    plan={'action':'deployment-plan','sha':req['sha'],'url':'https://drivy.shulker.ch/app/','release':str(release),'previousRelease':str(previous),'servicesBefore':before,'frontendOnly':True,'databaseMigration':False}
    if not req['execute']: return plan
    if not req.get('databaseBackup'): raise RuntimeError('Verified database backup required')
    data=base64.b64decode(req['archive'])
    if digest(data)!=req['archiveSha256']: raise RuntimeError('Artifact checksum mismatch')
    identifier=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-')+req['sha'][:12]
    directory=ROOT/'web-operator'/identifier
    directory.mkdir(parents=True,mode=0o700); os.chmod(directory.parent,0o700)
    existed=OVERRIDE.exists()
    override_before=OVERRIDE.read_bytes() if existed else None
    if existed: (directory/'override.before').write_bytes(override_before)
    (directory/'web.env.before').write_bytes(pathlib.Path('/etc/drivy-refonte/web.env').read_bytes())
    os.chmod(directory/'web.env.before',0o600)
    run(['systemctl','cat','drivy-refonte-web']) # Validate unit can be read; its content stays private.
    release.mkdir(parents=True,mode=0o755)
    for parent in [ROOT/'web-releases',release.parent.parent,release.parent,release]: os.chmod(parent,0o755)
    client=release/'dist/client'; client.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
        members=archive.getmembers()
        if len(members)!=req['fileCount']: raise RuntimeError('Artifact count mismatch')
        for member in members:
            path=pathlib.PurePosixPath(member.name)
            if not member.isfile() or path.is_absolute() or '..' in path.parts or any(p.startswith('.') for p in path.parts): raise RuntimeError('Unsafe artifact')
            target=client.joinpath(*path.parts); target.parent.mkdir(parents=True,exist_ok=True)
            with archive.extractfile(member) as source: target.write_bytes(source.read())
            target.chmod(0o644)
    expected=digest((client/'index.html').read_bytes())
    if expected!=req['htmlHash'] or req['sha'] not in (client/'index.html').read_text(): raise RuntimeError('Build identity mismatch')
    # Existing tabs may still request previous hashed chunks. Preserve only immutable assets.
    old_assets=previous/'dist/client/assets'
    if old_assets.is_dir():
        for old in old_assets.rglob('*'):
            if old.is_file():
                target=client/'assets'/old.relative_to(old_assets)
                if target.exists():
                    if digest(target.read_bytes())!=digest(old.read_bytes()): raise RuntimeError('Asset filename collision')
                else:
                    target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(old,target)
    shutil.copytree(previous/'dist/server',release/'dist/server')
    for filename in ['package.json','package-lock.json']: shutil.copy2(previous/filename,release/filename)
    for path in release.rglob('*'):
        if path.is_dir(): path.chmod(0o755)
        elif path.is_file(): path.chmod(0o644)
    (release/'node_modules').symlink_to((previous/'node_modules').resolve(),target_is_directory=True)
    # Snapshot compiled BFF hashes without exporting data or private configuration.
    bff={str(p.relative_to(previous/'dist/server')):digest(p.read_bytes()) for p in (previous/'dist/server').rglob('*') if p.is_file()}
    for name,value in bff.items():
        if digest((release/'dist/server'/name).read_bytes())!=value: raise RuntimeError('BFF copy mismatch')
    if services()!=before or private_state()!=config_before or (OVERRIDE.read_bytes() if OVERRIDE.exists() else None)!=override_before:
        raise RuntimeError('Concurrent deployment/configuration change; stopped before activation')
    override=('[Service]\nWorkingDirectory='+str(release)+'\n').encode()
    receipt=plan|{'action':'deployed','id':identifier,'databaseBackup':req['databaseBackup'],'overrideExisted':existed,'overrideAfter':digest(override),'previousHtml':digest((previous/'dist/client/index.html').read_bytes()),'artifactSha256':req['archiveSha256'],'bffCopiedUnchanged':True}
    (directory/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    OVERRIDE.parent.mkdir(parents=True,exist_ok=True)
    temporary=OVERRIDE.with_suffix('.pending'); temporary.write_bytes(override); temporary.chmod(0o644); temporary.replace(OVERRIDE)
    try:
        restart(); health(expected)
        after=services()
        if after['web']['processDirectory']!=str(release): raise RuntimeError('Active web directory mismatch')
        if private_state()!=config_before: raise RuntimeError('Private configuration changed')
        for label in before:
            if label!='web' and before[label]!=after[label]: raise RuntimeError('Another service changed: '+label)
        receipt['servicesAfter']=after
        (directory/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
        return receipt
    except Exception:
        current_directory=run(['systemctl','show','drivy-refonte-web','--property=WorkingDirectory','--value']).decode().strip()
        if not OVERRIDE.exists() or digest(OVERRIDE.read_bytes())!=receipt['overrideAfter'] or current_directory!=str(release):
            raise RuntimeError('Activation failed and configuration changed concurrently; automatic rollback refused')
        restore_override(directory,existed); health(receipt['previousHtml'])
        raise RuntimeError('Activation failed; previous web restored')
try:
    if REQUEST['execute']:
        with open('/run/lock/drivy-web311.lock','a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            print(json.dumps(execute(REQUEST)))
    else: print(json.dumps(execute(REQUEST)))
except Exception as error:
    print(json.dumps({'error':str(error) if isinstance(error,RuntimeError) else 'Operation failed; private diagnostics suppressed'}))
    raise SystemExit(1)
'''

BACKUP = r'''
import datetime,json,os,pathlib,subprocess
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
path=pathlib.Path('/root/drivy_refonte-before-web311-'+stamp+'.dump')
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'wb') as stream:
    result=subprocess.run(['runuser','-u','postgres','--','pg_dump','--format=custom','--dbname=drivy_refonte'],stdout=stream,stderr=subprocess.PIPE,timeout=300)
    stream.flush(); os.fsync(stream.fileno())
if result.returncode or path.stat().st_size<1024: raise RuntimeError('Database backup failed')
for args in [['pg_restore','--list',str(path)],['pg_restore','--file=/dev/null',str(path)]]:
    check=subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=300)
    if check.returncode: raise RuntimeError('Database archive verification failed')
print(json.dumps({'path':str(path),'bytes':path.stat().st_size,'catalogueVerified':True,'allBlocksRead':True,'restoreRehearsal':False}))
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dist', type=Path)
    parser.add_argument('--sha')
    parser.add_argument('--expected-previous')
    parser.add_argument('--rollback')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    request = {'execute': args.execute}
    if args.rollback:
        request['rollback'] = args.rollback
    else:
        if not args.dist or not args.sha or not re.fullmatch('[a-f0-9]{40}', args.sha) or not args.expected_previous:
            parser.error('--dist, --sha and --expected-previous are required')
        root = Path(__file__).resolve().parents[2]
        files = sorted(p for p in args.dist.rglob('*') if p.is_file())
        allowed = {'.html', '.js', '.css', '.woff', '.woff2', '.svg', '.png', '.jpg', '.webmanifest', '.txt', '.ico'}
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as archive:
            for path in files:
                if path.is_symlink() or path.suffix not in allowed or any(part.startswith('.') for part in path.relative_to(args.dist).parts):
                    raise RuntimeError('Unexpected build file')
                archive.add(path, arcname=path.relative_to(args.dist).as_posix(), recursive=False)
        html = (args.dist / 'index.html').read_bytes()
        if f'name="drivy-build" content="{args.sha}"'.encode() not in html:
            raise RuntimeError('Build metadata does not match commit')
        request.update(sha=args.sha, expectedPrevious=args.expected_previous, fileCount=len(files), htmlHash=hashlib.sha256(html).hexdigest(),
                       packageHash=hashlib.sha256((root/'apps/web/package.json').read_bytes()).hexdigest(),
                       lockHash=hashlib.sha256((root/'apps/web/package-lock.json').read_bytes()).hexdigest(),
                       archiveSha256=hashlib.sha256(data.getvalue()).hexdigest())
        if args.execute: request['archive'] = base64.b64encode(data.getvalue()).decode()
    host = 'import subprocess,json\nREQUEST=json.loads(' + repr(json.dumps(request)) + ')\n'
    host += 'WEB=' + repr(WEB) + '\nBACKUP=' + repr(BACKUP) + '\n'
    host += '''
def ct(number,code):
    result=subprocess.run(['pct','exec',str(number),'--','python3','-'],input=code.encode(),capture_output=True,timeout=660)
    if result.returncode:
        try: message=json.loads(result.stdout).get('error','Remote operation failed')
        except Exception: message='Remote operation failed; private diagnostics suppressed'
        raise RuntimeError(message)
    return json.loads(result.stdout)
if REQUEST['execute']:
    # Recheck the plan before taking a backup; the actual switch rechecks once more.
    ct(114,'REQUEST='+repr(REQUEST|{'execute':False})+'\\n'+WEB)
    REQUEST['databaseBackup']=ct(113,BACKUP)
print(json.dumps(ct(114,'REQUEST='+repr(REQUEST)+'\\n'+WEB),indent=2))
'''
    compile(host, '<homelab-deployment>', 'exec')
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=yes',
                             'root@192.168.1.106', 'python3 -'], input=host.encode(), capture_output=True, timeout=900)
    if result.returncode:
        # The remote wrapper only exposes curated errors. Never echo the program/traceback with its request.
        errors = result.stderr.decode(errors='replace').splitlines()
        message = next((line for line in reversed(errors) if line.startswith('RuntimeError: ')), 'Deployment failed; diagnostics suppressed')
        raise SystemExit(message)
    print(result.stdout.decode())

if __name__ == '__main__':
    main()
