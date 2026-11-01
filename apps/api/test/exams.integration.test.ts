import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,slot,id,type Call} from './support/harness.js';
import {attemptNumbers,summarize} from '../src/exams.js';

/** #54 : examens théorique et pratique, tentatives, résultat saisi (jamais déduit d'une date), accompagnement qui occupe le moniteur. */
let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let validateState:ReturnType<Ajv2020['compile']>,validateRevisions:ReturnType<Ajv2020['compile']>,validateList:ReturnType<Ajv2020['compile']>;
let nextDay=120;
const alice='demo-alice',staff='demo-instructor',admin='demo-admin';
beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);
 const contract=JSON.parse(await readFile(new URL('../contracts/exams.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 validateState=ajv.compile({$ref:`${contract.$id}#/$defs/StateEnvelope`});validateRevisions=ajv.compile({$ref:`${contract.$id}#/$defs/RevisionsEnvelope`});validateList=ajv.compile({$ref:`${contract.$id}#/$defs/ListEnvelope`});
});
afterAll(async()=>{await app?.close();await pool?.end();});
const conforms=(validate:ReturnType<Ajv2020['compile']>,body:unknown)=>{expect(validate(body),JSON.stringify(validate.errors)).toBe(true);};
/** Chaque test travaille sur sa propre formation pour que les épreuves prévues ou réussies ne s'entrechoquent pas. */
async function freshTraining(){
 const offering=randomUUID(),training=randomUUID();
 await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
  VALUES($1,$2,$3,'B',1,true,$4,$5,50,9000)`,[offering,id.schoolA,`exam-${offering}`,school.curriculum,school.policy]);
 await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,$5,'ACTIVE',current_date)`,
  [training,id.schoolA,id.aliceLearner,offering,`exam-${offering}`]);
 await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,now()-interval '1 day')`,
  [randomUUID(),id.schoolA,training,id.instructorMember]);
 return training;
}
const when=(day:number,hour=9)=>slot(day,hour).plannedStart;
const body=(extra:Record<string,unknown>={})=>({operationId:randomUUID(),startsAt:when(nextDay++),timeZone:'Europe/Zurich',location:'Centre d’examen (synthétique)',...extra});
const create=(training:string,kind:'THEORY'|'PRACTICAL',extra:Record<string,unknown>={},subject=staff)=>
 call('POST',`/trainings/${training}/exams`,{kind,...body(extra)},null,subject);
const list=async(training:string,subject=staff)=>(await call('GET',`/trainings/${training}/exams`,undefined,null,subject)).json().data;
const toPast=(examId:string)=>pool.query("UPDATE drivy.exam SET starts_at=now()-interval '2 hours' WHERE id=$1",[examId]);
const heldBy=async(examId:string)=>(await pool.query('SELECT count(*)::int AS n FROM drivy.reservation WHERE exam_id=$1 AND active',[examId])).rows[0].n;

describe('prévoir un examen',()=>{
 it('enregistre une tentative lisible par l’élève, sans lui donner le droit de saisir',async()=>{
  const training=await freshTraining();
  const created=await create(training,'THEORY');expect(created.statusCode,created.body).toBe(201);conforms(validateState,created.json());
  const state=created.json().data;
  expect(state).toMatchObject({trainingId:training,canManage:true});
  expect(state.exams).toHaveLength(1);
  expect(state.exams[0]).toMatchObject({kind:'THEORY',status:'SCHEDULED',categoryCode:'B',attempt:1,needsResult:false,escort:null,resultRecordedAt:null,version:1});
  expect(state.summary).toEqual([{kind:'THEORY',passed:false,attempts:1,scheduledExamId:state.exams[0].id},{kind:'PRACTICAL',passed:false,attempts:0,scheduledExamId:null}]);
  // L'élève lit son examen et ne peut ni le créer ni le modifier.
  const own=await list(training,alice);expect(own.canManage).toBe(false);expect(own.exams[0].id).toBe(state.exams[0].id);
  expect((await create(training,'PRACTICAL',{},alice)).statusCode).toBe(403);
  const edit=await call('POST',`/exams/${state.exams[0].id}/update`,{...body()},1,alice);expect(edit.statusCode).toBe(403);
  // Rejeu de la même opération : même réponse, une seule ligne.
  const operationId=randomUUID(),again=body({operationId});
  const first=await call('POST',`/trainings/${training}/exams`,{kind:'PRACTICAL',...again},null,staff);expect(first.statusCode).toBe(201);
  const replay=await call('POST',`/trainings/${training}/exams`,{kind:'PRACTICAL',...again},null,staff);
  expect(replay.json().data.exams).toHaveLength(2);
  expect((await pool.query("SELECT count(*)::int AS n FROM drivy.exam WHERE training_id=$1",[training])).rows[0].n).toBe(2);
 });

 it('refuse une seconde date prévue pour la même épreuve et une formation que l’on ne gère pas',async()=>{
  const training=await freshTraining();
  expect((await create(training,'PRACTICAL')).statusCode).toBe(201);
  const duplicate=await create(training,'PRACTICAL');expect(duplicate.statusCode).toBe(409);expect(duplicate.json().code).toBe('EXAM_ALREADY_SCHEDULED');
  expect((await create(training,'THEORY')).statusCode).toBe(201);
  const wrongZone=await create(training,'THEORY',{timeZone:'America/New_York'});expect(wrongZone.statusCode).toBe(422);
  const tooFar=await create(await freshTraining(),'THEORY',{startsAt:when(900)});expect(tooFar.json().code).toBe('INVALID_EXAM_DATE');
  // Un moniteur non affecté à la formation ne saisit pas.
  const outsider=await create(training,'THEORY',{},'demo-other-instructor');expect([403,404]).toContain(outsider.statusCode);
 });
});

describe('résultat saisi, jamais déduit',()=>{
 it('une date passée reste « à renseigner » ; le résultat est saisi, corrigé avec motif et historisé',async()=>{
  const training=await freshTraining(),exam=(await create(training,'PRACTICAL')).json().data.exams[0];
  // Avant la date : pas de résultat.
  const early=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'FAILED'},exam.version,staff);
  expect(early.statusCode).toBe(409);expect(early.json().code).toBe('EXAM_NOT_STARTED');
  await toPast(exam.id);
  const waiting=(await list(training)).exams[0];
  expect(waiting).toMatchObject({status:'SCHEDULED',needsResult:true,resultRecordedAt:null});
  expect((await list(training)).summary[1]).toMatchObject({passed:false});
  // Résultat saisi : échec, points à travailler lus par l'élève.
  const failed=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'FAILED',note:'Priorités à droite'},waiting.version,staff);
  expect(failed.statusCode,failed.body).toBe(200);conforms(validateState,failed.json());
  expect(failed.json().data.exams[0]).toMatchObject({status:'FAILED',resultNote:'Priorités à droite',needsResult:false,version:2});
  expect((await list(training,alice)).exams[0]).toMatchObject({status:'FAILED',resultNote:'Priorités à droite'});
  // Correction : motif obligatoire.
  const noReason=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'PASSED'},2,staff);
  expect(noReason.statusCode).toBe(422);expect(noReason.json().code).toBe('EXAM_REASON_REQUIRED');
  const corrected=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'PASSED',reason:'Erreur de saisie : résultat communiqué par le centre'},2,staff);
  expect(corrected.statusCode,corrected.body).toBe(200);
  expect(corrected.json().data.exams[0]).toMatchObject({status:'PASSED',version:3});
  expect(corrected.json().data.summary[1]).toMatchObject({passed:true,attempts:1});
  // Version périmée : conflit.
  expect((await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'FAILED',reason:'Test'},2,staff)).statusCode).toBe(412);
  // Une épreuve réussie ne se replanifie pas.
  const again=await create(training,'PRACTICAL');expect(again.statusCode).toBe(409);expect(again.json().code).toBe('EXAM_ALREADY_PASSED');
  // Historique réservé au personnel, avec l'auteur et le motif.
  const revisions=await call('GET',`/exams/${exam.id}/revisions`,undefined,null,admin);expect(revisions.statusCode,revisions.body).toBe(200);conforms(validateRevisions,revisions.json());
  expect(revisions.json().data.items.map((item:{action:string})=>item.action)).toEqual(['RESULT_CORRECTED','RESULT_RECORDED','CREATED']);
  expect(revisions.json().data.items[0]).toMatchObject({status:'PASSED',reason:'Erreur de saisie : résultat communiqué par le centre',actorMembershipId:id.instructorMember});
  expect([403,404]).toContain((await call('GET',`/exams/${exam.id}/revisions`,undefined,null,alice)).statusCode);
 });

 it('l’absence n’est ni un échec ni une réussite, et ne ferme pas l’épreuve',async()=>{
  const training=await freshTraining(),exam=(await create(training,'THEORY')).json().data.exams[0];
  await toPast(exam.id);
  const absent=await call('POST',`/exams/${exam.id}/result`,{operationId:randomUUID(),result:'ABSENT'},exam.version,staff);
  expect(absent.statusCode,absent.body).toBe(200);
  expect(absent.json().data.exams[0].status).toBe('ABSENT');
  expect(absent.json().data.summary[0]).toMatchObject({kind:'THEORY',passed:false,attempts:1,scheduledExamId:null});
  // Une nouvelle tentative reste possible : elle porte le rang 2.
  const retry=await create(training,'THEORY');expect(retry.statusCode,retry.body).toBe(201);
  expect(retry.json().data.exams.map((entry:{attempt:number})=>entry.attempt).sort()).toEqual([1,2]);
 });
});

describe('report et tentatives',()=>{
 it('un report garde la tentative d’origine et ouvre une nouvelle date, sans toucher l’autre épreuve',async()=>{
  const training=await freshTraining();
  const theory=(await create(training,'THEORY')).json().data.exams[0],practical=(await create(training,'PRACTICAL')).json().data.exams[0];
  const target=when(nextDay++,14);
  const postponed=await call('POST',`/exams/${practical.id}/postpone`,{operationId:randomUUID(),startsAt:target,timeZone:'Europe/Zurich',location:'Autre centre',reason:'Moniteur indisponible'},practical.version,staff);
  expect(postponed.statusCode,postponed.body).toBe(200);conforms(validateState,postponed.json());
  const exams:{id:string;kind:string;status:string;attempt:number|null;postponedToExamId:string|null;location:string}[]=postponed.json().data.exams;
  const old=exams.find(entry=>entry.id===practical.id)!,next=exams.find(entry=>entry.kind==='PRACTICAL'&&entry.status==='SCHEDULED')!;
  expect(old).toMatchObject({status:'POSTPONED',attempt:null,postponedToExamId:next.id});
  expect(next).toMatchObject({attempt:1,location:'Autre centre'});expect(next.id).not.toBe(practical.id);
  expect(exams.find(entry=>entry.id===theory.id)).toMatchObject({status:'SCHEDULED',attempt:1});
  // Un examen reporté se modifie plus et n'a pas de résultat.
  const edit=await call('POST',`/exams/${practical.id}/update`,{...body()},2,staff);expect(edit.statusCode).toBe(409);expect(edit.json().code).toBe('EXAM_CLOSED');
  const result=await call('POST',`/exams/${practical.id}/result`,{operationId:randomUUID(),result:'FAILED'},2,staff);expect(result.statusCode).toBe(409);
  expect(postponed.json().data.summary[1]).toMatchObject({attempts:1,scheduledExamId:next.id});
  // Les deux lignes de l'historique du report portent le motif.
  const revisions=(await call('GET',`/exams/${practical.id}/revisions`,undefined,null,staff)).json().data.items;
  expect(revisions[0]).toMatchObject({action:'POSTPONED',reason:'Moniteur indisponible'});
 });

 it('modifie la date d’un examen prévu avec son historique',async()=>{
  const training=await freshTraining(),exam=(await create(training,'THEORY')).json().data.exams[0];
  const moved=await call('POST',`/exams/${exam.id}/update`,{operationId:randomUUID(),startsAt:when(nextDay++,15),timeZone:'Europe/Zurich',location:'Salle 2',reason:'Convocation modifiée'},exam.version,admin);
  expect(moved.statusCode,moved.body).toBe(200);
  expect(moved.json().data.exams[0]).toMatchObject({location:'Salle 2',version:2,status:'SCHEDULED'});
  expect((await call('GET',`/exams/${exam.id}/revisions`,undefined,null,admin)).json().data.items[0]).toMatchObject({action:'UPDATED',reason:'Convocation modifiée'});
 });

 it('compte les tentatives par épreuve sans compter les reports',()=>{
  const row=(idValue:string,kind:'THEORY'|'PRACTICAL',status:'SCHEDULED'|'POSTPONED'|'ABSENT'|'PASSED'|'FAILED',day:number)=>
   ({id:idValue,kind,status,starts_at:new Date(Date.UTC(2030,0,day)),created_at:new Date(Date.UTC(2029,0,day))});
  const rows=[row('a','PRACTICAL','POSTPONED',1),row('b','PRACTICAL','FAILED',5),row('c','PRACTICAL','SCHEDULED',9),row('d','THEORY','PASSED',2)];
  const ranks=attemptNumbers(rows);
  expect(ranks.get('a')).toBeUndefined();expect(ranks.get('b')).toBe(1);expect(ranks.get('c')).toBe(2);expect(ranks.get('d')).toBe(1);
  expect(summarize(rows)).toEqual([{kind:'THEORY',passed:true,attempts:1,scheduledExamId:null},{kind:'PRACTICAL',passed:false,attempts:2,scheduledExamId:'c'}]);
 });
});

describe('accompagnement du moniteur',()=>{
 it('occupe réellement l’agenda du moniteur, dans les deux sens, et se libère au report',async()=>{
  const training=await freshTraining(),day=nextDay++;
  const escort={instructorMembershipId:id.instructorMember,startsAt:when(day,9),endsAt:when(day,11)};
  const created=await create(training,'PRACTICAL',{startsAt:when(day,10),escort});expect(created.statusCode,created.body).toBe(201);
  const exam=created.json().data.exams[0];expect(exam.escort).toMatchObject({instructorMembershipId:id.instructorMember});expect(await heldBy(exam.id)).toBe(1);
  // Une leçon du même moniteur pendant l'accompagnement est refusée.
  const lesson=await call('POST','/lessons',lessonBody(commercial,school.policy,day,10),null,staff);expect(lesson.statusCode).toBe(409);
  // Et l'inverse : un accompagnement sur une leçon existante est refusé, sans rien créer.
  const otherDay=nextDay++,booked=await call('POST','/lessons',lessonBody(commercial,school.policy,otherDay,10),null,staff);expect(booked.statusCode,booked.body).toBe(201);
  const clash=await create(await freshTraining(),'PRACTICAL',{startsAt:when(otherDay,10),escort:{instructorMembershipId:id.instructorMember,startsAt:when(otherDay,10),endsAt:when(otherDay,12)}});
  expect(clash.statusCode).toBe(409);expect(clash.json().code).toBe('EXAM_ESCORT_CONFLICT');
  // Un moniteur non affecté à la formation n'accompagne pas.
  const unassigned=await create(await freshTraining(),'THEORY',{escort:{instructorMembershipId:id.otherInstructorMember,startsAt:when(nextDay,9),endsAt:when(nextDay,10)}});
  expect(unassigned.statusCode).toBe(422);expect(unassigned.json().code).toBe('INSTRUCTOR_NOT_ASSIGNED');
  // Retirer l'accompagnement libère le créneau.
  const cleared=await call('POST',`/exams/${exam.id}/update`,{...body({startsAt:when(day,10)}),escort:null},exam.version,staff);expect(cleared.statusCode,cleared.body).toBe(200);
  expect(await heldBy(exam.id)).toBe(0);
  expect((await call('POST','/lessons',lessonBody(commercial,school.policy,day,10),null,staff)).statusCode).toBe(201);
 });

 it('un report libère l’accompagnement de la tentative d’origine',async()=>{
  const training=await freshTraining(),day=nextDay++;
  const escort={instructorMembershipId:id.instructorMember,startsAt:when(day,13),endsAt:when(day,15)};
  const exam=(await create(training,'PRACTICAL',{startsAt:when(day,14),escort})).json().data.exams[0];expect(await heldBy(exam.id)).toBe(1);
  const postponed=await call('POST',`/exams/${exam.id}/postpone`,{operationId:randomUUID(),startsAt:when(nextDay++,14),timeZone:'Europe/Zurich'},exam.version,staff);
  expect(postponed.statusCode,postponed.body).toBe(200);expect(await heldBy(exam.id)).toBe(0);
  // Un examen sans accompagnement ne bloque rien.
  const nextId=postponed.json().data.exams.find((entry:{status:string})=>entry.status==='SCHEDULED').id;expect(await heldBy(nextId)).toBe(0);
 });
});

describe('listes transversales et moniteurs proposables',()=>{
 it('liste les résultats à renseigner pour le personnel et les examens à venir pour l’élève, chacun dans son périmètre',async()=>{
  const training=await freshTraining();
  const future=(await create(training,'THEORY')).json().data.exams[0],passed=(await create(training,'PRACTICAL')).json().data.exams[0];
  await toPast(passed.id);
  const waiting=await call('GET','/exams?filter=PENDING_RESULT',undefined,null,staff);expect(waiting.statusCode,waiting.body).toBe(200);conforms(validateList,waiting.json());
  const waitingIds=waiting.json().data.items.map((item:{exam:{id:string}})=>item.exam.id);
  expect(waitingIds).toContain(passed.id);expect(waitingIds).not.toContain(future.id);
  const item=waiting.json().data.items.find((entry:{exam:{id:string}})=>entry.exam.id===passed.id);
  expect(item.exam).toMatchObject({needsResult:true,attempt:1,kind:'PRACTICAL'});expect(item.learnerDisplayName).toBeTypeOf('string');
  // L'élève lit ses examens à venir ; la liste est celle de sa lecture.
  const upcoming=await call('GET','/exams?filter=UPCOMING',undefined,null,alice);expect(upcoming.statusCode,upcoming.body).toBe(200);conforms(validateList,upcoming.json());
  const upcomingIds=upcoming.json().data.items.map((entry:{exam:{id:string}})=>entry.exam.id);
  expect(upcomingIds).toContain(future.id);expect(upcomingIds).not.toContain(passed.id);
  expect((await call('GET','/exams?filter=ALL',undefined,null,alice)).statusCode).toBe(400);
  expect((await call('GET','/exams',undefined,null,alice)).statusCode).toBe(400);
 });

 it('propose à l’accompagnement les moniteurs affectés, au personnel seulement',async()=>{
  const training=await freshTraining();
  const staffState=await list(training,staff);
  expect(staffState.escortCandidates).toEqual([expect.objectContaining({membershipId:id.instructorMember})]);
  expect(staffState.escortCandidates[0].displayName).toBeTypeOf('string');
  expect((await list(training,alice)).escortCandidates).toEqual([]);
  expect((await list(training,admin)).escortCandidates.map((entry:{membershipId:string})=>entry.membershipId)).toEqual([id.instructorMember]);
 });
});

describe('isolement',()=>{
 it('les examens sont forcés par la sécurité par ligne',async()=>{
  const rows=await pool.query("SELECT relname,relrowsecurity AND relforcerowsecurity AS forced FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='drivy' AND relname IN('exam','exam_revision')");
  expect(rows.rows.map(row=>row.forced)).toEqual([true,true]);
  expect([403,404]).toContain((await call('GET',`/trainings/${randomUUID()}/exams`,undefined,null,alice)).statusCode);
 });
});
