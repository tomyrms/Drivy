import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

let pool:Pool,h:CaptureHarness;
beforeAll(async()=>{pool=await freshDatabase();h=await captureHarness(pool,{gpsOnlyQualificationSchoolIds:[id.schoolA]});});
afterAll(async()=>{await h?.app.close();await pool?.end();});
async function lesson(){
 const lessonId=randomUUID();
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  VALUES($1,$2,$3,$4,$5,$6,now()-interval '1 minute',now()+interval '45 minutes','Europe/Zurich','Recette synthétique',1000,0,$7,'{"mode":"UNIT_PRICE"}')`,[lessonId,id.schoolA,id.aliceTraining,id.aliceLearner,id.alice,id.instructorMember,h.policy]);
 return lessonId;
}
const choose=(lessonId:string,status:'ALLOWED'|'REFUSED',expectedChoiceVersion?:number,source='SELF',subject='demo-alice')=>h.call('POST',`/learners/${id.aliceLearner}/recording-choice`,{
 operationId:randomUUID(),lessonId,status,noticeVersionId:h.notice,source,...(expectedChoiceVersion===undefined?{}:{expectedChoiceVersion}),
},undefined,subject);
async function assessment(){
 const deviceId=randomUUID(),response=await h.call('POST',`/devices/${deviceId}/assessments`,{operationId:randomUUID(),platform:'IOS',deviceClass:'PHONE',modelCode:'TEST',osVersion:'TEST',appBuild:'TEST',permission:'BACKGROUND',preciseLocation:true,sampleAgeSeconds:0,horizontalAccuracyMeters:5,freeBytes:null,networkAvailable:true});
 expect(response.statusCode,response.body).toBe(201);return {deviceId,deviceAssessmentId:response.json().data.id as string};
}
const currentLesson=async(lessonId:string)=>(await h.call('GET',`/lessons/${lessonId}`)).json().data;

it('exige le choix personnel et sa version affichée, sans permettre au moniteur de se déclarer SELF',async()=>{
 const lessonId=await lesson();
 expect((await choose(lessonId,'ALLOWED',0,'RECORDED_VERBAL','demo-instructor')).json().code).toBe('RECORDING_SELF_REQUIRED');
 expect([403,404]).toContain((await choose(lessonId,'ALLOWED',0,'SELF','demo-instructor')).statusCode);
 expect((await choose(lessonId,'ALLOWED')).json().code).toBe('RECORDING_CHOICE_CHANGED');
 const first=await choose(lessonId,'ALLOWED',0);expect(first.statusCode,first.body).toBe(200);
 expect((await pool.query('SELECT count(*)::int AS n FROM drivy.recording_choice WHERE lesson_id=$1',[lessonId])).rows[0].n).toBe(1);
});

it('un retrait sur un second appareil empêche un ancien accord en attente de revenir, sans empêcher le retrait',async()=>{
 const lessonId=await lesson(),allowed=await choose(lessonId,'ALLOWED',0);expect(allowed.statusCode,allowed.body).toBe(200);
 const refused=await choose(lessonId,'REFUSED',0);expect(refused.statusCode,refused.body).toBe(200);
 const stale=await choose(lessonId,'ALLOWED',allowed.json().data.version);expect(stale.json().code).toBe('RECORDING_CHOICE_CHANGED');
 expect((await h.call('GET',`/learners/${id.aliceLearner}/recording-choice?lessonId=${lessonId}`)).json().data).toMatchObject({status:'REFUSED',version:refused.json().data.version});
 // Deux accords sur la même version : un seul peut remplacer ce retrait.
 const concurrent=await Promise.all([choose(lessonId,'ALLOWED',refused.json().data.version),choose(lessonId,'ALLOWED',refused.json().data.version)]);
 expect(concurrent.map(response=>response.statusCode).sort()).toEqual([200,409]);
});

it('un accord verbal antérieur à la qualification ne suffit pas pour commencer un trajet',async()=>{
 const lessonId=await lesson(),device=await assessment();
 const choice=(await pool.query(`INSERT INTO drivy.recording_choice(school_id,version,learner_id,lesson_id,status,notice_version_id,recorded_by,source)
  SELECT $1,coalesce(max(version),0)+1,$2,$3,'ALLOWED',$4,$5,'RECORDED_VERBAL' FROM drivy.recording_choice WHERE school_id=$1 AND learner_id=$2 RETURNING id,version`,[id.schoolA,id.aliceLearner,lessonId,h.notice,id.instructorMember])).rows[0];
 const denied=await h.call('POST',`/lessons/${lessonId}/captures`,{operationId:randomUUID(),...device,choiceId:choice.id,choiceVersion:choice.version,noticeVersionId:h.notice,explicitStartConfirmed:true},1);
 expect(denied.statusCode,denied.body).toBe(403);expect(denied.json().code).toBe('RECORDING_SELF_REQUIRED');
 expect(await currentLesson(lessonId)).toMatchObject({actualStart:null,version:1});
 expect((await pool.query('SELECT count(*)::int AS n FROM drivy.capture_session WHERE lesson_id=$1',[lessonId])).rows[0].n).toBe(0);
});

it('un départ hors créneau garde la fenêtre de sécurité et indique le déplacement du rendez-vous',async()=>{
 const lessonId=await lesson(),device=await assessment();
 await pool.query("UPDATE drivy.lesson SET planned_start=now()-interval '3 hours',planned_end=now()-interval '2 hours' WHERE id=$1",[lessonId]);
 const denied=await h.call('POST',`/lessons/${lessonId}/captures`,{operationId:randomUUID(),...device,choiceId:randomUUID(),choiceVersion:1,noticeVersionId:h.notice,explicitStartConfirmed:true},1);
 expect(denied.statusCode,denied.body).toBe(409);expect(denied.json().code).toBe('CAPTURE_START_WINDOW');
 expect(denied.json().title).toContain('Déplacez le rendez-vous');
 expect(await currentLesson(lessonId)).toMatchObject({actualStart:null,version:1});
 expect((await pool.query('SELECT count(*)::int AS n FROM drivy.capture_session WHERE lesson_id=$1',[lessonId])).rows[0].n).toBe(0);
});

it('refuse la source moto sans départ partiel, puis commence atomiquement le trajet voiture et la leçon',async()=>{
 const lessonId=await lesson(),choice=await choose(lessonId,'ALLOWED',0),device=await assessment();
 expect(choice.statusCode,choice.body).toBe(200);
 const body={operationId:randomUUID(),...device,choiceId:choice.json().data.id,choiceVersion:choice.json().data.version,noticeVersionId:h.notice,explicitStartConfirmed:true};
 await pool.query("UPDATE drivy.offering_version SET category_code='A' WHERE id=$1",[id.offeringA]);
 try{
  const denied=await h.call('POST',`/lessons/${lessonId}/captures`,body,1);expect(denied.json().code).toBe('GPS_SOURCE_UNQUALIFIED');
  expect(await currentLesson(lessonId)).toMatchObject({actualStart:null,version:1});
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.capture_session WHERE lesson_id=$1',[lessonId])).rows[0].n).toBe(0);
 }finally{await pool.query("UPDATE drivy.offering_version SET category_code='B' WHERE id=$1",[id.offeringA]);}
 const secondDevice=await assessment();
 const responses=await Promise.all([
  h.call('POST',`/lessons/${lessonId}/captures`,body,1),
  h.call('POST',`/lessons/${lessonId}/captures`,{...body,operationId:randomUUID(),...secondDevice},1),
 ]);
 expect(responses.map(response=>response.statusCode).sort()).toEqual([201,412]);
 const started=responses.find(response=>response.statusCode===201)!,capture=started.json().data.capture;
 expect(await currentLesson(lessonId)).toMatchObject({actualStart:capture.authorizedAt,version:2});
 expect((await pool.query("SELECT count(*)::int AS n FROM drivy.lesson_event_outbox WHERE lesson_id=$1 AND event_type='LessonStarted'",[lessonId])).rows[0].n).toBe(1);
 const revoked=await choose(lessonId,'REFUSED');expect(revoked.statusCode,revoked.body).toBe(200);
 expect((await h.call('GET',`/captures/${capture.id}`)).json().data.captureState).toBe('REVOKED');
 // Le retrait coupe le trajet ; il ne réécrit pas l'heure de départ déjà constatée.
 expect((await currentLesson(lessonId)).actualStart).toBe(capture.authorizedAt);
});
