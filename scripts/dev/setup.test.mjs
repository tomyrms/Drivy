/** Opt-in, disposable real Keycloak/PostgreSQL test. Never uses the shared dev stack.
 * DRIVY_SETUP_CONTAINER_TEST=1 node --test scripts/dev/setup.test.mjs
 * Docker publishes random loopback ports, secrets stay in memory/private temporary state.
 */
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { Pool } from 'pg';

const root = fileURLToPath(new URL('../../', import.meta.url));
const enabled = process.env.DRIVY_SETUP_CONTAINER_TEST === '1';
const docker = (args, env = process.env) => {
  try { return execFileSync('docker', args, { encoding:'utf8', env, stdio:['ignore','pipe','pipe'] }).trim(); }
  catch { throw new Error('Commande Docker du laboratoire isolé échouée, sortie masquée.'); }
};
async function waitFor(check) {
  for (let i=0;i<120;i++) {
    try { if (await check()) return; } catch { /* Booting disposable services. */ }
    await new Promise(resolve=>setTimeout(resolve,1000));
  }
  throw new Error('Délai du laboratoire isolé dépassé.');
}

test('setup réel isolé : import sécurisé, migrations, reprise et refus sans réinitialisation', { skip:!enabled, timeout:240_000 }, async t => {
  const sandbox = await mkdtemp(join(tmpdir(),'drivy-setup-test-'));
  const suffix = randomBytes(6).toString('hex');
  const names = [];
  const password = randomBytes(32).toString('base64url');
  const env = { ...process.env, KC_BOOTSTRAP_ADMIN_USERNAME:'drivy-local-bootstrap', KC_BOOTSTRAP_ADMIN_PASSWORD:password,
    POSTGRES_USER:'drivy_dev', POSTGRES_PASSWORD:password, POSTGRES_DB:'drivy_dev' };
  let pool;
  try {
    const identityCompose = await readFile(join(root,'infra/dev/compose.yaml'),'utf8');
    const databaseCompose = await readFile(join(root,'compose.yaml'),'utf8');
    const keycloakImage = identityCompose.match(/image: (quay\.io\/keycloak\/keycloak:[^\s]+)/)[1];
    const postgresImage = databaseCompose.match(/image: (postgres:[^\s]+)/)[1];
    for (const [name,image,port,options] of [
      [`drivy-setup-kc-${suffix}`,keycloakImage,8080,['-e','KC_BOOTSTRAP_ADMIN_USERNAME','-e','KC_BOOTSTRAP_ADMIN_PASSWORD','-e','KC_LOG_LEVEL=warn']],
      [`drivy-setup-pg-${suffix}`,postgresImage,5432,['-e','POSTGRES_USER','-e','POSTGRES_PASSWORD','-e','POSTGRES_DB']]
    ]) {
      docker(['run','-d','--name',name,'-p',`127.0.0.1::${port}`,...options,image,...(port===8080?['start-dev']:[])],env);
      names.push(name);
    }
    const kcOrigin = `http://${docker(['port',names[0],'8080/tcp'])}`;
    const pgAddress = docker(['port',names[1],'5432/tcp']);
    const databaseUrl = `postgres://drivy_dev:${password}@${pgAddress}/drivy_dev`;
    pool = new Pool({ connectionString:databaseUrl });
    await waitFor(async()=> (await fetch(`${kcOrigin}/realms/master/.well-known/openid-configuration`)).ok);
    await waitFor(async()=> { await pool.query('SELECT 1');return true; });
    for (const dir of ['scripts/dev','apps/api/scripts','infra/dev/.state']) await mkdir(join(sandbox,dir),{recursive:true,mode:0o700});
    await symlink(join(root,'node_modules'),join(sandbox,'node_modules'),'junction');
    await writeFile(join(sandbox,'package.json'),'{"type":"module"}');
    for (const path of ['scripts/dev/setup.ts','apps/api/scripts/fixtures.ts','apps/api/scripts/migrations.ts','infra/dev/realm.json']) await cp(join(root,path),join(sandbox,path));
    await cp(join(root,'apps/api/migrations'),join(sandbox,'apps/api/migrations'),{recursive:true});
    // Only the copied transport harness changes: no Docker compose or shared state access.
    let shared = await readFile(join(root,'scripts/dev/shared.ts'),'utf8');
    shared = shared.replaceAll('http://127.0.0.1:8081',kcOrigin)
      .replace('postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_dev',databaseUrl)
      .replace("  const child = spawn(executable,args,{ cwd:root,stdio:'inherit',windowsHide:true });", "  if (executable==='docker') return;\n  throw new Error('Commande externe interdite dans le laboratoire');\n  const child = spawn(executable,args,{ cwd:root,stdio:'inherit',windowsHide:true });");
    await writeFile(join(sandbox,'scripts/dev/shared.ts'),shared,{mode:0o600});
    await writeFile(join(sandbox,'infra/dev/.state/runtime.json'),JSON.stringify({adminUsername:'drivy-local-bootstrap',adminPassword:password,cursorSecret:randomBytes(32).toString('hex')}),{mode:0o600});
    const run = () => spawnSync(process.execPath,['--import','tsx','scripts/dev/setup.ts'],{cwd:sandbox,encoding:'utf8',timeout:120_000});
    const login = await fetch(`${kcOrigin}/realms/master/protocol/openid-connect/token`,{method:'POST',body:new URLSearchParams({grant_type:'password',client_id:'admin-cli',username:env.KC_BOOTSTRAP_ADMIN_USERNAME,password})});
    assert.ok(login.ok,'Authentification du seul fournisseur isolé');
    const { access_token } = await login.json();
    const admin = (path,init={}) => fetch(`${kcOrigin}/admin/realms/drivy-dev/${path}`,{...init,headers:{'Content-Type':'application/json',Authorization:`Bearer ${access_token}`}});
    let installed=false;
    await t.test('première installation complète',async()=> {
      const result=run();
      if (result.status!==0) {
        const clients=await (await admin('clients?clientId=drivy-apple')).json();
        t.diagnostic(`Échec Zod générique reproduit : ${result.stderr.includes('Configuration fournisseur locale non conforme.')}. Password grant importé actif : ${clients[0]?.directAccessGrantsEnabled===true}.`);
      }
      // Deliberately do not attach stdout/stderr or credential-bearing request objects to assertions.
      assert.ok(result.status===0,'setup doit terminer sans erreur de configuration fournisseur');
      const clients=await (await admin('clients?clientId=drivy-apple')).json();
      assert.equal(clients.length,1);
      const apple=clients[0];
      assert.equal(apple.directAccessGrantsEnabled,false);
      assert.equal(apple.implicitFlowEnabled,false);
      assert.equal(apple.publicClient,true);
      assert.equal(apple.standardFlowEnabled,true);
      assert.equal(apple.attributes['pkce.code.challenge.method'],'S256');
      assert.deepEqual(apple.redirectUris,['ch.drivy.qualification:/oauth/callback']);
      assert.deepEqual(apple.defaultClientScopes.sort(),['basic','email','profile']);
      const migrations=await pool.query("SELECT count(*)::int AS n FROM public.drivy_migrations WHERE name='045_course_notifications.sql'");
      assert.equal(migrations.rows[0].n,1);
      const worker=await pool.query("SELECT rolcanlogin,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb,rolinherit FROM pg_roles WHERE rolname='drivy_course_worker'");
      assert.deepEqual(worker.rows,[{rolcanlogin:false,rolsuper:false,rolbypassrls:false,rolcreaterole:false,rolcreatedb:false,rolinherit:false}]);
      const saved=JSON.parse(await readFile(join(sandbox,'infra/dev/.state/accounts.json'),'utf8'));
      assert.equal(saved.length,6);
      const links=await pool.query('SELECT count(*)::int AS n FROM drivy.identity_link WHERE subject=ANY($1::text[])',[saved.map(a=>a.subject)]);
      assert.equal(links.rows[0].n,6);
      const denied=await fetch(`${kcOrigin}/realms/drivy-dev/protocol/openid-connect/token`,{method:'POST',body:new URLSearchParams({grant_type:'password',client_id:'drivy-apple',username:saved[0].username,password:saved[0].password})});
      assert.equal((await denied.json()).error,'unauthorized_client');
      installed=true;
    });
    if (!installed) return;
    await t.test('migration 045 avec le propriétaire restreint du provisionnement',async()=> {
      await pool.query('CREATE ROLE drivy_refonte_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS');
      // Authenticate as the disposable administrator, then SET ROLE before any SQL.
      await pool.query('GRANT drivy_app TO drivy_refonte_owner WITH ADMIN OPTION');
      await pool.query('CREATE DATABASE drivy_refonte OWNER drivy_refonte_owner');
      const ownerUrl=databaseUrl.replace(/\/drivy_dev$/,'/drivy_refonte');
      await writeFile(join(sandbox,'owner-migration.ts'),`import {Pool} from 'pg';import {migrate} from './apps/api/scripts/migrations.ts';
const pool=new Pool({connectionString:process.env.TEST_OWNER_DATABASE_URL,options:'-c role=drivy_refonte_owner'});
try { await migrate(pool); } catch { process.exitCode=1; } finally {await pool.end();}`);
      const result=spawnSync(process.execPath,['--import','tsx','owner-migration.ts'],{cwd:sandbox,encoding:'utf8',timeout:120_000,env:{...process.env,TEST_OWNER_DATABASE_URL:ownerUrl}});
      assert.ok(result.status===0,'Migration complète avec les droits exacts du propriétaire restreint');
    });
    const stateFile=join(sandbox,'infra/dev/.state/accounts.json');
    const before=await readFile(stateFile,'utf8');
    await t.test('reprise idempotente sans remplacer les secrets',async()=> {
      assert.ok(run().status===0,'Seconde exécution réussie');
      assert.ok(await readFile(stateFile,'utf8')===before,'Secrets et subjects inchangés');
    });
    const [apple]=await (await admin('clients?clientId=drivy-apple')).json();
    await t.test('client préexistant non conforme refusé, jamais réparé silencieusement',async()=> {
      for (const patch of [{directAccessGrantsEnabled:true},{attributes:{'pkce.code.challenge.method':'plain'}},{implicitFlowEnabled:true}]) {
        assert.ok((await admin(`clients/${apple.id}`,{method:'PUT',body:JSON.stringify({...apple,...patch})})).ok);
        assert.ok(run().status!==0,'Configuration dangereuse refusée');
        assert.ok(await readFile(stateFile,'utf8')===before,'Aucun changement de mot de passe');
      }
      assert.ok((await admin(`clients/${apple.id}`,{method:'PUT',body:JSON.stringify(apple)})).ok);
    });
    await t.test('compte préexistant sans état local refusé sans réinitialisation',async()=> {
      await writeFile(stateFile,'[]',{mode:0o600});
      const result=run();
      assert.ok(result.status!==0 && result.stderr.includes('aucune réaffectation automatique'),'Refus explicite');
      assert.equal(await readFile(stateFile,'utf8'),'[]');
      const users=await (await admin('users?username=demo-admin&exact=true')).json();
      assert.ok(users[0].id===JSON.parse(before)[0].subject,'Subject existant conservé');
    });
  } finally {
    await pool?.end();
    for (const name of names.reverse()) docker(['rm','-f','-v',name]);
    await rm(sandbox,{recursive:true,force:true});
  }
});
