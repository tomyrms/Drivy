import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,slot,id,type Call} from './support/harness.js';
import {processPushBatch,type PushSender} from '../src/course-push.js';

/**
 * #43/#44 : demandes de leçon et examens enfilés dans la transaction de l'écriture, relus juste avant l'envoi.
 * Données synthétiques. L'envoi APNs réel est remplacé par un expéditeur de test : aucune réception n'est revendiquée.
 */
let pool:Pool,worker:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let validatePreferences:ReturnType<Ajv2020['compile']>;
let nextDay=210;
const alice='demo-alice',staff='demo-instructor',admin='demo-admin',outsider='demo-other-instructor';
const aliceToken='a1'.repeat(32),staffToken='b2'.repeat(32),adminToken='c3'.repeat(32);
beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);
 worker=new Pool({connectionString:process.env.TEST_DATABASE_URL,options:'-c role=drivy_harness_migrator'});
 const contract=JSON.parse(await readFile(new URL('../contracts/notification-preferences.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 validatePreferences=ajv.compile({$ref:`${contract.$id}#/$defs/Envelope`});
 for(const [subject,token] of [[staff,staffToken],[alice,aliceToken],[admin,adminToken]] as const)
  expect((await call('PUT','/v1/me/push-devices',{token,environment:'SANDBOX'} as never,null,subject)).statusCode).toBe(200);
});
afterAll(async()=>{await app?.close();await worker?.end();await pool?.end();});
const conforms=(validate:ReturnType<Ajv2020['compile']>,body:unknown)=>{expect(validate(body),JSON.stringify(validate.errors)).toBe(true);};

async function plan(){
 const r=await call('POST','/lessons',lessonBody(commercial,school.policy,nextDay++));expect(r.statusCode,r.body).toBe(201);return r.json().data;
}
const ask=(lessonId:string,kind:'RESCHEDULE'|'CANCEL',note='',operationId=randomUUID())=>call('POST',`/lessons/${lessonId}/change-requests`,{operationId,kind,note},null,alice);
const alerts=async(person:string,prefix:string)=>(await pool.query<{id:string;category:string;dedupe_key:string;title:string;body:string;status:string;failure_code:string|null;lesson_id:string|null;exam_id:string|null;valid_until:Date|null}>(
 `SELECT id,category,dedupe_key,title,body,status,failure_code,lesson_id,exam_id,valid_until FROM drivy.push_notification
  WHERE person_id=$1 AND dedupe_key LIKE $2 ORDER BY created_at,id`,[person,`${prefix}%`])).rows;
type Sent={token:string;payload:Record<string,unknown>};
let sent:Sent[]=[];
const sender:PushSender={send:async(token,_environment,payload)=>{sent.push({token,payload:payload as Record<string,unknown>});return 'SENT';},close(){}};
/** Un passage du service d'envoi : la file et la revalidation réelles, l'APNs remplacé. */
const batch=async()=>{sent=[];await processPushBatch(worker,sender);return sent.filter(entry=>['LESSON_REQUEST','LESSON_REQUEST_ANSWER','EXAM'].includes(String(entry.payload.category)));};
const prefs=async(subject:string)=>(await call('GET','/v1/me/notification-preferences',undefined,null,subject)).json().data;
const putPrefs=(subject:string,body:Record<string,unknown>,version:number)=>call('PUT','/v1/me/notification-preferences',body as never,version,subject);

/** Chaque test travaille sur sa propre formation pour que les épreuves ne s'entrechoquent pas. */
async function freshTraining(){
 const offering=randomUUID(),training=randomUUID();
 await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
  VALUES($1,$2,$3,'B',1,true,$4,$5,50,9000)`,[offering,id.schoolA,`push-${offering}`,school.curriculum,school.policy]);
 await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,$5,'ACTIVE',current_date)`,
  [training,id.schoolA,id.aliceLearner,offering,`push-${offering}`]);
 await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')`,
  [randomUUID(),id.schoolA,training,id.instructorMember]);
 return training;
}
const examBody=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),startsAt:slot(nextDay++,9).plannedStart,timeZone:'Europe/Zurich',location:'Centre d’examen (synthétique)',...extra});
const createExam=(training:string,extra:Record<string,unknown>={})=>call('POST',`/trainings/${training}/exams`,{kind:'THEORY',...examBody(extra)},null,staff);

describe('demande de leçon : le moniteur actif, sinon les administrateurs',()=>{
 it('enfile exactement une alerte au moniteur, jamais à l’élève auteur, avec une charge générique',async()=>{
  const lesson=await plan(),note='Je suis malade (synthétique)';
  const created=await ask(lesson.id,'CANCEL',note);expect(created.statusCode,created.body).toBe(201);
  const requestId=created.json().data.requests[0].id;
  const rows=await alerts(id.instructor,`LessonRequest:${requestId}`);
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({category:'LESSON_REQUEST',title:'Nouvelle demande',body:'Un élève attend votre réponse.',status:'PENDING',lesson_id:lesson.id,failure_code:null});
  expect(await alerts(id.alice,`LessonRequest:${requestId}`)).toHaveLength(0);
  // Échéance : au plus tard 24 h, et jamais après le début prévu de la leçon.
  const remaining=rows[0]!.valid_until!.getTime()-Date.now();
  expect(remaining).toBeGreaterThan(23.9*3_600_000);expect(remaining).toBeLessThanOrEqual(24*3_600_000+5_000);
  expect(rows[0]!.valid_until!.getTime()).toBeLessThanOrEqual(Date.parse(lesson.plannedStart));
  const calls=await batch();
  expect(calls).toHaveLength(1);
  expect(calls[0]).toEqual({token:staffToken,payload:{aps:{alert:{title:'Nouvelle demande',body:'Un élève attend votre réponse.'}},category:'LESSON_REQUEST'}});
  const payload=JSON.stringify(calls[0]!.payload);
  expect(payload).not.toContain('Alice');expect(payload).not.toContain('malade');expect(payload).not.toContain('CANCEL');
 });
 it('sans moniteur actif, tous les administrateurs actifs sont alertés, jamais l’auteur',async()=>{
  const lesson=await plan();
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
  try{
   const created=await ask(lesson.id,'CANCEL','Contretemps');expect(created.statusCode,created.body).toBe(201);
   const requestId=created.json().data.requests[0].id;
   expect(await alerts(id.admin,`LessonRequest:${requestId}`)).toHaveLength(1);
   expect(await alerts(id.instructor,`LessonRequest:${requestId}`)).toHaveLength(0);
   expect(await alerts(id.alice,`LessonRequest:${requestId}`)).toHaveLength(0);
   const calls=await batch();expect(calls.map(entry=>entry.token)).toEqual([adminToken]);
  }finally{await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.instructorMember]);}
 });
});

describe('réponse à la demande',()=>{
 it('un refus alerte l’élève demandeur, jamais le moniteur auteur, sans motif ni nom',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'RESCHEDULE','Mercredi après 16 h')).json().data.requests[0];
  await batch();
  const refused=await call('POST',`/lesson-change-requests/${request.id}/refuse`,{operationId:randomUUID(),note:'Créneau indisponible (synthétique)'},request.version,staff);
  expect(refused.statusCode,refused.body).toBe(200);
  const rows=await alerts(id.alice,`LessonRequestAnswer:${request.id}`);
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({category:'LESSON_REQUEST_ANSWER',title:'Demande traitée',body:'Votre demande a reçu une réponse.',lesson_id:lesson.id});
  expect(await alerts(id.instructor,`LessonRequestAnswer:${request.id}`)).toHaveLength(0);
  const calls=await batch();
  expect(calls).toEqual([{token:aliceToken,payload:{aps:{alert:{title:'Demande traitée',body:'Votre demande a reçu une réponse.'}},category:'LESSON_REQUEST_ANSWER'}}]);
  expect(JSON.stringify(calls[0]!.payload)).not.toContain('indisponible');
 });
 it('accepter par l’annulation ou le déplacement notifie l’élève une seule fois',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'CANCEL','Contretemps')).json().data.requests[0];
  await batch();
  const accepted=await call('POST',`/lessons/${lesson.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST',changeRequestId:request.id},lesson.version,staff);
  expect(accepted.statusCode,accepted.body).toBe(200);
  const rows=await alerts(id.alice,`LessonRequestAnswer:${request.id}`);
  expect(rows).toHaveLength(1);
  const calls=await batch();expect(calls).toHaveLength(1);expect(calls[0]!.token).toBe(aliceToken);
  // Le retrait par l'élève ne notifie personne : aucune réponse pour cette demande.
  const other=await plan(),withdrawn=(await ask(other.id,'CANCEL')).json().data.requests[0];
  await batch();
  expect((await call('POST',`/lesson-change-requests/${withdrawn.id}/withdraw`,{operationId:randomUUID()},withdrawn.version,alice)).statusCode).toBe(200);
  expect(await alerts(id.alice,`LessonRequestAnswer:${withdrawn.id}`)).toHaveLength(0);
  expect(await alerts(id.instructor,`LessonRequestAnswer:${withdrawn.id}`)).toHaveLength(0);
  expect(await batch()).toHaveLength(0);
 });
 it('préférence coupée : rien n’est enfilé, l’information reste consultable dans l’app',async()=>{
  const instructorPrefs=await prefs(staff);
  expect((await putPrefs(staff,{courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true,lessonRequests:false},instructorPrefs.version)).statusCode).toBe(200);
  try{
   const lesson=await plan(),request=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
   expect(await alerts(id.instructor,`LessonRequest:${request.id}`)).toHaveLength(0);
   expect((await call('GET',`/lessons/${lesson.id}/change-requests`,undefined,null,alice)).json().data.requests[0]).toMatchObject({status:'PENDING'});
  }finally{const current=await prefs(staff);await putPrefs(staff,{courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true,lessonRequests:true},current.version);}
 });
});

describe('relecture juste avant l’envoi',()=>{
 it('demande retirée ou leçon commencée avant l’envoi : EVENT_OBSOLETE, rien n’est envoyé',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
  expect((await call('POST',`/lesson-change-requests/${request.id}/withdraw`,{operationId:randomUUID()},request.version,alice)).statusCode).toBe(200);
  expect(await batch()).toHaveLength(0);
  expect((await alerts(id.instructor,`LessonRequest:${request.id}`))[0]).toMatchObject({status:'SKIPPED',failure_code:'EVENT_OBSOLETE'});

  const started=await plan(),other=(await ask(started.id,'CANCEL')).json().data.requests[0];
  await pool.query('UPDATE drivy.lesson SET actual_start=now() WHERE id=$1',[started.id]);
  expect(await batch()).toHaveLength(0);
  expect((await alerts(id.instructor,`LessonRequest:${other.id}`))[0]).toMatchObject({status:'SKIPPED',failure_code:'EVENT_OBSOLETE'});
 });
 it('destinataire retiré de l’école avant l’envoi : refus RECIPIENT_INELIGIBLE',async()=>{
  const lesson=await plan(),request=(await ask(lesson.id,'CANCEL')).json().data.requests[0];
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
  try{
   expect(await batch()).toHaveLength(0);
   expect((await alerts(id.instructor,`LessonRequest:${request.id}`))[0]).toMatchObject({status:'SKIPPED',failure_code:'RECIPIENT_INELIGIBLE'});
  }finally{await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.instructorMember]);}
 });
});

describe('préférences versionnées',()=>{
 it('les deux nouveaux champs sont facultatifs à l’écriture, toujours présents en lecture, et jamais remis à zéro',async()=>{
  const before=await call('GET','/v1/me/notification-preferences',undefined,null,'demo-bob');conforms(validatePreferences,before.json());
  expect(before.json().data).toMatchObject({lessonRequests:true,examUpdates:true});
  const version=before.json().data.version;
  const legacy={courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true};
  const saved=await putPrefs('demo-bob',legacy,version);expect(saved.statusCode,saved.body).toBe(200);
  expect(saved.json().data).toMatchObject({lessonRequests:true,examUpdates:true,version:version+1});
  const off=await putPrefs('demo-bob',{...legacy,lessonRequests:false,examUpdates:false},version+1);expect(off.statusCode).toBe(200);
  expect(off.json().data).toMatchObject({lessonRequests:false,examUpdates:false});
  // Une ancienne app qui ne mentionne que les quatre champs de cours ne réactive rien.
  const again=await putPrefs('demo-bob',legacy,version+2);expect(again.statusCode).toBe(200);
  expect(again.json().data).toMatchObject({lessonRequests:false,examUpdates:false,version:version+3});
  // Conflit de version : rien n'est écrit.
  expect((await putPrefs('demo-bob',legacy,version+2)).statusCode).toBe(412);
 });
 it('un tiers ne lit ni n’écrit les préférences d’un autre',async()=>{
  const mine=await call('GET','/v1/me/notification-preferences',undefined,null,outsider);conforms(validatePreferences,mine.json());
  expect(mine.json().data).toMatchObject({version:1,lessonRequests:true,examUpdates:true});
  // Bob a coupé ses deux catégories au test précédent ; un autre compte garde ses propres valeurs.
  expect((await prefs('demo-bob')).lessonRequests).toBe(false);
  expect((await prefs(outsider)).lessonRequests).toBe(true);
 });
});

describe('examens',()=>{
 it('saisie, date modifiée, report et résultat alertent l’élève de la formation, jamais l’auteur',async()=>{
  const training=await freshTraining();
  const created=await createExam(training);expect(created.statusCode,created.body).toBe(201);
  const exam=created.json().data.exams[0];
  const createdRows=await alerts(id.alice,`Exam:${exam.id}:CREATED`);
  expect(createdRows).toHaveLength(1);
  expect(createdRows[0]).toMatchObject({category:'EXAM',title:'Examen planifié',body:'Un examen a été ajouté.',exam_id:exam.id});
  expect(await alerts(id.instructor,`Exam:${exam.id}`)).toHaveLength(0);
  expect(await batch()).toEqual([{token:aliceToken,payload:{aps:{alert:{title:'Examen planifié',body:'Un examen a été ajouté.'}},category:'EXAM'}}]);
  // Modification de la date : une alerte « Examen modifié ».
  const moved=examBody({location:'Autre centre (synthétique)'});
  const updated=await call('POST',`/exams/${exam.id}/update`,moved,1,staff);expect(updated.statusCode,updated.body).toBe(200);
  expect(await alerts(id.alice,`Exam:${exam.id}:UPDATED:2`)).toHaveLength(1);
  expect((await batch())[0]).toEqual({token:aliceToken,payload:{aps:{alert:{title:'Examen modifié',body:'La date ou le lieu d’un examen a changé.'}},category:'EXAM'}});
  // Même date, même fuseau, même lieu : aucun nouvel envoi, même si la version avance.
  const unchanged=await call('POST',`/exams/${exam.id}/update`,{...moved,operationId:randomUUID(),reason:'Relecture'},2,staff);
  expect(unchanged.statusCode,unchanged.body).toBe(200);
  expect(await alerts(id.alice,`Exam:${exam.id}:UPDATED:3`)).toHaveLength(0);
  expect(await batch()).toHaveLength(0);
  // Report vers une autre date : une seule alerte pour l'ancienne tentative.
  const postponed=await call('POST',`/exams/${exam.id}/postpone`,examBody({startsAt:slot(nextDay++,11).plannedStart}),3,staff);
  expect(postponed.statusCode,postponed.body).toBe(200);
  const postponedRows=await alerts(id.alice,`Exam:${exam.id}:POSTPONED:4`);
  expect(postponedRows).toHaveLength(1);
  expect(postponedRows[0]).toMatchObject({title:'Examen modifié',exam_id:exam.id});
 });
 it('un résultat enregistré ou corrigé alerte sans jamais révéler réussi ou échoué',async()=>{
  const training=await freshTraining();
  const exam=(await createExam(training)).json().data.exams[0];
  await batch();
  await pool.query("UPDATE drivy.exam SET starts_at=now()-interval '2 hours' WHERE id=$1",[exam.id]);
  const result=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'FAILED',note:'Priorités à droite (synthétique)'},1,staff);
  expect(result.statusCode,result.body).toBe(200);
  const rows=await alerts(id.alice,`Exam:${exam.id}:RESULT:2`);
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({title:'Résultat d’examen',body:'Un résultat est disponible.'});
  const calls=await batch();
  expect(calls).toEqual([{token:aliceToken,payload:{aps:{alert:{title:'Résultat d’examen',body:'Un résultat est disponible.'}},category:'EXAM'}}]);
  const payload=JSON.stringify(calls[0]!.payload);
  expect(payload).not.toContain('FAILED');expect(payload).not.toContain('réussi');expect(payload).not.toContain('Priorités');
 });
 it('préférence examens coupée : aucune alerte n’est enfilée',async()=>{
  const current=await prefs(alice);
  expect((await putPrefs(alice,{courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true,examUpdates:false},current.version)).statusCode).toBe(200);
  try{
   const training=await freshTraining(),created=await createExam(training);expect(created.statusCode,created.body).toBe(201);
   const exam=created.json().data.exams[0];
   expect(await alerts(id.alice,`Exam:${exam.id}`)).toHaveLength(0);
  }finally{const after=await prefs(alice);await putPrefs(alice,{courseOffers:true,courseReminders:true,courseChanges:true,courseStaffAlerts:true,examUpdates:true},after.version);}
 });
});
