#!/usr/bin/env python3
"""Read-only deployment evidence. Never emits env contents, cookies or business records.

Runs only systemctl show, filesystem metadata reads, anonymous GETs and a PostgreSQL
READ ONLY transaction. It does not invoke any installer, backup or service mutation.
Requires the existing pinned SSH host key and operator SSH key; no fallback login.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=yes', 'root@192.168.1.106']


def remote(command, source):
    result = subprocess.run(SSH + [command], input=source, text=True, encoding='utf-8', capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError('Read-only probe failed; remote details withheld.')
    return result.stdout


APP_PROBE = r'''
import datetime,grp,hashlib,ipaddress,json,os,pathlib,pwd,re,subprocess,urllib.parse

def run(args, **kwargs):
 r=subprocess.run(args,capture_output=True,text=True,timeout=12,**kwargs)
 if r.returncode: raise RuntimeError('Read-only subcheck failed')
 return r.stdout.strip()

def envfile(name):
 p=pathlib.Path('/etc/drivy-refonte')/name
 if not p.is_file(): return {},{'present':False}
 st=p.stat()
 values={}
 for line in p.read_text().splitlines():
  if line and not line.startswith('#') and '=' in line:
   key,value=line.split('=',1)
   values[key]=value.strip().strip('"').strip("'")
 return values,{'present':True,'mode':oct(st.st_mode&0o777),'owner':pwd.getpwuid(st.st_uid).pw_name,'group':grp.getgrgid(st.st_gid).gr_name}

def urlcheck(value,db,role):
 u=urllib.parse.urlsplit(value)
 q=urllib.parse.parse_qs(u.query)
 return {'present':bool(value),'expectedHost':u.hostname=='drivy-db.tailb60275.ts.net','expectedDatabase':u.path=='/'+db,'expectedRole':u.username==role,'tlsMode':q.get('sslmode',['unspecified'])[0],'credentialsPresent':bool(u.password)}

def validate_config(relative,values):
 code="import {readConfig} from './"+relative+"';try{readConfig(process.env);console.log('valid')}catch{console.log('invalid')}"
 return run(['/opt/drivy-refonte/runtime/node/bin/node','--input-type=module','-e',code],cwd='/opt/drivy-refonte/current',env=os.environ|values)=='valid'

result={'observedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'current':str(pathlib.Path('/opt/drivy-refonte/current').resolve()),'services':{}}
for name in ['api','web','course-worker','identity']:
 unit='drivy-refonte-'+name
 props=['Id','ActiveState','SubState','WorkingDirectory','DropInPaths','MainPID','NRestarts','User','Group','UMask','NoNewPrivileges','RestrictSUIDSGID','LimitCORE']
 values=dict(line.split('=',1) for line in run(['systemctl','show',unit]+['-p'+p for p in props]).splitlines() if '=' in line)
 pid=values.get('MainPID','0')
 values['processDirectory']=str(pathlib.Path('/proc/'+pid+'/cwd').resolve()) if pid!='0' else None
 result['services'][name]=values
result['nodeVersion']=run(['/opt/drivy-refonte/runtime/node/bin/node','--version'])
result['diskAvailableKiB']=int(run(['df','-Pk','/opt/drivy-refonte']).splitlines()[-1].split()[3])
result['configFiles']={}
config={}
for name in ['api.env','web.env','course-worker.env','course-push.env','migration.env','identity.env']:
 config[name],result['configFiles'][name]=envfile(name)
api,web,worker,migration=config['api.env'],config['web.env'],config['course-worker.env'],config['migration.env']
result['configuration']={
 'apiSchemaValid':validate_config('apps/api/dist/config.js',api),
 'webSchemaValid':validate_config('apps/web/dist/server/config.js',web),
 'api':{key:api.get(key,'<default>') for key in ['NODE_ENV','HOST','PORT','MESSAGING_MODE','REAUTH_MAX_AGE_SECONDS']},
 'web':{key:web.get(key,'<default>') for key in ['NODE_ENV','WEB_DEVELOPMENT','WEB_HOST','WEB_PORT','WEB_TRUST_PROXY','WEB_SESSION_IDLE_MINUTES','WEB_SESSION_MAX_MINUTES','REAUTH_MAX_AGE_SECONDS','ACCOUNT_RECOVERY_ENABLED']},
 'gpsQualificationDisabled':not api.get('GPS_ONLY_QUALIFICATION_SCHOOL_IDS','').strip(),
 'messagingQualificationConfigured':bool(api.get('MESSAGING_QUALIFICATION_SCHOOL_IDS','').strip()),
 'webOriginExpected':web.get('WEB_ORIGIN','').rstrip('/')=='https://drivy.shulker.ch',
 'webApiExpected':web.get('API_BASE_URL','').rstrip('/')=='https://drivy.shulker.ch/refonte',
 'oidcIssuerMatches':web.get('OIDC_ISSUER')==api.get('OIDC_ISSUER'),
 'oidcClientSecretPresent':len(web.get('OIDC_WEB_CLIENT_SECRET',''))>=24,
 'cursorSecretPresent':len(api.get('CURSOR_SECRET',''))>=32,
 'runtimeDatabase':urlcheck(api.get('DATABASE_URL',''),'drivy_refonte','drivy_refonte_runtime'),
 'migrationDatabase':urlcheck(migration.get('MIGRATION_DATABASE_URL',''),'drivy_refonte','drivy_refonte_owner'),
 'workerDatabase':urlcheck(worker.get('COURSE_WORKER_DATABASE_URL',''),'drivy_refonte','drivy_refonte_course_worker'),
 'webJournalConfigured':bool(web.get('WEB_COMMAND_DATABASE_URL')),
}
# These URLs are only emitted after removing credentials, query and fragment.
for key in ['WEB_ORIGIN','API_BASE_URL','OIDC_ISSUER']:
 u=urllib.parse.urlsplit(web.get(key,''))
 result['configuration']['web'][key]=urllib.parse.urlunsplit((u.scheme,u.hostname or '',u.path,'',''))
host=api.get('HOST','127.0.0.1');ipaddress.ip_address(host)
port=int(api.get('PORT','3001'))
ready=json.loads(run(['curl','--silent','--show-error','--max-time','8','http://'+host+':'+str(port)+'/health/ready']))
result['readiness']=ready.get('status','unknown')
result['anonymousHttp']={}
public=pathlib.Path('/opt/drivy-refonte/current/apps/web/dist/client')
index=public/'index.html'
assets=re.findall(r'(?:src|href)="(/app/assets/[^"?#]+)"',index.read_text())
for route in ['/app/','/app/gestion','/app/preferences','/app/recover','/app/ouvrir','/refonte/v1/me',*assets]:
 response=subprocess.run(['curl','--silent','--show-error','--max-time','10','--include','https://drivy.shulker.ch'+route],capture_output=True,timeout=12)
 if response.returncode: raise RuntimeError('Anonymous GET failed')
 raw=response.stdout
 # Only allowlisted headers and a content hash; never return bodies or Set-Cookie.
 parts=raw.split(b'\r\n\r\n',1)
 lines=parts[0].decode().splitlines();headers={}
 for line in lines[1:]:
  if ':' in line:
   k,v=line.split(':',1)
   if k.lower() in ['cache-control','content-type','content-security-policy','x-content-type-options']:headers[k.lower()]=v.strip()
 digest=hashlib.sha256(parts[1] if len(parts)>1 else b'').hexdigest()
 evidence={'statusLine':lines[0],'headers':headers,'bodySha256':digest}
 local=index if route.startswith('/app/') and route not in assets else public/route.removeprefix('/app/') if route in assets else None
 if local is not None:evidence['matchesActiveBuild']=digest==hashlib.sha256(local.read_bytes()).hexdigest()
 result['anonymousHttp'][route]=evidence
print(json.dumps(result))
'''

DB_SQL = """
BEGIN READ ONLY;
SELECT json_build_object(
 'database',current_database(),
 'migrationRegistry',(SELECT json_agg(row_to_json(m)) FROM (SELECT name,sha256 FROM public.drivy_migrations ORDER BY name)m),
 'gpsAuditPolicyPresent',EXISTS(SELECT FROM pg_policies WHERE schemaname='drivy' AND tablename='audit_event' AND policyname='gps_preparation_audit_insert'),
 'webDatabaseExists',EXISTS(SELECT FROM pg_database WHERE datname='drivy_web'),
 'rlsTables',(SELECT count(*) FROM pg_class WHERE relnamespace='drivy'::regnamespace AND relkind='r'),
 'allTablesForceRls',NOT EXISTS(SELECT FROM pg_class WHERE relnamespace='drivy'::regnamespace AND relkind='r' AND (NOT relrowsecurity OR NOT relforcerowsecurity)),
 'runtimeRolesSafe',NOT EXISTS(SELECT FROM pg_roles WHERE rolname IN ('drivy_refonte_runtime','drivy_refonte_course_worker','drivy_app','drivy_course_worker') AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole)),
 'runtimeRolesPresent',(SELECT count(*)=4 FROM pg_roles WHERE rolname IN ('drivy_refonte_runtime','drivy_refonte_course_worker','drivy_app','drivy_course_worker'))
);
ROLLBACK;
"""

IDENTITY_SQL = """
BEGIN READ ONLY;
SELECT json_build_object(
 'webClientPresent',EXISTS(SELECT FROM client c JOIN realm r ON r.id=c.realm_id WHERE r.name='drivy' AND c.client_id='drivy-web'),
 'exactCallbackAllowed',EXISTS(SELECT FROM redirect_uris u JOIN client c ON c.id=u.client_id JOIN realm r ON r.id=c.realm_id WHERE r.name='drivy' AND c.client_id='drivy-web' AND u.value='https://drivy.shulker.ch/app/bff/callback'),
 'wildcardCallbackPresent',EXISTS(SELECT FROM redirect_uris u JOIN client c ON c.id=u.client_id JOIN realm r ON r.id=c.realm_id WHERE r.name='drivy' AND c.client_id='drivy-web' AND u.value LIKE '%*%')
);
ROLLBACK;
"""


def main():
    app = json.loads(remote('pct exec 114 -- python3 -', APP_PROBE))
    db_output = remote('pct exec 113 -- runuser -u postgres -- psql -X -qAt -v ON_ERROR_STOP=1 -d drivy_refonte', DB_SQL)
    db = json.loads(next(line for line in db_output.splitlines() if line.startswith('{')))
    registry = {item['name']: item['sha256'] for item in db.pop('migrationRegistry')}
    # Hash Git's stored LF bytes; Windows worktree autocrlf must not create a false mismatch.
    files = subprocess.run(['git', 'ls-tree', '-r', '--name-only', 'HEAD', 'apps/api/migrations'], cwd=ROOT,
                           capture_output=True, text=True, check=True).stdout.splitlines()
    expected = {}
    for filename in files:
        if filename.endswith('.sql'):
            data = subprocess.run(['git', 'show', 'HEAD:' + filename], cwd=ROOT, capture_output=True, check=True).stdout
            expected[Path(filename).name] = hashlib.sha256(data).hexdigest()
    db['appliedMigrationCount'] = len(registry)
    db['expectedMigrationCount'] = len(expected)
    db['checksumMismatch'] = [name for name in registry if name in expected and registry[name] != expected[name]]
    db['unexpectedMigrations'] = sorted(set(registry) - set(expected))
    db['pendingMigrations'] = sorted(set(expected) - set(registry))
    app['database'] = db
    identity = remote('pct exec 113 -- runuser -u postgres -- psql -X -qAt -v ON_ERROR_STOP=1 -d drivy_identity', IDENTITY_SQL)
    app['identity'] = json.loads(next(line for line in identity.splitlines() if line.startswith('{')))
    print(json.dumps(app, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Read-only probe incomplete; connection/configuration details withheld.', file=sys.stderr)
        sys.exit(1)
