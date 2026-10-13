/** Complete synthetic browser qualification. No token, identity credential, request trace or real account is an artifact. */
import { randomBytes,randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile,mkdir,mkdtemp,writeFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve,sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { z } from 'zod';
import { chromium,type Browser } from '../../infra/dev/browser.js';
import { migrate } from '../../apps/api/scripts/migrations.js';
import { buildApp } from '../../apps/api/src/app.js';
import { createTokenVerifier } from '../../apps/api/src/auth.js';
import { deliverOneInvitation,type InvitationMailConfig } from '../../apps/api/src/invitation-mail.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import { createIdentityProvider } from '../../apps/web/server/oidc.js';
import { SessionStore } from '../../apps/web/server/session.js';
import { parseMetadata } from '../../apps/web/client/command-core.js';
import { verifySchoolFirstLesson } from './check-school-first-lesson.js';

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
function assert(value:unknown,label:string):asserts value {stage=label;if(!value)throw new Error('CHECK_FAILED');checks.push(label);}
function docker(args:string[]):Promise<void> {return new Promise((done,fail)=>{const child=spawn('docker',args,{stdio:'ignore',windowsHide:true});child.on('error',()=>fail(new Error('DOCKER_UNAVAILABLE')));child.on('exit',code=>code===0?done():fail(new Error('DOCKER_FAILED')));});}
async function waitFor(url:string) {
  for(let attempt=0;attempt<120;attempt++){try{const response=await fetch(url,{signal:AbortSignal.timeout(1000),redirect:'error'});if(response.ok)return;}catch{/* Local service is still starting. */}await new Promise(done=>setTimeout(done,1000));}
  throw new Error('SERVICE_START_TIMEOUT');
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
    for(const role of ['drivy_e2e_migrator','drivy_app','drivy_invitation_mailer'])await administration.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
    await administration.query('GRANT CREATE ON DATABASE drivy_onboarding_e2e TO drivy_e2e_migrator');
    await administration.query('GRANT USAGE,CREATE ON SCHEMA public TO drivy_e2e_migrator');
    await administration.query('GRANT drivy_app,drivy_invitation_mailer TO drivy_e2e_migrator WITH ADMIN OPTION');
    const migrator=new Pool({connectionString:databaseURL,options:'-c role=drivy_e2e_migrator'});
    try{await migrate(migrator);}finally{await migrator.end();}
    runtime=new Pool({connectionString:databaseURL,options:'-c role=drivy_app',max:8});
    mailer=new Pool({connectionString:databaseURL,options:'-c role=drivy_invitation_mailer',max:2});
    const runtimeRole=(await runtime.query('SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user')).rows[0];
    assert(!runtimeRole.rolsuper&&!runtimeRole.rolbypassrls,'Le service métier utilise drivy_app sans BYPASSRLS');

    stage='serveur OIDC éphémère';temporary=await mkdtemp(resolve(tmpdir(),'drivy-opening-e2e-'));
    const adminPassword=syntheticSecret(),operatorPassword=syntheticSecret(),consumerPassword=syntheticSecret(),clientSecret=syntheticSecret();
    const envPath=resolve(temporary,'keycloak.env');
    await writeFile(envPath,`KC_BOOTSTRAP_ADMIN_USERNAME=drivy-e2e-admin\nKC_BOOTSTRAP_ADMIN_PASSWORD=${adminPassword}\nKC_HOSTNAME=${keycloakOrigin}\nKC_HTTP_ENABLED=true\nKC_LOG_LEVEL=warn\n`,{mode:0o600});
    await docker(['run','--detach','--rm','--name',containerName,'--env-file',envPath,'--publish','127.0.0.1:8081:8080','--add-host','host.docker.internal:host-gateway',keycloakImage,'start-dev']);containerStarted=true;
    await waitFor(`${keycloakOrigin}/realms/master/.well-known/openid-configuration`);
    const authentication=await fetch(`${keycloakOrigin}/realms/master/protocol/openid-connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
      body:new URLSearchParams({client_id:'admin-cli',grant_type:'password',username:'drivy-e2e-admin',password:adminPassword})});
    if(!authentication.ok)throw new Error('OIDC_ADMIN_UNAVAILABLE');const auth=await authentication.json() as {access_token?:string};if(!auth.access_token)throw new Error('OIDC_ADMIN_UNAVAILABLE');
    const realm=JSON.parse(await readFile(new URL('../../infra/dev/realm.json',import.meta.url),'utf8')) as Record<string,unknown>;
    realm.realm=realmName;realm.displayName='Drivy · Recette synthétique';realm.registrationAllowed=true;realm.verifyEmail=true;realm.resetPasswordAllowed=true;
    realm.smtpServer={host:'host.docker.internal',port:'1025',from:'identity@drivy.example.invalid',ssl:'false',starttls:'false',auth:'false'};
    realm.clients=[{clientId:'drivy-web-e2e',protocol:'openid-connect',enabled:true,publicClient:false,secret:clientSecret,standardFlowEnabled:true,
      directAccessGrantsEnabled:false,implicitFlowEnabled:false,serviceAccountsEnabled:false,fullScopeAllowed:false,
      redirectUris:[`${origin}/app/bff/callback`],webOrigins:[],attributes:{'pkce.code.challenge.method':'S256'},defaultClientScopes:['basic','profile','email'],optionalClientScopes:[],
      protocolMappers:[{name:'drivy-api-audience',protocol:'openid-connect',protocolMapper:'oidc-audience-mapper',consentRequired:false,
        config:{'included.custom.audience':'drivy-api','id.token.claim':'false','access.token.claim':'true','introspection.token.claim':'true'}}]}];
    realm.users=[{username:'operateur-recette',enabled:true,email:'operator@example.invalid',emailVerified:true,firstName:'Opérateur',lastName:'Synthétique',
      credentials:[{type:'password',value:operatorPassword,temporary:false}]}];
    const realmResponse=await fetch(`${keycloakOrigin}/admin/realms`,{method:'POST',headers:{Authorization:`Bearer ${auth.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(realm)});
    if(!realmResponse.ok)throw new Error('OIDC_REALM_FAILED');
    const users=await fetch(`${keycloakOrigin}/admin/realms/${realmName}/users?username=operateur-recette&exact=true`,{headers:{Authorization:`Bearer ${auth.access_token}`}});
    if(!users.ok)throw new Error('OIDC_OPERATOR_FAILED');const operatorList=await users.json() as {id:string}[];if(operatorList.length!==1)throw new Error('OIDC_OPERATOR_FAILED');
    delete auth.access_token;
    const config={origin,apiBaseURL:apiOrigin,issuer,clientId:'drivy-web-e2e',clientSecret,development:true,host:'127.0.0.1',port:3002};
    const invitationMail:InvitationMailConfig={webURL:`${origin}/app/invitation`,encryptionKey:randomBytes(32).toString('hex'),host:'127.0.0.1',port:1025,
      secure:false,requireTLS:false,from:'school@drivy.example.invalid'};
    api=buildApp({pool:runtime,verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/protocol/openid-connect/certs`}),
      cursorSecret:syntheticSecret(),invitationMail,schoolOpening:{operators:[{issuer,subject:operatorList[0]!.id}],validityDays:7}});
    const sessionStore=new SessionStore();
    web=await buildWebApp({config,identity:await createIdentityProvider(config),store:sessionStore,staticRoot:fileURLToPath(new URL('../../apps/web/dist/client/',import.meta.url))});
    await api.listen({host:'127.0.0.1',port:3001});await web.listen({host:'127.0.0.1',port:3002});
    await mkdir(artifactDirectory,{recursive:true});
    stage='navigateur Chromium';browser=await chromium.launch({headless:true});
    const operatorContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
    let consumerContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
    for(const context of [operatorContext,consumerContext])await context.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const operatorPage=await operatorContext.newPage();operatorPage.setDefaultTimeout(20_000);
    stage='connexion opérateur OIDC';await operatorPage.goto(`${origin}/app/operateur`);
    await operatorPage.getByRole('button',{name:'Créer mon compte ou me connecter',exact:true}).click();
    await operatorPage.locator('input[name="username"]').fill('operateur-recette');await operatorPage.locator('input[name="password"]').fill(operatorPassword);
    await operatorPage.locator('input[type="submit"],button[type="submit"]').first().click();
    await operatorPage.waitForURL(`${origin}/app/operateur`);
    stage='génération du lien via l’interface opérateur';await operatorPage.getByRole('button',{name:'Créer un lien d’ouverture',exact:true}).click();
    const linkInput=operatorPage.getByLabel('Lien à transmettre',{exact:true});await linkInput.waitFor();const openingLink=await linkInput.inputValue();
    assert(new URL(openingLink).pathname==='/app/ouvrir' && !new URL(openingLink).search,'Le lien de création porte son secret dans le fragment uniquement');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.school')).rows[0].n===0,'Créer ou consulter un lien ne crée pas d’école');

    let page=await consumerContext.newPage();page.setDefaultTimeout(20_000);
    stage='visite du lien et nouveau compte OIDC';await page.goto(openingLink);
    await page.getByRole('button',{name:'Créer mon compte ou me connecter',exact:true}).waitFor();
    assert(new URL(page.url()).hash==='','Le secret du lien est retiré avant la connexion');
    await page.getByRole('button',{name:'Créer mon compte ou me connecter',exact:true}).click();
    await page.waitForURL(url=>url.origin===keycloakOrigin);
    assert(new URL(page.url()).searchParams.get('code_challenge_method')==='S256' && !page.url().includes(new URL(openingLink).hash.slice(7)),'Connexion OIDC réelle avec PKCE sans secret d’ouverture');
    stage='inscription OIDC du responsable avant mot de passe';
    await page.locator('#kc-registration a').click();
    await page.locator('input[name="username"]').fill('responsable-recette');await page.locator('input[name="email"]').fill('school@example.invalid');
    await page.locator('input[name="firstName"]').fill('Responsable');await page.locator('input[name="lastName"]').fill('Synthétique');
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    stage='vérification réelle de l’adresse par SMTP';
    const verification=await ownMail('school@example.invalid');
    assert(new URL(page.url()).origin===keycloakOrigin,'Le compte reste chez le fournisseur avant la vérification de son adresse');
    await page.goto(mailLink(verification,keycloakOrigin,`/realms/${realmName}/login-actions/action-token`));
    // Keycloak 26.7 requires the password after e-mail verification, never on the initial registration form.
    stage='choix du mot de passe après vérification du responsable';
    await page.locator('input[name="password-new"]').fill(consumerPassword);await page.locator('input[name="password-confirm"]').fill(consumerPassword);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    await page.waitForURL(`${origin}/app/ouvrir`);await page.getByLabel('Nom de l’auto-école',{exact:true}).waitFor();
    const verifiedSession=await consumerContext.request.get(`${origin}/app/bff/session`);
    assert(z.object({authenticated:z.literal(true),user:z.object({emailVerified:z.literal(true)})}).safeParse(await verifiedSession.json()).success,'Le lien SMTP vérifie réellement le nouveau compte avant création');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.person')).rows[0].n===0,'Le nouveau compte OIDC n’est pas créé dans la base métier avant confirmation');
    stage='création volontaire et perte de réponse navigateur';await page.getByLabel('Votre nom',{exact:true}).fill('Responsable de recette synthétique');
    await page.getByLabel('Nom de l’auto-école',{exact:true}).fill('Auto-école Recette · synthétique');await page.getByLabel('E-mail professionnel',{exact:true}).fill('school@example.invalid');
    assert(await page.getByLabel('Nom de l’auto-école',{exact:true}).evaluate(element=>element.getBoundingClientRect().height>=44),
      'Les champs d’ouverture réutilisent les contrôles du portail avec une cible d’au moins 44 pixels');
    stage='erreur de fuseau ciblée avant création';
    const openingZone=page.getByLabel('Fuseau horaire',{exact:true});
    const zoneDetails=page.locator('details').filter({has:openingZone});
    await zoneDetails.locator('summary').click();await openingZone.fill('Zurich');await zoneDetails.locator('summary').click();
    await page.getByRole('button',{name:'Créer mon école',exact:true}).click();
    await page.waitForFunction(()=>document.activeElement?.getAttribute('name')==='timeZone');
    assert(await openingZone.getAttribute('aria-invalid')==='true' && await zoneDetails.getAttribute('open')!==null,
      'Un fuseau invalide rouvre le détail et cible le champ avec une explication');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.school')).rows[0].n===0,'Une saisie invalide ne consomme pas le lien et ne crée aucune école');
    await openingZone.fill('Europe/Zurich');
    await page.getByLabel('Je donne aussi des leçons',{exact:true}).check();
    stage='création volontaire et perte de réponse navigateur';
    await page.route('**/app/bff/opening/create',async route=>{await route.fetch();await route.abort('failed');},{times:1});
    await page.getByRole('button',{name:'Créer mon école',exact:true}).click();
    await page.getByRole('heading',{name:'Votre école est créée',exact:true}).waitFor();
    const school=(await administration.query('SELECT id,status FROM drivy.school')).rows[0];assert(!!school && school.status==='DRAFT','La création confirmée est retrouvée après une réponse navigateur perdue');
    const membership=(await administration.query('SELECT roles,grants FROM drivy.membership WHERE school_id=$1',[school.id])).rows[0];
    assert(membership.roles.join(',')==='ADMIN,INSTRUCTOR' && membership.grants.join(',')==='CONFIGURE_CATALOG','L’administrateur et le rôle moniteur choisi sont durables');
    await page.getByRole('link',{name:'Continuer la préparation',exact:true}).click();
    await page.getByRole('heading',{name:'Votre école',exact:true}).waitFor();
    stage='première sauvegarde du guide';await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
    await page.getByRole('heading',{name:'Confidentialité',exact:true}).waitFor();
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
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
    await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor();
    assert(lostDraftHTTPStatus===200&&z.uuid().safeParse(lostDraftOperation).success,'La sauvegarde du brouillon est confirmée au serveur avant la perte de sa réponse');
    assert(await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).isDisabled(),'Le guide bloque une nouvelle sauvegarde tant que le résultat précédent reste inconnu');
    stage='rechargement du guide avec une sauvegarde au résultat inconnu';
    page.once('dialog',async dialog=>{if(dialog.type()==='beforeunload')await dialog.accept();else await dialog.dismiss();});
    await page.reload();await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor();
    assert(await page.getByRole('button',{name:'Renvoyer la même demande',exact:true}).count()===0,'Après rechargement, le suivi conserve les identifiants et ne recrée pas le corps de la commande');
    const pendingDraft:unknown=JSON.parse(await page.evaluate(()=>sessionStorage.getItem('drivy-gestion-demandes-v1')??'[]'));
    assert(Array.isArray(pendingDraft)&&pendingDraft.length===1&&parseMetadata(pendingDraft[0])?.operationId===lostDraftOperation,
      'Le rechargement conserve la référence de sauvegarde sans persister les textes saisis');
    stage='récupération de la sauvegarde depuis PendingPanel et AP72';
    const recoveryResponse=page.waitForResponse(response=>response.request().method()==='GET'&&new URL(response.url()).pathname===`/app/bff/schools/${school.id}/operations/${lostDraftOperation}`);
    await page.getByRole('button',{name:'Vérifier auprès de l’école',exact:true}).click();
    const recoveredSave=await recoveryResponse;
    const savedReceipt=z.object({data:z.object({operationId:z.uuid(),commandType:z.literal('SAVE_SCHOOL_SETUP_DRAFT'),resourceType:z.literal('SchoolSetupDraft'),
      resourceId:z.uuid(),resourceVersion:z.number().int(),committedAt:z.iso.datetime({offset:true})})}).parse(await recoveredSave.json()).data;
    assert(recoveredSave.ok()&&savedReceipt.operationId===lostDraftOperation&&savedReceipt.resourceId===school.id&&savedReceipt.resourceVersion===draftBefore.version+1,
      'AP72 confirme la même opération et la seule nouvelle version du brouillon');
    await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor({state:'hidden'});
    await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    const draftResponse=await consumerContext.request.get(draftEndpoint);
    const draft=z.object({data:z.object({version:z.number().int(),currentStep:z.string(),content:z.object({privacy:z.object({noticeText:z.string(),retentionText:z.string()})})})}).parse(await draftResponse.json());
    assert(draftResponse.ok()&&draft.data.version===savedReceipt.resourceVersion&&draft.data.currentStep==='PROFILE'&&draft.data.content.privacy.noticeText===notice&&draft.data.content.privacy.retentionText===retention,
      'Le guide reprend l’étape Profil et les textes réellement enregistrés après la réponse perdue');
    await page.getByRole('button',{name:'Retour',exact:true}).click();await page.getByRole('heading',{name:'Confidentialité',exact:true}).waitFor();
    assert(await page.getByLabel('Information des personnes',{exact:true}).inputValue()===notice&&await page.getByLabel('Conservation des données',{exact:true}).inputValue()===retention,
      'Les champs du guide retrouvent les textes du serveur après vérification du reçu');
    await page.getByRole('button',{name:/Informations des élèves/}).click();await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    const durableSave=(await administration.query("SELECT count(*)::int AS n FROM drivy.operation WHERE school_id=$1 AND operation_id=$2 AND command_type='SAVE_SCHOOL_SETUP_DRAFT'",[school.id,lostDraftOperation])).rows[0];
    assert(draftWrites===1&&durableSave.n===1,'La reprise AP72 et la navigation du guide ne renvoient aucune sauvegarde ni commande en double');
    await page.unroute(draftEndpoint);
    await page.screenshot({path:resolve(artifactDirectory,'01-profil-desktop-synthetic.png'),fullPage:true});
    stage='fermeture du navigateur avec une saisie non enregistrée après le dernier brouillon confirmé';
    const savedPhoneExplanation=await page.getByLabel('Explication · Téléphone',{exact:true}).inputValue();
    await page.locator('details').filter({has:page.getByLabel('Explication · Téléphone',{exact:true})}).locator('summary').click();
    await page.getByLabel('Explication · Téléphone',{exact:true}).fill('Saisie synthétique non enregistrée avant fermeture.');
    await consumerContext.close();
    stage='reprise depuis un contexte navigateur indépendant, sans cookie ni stockage transmis';
    consumerContext=await browser.newContext({viewport:{width:1024,height:960},locale:'fr-CH'});consumerContext.setDefaultTimeout(20_000);
    await consumerContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    page=await consumerContext.newPage();await page.goto(`${origin}/app`);
    await page.getByRole('button',{name:'Se connecter',exact:true}).click();
    await page.locator('input[name="username"]').fill('responsable-recette');await page.locator('input[name="password"]').fill(consumerPassword);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    await page.getByRole('link',{name:'Ouvrir l’école Auto-école Recette · synthétique',exact:true}).click();
    await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    assert(await page.getByLabel('Explication · Téléphone',{exact:true}).inputValue()===savedPhoneExplanation,
      'Un navigateur indépendant reprend l’étape confirmée et le contenu serveur, sans annoncer la frappe non enregistrée comme sauvegardée');
    const resumedDraft=z.object({data:z.object({version:z.number().int(),currentStep:z.string(),content:z.object({privacy:z.object({noticeText:z.string(),retentionText:z.string()})})})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    assert(resumedDraft.version===savedReceipt.resourceVersion&&resumedDraft.currentStep==='PROFILE'&&resumedDraft.content.privacy.noticeText===notice&&resumedDraft.content.privacy.retentionText===retention,
      'La reconnexion sans lien d’ouverture retrouve le même brouillon et n’ajoute aucune version');
    assert(await page.evaluate(()=>sessionStorage.length===0&&localStorage.length===0),
      'La reprise indépendante ne dépend d’aucun contenu ni reçu conservé dans le stockage du premier navigateur');
    await page.setViewportSize({width:1440,height:1100});
    stage='sauvegarde depuis le dialogue de sortie avec réponse perdue';
    const exitExplanation=`${savedPhoneExplanation} Complément synthétique enregistré avant la sortie.`;
    const exitPhone=page.getByLabel('Explication · Téléphone',{exact:true});
    await page.locator('details').filter({has:exitPhone}).locator('summary').click();await exitPhone.fill(exitExplanation);
    let exitWrites=0,exitOperation='',exitHTTPStatus=0;
    await page.route(draftEndpoint,async route=>{
      if(route.request().method()!=='PUT'){await route.continue();return;}
      exitWrites++;exitOperation=route.request().headers()['idempotency-key']??'';
      const committed=await route.fetch();exitHTTPStatus=committed.status();await route.abort('failed');
    });
    await page.getByRole('button',{name:'Se déconnecter',exact:true}).click();
    const exitDialog=page.getByRole('dialog',{name:'Enregistrer avant de quitter ?',exact:true});
    await exitDialog.getByRole('button',{name:'Enregistrer et quitter',exact:true}).click();
    await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor();await exitDialog.waitFor({state:'hidden'});
    assert(exitWrites===1&&exitHTTPStatus===200&&z.uuid().safeParse(exitOperation).success,
      'Une réponse de sauvegarde perdue ferme le dialogue de sortie sans abandonner la commande durable');
    await page.getByRole('button',{name:'Se déconnecter',exact:true}).click();
    assert(await exitDialog.count()===0&&await page.getByRole('button',{name:'Vérifier auprès de l’école',exact:true}).isEnabled(),
      'Une nouvelle tentative de sortie ne masque pas la récupération de la demande incertaine');
    await page.getByRole('button',{name:'Vérifier auprès de l’école',exact:true}).click();
    await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor({state:'hidden'});
    await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    await page.waitForFunction(value=>document.querySelector<HTMLTextAreaElement>('[name^="profile.fields."][name$=".explanation"]')!==null&&[...document.querySelectorAll<HTMLTextAreaElement>('textarea')].some(input=>input.value===value),exitExplanation);
    const exitSaved=z.object({data:z.object({version:z.number().int(),currentStep:z.string()})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    const exitReceipts=(await administration.query('SELECT count(*)::int AS n FROM drivy.operation WHERE school_id=$1 AND operation_id=$2',[school.id,exitOperation])).rows[0];
    assert(exitWrites===1&&exitReceipts.n===1&&exitSaved.version===resumedDraft.version+1&&exitSaved.currentStep==='PROFILE'&&await exitPhone.inputValue()===exitExplanation,
      'La récupération du dialogue retrouve la saisie avec une seule commande et une seule version supplémentaire');
    await page.unroute(draftEndpoint);
    await page.getByRole('link',{name:'École',exact:true}).click();await page.getByRole('heading',{name:'École',exact:true}).waitFor();
    await page.getByRole('link',{name:'Préparation',exact:true}).click();await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    assert(await exitPhone.inputValue()===exitExplanation,'Après récupération, quitter puis reprendre le guide reste possible sans perdre la saisie enregistrée');
    stage='erreur précise dans les informations demandées';
    const phoneExplanation=page.getByLabel('Explication · Téléphone',{exact:true});
    const originalPhoneExplanation=await phoneExplanation.inputValue();
    await page.locator('details').filter({has:phoneExplanation}).locator('summary').click();await phoneExplanation.fill('');
    await page.getByRole('button',{name:/Vérifier et démarrer/}).click();
    await page.getByRole('button',{name:'Expliquez à l’élève pourquoi cette information est demandée.',exact:true}).click();
    await page.waitForFunction(()=>{const active=document.activeElement;return active instanceof HTMLTextAreaElement&&active.name.startsWith('profile.fields.')&&active.value==='';});
    assert(await phoneExplanation.evaluate(element=>element===document.activeElement&&element.getAttribute('aria-invalid')==='true'&&!!document.getElementById(element.getAttribute('aria-describedby')??'')?.textContent?.includes('pourquoi cette information'))&&await phoneExplanation.isVisible(),
      'L’erreur d’explication retourne au téléphone concerné et lui associe son message, sans viser le prénom valide');
    await phoneExplanation.fill(originalPhoneExplanation);
    stage='transition du guide sur mobile depuis le bas de page';await page.setViewportSize({width:390,height:844});
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
    await page.getByRole('heading',{name:'Vos formations',exact:true}).waitFor();
    await page.waitForFunction(()=>{const title=document.querySelector('.setup-title');const bounds=title?.getBoundingClientRect();return title===document.activeElement&&bounds&&bounds.top>=0&&bounds.bottom<window.innerHeight;});
    assert(true,'Continuer depuis le bas d’une étape mobile montre et focalise le titre de l’étape suivante');
    await page.setViewportSize({width:1440,height:1100});
    stage='préparation des informations élèves et du permis B';
    await page.getByRole('heading',{name:'Vos formations',exact:true}).waitFor();await page.getByRole('button',{name:'Permis B',exact:true}).click();
    const secondCompetence=page.locator('[name="formations.0.competencies.1.label"]');
    const thirdDescription=page.locator('[name="formations.0.competencies.2.description"]');
    const originalSecondCompetence=await secondCompetence.inputValue(),originalThirdDescription=await thirdDescription.inputValue();
    await page.locator('details').filter({has:secondCompetence}).locator('summary').click();
    await secondCompetence.fill('');await thirdDescription.fill('');
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vos tarifs',exact:true}).waitFor();
    await page.getByLabel('Prix (CHF)',{exact:true}).fill('95');await page.getByLabel('Durée (minutes)',{exact:true}).fill('50');
    await page.getByLabel('Conditions d’annulation',{exact:true}).fill('');
    await page.getByLabel('Conditions du tarif',{exact:true}).fill('Tarif synthétique pour une leçon de 50 minutes, destiné seulement à cette recette.');
    await page.getByLabel('Proposer cette formation et ce tarif après confirmation',{exact:true}).check();
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vérifier et démarrer',exact:true}).waitFor();
    stage='erreurs précises et associées dans les compétences et l’annulation';
    for(const [field,message,value] of [
      ['formations.0.competencies.1.label','Indiquez le nom de cette compétence.',originalSecondCompetence],
      ['formations.0.competencies.2.description','Décrivez cette compétence.',originalThirdDescription],
      ['formations.0.cancellationPolicyText','Complétez les conditions d’annulation.','Recette synthétique : annulation au moins 24 heures avant la leçon.']
    ] as const) {
      await page.getByRole('button',{name:message,exact:true}).click();
      const fieldInput=page.locator(`[name="${field}"]`);
      await page.waitForFunction(name=>document.activeElement?.getAttribute('name')===name,field);
      const before=await fieldInput.evaluate(element=>({invalid:element.getAttribute('aria-invalid'),description:(element.getAttribute('aria-describedby')??'').split(/\s+/).map(id=>document.getElementById(id)?.textContent??'').join(' '),visible:element.getBoundingClientRect().top>=0&&element.getBoundingClientRect().bottom<=window.innerHeight}));
      await fieldInput.fill(value);
      await page.waitForFunction(name=>document.querySelector(`[name="${name}"]`)?.getAttribute('aria-invalid')!=='true',field);
      assert(before.invalid==='true'&&before.description.includes(message)&&before.visible,`La revue cible ${field}, associe son erreur et retire celle-ci après correction`);
      await page.getByRole('button',{name:/Vérifier et démarrer/}).click();
      await page.getByRole('heading',{name:'Vérifier et démarrer',exact:true}).waitFor();
    }
    const acknowledgement=page.getByLabel('J’ai relu ces choix et ces textes. Je les adopte pour mon école et confirme son activation.',{exact:true});await acknowledgement.waitFor();
    assert(!(await acknowledgement.isChecked()),'Les textes et l’activation ne sont jamais préconfirmés');
    assert((await administration.query('SELECT status FROM drivy.school WHERE id=$1',[school.id])).rows[0].status==='DRAFT','Les étapes enregistrées ne déclenchent aucune activation implicite');
    await page.screenshot({path:resolve(artifactDirectory,'02-relecture-desktop-synthetic.png'),fullPage:true});
    stage='activation explicite et ouverture du planning';await acknowledgement.check();await page.getByRole('button',{name:'Adopter les textes et activer l’école',exact:true}).click();
    await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();
    assert((await administration.query('SELECT status FROM drivy.school WHERE id=$1',[school.id])).rows[0].status==='ACTIVE','L’agenda apparaît après le commit ACTIVE');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.service_product_version WHERE school_id=$1 AND unit_price_cents=9500',[school.id])).rows[0].n===1,'Le tarif saisi est créé sans montant inventé');
    await page.reload();await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();assert(true,'Une école active revient à l’agenda après rechargement');
    await page.screenshot({path:resolve(artifactDirectory,'03-agenda-desktop-synthetic.png'),fullPage:true});
    stage='préparation web sur écran mobile';await page.setViewportSize({width:390,height:844});await page.goto(`${origin}/app/gestion/${school.id}/apercu`);
    await page.getByRole('heading',{name:'Préparation de l’école',exact:true}).waitFor();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'La préparation mobile ne déborde pas horizontalement');
    const mobileMenu=page.getByRole('button',{name:'Menu',exact:true});await mobileMenu.focus();await page.keyboard.press('Enter');
    await page.getByRole('link',{name:'École',exact:true}).waitFor();
    await page.keyboard.press('Escape');await page.waitForFunction(()=>document.querySelector('.navigation-toggle')?.getAttribute('aria-expanded')==='false');
    assert(await mobileMenu.evaluate(element=>element===document.activeElement),'Échap ferme le menu ouvert au clavier et garde le focus sur Menu');
    await page.screenshot({path:resolve(artifactDirectory,'04-preparation-mobile-synthetic.png'),fullPage:true});
    await page.goto(`${origin}/app/gestion/${school.id}/apercu?from=formations`);
    await page.getByRole('heading',{name:'Préparer une formation',exact:true}).waitFor();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),'Le guide de formation mobile ne déborde pas horizontalement');
    await page.screenshot({path:resolve(artifactDirectory,'05-formation-mobile-synthetic.png'),fullPage:true});
    stage='ajout guidé d’un tarif à la formation existante';await page.setViewportSize({width:1440,height:1100});
    const catalogueBefore=(await administration.query(`SELECT
      (SELECT count(*)::int FROM drivy.service_product_version WHERE school_id=$1) AS products,
      (SELECT count(*)::int FROM drivy.offering_version WHERE school_id=$1) AS offerings`,[school.id])).rows[0];
    await page.getByText('Ajouter un tarif à une formation existante',{exact:true}).click();
    await page.getByLabel('Formation',{exact:true}).selectOption({label:'Permis B · 50 min'});
    await page.getByRole('button',{name:'Préparer ce tarif',exact:true}).click();
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vos tarifs',exact:true}).waitFor();
    await page.getByLabel('Prix (CHF)',{exact:true}).fill('105');
    await page.getByLabel('Conditions du tarif',{exact:true}).fill('Tarif supplémentaire synthétique de 105 CHF pour la recette de reprise.');
    await page.getByLabel('Proposer cette formation et ce tarif après confirmation',{exact:true}).check();
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vérifier la formation',exact:true}).waitFor();
    const catalogueReview=page.getByLabel('J’ai relu les formations et tarifs sélectionnés. Je confirme leur mise à disposition.',{exact:true});
    assert(!(await catalogueReview.isChecked()),'Le tarif supplémentaire exige sa propre confirmation et ne réactive pas l’école');
    const catalogueDraft=z.object({data:z.object({version:z.number().int()})}).parse(await (await consumerContext.request.get(draftEndpoint)).json()).data;
    const completeEndpoint=`${draftEndpoint}/complete`;let applyWrites=0,lostApplyOperation='',lostApplyHTTPStatus=0;
    await page.route(completeEndpoint,async route=>{
      if(route.request().method()!=='POST'){await route.continue();return;}
      applyWrites++;if(applyWrites!==1){await route.continue();return;}
      lostApplyOperation=route.request().headers()['idempotency-key']??'';
      const committed=await route.fetch();lostApplyHTTPStatus=committed.status();await route.abort('failed');
    });
    const catalogueDocumentOrigin=await page.evaluate(()=>performance.timeOrigin);
    stage='application catalogue engagée puis réponse navigateur perdue';await catalogueReview.check();
    await page.getByRole('button',{name:'Confirmer la préparation',exact:true}).click();
    await page.getByRole('heading',{name:'Demande à vérifier',exact:true}).waitFor();
    assert(lostApplyHTTPStatus===200&&z.uuid().safeParse(lostApplyOperation).success,'L’ajout du tarif est durable avant la perte de la réponse d’application');
    assert(await page.getByRole('button',{name:'Confirmer la préparation',exact:true}).isDisabled(),'La relecture du catalogue bloque une deuxième application au résultat inconnu');
    stage='récupération AP72 de l’application catalogue sans recharger la page';
    const applyRecoveryResponse=page.waitForResponse(response=>response.request().method()==='GET'&&new URL(response.url()).pathname===`/app/bff/schools/${school.id}/operations/${lostApplyOperation}`);
    await page.getByRole('button',{name:'Vérifier auprès de l’école',exact:true}).click();const recoveredApply=await applyRecoveryResponse;
    const applyReceipt=z.object({data:z.object({operationId:z.uuid(),commandType:z.literal('APPLY_SCHOOL_SETUP_DRAFT'),resourceType:z.literal('SchoolSetupDraft'),
      resourceId:z.uuid(),resourceVersion:z.number().int(),committedAt:z.iso.datetime({offset:true})})}).parse(await recoveredApply.json()).data;
    assert(recoveredApply.ok()&&applyReceipt.operationId===lostApplyOperation&&applyReceipt.resourceId===school.id&&applyReceipt.resourceVersion===catalogueDraft.version+1,
      'AP72 confirme la même application du catalogue et sa seule version supplémentaire');
    await page.getByRole('heading',{name:'Formations et tarifs',exact:true}).waitFor();
    assert(new URL(page.url()).pathname===`/app/gestion/${school.id}/formations`&&await page.evaluate(()=>performance.timeOrigin)===catalogueDocumentOrigin,
      'La confirmation AP72 quitte le guide catalogue et revient aux formations sans rechargement');
    const catalogueAfter=(await administration.query(`SELECT
      (SELECT count(*)::int FROM drivy.service_product_version WHERE school_id=$1) AS products,
      (SELECT count(*)::int FROM drivy.service_product_version WHERE school_id=$1 AND unit_price_cents=10500) AS added,
      (SELECT count(*)::int FROM drivy.offering_version WHERE school_id=$1) AS offerings,
      (SELECT count(*)::int FROM drivy.operation WHERE school_id=$1 AND operation_id=$2 AND command_type='APPLY_SCHOOL_SETUP_DRAFT') AS operations`,[school.id,lostApplyOperation])).rows[0];
    assert(applyWrites===1&&catalogueAfter.products===catalogueBefore.products+1&&catalogueAfter.added===1&&catalogueAfter.offerings===catalogueBefore.offerings&&catalogueAfter.operations===1,
      'La reprise crée exactement un tarif supplémentaire, sans nouvelle formation ni seconde commande');
    await page.unroute(completeEndpoint);
    await page.locator('.formation-prices').getByText(/105[.,]00\s*CHF/).waitFor();
    assert(await page.locator('.formation-prices > li').count()===catalogueBefore.products+1,'Les formations affichent le nouveau tarif après la confirmation du reçu');
    await page.screenshot({path:resolve(artifactDirectory,'07-catalogue-reprise-synthetic.png'),fullPage:true});
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
    await page.getByRole('button',{name:'Relire l’invitation',exact:true}).click();
    const invitationDialog=page.getByRole('dialog');
    const invitationReview=invitationDialog.getByLabel('J’ai vérifié l’adresse et les rôles proposés.',{exact:true});
    assert(!(await invitationReview.isChecked()),'L’envoi à un membre de l’équipe exige une confirmation distincte');
    await invitationReview.check();await invitationDialog.getByRole('button',{name:'Envoyer l’invitation',exact:true}).click();
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
    await staffPage.getByRole('button',{name:'Se connecter',exact:true}).click();
    await staffPage.locator('#kc-registration a').click();
    await staffPage.locator('input[name="username"]').fill('moniteur-recette');await staffPage.locator('input[name="email"]').fill('instructor@example.invalid');
    await staffPage.locator('input[name="firstName"]').fill('Moniteur');await staffPage.locator('input[name="lastName"]').fill('Synthétique');
    await staffPage.locator('input[type="submit"],button[type="submit"]').first().click();
    stage='vérification réelle du compte moniteur';
    await staffPage.goto(mailLink(await ownMail('instructor@example.invalid'),keycloakOrigin,`/realms/${realmName}/login-actions/action-token`));
    stage='choix du mot de passe après vérification du moniteur';const instructorPassword=syntheticSecret();
    await staffPage.locator('input[name="password-new"]').fill(instructorPassword);await staffPage.locator('input[name="password-confirm"]').fill(instructorPassword);
    await staffPage.locator('input[type="submit"],button[type="submit"]').first().click();
    await staffPage.waitForURL(`${origin}/app/invitation`);
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
    await staffPage.reload();await staffPage.getByRole('heading',{name:'Auto-école Recette · synthétique',exact:true}).waitFor();
    await staffPage.screenshot({path:resolve(artifactDirectory,'06-equipe-invitation-acceptee-synthetic.png'),fullPage:true});await staffContext.close();
    await verifySchoolFirstLesson({browser,page,consumerContext,schoolId:school.id,origin,apiOrigin,keycloakOrigin,realmName,administration,
      ownMail,mailLink,deliverInvitation:()=>deliverOneInvitation(mailer!,invitationMail),
      getAccessToken:async()=>{
        const identityResponse=await consumerContext.request.get(`${origin}/app/bff/me`);
        if(!identityResponse.ok())throw new Error('FIRST_LESSON_IDENTITY_UNAVAILABLE');
        const cookie=(await consumerContext.cookies(origin)).find(item=>item.name==='drivy-dev-session');
        const token=sessionStore.get(cookie?.value)?.tokens?.accessToken;
        if(!token)throw new Error('FIRST_LESSON_IDENTITY_UNAVAILABLE');return token;
      },assert,setStage:value=>{stage=value;},artifactDirectory});
    stage='récupération du compte OIDC par courrier';
    const recoveryContext=await browser.newContext({locale:'fr-CH'});recoveryContext.setDefaultTimeout(20_000);
    await recoveryContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const recoveryPage=await recoveryContext.newPage();await recoveryPage.goto(`${origin}/app`);
    await recoveryPage.getByRole('button',{name:'Se connecter',exact:true}).click();
    await recoveryPage.locator('a[href*="/login-actions/reset-credentials"]').click();
    await recoveryPage.locator('input[name="username"]').fill('responsable-recette');
    await recoveryPage.locator('input[type="submit"],button[type="submit"]').first().click();
    const resetLink=mailLink(await ownMail('school@example.invalid'),keycloakOrigin,`/realms/${realmName}/login-actions/action-token`);
    await recoveryPage.goto(resetLink);const recoveredPassword=syntheticSecret();
    await recoveryPage.locator('input[name="password-new"]').fill(recoveredPassword);await recoveryPage.locator('input[name="password-confirm"]').fill(recoveredPassword);
    await recoveryPage.locator('input[type="submit"],button[type="submit"]').first().click();
    await recoveryPage.locator('input[name="password-new"]').waitFor({state:'hidden'});await recoveryContext.close();
    const recoveredContext=await browser.newContext({locale:'fr-CH'});recoveredContext.setDefaultTimeout(20_000);
    await recoveredContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const recoveredPage=await recoveredContext.newPage();await recoveredPage.goto(`${origin}/app`);
    await recoveredPage.getByRole('button',{name:'Se connecter',exact:true}).click();
    await recoveredPage.locator('input[name="username"]').fill('responsable-recette');await recoveredPage.locator('input[name="password"]').fill(recoveredPassword);
    await recoveredPage.locator('input[type="submit"],button[type="submit"]').first().click();await recoveredPage.waitForURL(url=>url.origin===origin);
    const recoveredMe=await recoveredContext.request.get(`${origin}/app/bff/me`);
    const recoveredData=z.object({data:z.object({memberships:z.array(z.object({schoolId:z.string(),roles:z.array(z.string())}))})}).parse(await recoveredMe.json());
    assert(recoveredMe.ok()&&recoveredData.data.memberships.some(member=>member.schoolId===school.id&&member.roles.includes('ADMIN')),'Le mot de passe récupéré reconnecte la même identité et retrouve son école');
    await recoveredContext.close();
    await writeFile(resolve(artifactDirectory,'result.json'),JSON.stringify({status:'PASSED',checkedAt:new Date().toISOString(),browser:browser.version(),checks,
      scope:'Chromium desktop et viewport mobile, Keycloak réel, vérification e-mail, invitation équipe et récupération du compte par SMTP, BFF, API et PostgreSQL isolés ; données synthétiques uniquement. Aucun appareil, GPS, batterie ou lecteur d’écran physique qualifié.'},null,2));
    console.log(`${checks.length} contrôles de recette réussis : navigateur → OIDC → BFF → API → PostgreSQL.`);
  } finally {
    await browser?.close();await web?.close();await api?.close();await runtime?.end();await mailer?.end();await administration.end();
    if(containerStarted)try{await docker(['rm','--force',containerName]);}catch{/* Runner teardown also removes the ephemeral container. */}
    if(temporary){const absolute=resolve(temporary),prefix=resolve(tmpdir())+sep+'drivy-opening-e2e-';if(absolute.startsWith(prefix))await rm(absolute,{recursive:true,force:true});}
  }
}
main().catch(async()=>{
  await mkdir(artifactDirectory,{recursive:true});await writeFile(resolve(artifactDirectory,'result.json'),JSON.stringify({status:'FAILED',stage,passedChecks:checks,checkedAt:new Date().toISOString()},null,2));
  console.error(`Recette ouverture école interrompue : ${stage}. Aucun journal réseau ni identifiant de connexion enregistré.`);process.exitCode=1;
});
