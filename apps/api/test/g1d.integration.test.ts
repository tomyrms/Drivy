import {readFile} from 'node:fs/promises';
import {createDecipheriv,randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {beforeAll,beforeEach,afterAll,describe,it,expect} from 'vitest';
import {Pool} from 'pg';
import {createLocalJWKSet,exportJWK,generateKeyPair,SignJWT} from 'jose';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {parse} from 'yaml';
import {buildApp} from '../src/app.js';
import {createTokenVerifier} from '../src/auth.js';
import {migrate} from '../scripts/migrations.js';
import {fixtureIds as id,seedFixtures} from '../scripts/fixtures.js';

const url=process.env.TEST_DATABASE_URL;
if(!url || new URL(url).pathname!=='/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool=new Pool({connectionString:url,max:10,application_name:'drivy-g1d-tests'});
const issuer='https://identity.test.invalid';const school=`/v1/schools/${id.schoolA}`;
const profilePath=`${school}/learners/${id.aliceLearner}/administrative-profile`;
let app:ReturnType<typeof buildApp>;let keys:Awaited<ReturnType<typeof generateKeyPair>>;
const validators=new Map<string,ReturnType<Ajv2020['compile']>>();
beforeAll(async()=>{
  await migrate(pool);keys=await generateKeyPair('RS256');const key=await exportJWK(keys.publicKey);
  app=buildApp({pool,cursorSecret:'secret-test-32-caracteres-minimum',invitationMail:{webURL:'http://127.0.0.1:3002/app/invitation',encryptionKey:'a1'.repeat(32),host:'127.0.0.1',port:1025,secure:false,requireTLS:false,from:'drivy@example.invalid'},verifyToken:createTokenVerifier({OIDC_ISSUER:issuer,OIDC_AUDIENCE:'drivy-api',OIDC_JWKS_URL:`${issuer}/jwks`},createLocalJWKSet({keys:[{...key,kid:'g1d',alg:'RS256'}]}))});
  const document=parse(await readFile(new URL('../../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml',import.meta.url),'utf8')) as {components:object};
  const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema({$id:'g1d',components:document.components});
  for(const name of ['ProfileFieldPolicyEnvelopeV3','ProfileFieldPolicyPageV3EnvelopeV3','AdministrativeProfileEnvelopeV3','OnboardingProgressEnvelopeV3','LearnerActionReadinessEnvelopeV3','LearnerEnvelope','OperationResultEnvelope']) validators.set(name,ajv.compile({$ref:`g1d#/components/schemas/${name}`}));
});
beforeEach(async()=>{await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');await seedFixtures(pool,issuer);});
afterAll(async()=>{await app?.close();await pool.end();});
async function call(method:'GET'|'PUT'|'POST'|'PATCH',path:string,body?:Record<string,unknown>,version?:number,subject='demo-admin',claims:Record<string,unknown>={}) {
  const jwt=await new SignJWT(claims).setProtectedHeader({alg:'RS256',kid:'g1d'}).setSubject(subject).setIssuer(issuer).setAudience('drivy-api').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  return app.inject({method,url:path,headers:{authorization:`Bearer ${jwt}`,...(body?{'idempotency-key':String(body.operationId)}:{}),...(version?{'if-match':`"${version}"`}:{})},...(body?{payload:body}:{})});
}
function conforms(name:string,value:unknown) {const validate=validators.get(name)!;expect(validate(value),JSON.stringify(validate.errors)).toBe(true);}
const names=()=>['firstName','lastName'].map(field=>({field,requirement:'REQUIRED',stage:'JOIN',purposeCode:'IDENTIFICATION',explanation:'Identifier le dossier scolaire.'}));
const optional=(field:string,purposeCode='LESSON_CONTACT')=>({field,requirement:'OPTIONAL',stage:'OPTIONAL',purposeCode,explanation:'Information facultative expliquée.'});
const noticeBody=()=>({operationId:randomUUID(),noticeText:'Notice de test du profil.',retentionText:'Conservation limitée aux tests.',contactEmail:'privacy@example.invalid',reviewAcknowledged:true});
async function notice() {const response=await call('PUT',`${school}/data-policy`,noticeBody(),1);expect(response.statusCode,response.body).toBe(200);return response.json().data.noticeVersionId as string;}
async function draft(rules=names(),effectiveFrom='2026-01-01T00:00:00Z',noticeId?:string) {
  const noticeVersionId=noticeId ?? await notice();const version=(await call('GET',school)).json().data.version;
  const response=await call('POST',`${school}/profile-field-policies`,{operationId:randomUUID(),fields:rules,effectiveFrom,noticeVersionId,impactAcknowledged:true},version);
  expect(response.statusCode,response.body).toBe(201);conforms('ProfileFieldPolicyEnvelopeV3',response.json());return response.json().data as {id:string;version:number;noticeVersionId:string};
}
async function publish(rules=[...names(),optional('contactEmail'),optional('contactPhone'),optional('birthDate','COURSE_ELIGIBILITY'),optional('postalAddress','POSTAL_CONTACT'),optional('profilePhotoDocumentId','PERSONALISATION')]) {
  const policy=await draft(rules);const response=await call('POST',`${school}/profile-field-policies/${policy.id}/publish`,{operationId:randomUUID()},1);
  expect(response.statusCode,response.body).toBe(200);conforms('ProfileFieldPolicyEnvelopeV3',response.json());return policy.id;
}
async function counts() {return (await pool.query(`SELECT (SELECT count(*)::int FROM drivy.operation) operations,(SELECT count(*)::int FROM drivy.audit_event) audits,
  (SELECT count(*)::int FROM drivy.profile_field_policy) policies,(SELECT count(*)::int FROM drivy.onboarding_progress) progresses`)).rows[0];}
async function waitForLock() {
  const deadline=Date.now()+4000;
  while(Date.now()<deadline) {if((await pool.query("SELECT 1 FROM pg_stat_activity WHERE application_name='drivy-g1d-tests' AND wait_event_type='Lock' AND query LIKE '%FROM drivy.school WHERE id=$1 FOR UPDATE%'")).rowCount) return;await delay(10);}
  throw new Error('La commande ne s’est pas présentée au verrou scolaire attendu.');
}

describe('G1D1 · politique versionnée et profil minimal',()=>{
  it('GET ne crée ni politique ni accueil, sans noms dérivés du nom public',async()=>{
    const before=await counts();expect((await call('GET',profilePath)).json().code).toBe('PROFILE_POLICY_NOT_READY');
    expect((await call('GET',`${school}/my-onboarding?kind=STUDENT`,undefined,undefined,'demo-alice')).json().code).toBe('PROFILE_POLICY_NOT_READY');
    const page=await call('GET',`${school}/profile-field-policies`);conforms('ProfileFieldPolicyPageV3EnvelopeV3',page.json());expect(page.json().data.items).toEqual([]);
    expect(await counts()).toEqual(before);expect((await pool.query('SELECT first_name,last_name FROM drivy.learner_profile WHERE id=$1',[id.aliceLearner])).rows[0]).toEqual({first_name:null,last_name:null});
  });
  it('UUID de notice persistant par révision, sans adoption automatique, et lecture de l’ancienne notice',async()=>{
    const initial=(await call('GET',`${school}/data-policy`)).json().data;expect(initial.status).toBe('DRAFT');expect(initial.noticeVersionId).toMatch(/^[a-f0-9-]{36}$/);
    const body=noticeBody();const response=await call('PUT',`${school}/data-policy`,body,1);const first=response.json().data;
    const second=(await call('PUT',`${school}/data-policy`,noticeBody(),2)).json().data;expect(new Set([initial.noticeVersionId,first.noticeVersionId,second.noticeVersionId]).size).toBe(3);
    const read=await call('GET',`${school}/data-policy?noticeVersionId=${first.noticeVersionId}`,undefined,undefined,'demo-alice');expect(read.json().data).toEqual(first);
    expect((await call('GET',`${school}/data-policy?noticeVersionId=${initial.noticeVersionId}`,undefined,undefined,'demo-alice')).statusCode).toBe(404);
    // Une preuve historique dépourvue de l’extension reçoit l’UUID réel sans réécriture de sa réponse stockée.
    await pool.query("UPDATE drivy.operation SET response_data=response_data-'noticeVersionId' WHERE operation_id=$1",[body.operationId]);
    const replay=await call('PUT',`${school}/data-policy`,body,1);expect(replay.json().data).toEqual(first);
    expect((await pool.query("SELECT response_data ? 'noticeVersionId' AS present FROM drivy.operation WHERE operation_id=$1",[body.operationId])).rows[0].present).toBe(false);
  });
  it('publication explicite : école et politique versionnées, initialisation vide et champs canoniques',async()=>{
    const policy=await draft();expect((await call('GET',school)).json().data).toMatchObject({version:3,configurationVersion:2});expect((await counts()).progresses).toBe(0);
    expect((await call('GET',`${school}/profile-field-policies`,undefined,undefined,'demo-alice')).json().data.items).toEqual([]);
    const response=await call('POST',`${school}/profile-field-policies/${policy.id}/publish`,{operationId:randomUUID()},1);expect(response.statusCode,response.body).toBe(200);
    expect(response.json().data).toMatchObject({version:2,status:'PUBLISHED',approvedByMembershipId:id.adminMember});expect((await call('GET',school)).json().data).toMatchObject({version:4,configurationVersion:3});
    expect((await pool.query('SELECT settings FROM drivy.school_settings_version WHERE school_id=$1 AND version=3',[id.schoolA])).rows[0].settings.profileFieldPolicyVersionId).toBe(policy.id);
    const profile=await call('GET',profilePath);conforms('AdministrativeProfileEnvelopeV3',profile.json());expect(profile.json().data).toMatchObject({firstName:null,lastName:null,version:1,policyVersionId:policy.id,enteredByMembershipId:id.aliceMember});
    expect(profile.json().data.id).not.toBe(id.aliceLearner);const before=await counts();expect(before.progresses).toBe(5);
    for(const [kind,subject] of [['STUDENT','demo-alice'],['STAFF','demo-admin']]) {const r=await call('GET',`${school}/my-onboarding?kind=${kind}`,undefined,undefined,subject);conforms('OnboardingProgressEnvelopeV3',r.json());expect(r.json().data).toMatchObject({status:'IN_PROGRESS',currentStep:'IDENTITY',skippedOptionalSteps:[]});}
    expect(await counts()).toEqual(before);
  });
  it('refuse notice non adoptée/étrangère, règles dupliquées, photo requise et rôles non ADMIN',async()=>{
    const noticeId=(await call('GET',`${school}/data-policy`)).json().data.noticeVersionId;
    const make=(noticeVersionId:string,fields=names())=>({operationId:randomUUID(),noticeVersionId,fields,effectiveFrom:'2026-01-01T00:00:00Z',impactAcknowledged:true});
    expect((await call('POST',`${school}/profile-field-policies`,make(noticeId),1)).json().code).toBe('POLICY_REVIEW_REQUIRED');
    const approved=await notice();
    for(const rules of [[...names(),names()[0]!],[...names(),{...optional('profilePhotoDocumentId','PERSONALISATION'),requirement:'REQUIRED',stage:'JOIN'}],names().slice(1)]) {
      const r=await call('POST',`${school}/profile-field-policies`,make(approved,rules),2);expect([400,422]).toContain(r.statusCode);
    }
    expect((await call('POST',`${school}/profile-field-policies`,make(approved),2,'demo-instructor')).statusCode).toBe(403);
    expect((await counts()).policies).toBe(0);
  });
  it('concurrence création et publication : un seul effet, rejeu exact et conflit de contenu',async()=>{
    const noticeId=await notice();const body={operationId:randomUUID(),noticeVersionId:noticeId,fields:names(),effectiveFrom:'2026-01-01T00:00:00Z',impactAcknowledged:true};
    const created=await Promise.all([call('POST',`${school}/profile-field-policies`,body,2),call('POST',`${school}/profile-field-policies`,body,2)]);
    expect(created.map(r=>r.statusCode)).toEqual([201,201]);expect(created[0]!.json().data).toEqual(created[1]!.json().data);expect((await counts()).policies).toBe(1);
    expect((await call('POST',`${school}/profile-field-policies`,{...body,effectiveFrom:'2026-02-01T00:00:00Z'},2)).json().code).toBe('IDEMPOTENCY_MISMATCH');
    const path=`${school}/profile-field-policies/${created[0]!.json().data.id}/publish`;
    const published=await Promise.all([call('POST',path,{operationId:randomUUID()},1),call('POST',path,{operationId:randomUUID()},1)]);expect(published.map(r=>r.statusCode).sort()).toEqual([200,412]);
  });
  it('politique future sans effet anticipé et conflit de date sans publication partielle',async()=>{
    const current=await publish();const noticeId=(await call('GET',`${school}/data-policy`)).json().data.noticeVersionId;
    const future=await draft(names(),'2099-01-01T00:00:00Z',noticeId);expect((await call('POST',`${school}/profile-field-policies/${future.id}/publish`,{operationId:randomUUID()},1)).statusCode).toBe(200);
    expect((await call('GET',profilePath)).json().data.policyVersionId).toBe(current);
    const collision=await draft(names(),'2026-01-01T00:00:00Z',noticeId);expect((await call('POST',`${school}/profile-field-policies/${collision.id}/publish`,{operationId:randomUUID()},1)).json().code).toBe('PROFILE_POLICY_DATE_CONFLICT');
    expect((await pool.query('SELECT status FROM drivy.profile_field_policy WHERE id=$1',[collision.id])).rows[0].status).toBe('DRAFT');
    const member=await call('GET',`${school}/profile-field-policies`,undefined,undefined,'demo-alice');expect(member.json().data.items.map((p:{id:string})=>p.id)).toEqual([current]);
    expect((await call('GET',`${school}/profile-field-policies`)).json().data.items.length).toBe(3);
  });
  it('AP176 partiel et AP16 partagent la version sans transformer le nom public en identité',async()=>{
    const policyVersionId=await publish();const response=await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,firstName:'Élodie',lastName:'Exemple'},1,'demo-alice');
    expect(response.statusCode,response.body).toBe(200);conforms('AdministrativeProfileEnvelopeV3',response.json());expect(response.json().data).toMatchObject({version:2,entrySource:'SELF'});
    const old=`${school}/learners/${id.aliceLearner}`;const contact=await call('PATCH',old,{operationId:randomUUID(),contactPhone:'+41 21 000 00 00'},2,'demo-instructor');
    expect(contact.statusCode,contact.body).toBe(200);conforms('LearnerEnvelope',contact.json());expect(contact.json().data.version).toBe(3);
    const read=(await call('GET',profilePath)).json().data;expect(read).toMatchObject({firstName:'Élodie',lastName:'Exemple',version:3,entrySource:'STAFF_ASSISTED',enteredByMembershipId:id.instructorMember});
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:null},2)).json().code).toBe('VERSION_CONFLICT');
    expect((await call('PATCH',old,{operationId:randomUUID(),displayName:'Nom public distinct'},3)).statusCode).toBe(200);
    expect((await call('GET',profilePath)).json().data.firstName).toBe('Élodie');
  });
  it('permissions : élève propre, ADMIN, moniteur affecté coordonnées seulement, omission des champs protégés',async()=>{
    const policyVersionId=await publish();const body={operationId:randomUUID(),policyVersionId,firstName:'Alice',birthDate:'2000-01-01'};
    expect((await call('PATCH',profilePath,body,1)).statusCode).toBe(200);
    const instructor=await call('GET',profilePath,undefined,undefined,'demo-instructor');conforms('AdministrativeProfileEnvelopeV3',instructor.json());expect(instructor.json().data.firstName).toBe('Alice');expect(instructor.json().data).not.toHaveProperty('birthDate');expect(instructor.json().data).not.toHaveProperty('postalAddress');
    for(const subject of ['demo-bob','demo-other-instructor','demo-foreign']) expect((await call('GET',profilePath,undefined,undefined,subject)).statusCode).toBe(subject==='demo-foreign'?403:404);
    const before=await counts();const forbidden=await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:'021',birthDate:null},2,'demo-instructor');expect(forbidden.json().code).toBe('PROFILE_FIELD_FORBIDDEN');expect(await counts()).toEqual(before);
    expect((await call('GET',profilePath)).json().data.contactPhone).toBeNull();
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:'021'},2,'demo-alice')).statusCode).toBe(200);
  });
  it('refus explicites : photos non déposées, dates futures, champs inconnus, archives et versions',async()=>{
    const policyVersionId=await publish();const before=await counts();
    for(const [change,code] of [[{profilePhotoDocumentId:randomUUID()},'DOCUMENT_NOT_READY'],[{birthDate:'2999-01-01'},'INVALID_BIRTH_DATE'],[{arbitraryMedicalField:'x'},'INVALID_REQUEST']] as const)
      expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,...change},1)).json().code).toBe(code);
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:'021'})).statusCode).toBe(428);
    await pool.query('UPDATE drivy.learner_profile SET archived_at=now() WHERE id=$1',[id.aliceLearner]);
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:'021'},1)).json().code).toBe('LEARNER_ARCHIVED');expect(await counts()).toEqual(before);
  });
  it('pas de troncature silencieuse des noms Unicode',async()=>{
    const policyVersionId=await publish();const name='𐐀'.repeat(150);const accepted=await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,firstName:name},1);
    expect(accepted.statusCode,accepted.body).toBe(200);expect(accepted.json().data.firstName).toBe(name);
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,lastName:name+'a'},2)).statusCode).toBe(400);
  });
  it('readiness autorise l’entrée minimale, photo ignorée, uniquement les champs requis au stade visé',async()=>{
    await publish([...names(),{field:'contactPhone',requirement:'REQUIRED',stage:'BEFORE_LESSON',purposeCode:'LESSON_CONTACT',explanation:'Contacter avant la leçon.'},optional('profilePhotoDocumentId','PERSONALISATION')]);
    const path=`${school}/learners/${id.aliceLearner}/action-readiness`;
    const enter=await call('GET',`${path}?action=ENTER`,undefined,undefined,'demo-alice');conforms('LearnerActionReadinessEnvelopeV3',enter.json());expect(enter.json().data).toMatchObject({ready:true,blockers:[]});
    const plan=await call('GET',`${path}?action=PLAN_LESSON&resourceId=${id.aliceTraining}`);conforms('LearnerActionReadinessEnvelopeV3',plan.json());expect(plan.json().data.ready).toBe(false);
    expect(plan.json().data.blockers.map((b:{field:string|null})=>b.field)).toEqual(['firstName','lastName','contactPhone',null]);
    expect((await call('GET',`${path}?action=PLAN_LESSON&resourceId=${id.bobTraining}`)).statusCode).toBe(404);
  });
  it('onboarding propre : noms, revue explicite, facultatifs réellement passables, aucun consentement inventé',async()=>{
    const policyVersionId=await publish();const path=`${school}/my-onboarding`;
    const complete=()=>({operationId:randomUUID(),kind:'STUDENT',policyVersionId});
    expect((await call('POST',`${path}/complete`,complete(),1,'demo-alice')).json().code).toBe('ONBOARDING_NOT_READY');
    expect((await call('GET',`${path}?kind=STAFF`,undefined,undefined,'demo-alice')).statusCode).toBe(403);
    expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,firstName:'Alice',lastName:'Exemple'},1,'demo-alice')).statusCode).toBe(200);
    const saved=await call('PATCH',path,{operationId:randomUUID(),kind:'STUDENT',currentStep:'REVIEW',skippedOptionalSteps:['PHOTO','NOTIFICATIONS','DEVICE'],policyVersionId},1,'demo-alice');expect(saved.statusCode,saved.body).toBe(200);conforms('OnboardingProgressEnvelopeV3',saved.json());expect(saved.json().data.status).toBe('READY');
    const body=complete();const done=await call('POST',`${path}/complete`,body,2,'demo-alice');expect(done.statusCode,done.body).toBe(200);expect(done.json().data.status).toBe('COMPLETED');
    expect((await call('POST',`${path}/complete`,body,2,'demo-alice')).json().data).toEqual(done.json().data);
    expect((await pool.query('SELECT onboarding FROM drivy.membership WHERE id=$1',[id.aliceMember])).rows[0].onboarding).not.toHaveProperty('gpsConsent');
    expect((await pool.query('SELECT count(*)::int n FROM drivy.training')).rows[0].n).toBe(3);
  });
  it('conflit de politique relisible sans écraser les données déjà saisies',async()=>{
    const previous=await publish();expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId:previous,firstName:'Alice'},1)).statusCode).toBe(200);
    const next=await draft(names(),'2026-02-01T00:00:00Z',(await call('GET',`${school}/data-policy`)).json().data.noticeVersionId);
    expect((await call('POST',`${school}/profile-field-policies/${next.id}/publish`,{operationId:randomUUID()},1)).statusCode).toBe(200);
    const rejected=await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId:previous,lastName:'Exemple'},2);expect(rejected.json().code).toBe('PROFILE_POLICY_CHANGED');
    expect((await call('GET',profilePath)).json().data).toMatchObject({policyVersionId:next.id,firstName:'Alice',lastName:null,version:2});
    expect((await call('GET',`${school}/profile-field-policies`,undefined,undefined,'demo-alice')).json().data.items.map((p:{id:string})=>p.id)).toEqual([next.id]);
  });
  it('deux mutations de profil concurrentes : version gagnante unique, preuve et audit atomiques',async()=>{
    const policyVersionId=await publish();const before=await counts();const updates=await Promise.all(['111','222'].map(contactPhone=>call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone},1,'demo-alice')));
    expect(updates.map(r=>r.statusCode).sort()).toEqual([200,412]);expect(await counts()).toEqual({...before,operations:before.operations+1,audits:before.audits+1});expect((await call('GET',profilePath)).json().data.version).toBe(2);
  });
  it('rejeu après perte d’affectation refusé, AP72 suit les droits actuels',async()=>{
    const policyVersionId=await publish();const body={operationId:randomUUID(),policyVersionId,contactPhone:'021'};
    const first=await call('PATCH',profilePath,body,1,'demo-instructor');expect(first.statusCode,first.body).toBe(200);
    const proofPath=`${school}/operations/${body.operationId}`;const proof=await call('GET',proofPath,undefined,undefined,'demo-instructor');expect(proof.statusCode,proof.body).toBe(200);conforms('OperationResultEnvelope',proof.json());expect(proof.json().data.resourceType).toBe('AdministrativeProfile');
    await pool.query('DELETE FROM drivy.instructor_assignment WHERE id=$1',[id.assignment]);
    expect((await call('PATCH',profilePath,body,1,'demo-instructor')).statusCode).toBe(404);expect((await call('GET',proofPath,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
  });
  it('attente du verrou école : une affectation révoquée est relue avant toute écriture',async()=>{
    const policyVersionId=await publish();const before=await counts();const locker=await pool.connect();await locker.query('BEGIN');await locker.query('SELECT id FROM drivy.school WHERE id=$1 FOR UPDATE',[id.schoolA]);
    const pending=call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,contactPhone:'021'},1,'demo-instructor');
    try {await waitForLock();await locker.query('DELETE FROM drivy.instructor_assignment WHERE id=$1',[id.assignment]);await locker.query('COMMIT');const response=await pending;expect(response.statusCode,response.body).toBe(404);}
    finally {await locker.query('ROLLBACK');locker.release();}
    expect(await counts()).toEqual(before);expect((await call('GET',profilePath)).json().data.version).toBe(1);
  });
  it('échec d’audit : rollback du profil, de la version et de la preuve',async()=>{
    const policyVersionId=await publish();const before=await counts();
    await pool.query("CREATE FUNCTION drivy.fail_g1d_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Échec de recette'; END $$");
    await pool.query('CREATE TRIGGER fail_g1d_audit BEFORE INSERT ON drivy.audit_event FOR EACH ROW EXECUTE FUNCTION drivy.fail_g1d_audit()');
    try {expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,firstName:'Alice'},1)).statusCode).toBe(503);}
    finally {await pool.query('DROP TRIGGER fail_g1d_audit ON drivy.audit_event');await pool.query('DROP FUNCTION drivy.fail_g1d_audit()');}
    expect(await counts()).toEqual(before);expect((await call('GET',profilePath)).json().data).toMatchObject({version:1,firstName:null});
  });
  it('RLS SQL : un moniteur ne peut pas écrire un nom protégé, ni modifier une politique publiée',async()=>{
    await publish();const db=await pool.connect();
    try {await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",[id.schoolA,id.instructor,id.instructorMember]);
      await expect(db.query('UPDATE drivy.learner_profile SET first_name=$2,entered_by_membership_id=$3 WHERE id=$1',[id.aliceLearner,'Interdit',id.instructorMember])).rejects.toMatchObject({code:'42501'});await db.query('ROLLBACK');
      await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",[id.schoolA,id.admin,id.adminMember]);
      await expect(db.query("UPDATE drivy.profile_field_policy SET fields='[]'::jsonb")).rejects.toMatchObject({code:'42501'});
    } finally {await db.query('ROLLBACK');db.release();}
  });
  it('RLS forcée sur chaque table et fonctions internes non exécutables par PUBLIC',async()=>{
    const tables=await pool.query("SELECT relrowsecurity,relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relkind='r'");expect(tables.rowCount).toBe(17);expect(tables.rows.every(row=>row.relrowsecurity && row.relforcerowsecurity)).toBe(true);
    const functions=await pool.query("SELECT prosecdef,proconfig,has_function_privilege('public',p.oid,'EXECUTE') exposed FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='drivy' AND proname IN('profile_access','initialize_profile_context','profile_target_person','profile_fields_writable')");
    expect(functions.rowCount).toBe(4);expect(functions.rows.every(row=>row.prosecdef && !row.exposed && row.proconfig.includes('search_path=pg_catalog, drivy'))).toBe(true);
  });
  it('rejeu ADMIN devenu moniteur : réponse limitée aux champs encore lisibles',async()=>{
    const policyVersionId=await publish();await pool.query("UPDATE drivy.learner_profile SET birth_date='2000-01-01' WHERE id=$1",[id.aliceLearner]);
    const body={operationId:randomUUID(),policyVersionId,contactPhone:'021'};const response=await call('PATCH',profilePath,body,1);expect(response.statusCode,response.body).toBe(200);expect(response.json().data.birthDate).toBe('2000-01-01');
    await pool.query("UPDATE drivy.membership SET roles=ARRAY['INSTRUCTOR']::text[],access_epoch=access_epoch+1 WHERE id=$1",[id.adminMember]);
    await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,'2026-01-01')",[randomUUID(),id.schoolA,id.aliceTraining,id.adminMember]);
    const replay=await call('PATCH',profilePath,body,1);expect(replay.statusCode,replay.body).toBe(200);expect(replay.json().data).not.toHaveProperty('birthDate');expect(replay.json().data.contactPhone).toBe('021');
    expect((await call('GET',`${school}/operations/${body.operationId}`)).statusCode).toBe(200);
  });
  it('une nouvelle politique ne recommence pas un accueil déjà terminé et encore adéquat',async()=>{
    const policyVersionId=await publish();expect((await call('PATCH',profilePath,{operationId:randomUUID(),policyVersionId,firstName:'Alice',lastName:'Exemple'},1,'demo-alice')).statusCode).toBe(200);
    const path=`${school}/my-onboarding`;expect((await call('PATCH',path,{operationId:randomUUID(),kind:'STUDENT',currentStep:'REVIEW',policyVersionId},1,'demo-alice')).statusCode).toBe(200);
    expect((await call('POST',`${path}/complete`,{operationId:randomUUID(),kind:'STUDENT',policyVersionId},2,'demo-alice')).json().data.status).toBe('COMPLETED');
    const next=await draft([...names(),{field:'contactPhone',requirement:'REQUIRED',stage:'BEFORE_LESSON',purposeCode:'LESSON_CONTACT',explanation:'Contact avant une prochaine leçon.'}],'2026-02-01T00:00:00Z',(await call('GET',`${school}/data-policy`)).json().data.noticeVersionId);
    expect((await call('POST',`${school}/profile-field-policies/${next.id}/publish`,{operationId:randomUUID()},1)).statusCode).toBe(200);
    expect((await call('GET',`${path}?kind=STUDENT`,undefined,undefined,'demo-alice')).json().data).toMatchObject({status:'COMPLETED',version:3,policyVersionId:next.id,pendingActions:[]});
  });
  it('publication exclusivement future : aucune politique applicable prématurée',async()=>{
    const policy=await draft(names(),'2099-01-01T00:00:00Z');expect((await call('POST',`${school}/profile-field-policies/${policy.id}/publish`,{operationId:randomUUID()},1)).statusCode).toBe(200);
    expect((await call('GET',profilePath)).json().code).toBe('PROFILE_POLICY_NOT_READY');expect((await call('GET',`${school}/my-onboarding?kind=STUDENT`,undefined,undefined,'demo-alice')).json().code).toBe('PROFILE_POLICY_NOT_READY');
  });
  it('nouvelle acceptation G1C après publication : accueil canonique minimal, aucun prénom déduit',async()=>{
    const policyVersionId=await publish();const created=await call('POST',`${school}/invitations`,{operationId:randomUUID(),email:'entrant@example.invalid',roles:['LEARNER']});expect(created.statusCode,created.body).toBe(201);
    const mail=(await pool.query('SELECT id,payload FROM drivy.invitation_mail WHERE invitation_id=$1',[created.json().data.id])).rows[0] as {id:string;payload:Buffer};
    const cipher=createDecipheriv('aes-256-gcm',Buffer.from('a1'.repeat(32),'hex'),mail.payload.subarray(0,12));cipher.setAAD(Buffer.from(mail.id));cipher.setAuthTag(mail.payload.subarray(12,28));
    const token=(JSON.parse(Buffer.concat([cipher.update(mail.payload.subarray(28)),cipher.final()]).toString()) as {token:string}).token;
    const accepted=await call('POST','/v1/invitations/accept',{operationId:randomUUID(),token},undefined,'nouveau-g1d',{email:'entrant@example.invalid',email_verified:true});expect(accepted.statusCode,accepted.body).toBe(201);
    const onboarding=await call('GET',`${school}/my-onboarding?kind=STUDENT`,undefined,undefined,'nouveau-g1d');expect(onboarding.statusCode,onboarding.body).toBe(200);conforms('OnboardingProgressEnvelopeV3',onboarding.json());expect(onboarding.json().data).toMatchObject({policyVersionId,currentStep:'IDENTITY',status:'IN_PROGRESS'});
    const rows=await pool.query('SELECT l.id,l.first_name,l.last_name,l.administrative_policy_id FROM drivy.learner_profile l JOIN drivy.identity_link i ON i.person_id=l.person_id WHERE i.subject=$1',['nouveau-g1d']);
    expect(rows.rows[0]).toMatchObject({first_name:null,last_name:null,administrative_policy_id:policyVersionId});expect((await call('GET',`${school}/learners/${rows.rows[0].id}/administrative-profile`,undefined,undefined,'nouveau-g1d')).statusCode).toBe(200);
    expect((await pool.query('SELECT count(*)::int n FROM drivy.training')).rows[0].n).toBe(3);
  });
  it('rollback de publication restaure aussi les initialisations de profils et d’accueils',async()=>{
    const policy=await draft();const before=await counts();await pool.query("CREATE FUNCTION drivy.fail_g1d_publish() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Échec de recette'; END $$");
    await pool.query('CREATE TRIGGER fail_g1d_publish BEFORE INSERT ON drivy.audit_event FOR EACH ROW EXECUTE FUNCTION drivy.fail_g1d_publish()');
    try {expect((await call('POST',`${school}/profile-field-policies/${policy.id}/publish`,{operationId:randomUUID()},1)).statusCode).toBe(503);}
    finally {await pool.query('DROP TRIGGER fail_g1d_publish ON drivy.audit_event');await pool.query('DROP FUNCTION drivy.fail_g1d_publish()');}
    expect(await counts()).toEqual(before);expect((await pool.query('SELECT administrative_policy_id FROM drivy.learner_profile WHERE id=$1',[id.aliceLearner])).rows[0].administrative_policy_id).toBeNull();
    expect((await pool.query('SELECT status,version FROM drivy.profile_field_policy WHERE id=$1',[policy.id])).rows[0]).toEqual({status:'DRAFT',version:1});
  });
});
