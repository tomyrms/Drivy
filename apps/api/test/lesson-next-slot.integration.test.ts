import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import type {Pool} from 'pg';
import {freshDatabase,harness,prepareCommercial,prepareSchool,lessonBody,id,type Call} from './support/harness.js';
import {fromWallClock,nextCivilDay,wallClock} from '../src/next-slot.js';

let pool:Pool,call:Call,app:Awaited<ReturnType<typeof harness>>['app'];
let school:Awaited<ReturnType<typeof prepareSchool>>,commercial:Awaited<ReturnType<typeof prepareCommercial>>;
let validate:ReturnType<Ajv2020['compile']>;
const zone='Europe/Zurich',otherTraining=randomUUID(),otherOffering=randomUUID();
/** Jour civil de l'école dans `offset` jours ; heures murales synthétiques de ce jour. */
function day(offset:number){let value=wallClock(new Date(),zone).date;for(let i=0;i<offset;i++)value=nextCivilDay(value);return value;}
const wall=(date:string,hour:number,minute=0)=>fromWallClock(date,hour*60+minute,zone)!.toISOString();

beforeAll(async()=>{
 pool=await freshDatabase();({call,app}=await harness(pool));school=await prepareSchool(pool);commercial=await prepareCommercial(call);
 const contract=JSON.parse(await readFile(new URL('../contracts/lesson-next-slot.json',import.meta.url),'utf8')) as {$id:string};
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});ajv.addSchema(contract);
 validate=ajv.compile({$ref:`${contract.$id}#/$defs/NextSlotEnvelope`});
 await pool.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
  VALUES($1,$2,'second-training','B',1,true,$3,$4,50,9000)`,[otherOffering,id.schoolA,school.curriculum,school.policy]);
 await pool.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on)
  VALUES($1,$2,$3,$4,'second-training','ACTIVE',current_date)`,[otherTraining,id.schoolA,id.aliceLearner,otherOffering]);
 await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from)
  VALUES($1,$2,$3,$4,now()-interval '1 day')`,[randomUUID(),id.schoolA,otherTraining,id.otherInstructorMember]);
 const rules=await call('POST','/availability-rules',{operationId:randomUUID(),instructorMembershipId:id.otherInstructorMember,
  weekdays:[1,2,3,4,5,6,7],localStart:'06:00',localEnd:'22:00',validFrom:new Date().toISOString().slice(0,10),validUntil:null},null,'demo-admin');
 expect(rules.statusCode,rules.body).toBe(201);
});
afterAll(async()=>{await app?.close();await pool?.end();});

function route(extra:Record<string,string|number>={}){
 const value={trainingId:id.aliceTraining,instructorMembershipId:id.instructorMember,durationMinutes:50,bufferMinutes:10,timeZone:zone,...extra};
 return `/lessons/next-slot?${new URLSearchParams(Object.entries(value).map(([key,item])=>[key,String(item)]))}`;
}
async function next(extra:Record<string,string|number>={},subject='demo-instructor'){
 const response=await call('GET',route(extra),undefined,null,subject);
 expect(response.statusCode,response.body).toBe(200);
 expect(validate(response.json()),JSON.stringify(validate.errors)).toBe(true);
 expect(response.headers['cache-control']).toBe('no-store');
 return response.json().data as {slot:{plannedStart:string;plannedEnd:string}|null;searchedThrough:string;timeZone:string};
}
async function counts(){return (await pool.query(`SELECT (SELECT count(*) FROM drivy.lesson) AS lessons,
 (SELECT count(*) FROM drivy.reservation) AS reservations,(SELECT count(*) FROM drivy.operation) AS operations,
 (SELECT count(*) FROM drivy.audit_event) AS audits`)).rows[0];}

describe('prochain créneau libre à l’ouverture de « Planifier une leçon »',()=>{
 it('propose un créneau futur dans les ouvertures, sans rien écrire, et la prévalidation le confirme libre',async()=>{
  const before=await counts();
  const found=await next();
  expect(await counts()).toEqual(before);
  const start=Date.parse(found.slot!.plannedStart),end=Date.parse(found.slot!.plannedEnd);
  expect(start).toBeGreaterThan(Date.now());
  expect(end-start).toBe(50*60_000);
  const opens=wallClock(new Date(start),zone),closes=wallClock(new Date(end),zone);
  expect(opens.date).toBe(closes.date);
  expect(opens.minutes).toBeGreaterThanOrEqual(6*60);
  expect(closes.minutes).toBeLessThanOrEqual(22*60);
  expect(found.timeZone).toBe(zone);
  const check=await call('GET',`/lessons/availability?${new URLSearchParams({trainingId:id.aliceTraining,instructorMembershipId:id.instructorMember,
   plannedStart:found.slot!.plannedStart,plannedEnd:found.slot!.plannedEnd,timeZone:zone,bufferMinutes:'10'})}`);
  expect(check.json().data).toEqual({available:true,reasonCode:null});
  expect((await next({},'demo-admin')).slot).not.toBeNull();
 });

 it('évite l’occupation privée de l’élève, la leçon du moniteur avec son tampon, puis sa fermeture',async()=>{
  const date=day(3),from=wall(date,6);
  expect((await next({from})).slot!.plannedStart).toBe(wall(date,6));
  // Autre formation de l'élève, autre moniteur : invisible au moniteur, mais l'élève est occupé 6:00–6:50.
  const hidden=await call('POST','/lessons',lessonBody(commercial,school.policy,3,8,{trainingId:otherTraining,instructorMembershipId:id.otherInstructorMember,
   plannedStart:wall(date,6),plannedEnd:wall(date,6,50)}),null,'demo-admin');
  expect(hidden.statusCode,hidden.body).toBe(201);
  expect((await next({from})).slot!.plannedStart).toBe(wall(date,7));
  const own=await call('POST','/lessons',lessonBody(commercial,school.policy,3,8,{plannedStart:wall(date,7),plannedEnd:wall(date,7,50)}));
  expect(own.statusCode,own.body).toBe(201);
  expect((await next({from})).slot!.plannedStart).toBe(wall(date,8)); // 7:50 + tampon de 10 minutes
  expect((await next({from,bufferMinutes:0})).slot!.plannedStart).toBe(wall(date,8));
  const closure=await call('POST','/closures',{operationId:randomUUID(),instructorMembershipId:id.instructorMember,
   startsAt:wall(date,8),endsAt:wall(date,9,30),reason:'Motif privé synthétique'});
  expect(closure.statusCode,closure.body).toBe(201);
  const found=await next({from});
  expect(found.slot!.plannedStart).toBe(wall(date,9,30));
  expect(JSON.stringify(found)).not.toContain('Motif');
 });

 it('signale explicitement l’absence de créneau et la dernière date examinée',async()=>{
  const date=day(5),from=wall(date,21,20);
  const found=await next({from,days:1});
  expect(found).toEqual({slot:null,searchedThrough:date,timeZone:zone});
  const wider=await next({from:wall(nextCivilDay(date),0),days:1});
  expect(wider.slot!.plannedStart).toBe(wall(nextCivilDay(date),6));
 });

 it('relit les droits et refuse les paramètres invalides',async()=>{
  expect((await call('GET',route(),undefined,null,'demo-alice')).statusCode).toBe(403);
  expect((await call('GET',route(),undefined,null,'demo-other-instructor')).statusCode).toBe(404);
  expect((await call('GET',route({trainingId:id.foreignTraining}))).statusCode).toBe(404);
  expect((await call('GET',route(),undefined,null,'demo-foreign')).statusCode).toBe(403);
  expect((await call('GET',route({timeZone:'UTC'}))).json().code).toBe('INVALID_TIME_ZONE');
  expect((await call('GET',route({days:32}))).statusCode).toBe(400);
  expect((await call('GET',route({durationMinutes:481}))).statusCode).toBe(400);
  expect((await call('GET',route({stepMinutes:1}))).statusCode).toBe(400);
  expect((await call('GET',route({unknown:1}))).statusCode).toBe(400);
 });
});
