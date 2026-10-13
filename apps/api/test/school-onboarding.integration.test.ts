import {randomUUID} from 'node:crypto';
import {beforeAll,beforeEach,afterAll,expect,it} from 'vitest';
import {Pool} from 'pg';
import {buildApp} from '../src/app.js';
import {registerSchoolOnboarding} from '../src/school-onboarding.js';
import {setupTemplates,type SetupContent,type SetupFormation} from '../src/school-onboarding-model.js';
import {migrate} from '../scripts/migrations.js';
import {fixtureIds as id,seedFixtures} from '../scripts/fixtures.js';

const url=process.env.TEST_DATABASE_URL;
if(!url||new URL(url).pathname!=='/drivy_test')throw new Error('Base de recette isolée drivy_test obligatoire.');
const pool=new Pool({connectionString:url,max:8});
const issuer='https://identity.test.invalid',base=`/v1/schools/${id.schoolA}/setup-draft`;
const options={pool,cursorSecret:'school-onboarding-synthetic-test-secret',verifyToken:async(header:string|undefined)=>({issuer,subject:header?.replace('Bearer ','')??'anonymous'})};
const makeApp=()=>{const value=buildApp(options);if(!value.hasRoute({method:'GET',url:'/v1/schools/:schoolId/setup-draft'}))registerSchoolOnboarding(value,options);return value;};
let app:ReturnType<typeof makeApp>;
beforeAll(async()=>{
  expect((await pool.query('SELECT current_database() AS name')).rows[0].name).toBe('drivy_test');
  await pool.query('DROP SCHEMA IF EXISTS drivy CASCADE');await pool.query('DROP TABLE IF EXISTS public.drivy_migrations');
  for(const role of ['drivy_test_migrator','drivy_app','drivy_invitation_mailer'])await pool.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
  await pool.query('GRANT CREATE ON DATABASE drivy_test TO drivy_test_migrator');await pool.query('GRANT USAGE,CREATE ON SCHEMA public TO drivy_test_migrator');
  await pool.query('GRANT drivy_app,drivy_invitation_mailer TO drivy_test_migrator WITH ADMIN OPTION');
  const migration=new Pool({connectionString:url,options:'-c role=drivy_test_migrator'});
  try {await migrate(migration);}finally{await migration.end();}
  app=makeApp();
});
beforeEach(async()=>{
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);
  await pool.query("UPDATE drivy.school SET status='DRAFT' WHERE id=$1",[id.schoolA]);
  await pool.query("UPDATE drivy.membership SET grants=ARRAY['CONFIGURE_CATALOG']::text[] WHERE id=$1",[id.adminMember]);
});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'POST'|'PUT',route:string,body?:Record<string,unknown>,version?:number,subject='demo-admin') {
  return app.inject({method,url:route,headers:{authorization:`Bearer ${subject}`,...(body?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
}
async function getDraft(){const response=await call('GET',base);expect(response.statusCode,response.body).toBe(200);return response.json().data as {version:number;status:string;content:SetupContent};}
const formation=():SetupFormation=>{const template=setupTemplates.formations.find(item=>item.categoryCode==='B')!;return {id:randomUUID(),apply:true,categoryCode:template.categoryCode,label:'Conduite B',templateId:template.id,templateVersion:template.version,competencies:structuredClone(template.competencies),procedureText:template.procedureText,cancellationPolicyText:'Annulation de recette sans données réelles.',sourceUrls:[],durationMinutes:50,priceCents:9300,termsText:'Conditions synthétiques de recette confirmées.',validFrom:'2026-01-01',existingOfferingId:null};};
async function prepared(withFormation=false) {
  const current=await getDraft(),content=current.content;
  content.privacy={noticeText:'Information des personnes : texte synthétique relu pour la recette.',retentionText:'Conservation limitée au test synthétique. Aucune personne réelle.',contactEmail:'privacy@example.invalid',templateId:null,templateVersion:null};
  if(withFormation){content.selectedSections.push('CATALOGUE');content.formations=[formation()];}
  return save(content,current.version);
}
async function save(content:SetupContent,version:number) {
  const body={operationId:randomUUID(),currentStep:'REVIEW',content};
  const response=await call('PUT',base,body,version);expect(response.statusCode,response.body).toBe(200);return response.json().data as {version:number;content:SetupContent};
}
async function reviewed(activate=true) {const response=await call('GET',`${base}/preview?activate=${activate}`);expect(response.statusCode,response.body).toBe(200);return response.json().data;}
async function completion(activate=true) {
  const review=await reviewed(activate);return {version:review.draftVersion,body:{operationId:randomUUID(),expectedSchoolVersion:review.schoolVersion,expectedConfigurationVersion:review.configurationVersion,reviewDigest:review.reviewDigest,reviewAcknowledged:true,activate}};
}
async function counts(){return (await pool.query(`SELECT (SELECT count(*)::int FROM drivy.operation) operations,(SELECT count(*)::int FROM drivy.audit_event) audits,
  (SELECT count(*)::int FROM drivy.school_data_policy WHERE school_id=$1) policies,(SELECT count(*)::int FROM drivy.profile_field_policy WHERE school_id=$1) profile_policies,
  (SELECT count(*)::int FROM drivy.curriculum_version WHERE school_id=$1) curricula,(SELECT count(*)::int FROM drivy.service_product_version WHERE school_id=$1) products`,[id.schoolA])).rows[0];}

it('lit sans créer de brouillon ; réserve contenus et modèles aux ADMIN du bon périmètre',async()=>{
  const before=await counts();expect((await getDraft()).version).toBe(1);expect(await counts()).toEqual(before);
  expect((await pool.query('SELECT draft_content FROM drivy.school_setup WHERE school_id=$1',[id.schoolA])).rows[0].draft_content).toBeNull();
  const templates=(await call('GET',`${base}/templates`)).json().data;
  const proposals=(await call('GET',`/v1/schools/${id.schoolA}/text-proposals`)).json().data;
  const identity=(await getDraft()).content.identity;
  const personalize=(text:string)=>text.replaceAll('[Nom de l’école]',identity.name).replaceAll('[contact données]',identity.contactEmail);
  expect(personalize(templates.privacy.noticeText)).toBe(proposals.dataPolicy.noticeText);expect(templates.privacy.retentionText).toBe(proposals.dataPolicy.retentionText);
  expect(templates.profileFields).toEqual(proposals.profileFields);expect(personalize(templates.commercial.termsText)).toBe(proposals.commercialTerms.termsText);
  expect(templates.commercial.cancellationPolicyText).toBe(proposals.procedure.cancellationPolicyText);
  expect(templates.formations.every((item:{procedureText:string})=>item.procedureText===proposals.procedure.procedureText)).toBe(true);
  expect(templates.privacy.noticeText).not.toContain('Mapbox');expect(await counts()).toEqual(before);
  const mapboxApp=buildApp({...options,mapMatching:{provider:'mapbox',minimumConfidence:0.8}});
  try {const response=await mapboxApp.inject({method:'GET',url:`${base}/templates`,headers:{authorization:'Bearer demo-admin'}});expect(response.statusCode,response.body).toBe(200);expect(response.json().data.privacy.noticeText).toContain('Mapbox');}
  finally {await mapboxApp.close();}
  for(const route of [base,`${base}/templates`,`${base}/next-actions`,`${base}/preview?activate=true`]) {
    expect((await call('GET',route,undefined,undefined,'demo-instructor')).statusCode).toBe(403);
    expect((await call('GET',route,undefined,undefined,'demo-foreign')).statusCode).toBe(403);
  }
  expect((await call('GET',`${base}/preview`)).statusCode).toBe(400);
  expect((await call('GET',`${base}/preview?activate=maybe`)).statusCode).toBe(400);
});

it('sauvegarde partielle durable, sans adoption ; conflit et rejeu conservent la saisie',async()=>{
  const current=await getDraft();current.content.identity.name='';current.content.privacy.noticeText='Texte de travail incomplet';
  const phoneIndex=current.content.profile.fields.findIndex(field=>field.field==='contactPhone');expect(phoneIndex).toBeGreaterThanOrEqual(0);
  current.content.profile.fields[phoneIndex]!.explanation='';
  const incompleteFormation=formation();incompleteFormation.durationMinutes=0;current.content.formations=[incompleteFormation];current.content.selectedSections.push('CATALOGUE');
  const command={operationId:randomUUID(),currentStep:'PRIVACY',content:current.content};
  const first=await call('PUT',base,command,1);expect(first.statusCode,first.body).toBe(200);
  expect((await call('PUT',base,command,1)).json().data).toEqual(first.json().data);
  expect((await call('PUT',base,{...command,operationId:randomUUID()},1)).statusCode).toBe(412);
  expect((await call('PUT',base,{...command,extra:true},2)).statusCode).toBe(400);
  expect((await call('PUT',base,{...command,operationId:randomUUID()},undefined)).statusCode).toBe(428);
  await app.close();app=makeApp();
  expect((await getDraft()).content).toEqual(current.content);
  const review=await reviewed();expect(review.ready).toBe(false);
  expect(review.issues.map((issue:{field:string})=>issue.field)).toEqual(expect.arrayContaining(['privacy.noticeText',`profile.fields.${phoneIndex}.explanation`,'formations.0.durationMinutes']));
  expect(review.issues.filter((issue:{field:string})=>issue.field.startsWith('profile.'))).toEqual([{field:`profile.fields.${phoneIndex}.explanation`,code:'PROFILE_POLICY_RULE_INVALID',message:'Expliquez à l’élève pourquoi cette information est demandée.'}]);
  expect(review.issues).toEqual(expect.arrayContaining([expect.objectContaining({field:'privacy.noticeText',code:'POLICY_TEXT_TOO_SHORT'})]));
  expect((await pool.query('SELECT count(*)::int n FROM drivy.school_data_policy WHERE approved_at IS NOT NULL')).rows[0].n).toBe(0);
});

it('active le minimum sans publier une formation reportée ni fabriquer de prix ou de GPS',async()=>{
  const saved=await prepared();const deferred=formation();deferred.priceCents=null;deferred.apply=false;saved.content.formations=[deferred];saved.content.selectedSections.push('CATALOGUE');await save(saved.content,saved.version);
  const before=await counts(),command=await completion();const response=await call('POST',`${base}/complete`,command.body,command.version);
  expect(response.statusCode,response.body).toBe(200);expect(response.json().data.school.status).toBe('ACTIVE');expect(response.json().data.applied.productIds).toEqual([]);
  const after=await counts();expect(after.products).toBe(before.products);expect(after.curricula).toBe(before.curricula);expect(after.policies).toBe(before.policies+1);expect(after.profile_policies).toBe(before.profile_policies+1);
  expect((await pool.query('SELECT count(*)::int n FROM drivy.recording_choice')).rows[0].n).toBe(0);
  const ready=(await call('GET',`/v1/schools/${id.schoolA}/readiness`)).json().data;expect(ready.capabilities.find((c:{capability:string})=>c.capability==='CAN_PLAN_LESSON').ready).toBe(false);
  expect((await getDraft()).content.formations[0]?.priceCents).toBeNull();
});

it('la publication complète est atomique, idempotente et tarifée à partir d’une seule valeur',async()=>{
  const saved=await prepared(true),before=await counts(),command=await completion();
  const responses=await Promise.all([call('POST',`${base}/complete`,command.body,command.version),call('POST',`${base}/complete`,command.body,command.version)]);
  for(const response of responses)expect(response.statusCode,response.body).toBe(200);
  const result=responses[0]!.json().data;expect(responses[1]!.json().data).toEqual(result);
  const after=await counts();expect(after.operations).toBe(before.operations+1);expect(after.audits).toBe(before.audits+1);expect(after.products).toBe(1);expect(after.curricula).toBe(1);
  expect(result.id).toBe(id.schoolA);expect(result.version).toBe(saved.version+1);expect(result.draft.status).toBe('APPLIED');
  const product=(await pool.query('SELECT unit_price_cents,duration_minutes,terms_version_id FROM drivy.service_product_version WHERE id=$1',[result.applied.productIds[0]])).rows[0];
  const offer=(await pool.query('SELECT default_price_cents,default_duration_minutes FROM drivy.offering_version WHERE id=$1',[result.applied.offeringIds[0]])).rows[0];
  expect(Number(product.unit_price_cents)).toBe(9300);expect(Number(offer.default_price_cents)).toBe(9300);expect(product.duration_minutes).toBe(offer.default_duration_minutes);
  const policy=(await pool.query('SELECT notice_text FROM drivy.school_data_policy WHERE notice_version_id=$1',[result.applied.policyVersionId])).rows[0];expect(policy.notice_text).toBe(saved.content.privacy.noticeText);
  const receipt=await call('GET',`/v1/schools/${id.schoolA}/operations/${command.body.operationId}`);expect(receipt.statusCode,receipt.body).toBe(200);expect(receipt.json().data.commandType).toBe('APPLY_SCHOOL_SETUP_DRAFT');
  expect((await call('POST',`${base}/complete`,{...command.body,operationId:randomUUID()},command.version)).statusCode).toBe(412);
});

it('bloque prix absent, modèle obsolète, champ interdit et placeholders avant toute adoption',async()=>{
  const saved=await prepared(true);saved.content.formations[0]!.priceCents=null;saved.content.formations[0]!.templateVersion='ancienne';saved.content.privacy.retentionText='[à compléter]';
  saved.content.formations[0]!.termsText='Conditions à relire : [à compléter : paiement].';saved.content.formations[0]!.cancellationPolicyText='Annulation : [à compléter : délai].';
  saved.content.profile.fields.push({field:'profilePhotoDocumentId',requirement:'REQUIRED',stage:'JOIN',purposeCode:'PERSONALISATION',explanation:'Une photo.'});await save(saved.content,saved.version);
  const preview=await reviewed();expect(preview.ready).toBe(false);expect(preview.issues.map((i:{code:string})=>i.code)).toEqual(expect.arrayContaining(['SETUP_FIELD_REQUIRED','SETUP_PLACEHOLDER','SETUP_TEMPLATE_CHANGED','PROFILE_POLICY_RULE_INVALID']));
  expect(preview.issues.filter((issue:{code:string})=>issue.code==='SETUP_PLACEHOLDER').map((issue:{field:string})=>issue.field)).toEqual(expect.arrayContaining(['formations.0.termsText','formations.0.cancellationPolicyText']));
  const before=await counts(),command=await completion();expect((await call('POST',`${base}/complete`,command.body,command.version)).statusCode).toBe(409);expect(await counts()).toEqual(before);
});

it('recalcule le grant commercial et les versions après la revue',async()=>{
  const saved=await prepared(true),command=await completion(),before=await counts();
  await pool.query("UPDATE drivy.membership SET grants='{}' WHERE id=$1",[id.adminMember]);
  const denied=await call('POST',`${base}/complete`,command.body,command.version);expect(denied.json().code).toBe('CATALOGUE_ACCESS_REQUIRED');expect(await counts()).toEqual(before);
  await pool.query("UPDATE drivy.membership SET grants=ARRAY['CONFIGURE_CATALOG']::text[] WHERE id=$1",[id.adminMember]);
  saved.content.privacy.noticeText+=' Modification après revue.';await save(saved.content,saved.version);
  expect((await call('POST',`${base}/complete`,command.body,command.version)).statusCode).toBe(412);
  const fresh=await completion();fresh.body.reviewDigest='0'.repeat(64);expect((await call('POST',`${base}/complete`,fresh.body,fresh.version)).json().code).toBe('SETUP_REVIEW_CHANGED');
});

it('annule toutes les écritures sur échec au milieu de la publication et conserve le brouillon',async()=>{
  const saved=await prepared(true),command=await completion(),before=await counts();
  await pool.query("CREATE FUNCTION public.fail_setup_product() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic rollback'; END $$");
  await pool.query('CREATE TRIGGER fail_setup_product BEFORE INSERT ON drivy.service_product_version FOR EACH ROW EXECUTE FUNCTION public.fail_setup_product()');
  try {const response=await call('POST',`${base}/complete`,command.body,command.version);expect(response.statusCode).toBe(503);expect(await counts()).toEqual(before);expect((await getDraft()).version).toBe(saved.version);expect((await pool.query('SELECT status FROM drivy.school WHERE id=$1',[id.schoolA])).rows[0].status).toBe('DRAFT');}
  finally {await pool.query('DROP TRIGGER fail_setup_product ON drivy.service_product_version');await pool.query('DROP FUNCTION public.fail_setup_product()');}
  expect((await call('POST',`${base}/complete`,command.body,command.version)).statusCode).toBe(200);
});

it('ajoute un tarif à une école active sans réadopter les textes ni changer les anciennes références',async()=>{
  await prepared(true);const initial=await completion();const opened=(await call('POST',`${base}/complete`,initial.body,initial.version)).json().data;
  const current=await getDraft(),before=await counts(),item=formation();item.id=randomUUID();item.existingOfferingId=opened.applied.offeringIds[0];item.priceCents=10500;
  current.content.selectedSections=['CATALOGUE'];current.content.formations=[item];const withIgnoredText=await save(current.content,current.version);
  const invalid=await completion(false);expect((await call('POST',`${base}/complete`,invalid.body,invalid.version)).json().code).toBe('SETUP_INHERITED_CANCELLATION');
  expect((await counts()).products).toBe(before.products);
  withIgnoredText.content.formations[0]!.cancellationPolicyText='';await save(withIgnoredText.content,withIgnoredText.version);
  const command=await completion(false),response=await call('POST',`${base}/complete`,command.body,command.version);expect(response.statusCode,response.body).toBe(200);
  const after=await counts();expect(after.policies).toBe(before.policies);expect(after.profile_policies).toBe(before.profile_policies);expect(after.curricula).toBe(before.curricula);expect(after.products).toBe(before.products+1);
  expect(response.json().data.applied.offeringIds).toEqual(opened.applied.offeringIds);expect(response.json().data.applied.policyVersionId).toBeNull();
  expect(Number((await pool.query('SELECT unit_price_cents FROM drivy.service_product_version WHERE id=$1',[opened.applied.productIds[0]])).rows[0].unit_price_cents)).toBe(9300);
  const applied=await getDraft();await save(applied.content,applied.version);
  const review=await reviewed(false);expect(review.ready).toBe(false);expect(review.issues.map((issue:{code:string})=>issue.code)).toContain('SETUP_ITEM_ALREADY_APPLIED');
  const retry=await completion(false);expect((await call('POST',`${base}/complete`,retry.body,retry.version)).json().code).toBe('SETUP_ITEM_ALREADY_APPLIED');
  expect((await counts()).products).toBe(after.products);
});

it('conserve une ancienne date dans le brouillon mais exige un effet immédiat explicitement revu',async()=>{
  const saved=await prepared(true);saved.content.profile.effectiveFrom='2099-01-01T00:00:00Z';const future=await save(saved.content,saved.version);
  expect((await getDraft()).content.profile.effectiveFrom).toBe('2099-01-01T00:00:00Z');
  const before=await counts(),command=await completion(),blocked=await call('POST',`${base}/complete`,command.body,command.version);
  expect(blocked.statusCode,blocked.body).toBe(409);expect(blocked.json().code).toBe('PROFILE_EFFECTIVE_NOW_REQUIRED');expect(await counts()).toEqual(before);
  future.content.profile.effectiveFrom=null;await save(future.content,future.version);
  const immediate=await completion(),result=await call('POST',`${base}/complete`,immediate.body,immediate.version);expect(result.statusCode,result.body).toBe(200);
  const profile=(await pool.query("SELECT status,effective_from<=statement_timestamp() AS current FROM drivy.profile_field_policy WHERE id=$1",[result.json().data.applied.profilePolicyId])).rows[0];
  expect(profile).toEqual({status:'PUBLISHED',current:true});
});

it('annonce les accords GPS rendus caducs et réexige la revue quand cet impact change',async()=>{
  await prepared();const initial=await completion();const first=await call('POST',`${base}/complete`,initial.body,initial.version);expect(first.statusCode,first.body).toBe(200);
  const current=await getDraft();current.content.selectedSections=['PRIVACY'];current.content.privacy.noticeText+=' Nouvelle version synthétique explicitement relue.';
  await save(current.content,current.version);
  const oldReview=await completion(false);
  await pool.query(`INSERT INTO drivy.recording_choice(school_id,version,learner_id,status,notice_version_id,recorded_by,source)
    VALUES($1,1,$2,'ALLOWED',$3,$4,'RECORDED_VERBAL')`,[id.schoolA,id.aliceLearner,first.json().data.applied.policyVersionId,id.instructorMember]);
  const changed=await call('POST',`${base}/complete`,oldReview.body,oldReview.version);expect(changed.statusCode,changed.body).toBe(409);expect(changed.json().code).toBe('SETUP_REVIEW_CHANGED');
  const review=await reviewed(false);expect(review.effects).toHaveLength(1);expect(review.effects[0]).toContain('1 accord(s) GPS');expect(review.effects[0]).toContain('0 trajet(s) en cours');
  const fresh=await completion(false),result=await call('POST',`${base}/complete`,fresh.body,fresh.version);expect(result.statusCode,result.body).toBe(200);
  const choices=await call('GET',`/v1/schools/${id.schoolA}/recording-choices`);expect(choices.json().data.items[0]).toMatchObject({learnerId:id.aliceLearner,status:'ALLOWED',currentNotice:false});
  expect((await pool.query('SELECT count(*)::int n FROM drivy.recording_choice WHERE school_id=$1',[id.schoolA])).rows[0].n).toBe(1);
});

it('les prochaines actions séparent configuration, dossier et première leçon puis disparaissent après usage',async()=>{
  const initial=await call('GET',`${base}/next-actions`);expect(initial.statusCode,initial.body).toBe(200);
  expect(initial.json().data.planningReady).toBe(false);expect(initial.json().data.actions.map((a:{code:string})=>a.code)).toContain('POLICY_REVIEW_REQUIRED');
  await prepared(true);const command=await completion();const result=(await call('POST',`${base}/complete`,command.body,command.version)).json().data;
  const availability=await call('POST',`/v1/schools/${id.schoolA}/availability-rules`,{operationId:randomUUID(),instructorMembershipId:id.instructorMember,weekdays:[1,2,3,4,5,6,7],localStart:'08:00',localEnd:'18:00',validFrom:'2020-01-01',validUntil:null});expect(availability.statusCode,availability.body).toBe(201);
  const profile=await call('GET',`${base}/next-actions`);expect(profile.json().data.planningReady).toBe(true);expect(profile.json().data.actions[0]).toMatchObject({code:'PROFILE_ACTION_REQUIRED',section:'eleves',query:{selection:id.aliceLearner}});
  await pool.query("UPDATE drivy.learner_profile SET first_name='Alice',last_name='Exemple' WHERE id=$1",[id.aliceLearner]);
  const trainingId=randomUUID();await pool.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,$5,'ACTIVE','2026-01-01')",[trainingId,id.schoolA,id.aliceLearner,result.applied.offeringIds[0],`setup-${(await getDraft()).content.formations[0]!.id}`]);
  expect((await call('GET',`${base}/next-actions`)).json().data.actions[0].code).toBe('INSTRUCTOR_NOT_ASSIGNED');
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,'2020-01-01')",[randomUUID(),id.schoolA,trainingId,id.instructorMember]);
  expect((await call('GET',`${base}/next-actions`)).json().data.actions[0]).toMatchObject({code:'PLAN_FIRST_LESSON',label:'Planifier dans l’app Drivy',section:'eleves',query:{selection:id.aliceLearner}});
  const policyId=(await pool.query('SELECT policy_version_id FROM drivy.offering_version WHERE id=$1',[result.applied.offeringIds[0]])).rows[0].policy_version_id;
  await pool.query(`INSERT INTO drivy.lesson(school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,status,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
    VALUES($1,$2,$3,$4,$5,'2026-01-01T09:00:00Z','2026-01-01T09:50:00Z','Europe/Zurich','Lieu synthétique','CANCELLED',9300,0,$6,'{}')`,[id.schoolA,trainingId,id.aliceLearner,id.alice,id.instructorMember,policyId]);
  expect((await call('GET',`${base}/next-actions`)).json().data.actions).toEqual([]);
  await pool.query('DELETE FROM drivy.availability_rule WHERE school_id=$1',[id.schoolA]);
  const changed=(await call('GET',`${base}/next-actions`)).json().data;expect(changed.planningReady).toBe(false);expect(changed.actions.map((a:{code:string})=>a.code)).toEqual(['AVAILABILITY_REQUIRED']);
});

async function firstLearnerWithTraining(otherCategory=false) {
  const saved=await prepared(true);
  if(otherCategory) {
    saved.content.formations.push({...formation(),categoryCode:'A',label:'Conduite A',templateId:null,templateVersion:null});
    await save(saved.content,saved.version);
  }
  const command=await completion(),response=await call('POST',`${base}/complete`,command.body,command.version);expect(response.statusCode,response.body).toBe(200);
  const applied=response.json().data.applied;
  await pool.query("UPDATE drivy.learner_profile SET first_name='Alice',last_name='Exemple' WHERE id=$1",[id.aliceLearner]);
  const training=await call('POST',`/v1/schools/${id.schoolA}/trainings`,{operationId:randomUUID(),learnerId:id.aliceLearner,offeringId:applied.offeringIds[0],assignCreator:false});
  expect(training.statusCode,training.body).toBe(201);
  const assigned=await call('POST',`/v1/schools/${id.schoolA}/trainings/${training.json().data.id}/assignments`,{operationId:randomUUID(),instructorMembershipId:id.instructorMember,validFrom:'2020-01-01T00:00:00Z',validUntil:null});
  expect(assigned.statusCode,assigned.body).toBe(201);
  return {applied,content:saved.content};
}
async function addAvailability(instructorMembershipId:string) {
  const response=await call('POST',`/v1/schools/${id.schoolA}/availability-rules`,{operationId:randomUUID(),instructorMembershipId,weekdays:[1,2,3,4,5,6,7],localStart:'08:00',localEnd:'18:00',validFrom:'2020-01-01',validUntil:null});
  expect(response.statusCode,response.body).toBe(201);
}

it('oriente vers les disponibilités du moniteur affecté même si un autre moniteur est déjà disponible',async()=>{
  await firstLearnerWithTraining();await addAvailability(id.otherInstructorMember);
  const before=(await call('GET',`${base}/next-actions`)).json().data;
  expect(before.planningReady).toBe(true);
  expect(before.actions).toEqual([{code:'AVAILABILITY_REQUIRED',label:'Définir les disponibilités du moniteur affecté',section:'disponibilites',query:{instructor:id.instructorMember}}]);
  await addAvailability(id.instructorMember);
  expect((await call('GET',`${base}/next-actions`)).json().data.actions[0].code).toBe('PLAN_FIRST_LESSON');
});

it('oriente le tarif manquant vers la formation exacte de l’élève quand un autre permis est déjà tarifé',async()=>{
  const {applied,content}=await firstLearnerWithTraining(true);await addAvailability(id.instructorMember);
  const disabled=await call('POST',`/v1/schools/${id.schoolA}/service-products`,{operationId:randomUUID(),productKey:`setup-${content.formations[0]!.id}`,
    label:'Ancien tarif B',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9300,
    validFrom:'2026-01-01',validUntil:null,termsVersionId:applied.termsIds[0],enabled:false});
  expect(disabled.statusCode,disabled.body).toBe(201);
  const next=(await call('GET',`${base}/next-actions`)).json().data;
  expect(next.planningReady).toBe(true);
  expect(next.actions).toEqual([{code:'COMMERCIAL_SETUP_REQUIRED',label:'Ajouter un tarif pour la formation de l’élève',section:'apercu',query:{from:'formations',selection:applied.offeringIds[0]}}]);
});
