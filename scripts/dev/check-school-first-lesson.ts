/** Suite de la recette synthétique : préparation par le portail, réservation par l’API utilisée par l’app. */
import {randomBytes,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import type {Pool} from 'pg';
import {z} from 'zod';
import type {Browser} from '../../infra/dev/browser.js';

type BrowserContext=Awaited<ReturnType<Browser['newContext']>>;
type Page=Awaited<ReturnType<BrowserContext['newPage']>>;
export interface FirstLessonOptions {
  browser:Browser;page:Page;consumerContext:BrowserContext;schoolId:string;origin:string;apiOrigin:string;
  keycloakOrigin:string;realmName:string;administration:Pool;artifactDirectory:string;
  ownMail:(email:string)=>Promise<string>;
  mailLink:(text:string,expectedOrigin:string,path:string)=>string;
  deliverInvitation:()=>Promise<unknown>;
  /** Jeton issu de la connexion réelle, conservé en mémoire : aucun journal ni artefact ne le reçoit. */
  getAccessToken:()=>Promise<string>;
  assert:(value:unknown,label:string)=>void;
  setStage:(value:string)=>void;
}
const nextSchema=z.object({schoolId:z.uuid(),planningReady:z.boolean(),actions:z.array(z.object({
  code:z.string(),section:z.string(),query:z.record(z.string(),z.string()).optional()
}))});
const membersSchema=z.object({items:z.array(z.object({id:z.uuid(),displayName:z.string(),roles:z.array(z.string()),status:z.string()}))});
const learnersSchema=z.object({items:z.array(z.object({id:z.uuid(),displayName:z.string(),contactEmail:z.string().nullable()}))});
const trainingSchema=z.object({items:z.array(z.object({id:z.uuid(),learnerId:z.uuid(),offeringId:z.uuid(),status:z.string()}))});
const offeringsSchema=z.object({items:z.array(z.object({id:z.uuid(),categoryCode:z.string(),policyVersionId:z.uuid().nullable(),enabled:z.boolean()}))});
const productsSchema=z.object({items:z.array(z.object({id:z.uuid(),enabled:z.boolean(),categoryCode:z.string().nullable(),durationMinutes:z.number().nullable(),
  unitPriceCents:z.number(),termsVersionId:z.uuid(),type:z.string()}))});
const readinessSchema=z.object({learnerId:z.uuid(),ready:z.boolean(),blockers:z.array(z.object({code:z.string()}))});
const slotSchema=z.object({slot:z.object({plannedStart:z.iso.datetime({offset:true}),plannedEnd:z.iso.datetime({offset:true})}).nullable(),timeZone:z.string()});

export async function verifySchoolFirstLesson(options:FirstLessonOptions):Promise<void> {
  const {browser,page,consumerContext,schoolId,origin,apiOrigin,keycloakOrigin,realmName,administration,artifactDirectory,
    ownMail,mailLink,deliverInvitation,getAccessToken,assert,setStage}=options;
  const schoolPath=`${origin}/app/gestion/${schoolId}`,bff=`${origin}/app/bff/schools/${schoolId}`;
  async function read<T>(path:string,schema:z.ZodType<T>):Promise<T> {
    const response=await consumerContext.request.get(`${bff}${path?`/${path}`:''}`);
    if(!response.ok())throw new Error('FIRST_LESSON_READ_FAILED');
    return z.object({data:schema}).parse(await response.json()).data;
  }
  async function native(path:string,body?:Record<string,unknown>) {
    const accessToken=await getAccessToken();
    if(!accessToken)throw new Error('FIRST_LESSON_SESSION_MISSING');
    return fetch(`${apiOrigin}/v1/schools/${schoolId}/${path}`,{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(15_000),
      headers:{Authorization:`Bearer ${accessToken}`,...(body?{'Content-Type':'application/json','Idempotency-Key':String(body.operationId)}:{})},
      ...(body?{body:JSON.stringify(body)}:{})});
  }
  async function agenda() {await page.goto(`${schoolPath}/agenda`);await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();}
  async function addAvailability(instructorId:string) {
    await page.getByRole('heading',{name:'Disponibilités',exact:true}).waitFor();
    await page.getByLabel('Moniteur',{exact:true}).selectOption(instructorId);
    await page.getByText('Ajouter un horaire',{exact:true}).click();
    const form=page.locator('details.schedule-add');
    for(const day of ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'])await form.getByLabel(day,{exact:true}).check();
    await form.getByLabel('De',{exact:true}).fill('08:00');await form.getByLabel('À',{exact:true}).fill('18:00');
    const response=page.waitForResponse(value=>value.request().method()==='POST'&&value.url()===`${bff}/availability-rules`);
    await form.getByRole('button',{name:'Ajouter l’horaire',exact:true}).click();
    if(!(await response).ok())throw new Error('FIRST_LESSON_AVAILABILITY_FAILED');
    await page.waitForFunction(()=>!document.querySelector<HTMLDetailsElement>('details.schedule-add')?.open);
  }

  setStage('première leçon : disponibilités depuis l’action du planning');
  const school=await read('',z.object({name:z.string(),timeZone:z.string()}));
  const members=(await read('members',membersSchema)).items;
  const founder=members.find(member=>member.status==='ACTIVE'&&member.roles.includes('ADMIN')&&member.roles.includes('INSTRUCTOR'));
  const colleague=members.find(member=>member.status==='ACTIVE'&&member.roles.includes('INSTRUCTOR')&&!member.roles.includes('ADMIN'));
  if(!founder||!colleague)throw new Error('FIRST_LESSON_INSTRUCTORS_MISSING');
  const initial=await read('setup-draft/next-actions',nextSchema);
  assert(!initial.planningReady&&initial.actions.some(action=>action.code==='AVAILABILITY_REQUIRED'),'Après activation, les disponibilités encore absentes restent un vrai prérequis');
  await agenda();
  await page.locator('.blocker-list li').filter({hasText:'Renseignez les disponibilités d’au moins un moniteur actif.'}).getByRole('button',{name:'Ouvrir',exact:true}).click();
  // La première disponibilité appartient à l’autre moniteur : la suite doit encore vérifier celui affecté à l’élève.
  await addAvailability(colleague.id);
  const firstLearner=await read('setup-draft/next-actions',nextSchema);
  assert(firstLearner.planningReady&&firstLearner.actions[0]?.code==='FIRST_LEARNER_REQUIRED','Une disponibilité confirmée fait proposer l’invitation du premier élève');

  setStage('première leçon : invitation élève guidée et acceptation réelle');
  await agenda();await page.getByRole('link',{name:'Inviter votre premier élève',exact:true}).click();
  assert(new URL(page.url()).searchParams.get('audience')==='learners','L’action du planning ouvre les invitations destinées aux élèves');
  const learnerEmail='first-learner@example.invalid';
  await page.getByRole('button',{name:'Inviter par e-mail',exact:true}).click();
  await page.getByLabel('Adresse e-mail',{exact:true}).fill(learnerEmail);
  await page.getByRole('button',{name:'Relire l’invitation',exact:true}).click();
  const invitationDialog=page.getByRole('dialog');
  await invitationDialog.getByLabel('J’ai vérifié l’adresse et les rôles proposés.',{exact:true}).check();
  await invitationDialog.getByRole('button',{name:'Envoyer l’invitation',exact:true}).click();await invitationDialog.waitFor({state:'hidden'});
  const pending=await read('setup-draft/next-actions',nextSchema);
  assert(pending.actions[0]?.code==='LEARNER_INVITATION_PENDING'&&(await read('learners',learnersSchema)).items.length===0,
    'L’invitation envoyée ne crée aucun dossier ni fausse possibilité de planifier');
  await agenda();await page.getByRole('link',{name:'Consulter l’invitation en attente',exact:true}).click();
  await page.getByRole('heading',{name:'Invitations élèves',exact:true}).waitFor();
  await deliverInvitation();
  const invitationURL=mailLink(await ownMail(learnerEmail),origin,'/app/invitation');
  const learnerContext=await browser.newContext({viewport:{width:1440,height:1100},locale:'fr-CH'});learnerContext.setDefaultTimeout(20_000);
  try {
    await learnerContext.route('**/*',route=>[origin,keycloakOrigin].includes(new URL(route.request().url()).origin)?route.continue():route.abort());
    const learnerPage=await learnerContext.newPage();await learnerPage.goto(invitationURL);
    await learnerPage.getByRole('button',{name:'Se connecter',exact:true}).click();await learnerPage.locator('#kc-registration a').click();
    await learnerPage.locator('input[name="username"]').fill('premier-eleve-recette');await learnerPage.locator('input[name="email"]').fill(learnerEmail);
    await learnerPage.locator('input[name="firstName"]').fill('Élève');await learnerPage.locator('input[name="lastName"]').fill('Synthétique');
    await learnerPage.locator('input[type="submit"],button[type="submit"]').first().click();
    await learnerPage.goto(mailLink(await ownMail(learnerEmail),keycloakOrigin,`/realms/${realmName}/login-actions/action-token`));
    const password=randomBytes(36).toString('base64url');
    await learnerPage.locator('input[name="password-new"]').fill(password);await learnerPage.locator('input[name="password-confirm"]').fill(password);
    await learnerPage.locator('input[type="submit"],button[type="submit"]').first().click();await learnerPage.waitForURL(`${origin}/app/invitation`);
    const session=await learnerContext.request.get(`${origin}/app/bff/session`);
    assert(z.object({authenticated:z.literal(true),user:z.object({emailVerified:z.literal(true)})}).safeParse(await session.json()).success,
      'Le premier élève vérifie son adresse OIDC avant d’accepter le rattachement');
    await learnerPage.getByRole('checkbox').check();await learnerPage.getByRole('button',{name:'Rejoindre cette école',exact:true}).click();
    await learnerPage.getByText(`Vous avez rejoint ${school.name}`,{exact:true}).waitFor();
  } finally {await learnerContext.close();}

  setStage('première leçon : compléter le bon dossier puis ouvrir sa formation');
  const learner=(await read('learners',learnersSchema)).items.find(item=>item.contactEmail===learnerEmail);
  if(!learner)throw new Error('FIRST_LESSON_LEARNER_MISSING');
  const profileAction=await read('setup-draft/next-actions',nextSchema);
  assert(profileAction.actions[0]?.code==='PROFILE_ACTION_REQUIRED'&&profileAction.actions[0]?.query?.selection===learner.id,
    'Après acceptation, le guide désigne les informations réellement manquantes du bon élève');
  await agenda();await page.getByRole('link',{name:'Compléter le dossier de l’élève',exact:true}).click();
  assert(new URL(page.url()).searchParams.get('selection')===learner.id,'Le lien de préparation sélectionne le dossier de l’élève accepté');
  const profile=page.locator('.profile-completion');
  await profile.getByLabel('Prénom',{exact:true}).fill('Élève');await profile.getByLabel('Nom',{exact:true}).fill('Première leçon');
  await profile.getByRole('button',{name:'Enregistrer le profil',exact:true}).click();await profile.waitFor({state:'hidden'});
  const withoutTraining=await read('setup-draft/next-actions',nextSchema);
  assert(withoutTraining.actions[0]?.code==='TRAINING_NOT_ACTIVE'&&withoutTraining.actions[0]?.query?.selection===learner.id,
    'Le dossier complété conduit à l’ouverture de sa formation, sans annoncer une leçon prête');
  await agenda();await page.getByRole('link',{name:'Ouvrir la formation de l’élève',exact:true}).click();
  await page.getByText('Ouvrir une formation',{exact:true}).click();
  await page.getByLabel('Nouvelle formation',{exact:true}).selectOption({label:'Permis B'});
  const trainingResponse=page.waitForResponse(response=>response.request().method()==='POST'&&response.url()===`${bff}/trainings`);
  await page.getByRole('button',{name:'Ouvrir la formation',exact:true}).click();
  if(!(await trainingResponse).ok())throw new Error('FIRST_LESSON_TRAINING_FAILED');
  const training=(await read('trainings',trainingSchema)).items.find(item=>item.learnerId===learner.id&&item.status==='ACTIVE');
  if(!training)throw new Error('FIRST_LESSON_TRAINING_MISSING');
  const assignments=await read(`trainings/${training.id}/assignments`,z.object({items:z.array(z.object({instructorMembershipId:z.uuid()}))}));
  assert(assignments.items.length===1&&assignments.items[0]?.instructorMembershipId===founder.id,'Le responsable qui donne des leçons est réellement affecté à la formation qu’il ouvre');

  setStage('première leçon : disponibilité du moniteur réellement affecté');
  const assignedAvailability=await read('setup-draft/next-actions',nextSchema);
  assert(assignedAvailability.actions[0]?.code==='AVAILABILITY_REQUIRED'&&assignedAvailability.actions[0]?.section==='disponibilites'&&assignedAvailability.actions[0]?.query?.instructor===founder.id,
    'Les horaires d’un autre moniteur ne rendent pas la formation planifiable : le guide cible celui affecté');
  await agenda();await page.getByRole('link',{name:'Définir les disponibilités du moniteur affecté',exact:true}).click();
  assert(new URL(page.url()).searchParams.get('instructor')===founder.id,'L’action ouvre les disponibilités avec le moniteur affecté sélectionné');
  await addAvailability(founder.id);
  const ready=await read(`learners/${learner.id}/action-readiness?action=PLAN_LESSON`,readinessSchema);
  const finalAction=await read('setup-draft/next-actions',nextSchema);
  assert(ready.ready&&ready.blockers.length===0&&finalAction.actions[0]?.code==='PLAN_FIRST_LESSON'&&finalAction.actions[0]?.query?.selection===learner.id,
    'La préparation serveur de ce dossier autorise la planification seulement après ses vrais prérequis');
  await agenda();await page.getByRole('button',{name:'Planifier dans l’app Drivy',exact:true}).click();
  const appDialog=page.getByRole('dialog',{name:'Votre première leçon',exact:true});
  await appDialog.getByText(/Connectez-vous à l’app Drivy avec votre compte moniteur/).waitFor();
  await appDialog.getByRole('button',{name:'Voir le dossier',exact:true}).click();
  assert(new URL(page.url()).pathname===`/app/gestion/${schoolId}/eleves`&&new URL(page.url()).searchParams.get('selection')===learner.id,
    'Le relais vers l’app explique la planification et conserve le bon dossier sans inventer de lien d’installation');

  setStage('première leçon : créneau et réservation par l’API de l’app avec le vrai compte OIDC');
  const offering=(await read('offerings',offeringsSchema)).items.find(item=>item.id===training.offeringId&&item.enabled);
  if(!offering?.policyVersionId)throw new Error('FIRST_LESSON_OFFERING_MISSING');
  const product=(await read('service-products',productsSchema)).items.find(item=>item.enabled&&item.type==='INDIVIDUAL_LESSON'&&item.categoryCode===offering.categoryCode&&item.durationMinutes===50&&item.unitPriceCents===9500);
  if(!product?.durationMinutes)throw new Error('FIRST_LESSON_PRODUCT_MISSING');
  const query=new URLSearchParams({trainingId:training.id,instructorMembershipId:founder.id,durationMinutes:String(product.durationMinutes),bufferMinutes:'0',timeZone:school.timeZone,days:'14'});
  const nextSlot=await native(`lessons/next-slot?${query}`);
  if(!nextSlot.ok)throw new Error('FIRST_LESSON_SLOT_FAILED');
  const slot=z.object({data:slotSchema}).parse(await nextSlot.json()).data.slot;
  if(!slot)throw new Error('FIRST_LESSON_SLOT_MISSING');
  const availabilityQuery=new URLSearchParams({trainingId:training.id,instructorMembershipId:founder.id,...slot,timeZone:school.timeZone,bufferMinutes:'0'});
  const available=await native(`lessons/availability?${availabilityQuery}`);
  assert(available.ok&&z.object({data:z.object({available:z.literal(true)})}).safeParse(await available.json()).success,
    'Un vrai créneau futur est proposé puis confirmé disponible par l’API de planification');
  const operationId=randomUUID(),command={operationId,trainingId:training.id,instructorMembershipId:founder.id,...slot,timeZone:school.timeZone,
    meetingPoint:'Point de rencontre synthétique',agreedPriceCents:product.unitPriceCents,bufferMinutes:0,policyVersionId:offering.policyVersionId,
    commercialSelection:{mode:'UNIT_PRICE',serviceProductVersionId:product.id,quantity:1,entitlementLotId:null,acceptedTermsVersionId:product.termsVersionId}};
  const response=await native('lessons',command);
  if(response.status!==201)throw new Error('FIRST_LESSON_BOOKING_FAILED');
  const lesson=z.object({data:z.object({id:z.uuid(),status:z.literal('PLANNED'),learnerId:z.uuid(),trainingId:z.uuid(),instructorMembershipId:z.uuid(),priceCentsSnapshot:z.number()})}).parse(await response.json()).data;
  assert(lesson.learnerId===learner.id&&lesson.trainingId===training.id&&lesson.instructorMembershipId===founder.id&&lesson.priceCentsSnapshot===9500,
    'L’API confirme une vraie leçon planifiée pour cet élève, ce moniteur et le tarif explicitement préparé');
  const proof=(await administration.query(`SELECT
    (SELECT count(*)::int FROM drivy.lesson WHERE school_id=$1 AND id=$2 AND status='PLANNED') AS lessons,
    (SELECT count(*)::int FROM drivy.reservation WHERE school_id=$1 AND lesson_id=$2 AND active) AS reservations,
    (SELECT count(*)::int FROM drivy.operation WHERE school_id=$1 AND operation_id=$3 AND command_type='CREATE_LESSON') AS operations,
    (SELECT count(*)::int FROM drivy.recording_choice WHERE school_id=$1) AS gps_choices,
    (SELECT count(*)::int FROM drivy.capture_session WHERE school_id=$1) AS captures`,[schoolId,lesson.id,operationId])).rows[0];
  assert(proof.lessons===1&&proof.reservations===2&&proof.operations===1&&proof.gps_choices===0&&proof.captures===0,
    'La leçon, les deux occupations et son reçu sont durables sans accord GPS ni trajet fabriqué');
  const receipt=await read(`operations/${operationId}`,z.object({commandType:z.string(),resourceId:z.uuid()}));
  assert(receipt.commandType==='CREATE_LESSON'&&receipt.resourceId===lesson.id,'Le reçu AP72 confirme la réservation de cette première leçon');

  setStage('première leçon : relecture dans l’agenda et fin des prochaines actions initiales');
  const civilDay=new Intl.DateTimeFormat('en-CA',{timeZone:school.timeZone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(slot.plannedStart));
  await page.goto(`${schoolPath}/agenda?week=${civilDay}`);await page.getByRole('heading',{name:'Agenda',exact:true}).waitFor();
  await page.locator('.agenda-lesson').waitFor();
  const final=await read('setup-draft/next-actions',nextSchema);
  assert(final.planningReady&&final.actions.length===0&&await page.locator('.agenda-lesson').count()===1,
    'L’Agenda relit la première leçon durable et les actions de première utilisation sont terminées');
  await page.screenshot({path:resolve(artifactDirectory,'08-premiere-lecon-planifiee-synthetic.png'),fullPage:true});
  await page.locator('.agenda-lesson').click();
  assert(new URL(page.url()).searchParams.get('selection')===learner.id,'La leçon de l’Agenda ouvre toujours le dossier du bon élève');
}
