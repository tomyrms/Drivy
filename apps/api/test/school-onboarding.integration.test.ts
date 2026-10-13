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
  for(const route of [base,`${base}/templates`,`${base}/next-actions`,`${base}/preview?activate=true`]) {
    expect((await call('GET',route,undefined,undefined,'demo-instructor')).statusCode).toBe(403);
    expect((await call('GET',route,undefined,undefined,'demo-foreign')).statusCode).toBe(403);
  }
  expect((await call('GET',`${base}/preview`)).statusCode).toBe(400);
  expect((await call('GET',`${base}/preview?activate=maybe`)).statusCode).toBe(400);
});

it('sauvegarde partielle durable, sans adoption ; conflit et rejeu conservent la saisie',async()=>{
  const current=await getDraft();current.content.identity.name='';current.content.privacy.noticeText='Texte de travail incomplet';
  current.content.profile.fields[0]!.explanation='';
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
  expect(review.issues.map((issue:{field:string})=>issue.field)).toEqual(expect.arrayContaining(['profile.fields','formations.0.durationMinutes']));
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
  saved.content.profile.fields.push({field:'profilePhotoDocumentId',requirement:'REQUIRED',stage:'JOIN',purposeCode:'PERSONALISATION',explanation:'Une photo.'});await save(saved.content,saved.version);
  const preview=await reviewed();expect(preview.ready).toBe(false);expect(preview.issues.map((i:{code:string})=>i.code)).toEqual(expect.arrayContaining(['SETUP_FIELD_REQUIRED','SETUP_PLACEHOLDER','SETUP_TEMPLATE_CHANGED','PROFILE_POLICY_RULE_INVALID']));
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
  current.content.selectedSections=['CATALOGUE'];current.content.formations=[item];await save(current.content,current.version);
  const command=await completion(false),response=await call('POST',`${base}/complete`,command.body,command.version);expect(response.statusCode,response.body).toBe(200);
  const after=await counts();expect(after.policies).toBe(before.policies);expect(after.profile_policies).toBe(before.profile_policies);expect(after.curricula).toBe(before.curricula);expect(after.products).toBe(before.products+1);
  expect(response.json().data.applied.offeringIds).toEqual(opened.applied.offeringIds);expect(response.json().data.applied.policyVersionId).toBeNull();
  expect(Number((await pool.query('SELECT unit_price_cents FROM drivy.service_product_version WHERE id=$1',[opened.applied.productIds[0]])).rows[0].unit_price_cents)).toBe(9300);
});

it('une politique future ne donne pas une préparation de planification actuelle',async()=>{
  const saved=await prepared(true);saved.content.profile.effectiveFrom='2099-01-01T00:00:00Z';await save(saved.content,saved.version);
  const command=await completion(),result=await call('POST',`${base}/complete`,command.body,command.version);expect(result.statusCode,result.body).toBe(200);
  const ready=(await call('GET',`/v1/schools/${id.schoolA}/readiness`)).json().data;
  expect(ready.capabilities.find((c:{capability:string})=>c.capability==='CAN_PLAN_LESSON').blockers.map((b:{code:string})=>b.code)).toContain('PROFILE_POLICY_NOT_READY');
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
  expect((await call('GET',`${base}/next-actions`)).json().data.actions[0]).toMatchObject({code:'PLAN_FIRST_LESSON',section:'agenda',query:{learner:id.aliceLearner}});
  const policyId=(await pool.query('SELECT policy_version_id FROM drivy.offering_version WHERE id=$1',[result.applied.offeringIds[0]])).rows[0].policy_version_id;
  await pool.query(`INSERT INTO drivy.lesson(school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,status,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
    VALUES($1,$2,$3,$4,$5,'2026-01-01T09:00:00Z','2026-01-01T09:50:00Z','Europe/Zurich','Lieu synthétique','CANCELLED',9300,0,$6,'{}')`,[id.schoolA,trainingId,id.aliceLearner,id.alice,id.instructorMember,policyId]);
  expect((await call('GET',`${base}/next-actions`)).json().data.actions).toEqual([]);
  await pool.query('DELETE FROM drivy.availability_rule WHERE school_id=$1',[id.schoolA]);
  const changed=(await call('GET',`${base}/next-actions`)).json().data;expect(changed.planningReady).toBe(false);expect(changed.actions.map((a:{code:string})=>a.code)).toEqual(['AVAILABILITY_REQUIRED']);
});
