import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {expectContract,freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,slot,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'],school:Awaited<ReturnType<typeof prepareSchool>>;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);});
afterAll(async()=>{await app?.close();await pool?.end();});
const audits=async(operationId:string)=>(await pool.query('SELECT count(*)::int AS n FROM drivy.audit_event WHERE operation_id=$1',[operationId])).rows[0].n;
const today=new Date().toISOString().slice(0,10);

describe('conditions commerciales et prestations (extension commercial-terms, AP100/AP101)',()=>{
 it('grant CONFIGURE_CATALOG explicite, versions immuables, brouillons limités et rejeu',async()=>{
  const terms={operationId:randomUUID(),label:'Conditions',termsText:'Texte synthétique',validFrom:today,validUntil:null,approved:false,approvalReason:'Brouillon'};
  expect((await call('POST','/commercial-terms',terms)).statusCode).toBe(403);// moniteur sans grant
  expect((await call('POST','/commercial-terms',terms,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST','/commercial-terms',{...terms,validUntil:'2000-01-01'},null,'demo-admin')).json().code).toBe('INVALID_INTERVAL');
  const draft=await call('POST','/commercial-terms',terms,null,'demo-admin');expect(draft.statusCode,draft.body).toBe(201);
  expect(draft.json().data).toMatchObject({version:1,approved:false,approvedByMembershipId:null,approvedAt:null});
  expect((await call('POST','/commercial-terms',terms,null,'demo-admin')).json().data).toEqual(draft.json().data);expect(await audits(terms.operationId)).toBe(1);
  expect((await call('POST','/commercial-terms',{...terms,label:'Autre'},null,'demo-admin')).json().code).toBe('IDEMPOTENCY_MISMATCH');
  const product={operationId:randomUUID(),productKey:'lesson-50',label:'Leçon',type:'INDIVIDUAL_LESSON',categoryCode:'B',siteId:null,durationMinutes:50,unitLabel:'leçon',unitPriceCents:9000,validFrom:today,validUntil:null,termsVersionId:draft.json().data.id,enabled:true};
  expect((await call('POST','/service-products',product,null,'demo-admin')).json().code).toBe('COMMERCIAL_TERMS_NOT_APPROVED');
  expect((await call('POST','/service-products',{...product,operationId:randomUUID(),siteId:randomUUID()},null,'demo-admin')).json().code).toBe('SITE_SETUP_REQUIRED');
  expect((await call('POST','/service-products',{...product,operationId:randomUUID(),durationMinutes:null},null,'demo-admin')).json().code).toBe('INVALID_SERVICE_PRODUCT');
  // Lecture : brouillon invisible sans grant, version approuvée visible par tout membre.
  expect((await call('GET','/commercial-terms')).json().data.items).toEqual([]);
  expect((await call('GET','/commercial-terms',undefined,null,'demo-admin')).json().data.items).toHaveLength(1);
  expect((await call('GET',`/v1/schools/${id.schoolB}/commercial-terms`,undefined,null,'demo-alice')).statusCode).toBe(403);
 });
});

describe('ouvertures et fermetures (AP31–AP37)',()=>{
 it('moniteur sur soi, ADMIN sur tous, If-Match, retrait bloqué par un rendez-vous',async()=>{
  const body={operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,weekdays:[1,2,3],localStart:'08:00',localEnd:'12:00',validFrom:today,validUntil:null};
  expect((await call('POST','/availability-rules',body)).statusCode).toBe(403);// moniteur pour un autre
  expect((await call('POST','/availability-rules',body,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST','/availability-rules',{...body,localEnd:'07:00'},null,'demo-admin')).json().code).toBe('INVALID_INTERVAL');
  const created=await call('POST','/availability-rules',body,null,'demo-other-instructor');expect(created.statusCode,created.body).toBe(201);
  await expectContract('AvailabilityRuleEnvelope',created.json());const rule=created.json().data;expect(rule).toMatchObject({version:1,weekdays:[1,2,3],localStart:'08:00',localEnd:'12:00',validUntil:null});
  expect((await call('GET','/availability-rules',undefined,null,'demo-alice')).statusCode).toBe(403);
  await expectContract('AvailabilityRulePageEnvelope',(await call('GET','/availability-rules',undefined,null,'demo-admin')).json());
  expect((await call('GET','/availability-rules')).json().data.items.map((r:{id:string})=>r.id)).not.toContain(rule.id);
  expect((await call('GET','/availability-rules',undefined,null,'demo-admin')).json().data.items.map((r:{id:string})=>r.id)).toContain(rule.id);
  const update={...body,operationId:randomUUID(),weekdays:[4,5]};
  expect((await call('PUT',`/availability-rules/${rule.id}`,update,null,'demo-other-instructor')).statusCode).toBe(428);
  expect((await call('PUT',`/availability-rules/${rule.id}`,update,2,'demo-other-instructor')).json().code).toBe('VERSION_CONFLICT');
  expect((await call('PUT',`/availability-rules/${rule.id}`,{...update,instructorMembershipId:id.instructorMember},1,'demo-admin')).json().code).toBe('INVALID_REQUEST');
  const updated=await call('PUT',`/availability-rules/${rule.id}`,update,1,'demo-other-instructor');expect(updated.statusCode,updated.body).toBe(200);expect(updated.json().data).toMatchObject({version:2,weekdays:[4,5]});
  const removal={operationId:randomUUID(),reason:'Plage de recette retirée'};
  const removed=await call('POST',`/availability-rules/${rule.id}/remove`,removal,2,'demo-other-instructor');expect(removed.statusCode,removed.body).toBe(200);expect(removed.json().data).toEqual({operationId:removal.operationId,accepted:true});
  expect((await call('POST',`/availability-rules/${rule.id}/remove`,removal,2,'demo-other-instructor')).json().data.accepted).toBe(true);
  expect((await call('POST',`/availability-rules/${rule.id}/remove`,{...removal,operationId:randomUUID()},3,'demo-other-instructor')).statusCode).toBe(404);
  const closure={operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,startsAt:new Date(Date.now()+86_400_000).toISOString(),endsAt:new Date(Date.now()+90_000_000).toISOString(),reason:null};
  expect((await call('POST','/closures',{...closure,endsAt:closure.startsAt},null,'demo-other-instructor')).json().code).toBe('INVALID_INTERVAL');
  const c=await call('POST','/closures',closure,null,'demo-other-instructor');expect(c.statusCode,c.body).toBe(201);
  await expectContract('ClosureEnvelope',c.json());await expectContract('ClosurePageEnvelope',(await call('GET','/closures',undefined,null,'demo-admin')).json());
  expect((await call('GET',`/closures?instructorMembershipId=${id.otherInstructorMember}`,undefined,null,'demo-admin')).json().data.items.map((x:{id:string})=>x.id)).toContain(c.json().data.id);
  expect((await call('POST',`/closures/${c.json().data.id}/remove`,{operationId:randomUUID(),reason:'Retrait'},1,'demo-other-instructor')).statusCode).toBe(200);
  expect((await call('GET',`/operations/${closure.operationId}`,undefined,null,'demo-other-instructor')).json().data.resourceType).toBe('Closure');
 });
});

describe('leçons (AP39–AP43)',()=>{
 it('création réelle, conflits d’occupation, fermeture, déplacement, annulation, droits et rejeu',async()=>{
  const commercial=await prepareCommercial(call);
  const body=lessonBody(commercial,school.policy,2);
  expect((await call('POST','/lessons',body,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('POST','/lessons',{...body,instructorMembershipId:id.otherInstructorMember},null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),timeZone:'UTC'})).json().code).toBe('INVALID_TIME_ZONE');
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(-1)})).json().code).toBe('INVALID_INTERVAL');
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),agreedPriceCents:1})).json().code).toBe('PRICE_OVERRIDE_REQUIRED');
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),policyVersionId:randomUUID()})).json().code).toBe('SCHOOL_POLICY_CHANGED');
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(2,22)})).json().code).toMatch(/SLOT_UNAVAILABLE|INVALID_INTERVAL/);
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),commercialSelection:{...body.commercialSelection,mode:'ENTITLEMENT',entitlementLotId:randomUUID()}})).json().code).toBe('ENTITLEMENT_NOT_READY');
  const [first,replay]=await Promise.all([call('POST','/lessons',body),call('POST','/lessons',body)]);
  expect(first.statusCode,first.body).toBe(201);expect(replay.json().data).toEqual(first.json().data);expect(await audits(body.operationId)).toBe(1);
  const lesson=first.json().data;await expectContract('LessonEnvelope',first.json());
  expect(lesson).toMatchObject({status:'PLANNED',version:1,trainingId:id.aliceTraining,learnerId:id.aliceLearner,priceCentsSnapshot:9000,bufferMinutesSnapshot:10,permitWarning:true,publicationVersion:0,currentPublishedRevisionId:null,commercialRevisionVersion:1,captureSummary:{hasCapture:false,syncState:null,publicationState:'NONE'}});
  expect(first.headers.etag).toBe('"1"');
  expect((await call('POST','/lessons',{...body,meetingPoint:'Autre lieu'})).json().code).toBe('IDEMPOTENCY_MISMATCH');
  // Même élève ou tampon du moniteur : exclusion PostgreSQL, sans effet partiel.
  const overlap=await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(2,8,30)});expect(overlap.json().code).toBe('SLOT_CONFLICT');expect(overlap.statusCode).toBe(409);
  const buffer=await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(2,8,55)});expect(buffer.json().code).toBe('SLOT_CONFLICT');
  // Lectures : élève sur soi, autre élève et autre école exclus.
  expect((await call('GET',`/lessons/${lesson.id}`,undefined,null,'demo-alice')).statusCode).toBe(200);
  expect((await call('GET',`/lessons/${lesson.id}`,undefined,null,'demo-bob')).statusCode).toBe(404);
  expect((await call('GET',`/lessons/${lesson.id}`,undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('GET',`/v1/schools/${id.schoolB}/lessons/${lesson.id}`,undefined,null,'demo-foreign')).statusCode).toBe(404);
  expect((await call('GET','/lessons',undefined,null,'demo-bob')).json().data.items).toEqual([]);
  expect((await call('GET','/lessons',undefined,null,'demo-alice')).json().data.items.map((l:{id:string})=>l.id)).toEqual([lesson.id]);
  expect((await call('GET',`/lessons?from=${encodeURIComponent(slot(3).plannedStart)}&to=${encodeURIComponent(slot(2).plannedStart)}`)).json().code).toBe('INVALID_INTERVAL');
  // Fermeture sur un rendez-vous existant : refusée.
  expect((await call('POST','/closures',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,startsAt:lesson.plannedStart,endsAt:lesson.plannedEnd,reason:null})).json().code).toBe('EXISTING_BOOKINGS');
  // Déplacement : If-Match, accord explicite, ancien créneau libéré.
  const move={operationId:randomUUID(),...slot(3),timeZone:'Europe/Zurich',meetingPoint:'Place (synthétique)',instructorMembershipId:id.instructorMember,agreementConfirmed:true,reason:null};
  expect((await call('POST',`/lessons/${lesson.id}/move`,move)).statusCode).toBe(428);
  expect((await call('POST',`/lessons/${lesson.id}/move`,move,9)).json().code).toBe('VERSION_CONFLICT');
  expect((await call('POST',`/lessons/${lesson.id}/move`,{...move,operationId:randomUUID(),agreementConfirmed:false},1)).statusCode).toBe(400);
  const longer=slot(3);longer.plannedEnd=new Date(Date.parse(longer.plannedStart)+100*60_000).toISOString();
  expect((await call('POST',`/lessons/${lesson.id}/move`,{...move,operationId:randomUUID(),...longer},1)).json().code).toBe('LESSON_COMMERCIAL_CHANGE_REQUIRED');
  const moved=await call('POST',`/lessons/${lesson.id}/move`,move,1);expect(moved.statusCode,moved.body).toBe(200);expect(moved.json().data).toMatchObject({version:2,meetingPoint:'Place (synthétique)',plannedStart:move.plannedStart});
  const reuse=await call('POST','/lessons',{...body,operationId:randomUUID()});expect(reuse.statusCode,reuse.body).toBe(201);
  // Fermeture future ailleurs : bloque une nouvelle planification sur ce créneau.
  const closure=await call('POST','/closures',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,startsAt:slot(4,6).plannedStart,endsAt:slot(4,10).plannedStart,reason:'Formation'});expect(closure.statusCode,closure.body).toBe(201);
  expect((await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(4)})).json().code).toBe('SLOT_UNAVAILABLE');
  // Annulation : motif canonique, If-Match, résultat définitif.
  const cancel={operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',comment:'Demande synthétique'};
  expect((await call('POST',`/lessons/${lesson.id}/cancel`,cancel,1)).json().code).toBe('VERSION_CONFLICT');
  const cancelled=await call('POST',`/lessons/${lesson.id}/cancel`,cancel,2,'demo-admin');expect(cancelled.statusCode,cancelled.body).toBe(200);expect(cancelled.json().data).toMatchObject({status:'CANCELLED',version:3});
  expect((await call('POST',`/lessons/${lesson.id}/cancel`,cancel,2,'demo-admin')).json().data).toEqual(cancelled.json().data);
  expect((await call('POST',`/lessons/${lesson.id}/cancel`,{...cancel,operationId:randomUUID()},3,'demo-admin')).json().code).toBe('LESSON_CLOSED');
  expect((await call('POST',`/lessons/${lesson.id}/move`,{...move,operationId:randomUUID()},3)).json().code).toBe('LESSON_CLOSED');
  const again=await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(3)});expect(again.statusCode,again.body).toBe(201);
  const events=(await pool.query('SELECT event_type FROM drivy.lesson_event_outbox WHERE lesson_id=$1 ORDER BY lesson_version',[lesson.id])).rows.map(r=>r.event_type);
  expect(events).toEqual(['LessonCreated','LessonMoved','LessonCancelled']);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'CREATE_LESSON',resourceType:'Lesson',resourceId:lesson.id});
  expect((await call('GET',`/operations/${body.operationId}`,undefined,null,'demo-alice')).statusCode).toBe(404);
  // Affectation retirée : le moniteur perd la leçon, l'administration la conserve.
  const kept=again.json().data;
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{
   expect((await call('GET',`/lessons/${kept.id}`)).statusCode).toBe(404);
   expect((await call('POST',`/lessons/${kept.id}/cancel`,{...cancel,operationId:randomUUID()},kept.version)).statusCode).toBe(404);
   expect((await call('POST','/lessons',{...body,operationId:randomUUID(),...slot(5)})).statusCode).toBe(404);
   expect((await call('GET',`/operations/${body.operationId}`)).statusCode).toBe(404);
   expect((await call('GET',`/lessons/${kept.id}`,undefined,null,'demo-admin')).statusCode).toBe(200);
  }finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  // Pagination par curseur lié à la personne.
  const page=await call('GET','/lessons?limit=1');await expectContract('LessonPageEnvelope',page.json());expect(page.json().data.items).toHaveLength(1);
  const next=await call('GET',`/lessons?limit=1&cursor=${encodeURIComponent(page.json().data.nextCursor)}`);expect(next.statusCode).toBe(200);expect(next.json().data.items[0].id).not.toBe(page.json().data.items[0].id);
  expect((await call('GET',`/lessons?limit=1&cursor=${encodeURIComponent(page.json().data.nextCursor)}`,undefined,null,'demo-admin')).statusCode).toBe(400);
 });
 it('AP177 PLAN_LESSON reflète les prérequis de planification',async()=>{
  const ready=await call('GET',`/learners/${id.aliceLearner}/action-readiness?action=PLAN_LESSON&resourceId=${id.aliceTraining}`,undefined,null,'demo-admin');
  expect(ready.statusCode,ready.body).toBe(200);expect(ready.json().data).toMatchObject({ready:true,blockers:[]});
  // Formation de Bob sans moniteur affecté : blocage nommé, sans fuite de valeurs protégées.
  const bob=await call('GET',`/learners/${id.bobLearner}/action-readiness?action=PLAN_LESSON&resourceId=${id.bobTraining}`,undefined,null,'demo-admin');
  expect(bob.statusCode,bob.body).toBe(200);expect(bob.json().data.ready).toBe(false);expect(bob.json().data.blockers.map((b:{code:string})=>b.code)).toContain('INSTRUCTOR_NOT_ASSIGNED');
  expect((await call('GET',`/learners/${id.aliceLearner}/action-readiness?action=PLAN_LESSON&resourceId=${id.aliceTraining}`,undefined,null,'demo-alice')).json().data.blockers.map((b:{code:string})=>b.code)).toContain('PLANNING_ACCESS_REQUIRED');
 });
});
