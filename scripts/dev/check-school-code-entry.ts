/** Code élève : rattachement web réel, puis dossier utilisable dans l’app avec le même compte. */
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {Pool} from 'pg';
import {z} from 'zod';
import type {Browser} from '../../infra/dev/browser.js';

export async function verifySchoolCodeEntry(options:{browser:Browser;origin:string;apiOrigin:string;keycloakOrigin:string;
  schoolId:string;administration:Pool;getAccessToken:()=>Promise<string>;existingEmail:string;existingPassword:string;artifactDirectory:string;
  assert:(value:unknown,label:string)=>void;setStage:(value:string)=>void}):Promise<void> {
  const {browser,origin,apiOrigin,keycloakOrigin,schoolId,administration,getAccessToken,existingEmail,existingPassword,artifactDirectory,assert}=options;
  let stage='code élève : préparation';
  const setStage=(value:string)=>{stage=value;options.setStage(value);};
  async function native(path:string,body?:{operationId:string;[key:string]:unknown}) {
    const response=await fetch(`${apiOrigin}/v1/schools/${schoolId}/${path}`,{
      method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(15_000),
      headers:{Authorization:`Bearer ${await getAccessToken()}`,...(body?{'Content-Type':'application/json','Idempotency-Key':body.operationId}:{})},
      ...(body?{body:JSON.stringify(body)}:{})});
    if(!response.ok){setStage(`${stage} · API HTTP ${response.status}`);throw new Error('CODE_ENTRY_SETUP_FAILED');}return response.json();
  }
  setStage('code élève : lecture du moniteur et de la version courante du permis B');
  const members=z.object({data:z.object({items:z.array(z.object({id:z.uuid(),roles:z.array(z.string()),status:z.string()}))})}).parse(await native('members')).data.items;
  const instructor=members.find(member=>member.status==='ACTIVE'&&member.roles.includes('INSTRUCTOR')&&member.roles.includes('ADMIN'));
  // La recette précédente a révisé B : /offerings contient aussi l'ancienne version, encore enabled.
  // La fiche expose les seules têtes courantes, comme le formulaire d'invitation de l'école.
  const programmes=z.object({data:z.object({programmes:z.array(z.object({head:z.object({id:z.uuid(),enabled:z.boolean()}),
    curriculum:z.object({approved:z.boolean()}).nullable(),procedure:z.object({approved:z.boolean()}).nullable()}))})}).parse(await native('formations/sheet?category=B')).data.programmes;
  const offering=programmes.find(value=>value.head.enabled&&value.curriculum?.approved&&value.procedure?.approved)?.head;
  if(!instructor||!offering)throw new Error('CODE_ENTRY_TRAINING_MISSING');
  const school=(await administration.query('SELECT name FROM drivy.school WHERE id=$1',[schoolId])).rows[0];
  if(!school)throw new Error('CODE_ENTRY_SCHOOL_MISSING');
  for(const entry of ['existing','new','signed-in'] as const) {
    const fresh=entry==='new',signedIn=entry==='signed-in';
    const step=(detail:string)=>setStage(`code élève · ${fresh?'nouveau compte':signedIn?'compte connecté':'compte existant'} : ${detail}`);
    step('création de l’invitation sur le programme courant');
    const invitation=z.object({data:z.object({id:z.uuid(),code:z.string()})}).parse(await native('invitations',{
      operationId:randomUUID(),delivery:'CODE',roles:['LEARNER'],training:{offeringId:offering.id,instructorMembershipId:instructor.id}})).data;
    const context=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});context.setDefaultTimeout(20_000);
    const firstName=fresh?'Camille Anne':'Responsable',lastName=fresh?'De la Tour-Roux':'Synthétique';
    const email=fresh?'code-learner@example.invalid':existingEmail,password=fresh?randomBytes(36).toString('base64url'):existingPassword;
    let page:Awaited<ReturnType<typeof context.newPage>>|undefined;
    try {
      await context.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
      step('ouverture du formulaire Drivy');
      page=await context.newPage();await page.goto(`${origin}/app`);
      const before=(await administration.query('SELECT count(*)::int AS n FROM drivy.learner_profile WHERE school_id=$1',[schoolId])).rows[0].n;
      let signedPersonId:string|undefined,previousProfile:unknown;
      if(signedIn) {
        step('connexion préalable et lecture des écoles');
        await page.getByLabel('E-mail',{exact:true}).fill(email);await page.getByLabel('Mot de passe',{exact:true}).fill(password);
        await page.getByRole('button',{name:'Se connecter',exact:true}).click();
        await page.getByRole('heading',{name:'Une école liée',exact:true}).waitFor();
        const response=await context.request.get(`${origin}/app/bff/me`);
        signedPersonId=z.object({data:z.object({personId:z.uuid()})}).parse(await response.json()).data.personId;
        previousProfile=(await administration.query('SELECT to_jsonb(l) AS profile FROM drivy.learner_profile l WHERE school_id=$1 AND person_id=$2',[schoolId,signedPersonId])).rows[0]?.profile;
        assert(response.ok()&&previousProfile!==undefined&&await page.getByRole('button',{name:'J’ai un code',exact:true}).isVisible(),
          'Un compte déjà connecté et membre peut saisir un code depuis ses écoles, sans se déconnecter');
      }
      step('ouverture de la saisie du code');
      await page.getByRole('button',{name:'J’ai un code',exact:true}).click();
      step('saisie du code et choix du parcours de compte');
      await page.getByLabel('Code ou lien reçu',{exact:true}).fill(invitation.code);
      // Le compte existant choisit ce lien directement : aucun « Continuer » préalable ne prépare son intention.
      await page.getByRole('button',{name:fresh||signedIn?'Continuer':'J’ai déjà un compte',exact:true}).click();
      if(!signedIn) {
        step(fresh?'saisie du nouveau compte':'saisie du compte existant');
        if(fresh) {
          await page.getByLabel('Prénom',{exact:true}).fill(firstName);await page.getByLabel('Nom',{exact:true}).fill(lastName);
        }
        await page.getByLabel('E-mail',{exact:true}).fill(email);await page.getByLabel('Mot de passe',{exact:true}).fill(password);
        step(fresh?'création du compte':'connexion avec le code conservé');
        await page.getByRole('button',{name:fresh?'Créer mon compte':'Se connecter',exact:true}).click();
      }
      step('affichage de l’aperçu de l’école');
      await page.getByRole('heading',{name:school.name,exact:true}).waitFor();
      step('identité présentée avant confirmation');
      assert(await page.locator('.invitation-facts').getByText(`${firstName} ${lastName}`,{exact:true}).isVisible()
        &&await page.getByLabel('Code ou lien reçu',{exact:true}).count()===0,
        `Le code du ${fresh?'nouveau compte':'compte existant'} est conservé jusqu’à l’aperçu de l’école et de l’identité, sans nouvelle saisie`);
      const join=page.getByRole('button',{name:'Rejoindre cette école',exact:true});
      step('absence de dossier avant la confirmation');
      assert(await join.isDisabled()&&(await administration.query('SELECT count(*)::int AS n FROM drivy.learner_profile WHERE school_id=$1',[schoolId])).rows[0].n===before,
        'Lire l’aperçu du code ne crée aucun dossier avant la confirmation volontaire');
      if(fresh) {
        step('compte connecté sans vérification e-mail imposée');
        const session=await context.request.get(`${origin}/app/bff/session`);
        assert(z.object({authenticated:z.literal(true),user:z.object({emailVerified:z.literal(false)})}).safeParse(await session.json()).success,
          'Le compte créé par code arrive à la confirmation sans détour par la vérification d’une adresse non utilisée par l’invitation');
      }
      step('confirmation volontaire du rattachement');
      await page.getByRole('checkbox').check();await join.click();
      step('affichage du rattachement confirmé');
      await page.getByText(`Vous avez rejoint ${school.name}`,{exact:true}).waitFor();
      step('relecture de l’adhésion et des rôles');
      const meResponse=await context.request.get(`${origin}/app/bff/me`);
      const me=z.object({data:z.object({personId:z.uuid(),memberships:z.array(z.object({schoolId:z.uuid(),roles:z.array(z.string())}))})}).parse(await meResponse.json()).data;
      const membership=me.memberships.find(value=>value.schoolId===schoolId);
      assert(meResponse.ok()&&membership?.roles.includes('LEARNER')
        &&(fresh?membership.roles.length===1:membership.roles.includes('ADMIN')&&membership.roles.includes('INSTRUCTOR')),
        'La relecture du même compte retrouve l’école rejointe et préserve ses rôles existants');
      const profiles=(await administration.query(`SELECT id,profile_id,first_name,last_name,display_name FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2`,[schoolId,me.personId])).rows;
      const profile=profiles[0];
      step('noms structurés du dossier durable');
      assert(profiles.length===1&&profile.first_name===firstName&&profile.last_name===lastName&&profile.display_name===`${firstName} ${lastName}`,
        'Le compte rejoint par code possède un seul dossier avec ses noms structurés exacts');
      if(signedIn) {
        step('dossier existant conservé sans réécriture');
        const currentProfile=(await administration.query('SELECT to_jsonb(l) AS profile FROM drivy.learner_profile l WHERE school_id=$1 AND person_id=$2',[schoolId,me.personId])).rows[0]?.profile;
        const total=(await administration.query('SELECT count(*)::int AS n FROM drivy.learner_profile WHERE school_id=$1',[schoolId])).rows[0].n;
        assert(me.personId===signedPersonId&&total===before&&JSON.stringify(currentProfile)===JSON.stringify(previousProfile),
          'Accepter un autre code avec le compte connecté conserve la même personne et tout le dossier existant, sans doublon ni réécriture');
      }
      step('dossier prêt sans seconde saisie de noms');
      const writes=(await administration.query("SELECT count(*)::int AS n FROM drivy.operation WHERE school_id=$1 AND resource_id=$2 AND command_type='UPDATE_ADMINISTRATIVE_PROFILE'",[schoolId,profile.profile_id])).rows[0].n;
      const readiness=z.object({data:z.object({ready:z.boolean(),blockers:z.array(z.unknown())})}).parse(await native(`learners/${profile.id}/action-readiness?action=ENTER`)).data;
      assert(writes===0&&readiness.ready&&readiness.blockers.length===0,
        'Le dossier rejoint par code est prêt pour l’entrée sans seconde commande de noms');
      step('formation unique rattachée au dossier');
      assert((await administration.query('SELECT count(*)::int AS n FROM drivy.training WHERE school_id=$1 AND learner_id=$2',[schoolId,profile.id])).rows[0].n===1,
        'La formation portée par le code est déjà rattachée au dossier avant de passer à l’app');
    } catch(error) {
      const failure=error instanceof z.ZodError?'INVALID_RESPONSE_SCHEMA':error instanceof Error&&error.name==='TimeoutError'?'UI_WAIT_TIMEOUT'
        :error instanceof Error&&error.message.includes('strict mode violation')?'UI_SELECTOR_NOT_UNIQUE':'CHECK_OR_BROWSER_FAILED';
      // Ne jamais conserver le code, les identifiants, les champs saisis, l'URL ou le message brut d'exception.
      const ui=await page?.evaluate(()=>({
        codeField:!!document.querySelector('input[name="code"]'),accountFields:!!document.querySelector('input[name="password"]'),
        preview:!!document.querySelector('.invitation-facts'),identityPresented:!!document.querySelector('.invitation-facts dd'),
        alerts:document.querySelectorAll('[role="alert"]').length,confirmationControls:document.querySelectorAll('[role="checkbox"],input[type="checkbox"]').length,
      })).catch(()=>null);
      await writeFile(resolve(artifactDirectory,`99-code-${entry}-diagnostic.json`),JSON.stringify({stage,failure,ui:ui??null},null,2)).catch(()=>undefined);
      throw error;
    } finally {await context.close();}
  }
}
