import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToPast,slot,id,type Call} from './support/harness.js';

/** #52 : l'élève demande un déplacement ou une annulation, le personnel répond ; la leçon ne bouge qu'à la réponse. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let validateState:ReturnType<Ajv2020['compile']>,validateInbox:ReturnType<Ajv2020['compile']>;
let nextDay=90;
beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);
 const contract=JSON.parse(await readFile(new URL('../contracts/lesson-change-requests.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 validateState=ajv.compile({$ref:`${contract.$id}#/$defs/StateEnvelope`});validateInbox=ajv.compile({$ref:`${contract.$id}#/$defs/InboxEnvelope`});
});
const conforms=(validate:ReturnType<Ajv2020['compile']>,body:unknown)=>{expect(validate(body),JSON.stringify(validate.errors)).toBe(true);};
afterAll(async()=>{await app?.close();await pool?.end();});
async function plan(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,nextDay++));expect(r.statusCode,r.body).toBe(201);return r.json().data;}
const alice='demo-alice',staff='demo-instructor';
const ask=(lessonId:string,kind:'RESCHEDULE'|'CANCEL',note='',operationId=randomUUID())=>call('POST',`/lessons/${lessonId}/change-requests`,{operationId,kind,note},null,alice);
const state=async(lessonId:string,subject=alice)=>(await call('GET',`/lessons/${lessonId}/change-requests`,undefined,null,subject)).json().data;
const lessonRow=async(lessonId:string)=>(await pool.query('SELECT status,version,planned_start FROM drivy.lesson WHERE id=$1',[lessonId])).rows[0];
const activeReservations=async(lessonId:string)=>(await pool.query('SELECT count(*)::int AS n FROM drivy.reservation WHERE lesson_id=$1 AND active',[lessonId])).rows[0].n;

describe('demande de l’élève',()=>{
 it('une demande d’annulation est enregistrée sans toucher la leçon, rejouable et unique par leçon',async()=>{
  const lesson=await plan(),operationId=randomUUID();
  const created=await ask(lesson.id,'CANCEL','Je suis malade',operationId);expect(created.statusCode,created.body).toBe(201);
  conforms(validateState,created.json());
  const data=created.json().data;
  expect(data.lessonId).toBe(lesson.id);
  expect(data.requests).toHaveLength(1);
  expect(data.requests[0]).toMatchObject({kind:'CANCEL',status:'PENDING',note:'Je suis malade',mine:true,version:1,resolvedAt:null});
  expect(data.conditions).toMatchObject({canRequest:false,blockedReason:'REQUEST_PENDING'});
  // Rien n'a bougé : même version, même créneau, même occupation.
  expect(await lessonRow(lesson.id)).toMatchObject({status:'PLANNED',version:lesson.version});
  expect(await activeReservations(lesson.id)).toBe(2);
  // Même opération : même réponse, aucune seconde ligne.
  expect((await ask(lesson.id,'CANCEL','Je suis malade',operationId)).json().data.requests).toHaveLength(1);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.lesson_change_request WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(1);
  // Autre opération pendant l'attente : refusée sans doublon.
  const second=await ask(lesson.id,'RESCHEDULE','Plutôt jeudi');expect(second.statusCode).toBe(409);expect(second.json().code).toBe('LESSON_CHANGE_REQUEST_PENDING');
  // Le reçu reste lisible par son auteur.
  expect((await call('GET',`/operations/${operationId}`,undefined,null,alice)).json().data).toMatchObject({commandType:'CREATE_LESSON_CHANGE_REQUEST',resourceType:'LessonChangeRequest'});
 });

 it('un déplacement exige des disponibilités ou une proposition',async()=>{
  const lesson=await plan();
  expect((await ask(lesson.id,'RESCHEDULE','')).statusCode).toBe(400);
  expect((await ask(lesson.id,'RESCHEDULE','   ')).statusCode).toBe(400);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.lesson_change_request WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(0);
  expect((await ask(lesson.id,'RESCHEDULE','Mercredi après 16 h')).statusCode).toBe(201);
 });

 it('seul l’élève de la leçon demande ; le personnel passe par le déplacement et l’annulation',async()=>{
  const lesson=await plan();
  const byStaff=await call('POST',`/lessons/${lesson.id}/change-requests`,{operationId:randomUUID(),kind:'CANCEL',note:''},null,staff);
  expect(byStaff.statusCode).toBe(403);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.lesson_change_request WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(0);
 });

 it('relit le délai de la procédure de la leçon sans rien supposer quand l’école n’en fixe pas',async()=>{
  const lesson=await plan();
  expect((await state(lesson.id)).conditions).toMatchObject({cancellationHours:null,deadlineAt:null,late:null,lateAction:null,canRequest:true,blockedReason:null});
  await pool.query(`UPDATE drivy.school_policy_version SET cancellation_rules='{"cancellationHours":24,"lateAction":"CONTACT"}'::jsonb WHERE id=$1`,[school.policy]);
  try{
   const conditions=(await state(lesson.id)).conditions;
   expect(conditions).toMatchObject({cancellationHours:24,lateAction:'CONTACT',late:false,policyVersionId:school.policy});
   expect(Date.parse(conditions.deadlineAt)).toBe(Date.parse(lesson.plannedStart)-24*3_600_000);
   // La demande fige le délai et son état au moment où elle est faite.
   const created=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
   expect(created).toMatchObject({late:false,cancellationHours:24,policyVersionId:school.policy});
   // Une leçon proche dépasse le délai : la demande reste possible et se dit hors délai, sans frais ni refus automatique.
   const near=await plan();await pool.query("UPDATE drivy.lesson SET planned_start=now()+interval '3 hours',planned_end=now()+interval '4 hours' WHERE id=$1",[near.id]);
   expect((await state(near.id)).conditions).toMatchObject({late:true,canRequest:true});
   expect((await ask(near.id,'CANCEL')).json().data.requests[0]).toMatchObject({late:true,status:'PENDING'});
   // Changer la procédure ensuite ne réécrit pas la demande déjà faite.
   await pool.query(`UPDATE drivy.school_policy_version SET cancellation_rules='{"cancellationHours":1,"lateAction":"NO_FEE"}'::jsonb WHERE id=$1`,[school.policy]);
   expect((await state(lesson.id)).requests[0]).toMatchObject({cancellationHours:24,late:false});
  }finally{await pool.query('UPDATE drivy.school_policy_version SET cancellation_rules=NULL WHERE id=$1',[school.policy]);}
 });

 it('refuse une demande sur une leçon commencée, passée ou déjà annulée',async()=>{
  const past=await plan();await moveToPast(pool,past.id);
  expect((await ask(past.id,'CANCEL')).json().code).toBe('LESSON_IN_PAST');
  expect((await state(past.id)).conditions).toMatchObject({canRequest:false,blockedReason:'LESSON_IN_PAST'});
  const started=await plan();await pool.query('UPDATE drivy.lesson SET actual_start=now() WHERE id=$1',[started.id]);
  expect((await ask(started.id,'CANCEL')).json().code).toBe('LESSON_STARTED');
  const cancelled=await plan();expect((await call('POST',`/lessons/${cancelled.id}/cancel`,{operationId:randomUUID(),reasonCode:'SCHOOL_CLOSURE'},cancelled.version)).statusCode).toBe(200);
  expect((await ask(cancelled.id,'CANCEL')).json().code).toBe('LESSON_CLOSED');
 });
});

describe('retrait par l’élève',()=>{
 it('retire la demande en attente, une seule fois, et permet d’en refaire une',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'RESCHEDULE','Lundi matin')).json().data.requests[0];
  const operationId=randomUUID();
  const withdrawn=await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId},request.version,alice);
  expect(withdrawn.statusCode,withdrawn.body).toBe(200);
  expect(withdrawn.json().data.requests[0]).toMatchObject({id:request.id,status:'WITHDRAWN',version:2});
  expect(withdrawn.json().data.conditions).toMatchObject({canRequest:true});
  expect(await lessonRow(lesson.id)).toMatchObject({status:'PLANNED',version:lesson.version});
  // Rejeu identique : même réponse. Nouvelle opération sur la demande close : refus propre.
  expect((await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId},request.version,alice)).json().data.requests[0].status).toBe('WITHDRAWN');
  const again=await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId:randomUUID()},2,alice);
  expect(again.statusCode).toBe(409);expect(again.json().code).toBe('LESSON_CHANGE_REQUEST_CLOSED');
  const stale=await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId:randomUUID()},1,alice);
  expect(stale.statusCode).toBe(412);
  expect((await ask(lesson.id,'CANCEL')).statusCode).toBe(201);
 });

 it('ne laisse ni le personnel ni un autre compte retirer à la place de l’élève',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
  const byStaff=await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId:randomUUID()},request.version,staff);
  expect(byStaff.statusCode).toBe(403);
  expect((await pool.query('SELECT status FROM drivy.lesson_change_request WHERE id=$1',[request.id])).rows[0].status).toBe('PENDING');
 });
});

describe('réponse du personnel',()=>{
 it('la boîte du personnel liste les demandes en attente avec l’élève et le créneau, jamais à un élève',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'RESCHEDULE','Mardi 17 h')).json().data.requests[0];
  const inbox=await call('GET','/lesson-change-requests',undefined,null,staff);expect(inbox.statusCode,inbox.body).toBe(200);
  conforms(validateInbox,inbox.json());
  const item=inbox.json().data.items.find((entry:{request:{id:string}})=>entry.request.id===request.id);
  expect(item).toBeDefined();
  expect(item.request).toMatchObject({kind:'RESCHEDULE',note:'Mardi 17 h',mine:false});
  expect(item.lesson).toMatchObject({id:lesson.id,plannedStart:lesson.plannedStart,version:lesson.version,instructorMembershipId:id.instructorMember});
  expect(item.lesson.learnerDisplayName).toBeTypeOf('string');
  expect((await call('GET','/lesson-change-requests',undefined,null,'demo-admin')).json().data.items.some((entry:{request:{id:string}})=>entry.request.id===request.id)).toBe(true);
  expect((await call('GET','/lesson-change-requests',undefined,null,alice)).statusCode).toBe(403);
 });

 it('refuser garde la leçon et rend le motif lisible par l’élève',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'RESCHEDULE','Mercredi')).json().data.requests[0];
  const refused=await call('POST',`/lesson-change-requests/${request.id}/refuse`,{operationId:randomUUID(),note:'Ce créneau est déjà pris'},request.version,staff);
  expect(refused.statusCode,refused.body).toBe(200);
  expect(refused.json().data.requests[0]).toMatchObject({status:'REFUSED',resolutionNote:'Ce créneau est déjà pris',version:2});
  expect((await state(lesson.id)).requests[0]).toMatchObject({status:'REFUSED',resolutionNote:'Ce créneau est déjà pris'});
  expect(await lessonRow(lesson.id)).toMatchObject({status:'PLANNED',version:lesson.version});
  expect(await activeReservations(lesson.id)).toBe(2);
  // Un élève ne répond pas à sa propre demande.
  const own=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
  expect((await call('POST',`/lesson-change-requests/${own.id}/refuse`,{operationId:randomUUID()},own.version,alice)).statusCode).toBe(403);
 });

 it('accepter une annulation passe par l’annulation existante, libère les occupations une fois et clôt la demande',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'CANCEL','Contretemps')).json().data.requests[0];
  // Une demande de déplacement ne peut pas servir à annuler.
  const other=await plan(),otherRequest=(await ask(other.id,'RESCHEDULE','Jeudi')).json().data.requests[0];
  const wrong=await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',changeRequestId:otherRequest.id},lesson.version);
  expect(wrong.statusCode).toBe(404);
  const mismatch=await call('POST',`/lessons/${other.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',changeRequestId:otherRequest.id},other.version);
  expect(mismatch.statusCode).toBe(422);expect(mismatch.json().code).toBe('LESSON_CHANGE_REQUEST_KIND');
  const accepted=await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',changeRequestId:request.id},lesson.version);
  expect(accepted.statusCode,accepted.body).toBe(200);
  expect(await lessonRow(lesson.id)).toMatchObject({status:'CANCELLED'});
  expect(await activeReservations(lesson.id)).toBe(0);
  expect((await pool.query('SELECT status,resolved_by_membership_id FROM drivy.lesson_change_request WHERE id=$1',[request.id])).rows[0]).toMatchObject({status:'ACCEPTED',resolved_by_membership_id:id.instructorMember});
  // La demande close ne peut plus être refusée.
  const late=await call('POST',`/lesson-change-requests/${request.id}/refuse`,{operationId:randomUUID()},request.version+1,staff);
  expect(late.statusCode).toBe(409);expect(late.json().code).toBe('LESSON_CHANGE_REQUEST_CLOSED');
 });

 it('accepter un déplacement passe par le déplacement existant ; un déplacement sans demande ferme les demandes de déplacement seulement',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'RESCHEDULE','Plutôt le matin')).json().data.requests[0];
  const target=slot(nextDay++,9);
  const move={operationId:randomUUID(),...target,timeZone:'Europe/Zurich',meetingPoint:lesson.meetingPoint,instructorMembershipId:id.instructorMember,agreementConfirmed:true,changeRequestId:request.id};
  const moved=await call('POST',`/lessons/${lesson.id}/move`,move,lesson.version);expect(moved.statusCode,moved.body).toBe(200);
  expect(new Date((await lessonRow(lesson.id)).planned_start).toISOString()).toBe(target.plannedStart);
  expect((await pool.query('SELECT status FROM drivy.lesson_change_request WHERE id=$1',[request.id])).rows[0].status).toBe('ACCEPTED');
  // Déplacement par le personnel sans désigner la demande : la demande de déplacement devient caduque, celle d'annulation survit.
  const second=await plan(),moveRequest=(await ask(second.id,'RESCHEDULE','Samedi')).json().data.requests[0];
  const free={operationId:randomUUID(),...slot(nextDay++,10),timeZone:'Europe/Zurich',meetingPoint:second.meetingPoint,instructorMembershipId:id.instructorMember,agreementConfirmed:true};
  expect((await call('POST',`/lessons/${second.id}/move`,free,second.version)).statusCode).toBe(200);
  expect((await pool.query('SELECT status FROM drivy.lesson_change_request WHERE id=$1',[moveRequest.id])).rows[0].status).toBe('SUPERSEDED');
  const third=await plan(),cancelRequest=(await ask(third.id,'CANCEL')).json().data.requests[0];
  expect((await call('POST',`/lessons/${third.id}/move`,{...free,operationId:randomUUID(),...slot(nextDay++,11)},third.version)).statusCode).toBe(200);
  expect((await pool.query('SELECT status FROM drivy.lesson_change_request WHERE id=$1',[cancelRequest.id])).rows[0].status).toBe('PENDING');
  // Annuler la leçon sans désigner la demande ferme toute demande en attente.
  const cancelled=await call('POST',`/lessons/${third.id}/cancel`,{operationId:randomUUID(),reasonCode:'INSTRUCTOR_UNAVAILABLE'},(await lessonRow(third.id)).version);
  expect(cancelled.statusCode,cancelled.body).toBe(200);
  expect((await pool.query('SELECT status FROM drivy.lesson_change_request WHERE id=$1',[cancelRequest.id])).rows[0].status).toBe('SUPERSEDED');
 });
});

describe('isolement',()=>{
 it('les demandes sont forcées par la sécurité par ligne et invisibles hors périmètre',async()=>{
  expect((await pool.query("SELECT relrowsecurity AND relforcerowsecurity AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relname='lesson_change_request'")).rows[0].forced).toBe(true);
  const lesson=await plan();await ask(lesson.id,'CANCEL');
  // Une identité sans appartenance à l'école ne lit rien.
  const outsider=await call('GET',`/lessons/${lesson.id}/change-requests`,undefined,null,'demo-outsider');
  expect([403,404]).toContain(outsider.statusCode);
 });
});
