import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { z } from 'zod';
import { chromium,type Browser } from '../../infra/dev/browser.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider } from '../../apps/web/server/oidc.js';
import { apiOrigin,audience,databaseUrl,issuer,keycloakOrigin,loadAccounts,loadRuntime,stateDirectory,secretFile } from './shared.js';

let stage='préparation';
async function main() {
  const runtime=await loadRuntime();const accounts=await loadAccounts();
  const webRuntime=z.object({clientSecret:z.string()}).parse(JSON.parse(await readFile(new URL('web-runtime.json',stateDirectory),'utf8')));
  const config={origin:'http://127.0.0.1:3002',apiBaseURL:apiOrigin,issuer,clientId:'drivy-web',clientSecret:webRuntime.clientSecret,
    development:true,host:'127.0.0.1',port:3002};
  const identity=await createIdentityProvider(config);
  const pool=new Pool({connectionString:databaseUrl});
  const api=buildApp({pool,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:audience,OIDC_JWKS_URL:`${issuer}/protocol/openid-connect/certs`}),cursorSecret:runtime.cursorSecret});
  const web=await buildWebApp({config,identity,staticRoot:fileURLToPath(new URL('../../apps/web/dist/client/',import.meta.url))});
  let browser:Browser|undefined;const checks:string[]=[];
  function assert(value:unknown,name:string): asserts value {stage=name;if(!value)throw new Error('Échec');checks.push(name);}
  try {
    stage='services loopback';await api.listen({host:'127.0.0.1',port:3001});await web.listen({host:'127.0.0.1',port:3002});
    stage='navigateur isolé';browser=await chromium.launch({channel:z.enum(['msedge','chrome']).parse(process.env.DRIVY_BROWSER_CHANNEL??'msedge'),headless:true});
    const context=await browser.newContext();
    await context.route('**/*',async route=>{
      const origin=new URL(route.request().url()).origin;
      return [config.origin,keycloakOrigin].includes(origin) ? route.continue() : route.abort();
    });
    const page=await context.newPage();stage='application web';await page.goto(`${config.origin}/app`);
    await page.getByRole('button',{name:'Se connecter',exact:true}).waitFor();
    const bootstrap=await context.request.get(`${config.origin}/app/bff/session`);
    const initial=await bootstrap.json() as {csrfToken:string;authenticated:boolean};
    assert(!initial.authenticated,'Session navigateur initiale anonyme');
    stage='début connexion depuis le bouton web';
    await page.getByRole('button',{name:'Se connecter',exact:true}).click();
    await page.waitForURL(url=>url.origin===keycloakOrigin);
    const authURL=new URL(page.url());
    assert(authURL.searchParams.get('code_challenge_method')==='S256' && authURL.searchParams.get('scope')?.includes('email'),'Client web code PKCE et scope email');
    stage='formulaire du fournisseur';const account=accounts.find(item=>item.username==='demo-admin')!;
    await page.locator('input[name="username"]').fill(account.username);await page.locator('input[name="password"]').fill(account.password);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    await page.waitForURL(`${config.origin}/app`);
    await page.getByRole('heading',{name:'Bienvenue dans Drivy'}).waitFor();
    await page.getByRole('heading',{name:'Auto-école Horizon'}).waitFor();
    assert(true,'Connexion par le bouton React et affichage de l’école réelle');
    const sessionResponse=await context.request.get(`${config.origin}/app/bff/session`);
    const session=await sessionResponse.json() as {authenticated:boolean;csrfToken:string;user:{emailVerified:boolean}};
    assert(session.authenticated && session.user.emailVerified,'OIDC réel : compte vérifié et session BFF');
    const meResponse=await context.request.get(`${config.origin}/app/bff/me`);const me=await meResponse.json() as {data:{personId:string}};
    assert(meResponse.status()===200 && me.data.personId===account.personId,'BFF vers API et vraie identité PostgreSQL');
    const cookies=await context.cookies(config.origin);const sessionCookie=cookies.find(item=>item.name==='drivy-dev-session');
    assert(sessionCookie?.httpOnly && sessionCookie.sameSite==='Lax','Cookie HttpOnly SameSite sur loopback de développement');
    assert(!Object.keys(await sessionResponse.json()).some(key=>/token/i.test(key) && key!=='csrfToken'),'Aucun jeton OAuth retourné au frontend');
    assert(await page.evaluate(()=>localStorage.length===0 && sessionStorage.length===0),'Aucune persistance navigateur');
    assert((await context.request.post(`${config.origin}/app/bff/logout`,{headers:{Origin:'https://foreign.example'},data:{}})).status()===403,'Déconnexion forgée refusée');
    const logout=await context.request.post(`${config.origin}/app/bff/logout`,{headers:{Origin:config.origin,'X-CSRF-Token':session.csrfToken},data:{}});
    assert(logout.status()===200 && (await context.request.get(`${config.origin}/app/bff/me`)).status()===401,'Déconnexion BFF et accès privé refusé');
    await secretFile('web-check-result.json',{checkedAt:new Date().toISOString(),browser:browser.version(),checks,passed:checks.length,
      scope:'Windows Edge/Keycloak réel/BFF/API/PostgreSQL, boucle web de connexion uniquement ; invitations et SMTP non couverts par ce contrôle.'});
    console.log(`${checks.length} contrôles web réels réussis : navigateur → Keycloak → BFF → API → PostgreSQL.`);
  } finally {await browser?.close();await web.close();await api.close();await pool.end();}
}
main().catch(()=>{console.error(`Contrôle web interrompu : ${stage}. Aucun jeton ni mot de passe journalisé.`);process.exitCode=1;});
