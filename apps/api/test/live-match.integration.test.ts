import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterEach,beforeAll,beforeEach,describe,expect,it,vi} from 'vitest';
import type {Pool} from 'pg';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {freshDatabase,id,issuer} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';
import {buildApp} from '../src/app.js';
import type {LiveMatcher,LiveMatchInput} from '../src/live-matching.js';

let pool:Pool,h:CaptureHarness,trip:Awaited<ReturnType<CaptureHarness['startTrip']>>;
let validate:(value:unknown)=>boolean,validateRequest:(value:unknown)=>boolean;
const apps:ReturnType<typeof buildApp>[]=[];
// Quatre mesures à 25 m l'une de l'autre : assez de mouvement pour que la fenêtre parte au moteur.
const body=():LiveMatchInput=>{const now=Date.now();return {segmentId:randomUUID(),points:Array.from({length:4},(_,i)=>({sequence:i,elapsedMs:i*1000,capturedAt:new Date(now-3000+i*1000).toISOString(),latitude:46+i*25/111_195,longitude:7,accuracyMeters:5,speed:11}))};};
const road:LiveMatcher=async points=>({code:'Ok',matchings:[{confidence:0.95,geometry:{type:'LineString',coordinates:points.map(p=>[p.longitude,p.latitude])}}],tracepoints:points.map(p=>({location:[p.longitude,p.latitude],matchings_index:0,alternatives_count:0}))});
const url=(school=id.schoolA as string,capture=trip.capture.id)=>`/v1/schools/${school}/captures/${capture}/live-match`;
const appFor=(matcher:LiveMatcher|undefined=road,subject='demo-instructor')=>{const app=buildApp({pool,cursorSecret:'live-match-test-secret-32-characters',verifyToken:async()=>({issuer,subject}),liveMatcher:matcher});apps.push(app);return app;};
const post=(app:ReturnType<typeof buildApp>,payload:unknown=body(),path=url())=>app.inject({method:'POST',url:path,payload:payload as object});
// Fixture de propriété incohérente sans désactiver RLS ni les triggers: capture liée à une autre leçon.
// Déplacer la leçon d'une capture active est déjà interdit par PostgreSQL.
const rebindToOtherAuthor=async()=>{
 const lesson=randomUUID();
 await pool.query(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  SELECT $2,school_id,training_id,learner_id,learner_person_id,$3,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection FROM drivy.lesson WHERE id=$1`,[trip.lesson,lesson,id.otherInstructorMember]);
 await pool.query('UPDATE drivy.capture_session SET lesson_id=$2 WHERE id=$1',[trip.capture.id,lesson]);
};
const snapshot=async()=>{
 const result=await pool.query(`SELECT (SELECT count(*) FROM drivy.capture_chunk) chunks,(SELECT count(*) FROM drivy.capture_matched_route) routes,(SELECT count(*) FROM drivy.operation) operations,(SELECT count(*) FROM drivy.audit_event) audits,(SELECT row_to_json(c) FROM drivy.capture_session c WHERE c.id=$1) capture`,[trip.capture.id]);return result.rows[0];
};
beforeAll(async()=>{
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});
 const schema=JSON.parse(await readFile(new URL('../contracts/live-match.json',import.meta.url),'utf8')) as {$id:string};ajv.addSchema(schema);
 validate=ajv.compile({$ref:`${schema.$id}#/$defs/LiveMatchEnvelope`}) as (value:unknown)=>boolean;
 validateRequest=ajv.compile({$ref:`${schema.$id}#/$defs/LiveMatchRequest`}) as (value:unknown)=>boolean;
});
beforeEach(async()=>{
 pool=await freshDatabase();h=await captureHarness(pool);
 trip=await h.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
 await pool.query("UPDATE drivy.capture_session SET authorized_at=authorized_at-interval '1 minute',expires_at=expires_at-interval '1 minute' WHERE id=$1",[trip.capture.id]);
},60_000);
afterEach(async()=>{for(const app of apps.splice(0))await app.close();await h?.app.close();await pool?.end();vi.restoreAllMocks();});

describe('extension live-match, PostgreSQL réel',()=>{
 it('retourne la position et le tronçon recalés de la dernière mesure sans aucune écriture',async()=>{
  const app=appFor(),input=body(),before=await snapshot();expect(validateRequest(input)).toBe(true);
  const result=await post(app,input);
  expect(result.statusCode).toBe(200);expect(validate(result.json())).toBe(true);
  const latitude=Math.round(input.points[3]!.latitude*1e7)/1e7;
  expect(result.json().data).toMatchObject({status:'MATCHED',segmentId:input.segmentId,sequence:3,elapsedMs:3000,position:{latitude,longitude:7},confidence:0.95});
  expect(result.json().data.route.anchors.map((a:number[])=>a[0])).toEqual([0,1,2,3]);
  expect(result.headers['cache-control']).toBe('no-store');expect(await snapshot()).toEqual(before);
 });
 it('authentifie avec le vérificateur réel avant tout traitement',async()=>{
  const result=await h.app.inject({method:'POST',url:url(),payload:body()});expect(result.statusCode).toBe(401);
 });
 it.each(['demo-admin','demo-alice','demo-other-instructor','demo-foreign'])('refuse %s sans appel moteur',async subject=>{
  let calls=0;const app=appFor(async(...args)=>{calls++;return road(...args);},subject);
  const result=await post(app);expect([403,404]).toContain(result.statusCode);expect(calls).toBe(0);expect(result.json()).not.toHaveProperty('data');
 });
 it('ne peut traverser école ou capture, même pour la même personne',async()=>{
  const result=await post(appFor(),body(),url(id.schoolB));expect(result.statusCode).toBe(404);
  const missing=await post(appFor(),body(),url(id.schoolA,randomUUID()));expect(missing.statusCode).toBe(404);
 });
 it.each(['STOPPED','REVOKED','EXPIRED'] as const)('refuse une capture %s',async state=>{
  await pool.query('UPDATE drivy.capture_session SET capture_state=$2 WHERE id=$1',[trip.capture.id,state]);
  let calls=0;const result=await post(appFor(async(...args)=>{calls++;return road(...args);}));expect(result.statusCode).toBe(404);expect(calls).toBe(0);
 });
 it('refuse une capture expirée encore marquée AUTHORIZED',async()=>{
  await pool.query("UPDATE drivy.capture_session SET expires_at=now()-interval '1 second' WHERE id=$1",[trip.capture.id]);
  expect((await post(appFor())).statusCode).toBe(404);
 });
 it('refuse une borne de révocation même si état reste AUTHORIZED',async()=>{
  await pool.query('UPDATE drivy.capture_session SET cutoff_at=now() WHERE id=$1',[trip.capture.id]);expect((await post(appFor())).statusCode).toBe(404);
 });
 it('refuse les mesures antérieures à l’autorisation sans les envoyer au moteur',async()=>{
  const b=body();for(const p of b.points)p.capturedAt=new Date(Date.now()-120000+p.elapsedMs).toISOString();
  expect((await post(appFor(),b)).statusCode).toBe(400);
 });
 it('ne prend pas les droits du propriétaire lorsque la leçon a changé d’auteur',async()=>{
  await rebindToOtherAuthor();expect((await post(appFor())).statusCode).toBe(404);
 });
 it.each(['capture','membership','role','assignment','author','person','expiry','choice'] as const)('relit les droits après moteur: %s perdu',async loss=>{
  let calls=0;
  const app=appFor(async(...args)=>{
   calls++;
   if(loss==='capture')await pool.query("UPDATE drivy.capture_session SET capture_state='REVOKED',cutoff_at=now() WHERE id=$1",[trip.capture.id]);
   if(loss==='membership')await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
   if(loss==='role')await pool.query("UPDATE drivy.membership SET roles='{ADMIN}' WHERE id=$1",[id.instructorMember]);
   if(loss==='assignment')await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1',[id.assignment]);
   if(loss==='author')await rebindToOtherAuthor();
   if(loss==='person')await pool.query("UPDATE drivy.person SET status='SUSPENDED' WHERE id=$1",[id.instructor]);
   if(loss==='expiry')await pool.query("UPDATE drivy.capture_session SET expires_at=now()-interval '1 millisecond' WHERE id=$1",[trip.capture.id]);
   if(loss==='choice'){
    const choice=await h.call('POST',`/learners/${id.aliceLearner}/recording-choice`,{operationId:randomUUID(),lessonId:trip.lesson,status:'REFUSED',noticeVersionId:h.notice,source:'SELF'},undefined,'demo-alice');
    expect(choice.statusCode).toBe(200);
   }
   return road(...args);
  });
  const result=await post(app);expect(calls).toBe(1);expect([403,404]).toContain(result.statusCode);expect(result.json()).not.toHaveProperty('data');
 });
 it('relit également les droits après erreur du moteur',async()=>{
  const result=await post(appFor(async()=>{await pool.query("UPDATE drivy.capture_session SET capture_state='STOPPED' WHERE id=$1",[trip.capture.id]);throw new Error('upstream private details');}));
  expect(result.statusCode).toBe(404);expect(result.body).not.toContain('upstream');
 });
 it('refuse corps invalide et trop volumineux sans exposer valeurs ni appeler OSRM',async()=>{
  let calls=0;const app=appFor(async(...args)=>{calls++;return road(...args);});const b=body();b.points[0]!.latitude=123.456789;
  const result=await post(app,b);expect(result.statusCode).toBe(400);expect(result.body).not.toContain('123.456789');
  expect((await post(app,{...body(),extra:'x'.repeat(20000)})).statusCode).toBe(413);expect(calls).toBe(0);
 });
 it('absence de moteur et exception sensible restent UNAVAILABLE sans journal ni écriture',async()=>{
  const before=await snapshot();
  const unavailable=buildApp({pool,cursorSecret:'live-match-test-secret-32-characters',verifyToken:async()=>({issuer,subject:'demo-instructor'})});apps.push(unavailable);
  const first=await post(unavailable);expect(first.statusCode).toBe(200);expect(first.json().data.status).toBe('UNAVAILABLE');expect(validate(first.json())).toBe(true);
  const app=appFor(async()=>{throw new Error('http://private.example/match/7.123456,46.123456');}),errorLog=vi.spyOn(app.log,'error');
  const second=await post(app);expect(second.statusCode).toBe(200);expect(validate(second.json())).toBe(true);expect(second.json().data.status).toBe('UNAVAILABLE');expect(second.body).not.toContain('7.123456');expect(errorLog).not.toHaveBeenCalled();expect(await snapshot()).toEqual(before);
 });
 it('borne concurrence et cadence par identité malgré changement de segment ou capture',async()=>{
  let enter!:()=>void,finish!:(value:unknown)=>void;const entered=new Promise<void>(resolve=>{enter=resolve;});
  const app=appFor(async()=>{enter();return new Promise(resolve=>{finish=resolve;});});
  const b=body(),first=post(app,b);await entered;
  const concurrent=await post(app,body(),url(id.schoolA,randomUUID()));expect(concurrent.statusCode).toBe(429);expect(concurrent.headers['retry-after']).toBe('2');
  finish(await road(b.points,new AbortController().signal));expect((await first).statusCode).toBe(200);
  expect((await post(app)).statusCode).toBe(429);
 });
});
