import {afterAll,beforeAll,describe,expect,it} from 'vitest';
import type {Pool} from 'pg';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

/**
 * F3 : une observation prise pendant le trajet n'a pas de position tant que l'app n'a pas d'ancre acquittée. À la finalisation
 * (et pour une observation tardive), le serveur la place sur la mesure la plus proche qui ne la suit pas, à 60 s près, sans rien inventer.
 */
let pool:Pool,h:CaptureHarness;
beforeAll(async()=>{pool=await freshDatabase();h=await captureHarness(pool);});
afterAll(async()=>{await h?.app.close();await pool?.end();});
const alice={instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining};
type Anchored={id:string;version:number;captureId:string|null;segmentId:string|null;pointSequence:number|null};
const anchorOf=(o:Anchored)=>({captureId:o.captureId,segmentId:o.segmentId,pointSequence:o.pointSequence});
const none={captureId:null,segmentId:null,pointSequence:null};
const post=(lesson:string,body:ReturnType<CaptureHarness['marker']>)=>h.call('POST',`/lessons/${lesson}/geo-observations`,body);
const observations=async(lesson:string)=>new Map<string,Anchored>((await h.call('GET',`/lessons/${lesson}/geo-observations?limit=100`)).json().data.items.map((o:Anchored)=>[o.id,o]));

describe('ancrage serveur des observations (F3)',()=>{
 it('à la finalisation, place les observations de l’instant du trajet et laisse les autres sans position',async()=>{
  const trip=await h.startTrip(alice),{started}=h.pointTimes(trip);
  // Mesures aux instants started+10, +20, +30 (séquences 0, 1, 2). Le moniteur note avant l'acquittement du moindre lot : aucune ancre possible.
  const create=async(observedAt:number,text:string)=>{const r=await post(trip.lesson,h.marker(observedAt,text));expect(r.statusCode,r.body).toBe(201);return r.json().data as Anchored;};
  const between=await create(started+12,'Entre deux mesures');// dernière mesure qui ne la suit pas : séquence 0 (à +10)
  const exact=await create(started+30,'Sur une mesure');// séquence 2
  const late=await create(started+25,'Avant la dernière');// séquence 1 (à +20)
  const beforeFirst=await create(started+5,'Avant la première mesure');// aucune mesure qui ne la suit pas
  const beforeCapture=await create(Date.parse(trip.capture.authorizedAt)-5_000,'Avant la capture');// hors de la capture
  for(const o of [between,exact,late,beforeFirst,beforeCapture])expect(anchorOf(o)).toEqual(none);
  const done=await h.uploadStopFinalize(trip);
  const after=await observations(trip.lesson);
  const at=(sequence:number)=>({captureId:trip.capture.id,segmentId:done.segment,pointSequence:sequence});
  expect(anchorOf(after.get(between.id)!)).toEqual(at(0));
  expect(anchorOf(after.get(late.id)!)).toEqual(at(1));
  expect(anchorOf(after.get(exact.id)!)).toEqual(at(2));
  // Pas de position inventée : hors de la capture, ou avant la première mesure, l'observation reste telle quelle (version comprise).
  expect(anchorOf(after.get(beforeFirst.id)!)).toEqual(none);expect(after.get(beforeFirst.id)!.version).toBe(beforeFirst.version);
  expect(anchorOf(after.get(beforeCapture.id)!)).toEqual(none);expect(after.get(beforeCapture.id)!.version).toBe(beforeCapture.version);
  // Une observation placée change de version ; la preuve de finalisation le signale sans contenir de position.
  for(const o of [between,exact,late])expect(after.get(o.id)!.version).toBe(o.version+1);
  const audit=(await pool.query("SELECT changed_fields FROM drivy.audit_event WHERE action='CaptureFinalized' AND resource_id=$1",[trip.capture.id])).rows[0].changed_fields as string[];
  expect(audit).toContain('observationAnchors');
  // Le trajet rejoué porte maintenant ces observations (seules celles dont la mesure figure dans la page).
  const replay=(await h.call('GET',`/captures/${trip.capture.id}/replay?limit=10`)).json().data;
  expect(replay.observations.map((o:{id:string})=>o.id).sort()).toEqual([between.id,exact.id,late.id].sort());
  // Une réécriture par l'app avec l'ancre posée par le serveur reste valide (la mesure ne suit jamais l'observation).
  const put=await h.call('PUT',`/geo-observations/${late.id}`,{...h.marker(started+25,'Avant la dernière, relue'),captureId:trip.capture.id,segmentId:done.segment,pointSequence:1},after.get(late.id)!.version);
  expect(put.statusCode,put.body).toBe(200);expect(anchorOf(put.json().data)).toEqual(at(1));
 });
 it('une observation qui arrive après la finalisation est placée aussitôt ; hors capture, elle reste sans position',async()=>{
  const trip=await h.startTrip(alice),{started}=h.pointTimes(trip),done=await h.uploadStopFinalize(trip);
  const inside=await post(trip.lesson,h.marker(started+22,'Tardive dans le trajet'));
  expect(inside.statusCode,inside.body).toBe(201);
  expect(anchorOf(inside.json().data)).toEqual({captureId:trip.capture.id,segmentId:done.segment,pointSequence:1});expect(inside.json().data.version).toBe(2);
  const outside=await post(trip.lesson,h.marker(Date.parse(trip.capture.authorizedAt)-30_000,'Tardive hors trajet'));
  expect(outside.statusCode,outside.body).toBe(201);expect(anchorOf(outside.json().data)).toEqual(none);expect(outside.json().data.version).toBe(1);
  // Un rejeu de la création rend l'observation telle qu'elle est en base, ancre comprise.
  const body=h.marker(started+30,'Rejouée');const first=await post(trip.lesson,body);expect(first.statusCode).toBe(201);
  const replay=await post(trip.lesson,body);expect(replay.statusCode).toBe(201);expect(replay.json().data).toEqual(first.json().data);expect(first.json().data.pointSequence).toBe(2);
 });
 it('un lot illisible n’ancre rien et ne fait pas échouer la finalisation',async()=>{
  const trip=await h.startTrip(alice),{started}=h.pointTimes(trip);
  const note=await post(trip.lesson,h.marker(started+20,'Pendant un trajet dont le lot sera illisible'));expect(note.statusCode).toBe(201);
  // Le lot est corrompu après l'arrêt : le déchiffrement échoue, la finalisation aboutit quand même.
  const done=await h.uploadStopFinalize(trip,async()=>{await pool.query("UPDATE drivy.capture_chunk SET encrypted_points=decode(repeat('ab',40),'hex') WHERE capture_id=$1",[trip.capture.id]);});
  expect(done.finalized.syncState).toBe('SYNCED');
  expect(anchorOf((await observations(trip.lesson)).get(note.json().data.id)!)).toEqual(none);
 });
});
