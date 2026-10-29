/** Complete synthetic browser qualification. No token, identity credential, request trace or real account is an artifact. */
import { createHash,randomBytes,randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile,mkdir,mkdtemp,writeFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve,sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { z } from 'zod';
import { createRemoteJWKSet,jwtVerify } from 'jose';
import { chromium,type Browser } from '../../infra/dev/browser.js';
import type { Page } from '../../infra/dev/browser.js';
import { migrate } from '../../apps/api/scripts/migrations.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { createKeycloakProvisioner } from '../../apps/api/src/account-provisioning.js';
import { deliverOneInvitation,type InvitationMailConfig } from '../../apps/api/src/invitation-mail.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider } from '../../apps/web/server/oidc.js';
import { SessionStore } from '../../apps/web/server/session.js';
import { parseMetadata } from '../../apps/web/client/command-core.js';
import { verifySchoolFirstLesson } from './check-school-first-lesson.js';
import { verifyAuditV2 } from './check-audit-v2-acceptance.js';
import { verifySchoolFormations } from './check-school-formations.js';
import { verifyPersonalWelcome } from './check-personal-welcome.js';
import { verifyAccountRecovery } from './check-school-account-recovery.js';
import { verifySchoolCodeEntry } from './check-school-code-entry.js';

const keycloakOrigin='http://127.0.0.1:8081',realmName='drivy-opening-e2e',issuer=`${keycloakOrigin}/realms/${realmName}`;
const origin='http://127.0.0.1:3002',apiOrigin='http://127.0.0.1:3001';
const mailOrigin='http://127.0.0.1:8025';
const keycloakImage='quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c';
const artifactDirectory=fileURLToPath(new URL('../../artifacts/onboarding-web-synthetic/',import.meta.url));
const containerName=`drivy-opening-e2e-${randomUUID()}`;
const checks:string[]=[];let stage='initialisation de la recette';
const inspectedMessages=new Set<string>();
const messageSchema=z.object({ID:z.string().regex(/^[a-zA-Z0-9-]+$/),MessageID:z.string(),To:z.array(z.object({Address:z.string()}))});
async function ownMail(email:string,matches:(message:z.infer<typeof messageSchema>)=>boolean=()=>true) {
  for(let attempt=0;attempt<40;attempt++) {
    const response=await fetch(`${mailOrigin}/api/v1/messages?limit=500`,{signal:AbortSignal.timeout(5000),redirect:'error'});
    if(!response.ok)throw new Error('MAIL_UNAVAILABLE');
    const messages=z.object({messages:z.array(messageSchema)}).parse(await response.json()).messages;
    const message=messages.find(item=>!inspectedMessages.has(item.ID)&&item.To.some(to=>to.Address===email)&&matches(item));
    if(message) {
      const detail=await fetch(`${mailOrigin}/api/v1/message/${message.ID}`,{signal:AbortSignal.timeout(5000),redirect:'error'});
      if(!detail.ok)throw new Error('MAIL_UNAVAILABLE');inspectedMessages.add(message.ID);
      return z.object({Text:z.string()}).parse(await detail.json()).Text;
    }
    await new Promise(done=>setTimeout(done,500));
  }
  throw new Error('MAIL_MISSING');
}
function mailLink(text:string,expectedOrigin:string,path:string) {
  const links=(text.match(/https?:\/\/[^\s<>]+/g)??[]).map(value=>new URL(value)).filter(url=>url.origin===expectedOrigin&&url.pathname===path);
  if(links.length!==1||links[0]!.username||links[0]!.password)throw new Error('MAIL_LINK_INVALID');return links[0]!.href;
}
// Un contrôle réussi n'est jamais présenté comme l'étape en échec si l'action suivante échoue.
function assert(value:unknown,label:string):asserts value {stage=label;if(!value)throw new Error('CHECK_FAILED');checks.push(label);stage=`après « ${label} »`;}
function docker(args:string[]):Promise<void> {return new Promise((done,fail)=>{const child=spawn('docker',args,{stdio:'ignore',windowsHide:true});child.on('error',()=>fail(new Error('DOCKER_UNAVAILABLE')));child.on('exit',code=>code===0?done():fail(new Error('DOCKER_FAILED')));});}
function runBuild(command:string,args:string[]):Promise<void> {return new Promise((done,fail)=>{const child=spawn(command,args,{stdio:'ignore',windowsHide:true});child.on('error',()=>fail(new Error('IDENTITY_BUILD_UNAVAILABLE')));child.on('exit',code=>code===0?done():fail(new Error('IDENTITY_BUILD_FAILED')));});}
async function buildIdentityProvider(temporary:string) {
  const lock=z.object({keycloak:z.object({version:z.literal('26.7.4'),url:z.url(),sha256:z.string().regex(/^[a-f0-9]{64}$/)})}).parse(
    JSON.parse(await readFile(new URL('../../infra/deploy/runtime-lock.json',import.meta.url),'utf8'))).keycloak;
  const download=await fetch(lock.url,{signal:AbortSignal.timeout(120_000)});
  if(!download.ok)throw new Error('IDENTITY_DISTRIBUTION_UNAVAILABLE');
  const archive=Buffer.from(await download.arrayBuffer());
  if(createHash('sha256').update(archive).digest('hex')!==lock.sha256)throw new Error('IDENTITY_DISTRIBUTION_HASH_MISMATCH');
  const archivePath=resolve(temporary,'keycloak.tar.gz'),provider=resolve(temporary,'drivy-direct-grant-auth-time.jar');
  await writeFile(archivePath,archive);await runBuild('tar',['-xzf',archivePath,'-C',temporary]);
  await runBuild(process.execPath,[fileURLToPath(new URL('../../infra/identity/build-provider.mjs',import.meta.url)),
    '--distribution',resolve(temporary,`keycloak-${lock.version}`),'--output',provider]);
  return provider;
}
async function waitFor(url:string) {
  for(let attempt=0;attempt<120;attempt++){try{const response=await fetch(url,{signal:AbortSignal.timeout(1000),redirect:'error'});if(response.ok)return;}catch{/* Local service is still starting. */}await new Promise(done=>setTimeout(done,1000));}
  throw new Error('SERVICE_START_TIMEOUT');
}
/** Sign-in with the Drivy form (the password never goes through a provider page). */
async function signIn(page:Page,email:string,password:string) {
  await page.getByLabel('E-mail',{exact:true}).fill(email);await page.getByLabel('Mot de passe',{exact:true}).fill(password);
  await page.getByRole('button',{name:'Se connecter',exact:true}).click();
  await page.getByRole('heading',{name:'Se connecter',exact:true}).waitFor({state:'hidden'});
}
type NewAccount={firstName:string;lastName:string;email:string;password:string};
async function fillRegistration(page:Page,account:NewAccount) {
  await page.getByLabel('Prénom',{exact:true}).fill(account.firstName);await page.getByLabel('Nom',{exact:true}).fill(account.lastName);
  await page.getByLabel('E-mail',{exact:true}).fill(account.email);await page.getByLabel('Mot de passe',{exact:true}).fill(account.password);
  await page.getByRole('button',{name:'Créer mon compte',exact:true}).click();
}
/** Account creation with the code or link already opened; waits until the form is gone. */
async function register(page:Page,account:NewAccount) {
  await fillRegistration(page,account);
  const refused=page.getByRole('region',{name:'Créer votre compte',exact:true}).getByRole('alert');
  await Promise.race([page.getByRole('button',{name:'Créer mon compte',exact:true}).waitFor({state:'detached'}),refused.waitFor()]);
  // Le message affiché (texte d'interface, sans donnée de personne) rejoint l'étape pour le diagnostic de la recette.
  if(await refused.count())throw new Error(`REGISTRATION_REFUSED: ${await refused.innerText()}`);
}
/** A refused creation: returns the message shown, the form stays. */
async function submitRegistration(page:Page,account:NewAccount) {
  await fillRegistration(page,account);const notice=page.getByRole('region',{name:'Créer votre compte',exact:true}).getByRole('alert');await notice.waitFor();return notice.innerText();
}
/** Open a real disclosure through its public control; closed Base UI panels may be unmounted. */
async function expand(root:Page|ReturnType<Page['locator']>,name:string|RegExp) {
  const trigger=root.getByRole('button',{name,exact:typeof name==='string'});
  await trigger.waitFor();
  if(await trigger.getAttribute('aria-expanded')!=='true')await trigger.click();
}
async function main() {
  const databaseURL=process.env.ONBOARDING_E2E_DATABASE_URL;
  if(!databaseURL)throw new Error('ISOLATED_DATABASE_REQUIRED');const target=new URL(databaseURL);
  if(target.pathname!=='/drivy_onboarding_e2e'||!['localhost','127.0.0.1','[::1]'].includes(target.hostname))throw new Error('ISOLATED_DATABASE_REQUIRED');
  const administration=new Pool({connectionString:databaseURL,max:3});
  let runtime:Pool|undefined,mailer:Pool|undefined,browser:Browser|undefined,api:ReturnType<typeof buildApp>|undefined,web:Awaited<ReturnType<typeof buildWebApp>>|undefined;
  let temporary:string|undefined,containerStarted=false;
  const syntheticSecret=()=>randomBytes(36).toString('base64url');
  try {
    stage='base vierge et migrations non privilégiées';
    assert((await administration.query("SELECT to_regnamespace('drivy') AS schema")).rows[0].schema===null,'La recette commence dans une base vide isolée');
    for(const role of ['drivy_e2e_migrator','drivy_app','drivy_invitation_mailer','drivy_course_worker'])await administration.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
    await administration.query('GRANT CREATE ON DATABASE drivy_onboarding_e2e TO drivy_e2e_migrator');
    await administration.query('GRANT USAGE,CREATE ON SCHEMA public TO drivy_e2e_migrator');
    await administration.query('GRANT drivy_app,drivy_invitation_mailer,drivy_course_worker TO drivy_e2e_migrator WITH ADMIN OPTION');
    const migrator=new Pool({connectionString:databaseURL,options:'-c role=drivy_e2e_migrator'});
    try{await migrate(migrator);}finally{await migrator.end();}
    runtime=new Pool({connectionString:databaseURL,options:'-c role=drivy_app',max:8});
    mailer=new Pool({connectionString:databaseURL,options:'-c role=drivy_invitation_mailer',max:2});
    const runtimeRole=(await runtime.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0];
    assert(!runtimeRole.rolsuper&&!runtimeRole.rolbypassrls,'Le service métier utilise drivy_app sans BYPASSRLS');

    stage='serveur OIDC éphémère';temporary=await mkdtemp(resolve(tmpdir(),'drivy-opening-e2e-'));
    const adminPassword=syntheticSecret(),operatorPassword=syntheticSecret(),consumerPassword=syntheticSecret(),clientSecret=syntheticSecret(),accountsSecret=syntheticSecret();
    const envPath=resolve(temporary,'keycloak.env');
    stage='compilation du fournisseur d’identité contre la distribution verrouillée';
    const identityProviderJar=await buildIdentityProvider(temporary);
    await writeFile(envPath,`KC_BOOTSTRAP_ADMIN_USERNAME=drivy-e2e-admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=${adminPassword}\nKC_HOSTNAME=${keycloakOrigin}\nKC_HTTP_ENABLED=true\nKC_LOG_LEVEL=warn\n`,{mode:0o600});
    stage='serveur OIDC éphémère avec le fournisseur d’identité compilé';
    await docker(['run','--detach','--rm','--name',containerName,'--env-file',envPath,'--publish','127.0.0.1:8081:8080','--add-host','host.docker.internal:host-gateway',
      '--mount',`type=bind,source=${identityProviderJar},target=/opt/keycloak/providers/drivy-direct-grant-auth-time.jar,readonly`,'--mount',`type=bind,source=${fileURLToPath(new URL('../../infra/identity/themes/drivy/',import.meta.url))},target=/opt/keycloak/themes/drivy,readonly`,keycloakImage,'start-dev']);containerStarted=true;
    await waitFor(`${keycloakOrigin}/realms/master/.well-known/openid-configuration`);
    const authentication=await fetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({client_id:'admin-cli',grant_type:'password',username:'drivy-e2e-admin',password:adminPassword})});
    if(!authentication.ok)throw new Error('OIDC_ADMIN_UNAVAILABLE');const auth=await authentication.json() as {access_token?:string};if(!auth.access_token)throw new Error('OIDC_ADMIN_UNAVAILABLE');
    const realm=JSON.parse(await readFile(new URL('../../infra/dev/realm.json',import.meta.url),'utf8')) as Record<string,unknown>;
    Object.assign(realm,JSON.parse(await readFile(new URL('../../infra/identity/direct-grant-flow.json',import.meta.url),'utf8')));
    // L'inscription libre est fermée : un compte ne se crée qu'avec un code ou un lien valable, par le client de service de l'API.
    realm.realm=realmName;realm.displayName='Drivy · Recette synthétique';realm.registrationAllowed=false;realm.verifyEmail=false;realm.resetPasswordAllowed=true;realm.loginTheme='drivy';
    realm.smtpServer={host:'host.docker.internal',port:'1025',from:'identity@drivy.example.invalid',ssl:'false',starttls:'false',auth:'false'};
    realm.clients=[{clientId:'drivy-web-e2e',protocol:'openid-connect',enabled:true,publicClient:false,secret:clientSecret,standardFlowEnabled:true,
      directAccessGrantsEnabled:true,implicitFlowEnabled:false,serviceAccountsEnabled:false,fullScopeAllowed:false,
      redirectUris:[`${origin}/app/bff/callback`],webOrigins:[],attributes:{'pkce.code.challenge.method':'S256'},defaultClientScopes:['basic','profile','email'],optionalClientScopes:[],
      protocolMappers:[{name:'drivy-api-audience',protocol:'openid-connect',protocolMapper:'oidc-audience-mapper',consentRequired:false,
        config:{'included.custom.audience':'drivy-api','id.token.claim':'false','access.token.claim':'true','introspection.token.claim':'true'}}]},
      {clientId:'drivy-accounts-e2e',protocol:'openid-connect',enabled:true,publicClient:false,secret:accountsSecret,standardFlowEnabled:false,
        directAccessGrantsEnabled:false,implicitFlowEnabled:false,serviceAccountsEnabled:true,fullScopeAllowed:true,redirectUris:[],webOrigins:[]}];
    realm.users=[{username:'operateur-recette',enabled:true,email:'operator@example.invalid',emailVerified:true,firstName:'Opérateur',lastName:'Synthétique',
      credentials:[{type:'password',value:operatorPassword,temporary:false}]},
      {username:'service-account-drivy-accounts-e2e',enabled:true,serviceAccountClientId:'drivy-accounts-e2e',clientRoles:{'realm-management':['manage-users']}}];
    const realmResponse=await fetch(`${keycloakOrigin}/admin/realms`,{method:'POST',headers:{Authorization:`Bearer ${auth.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(realm)});
    if(!realmResponse.ok)throw new Error('OIDC_REALM_FAILED');
    const users=await fetch(`${keycloakOrigin}/admin/realms/${realmName}/users?username=operateur-recette&exact=true`,{headers:{Authorization:`Bearer ${auth.access_token}`}});
    if(!users.ok)throw new Error('OIDC_OPERATOR_FAILED');const operatorList=await users.json() as {id:string}[];if(operatorList.length!==1)throw new Error('OIDC_OPERATOR_FAILED');
    delete auth.access_token;
    // JWTs stay in memory. Both proofs are signature/issuer/audience checked, never decoded as trusted data.
    const identityKeys=createRemoteJWKSet(new URL(`${issuer}/protocol/openid-connect/certs`));
    const grantSchema=z.object({access_token:z.string(),id_token:z.string(),refresh_token:z.string()});
    async function passwordGrant(email:string,password:string) {
      const response=await fetch(`${issuer}/protocol/openid-connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:new URLSearchParams({client_id:'drivy-web-e2e',client_secret:clientSecret,grant_type:'password',scope:'openid profile email',username:email,password})});
      if(!response.ok)throw new Error('DIRECT_GRANT_REFUSED');return grantSchema.parse(await response.json());
    }
    async function authenticationTime(tokens:z.infer<typeof grantSchema>) {
      const [access,id]=await Promise.all([
        jwtVerify(tokens.access_token,identityKeys,{issuer,audience:'drivy-api',algorithms:['RS256']}),
        jwtVerify(tokens.id_token,identityKeys,{issuer,audience:'drivy-web-e2e',algorithms:['RS256']})]);
      const proof=z.object({auth_time:z.number().int().nonnegative(),sub:z.string()});
      const a=proof.parse(access.payload),i=proof.parse(id.payload);
      assert(a.auth_time===i.auth_time&&a.sub===i.sub,'Les jetons accès et identité signés portent la même preuve d’authentification');
      return a.auth_time;
    }
    stage='preuve d’authentification du mot de passe et renouvellement réel';
    const loginStarted=Math.floor(Date.now()/1000),initialGrant=await passwordGrant('operator@example.invalid',operatorPassword);
    const initialAuthTime=await authenticationTime(initialGrant);
    assert(initialAuthTime>=loginStarted&&initialAuthTime<=Math.floor(Date.now()/1000),'La connexion par mot de passe porte une heure d’authentification récente');
    // Cross a second boundary so a mistaken refresh-time timestamp cannot pass equality by chance.
    while(Math.floor(Date.now()/1000)<=initialAuthTime)await new Promise(done=>setTimeout(done,100));
    const refreshedResponse=await fetch(`${issuer}/protocol/openid-connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({client_id:'drivy-web-e2e',client_secret:clientSecret,grant_type:'refresh_token',refresh_token:initialGrant.refresh_token})});
    if(!refreshedResponse.ok)throw new Error('DIRECT_GRANT_REFRESH_REFUSED');
    const refreshedGrant=grantSchema.parse(await refreshedResponse.json());
    assert(await authenticationTime(refreshedGrant)===initialAuthTime,'Le renouvellement ne rajeunit pas la preuve d’authentification');
    const nextLoginStarted=Math.floor(Date.now()/1000),nextGrant=await passwordGrant('operator@example.invalid',operatorPassword);
    const nextAuthTime=await authenticationTime(nextGrant);
    assert(nextAuthTime>initialAuthTime&&nextAuthTime>=nextLoginStarted&&nextAuthTime<=Math.floor(Date.now()/1000),
      'Une nouvelle validation du mot de passe produit une nouvelle preuve récente');
    const config={origin,apiBaseURL:apiOrigin,issuer,clientId:'drivy-web-e2e',clientSecret,development:true,host:'127.0.0.1',port:3002,accountRecoveryEnabled:true};
    const invitationMail:InvitationMailConfig={webURL:`${origin}/app/invitation`,encryptionKey:randomBytes(32).toString('hex'),host:'127.0.0.1',port:1025,
      secure:false,requireTLS:false,from:'school@drivy.example.invalid'};
    api=buildApp({pool:runtime,accountRecovery:{available:true,recoveryUrl:origin+'/app/recover'},verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/protocol/openid-connect/certs`}),
      cursorSecret:syntheticSecret(),invitationMail,schoolOpening:{operators:[{issuer,subject:operatorList[0]!.id}],validityDays:7},
      provisionAccount:createKeycloakProvisioner({baseURL:keycloakOrigin,realm:realmName,clientId:'drivy-accounts-e2e',clientSecret:accountsSecret})});
    const sessionStore=new SessionStore();
    web=await buildWebApp({config,identity:await createIdentityProvider(config),store:sessionStore,staticRoot:fileURLToPath(new URL('../../apps/web/dist/client/',import.meta.url))});
    await api.listen({host:'127.0.0.1',port:3001});await web.listen({host:'127.0.0.1',port:3002});
    await mkdir(artifactDirectory,{recursive:true});
    stage='navigateur Chromium';browser=await chromium.launch({headless:true});
    const operatorContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
    let consumerContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
    async function accessTokenFor(context=consumerContext) {
      const identityResponse=await context.request.get(`${origin}/app/bff/me`);
      if(!identityResponse.ok())throw new Error('PERSONAL_SESSION_IDENTITY_UNAVAILABLE');
      const cookie=(await context.cookies(origin)).find(item=>item.name==='drivy-dev-session');
      const token=sessionStore.get(cookie?.value)?.tokens?.accessToken;
      if(!token)throw new Error('PERSONAL_SESSION_IDENTITY_UNAVAILABLE');return token;
    }
    for(const context of [operatorContext,consumerContext])await context.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const operatorPage=await operatorContext.newPage();operatorPage.setDefaultTimeout(20_000);
    stage='connexion opérateur par le formulaire';await operatorPage.goto(`${origin}/app/operateur`);
    await signIn(operatorPage,'operator@example.invalid',operatorPassword);
    assert(new URL(operatorPage.url()).origin===origin,'La connexion se fait sur la page Drivy, sans détour par le fournisseur');
    stage='génération du lien via l’interface opérateur';await operatorPage.getByRole('button',{name:'Créer un lien d’ouverture',exact:true}).click();
    const linkInput=operatorPage.getByLabel('Lien d’ouverture',{exact:true});await linkInput.waitFor();const openingLink=await linkInput.inputValue();
    assert(new URL(openingLink).pathname==='/app/ouvrir' && !new URL(openingLink).search,'Le lien de création porte son secret dans le fragment uniquement');
    const openingCode=await operatorPage.getByLabel('Code d’ouverture',{exact:true}).inputValue();
    assert(/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/.test(openingCode)&&new URL(openingLink).hash===`#token=${openingCode}`,'Le lien porte un code court, lisible et saisissable à la main');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.school')).rows[0].n===0,'Créer ou consulter un lien ne crée pas d’école');

    let page=await consumerContext.newPage();page.setDefaultTimeout(20_000);
    stage='inscription libre fermée chez le fournisseur';
    const registration=await fetch(`${issuer}/protocol/openid-connect/registrations?client_id=drivy-web-e2e&response_type=code&scope=openid&redirect_uri=${encodeURIComponent(`${origin}/app/bff/callback`)}`);
    assert(!(await registration.text()).includes('name="password-confirm"'),'Le fournisseur ne propose plus de formulaire d’inscription libre');
    stage='visite du lien et création du compte avec son code';await page.goto(openingLink);
    await page.getByRole('heading',{name:'Créer votre compte',exact:true}).waitFor();
    assert(new URL(page.url()).hash==='','Le secret du lien est retiré avant la connexion');
    await register(page,{firstName:'Responsable',lastName:'Synthétique',email:'school@example.invalid',password:consumerPassword});
    await page.getByLabel('Nom de l’auto-école',{exact:true}).waitFor();
    assert(new URL(page.url()).origin===origin&&new URL(page.url()).pathname==='/app/ouvrir','Le compte créé arrive directement sur le formulaire de l’école');
    const openedSession=await consumerContext.request.get(`${origin}/app/bff/session`);
    assert(z.object({authenticated:z.literal(true)}).safeParse(await openedSession.json()).success,'Le compte créé avec le code est aussitôt connecté');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.person')).rows[0].n===0,'Le nouveau compte OIDC n’est pas créé dans la base métier avant confirmation');
    assert(await page.getByLabel('Nom du responsable',{exact:true}).inputValue()==='Responsable Synthétique'
      &&await page.getByLabel('E-mail de l’école',{exact:true}).inputValue()==='school@example.invalid',
      'L’ouverture reprend le nom et l’adresse du compte sans nouvelle saisie');
    assert(!(await page.getByRole('checkbox',{name:'Je donne aussi des leçons',exact:true}).isChecked()),
      'Le rôle moniteur reste un choix explicite à l’ouverture de l’école');
    stage='création volontaire et perte de réponse navigateur';
    await page.getByLabel('Nom de l’auto-école',{exact:true}).fill('Auto-école Recette · synthétique');
    assert(await page.getByLabel('Nom de l’auto-école',{exact:true}).evaluate(element=>element.getBoundingClientRect().height>=40),
      'Les champs d’ouverture conservent une cible d’au moins 40 pixels sur ordinateur');
    await page.setViewportSize({width:390,height:844});
    assert(await page.getByLabel('Nom de l’auto-école',{exact:true}).evaluate(element=>element.getBoundingClientRect().height>=44),
      'Les champs d’ouverture conservent une cible d’au moins 44 pixels sur mobile');
    await page.setViewportSize({width:1440,height:1100});
    stage='erreur de fuseau ciblée avant création';
    const openingZone=page.getByLabel('Fuseau horaire',{exact:true});
    await openingZone.fill('Zurich');
    await page.getByRole('button',{name:'Créer mon école',exact:true}).click();
    await page.waitForFunction(()=>document.activeElement?.getAttribute('name')==='timeZone');
    const zoneError=await openingZone.evaluate(element=>(element.getAttribute('aria-describedby')??'').split(/\s+/).filter(Boolean).some(id=>!!document.getElementById(id)?.textContent?.trim()));
    assert(await openingZone.getAttribute('aria-invalid')==='true' && await openingZone.isVisible() && zoneError,
      'Un fuseau invalide cible le champ visible et lui associe une explication');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.school')).rows[0].n===0,'Une saisie invalide ne consomme pas le lien et ne crée aucune école');
    await openingZone.fill('Europe/Zurich');
    await page.getByRole('checkbox',{name:'Je donne aussi des leçons',exact:true}).check();
    stage='création volontaire et perte de réponse navigateur';
    await page.route('**/app/bff/opening/create',async route=>{await route.fetch();await route.abort('failed');},{times:1});
    await page.getByRole('button',{name:'Créer mon école',exact:true}).click();
    await page.getByRole('heading',{name:'Permis enseignés',exact:true}).waitFor();
    const school=(await administration.query('SELECT id,status FROM drivy.school')).rows[0];assert(!!school && school.status==='DRAFT','La création confirmée est retrouvée après une réponse navigateur perdue');
    const membership=(await administration.query('SELECT roles,grants FROM drivy.membership WHERE school_id=$1',[school.id])).rows[0];
    assert(membership.roles.join(',')==='ADMIN,INSTRUCTOR' && membership.grants.join(',')==='CONFIGURE_CATALOG','L’administrateur et le rôle moniteur choisi sont durables');
    assert(new URL(page.url()).pathname===`/app/gestion/${school.id}/apercu`
      &&await page.getByRole('link',{name:'Continuer la préparation',exact:true}).count()===0,
      'La création confirmée enchaîne sur les permis enseignés sans écran intermédiaire ni formulaire d’identité répété');
    const openReview=async()=>{
      stage='navigation vers le résumé de préparation';
      await page.getByRole('navigation',{name:'Étapes de préparation',exact:true}).getByRole('button',{name:'Résumé',exact:true}).click();
      await page.getByRole('heading',{name:'Résumé et confirmation',exact:true}).waitFor();
    };
    const editReviewSection=async(name:string)=>{
      stage=`personnalisation depuis le résumé : ${name}`;
      await page.locator('.setup-summary-part').filter({has:page.getByRole('heading',{name,exact:true})})
        .getByRole('button',{name:/^Modifier/}).click();
      await page.getByRole('heading',{name:name==='Permis proposés'?'Permis enseignés':name,exact:true}).waitFor();
    };
    const revealPhoneExplanation=async()=>{
      await expand(page,'Adapter les informations demandées');
      await expand(page.getByRole('group',{name:'Téléphone',exact:true}),'Pourquoi cette information ?');
      await page.getByLabel('Explication · Téléphone',{exact:true}).waitFor();
    };
    const pendingResult=()=>page.getByRole('region',{name:'Demandes en cours',exact:true}).getByText('Résultat à vérifier',{exact:true});
    const verifyPending=()=>page.getByRole('region',{name:'Demandes en cours',exact:true}).getByRole('button',{name:'Vérifier le résultat',exact:true});
    const requestLogout=async()=>{
      await page.getByRole('button',{name:/^Compte de /}).click();
      await page.getByRole('menuitem',{name:'Se déconnecter',exact:true}).click();
    };
    const reviewRecoveredDraft=async()=>{
      stage='relecture explicite après reprise du brouillon confirmé';
      await page.getByRole('button',{name:'Vérifier la préparation',exact:true}).click();
      await page.locator('.setup-summary').waitFor();
    };
    await openReview();await editReviewSection('Confidentialité');
    stage='première sauvegarde du guide';
    const notice='Recette synthétique uniquement. Les leçons et observations partagées sont visibles par l’élève ; les notes privées restent privées. Aucun compte réel.';
    const retention='Texte de recette synthétique uniquement. Les données de cette base éphémère sont supprimées à la fin du test.';
    await page.getByLabel('Information des personnes',{exact:true}).fill(notice);await page.getByLabel('Conservation des données',{exact:true}).fill(retention);
    const draftEndpoint=`${origin}/app/bff/schools/${school.id}/setup-draft`;
    const draftBefore=z.object({data:z.object({version:z.number().int()})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    let draftWrites=0,lostDraftOperation='',lostDraftHTTPStatus=0;
    await page.route(draftEndpoint,async route=>{
      if(route.request().method()!=='PUT'){await route.continue();return;}
      draftWrites++;
      if(draftWrites!==1){await route.continue();return;}
      lostDraftOperation=route.request().headers()['idempotency-key']??'';
      const committed=await route.fetch();lostDraftHTTPStatus=committed.status();await route.abort('failed');
    });
    stage='sauvegarde de confidentialité engagée puis réponse navigateur perdue';
    await page.getByRole('button',{name:'Enregistrer et revenir au résumé',exact:true}).click();
    await pendingResult().waitFor();
    assert(lostDraftHTTPStatus===200&&z.uuid().safeParse(lostDraftOperation).success,'La sauvegarde du brouillon est confirmée au serveur avant la perte de sa réponse');
    assert(await page.getByRole('button',{name:'Enregistrer et quitter',exact:true}).isDisabled(),'Le guide bloque une nouvelle sauvegarde tant que le résultat précédent reste inconnu');
    stage='rechargement du guide avec une sauvegarde au résultat inconnu';
    page.once('dialog',async dialog=>{if(dialog.type()==='beforeunload')await dialog.accept();else await dialog.dismiss();});
    await page.reload();await pendingResult().waitFor();
    assert(await page.getByRole('button',{name:'Renvoyer la même demande',exact:true}).count()===0,'Après rechargement, le suivi conserve les identifiants et ne recrée pas le corps de la commande');
    const pendingDraft:unknown=JSON.parse(await page.evaluate(()=>sessionStorage.getItem('drivy-gestion-demandes-v1')??'[]'));
    assert(Array.isArray(pendingDraft)&&pendingDraft.length===1&&parseMetadata(pendingDraft[0])?.operationId===lostDraftOperation,
      'Le rechargement conserve la référence de sauvegarde sans persister les textes saisis');
    stage='récupération de la sauvegarde depuis le suivi et AP72';
    const recoveryResponse=page.waitForResponse(response=>response.request().method()==='GET'&&new URL(response.url()).pathname===`/app/bff/schools/${school.id}/operations/${lostDraftOperation}`);
    await verifyPending().click();
    const recoveredSave=await recoveryResponse;
    const savedReceipt=z.object({data:z.object({operationId:z.uuid(),commandType:z.literal('SAVE_SCHOOL_SETUP_DRAFT'),resourceType:z.literal('SchoolSetupDraft'),
      resourceId:z.uuid(),resourceVersion:z.number().int(),committedAt:z.iso.datetime({offset:true})})}).parse(await recoveredSave.json()).data;
    assert(recoveredSave.ok()&&savedReceipt.operationId===lostDraftOperation&&savedReceipt.resourceId===school.id&&savedReceipt.resourceVersion===draftBefore.version+1,
      'AP72 confirme la même opération et la seule nouvelle version du brouillon');
    await pendingResult().waitFor({state:'hidden'});
    await page.getByRole('heading',{name:'Résumé et confirmation',exact:true}).waitFor();
    const draftResponse=await consumerContext.request.get(draftEndpoint);
    const draft=z.object({data:z.object({version:z.number().int(),currentStep:z.string(),content:z.object({privacy:z.object({noticeText:z.string(),retentionText:z.string()})})})}).parse(await draftResponse.json());
    assert(draftResponse.ok()&&draft.data.version===savedReceipt.resourceVersion&&draft.data.currentStep==='REVIEW'&&draft.data.content.privacy.noticeText===notice&&draft.data.content.privacy.retentionText===retention,
      'Le guide reprend le résumé et les textes réellement enregistrés après la réponse perdue');
    await reviewRecoveredDraft();
    await editReviewSection('Confidentialité');
    assert(await page.getByLabel('Information des personnes',{exact:true}).inputValue()===notice&&await page.getByLabel('Conservation des données',{exact:true}).inputValue()===retention,
      'Les champs du guide retrouvent les textes du serveur après vérification du reçu');
    await openReview();await editReviewSection('Informations des élèves');
    const durableSave=(await administration.query("SELECT count(*)::int AS n FROM drivy.operation WHERE school_id=$1 AND operation_id=$2 AND command_type='SAVE_SCHOOL_SETUP_DRAFT'",[school.id,lostDraftOperation])).rows[0];
    assert(draftWrites===1&&durableSave.n===1,'La reprise AP72 et la navigation du guide ne renvoient aucune sauvegarde ni commande en double');
    await page.unroute(draftEndpoint);
    await page.screenshot({path:resolve(artifactDirectory,'01-profil-desktop-synthetic.png'),fullPage:true});
    stage='fermeture du navigateur avec une saisie non enregistrée après le dernier brouillon confirmé';
    await revealPhoneExplanation();
    const savedPhoneExplanation=await page.getByLabel('Explication · Téléphone',{exact:true}).inputValue();
    await page.getByLabel('Explication · Téléphone',{exact:true}).fill('Saisie synthétique non enregistrée avant fermeture.');
    await consumerContext.close();
    stage='reprise depuis un contexte navigateur indépendant, sans cookie ni stockage transmis';
    consumerContext=await browser.newContext({viewport:{width:1024,height:960},locale:'fr-CH'});consumerContext.setDefaultTimeout(20_000);
    await consumerContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    page=await consumerContext.newPage();await page.goto(`${origin}/app`);
    await signIn(page,'school@example.invalid',consumerPassword);
    await page.getByRole('link',{name:'Ouvrir l’école Auto-école Recette · synthétique',exact:true}).click();
    await page.getByRole('heading',{name:'Résumé et confirmation',exact:true}).waitFor();
    await reviewRecoveredDraft();await editReviewSection('Informations des élèves');
    await revealPhoneExplanation();
    assert(await page.getByLabel('Explication · Téléphone',{exact:true}).inputValue()===savedPhoneExplanation,
      'Un navigateur indépendant reprend l’étape confirmée et le contenu serveur, sans annoncer la frappe non enregistrée comme sauvegardée');
    const resumedDraft=z.object({data:z.object({version:z.number().int(),currentStep:z.string(),content:z.object({privacy:z.object({noticeText:z.string(),retentionText:z.string()})})})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    assert(resumedDraft.version===savedReceipt.resourceVersion&&resumedDraft.currentStep==='REVIEW'&&resumedDraft.content.privacy.noticeText===notice&&resumedDraft.content.privacy.retentionText===retention,
      'La reconnexion sans lien d’ouverture retrouve le même brouillon et n’ajoute aucune version');
    assert(await page.evaluate(()=>sessionStorage.length===0&&localStorage.length===0),
      'La reprise indépendante ne dépend d’aucun contenu ni reçu conservé dans le stockage du premier navigateur');
    await page.setViewportSize({width:1440,height:1100});
    stage='sauvegarde depuis le dialogue de sortie avec réponse perdue';
    const exitExplanation=`${savedPhoneExplanation} Complément synthétique enregistré avant la sortie.`;
    const exitPhone=page.getByLabel('Explication · Téléphone',{exact:true});
    await revealPhoneExplanation();await exitPhone.fill(exitExplanation);
    let exitWrites=0,exitOperation='',exitHTTPStatus=0;
    await page.route(draftEndpoint,async route=>{
      if(route.request().method()!=='PUT'){await route.continue();return;}
      exitWrites++;exitOperation=route.request().headers()['idempotency-key']??'';
      const committed=await route.fetch();exitHTTPStatus=committed.status();await route.abort('failed');
    });
    await requestLogout();
    const exitDialog=page.getByRole('dialog',{name:'Enregistrer avant de quitter ?',exact:true});
    await exitDialog.getByRole('button',{name:'Enregistrer et quitter',exact:true}).click();
    await pendingResult().waitFor();await exitDialog.waitFor({state:'hidden'});
    assert(exitWrites===1&&exitHTTPStatus===200&&z.uuid().safeParse(exitOperation).success,
      'Une réponse de sauvegarde perdue ferme le dialogue de sortie sans abandonner la commande durable');
    await requestLogout();
    assert(await exitDialog.count()===0&&await verifyPending().isEnabled(),
      'Une nouvelle tentative de sortie ne masque pas la récupération de la demande incertaine');
    await verifyPending().click();
    await pendingResult().waitFor({state:'hidden'});
    await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    await revealPhoneExplanation();
    await page.waitForFunction(value=>document.querySelector<HTMLTextAreaElement>('[name^="profile.fields."][name$=".explanation"]')!==null&&[...document.querySelectorAll<HTMLTextAreaElement>('textarea')].some(input=>input.value===value),exitExplanation);
    const exitSaved=z.object({data:z.object({version:z.number().int(),currentStep:z.string()})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    const exitReceipts=(await administration.query('SELECT count(*)::int AS n FROM drivy.operation WHERE school_id=$1 AND operation_id=$2',[school.id,exitOperation])).rows[0];
    assert(exitWrites===1&&exitReceipts.n===1&&exitSaved.version===resumedDraft.version+1&&exitSaved.currentStep==='PROFILE'&&await exitPhone.inputValue()===exitExplanation,
      'La récupération du dialogue retrouve la saisie avec une seule commande et une seule version supplémentaire');
    await page.unroute(draftEndpoint);
    await page.getByRole('button',{name:'Enregistrer et quitter',exact:true}).click();await page.getByRole('heading',{name:'École',exact:true}).waitFor();
    await page.getByRole('navigation',{name:'Réglages',exact:true}).getByRole('button',{name:'Préparation',exact:true}).click();
    await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();await revealPhoneExplanation();
    assert(await exitPhone.inputValue()===exitExplanation,'Après récupération, quitter puis reprendre le guide reste possible sans perdre la saisie enregistrée');
    stage='erreur précise dans les informations demandées';
    const phoneExplanation=page.getByLabel('Explication · Téléphone',{exact:true});
    const originalPhoneExplanation=await phoneExplanation.inputValue();
    await phoneExplanation.fill('');
    await openReview();
    await page.getByRole('button',{name:'Expliquez à l’élève pourquoi cette information est demandée.',exact:true}).click();
    await page.waitForFunction(()=>{const active=document.activeElement;return active instanceof HTMLTextAreaElement&&active.name.startsWith('profile.fields.')&&active.value==='';});
    assert(await phoneExplanation.evaluate(element=>element===document.activeElement&&element.getAttribute('aria-invalid')==='true'&&(element.getAttribute('aria-describedby')??'').split(/\s+/).some(id=>document.getElementById(id)?.textContent?.includes('pourquoi cette information')))&&await phoneExplanation.isVisible(),
      'L’erreur d’explication retourne au téléphone concerné et lui associe son message, sans viser le prénom valide');
    await phoneExplanation.fill(originalPhoneExplanation);
    stage='transition du guide sur mobile depuis le bas de page';await page.setViewportSize({width:390,height:844});
    await page.getByRole('button',{name:'Enregistrer et revenir au résumé',exact:true}).click();
    await page.getByRole('heading',{name:'Résumé et confirmation',exact:true}).waitFor();
    await page.waitForFunction(()=>{const title=document.querySelector('.setup-step-title');const bounds=title?.getBoundingClientRect();return title===document.activeElement&&bounds&&bounds.top>=0&&bounds.bottom<window.innerHeight;});
    assert(true,'Continuer depuis le bas d’une étape mobile montre et focalise le titre de l’étape suivante');
    await page.setViewportSize({width:1440,height:1100});
    stage='préparation des informations élèves et du permis B';
    await page.getByRole('navigation',{name:'Étapes de préparation',exact:true}).getByRole('button',{name:'Permis',exact:true}).click();
    await page.getByRole('heading',{name:'Permis enseignés',exact:true}).waitFor();await page.getByRole('button',{name:'Permis B',exact:true}).click();
    await expand(page,/^Programme · \d+ compétences?$/);
    const secondCompetence=page.locator('[name="formations.0.competencies.1.label"]');
    const thirdDescription=page.locator('[name="formations.0.competencies.2.description"]');
    const originalSecondCompetence=await secondCompetence.inputValue(),originalThirdDescription=await thirdDescription.inputValue();
    await secondCompetence.fill('');await thirdDescription.fill('');
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Prix et règles de l’école',exact:true}).waitFor();
    await page.getByLabel('Prix de la leçon',{exact:true}).fill('95');await page.getByLabel('Durée',{exact:true}).fill('50');
    await page.getByLabel('En cas d’annulation',{exact:true}).click();
    await page.getByRole('option',{name:'Un délai, puis contact avec l’école',exact:true}).click();
    await page.getByLabel('Prévenir combien d’heures avant la leçon ?',{exact:true}).fill('');
    await page.getByLabel('Quand et comment se règle la leçon ?',{exact:true}).fill('Tarif synthétique pour une leçon de 50 minutes, destiné seulement à cette recette.');
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Résumé et confirmation',exact:true}).waitFor();
    stage='erreurs précises et associées dans les compétences et l’annulation';
    for(const [field,message,value] of [
      ['formations.0.competencies.1.label','Indiquez le nom de cette compétence.',originalSecondCompetence],
      ['formations.0.competencies.2.description','Décrivez cette compétence.',originalThirdDescription],
      ['commonLessonRules.cancellationHours','Indiquez le délai de votre école.','24']
    ] as const) {
      await page.getByRole('button',{name:message,exact:true}).click();
      const fieldInput=page.locator(`[name="${field}"]`);
      await page.waitForFunction(name=>document.activeElement?.getAttribute('name')===name,field);
      const before=await fieldInput.evaluate(element=>({invalid:element.getAttribute('aria-invalid'),description:(element.getAttribute('aria-describedby')??'').split(/\s+/).map(id=>document.getElementById(id)?.textContent??'').join(' '),visible:element.getBoundingClientRect().top>=0&&element.getBoundingClientRect().bottom<=window.innerHeight}));
      await fieldInput.fill(value);
      await page.waitForFunction(name=>document.querySelector(`[name="${name}"]`)?.getAttribute('aria-invalid')!=='true',field);
      assert(before.invalid==='true'&&before.description.includes(message)&&before.visible,`La revue cible ${field}, associe son erreur et retire celle-ci après correction`);
      await openReview();
    }
    const acknowledgement=page.getByRole('checkbox',{name:'J’ai relu ces choix et ces textes. Je les adopte pour mon école et confirme son activation.',exact:true});await acknowledgement.waitFor();
    assert(!(await acknowledgement.isChecked()),'Les textes et l’activation ne sont jamais préconfirmés');
    assert((await administration.query('SELECT status FROM drivy.school WHERE id=$1',[school.id])).rows[0].status==='DRAFT','Les étapes enregistrées ne déclenchent aucune activation implicite');
    await page.screenshot({path:resolve(artifactDirectory,'02-relecture-desktop-synthetic.png'),fullPage:true});
    stage='activation explicite et ouverture du planning';await acknowledgement.check();await page.getByRole('button',{name:'Adopter les textes et activer l’école',exact:true}).click();
    await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();
    assert((await administration.query('SELECT status FROM drivy.school WHERE id=$1',[school.id])).rows[0].status==='ACTIVE','L’agenda apparaît après le commit ACTIVE');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.service_product_version WHERE school_id=$1 AND unit_price_cents=9500',[school.id])).rows[0].n===1,'Le tarif saisi est créé sans montant inventé');
    const cancellation=(await administration.query('SELECT cancellation_rules FROM drivy.school_policy_version WHERE school_id=$1',[school.id])).rows;
    assert(cancellation.length===1&&cancellation[0].cancellation_rules?.cancellationHours===24&&cancellation[0].cancellation_rules?.lateAction==='CONTACT',
      'La confirmation conserve le délai de 24 heures et le contact avec l’école dans les règles structurées');
    await page.reload();await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();assert(true,'Une école active revient à l’agenda après rechargement');
    await page.screenshot({path:resolve(artifactDirectory,'03-agenda-desktop-synthetic.png'),fullPage:true});
    stage='entrée quotidienne puis préparation web sur écran mobile';await page.setViewportSize({width:390,height:844});await page.goto(`${origin}/app/gestion/${school.id}/apercu`);
    await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();
    assert(new URL(page.url()).pathname===`/app/gestion/${school.id}/agenda`,'L’ancienne entrée quotidienne d’une école active retrouve son agenda');
    await page.goto(`${origin}/app/gestion/${school.id}/apercu?from=configuration`);
    await page.getByRole('heading',{name:'Préparation de l’école',exact:true}).waitFor();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'La préparation mobile ne déborde pas horizontalement');
    stage='navigation mobile et restitution du focus après fermeture d’un menu';
    const settingsNavigation=page.getByRole('navigation',{name:'Réglages',exact:true});
    await settingsNavigation.getByRole('button',{name:'École',exact:true}).waitFor();
    assert(await page.getByRole('navigation',{name:'Navigation principale',exact:true}).getByRole('button',{name:'Réglages',exact:true}).getAttribute('aria-current')==='page',
      'La navigation mobile identifie le contexte Réglages et garde les rubriques accessibles');
    const appearance=page.getByRole('button',{name:'Choisir l’apparence',exact:true});await appearance.focus();await page.keyboard.press('Enter');
    await page.getByRole('menuitemradio',{name:'Système',exact:true}).waitFor();await page.keyboard.press('Escape');
    await page.waitForFunction(()=>document.activeElement?.getAttribute('aria-label')==='Choisir l’apparence');
    assert(await appearance.getAttribute('aria-expanded')==='false','Échap ferme le menu mobile et restitue le focus au contrôle qui l’a ouvert');
    await page.screenshot({path:resolve(artifactDirectory,'04-preparation-mobile-synthetic.png'),fullPage:true});
    await page.goto(`${origin}/app/gestion/${school.id}/apercu?from=formations`);
    await page.getByRole('heading',{name:'Préparer une formation',exact:true}).waitFor();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'Le guide de formation mobile ne déborde pas horizontalement');
    await page.screenshot({path:resolve(artifactDirectory,'05-formation-mobile-synthetic.png'),fullPage:true});
    const browserStorage=await page.evaluate(()=>({localKeys:localStorage.length,sessionEntries:Object.keys(sessionStorage).map(key=>[key,sessionStorage.getItem(key)!])}));
    assert(browserStorage.localKeys===0&&browserStorage.sessionEntries.every(([key,value])=>{
      if(key!=='drivy-gestion-demandes-v1')return false;const metadata:unknown=JSON.parse(value!);
      return Array.isArray(metadata)&&metadata.length<=50&&metadata.every(item=>parseMetadata(item)!==null);
    }),'Le navigateur conserve seulement les métadonnées autorisées de reçu, sans jeton ni contenu personnel');
    const operatorDenied=await consumerContext.request.get(`${origin}/app/bff/operator/school-opening-links`);assert(operatorDenied.status()===403,'Un ADMIN scolaire ne devient pas opérateur Drivy');
    stage='invitation de l’équipe depuis le portail';await page.setViewportSize({width:1440,height:1100});
    await page.goto(`${origin}/app/gestion/${school.id}/invitations?audience=team`);
    await page.getByRole('button',{name:'Inviter par e-mail',exact:true}).click();
    await page.getByLabel('Adresse e-mail',{exact:true}).fill('instructor@example.invalid');
    assert(await page.getByRole('checkbox',{name:/^Moniteur/}).isChecked(),'Une invitation de l’équipe propose explicitement le rôle moniteur');
    await page.getByRole('button',{name:'Relire',exact:true}).click();
    const invitationDialog=page.getByRole('dialog',{name:'Inviter par e-mail ?',exact:true});
    await invitationDialog.waitFor();
    assert(await invitationDialog.getByText('instructor@example.invalid',{exact:true}).isVisible()
      &&await invitationDialog.getByText('Moniteur',{exact:true}).isVisible()
      &&(await administration.query('SELECT count(*)::int AS n FROM drivy.invitation WHERE school_id=$1 AND email=$2',[school.id,'instructor@example.invalid'])).rows[0].n===0,
      'La relecture présente l’adresse et le rôle sans créer d’invitation avant la confirmation distincte');
    await invitationDialog.getByRole('button',{name:'Enregistrer l’invitation',exact:true}).click();
    await invitationDialog.waitFor({state:'hidden'});
    const invitation=(await administration.query('SELECT id,status,roles FROM drivy.invitation WHERE school_id=$1 AND email=$2',[school.id,'instructor@example.invalid'])).rows[0];
    assert(invitation?.status==='PENDING'&&JSON.stringify(invitation.roles)==='["INSTRUCTOR"]','L’invitation équipe est enregistrée avant livraison, sans rôle supplémentaire');
    const queued=(await administration.query('SELECT id,status,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[invitation.id])).rows[0];
    assert(queued?.status==='QUEUED'&&Buffer.isBuffer(queued.payload),'Le courrier attendu est conservé chiffré dans l’outbox');
    stage='livraison SMTP réelle de l’invitation équipe';await deliverOneInvitation(mailer,invitationMail);
    const invitationURL=mailLink(await ownMail('instructor@example.invalid',message=>message.MessageID.includes(queued.id)),origin,'/app/invitation');
    const sent=(await administration.query('SELECT status,payload FROM drivy.invitation_mail WHERE id=$1',[queued.id])).rows[0];
    assert(sent?.status==='SENT'&&sent.payload===null,'Le SMTP accepte le courrier puis la charge chiffrée est effacée');
    const staffContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});staffContext.setDefaultTimeout(20_000);
    await staffContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const staffPage=await staffContext.newPage();await staffPage.goto(invitationURL);
    stage='création du compte moniteur avec le lien reçu';
    await staffPage.getByRole('heading',{name:'Créer votre compte',exact:true}).waitFor();
    const otherAddress=await submitRegistration(staffPage,{firstName:'Moniteur',lastName:'Synthétique',email:'someone-else@example.invalid',password:syntheticSecret()});
    assert(otherAddress.includes('l’adresse à laquelle'),'Le lien d’invitation ne crée pas de compte à une autre adresse');
    await register(staffPage,{firstName:'Moniteur',lastName:'Synthétique',email:'instructor@example.invalid',password:syntheticSecret()});
    await staffPage.getByRole('heading',{name:'Auto-école Recette · synthétique',exact:true}).waitFor();
    const staffSession=await staffContext.request.get(`${origin}/app/bff/session`);
    assert(z.object({authenticated:z.literal(true),user:z.object({emailVerified:z.literal(true)})}).safeParse(await staffSession.json()).success,'Le moniteur vérifie son adresse avant de rejoindre l’école');
    const join=staffPage.getByRole('button',{name:'Rejoindre cette école',exact:true});
    assert(await join.isDisabled()&&(await administration.query("SELECT count(*)::int AS n FROM drivy.membership WHERE school_id=$1",[school.id])).rows[0].n===1,'Lire l’invitation ne crée aucun rattachement sans consentement');
    await staffPage.getByRole('checkbox').check();await join.click();
    await staffPage.getByText('Vous avez rejoint Auto-école Recette · synthétique',{exact:true}).waitFor();
    const staffMe=await staffContext.request.get(`${origin}/app/bff/me`);
    const staffMember=z.object({data:z.object({memberships:z.array(z.object({schoolId:z.string(),roles:z.array(z.string())}))})}).parse(await staffMe.json());
    assert(staffMe.ok()&&staffMember.data.memberships.length===1&&staffMember.data.memberships[0]!.schoolId===school.id&&JSON.stringify(staffMember.data.memberships[0]!.roles)==='["INSTRUCTOR"]','Le compte invité rejoint une seule école avec le seul rôle moniteur');
    assert((await administration.query(`SELECT count(*)::int AS n FROM drivy.learner_profile l JOIN drivy.membership m
      ON m.school_id=l.school_id AND m.person_id=l.person_id WHERE m.school_id=$1 AND m.invitation_email=$2`,[school.id,'instructor@example.invalid'])).rows[0].n===0,
      'Rejoindre comme moniteur ne crée aucun dossier élève ni demande de noms scolaires');
    await verifyPersonalWelcome({apiOrigin,schoolId:school.id,kind:'STAFF',getAccessToken:()=>accessTokenFor(staffContext),assert,setStage:value=>{stage=value;}});
    await staffPage.reload();await staffPage.getByRole('heading',{name:'Vos écoles',exact:true}).waitFor();
    await staffPage.getByText('Auto-école Recette · synthétique',{exact:true}).waitFor();
    await staffPage.screenshot({path:resolve(artifactDirectory,'06-equipe-invitation-acceptee-synthetic.png'),fullPage:true});await staffContext.close();
    await verifySchoolFirstLesson({browser,page,consumerContext,schoolId:school.id,origin,apiOrigin,keycloakOrigin,administration,
      ownMail,mailLink,deliverInvitation:()=>deliverOneInvitation(mailer!,invitationMail),
      getAccessToken:accessTokenFor,assert,setStage:value=>{stage=value;},artifactDirectory});
    if(process.argv.includes('--audit-v2')) await verifyAuditV2({page,context:consumerContext,origin,keycloakOrigin,schoolId:school.id,
      operatorPassword,consumerPassword,assert,setStage:value=>{stage=value;}});
    // Formations et tarifs après une première leçon réelle : l'inscription et la réservation existantes doivent rester intactes.
    await verifySchoolFormations({page,consumerContext,schoolId:school.id,origin,administration,artifactDirectory,assert,setStage:value=>{stage=value;}});
    await verifySchoolCodeEntry({browser,origin,apiOrigin,keycloakOrigin,schoolId:school.id,administration,getAccessToken:accessTokenFor,
      existingEmail:'school@example.invalid',existingPassword:consumerPassword,assert,setStage:value=>{stage=value;},artifactDirectory});
    stage='confirmation d’identité du même compte avant le réglage GPS';
    const sessionProof=z.object({authenticated:z.literal(true),csrfToken:z.string(),reauthenticationRequired:z.boolean()});
    const beforeReauth=sessionProof.parse(await (await consumerContext.request.get(`${origin}/app/bff/session`)).json());
    const beforeCookie=(await consumerContext.cookies(origin)).find(item=>item.name==='drivy-dev-session')?.value;
    const beforeSubject=sessionStore.get(beforeCookie)?.tokens?.principal.subject;
    const refusedReauth=await consumerContext.request.post(`${origin}/app/bff/reauthenticate`,{
      headers:{Origin:origin,'X-CSRF-Token':beforeReauth.csrfToken},data:{email:'school@example.invalid',password:syntheticSecret()}});
    assert(refusedReauth.status()===401&&sessionStore.get(beforeCookie)?.tokens?.principal.subject===beforeSubject,
      'Un mauvais mot de passe de confirmation conserve le compte et sa session');
    const wrongAccount=await consumerContext.request.post(`${origin}/app/bff/reauthenticate`,{
      headers:{Origin:origin,'X-CSRF-Token':beforeReauth.csrfToken},data:{email:'operator@example.invalid',password:operatorPassword}});
    assert(wrongAccount.status()===409&&sessionStore.get(beforeCookie)?.tokens?.principal.subject===beforeSubject,
      'La confirmation refuse un autre compte sans remplacer la session scolaire');
    const freshReauth=await consumerContext.request.post(`${origin}/app/bff/reauthenticate`,{
      headers:{Origin:origin,'X-CSRF-Token':beforeReauth.csrfToken},data:{email:'school@example.invalid',password:consumerPassword}});
    const afterReauth=sessionProof.parse(await (await consumerContext.request.get(`${origin}/app/bff/session`)).json());
    const afterCookie=(await consumerContext.cookies(origin)).find(item=>item.name==='drivy-dev-session')?.value;
    assert(freshReauth.ok()&&!afterReauth.reauthenticationRequired&&afterCookie!==beforeCookie
      &&afterReauth.csrfToken!==beforeReauth.csrfToken&&sessionStore.get(afterCookie)?.tokens?.principal.subject===beforeSubject,
      'La confirmation réelle renouvelle la preuve, le cookie et le CSRF en conservant le même compte');
    assert((await administration.query('SELECT modules FROM drivy.school WHERE id=$1',[school.id])).rows[0].modules.gpsEnabled===false,
      'Confirmer son identité ne modifie pas le réglage GPS');
    stage='activation GPS explicite avec authentification récente signée';
    await page.goto(`${origin}/app/gestion/${school.id}/confidentialite?focus=gps-module`);
    const gpsSection=page.getByRole('region',{name:'Trajets GPS',exact:true});
    await gpsSection.getByRole('button',{name:'Activer les trajets GPS',exact:true}).click();
    const gpsReview=page.getByRole('dialog',{name:'Activer les trajets GPS',exact:true});
    await gpsReview.getByRole('button',{name:'Activer',exact:true}).click();await gpsReview.waitFor({state:'hidden'});
    await gpsSection.getByRole('button',{name:'Désactiver les trajets GPS',exact:true}).waitFor();
    assert((await administration.query('SELECT modules FROM drivy.school WHERE id=$1',[school.id])).rows[0].modules.gpsEnabled===true,
      'Le réglage GPS est accepté et durable après confirmation explicite avec la preuve récente');
    await page.screenshot({path:resolve(artifactDirectory,'13-gps-enabled-synthetic.png'),fullPage:true});
    await verifyAccountRecovery({browser,origin,apiOrigin,issuer,keycloakOrigin,realmName,adminPassword,clientId:'drivy-web-e2e',clientSecret,ownMail,mailLink,assert,setStage:value=>{stage=value;}});
    await writeFile(resolve(artifactDirectory,'result.json'),JSON.stringify({status:'PASSED',checkedAt:new Date().toISOString(),browser:browser.version(),checks,
      scope:'Chromium desktop et viewport mobile, Keycloak réel à inscription fermée, création de compte par code et par lien d’invitation SMTP, connexion par formulaire, BFF, API et PostgreSQL isolés ; données synthétiques uniquement. Aucun appareil, GPS, batterie ou lecteur d’écran physique qualifié.'},null,2));
    console.log(`${checks.length} contrôles de recette réussis : navigateur → OIDC → BFF → API → PostgreSQL.`);
  } finally {
    await browser?.close();await web?.close();await api?.close();await runtime?.end();await mailer?.end();await administration.end();
    if(containerStarted)try{await docker(['rm','--force',containerName]);}catch{/* Runner teardown also removes the ephemeral container. */}
    if(temporary){const absolute=resolve(temporary),prefix=resolve(tmpdir())+sep+'drivy-opening-e2e-';if(absolute.startsWith(prefix))await rm(absolute,{recursive:true,force:true});}
  }
}
main().catch(async(error:unknown)=>{
  const refusal=error instanceof Error&&error.message.startsWith('REGISTRATION_REFUSED: ')?error.message.slice(22,200):'';
  if(refusal)stage=`${stage} · refus affiché : ${refusal}`;
  await mkdir(artifactDirectory,{recursive:true});await writeFile(resolve(artifactDirectory,'result.json'),JSON.stringify({status:'FAILED',stage,passedChecks:checks,checkedAt:new Date().toISOString()},null,2));
  console.error(`Recette ouverture école interrompue : ${stage}. Aucun journal réseau ni identifiant de connexion enregistré.`);process.exitCode=1;
  // Diagnostic local explicite : seulement la première ligne de l'erreur (jamais en CI, jamais dans un artefact).
  if(process.env.DRIVY_E2E_DEBUG==='1'&&!process.env.CI)console.error(String(error instanceof Error?error.message:error).split('\n')[0]?.slice(0,300));
});
