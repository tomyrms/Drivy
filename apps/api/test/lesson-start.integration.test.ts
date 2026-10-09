import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToPast,slot,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let nextDay=60;
beforeAll(async()=>{pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);});
afterAll(async()=>{await app?.close();await pool?.end();});
const read=async(lessonId:string,subject='demo-instructor')=>(await call('GET',`/lessons/${lessonId}`,undefined,null,subject)).json().data;
async function plan(){const r=await call('POST','/lessons',lessonBody(commercial,school.policy,nextDay++));expect(r.statusCode,r.body).toBe(201);return r.json().data;}
const completeBody=(actualStart:string)=>({operationId:randomUUID(),actualStart,actualEnd:new Date().toISOString(),anomalyReason:'Permis non contrôlé, recette synthétique'});

describe('départ explicite et durable, avec ou sans agenda',()=>{
 it('start-now persiste le départ, le relit côté élève et termine une seule fois avec partage',async()=>{
  const body={operationId:randomUUID(),trainingId:id.aliceTraining};
  const result=await call('POST','/lessons/start-now',body);expect(result.statusCode,result.body).toBe(201);
  const lesson=result.json().data;
  expect(lesson).toMatchObject({status:'PLANNED',actualStart:lesson.plannedStart,actualEnd:null,version:1});
  expect((await read(lesson.id,'demo-alice')).actualStart).toBe(lesson.actualStart);
  expect((await call('POST','/lessons/start-now',body)).json().data).toEqual(lesson);
  // Une horloge cliente décalée ne remplace plus le début déjà enregistré.
  const complete={...completeBody(new Date(Date.now()-60_000).toISOString()),workedOn:'Observation synthétique'};
  const [a,b]=await Promise.all([call('POST',`/lessons/${lesson.id}/complete`,complete,lesson.version),call('POST',`/lessons/${lesson.id}/complete`,complete,lesson.version)]);
  expect(a.statusCode,a.body).toBe(200);expect(b.json().data).toEqual(a.json().data);
  expect(a.json().data.lesson).toMatchObject({status:'COMPLETED',actualStart:lesson.actualStart,actualEnd:complete.actualEnd});
  const shared=a.json().data.lesson.currentPublishedRevisionId;expect(shared).toBeTypeOf('string');
  expect((await call('GET',`/report-revisions/${shared}`,undefined,null,'demo-alice')).statusCode).toBe(200);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.charge_entry WHERE operation_id=$1',[complete.operationId])).rows[0].n).toBe(1);
 });

 it('un rendez-vous dépassé reste en attente à chaque lecture, sans bilan ni compte créé',async()=>{
  const lesson=await plan();await moveToPast(pool,lesson.id);
  for(const subject of ['demo-instructor','demo-admin','demo-alice']){
   expect(await read(lesson.id,subject)).toMatchObject({status:'PLANNED',actualStart:null,actualEnd:null,version:1});
  }
  const page=await call('GET',`/lessons?trainingId=${id.aliceTraining}&limit=100`);
  expect(page.json().data.items.find((l:{id:string})=>l.id===lesson.id)).toMatchObject({status:'PLANNED',actualStart:null});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.report_draft WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(0);
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.lesson_account WHERE lesson_id=$1',[lesson.id])).rows[0].n).toBe(0);
  const cancel=await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST'},lesson.version);
  expect(cancel.statusCode,cancel.body).toBe(200);expect(cancel.json().data).toMatchObject({status:'CANCELLED',actualStart:null});
 });

 it('démarre tardivement avec un instant serveur unique puis se termine sans dépendre du créneau',async()=>{
  const lesson=await plan();await moveToPast(pool,lesson.id);
  const body={operationId:randomUUID()},route=`/lessons/${lesson.id}/start`,before=Date.now();
  const [a,b]=await Promise.all([call('POST',route,body,lesson.version),call('POST',route,body,lesson.version)]);
  expect(a.statusCode,a.body).toBe(200);expect(b.json().data).toEqual(a.json().data);
  const started=a.json().data;expect(started).toMatchObject({status:'PLANNED',version:2,actualEnd:null});
  expect(Date.parse(started.actualStart)).toBeGreaterThanOrEqual(before);expect(a.headers.etag).toBe('"2"');
  expect((await read(lesson.id)).actualStart).toBe(started.actualStart);
  expect((await call('GET',`/operations/${body.operationId}`)).json().data).toMatchObject({commandType:'START_LESSON',resourceType:'Lesson',resourceId:lesson.id,resourceVersion:2});
  expect((await call('POST',route,{operationId:randomUUID()},started.version)).json().code).toBe('LESSON_STARTED');
  expect((await call('POST',`/lessons/${lesson.id}/no-show`,{operationId:randomUUID(),reason:'Absence synthétique'},started.version)).json().code).toBe('LESSON_STARTED');
  const invalid=await call('POST',`/lessons/${lesson.id}/complete`,{...completeBody(started.actualStart),actualEnd:started.actualStart},started.version);
  expect(invalid.json().code).toBe('INVALID_ACTUAL_INTERVAL');expect((await read(lesson.id)).version).toBe(2);
  const done=await call('POST',`/lessons/${lesson.id}/complete`,completeBody(started.actualStart),started.version);
  expect(done.statusCode,done.body).toBe(200);expect(done.json().data.lesson.status).toBe('COMPLETED');
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.lesson_event_outbox WHERE lesson_id=$1 AND event_type='LessonStarted'",[lesson.id])).rows[0].n).toBe(1);
 });

 it('un départ réel anticipé se termine ; une leçon future sans départ reste protégée',async()=>{
  const lesson=await plan(),route=`/lessons/${lesson.id}`;
  const refused=await call('POST',`${route}/complete`,completeBody(new Date(Date.now()-60_000).toISOString()),lesson.version);
  expect(refused.json().code).toBe('LESSON_NOT_STARTED');
  const start=await call('POST',`${route}/start`,{operationId:randomUUID()},lesson.version);expect(start.statusCode,start.body).toBe(200);
  const done=await call('POST',`${route}/complete`,completeBody(start.json().data.actualStart),start.json().data.version);
  expect(done.statusCode,done.body).toBe(200);expect(done.json().data.lesson.actualStart).toBe(start.json().data.actualStart);
 });

 it('revérifie auteur, école, formation, version et révocation sans départ partiel',async()=>{
  const lesson=await plan(),route=`/lessons/${lesson.id}/start`;
  expect((await call('POST',route,{operationId:randomUUID()})).statusCode).toBe(428);
  expect((await call('POST',route,{operationId:randomUUID()},99)).json().code).toBe('VERSION_CONFLICT');
  for(const subject of ['demo-admin','demo-alice','demo-other-instructor','demo-foreign']){
   const result=await call('POST',route,{operationId:randomUUID()},lesson.version,subject);expect([403,404]).toContain(result.statusCode);
  }
  await pool.query("UPDATE drivy.training SET status='PAUSED' WHERE id=$1",[id.aliceTraining]);
  try{expect((await call('POST',route,{operationId:randomUUID()},lesson.version)).json().code).toBe('TRAINING_NOT_ACTIVE');}
  finally{await pool.query("UPDATE drivy.training SET status='ACTIVE' WHERE id=$1",[id.aliceTraining]);}
  await pool.query("UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1",[id.assignment]);
  try{expect((await call('POST',route,{operationId:randomUUID()},lesson.version)).statusCode).toBe(404);}
  finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
  expect(await read(lesson.id)).toMatchObject({actualStart:null,version:1});
  const start=await call('POST',route,{operationId:randomUUID()},lesson.version);expect(start.statusCode,start.body).toBe(200);
  const move={operationId:randomUUID(),...slot(nextDay++),timeZone:'Europe/Zurich',meetingPoint:'Recette',instructorMembershipId:id.instructorMember,agreementConfirmed:true};
  expect((await call('POST',`/lessons/${lesson.id}/move`,move,start.json().data.version)).json().code).toBe('LESSON_STARTED');
 });

 it('conserve un rendez-vous dépassé déplaçable tant qu’aucun départ n’a été enregistré',async()=>{
  const lesson=await plan();await moveToPast(pool,lesson.id);
  const future=slot(nextDay++),query=new URLSearchParams({trainingId:lesson.trainingId,instructorMembershipId:lesson.instructorMembershipId,...future,timeZone:lesson.timeZone,bufferMinutes:String(lesson.bufferMinutesSnapshot),excludeLessonId:lesson.id});
  const available=await call('GET',`/lessons/availability?${query}`);expect(available.statusCode,available.body).toBe(200);expect(available.json().data.available).toBe(true);
  const moved=await call('POST',`/lessons/${lesson.id}/move`,{operationId:randomUUID(),...future,timeZone:lesson.timeZone,meetingPoint:'Recette',instructorMembershipId:lesson.instructorMembershipId,agreementConfirmed:true},lesson.version);
  expect(moved.statusCode,moved.body).toBe(200);expect(moved.json().data).toMatchObject({status:'PLANNED',actualStart:null,plannedStart:future.plannedStart});
 });

 it('une annulation concurrente au départ ne valide qu’une commande sur la version affichée',async()=>{
  const lesson=await plan();
  const results=await Promise.all([call('POST',`/lessons/${lesson.id}/start`,{operationId:randomUUID()},lesson.version),call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},lesson.version)]);
  expect(results.map(r=>r.statusCode).sort()).toEqual([200,412]);
  const saved=await read(lesson.id);expect(saved.version).toBe(2);
  expect(saved.status==='CANCELLED'?saved.actualStart===null:typeof saved.actualStart==='string').toBe(true);
 });

 it('répare les anciens départs manuels prouvés sans transformer les rendez-vous simplement dépassés',async()=>{
  const manual=await call('POST','/lessons/start-now',{operationId:randomUUID(),trainingId:id.aliceTraining});expect(manual.statusCode,manual.body).toBe(201);
  const known=manual.json().data,waiting=await plan();await moveToPast(pool,waiting.id);
  await pool.query('UPDATE drivy.lesson SET actual_start=NULL WHERE id=$1',[known.id]);
  const migration=await readFile(new URL('../migrations/023_explicit_lesson_start.sql',import.meta.url),'utf8');
  const repair=migration.slice(migration.indexOf('ALTER TABLE drivy.lesson NO FORCE'),migration.indexOf('-- Un rendez-vous dépassé'));
  const db=await pool.connect();
  try{await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_harness_migrator');await db.query(repair);await db.query('COMMIT');}
  catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
  expect(await read(known.id)).toMatchObject({actualStart:known.plannedStart,version:known.version+1});
  expect(await read(waiting.id)).toMatchObject({actualStart:null,status:'PLANNED',version:1});
  const forced=await pool.query("SELECT bool_and(relforcerowsecurity) AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND c.relkind='r'");
  expect(forced.rows[0].forced).toBe(true);
 });
});
