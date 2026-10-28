import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,moveToNow,id,type Call} from './support/harness.js';

let pool:Pool,call:Call,legacy:Awaited<ReturnType<typeof harness>>,qualified:Awaited<ReturnType<typeof harness>>;
const mixedCaseSchool='abcdefab-1234-4234-8234-abcdefabcdef';
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
beforeAll(async()=>{
 pool=await freshDatabase();legacy=await harness(pool);qualified=await harness(pool,{gpsOnlyQualificationSchoolIds:[id.schoolA,mixedCaseSchool]});
 call=qualified.call;school=await prepareSchool(pool);commercial=await prepareCommercial(call);
});
afterAll(async()=>{await qualified?.app.close();await legacy?.app.close();await pool?.end();});

it('annonce la politique de qualification et conserve LEGACY hors activation explicite',async()=>{
 expect((await call('GET','/recording-notice')).json().data.practicalStartPolicy).toBe('GPS_REQUIRED');
 expect((await legacy.call('GET','/recording-notice')).json().data.practicalStartPolicy).toBe('LEGACY');
});

it('ne permet pas de contourner la politique par des UUID majuscules dans le chemin',async()=>{
 const member=randomUUID(),notice=randomUUID(),learner=randomUUID(),offering=randomUUID(),training=randomUUID();
 await pool.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES($1,'École synthétique casse UUID','ACTIVE','test@example.invalid')",[mixedCaseSchool]);
 await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles,status) VALUES($1,$2,$3,'{INSTRUCTOR}','ACTIVE')",[member,mixedCaseSchool,id.instructor]);
 await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles,status) VALUES($1,$2,$3,'{LEARNER}','ACTIVE')",[randomUUID(),mixedCaseSchool,id.alice]);
 await pool.query('INSERT INTO drivy.learner_profile(id,school_id,person_id) VALUES($1,$2,$3)',[learner,mixedCaseSchool,id.alice]);
 await pool.query("INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version) VALUES($1,$2,'category-b','B',1)",[offering,mixedCaseSchool]);
 await pool.query("INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status) VALUES($1,$2,$3,$4,'category-b','ACTIVE')",[training,mixedCaseSchool,learner,offering]);
 await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')",[randomUUID(),mixedCaseSchool,training,member]);
 await pool.query("INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at,notice_version_id) VALUES($1,1,'Notice synthétique','Conservation synthétique','test@example.invalid',$2,now(),$3)",[mixedCaseSchool,member,notice]);
 const path=`/v1/schools/${mixedCaseSchool.toUpperCase()}`;
 const read=await call('GET',`${path}/recording-notice`);expect(read.statusCode,read.body).toBe(200);
 expect(read.json().data.practicalStartPolicy).toBe('GPS_REQUIRED');
 const start=await call('POST',`${path}/lessons/start-now`,{operationId:randomUUID(),trainingId:training});
 expect(start.statusCode,start.body).toBe(409);expect(start.json().code).toBe('GPS_START_REQUIRED');
 const policy=randomUUID(),lessonId=randomUUID();
 await pool.query("INSERT INTO drivy.school_policy_version(id,school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at) VALUES($1,$2,'B',1,'Recette synthétique','Recette synthétique','{}',true,'Recette synthétique',$3,now())",[policy,mixedCaseSchool,member]);
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  VALUES($1,$2,$3,$4,$5,$6,now(),now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{}')`,[lessonId,mixedCaseSchool,training,learner,id.alice,member,policy]);
 const plannedStart=await call('POST',`${path}/lessons/${lessonId}/start`,{operationId:randomUUID()},1);
 expect(plannedStart.statusCode,plannedStart.body).toBe(409);expect(plannedStart.json().code).toBe('GPS_START_REQUIRED');
 expect((await pool.query('SELECT actual_start FROM drivy.lesson WHERE id=$1',[lessonId])).rows[0].actual_start).toBeNull();
});

it('refuse les anciens départs sans écrire une opération, puis prépare une leçon non commencée avec rejeu durable',async()=>{
 const before=(await pool.query('SELECT count(*)::int AS n FROM drivy.lesson')).rows[0].n;
 const deniedOperation=randomUUID();
 for(const prepareForGPS of [undefined,false]){
  const denied=await call('POST','/lessons/start-now',{operationId:deniedOperation,trainingId:id.aliceTraining,...(prepareForGPS===undefined?{}:{prepareForGPS})});
  expect(denied.statusCode,denied.body).toBe(409);expect(denied.json().code).toBe('GPS_START_REQUIRED');
 }
 expect((await pool.query('SELECT count(*)::int AS n FROM drivy.lesson')).rows[0].n).toBe(before);
 expect((await pool.query('SELECT count(*)::int AS n FROM drivy.operation WHERE operation_id=$1',[deniedOperation])).rows[0].n).toBe(0);
 const body={operationId:randomUUID(),trainingId:id.aliceTraining,prepareForGPS:true};
 const prepared=await call('POST','/lessons/start-now',body);expect(prepared.statusCode,prepared.body).toBe(201);
 const lesson=prepared.json().data;expect(lesson).toMatchObject({status:'PLANNED',actualStart:null,actualEnd:null,version:1});
 expect((await call('POST','/lessons/start-now',body)).json().data).toEqual(lesson);
 expect((await call('GET',`/lessons/${lesson.id}`,undefined,null,'demo-alice')).json().data.actualStart).toBeNull();
 expect((await pool.query("SELECT count(*)::int AS n FROM drivy.lesson_event_outbox WHERE lesson_id=$1 AND event_type='LessonStarted'",[lesson.id])).rows[0].n).toBe(0);
 expect((await call('POST',`/lessons/${lesson.id}/start`,{operationId:randomUUID()},lesson.version)).json().code).toBe('GPS_START_REQUIRED');
 const cancelled=await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},lesson.version);
 expect(cancelled.statusCode,cancelled.body).toBe(200);expect(cancelled.json().data.actualStart).toBeNull();
});

it('bloque aussi une leçon planifiée et laisse le serveur LEGACY commencer normalement',async()=>{
 const planned=await call('POST','/lessons',lessonBody(commercial,school.policy,80));expect(planned.statusCode,planned.body).toBe(201);
 const lesson=planned.json().data;await moveToNow(pool,lesson.id);
 const denied=await call('POST',`/lessons/${lesson.id}/start`,{operationId:randomUUID()},lesson.version);
 expect(denied.json().code).toBe('GPS_START_REQUIRED');
 expect((await call('GET',`/lessons/${lesson.id}`)).json().data).toMatchObject({actualStart:null,version:1});
 const start=await legacy.call('POST',`/lessons/${lesson.id}/start`,{operationId:randomUUID()},lesson.version);
 expect(start.statusCode,start.body).toBe(200);expect(start.json().data.actualStart).toBeTypeOf('string');
});
