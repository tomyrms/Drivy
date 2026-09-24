import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { Pool } from 'pg';
import { z } from 'zod';
import { migrate } from '../../apps/api/scripts/migrations.js';
import { fixtureIds, seedFixtures } from '../../apps/api/scripts/fixtures.js';
import { command,databaseUrl,initializeRuntime,issuer,keycloakOrigin,loadAccounts,localFetch,secretFile,stateDirectory,waitForIdentity,type Account } from './shared.js';

async function main() {
  const runtime = await initializeRuntime();
  await writeFile(new URL('keycloak.env',stateDirectory),`KC_BOOTSTRAP_ADMIN_USERNAME=${runtime.adminUsername}\nKC_BOOTSTRAP_ADMIN_PASSWORD=${runtime.adminPassword}\n`,{ mode:0o600 });
  await command('docker',['compose','-f','compose.yaml','up','-d','--wait','postgres']);
  await command('docker',['compose','-f','infra/dev/compose.yaml','up','-d']);
  console.log('Attente du fournisseur OIDC local…');
  await waitForIdentity();
  const tokenResponse = await localFetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`,{
    method:'POST',body:new URLSearchParams({ grant_type:'password',client_id:'admin-cli',username:runtime.adminUsername,password:runtime.adminPassword })
  });
  if (!tokenResponse.ok) throw new Error('Authentification administrative locale refusée ; secrets existants conservés.');
  const admin = z.object({ access_token:z.string() }).parse(await tokenResponse.json());
  const adminFetch = (path: string,init: RequestInit = {}) => localFetch(`${keycloakOrigin}/admin/${path}`,{
    ...init,headers:{ 'Content-Type':'application/json',Authorization:`Bearer ${admin.access_token}`,...init.headers }
  });
  const realm = JSON.parse(await readFile(new URL('../../infra/dev/realm.json',import.meta.url),'utf8')) as { realm:string;clients:Array<{clientId:string}> };
  const existing = await adminFetch('realms/drivy-dev');
  if (existing.status===404) {
    const response = await adminFetch('realms',{ method:'POST',body:JSON.stringify(realm) });
    if (!response.ok) throw new Error('Création du realm local refusée.');
  } else if (!existing.ok) throw new Error('Lecture du realm local refusée.');
  const clientsResponse = await adminFetch('realms/drivy-dev/clients?clientId=drivy-apple');
  if (!clientsResponse.ok) throw new Error('Lecture du client Apple refusée.');
  const clients = z.array(z.object({ publicClient:z.literal(true),standardFlowEnabled:z.literal(true),directAccessGrantsEnabled:z.literal(false),implicitFlowEnabled:z.literal(false),
    redirectUris:z.array(z.string()),attributes:z.record(z.string(),z.string()),defaultClientScopes:z.array(z.string()) }).passthrough()).parse(await clientsResponse.json());
  if (clients.length!==1 || clients[0]?.attributes['pkce.code.challenge.method']!=='S256' ||
      JSON.stringify(clients[0].redirectUris)!==JSON.stringify(['ch.drivy.qualification:/oauth/callback']) ||
      JSON.stringify([...clients[0].defaultClientScopes].sort())!==JSON.stringify(['basic','email','profile'])) throw new Error('Client Apple local non conforme ; exécuter setup-web pour étendre le client précédent au scope email.');
  const fixturePeople = [
    ['demo-admin',fixtureIds.admin,'Camille','Administration'],['demo-instructor',fixtureIds.instructor,'Alex','Moniteur'],
    ['demo-alice',fixtureIds.alice,'Alice','Exemple'],['demo-bob',fixtureIds.bob,'Noé','Exemple'],
    ['demo-other-instructor',fixtureIds.otherInstructor,'Lou','Monitrice'],['demo-foreign',fixtureIds.foreign,'Sacha','Autre-école']
  ] as const;
  let accounts: Account[]=[];
  try { accounts=await loadAccounts(); }
  catch (error) { if (!(error instanceof Error) || !('code' in error) || error.code!=='ENOENT') throw new Error('Comptes locaux existants illisibles ; aucun remplacement de mot de passe.'); }
  for (const [username,personId,firstName,lastName] of fixturePeople) {
    const found = await adminFetch(`realms/drivy-dev/users?username=${encodeURIComponent(username)}&exact=true`);
    if (!found.ok) throw new Error('Recherche de compte synthétique refusée.');
    const users = z.array(z.object({ id:z.uuid(),username:z.string() })).parse(await found.json());
    const saved = accounts.find(account=>account.username===username);
    if (users.length===1 && saved && saved.subject===users[0]?.id && saved.personId===personId) continue;
    if (users.length>0) throw new Error('Compte existant sans correspondance locale vérifiée ; aucune réaffectation automatique.');
    if (saved) throw new Error('Compte fournisseur manquant alors que son lien local existe ; examiner avant recréation.');
    const password=randomBytes(32).toString('base64url');
    const response=await adminFetch('realms/drivy-dev/users',{ method:'POST',body:JSON.stringify({ username,firstName,lastName,
      email:`${username}@example.invalid`,emailVerified:true,enabled:true,requiredActions:[],
      credentials:[{ type:'password',value:password,temporary:false }] }) });
    if (response.status!==201) throw new Error('Création du compte synthétique refusée.');
    const subject=z.uuid().parse(response.headers.get('location')?.split('/').at(-1));
    accounts.push({ username,password,subject,personId });
    await secretFile('accounts.json',accounts);
  }
  const pool=new Pool({ connectionString:databaseUrl });
  try {
    await migrate(pool);
    await seedFixtures(pool,issuer);
    const db=await pool.connect();
    try {
      await db.query('BEGIN');
      for (const account of accounts) {
        const previous=await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[issuer,account.subject]);
        if (previous.rows[0] && previous.rows[0].person_id!==account.personId) throw new Error('Lien d’identité déjà attribué à une autre personne.');
        await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING',[issuer,account.subject,account.personId]);
      }
      await db.query('COMMIT');
    } catch (error) { await db.query('ROLLBACK'); throw error; }
    finally { db.release(); }
  } finally { await pool.end(); }
  console.log('Identité locale prête : 6 comptes synthétiques, client Apple PKCE et liens issuer/subject en base.');
  console.log('Mots de passe uniquement dans infra/dev/.state/accounts.json (ignoré par Git, accès local restreint).');
}
main().catch(error=>{ console.error(error instanceof z.ZodError ? 'Configuration fournisseur locale non conforme.' : error instanceof Error ? error.message : 'Échec du provisionnement local.');process.exitCode=1; });
