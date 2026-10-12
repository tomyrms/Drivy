import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

/**
 * Migration 025 : un trajet en cours n'est révoqué que par une vraie perte de droit. Un changement d'époque d'accès (affectation
 * créée ou terminée sur une AUTRE formation, par le bureau) ne coupe plus le trajet de la leçon en cours.
 */
let pool:Pool,h:CaptureHarness;
const alice={instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining};
beforeAll(async()=>{pool=await freshDatabase();h=await captureHarness(pool);});
afterAll(async()=>{await h?.app.close();await pool?.end();});
const state=async(captureId:string)=>(await pool.query<{capture_state:string}>('SELECT capture_state FROM drivy.capture_session WHERE id=$1',[captureId])).rows[0]!.capture_state;
const epoch=async(member:string)=>(await pool.query<{access_epoch:number}>('SELECT access_epoch FROM drivy.membership WHERE id=$1',[member])).rows[0]!.access_epoch;

describe('révocation d’un trajet en cours (migration 025)',()=>{
 it('une affectation créée puis terminée sur une autre formation laisse le trajet autorisé, et son lot est accepté',async()=>{
  const trip=await h.startTrip(alice),before=await epoch(id.instructorMember);
  const created=await h.call('POST',`/trainings/${id.bobTraining}/assignments`,{operationId:randomUUID(),instructorMembershipId:id.instructorMember,validFrom:new Date(Date.now()-60_000).toISOString()},undefined,'demo-admin');
  expect(created.statusCode,created.body).toBe(201);
  // L'époque d'accès du moniteur a bien changé : c'est ce changement seul qui révoquait le trajet avant la 025.
  expect(await epoch(id.instructorMember)).toBe(before+1);
  expect(await state(trip.capture.id)).toBe('AUTHORIZED');
  const ended=await h.call('POST',`/trainings/${id.bobTraining}/assignments/${created.json().data.id}/end`,{operationId:randomUUID()},created.json().data.version,'demo-admin');
  expect(ended.statusCode,ended.body).toBe(200);
  expect(await epoch(id.instructorMember)).toBe(before+2);
  expect(await state(trip.capture.id)).toBe('AUTHORIZED');
  expect((await h.call('GET',`/captures/${trip.capture.id}`)).json().data.captureState).toBe('AUTHORIZED');
  // Le lot mesuré après ces changements est reçu, et le trajet se finalise complet.
  const done=await h.uploadStopFinalize(trip);expect(done.finalized.syncState).toBe('SYNCED');
 });
 it('le changement d’époque de l’élève seul ne révoque pas non plus',async()=>{
  const trip=await h.startTrip(alice);
  await pool.query('UPDATE drivy.membership SET access_epoch=access_epoch+1,version=version+1 WHERE id=$1',[id.aliceMember]);
  expect(await state(trip.capture.id)).toBe('AUTHORIZED');
  expect((await h.uploadStopFinalize(trip)).finalized.syncState).toBe('SYNCED');
 });
 it('le retrait d’accès du moniteur révoque toujours',async()=>{
  const trip=await h.startTrip(alice);
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.instructorMember]);
  try{expect(await state(trip.capture.id)).toBe('REVOKED');}
  finally{await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.instructorMember]);}
 });
 it('le retrait d’accès de l’élève révoque toujours',async()=>{
  const trip=await h.startTrip(alice);
  await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1",[id.aliceMember]);
  try{expect(await state(trip.capture.id)).toBe('REVOKED');}
  finally{await pool.query("UPDATE drivy.membership SET status='ACTIVE' WHERE id=$1",[id.aliceMember]);}
 });
 it('le retrait du rôle Élève révoque toujours ; l’ajout d’un rôle ne révoque pas',async()=>{
  const trip=await h.startTrip(alice),roles=(await pool.query<{roles:string[]}>('SELECT roles FROM drivy.membership WHERE id=$1',[id.aliceMember])).rows[0]!.roles;
  try{
   await pool.query('UPDATE drivy.membership SET roles=$2,access_epoch=access_epoch+1 WHERE id=$1',[id.aliceMember,[...new Set([...roles,'INSTRUCTOR'])]]);
   expect(await state(trip.capture.id)).toBe('AUTHORIZED');
   await pool.query("UPDATE drivy.membership SET roles='{INSTRUCTOR}',access_epoch=access_epoch+1 WHERE id=$1",[id.aliceMember]);
   expect(await state(trip.capture.id)).toBe('REVOKED');
  }finally{await pool.query('UPDATE drivy.membership SET roles=$2 WHERE id=$1',[id.aliceMember,roles]);}
 });
 it('la fin de l’affectation du moniteur à la formation de la leçon révoque toujours (capture_assignment_changed)',async()=>{
  const trip=await h.startTrip(alice);
  const assignment=(await pool.query<{id:string;version:number}>('SELECT id,version FROM drivy.instructor_assignment WHERE school_id=$1 AND training_id=$2 AND instructor_membership_id=$3 AND valid_until IS NULL',[id.schoolA,id.aliceTraining,id.instructorMember])).rows[0]!;
  const ended=await h.call('POST',`/trainings/${id.aliceTraining}/assignments/${assignment.id}/end`,{operationId:randomUUID()},assignment.version,'demo-admin');
  expect(ended.statusCode,ended.body).toBe(200);
  expect(await state(trip.capture.id)).toBe('REVOKED');
 });
});
