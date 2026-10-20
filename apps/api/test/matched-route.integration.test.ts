import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {Ajv2020} from 'ajv/dist/2020.js';
import {fullFormats} from 'ajv-formats/dist/formats.js';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';
import {canonicalCaptureJSON,trackContentHash} from '../src/capture-crypto.js';
import {encryptRoute} from '../src/matched-routes.js';
import {MapMatchingError} from '../src/map-matching-client.js';
import {decodePolyline,type MatcherPoint,type MatcherResult} from '../src/track-matching.js';

/** Couche recalée d'un trajet privé (extension GET …/matched-route), sur PostgreSQL réel avec un moteur factice. */
const M=1/111_320;
let pool:Pool,h:CaptureHarness,calls=0,mode:'road'|'down'='road',validate:(value:unknown)=>boolean;
type Trip=Awaited<ReturnType<CaptureHarness['startTrip']>>;
let trip:Trip,segment:string,other:Trip;

/** Route est-ouest à trois mètres au nord des mesures : le moteur factice y accroche chaque point. */
const road=async(points:MatcherPoint[]):Promise<MatcherResult>=>{
 calls++;if(mode==='down')throw new MapMatchingError('PROVIDER_UNAVAILABLE');
 const north=points[0]!.latitude+3*M;
 return {matchings:[{confidence:0.92,geometry:[[north,points[0]!.longitude],[north,points.at(-1)!.longitude]]}],tracepoints:points.map(p=>({matchingIndex:0,latitude:north,longitude:p.longitude}))};
};
/** Soixante mesures synthétiques, une par seconde, quinze mètres plus à l'est à chaque fois. Le trajet est antidaté de dix minutes pour qu'elles soient toutes passées. */
async function drive(t:Trip){
 await pool.query("UPDATE drivy.capture_session SET authorized_at=authorized_at-interval '10 minutes',expires_at=expires_at-interval '10 minutes' WHERE id=$1",[t.capture.id]);
 const started=Date.now()-9*60_000,segmentId=randomUUID();
 const points=Array.from({length:60},(_,sequence)=>({sequence,elapsedMs:sequence*1000,capturedAt:new Date(started+sequence*1000).toISOString(),latitude:46.99,longitude:6.9+sequence*15*M,accuracyMeters:5}));
 const content={segmentIndex:0,segmentStartedAt:new Date(started).toISOString(),segmentStartReason:'START' as const,points};
 const upload=await h.call('PUT',`/captures/${t.capture.id}/segments/${segmentId}/chunks/0`,{operationId:randomUUID(),...content,contentHash:trackContentHash(content),signedUploadAuthorization:t.uploadAuthorization},undefined,t.party.instructorSubject);
 if(upload.statusCode!==200)throw new Error(upload.body);
 const manifest=[{segmentId,segmentIndex:0,expectedChunkIndices:[0],expectedPointCount:60,lastSequence:59,endReason:'STOP'}];
 const stop=await h.call('POST',`/captures/${t.capture.id}/stop`,{operationId:randomUUID(),stoppedAt:new Date().toISOString(),reason:'USER_STOP',segments:manifest,localCollectorStopped:true},undefined,t.party.instructorSubject);
 if(stop.statusCode!==200)throw new Error(stop.body);
 const finalized=await h.call('POST',`/captures/${t.capture.id}/finalize`,{operationId:randomUUID(),segments:manifest,allowPartial:false},stop.json().data.version,t.party.instructorSubject);
 if(finalized.statusCode!==200)throw new Error(finalized.body);
 return {segmentId,started,points};
}
const get=(capture:string,subject='demo-instructor')=>h.call('GET',`/captures/${capture}/matched-route`,undefined,undefined,subject);
/** Le calcul tourne hors de la requête : le client relit, comme l'app. */
async function settled(capture:string,subject='demo-instructor'){
 for(let attempt=0;attempt<200;attempt++){const response=await get(capture,subject);if(response.statusCode!==200||response.json().data.status!=='PENDING')return response;await new Promise(resolve=>setTimeout(resolve,25));}
 throw new Error('Le recalage ne se termine pas.');
}
const row=async(capture:string)=>(await pool.query<{status:string;attempts:number;failure_code:string|null;span_count:number;encrypted_route:Buffer|null;provider:string|null;retry_after:Date|null}>('SELECT status,attempts,failure_code,span_count,encrypted_route,provider,retry_after FROM drivy.capture_matched_route WHERE capture_id=$1',[capture])).rows[0];

beforeAll(async()=>{
 pool=await freshDatabase();
 h=await captureHarness(pool,{mapMatching:{provider:'osrm',minimumConfidence:0.5},mapMatcher:road});
 const ajv=new Ajv2020({strict:false,allErrors:true,formats:fullFormats});
 const contract=JSON.parse(await readFile(new URL('../contracts/matched-route.json',import.meta.url),'utf8')) as {$id:string};ajv.addSchema(contract);
 validate=ajv.compile({$ref:`${contract.$id}#/$defs/MatchedRoute`}) as (value:unknown)=>boolean;
 trip=await h.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
},60_000);
afterAll(async()=>{await h?.app.close();await pool?.end();});

describe('tracé recalé sur la route (extension GET /captures/:id/matched-route)',()=>{
 it('avant la finalisation : rien à proposer, et rien n’est calculé',async()=>{
  const early=await get(trip.capture.id);expect(early.statusCode,early.body).toBe(200);
  expect(early.json().data).toMatchObject({captureId:trip.capture.id,status:'UNAVAILABLE',provider:null,spans:[]});
  expect(validate(early.json().data)).toBe(true);expect(calls).toBe(0);expect(await row(trip.capture.id)).toBeUndefined();
 });
 it('première lecture après la leçon : un seul calcul, même pour deux lectures simultanées, puis le résultat',async()=>{
  segment=(await drive(trip)).segmentId;
  const [first,second]=await Promise.all([get(trip.capture.id),get(trip.capture.id)]);
  expect(first.statusCode,first.body).toBe(200);expect(second.statusCode,second.body).toBe(200);
  expect([first.json().data.status,second.json().data.status].every(status=>['PENDING','READY'].includes(status))).toBe(true);
  const ready=await settled(trip.capture.id);expect(ready.statusCode,ready.body).toBe(200);
  const data=ready.json().data;expect(validate(data)).toBe(true);
  expect(Object.keys(data).sort()).toEqual(['algorithmVersion','captureId','generatedAt','provider','reconstructionVersion','spans','status']);
  // L'arrêt et la finalisation ont déjà fait avancer la version des mesures : seule la base la connaît.
  const version=(await pool.query<{reconstruction_version:number}>('SELECT reconstruction_version FROM drivy.capture_session WHERE id=$1',[trip.capture.id])).rows[0]!.reconstruction_version;
  expect(data).toMatchObject({status:'READY',provider:'osrm',algorithmVersion:2,reconstructionVersion:version});
  expect(data.spans).toHaveLength(1);
  const span=data.spans[0];expect(span).toMatchObject({segmentId:segment,firstSequence:0,lastSequence:59,confidence:0.92});
  const geometry=decodePolyline(span.geometry);expect(geometry.length).toBeGreaterThanOrEqual(2);
  // La géométrie est celle de la route (3 m au nord), jamais celle des mesures.
  expect(geometry.every(point=>Math.abs(point[0]-(46.99+3*M))<2e-6)).toBe(true);
  expect(span.anchors[0]).toEqual([0,0]);expect(span.anchors.at(-1)[0]).toBe(59);
  for(let i=1;i<span.anchors.length;i++){expect(span.anchors[i][0]).toBeGreaterThan(span.anchors[i-1][0]);expect(span.anchors[i][1]).toBeGreaterThanOrEqual(span.anchors[i-1][1]);}
  expect(calls).toBe(1);
  expect(ready.headers['cache-control']).toBe('no-store');
  // Relire ne recalcule rien.
  expect((await get(trip.capture.id)).json().data.status).toBe('READY');expect(calls).toBe(1);
 });
 it('le résultat est chiffré au repos et le replay mesuré reste inchangé',async()=>{
  const stored=await row(trip.capture.id);
  expect(stored).toMatchObject({status:'READY',attempts:1,failure_code:null,span_count:1,provider:'osrm'});
  expect(stored!.encrypted_route!.includes('geometry')).toBe(false);expect(stored!.encrypted_route!.includes(segment)).toBe(false);
  const replay=await h.call('GET',`/captures/${trip.capture.id}/replay?limit=100`);expect(replay.statusCode,replay.body).toBe(200);
  expect(Object.keys(replay.json().data).sort()).toEqual(['captureId','generatedAt','geometrySnapshotId','nextCursor','observations','publicationState','quality','reportRevisionId','segments']);
  // Les mesures sont celles qui ont été envoyées : latitude 46,99, pas celle de la route.
  expect(replay.json().data.segments[0].points.every((point:{latitude:number})=>point.latitude===46.99)).toBe(true);
 });
 it('mêmes droits que le trajet : autre moniteur et école étrangère 404, élève seulement une fois le trajet partagé, administration en lecture',async()=>{
  expect((await get(trip.capture.id,'demo-other-instructor')).statusCode).toBe(404);
  expect((await get(trip.capture.id,'demo-foreign')).statusCode).toBeGreaterThanOrEqual(403);
  expect((await get(trip.capture.id,'demo-alice')).statusCode).toBe(404);
  await pool.query("UPDATE drivy.lesson SET status='COMPLETED',actual_start=now()-interval '2 minutes',actual_end=now()-interval '1 minute' WHERE id=$1",[trip.lesson]);
  const learner=await get(trip.capture.id,'demo-alice');expect(learner.statusCode,learner.body).toBe(200);expect(learner.json().data.spans).toHaveLength(1);
  const admin=await get(trip.capture.id,'demo-admin');expect(admin.statusCode,admin.body).toBe(200);expect(admin.json().data.status).toBe('READY');
  expect((await get(randomUUID())).statusCode).toBe(404);
  expect((await h.call('GET',`/captures/${trip.capture.id}/matched-route?limit=1`)).statusCode).toBe(400);
  expect(calls).toBe(1);
 });
 it('moteur en panne : le replay reste lisible, l’échec ne garde qu’un code, et un nouvel essai attend son heure',async()=>{
  await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,'2026-01-01T00:00:00Z')",[randomUUID(),id.schoolA,id.bobTraining,id.otherInstructorMember]);
  other=await h.startTrip({instructorSubject:'demo-other-instructor',instructorMember:id.otherInstructorMember,learnerSubject:'demo-bob',learnerId:id.bobLearner,learnerPerson:id.bob,trainingId:id.bobTraining});
  await drive(other);
  mode='down';const before=calls;
  const failed=await settled(other.capture.id,'demo-other-instructor');expect(failed.statusCode,failed.body).toBe(200);
  expect(failed.json().data).toMatchObject({status:'UNAVAILABLE',spans:[],provider:null});expect(validate(failed.json().data)).toBe(true);
  expect(calls).toBe(before+1);
  const stored=await row(other.capture.id);
  expect(stored).toMatchObject({status:'FAILED',attempts:1,failure_code:'PROVIDER_UNAVAILABLE',span_count:0,encrypted_route:null});
  expect(stored!.retry_after!.getTime()).toBeGreaterThan(Date.now());
  // Tant que l'essai suivant n'est pas dû, relire ne sollicite pas le moteur.
  expect((await get(other.capture.id,'demo-other-instructor')).json().data.status).toBe('UNAVAILABLE');expect(calls).toBe(before+1);
  const replay=await h.call('GET',`/captures/${other.capture.id}/replay?limit=100`,undefined,undefined,'demo-other-instructor');
  expect(replay.statusCode,replay.body).toBe(200);expect(replay.json().data.segments[0].points).toHaveLength(60);
  // Le moteur revient et l'essai est dû : la lecture suivante relance le calcul.
  mode='road';await pool.query("UPDATE drivy.capture_matched_route SET retry_after=now()-interval '1 second' WHERE capture_id=$1",[other.capture.id]);
  const recovered=await settled(other.capture.id,'demo-other-instructor');
  expect(recovered.json().data).toMatchObject({status:'READY',provider:'osrm'});expect(recovered.json().data.spans).toHaveLength(1);
  expect(await row(other.capture.id)).toMatchObject({status:'READY',attempts:2,failure_code:null});
 });
 it('un calcul abandonné en cours de route est repris après l’expiration de son bail',async()=>{
  await pool.query("UPDATE drivy.capture_matched_route SET status='PROCESSING',lease_id=gen_random_uuid(),lease_until=now()+interval '1 minute',encrypted_route=NULL,key_id=NULL,span_count=0 WHERE capture_id=$1",[other.capture.id]);
  const before=calls;
  expect((await get(other.capture.id,'demo-other-instructor')).json().data.status).toBe('PENDING');expect(calls).toBe(before);
  await pool.query("UPDATE drivy.capture_matched_route SET lease_until=now()-interval '1 second' WHERE capture_id=$1",[other.capture.id]);
  expect((await settled(other.capture.id,'demo-other-instructor')).json().data.status).toBe('READY');expect(calls).toBe(before+1);
 });
 it.each((['mapbox',null] as const).flatMap(provider=>(['READY','EMPTY','FAILED','PROCESSING'] as const).map(status=>({provider,status}))))('un ancien résultat $provider/$status est recalculé par OSRM sans modifier les chunks',async({provider,status})=>{
  const chunks=await pool.query('SELECT * FROM drivy.capture_chunk WHERE capture_id=$1 ORDER BY segment_index,chunk_index',[trip.capture.id]);
  const before=calls;
  await pool.query(`UPDATE drivy.capture_matched_route SET provider=$3,status=$2,
   encrypted_route=CASE WHEN $2='READY' THEN encrypted_route END,key_id=CASE WHEN $2='READY' THEN key_id END,
   lease_id=CASE WHEN $2='PROCESSING' THEN gen_random_uuid() END,lease_until=CASE WHEN $2='PROCESSING' THEN now()+interval '10 minutes' END,
   retry_after=CASE WHEN $2='FAILED' THEN now()+interval '1 day' END WHERE capture_id=$1`,[trip.capture.id,status,provider]);
  const response=await get(trip.capture.id);
  expect(response.json().data).toMatchObject({status:'PENDING',provider:null,spans:[]});
  expect((await settled(trip.capture.id)).json().data).toMatchObject({status:'READY',provider:'osrm',algorithmVersion:2});
  expect(calls).toBe(before+1);
  expect((await pool.query('SELECT * FROM drivy.capture_chunk WHERE capture_id=$1 ORDER BY segment_index,chunk_index',[trip.capture.id])).rows).toEqual(chunks.rows);
 });
 it('un cache OSRM de version 1 est recalculé à la version 2',async()=>{
  const before=calls;
  await pool.query('UPDATE drivy.capture_matched_route SET algorithm_version=1 WHERE capture_id=$1',[trip.capture.id]);
  expect((await get(trip.capture.id)).json().data).toMatchObject({status:'PENDING',provider:null,spans:[]});
  expect((await settled(trip.capture.id)).json().data).toMatchObject({status:'READY',provider:'osrm',algorithmVersion:2});
  expect(calls).toBe(before+1);
 });
 it('un ancien bail sans provider est remplacé et ne peut compléter après le recalcul',async()=>{
  const lease=randomUUID();
  await pool.query("UPDATE drivy.capture_matched_route SET status='PROCESSING',provider=NULL,lease_id=$2,lease_until=now()+interval '10 minutes',encrypted_route=NULL,key_id=NULL WHERE capture_id=$1",[trip.capture.id,lease]);
  const before=calls;
  expect((await get(trip.capture.id)).json().data.status).toBe('PENDING');
  const ready=await settled(trip.capture.id);expect(ready.json().data).toMatchObject({status:'READY',provider:'osrm'});expect(calls).toBe(before+1);
  const saved=await row(trip.capture.id);
  expect((await pool.query("SELECT drivy.complete_matched_route($1,$2,'EMPTY',NULL,NULL,0,'mapbox',NULL,NULL) AS accepted",[trip.capture.id,lease])).rows[0].accepted).toBe(false);
  expect(await row(trip.capture.id)).toEqual(saved);
 });
 it('borne resserrée : les mesures détruites emportent leur dérivé, qui n’est jamais resservi',async()=>{
  const previous=(await pool.query<{reconstruction_version:number}>('SELECT reconstruction_version FROM drivy.capture_session WHERE id=$1',[trip.capture.id])).rows[0]!.reconstruction_version;
  const cutoff=await pool.query<{reconstruction_version:number}>("UPDATE drivy.capture_session SET cutoff_at=authorized_at+interval '30 seconds' WHERE id=$1 RETURNING reconstruction_version",[trip.capture.id]);
  expect(cutoff.rows[0]!.reconstruction_version).toBe(previous+1);
  expect(await row(trip.capture.id)).toBeUndefined();
  const after=await settled(trip.capture.id);expect(after.statusCode,after.body).toBe(200);
  // Le lot a été détruit : il ne reste aucune mesure à recaler, donc aucun tronçon.
  expect(after.json().data).toMatchObject({status:'READY',reconstructionVersion:previous+1,spans:[]});expect(validate(after.json().data)).toBe(true);
  expect(await row(trip.capture.id)).toMatchObject({status:'EMPTY',encrypted_route:null,span_count:0});
 });
 it('trajet retiré : la couche recalée disparaît avec lui',async()=>{
  expect(await row(other.capture.id)).toMatchObject({status:'READY'});
  await pool.query("UPDATE drivy.capture_session SET publication_state='WITHDRAWN' WHERE id=$1",[other.capture.id]);
  expect(await row(other.capture.id)).toBeUndefined();
  expect((await get(other.capture.id,'demo-other-instructor')).statusCode).toBe(404);
 });
});

/** Sans moteur configuré, la route existe, ne calcule rien et le replay se suffit. Base distincte : le harnais installe sa propre école. */
describe('recalage non configuré',()=>{
 let barePool:Pool,bare:CaptureHarness;
 beforeAll(async()=>{barePool=await freshDatabase();bare=await captureHarness(barePool);},60_000);
 afterAll(async()=>{await bare?.app.close();await barePool?.end();});
 it('répond « indisponible » sans rien écrire, avec les mêmes droits',async()=>{
  const plain=await bare.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
  await bare.uploadStopFinalize(plain);
  const response=await bare.call('GET',`/captures/${plain.capture.id}/matched-route`);expect(response.statusCode,response.body).toBe(200);
  expect(response.json().data).toMatchObject({status:'UNAVAILABLE',provider:null,spans:[]});expect(validate(response.json().data)).toBe(true);
  expect((await barePool.query('SELECT 1 FROM drivy.capture_matched_route')).rowCount).toBe(0);
  // Même un cache valide ne doit plus être servi lorsque le moteur est désactivé.
  await barePool.query("INSERT INTO drivy.capture_matched_route(capture_id,school_id,reconstruction_version,algorithm_version,status,provider) SELECT id,school_id,reconstruction_version,2,'EMPTY','osrm' FROM drivy.capture_session WHERE id=$1",[plain.capture.id]);
  expect((await bare.call('GET',`/captures/${plain.capture.id}/matched-route`)).json().data).toMatchObject({status:'UNAVAILABLE',provider:null,spans:[]});
  const version=(await barePool.query('SELECT reconstruction_version FROM drivy.capture_session WHERE id=$1',[plain.capture.id])).rows[0].reconstruction_version;
  const encrypted=encryptRoute(bare.config,[],Buffer.from(canonicalCaptureJSON({schoolId:id.schoolA,captureId:plain.capture.id,kind:'matched-route',reconstructionVersion:version,algorithmVersion:2})));
  await barePool.query("UPDATE drivy.capture_matched_route SET status='READY',encrypted_route=$2,key_id=$3 WHERE capture_id=$1",[plain.capture.id,encrypted,bare.config.encryptionKeyId]);
  expect((await bare.call('GET',`/captures/${plain.capture.id}/matched-route`)).json().data).toMatchObject({status:'UNAVAILABLE',provider:null,spans:[]});
  expect((await bare.call('GET',`/captures/${plain.capture.id}/matched-route`,undefined,undefined,'demo-other-instructor')).statusCode).toBe(404);
  expect((await bare.call('GET',`/captures/${plain.capture.id}/replay`)).statusCode).toBe(200);
 });
});
