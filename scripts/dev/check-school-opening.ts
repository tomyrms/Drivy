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
import { parseMetadata } from '../../apps/web/client/command-core.js';

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
    web=await buildWebApp({config,identity:await createIdentityProvider(config),staticRoot:fileURLToPath(new URL('../../apps/web/dist/client/',import.meta.url))});
    await api.listen({host:'127.0.0.1',port:3001});await web.listen({host:'127.0.0.1',port:3002});
    await mkdir(artifactDirectory,{recursive:true});
    stage='navigateur Chromium';browser=await chromium.launch({headless:true});
    const operatorContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
    const consumerContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});
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

    const page=await consumerContext.newPage();page.setDefaultTimeout(20_000);
    stage='visite du lien et nouveau compte OIDC';await page.goto(openingLink);
    await page.getByRole('button',{name:'Créer mon compte ou me connecter',exact:true}).waitFor();
    assert(new URL(page.url()).hash==='','Le secret du lien est retiré avant la connexion');
    await page.getByRole('button',{name:'Créer mon compte ou me connecter',exact:true}).click();
    await page.waitForURL(url=>url.origin===keycloakOrigin);
    assert(new URL(page.url()).searchParams.get('code_challenge_method')==='S256' && !page.url().includes(new URL(openingLink).hash.slice(7)),'Connexion OIDC réelle avec PKCE sans secret d’ouverture');
    await page.locator('#kc-registration a').click();
    await page.locator('input[name="username"]').fill('responsable-recette');await page.locator('input[name="email"]').fill('school@example.invalid');
    await page.locator('input[name="firstName"]').fill('Responsable');await page.locator('input[name="lastName"]').fill('Synthétique');
    await page.locator('input[name="password"]').fill(consumerPassword);await page.locator('input[name="password-confirm"]').fill(consumerPassword);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    stage='vérification réelle de l’adresse par SMTP';
    const verification=await ownMail('school@example.invalid');
    assert(new URL(page.url()).origin===keycloakOrigin,'Le compte reste chez le fournisseur avant la vérification de son adresse');
    await page.goto(mailLink(verification,keycloakOrigin,`/realms/${realmName}/login-actions/action-token`));
    await page.waitForURL(`${origin}/app/ouvrir`);await page.getByLabel('Nom de l’auto-école',{exact:true}).waitFor();
    const verifiedSession=await consumerContext.request.get(`${origin}/app/bff/session`);
    assert(z.object({authenticated:z.literal(true),user:z.object({emailVerified:z.literal(true)})}).safeParse(await verifiedSession.json()).success,'Le lien SMTP vérifie réellement le nouveau compte avant création');
    assert((await administration.query('SELECT count(*)::int AS n FROM drivy.person')).rows[0].n===0,'Le nouveau compte OIDC n’est pas créé dans la base métier avant confirmation');
    stage='création volontaire et perte de réponse navigateur';await page.getByLabel('Votre nom',{exact:true}).fill('Responsable de recette synthétique');
    await page.getByLabel('Nom de l’auto-école',{exact:true}).fill('Auto-école Recette · synthétique');await page.getByLabel('E-mail professionnel',{exact:true}).fill('school@example.invalid');
    await page.getByLabel('Je donne aussi des leçons',{exact:true}).check();
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
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    stage='reprise serveur après rechargement';await page.reload();await page.getByRole('heading',{name:'Informations des élèves',exact:true}).waitFor();
    const draftResponse=await consumerContext.request.get(`${origin}/app/bff/schools/${school.id}/setup-draft`);const draft=await draftResponse.json() as {data:{currentStep:string;content:{privacy:{noticeText:string}}}};
    assert(draftResponse.ok() && draft.data.currentStep==='PROFILE' && draft.data.content.privacy.noticeText===notice,'Le rechargement reprend le brouillon et l’étape réellement enregistrés');
    await page.screenshot({path:resolve(artifactDirectory,'01-profil-desktop-synthetic.png'),fullPage:true});
    stage='préparation des informations élèves et du permis B';await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();
    await page.getByRole('heading',{name:'Vos formations',exact:true}).waitFor();await page.getByRole('button',{name:'Permis B',exact:true}).click();
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vos tarifs',exact:true}).waitFor();
    await page.getByLabel('Prix (CHF)',{exact:true}).fill('95');await page.getByLabel('Durée (minutes)',{exact:true}).fill('50');
    await page.getByLabel('Conditions d’annulation',{exact:true}).fill('Recette synthétique : annulation au moins 24 heures avant la leçon.');
    await page.getByLabel('Conditions du tarif',{exact:true}).fill('Tarif synthétique pour une leçon de 50 minutes, destiné seulement à cette recette.');
    await page.getByLabel('Proposer cette formation et ce tarif après confirmation',{exact:true}).check();
    await page.getByRole('button',{name:'Enregistrer et continuer',exact:true}).click();await page.getByRole('heading',{name:'Vérifier et démarrer',exact:true}).waitFor();
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
    assert(await page.getByRole('checkbox',{name:'Moniteur',exact:true}).isChecked(),'Une invitation de l’équipe propose explicitement le rôle moniteur');
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
    const instructorPassword=syntheticSecret();await staffPage.locator('input[name="password"]').fill(instructorPassword);await staffPage.locator('input[name="password-confirm"]').fill(instructorPassword);
    await staffPage.locator('input[type="submit"],button[type="submit"]').first().click();
    stage='vérification réelle du compte moniteur';
    await staffPage.goto(mailLink(await ownMail('instructor@example.invalid'),keycloakOrigin,`/realms/${realmName}/login-actions/action-token`));
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
