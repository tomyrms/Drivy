import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

/** Décision du 28 septembre 2026 : l'administration voit tous les trajets de l'école (lecture seule) ; GET /captures liste ce que le compte peut lire. */
let pool:Pool,h:CaptureHarness;
type Trip=Awaited<ReturnType<CaptureHarness['startTrip']>>;
let trip1:Trip,trip2:Trip,done1:Awaited<ReturnType<CaptureHarness['uploadStopFinalize']>>;
beforeAll(async()=>{
 pool=await freshDatabase();h=await captureHarness(pool);
 // Trajet 1 : Alice avec le moniteur affecté par les données de départ.
 trip1=await h.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
 done1=await h.uploadStopFinalize(trip1);
 // Trajet 2 : Noé avec l'autre moniteur, affecté pour l'occasion. Démarré plus tard : il est le plus récent.
 await pool.query("INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from) VALUES($1,$2,$3,$4,'2026-01-01T00:00:00Z')",[randomUUID(),id.schoolA,id.bobTraining,id.otherInstructorMember]);
 trip2=await h.startTrip({instructorSubject:'demo-other-instructor',instructorMember:id.otherInstructorMember,learnerSubject:'demo-bob',learnerId:id.bobLearner,learnerPerson:id.bob,trainingId:id.bobTraining});
 await h.uploadStopFinalize(trip2);
});
afterAll(async()=>{await h?.app.close();await pool?.end();});
const list=async(subject:string,query='',school:string=id.schoolA)=>h.call('GET',`/v1/schools/${school}/captures${query}`,undefined,undefined,subject);
const ids=(response:{json:()=>any})=>response.json().data.items.map((item:{id:string})=>item.id);
// Fin de leçon par SQL (comme la recette de capture) : le partage à l'élève ne dépend que de l'état COMPLETED.
const complete=(lesson:string)=>pool.query("UPDATE drivy.lesson SET status='COMPLETED',actual_start=now()-interval '2 minutes',actual_end=now()-interval '1 minute' WHERE id=$1",[lesson]);
const reopen=(lesson:string)=>pool.query("UPDATE drivy.lesson SET status='PLANNED',actual_start=NULL,actual_end=NULL WHERE id=$1",[lesson]);

describe('liste des trajets (extension GET /captures)',()=>{
 it('le moniteur ne voit que les trajets de ses formations, avec la projection canonique et quatre champs de plus',async()=>{
  const mine=await list('demo-instructor');expect(mine.statusCode,mine.body).toBe(200);
  expect(ids(mine)).toEqual([trip1.capture.id]);expect(mine.json().data.nextCursor).toBeNull();
  const item=mine.json().data.items[0];
  const canonical=(await h.call('GET',`/captures/${trip1.capture.id}`)).json().data;
  expect(item).toEqual({...canonical,learnerName:'Alice Exemple',instructorName:'Alex Moniteur',lessonPlannedStart:expect.any(String),lessonTimeZone:'Europe/Zurich'});
  expect(new Date(item.lessonPlannedStart).toISOString()).toBe(item.lessonPlannedStart);
  expect(Object.keys(item).sort()).toEqual([...Object.keys(canonical),'instructorName','learnerName','lessonPlannedStart','lessonTimeZone'].sort());
  const other=await list('demo-other-instructor');expect(ids(other)).toEqual([trip2.capture.id]);
  expect(other.json().data.items[0]).toMatchObject({learnerName:'Noé Exemple',instructorName:'Lou Monitrice'});
  expect(mine.headers['cache-control']).toBe('no-store');expect(Object.keys(mine.json()).sort()).toEqual(['data','requestId','serverTime']);
 });
 it('l’administrateur, sans affectation, voit tous les trajets, le plus récent d’abord, avec une pagination opaque',async()=>{
  const all=await list('demo-admin');expect(all.statusCode,all.body).toBe(200);expect(ids(all)).toEqual([trip2.capture.id,trip1.capture.id]);
  const first=await list('demo-admin','?limit=1');expect(ids(first)).toEqual([trip2.capture.id]);expect(first.json().data.nextCursor).toBeTypeOf('string');
  const second=await list('demo-admin',`?limit=1&cursor=${encodeURIComponent(first.json().data.nextCursor)}`);expect(ids(second)).toEqual([trip1.capture.id]);expect(second.json().data.nextCursor).toBeNull();
  // Le curseur est lié au compte et à l'accès : rejoué par un autre compte, il est refusé.
  const stolen=await list('demo-instructor',`?limit=1&cursor=${encodeURIComponent(first.json().data.nextCursor)}`);expect(stolen.statusCode).toBe(400);expect(stolen.json().code).toBe('INVALID_CURSOR');
  for(const query of ['?limit=0','?limit=101','?limit=abc','?cursor=not-a-cursor','?status=ALL','?unknown=1'])expect((await list('demo-admin',query)).statusCode,query).toBe(400);
  const dates=all.json().data.items.map((i:{authorizedAt:string})=>Date.parse(i.authorizedAt));expect(dates[0]).toBeGreaterThanOrEqual(dates[1]);
 });
 it('l’élève ne voit que ses trajets partagés : aucun avant la fin de la leçon, puis le sien, jamais celui d’un autre',async()=>{
  expect(ids(await list('demo-alice'))).toEqual([]);expect(ids(await list('demo-bob'))).toEqual([]);
  await complete(trip1.lesson);
  try{
   const alice=await list('demo-alice');expect(ids(alice)).toEqual([trip1.capture.id]);
   expect((await h.call('GET',`/lessons/${trip1.lesson}`,undefined,undefined,'demo-alice')).json().data.captureSummary).toMatchObject({hasCapture:true,syncState:'SYNCED'});
   // Le nom du moniteur vient de la fonction dédiée : l'élève ne lit pas la fiche personne de son moniteur.
   expect(alice.json().data.items[0]).toMatchObject({learnerName:'Alice Exemple',instructorName:'Alex Moniteur'});
   expect(ids(await list('demo-bob'))).toEqual([]);
   expect((await h.call('GET',`/captures/${trip2.capture.id}`,undefined,undefined,'demo-alice')).statusCode).toBe(404);
   // Trajet masqué par le moniteur : l'élève ne le liste plus ; l'administration le garde.
   await pool.query('UPDATE drivy.lesson SET capture_hidden=true WHERE id=$1',[trip1.lesson]);
   expect(ids(await list('demo-alice'))).toEqual([]);expect(ids(await list('demo-admin'))).toContain(trip1.capture.id);
   expect((await h.call('GET',`/lessons/${trip1.lesson}`,undefined,undefined,'demo-alice')).json().data.captureSummary.hasCapture).toBe(false);
   await pool.query('UPDATE drivy.lesson SET capture_hidden=false WHERE id=$1',[trip1.lesson]);
   expect(ids(await list('demo-alice'))).toEqual([trip1.capture.id]);
  }finally{await reopen(trip1.lesson);}
 });
 it('une autre école ne voit rien, ni par la liste ni par identifiant',async()=>{
  expect((await list('demo-foreign')).statusCode).toBe(403);// non-membre de l'école A
  const foreign=await list('demo-foreign','',id.schoolB);expect(foreign.statusCode).toBe(200);expect(foreign.json().data.items).toEqual([]);
  // Le moniteur de démonstration est ADMIN de l'école B : ses droits d'administration s'arrêtent à B.
  const otherSchoolAdmin=await list('demo-instructor','',id.schoolB);expect(otherSchoolAdmin.statusCode).toBe(200);expect(otherSchoolAdmin.json().data.items).toEqual([]);
  expect((await h.call('GET',`/v1/schools/${id.schoolB}/captures/${trip1.capture.id}`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
  expect((await h.call('GET',`/v1/schools/${id.schoolB}/captures/${trip1.capture.id}/replay`,undefined,undefined,'demo-instructor')).statusCode).toBe(404);
  expect((await h.app.inject({method:'GET',url:`/v1/schools/${id.schoolA}/captures`})).statusCode).toBe(401);
 });
 it('les trajets supprimés sont exclus de la liste',async()=>{
  await pool.query("UPDATE drivy.capture_session SET publication_state='DELETED' WHERE id=$1",[trip2.capture.id]);
  try{expect(ids(await list('demo-admin'))).toEqual([trip1.capture.id]);expect(ids(await list('demo-other-instructor'))).toEqual([]);}
  finally{await pool.query("UPDATE drivy.capture_session SET publication_state='PRIVATE' WHERE id=$1",[trip2.capture.id]);}
  expect(ids(await list('demo-admin'))).toEqual([trip2.capture.id,trip1.capture.id]);
 });
});

describe('lecture d’un trajet par l’administration',()=>{
 it('l’administrateur lit le trajet et son replay, en lecture seule',async()=>{
  const read=await h.call('GET',`/captures/${trip1.capture.id}`,undefined,undefined,'demo-admin');expect(read.statusCode,read.body).toBe(200);
  expect((await h.call('GET',`/lessons/${trip1.lesson}`,undefined,undefined,'demo-admin')).json().data.captureSummary).toMatchObject({hasCapture:true,syncState:'SYNCED'});
  expect(read.json().data).toMatchObject({id:trip1.capture.id,learnerId:id.aliceLearner,instructorMembershipId:id.instructorMember,syncState:'SYNCED'});
  const replay=await h.call('GET',`/captures/${trip1.capture.id}/replay?limit=10`,undefined,undefined,'demo-admin');expect(replay.statusCode,replay.body).toBe(200);
  expect(replay.json().data.segments[0].points).toHaveLength(3);expect(replay.json().data.quality).toBe('SYNCED');
  const otherTrip=await h.call('GET',`/captures/${trip2.capture.id}/replay?limit=10`,undefined,undefined,'demo-admin');expect(otherTrip.statusCode).toBe(200);
  // Aucune écriture : l'arrêt, la finalisation et le dépôt de lots restent réservés à l'auteur.
  const stop=await h.call('POST',`/captures/${trip1.capture.id}/stop`,{operationId:randomUUID(),stoppedAt:new Date().toISOString(),reason:'USER_STOP',segments:done1.manifest,localCollectorStopped:true},undefined,'demo-admin');
  expect(stop.statusCode).toBe(404);
  const finalize=await h.call('POST',`/captures/${trip1.capture.id}/finalize`,{operationId:randomUUID(),segments:done1.manifest,allowPartial:false},done1.finalized.version,'demo-admin');expect(finalize.statusCode).toBe(404);
  const rows=await pool.query('SELECT version,capture_state FROM drivy.capture_session WHERE id=$1',[trip1.capture.id]);expect(rows.rows[0].version).toBe(done1.finalized.version);
 });
 it('un moniteur non affecté et un élève tiers ne lisent toujours rien',async()=>{
  for(const subject of ['demo-other-instructor','demo-bob']){
   expect((await h.call('GET',`/captures/${trip1.capture.id}`,undefined,undefined,subject)).statusCode,subject).toBe(404);
   expect((await h.call('GET',`/captures/${trip1.capture.id}/replay`,undefined,undefined,subject)).statusCode,subject).toBe(404);
  }
 });
 it('les observations restent gouvernées par leurs propres règles : l’administrateur relit le trajet sans les observations, l’élève seulement celles qui lui sont partagées',async()=>{
  // Après la finalisation, le serveur place l'observation sur la mesure (F3) : elle figure alors dans le replay.
  const created=await h.call('POST',`/lessons/${trip1.lesson}/geo-observations`,h.marker(done1.at[1]!));expect(created.statusCode,created.body).toBe(201);
  expect(created.json().data).toMatchObject({captureId:trip1.capture.id,segmentId:done1.segment,pointSequence:1});
  const observations=async(subject:string)=>(await h.call('GET',`/captures/${trip1.capture.id}/replay?limit=10`,undefined,undefined,subject)).json().data.observations.map((o:{id:string})=>o.id);
  expect(await observations('demo-instructor')).toEqual([created.json().data.id]);
  expect(await observations('demo-admin')).toEqual([]);
  expect((await h.call('GET',`/lessons/${trip1.lesson}/geo-observations`,undefined,undefined,'demo-admin')).statusCode).toBe(404);
  // Leçon réalisée : l'élève relit l'observation non privée ; « Pour moi » la lui retire.
  await complete(trip1.lesson);
  try{
   expect(await observations('demo-alice')).toEqual([created.json().data.id]);
   await pool.query('UPDATE drivy.geo_observation SET private=true WHERE id=$1',[created.json().data.id]);
   expect(await observations('demo-alice')).toEqual([]);expect(await observations('demo-instructor')).toEqual([created.json().data.id]);expect(await observations('demo-admin')).toEqual([]);
  }finally{await reopen(trip1.lesson);}
 });
});
