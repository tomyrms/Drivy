import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

/** #61 : annuler une leçon commencée pendant que son trajet GPS est actif. */
let pool:Pool,h:CaptureHarness;
beforeAll(async()=>{pool=await freshDatabase();h=await captureHarness(pool);});
afterAll(async()=>{await h?.app.close();await pool?.end();});

describe('annulation d’une leçon commencée avec GPS actif (#61)',()=>{
 it('annule la leçon, révoque le trajet et conserve les positions déjà reçues',async()=>{
  const trip=await h.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
  await pool.query('UPDATE drivy.lesson SET actual_start=now()-interval \'1 minute\' WHERE id=$1',[trip.lesson]);
  const started=Date.parse(trip.capture.authorizedAt)+1,segment=randomUUID();
  while(Date.now()<started+40)await new Promise(r=>setTimeout(r,10));
  const {trackContentHash}=await import('../src/capture-crypto.js');
  const points=[0,1].map(sequence=>({sequence,elapsedMs:10+sequence*10,capturedAt:new Date(started+10+sequence*10).toISOString(),latitude:46.99,longitude:6.9+sequence/100000,accuracyMeters:5}));
  const content={segmentIndex:0,segmentStartedAt:new Date(started).toISOString(),segmentStartReason:'START' as const,points};
  const upload=await h.call('PUT',`/captures/${trip.capture.id}/segments/${segment}/chunks/0`,{operationId:randomUUID(),...content,contentHash:trackContentHash(content),signedUploadAuthorization:trip.uploadAuthorization});
  expect(upload.statusCode,upload.body).toBe(200);
  const lesson=(await h.call('GET',`/lessons/${trip.lesson}`)).json().data;
  expect(lesson.actualStart).not.toBeNull();
  const cancel=await h.call('POST',`/lessons/${trip.lesson}/cancel`,{operationId:randomUUID(),reasonCode:'OTHER'},lesson.version);
  expect(cancel.statusCode,cancel.body).toBe(200);
  expect(cancel.json().data).toMatchObject({status:'CANCELLED',actualStart:null,actualEnd:null});
  const capture=(await h.call('GET',`/captures/${trip.capture.id}`)).json().data;
  expect(capture.captureState).toBe('REVOKED');
  expect(capture.cutoffAt).not.toBeNull();
  expect((await pool.query('SELECT count(*)::int AS n FROM drivy.capture_chunk WHERE capture_id=$1',[trip.capture.id])).rows[0].n).toBe(1);
  // Aucun lot ne peut plus arriver après l'annulation.
  const late={...content,segmentIndex:0,points:[{...points[1]!,sequence:2,capturedAt:new Date().toISOString(),elapsedMs:Date.now()-started}]};
  const refused=await h.call('PUT',`/captures/${trip.capture.id}/segments/${segment}/chunks/1`,{operationId:randomUUID(),...late,contentHash:trackContentHash(late),signedUploadAuthorization:trip.uploadAuthorization});
  expect(refused.statusCode).not.toBe(200);
 });
});
