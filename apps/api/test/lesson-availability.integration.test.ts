import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import type {Pool} from 'pg';
import {withActor} from '../src/database.js';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,slot,id,issuer,type Call} from './support/harness.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let validate:ReturnType<Ajv2020['compile']>;
const otherTraining=randomUUID(),otherOffering=randomUUID(),bobAssignment=randomUUID();

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);
 const contract=JSON.parse(await readFile(new URL('../contracts/lesson-availability.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 validate=ajv.compile({$ref:`${contract.$id}#/$defs/AvailabilityEnvelope`});
 await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
  VALUES($1,$2,'second-training','B',1,true,$3,$4,50,9000)`,[otherOffering,id.schoolA,school.curriculum,school.policy]);
 await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on)
  VALUES($1,$2,$3,$4,'second-training','ACTIVE',current_date)`,[otherTraining,id.schoolA,id.aliceLearner,otherOffering]);
 await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from)
  VALUES($1,$2,$3,$4,now()-interval '1 day'),($5,$2,$6,$7,now()-interval '1 day')`,
  [randomUUID(),id.schoolA,otherTraining,id.otherInstructorMember,bobAssignment,id.bobTraining,id.instructorMember]);
 const rules=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,
  weekdays:[1,2,3,4,5,6,7],localStart:'06:00',localEnd:'22:00',validFrom:new Date().toISOString().slice(0,10),validUntil:null},null,'demo-admin');
 expect(rules.statusCode,rules.body).toBe(201);
});
afterAll(async()=>{await app?.close();await pool?.end();});

function query(day:number,extra:Record<string,string|number>={}){
 return {trainingId:id.aliceTraining,instructorMembershipId:id.instructorMember,...slot(day),timeZone:'Europe/Zurich',bufferMinutes:10,...extra};
}
function route(value:Record<string,string|number>){
 return `/lessons/availability?${new URLSearchParams(Object.entries(value).map(([key,item])=>[key,String(item)]))}`;
}
async function available(day:number,extra:Record<string,string|number>={},subject='demo-instructor'){
 const response=await call('GET',route(query(day,extra)),undefined,null,subject);
 expect(response.statusCode,response.body).toBe(200);
 expect(validate(response.json()),JSON.stringify(validate.errors)).toBe(true);
 expect(response.headers['cache-control']).toBe('no-store');
 return response.json().data as {available:boolean;reasonCode:string|null};
}
async function create(day:number,extra:Record<string,unknown>={},subject='demo-instructor'){
 const response=await call('POST','/lessons',lessonBody(commercial,school.policy,day,8,extra),null,subject);
 expect(response.statusCode,response.body).toBe(201);return response.json().data;
}
async function counts(){return (await pool.query(`SELECT (SELECT count(*) FROM drivy.lesson) AS lessons,
 (SELECT count(*) FROM drivy.reservation) AS reservations,(SELECT count(*) FROM drivy.operation) AS operations,
 (SELECT count(*) FROM drivy.audit_event) AS audits,(SELECT count(*) FROM drivy.lesson_event_outbox) AS events`)).rows[0];}

describe('prévalidation anonyme du créneau avant le tarif',()=>{
 it('lit sans créer de réservation, opération, événement ou audit et valide le contrat strict',async()=>{
  const before=await counts();
  expect(await available(1)).toEqual({available:true,reasonCode:null});
  expect(await available(1,{},'demo-admin')).toEqual({available:true,reasonCode:null});
  expect(await counts()).toEqual(before);
 });

 it('respecte les bornes semi-ouvertes et le tampon de chaque réservation moniteur',async()=>{
  await create(2);
  expect(await available(2)).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
  expect(await available(2,slot(2,8,55))).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
  expect(await available(2,slot(2,9))).toEqual({available:true,reasonCode:null});
  expect(await available(2,{...slot(2,7,10),bufferMinutes:0})).toEqual({available:true,reasonCode:null});
  expect(await available(2,{...slot(2,7,10),bufferMinutes:1})).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
 });

 it('distingue une ouverture ou fermeture d’une occupation sans exposer le motif privé',async()=>{
  const closure=await call('POST','/closures',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,
   startsAt:slot(3,8,50).plannedStart,endsAt:slot(3,9,30).plannedStart,reason:'Motif privé synthétique'});
  expect(closure.statusCode,closure.body).toBe(201);
  expect(await available(3)).toEqual({available:true,reasonCode:null}); // Le tampon n'allonge pas le contrôle des ouvertures.
  expect(await available(3,slot(3,9))).toEqual({available:false,reasonCode:'SLOT_UNAVAILABLE'});
  expect(await available(3,slot(3,9,30))).toEqual({available:true,reasonCode:null});
  expect(await available(3,slot(3,2))).toEqual({available:false,reasonCode:'SLOT_UNAVAILABLE'});
 });

 it('détecte l’occupation de l’élève sur une autre formation invisible au moniteur',async()=>{
  const hidden=await create(4,{trainingId:otherTraining,instructorMembershipId:id.otherInstructorMember},'demo-admin');
  expect((await call('GET',`/lessons/${hidden.id}`)).statusCode).toBe(404);
  const listed=await call('GET',`/lessons?from=${encodeURIComponent(slot(4).plannedStart)}&to=${encodeURIComponent(slot(4).plannedEnd)}`);
  expect(listed.json().data.items).toEqual([]);
  expect(await available(4)).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
  // Le tampon du moniteur de l'autre formation n'occupe pas l'élève.
  expect(await available(4,slot(4,8,50))).toEqual({available:true,reasonCode:null});
 });

 it('détecte le rendez-vous du moniteur même après retrait de son accès à cette formation',async()=>{
  const hidden=await create(5,{trainingId:id.bobTraining},'demo-admin');
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[bobAssignment]);
  try{
   expect((await call('GET',`/lessons/${hidden.id}`)).statusCode).toBe(404);
   expect(await available(5)).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
  }finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[bobAssignment]);}
 });

 it('exclut seulement une leçon future modifiable de la même formation sans changer son tampon',async()=>{
  const original=await create(6);
  expect(await available(6)).toEqual({available:false,reasonCode:'SLOT_CONFLICT'});
  expect(await available(6,{excludeLessonId:original.id})).toEqual({available:true,reasonCode:null});
  expect((await call('GET',route(query(6,{excludeLessonId:original.id,bufferMinutes:0})))).json().code).toBe('INVALID_INTERVAL');
  const mismatch=await call('GET',route(query(6,{trainingId:otherTraining,instructorMembershipId:id.otherInstructorMember,excludeLessonId:original.id})),undefined,null,'demo-admin');
  expect(mismatch.statusCode).toBe(404);
  expect((await call('GET',route(query(6,{excludeLessonId:randomUUID()})))).statusCode).toBe(404);
  const cancelled=await call('POST',`/lessons/${original.id}/cancel`,{operationId:randomUUID(),reasonCode:'LEARNER_REQUEST'},original.version);
  expect(cancelled.statusCode,cancelled.body).toBe(200);
  expect(await available(6)).toEqual({available:true,reasonCode:null});
  expect((await call('GET',route(query(6,{excludeLessonId:original.id})))).json().code).toBe('LESSON_CLOSED');
 });

 it('reste indicatif : un rendez-vous confirmé ensuite empêche la création',async()=>{
  expect(await available(7)).toEqual({available:true,reasonCode:null});
  await create(7);
  const before=await counts();
  const refused=await call('POST','/lessons',lessonBody(commercial,school.policy,7));
  expect(refused.statusCode).toBe(409);expect(refused.json().code).toBe('SLOT_CONFLICT');
  expect(await counts()).toEqual(before);
 });

 it('revérifie les droits sans ouvrir la projection aux élèves, moniteurs non affectés ou autres écoles',async()=>{
  expect((await call('GET',route(query(8)),undefined,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('GET',route(query(8)),undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('GET',route(query(8,{trainingId:id.foreignTraining})))).statusCode).toBe(404);
  expect((await call('GET',route(query(8)),undefined,null,'demo-foreign')).statusCode).toBe(403);
  await pool.query(`UPDATE drivy.instructor_assignment SET valid_until=now()-interval '1 second' WHERE id=$1`,[id.assignment]);
  try{expect((await call('GET',route(query(8)))).statusCode).toBe(404);}
  finally{await pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1',[id.assignment]);}
 });

 it('refuse aussi l’accès direct à la fonction SQL privilégiée hors du périmètre autorisé',async()=>{
  const value=query(8);
  await expect(withActor(pool,{issuer,subject:'demo-alice'},id.schoolA,db=>db.query(
   'SELECT drivy.lesson_slot_conflict($1,$2,$3,$4,$5,$6,$7)',
   [id.schoolA,value.trainingId,value.instructorMembershipId,value.plannedStart,value.plannedEnd,value.bufferMinutes,null])))
   .rejects.toMatchObject({code:'42501'});
  await expect(withActor(pool,{issuer,subject:'demo-instructor'},id.schoolA,db=>db.query(
   'SELECT drivy.lesson_slot_conflict($1,$2,$3,$4,$5,$6,$7)',
   [id.schoolB,value.trainingId,value.instructorMembershipId,value.plannedStart,value.plannedEnd,value.bufferMinutes,null])))
   .rejects.toMatchObject({code:'42501'});
  const hidden=(await pool.query<{id:string}>('SELECT id FROM drivy.lesson WHERE training_id=$1',[otherTraining])).rows[0]!;
  await expect(withActor(pool,{issuer,subject:'demo-instructor'},id.schoolA,db=>db.query(
   'SELECT drivy.lesson_slot_conflict($1,$2,$3,$4,$5,$6,$7)',
   [id.schoolA,value.trainingId,value.instructorMembershipId,value.plannedStart,value.plannedEnd,value.bufferMinutes,hidden.id])))
   .rejects.toMatchObject({code:'42501'});
 });

 it('refuse les paramètres incomplets, fuseaux divergents, intervalles invalides et passages de minuit local',async()=>{
  const value=query(9),{bufferMinutes:_,...missing}=value;
  expect((await call('GET',route(missing))).statusCode).toBe(400);
  expect((await call('GET',route({...value,bufferMinutes:241}))).statusCode).toBe(400);
  expect((await call('GET',route({...value,agreedPriceCents:1}))).statusCode).toBe(400);
  expect((await call('GET',route({...value,timeZone:'UTC'}))).json().code).toBe('INVALID_TIME_ZONE');
  expect((await call('GET',route(query(-1)))).json().code).toBe('INVALID_INTERVAL');
  expect((await call('GET',route({...value,plannedEnd:value.plannedStart}))).json().code).toBe('INVALID_INTERVAL');
  expect((await call('GET',route({...value,plannedEnd:new Date(Date.parse(value.plannedStart)+481*60_000).toISOString()}))).json().code).toBe('INVALID_INTERVAL');
  const night=slot(9,21,30);
  expect((await call('GET',route({...value,...night,plannedEnd:new Date(Date.parse(night.plannedStart)+3*60*60_000).toISOString()}))).json().code).toBe('INVALID_INTERVAL');
 });
});
