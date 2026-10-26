/** Real Keycloak/Mailpit qualification on a disposable realm. Never persist mail links, passwords or tokens. */
import { randomBytes } from 'node:crypto';
import type { Browser, Page } from '../../infra/dev/browser.js';

type Inputs = { browser: Browser; origin:string; apiOrigin:string; issuer:string; keycloakOrigin:string; realmName:string;
  adminPassword:string; clientId:string; clientSecret:string; ownMail:(email:string)=>Promise<string>;
  mailLink:(text:string,origin:string,path:string)=>string; assert:(value:unknown,label:string)=>void; setStage:(value:string)=>void };

export async function verifyAccountRecovery(input: Inputs) {
  const { browser,origin,apiOrigin,issuer,keycloakOrigin,realmName,clientId,clientSecret,assert,setStage } = input;
  const adminResponse = await fetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`, {method:'POST',
    body:new URLSearchParams({client_id:'admin-cli',grant_type:'password',username:'drivy-e2e-admin',password:input.adminPassword})});
  if (!adminResponse.ok) throw new Error('RECOVERY_ADMIN_UNAVAILABLE');
  const admin = await adminResponse.json() as {access_token:string};
  const headers = {Authorization:`Bearer ${admin.access_token}`,'Content-Type':'application/json'};
  const realmURL = `${keycloakOrigin}/admin/realms/${realmName}`;
  const realmResponse = await fetch(realmURL,{headers});
  if (!realmResponse.ok) throw new Error('RECOVERY_REALM_UNAVAILABLE');
  const initial = await realmResponse.json() as {smtpServer:Record<string,string>;actionTokenGeneratedByUserLifespan:number;attributes?:Record<string,string>};
  const email = `recovery-${randomBytes(8).toString('hex')}@example.invalid`;
  const initialPassword = randomBytes(24).toString('base64url'), nextPassword = randomBytes(24).toString('base64url');
  const userResponse = await fetch(`${realmURL}/users`,{method:'POST',headers,body:JSON.stringify({username:email,email,firstName:'Récupération',lastName:'Synthétique',emailVerified:true,enabled:true,
    credentials:[{type:'password',value:initialPassword,temporary:false}]})});
  if (userResponse.status !== 201) throw new Error('RECOVERY_IDENTITY_UNAVAILABLE');
  const userLocation = userResponse.headers.get('location');
  if (!userLocation || new URL(userLocation).origin !== keycloakOrigin) throw new Error('RECOVERY_IDENTITY_INVALID');
  const tokenURL = `${issuer}/protocol/openid-connect/token`;
  const grant = async (password:string) => fetch(tokenURL,{method:'POST',body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,
    grant_type:'password',scope:'openid profile email',username:email,password})});
  const activeResponse = await grant(initialPassword);
  if (!activeResponse.ok) throw new Error('RECOVERY_SESSION_UNAVAILABLE');
  const active = await activeResponse.json() as {refresh_token:string};
  const contexts: Awaited<ReturnType<Browser['newContext']>>[] = [];
  async function page() {
    const context = await browser.newContext({locale:'fr-CH'}); contexts.push(context);
    await context.route('**/*', route => [origin,keycloakOrigin].includes(new URL(route.request().url()).origin) ? route.continue() : route.abort());
    const result = await context.newPage(); result.setDefaultTimeout(15_000); return result;
  }
  const message = 'Si cette adresse correspond à un compte, vous pourrez recevoir un lien de récupération. Si aucun message n’arrive, réessayez plus tard.';
  async function requestLink(target:Page,address:string) {
    await target.goto(`${origin}/app/recover`);
    await target.getByRole('button',{name:'Récupérer mon accès',exact:true}).click();
    await target.locator('input[name="username"]').fill(address);
    await target.locator('input[type="submit"],button[type="submit"]').click();
    await target.getByText(message,{exact:true}).waitFor();
    return target.getByText(message,{exact:true}).innerText();
  }
  async function updateRealm(body:unknown) {
    const response = await fetch(realmURL,{method:'PUT',headers,body:JSON.stringify(body)});
    if (!response.ok) throw new Error('RECOVERY_REALM_UPDATE_FAILED');
  }
  try {
    setStage('récupération : disponibilité anonyme et SMTP réel');
    const availability = await fetch(`${apiOrigin}/v1/account-recovery/options`);
    const options = await availability.json() as {data:{available:boolean;recoveryUrl:string|null}};
    assert(availability.ok && options.data.available && options.data.recoveryUrl === `${origin}/app/recover`,
      'La récupération expose uniquement une entrée contrôlée, sans adresse ni jeton');
    const knownPage = await page(), unknownPage = await page();
    const knownMessage = await requestLink(knownPage,email);
    const unknownMessage = await requestLink(unknownPage,`unknown-${randomBytes(8).toString('hex')}@example.invalid`);
    assert(knownMessage === unknownMessage,'Une adresse connue et une adresse inconnue reçoivent la même réponse conditionnelle');
    const text = await input.ownMail(email);
    const link = input.mailLink(text,keycloakOrigin,`/realms/${realmName}/login-actions/action-token`);
    await knownPage.goto(link);
    await knownPage.locator('input[name="password-new"]').fill(nextPassword);
    await knownPage.locator('input[name="password-confirm"]').fill(nextPassword);
    await knownPage.locator('input[name="logout-sessions"]').check();
    await knownPage.locator('input[type="submit"],button[type="submit"]').click();
    await knownPage.locator('input[name="password-new"]').waitFor({state:'detached'});
    assert((await grant(initialPassword)).status === 400 && (await grant(nextPassword)).ok,
      'Le lien SMTP réel change le mot de passe ; ancien refusé et nouveau accepté');
    const refreshed = await fetch(tokenURL,{method:'POST',body:new URLSearchParams({client_id:clientId,client_secret:clientSecret,
      grant_type:'refresh_token',refresh_token:active.refresh_token})});
    assert(refreshed.status === 400,'Déconnecter les autres appareils révoque leur jeton de renouvellement');
    const replay = await page(); await replay.goto(link);
    assert(await replay.locator('input[name="password-new"]').count() === 0,'Le lien consommé ne permet pas une seconde réinitialisation');
    const session = await knownPage.context().request.get(`${origin}/app/bff/session`);
    assert((await session.json()).authenticated === false,'La récupération autonome ne crée aucune connexion applicative');

    setStage('récupération : lien expiré');
    await updateRealm({actionTokenGeneratedByUserLifespan:1,attributes:{...initial.attributes,'actionTokenGeneratedByUserLifespan.reset-credentials':'1'}});
    const expiryPage = await page(); await requestLink(expiryPage,email);
    const expiredLink = input.mailLink(await input.ownMail(email),keycloakOrigin,`/realms/${realmName}/login-actions/action-token`);
    await new Promise(done => setTimeout(done,2100));
    await expiryPage.goto(expiredLink);
    assert(await expiryPage.locator('input[name="password-new"]').count() === 0,'Un lien expiré ne permet pas de changer le mot de passe');

    setStage('récupération : panne SMTP sans annonce de livraison');
    await updateRealm({smtpServer:{...initial.smtpServer,host:'127.0.0.1',port:'1'}});
    const failedMailPage = await page();
    assert(await requestLink(failedMailPage,email) === unknownMessage,
      'Une panne SMTP garde la réponse conditionnelle et ne révèle pas l’existence du compte');
  } finally {
    await updateRealm({smtpServer:initial.smtpServer,actionTokenGeneratedByUserLifespan:initial.actionTokenGeneratedByUserLifespan,
      attributes:{...initial.attributes,'actionTokenGeneratedByUserLifespan.reset-credentials':''}});
    await fetch(userLocation,{method:'DELETE',headers});
    await Promise.all(contexts.map(context => context.close()));
  }
}
