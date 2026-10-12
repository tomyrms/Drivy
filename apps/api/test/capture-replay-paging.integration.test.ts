import {randomUUID} from 'node:crypto';
import {afterAll,beforeAll,describe,expect,it,vi} from 'vitest';
import type {Pool} from 'pg';

// Compte les déchiffrements réels, sans changer leur résultat : l'AAD (4e argument) nomme le lot déchiffré.
vi.mock('../src/capture-crypto.js',async importOriginal=>{
 const actual=await importOriginal<typeof import('../src/capture-crypto.js')>();
 return {...actual,decryptPoints:vi.fn(actual.decryptPoints)};
});
import {decryptPoints,trackContentHash} from '../src/capture-crypto.js';
import {freshDatabase,id} from './support/harness.js';
import {captureHarness,type CaptureHarness} from './support/capture-harness.js';

/** Le replay ne lit et ne déchiffre que les lots utiles à la page ; ses réponses restent celles de la lecture complète. */
let pool:Pool,h:CaptureHarness;
beforeAll(async()=>{pool=await freshDatabase();h=await captureHarness(pool);});
afterAll(async()=>{await h?.app.close();await pool?.end();});
interface Point {sequence:number;elapsedMs:number;capturedAt:string;latitude:number;longitude:number;accuracyMeters:number}
interface Flat {segmentId:string;segmentIndex:number;point:Point}
interface Segment {segmentId:string;segmentIndex:number;points:Point[];hasGapBefore:boolean;qualityLabel:string;continuesFromPreviousPage:boolean;continuesOnNextPage:boolean}

/** L'algorithme d'avant la correction, sur la liste complète des mesures : il sert de référence au caractère près. */
function reference(ordered:Flat[],begin:number,limit:number):Segment[]{
 const page=ordered.slice(begin,begin+limit),segments:Segment[]=[];
 for(let i=0;i<page.length;i++){
  const item=page[i]!,previous=ordered[begin+i-1],same=previous?.segmentId===item.segmentId,continuous=same&&previous!.point.sequence+1===item.point.sequence,last=segments.at(-1);
  if(last?.segmentId===item.segmentId&&continuous)last.points.push(item.point);
  else segments.push({segmentId:item.segmentId,segmentIndex:item.segmentIndex,points:[item.point],hasGapBefore:previous?(!same||!continuous):item.segmentIndex>0||item.point.sequence>0,qualityLabel:'AVAILABLE',continuesFromPreviousPage:i===0&&!!continuous,continuesOnNextPage:false});
 }
 const last=page.at(-1),next=ordered[begin+page.length];
 if(last&&next&&last.segmentId===next.segmentId&&last.point.sequence+1===next.point.sequence)segments.at(-1)!.continuesOnNextPage=true;
 return segments;
}

describe('replay paginé (lots déchiffrés à la demande)',()=>{
 it('trois lots sur deux segments, lus page par page : mêmes réponses que la lecture complète, et la page du milieu ne déchiffre pas le premier lot',async()=>{
  const trip=await h.startTrip({instructorSubject:'demo-instructor',instructorMember:id.instructorMember,learnerSubject:'demo-alice',learnerId:id.aliceLearner,learnerPerson:id.alice,trainingId:id.aliceTraining});
  const origin=Date.parse(trip.capture.authorizedAt)+1,segmentA=randomUUID(),segmentB=randomUUID();
  const point=(start:number,sequence:number,elapsedMs:number):Point=>({sequence,elapsedMs,capturedAt:new Date(start+elapsedMs).toISOString(),latitude:46.99+sequence/100000,longitude:6.9,accuracyMeters:5});
  // Segment A : deux lots, avec un trou de séquence (4 puis 6) dans le second. Segment B : un lot, après une reprise.
  const startB=origin+200;
  const lots=[
   {segmentId:segmentA,chunkIndex:0,segmentIndex:0,start:origin,reason:'START',points:[point(origin,0,10),point(origin,1,20),point(origin,2,30)]},
   {segmentId:segmentA,chunkIndex:1,segmentIndex:0,start:origin,reason:'START',points:[point(origin,3,40),point(origin,4,50),point(origin,6,70)]},
   {segmentId:segmentB,chunkIndex:0,segmentIndex:1,start:startB,reason:'RESUME',points:[point(startB,0,10),point(startB,1,20),point(startB,2,30)]}
  ];
  while(Date.now()<startB+60)await new Promise(resolve=>setTimeout(resolve,10));
  for(const lot of lots){
   const content={segmentIndex:lot.segmentIndex,segmentStartedAt:new Date(lot.start).toISOString(),segmentStartReason:lot.reason,points:lot.points};
   const upload=await h.call('PUT',`/captures/${trip.capture.id}/segments/${lot.segmentId}/chunks/${lot.chunkIndex}`,{operationId:randomUUID(),...content,contentHash:trackContentHash(content as never),signedUploadAuthorization:trip.uploadAuthorization});
   expect(upload.statusCode,upload.body).toBe(200);expect(upload.json().data.duplicate).toBe(false);
  }
  // Un lot déjà reçu est reconnu sans relire son contenu chiffré.
  const again={segmentIndex:0,segmentStartedAt:new Date(origin).toISOString(),segmentStartReason:'START',points:lots[0]!.points};
  const duplicate=await h.call('PUT',`/captures/${trip.capture.id}/segments/${segmentA}/chunks/0`,{operationId:randomUUID(),...again,contentHash:trackContentHash(again as never),signedUploadAuthorization:trip.uploadAuthorization});
  expect(duplicate.statusCode,duplicate.body).toBe(200);expect(duplicate.json().data.duplicate).toBe(true);
  const manifest=[{segmentId:segmentA,segmentIndex:0,expectedChunkIndices:[0,1],expectedPointCount:6,lastSequence:6,endReason:'PAUSE'},{segmentId:segmentB,segmentIndex:1,expectedChunkIndices:[0],expectedPointCount:3,lastSequence:2,endReason:'STOP'}];
  const stop=await h.call('POST',`/captures/${trip.capture.id}/stop`,{operationId:randomUUID(),stoppedAt:new Date().toISOString(),reason:'USER_STOP',segments:manifest,localCollectorStopped:true});
  expect(stop.statusCode,stop.body).toBe(200);
  const finalized=await h.call('POST',`/captures/${trip.capture.id}/finalize`,{operationId:randomUUID(),segments:manifest,allowPartial:false},stop.json().data.version);
  expect(finalized.statusCode,finalized.body).toBe(200);expect(finalized.json().data.syncState).toBe('SYNCED');

  const ordered:Flat[]=lots.flatMap(lot=>lot.points.map(p=>({segmentId:lot.segmentId,segmentIndex:lot.segmentIndex,point:p})));
  const spy=vi.mocked(decryptPoints);
  const decrypted=()=>spy.mock.calls.map(call=>{const aad=JSON.parse((call[3] as Buffer).toString('utf8')) as {segmentId:string;chunkIndex:number};return `${aad.segmentId===segmentA?'A':'B'}${aad.chunkIndex}`;}).sort();
  for(const limit of [2,4,100]){
   let cursor:string|undefined,begin=0,pages=0;const seen:Segment[][]=[];
   do{
    spy.mockClear();
    const response=await h.call('GET',`/captures/${trip.capture.id}/replay?limit=${limit}${cursor?`&cursor=${encodeURIComponent(cursor)}`:''}`);
    expect(response.statusCode,response.body).toBe(200);
    const data=response.json().data as {segments:Segment[];nextCursor:string|null;quality:string};
    expect(data.quality).toBe('SYNCED');
    expect(data.segments).toEqual(reference(ordered,begin,limit));
    const count=data.segments.reduce((n,s)=>n+s.points.length,0);
    expect(data.nextCursor===null).toBe(begin+count>=ordered.length);
    // Page du milieu en pages de deux mesures (rangs 4 et 5, second lot du segment A) : le premier lot n'est pas déchiffré.
    if(limit===2&&begin===4)expect(decrypted()).toEqual(['A1','B0']);
    // Première page de deux mesures : seul le premier lot est lu (la mesure suivante, rang 2, y est encore).
    if(limit===2&&begin===0)expect(decrypted()).toEqual(['A0']);
    // Aucun lot n'est déchiffré deux fois pour une même page.
    expect(new Set(decrypted()).size).toBe(decrypted().length);
    seen.push(data.segments);begin+=count;cursor=data.nextCursor??undefined;pages++;
   }while(cursor);
   expect(begin).toBe(ordered.length);expect(pages).toBe(Math.ceil(ordered.length/limit));
   expect(seen.flat().flatMap(s=>s.points)).toEqual(ordered.map(item=>item.point));
  }
  // Un curseur d'une autre taille de page est refusé comme avant.
  const first=(await h.call('GET',`/captures/${trip.capture.id}/replay?limit=2`)).json().data.nextCursor as string;
  expect((await h.call('GET',`/captures/${trip.capture.id}/replay?limit=4&cursor=${encodeURIComponent(first)}`)).json().code).toBe('INVALID_CURSOR');
 });
});
