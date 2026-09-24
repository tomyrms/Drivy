import { createHash,randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import { createRemoteJWKSet,jwtVerify } from 'jose';
import { z } from 'zod';
import { chromium,type Browser } from '../../infra/dev/browser.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { fixtureIds as ids } from '../../apps/api/scripts/fixtures.js';
import { apiOrigin,audience,clientId,databaseUrl,issuer,keycloakOrigin,loadAccounts,loadRuntime,localFetch,redirectUri,secretFile,type Account } from './shared.js';

const tokensSchema=z.object({ access_token:z.string(),id_token:z.string(),refresh_token:z.string(),token_type:z.literal('Bearer') });
type Tokens=z.infer<typeof tokensSchema>;
const tokenEndpoint=`${issuer}/protocol/openid-connect/token`;
let stage='Préparation du contrôle local';
const checks:string[]=[];
function assert(condition: unknown,name: string): asserts condition {
  stage=name;
  if (!condition) throw new Error('Contrôle refusé');
  checks.push(name);
}
function authorizationURL(verifier: string,state: string,nonce: string) {
  const url=new URL(`${issuer}/protocol/openid-connect/auth`);
  url.search=new URLSearchParams({ client_id:clientId,response_type:'code',redirect_uri:redirectUri,scope:'openid profile',
    state,nonce,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',prompt:'login' }).toString();
  return url;
}
async function authorize(browser: Browser,account: Account) {
  stage='Connexion navigateur sur le fournisseur local';
  const verifier=randomBytes(32).toString('base64url');
  const state=randomBytes(32).toString('base64url');
  const nonce=randomBytes(32).toString('base64url');
  const context=await browser.newContext();
  let resolveCallback:(location:string|null)=>void=()=>{};
  const callbackPromise=new Promise<string|null>(resolve=>{ resolveCallback=resolve; });
  let timeout:ReturnType<typeof setTimeout>|undefined;
  try {
    // Profil navigateur éphémère, sans trace/screenshot et sans accès aux comptes personnels.
    await context.route('**/*',async route=>{
      try {
      const target=new URL(route.request().url());
      if (target.origin!==keycloakOrigin) return route.abort();
      if (route.request().method()==='POST' && target.pathname.endsWith('/login-actions/authenticate')) {
        // Le formulaire et ses cookies restent ceux du vrai navigateur. Intercepter uniquement
        // la redirection finale évite de lancer un gestionnaire de protocole Windows personnel.
        const response=await route.fetch({ maxRedirects:0,timeout:10_000 });
        const location=response.headers()['location'];
        if (response.status()===302 && location?.startsWith(`${redirectUri}?`)) {
          await route.abort('aborted');
          await response.dispose();
          resolveCallback(location);
          return;
        }
        return route.fulfill({ response });
      }
      return route.continue();
      } catch {
        // Les erreurs réseau Playwright peuvent inclure le formulaire dans leur diagnostic.
        // Conserver uniquement l'échec, sans corps POST ni URL contenant un code OAuth.
        resolveCallback(null);
        await route.abort('failed').catch(()=>{});
      }
    });
    const page=await context.newPage();
    stage='Ouverture du formulaire Keycloak dans le navigateur';
    await page.goto(authorizationURL(verifier,state,nonce).href,{ waitUntil:'domcontentloaded' });
    stage='Saisie du compte synthétique dans le formulaire';
    await page.locator('input[name="username"]').fill(account.username);
    await page.locator('input[name="password"]').fill(account.password);
    stage='Validation du formulaire et réception du callback OAuth';
    await page.locator('input[type="submit"],button[type="submit"]').first().click({ noWaitAfter:true });
    const callbackLocation=await Promise.race([callbackPromise,new Promise<never>((_,reject)=>{
      timeout=setTimeout(()=>reject(new Error('Callback absent')),15_000);
    })]);
    if (!callbackLocation) throw new Error('Retour OIDC absent');
    const callback=new URL(callbackLocation);
    await page.goto('about:blank',{ waitUntil:'domcontentloaded' });
    stage='Vérification du state et de l’issuer du callback OAuth';
    if (callback.href.split('?')[0]!==redirectUri || callback.searchParams.get('state')!==state || callback.searchParams.get('iss')!==issuer) {
      throw new Error('Retour OIDC non conforme');
    }
    const code=callback.searchParams.get('code');
    if (!code) throw new Error('Code absent');
    return { code,verifier,nonce };
  } finally { if (timeout) clearTimeout(timeout);await context.close(); }
}
const exchange = (code:string,verifier:string) => localFetch(tokenEndpoint,{ method:'POST',body:new URLSearchParams({
  grant_type:'authorization_code',client_id:clientId,redirect_uri:redirectUri,code,code_verifier:verifier
}) });
async function api(path:string,token:string) {
  return localFetch(`${apiOrigin}${path}`,{ headers:{ Authorization:`Bearer ${token}` } });
}
async function main() {
  const runtime=await loadRuntime();
  const accounts=await loadAccounts();
  const pool=new Pool({ connectionString:databaseUrl });
  const app=buildApp({ pool,verifyToken:createTokenVerifier({ OIDC_ISSUER:issuer,OIDC_AUDIENCE:audience,OIDC_JWKS_URL:`${issuer}/protocol/openid-connect/certs` }),cursorSecret:runtime.cursorSecret });
  let browser:Browser|undefined;
  const jwks=createRemoteJWKSet(new URL(`${issuer}/protocol/openid-connect/certs`));
  try {
    stage='Ouverture de l’API locale sur le port3001 libre';
    await app.listen({ host:'127.0.0.1',port:3001 });
    stage='Lancement du navigateur local isolé';
    const channel=z.enum(['msedge','chrome']).parse(process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge');
    browser=await chromium.launch({ channel,headless:true });
    const discovery=await localFetch(`${issuer}/.well-known/openid-configuration`);
    const metadata=z.object({ issuer:z.literal(issuer),authorization_endpoint:z.string(),token_endpoint:z.literal(tokenEndpoint),code_challenge_methods_supported:z.array(z.string()) }).parse(await discovery.json());
    assert(metadata.code_challenge_methods_supported.includes('S256'),'Découverte OIDC et PKCE S256 annoncés');
    const noChallenge=authorizationURL('unused','state','nonce');noChallenge.searchParams.delete('code_challenge');noChallenge.searchParams.delete('code_challenge_method');
    const withoutPkce=await localFetch(noChallenge);
    const pkceLocation=withoutPkce.headers.get('location');
    const pkceError=pkceLocation ? new URL(pkceLocation) : undefined;
    assert(withoutPkce.status===400 || (withoutPkce.status===302 && pkceError?.href.split('?')[0]===redirectUri &&
      pkceError.searchParams.get('error')==='invalid_request' && !pkceError.searchParams.has('code')),'Autorisation sans PKCE refusée par le fournisseur');
    const wrongRedirect=authorizationURL('unused','state','nonce');wrongRedirect.searchParams.set('redirect_uri','http://127.0.0.1:3999/not-registered');
    assert((await localFetch(wrongRedirect)).status===400,'Redirection non enregistrée refusée');
    const credentialsDenied=await localFetch(tokenEndpoint,{ method:'POST',body:new URLSearchParams({ grant_type:'password',client_id:clientId,username:'unused',password:'unused' }) });
    assert(credentialsDenied.status===400 || credentialsDenied.status===401,'Password grant désactivé pour le client Apple');
    const tokensByUser=new Map<string,Tokens>();
    for (const account of accounts) {
      const authorization=await authorize(browser,account);
      const response=await exchange(authorization.code,authorization.verifier);
      if (!response.ok) throw new Error('Échange code refusé');
      const tokens=tokensSchema.parse(await response.json());
      const access=await jwtVerify(tokens.access_token,jwks,{ issuer,audience,algorithms:['RS256'] });
      const identity=await jwtVerify(tokens.id_token,jwks,{ issuer,audience:clientId,algorithms:['RS256'] });
      assert(access.payload.sub===account.subject && identity.payload.sub===account.subject && identity.payload.nonce===authorization.nonce,
        `Code navigateur, signatures, nonce et subject vérifiés (${account.username})`);
      const me=await api('/v1/me',tokens.access_token);
      stage='Réponse JSON du profil authentifié';
      const body=z.object({ data:z.object({ personId:z.uuid() }) }).parse(await me.json());
      assert(me.status===200 && body.data.personId===account.personId,`Identité fournisseur reliée à /v1/me (${account.username})`);
      tokensByUser.set(account.username,tokens);
    }
    const alice=tokensByUser.get('demo-alice')!;
    const instructor=tokensByUser.get('demo-instructor')!;
    const admin=tokensByUser.get('demo-admin')!;
    const other=tokensByUser.get('demo-other-instructor')!;
    const school=`/v1/schools/${ids.schoolA}`;
    assert((await api(`${school}/learners/${ids.aliceLearner}`,alice.access_token)).status===200,'Élève : lecture de son dossier');
    assert((await api(`${school}/learners/${ids.bobLearner}`,alice.access_token)).status===404,'Élève : autre dossier invisible');
    assert((await api(`${school}/trainings/${ids.aliceTraining}`,instructor.access_token)).status===200,'Moniteur : formation affectée visible');
    assert((await api(`${school}/trainings/${ids.bobTraining}`,instructor.access_token)).status===404,'Moniteur : formation non affectée invisible');
    assert((await api(`/v1/schools/${ids.schoolB}`,admin.access_token)).status===403,'Administrateur : autre école refusée');
    assert((await api(`${school}/learners/${ids.foreignLearner}`,admin.access_token)).status===404,'Identifiant d’une autre école non divulgué');
    const unassigned=await api(`${school}/learners`,other.access_token);
    const page=z.object({ data:z.object({ items:z.array(z.unknown()) }) }).parse(await unassigned.json());
    assert(unassigned.status===200 && page.data.items.length===0,'Moniteur non affecté : liste vide');
    assert((await api('/v1/me',alice.id_token)).status===401,'ID token refusé comme autorisation API');
    const wrongVerifier=await authorize(browser,accounts.find(account=>account.username==='demo-alice')!);
    assert((await exchange(wrongVerifier.code,randomBytes(32).toString('base64url'))).status===400,'Code avec mauvais vérificateur PKCE refusé');
    stage='Échange du refresh token du client public';
    const refresh=await localFetch(tokenEndpoint,{ method:'POST',body:new URLSearchParams({ grant_type:'refresh_token',client_id:clientId,refresh_token:alice.refresh_token }) });
    const refreshed=tokensSchema.parse(await refresh.json());
    assert(refresh.ok && (await api('/v1/me',refreshed.access_token)).status===200,'Renouvellement du jeton et accès API vérifiés');
    const replay=await localFetch(tokenEndpoint,{ method:'POST',body:new URLSearchParams({ grant_type:'refresh_token',client_id:clientId,refresh_token:alice.refresh_token }) });
    assert(replay.status===400,'Ancien refresh token refusé après rotation');
    const repeatedCode=await authorize(browser,accounts.find(account=>account.username==='demo-alice')!);
    assert((await exchange(repeatedCode.code,repeatedCode.verifier)).status===200 &&
      (await exchange(repeatedCode.code,repeatedCode.verifier)).status===400,'Code déjà échangé non réutilisable');
    const before=await pool.query<{status:string;access_epoch:number}>('SELECT status,access_epoch FROM drivy.membership WHERE id=$1',[ids.instructorMember]);
    const original=before.rows[0];
    if (!original || original.status!=='ACTIVE') throw new Error('Fixture de révocation non active');
    await pool.query("UPDATE drivy.membership SET status='REVOKED',access_epoch=access_epoch+1 WHERE id=$1 AND status='ACTIVE' AND access_epoch=$2",[ids.instructorMember,original.access_epoch]);
    try {
      assert((await api(`${school}/trainings/${ids.aliceTraining}`,instructor.access_token)).status===403,'Révocation scolaire effective malgré access token fournisseur valide');
    } finally {
      await pool.query("UPDATE drivy.membership SET status='ACTIVE',access_epoch=access_epoch+1 WHERE id=$1 AND status='REVOKED' AND access_epoch=$2",[ids.instructorMember,original.access_epoch+1]);
    }
    await secretFile('check-result.json',{ checkedAt:new Date().toISOString(),provider:'Keycloak26.7.4',browser:browser.version(),checks,passed:checks.length,
      scope:'Loopback local, vrai navigateur/Authorization Code+PKCE, API HTTP/PostgreSQL ; aucun client iOS exécuté.' });
    console.log(`${checks.length} contrôles réels réussis : navigateur → code PKCE → Keycloak → API → PostgreSQL.`);
    console.log('Rapport sans jetons dans infra/dev/.state/check-result.json. Aucun essai iPhone physique revendiqué.');
  } finally { await browser?.close();await app.close();await pool.end(); }
}
main().catch(()=>{ console.error(`Contrôle interrompu : ${stage}. Aucun jeton, mot de passe ou détail de réponse journalisé.`);process.exitCode=1; });
