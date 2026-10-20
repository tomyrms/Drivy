import {randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {createOSRMLiveMatcher,liveMatchRequest,matchLive,LiveMatchLimiter,type LiveMatchInput} from '../src/live-matching.js';

const input=():LiveMatchInput=>({segmentId:randomUUID(),points:Array.from({length:3},(_,i)=>({sequence:i,elapsedMs:i*1000,capturedAt:new Date(Date.now()-2000+i*1000).toISOString(),latitude:46+i*.0001,longitude:7,accuracyMeters:5,speed:11}))});
const response=(body:LiveMatchInput)=>({code:'Ok',matchings:[{confidence:.95}],tracepoints:body.points.map(p=>({location:[p.longitude,p.latitude],matchings_index:0,alternatives_count:0}))});
afterEach(()=>vi.useRealTimers());

describe('fenêtre live réelle et ordonnée',()=>{
 it('accepte trois à vingt mesures, mais pas les champs arbitraires',()=>{
  expect(liveMatchRequest.safeParse(input()).success).toBe(true);
  const twenty=input(),now=Date.now();twenty.points=Array.from({length:20},(_,i)=>({...twenty.points[0]!,sequence:i,elapsedMs:i*1000,capturedAt:new Date(now-(19-i)*1000).toISOString()}));
  expect(liveMatchRequest.safeParse(twenty).success).toBe(true);
  for(const count of [0,1,2,21]){const b=input();b.points=Array.from({length:count},(_,i)=>({...b.points[0]!,sequence:i,elapsedMs:i*1000,capturedAt:new Date(Date.now()-(count-i)*1000).toISOString()}));expect(liveMatchRequest.safeParse(b).success).toBe(false);}
  expect(liveMatchRequest.safeParse({...input(),predicted:true}).success).toBe(false);
 });
 it.each(['sequence','elapsedMs','capturedAt'] as const)('refuse désordre strict %s',key=>{
  const b=input();Object.assign(b.points[2]!,{[key]:b.points[1]![key]});expect(liveMatchRequest.safeParse(b).success).toBe(false);
 });
 it('refuse fenêtres longues, horloges incohérentes, valeurs non finies et coordonnées invalides',()=>{
  const b=input();b.points[2]!.elapsedMs=31000;expect(liveMatchRequest.safeParse(b).success).toBe(false);
  for(const patch of [{latitude:91},{longitude:-181},{accuracyMeters:-1},{speed:-1},{latitude:NaN},{elapsedMs:Infinity},{speed:1000}]){const c=input();Object.assign(c.points[0]!,patch);expect(liveMatchRequest.safeParse(c).success).toBe(false);}
 });
});

describe('recalage conservateur de la dernière mesure uniquement',()=>{
 it('retourne uniquement la dernière ancre, avec confiance et distance calculée',async()=>{
  const b=input(),r=response(b);r.tracepoints[2]!.location[0]!+=.00001;
  const result=await matchLive(b,async()=>r);
  expect(result).toMatchObject({status:'MATCHED',segmentId:b.segmentId,sequence:2,elapsedMs:2000,confidence:.95});
  expect(result).not.toHaveProperty('points');
  if(result.status==='MATCHED'){expect(result.distanceMeters).toBeGreaterThan(0);expect(result.distanceMeters).toBeLessThan(5);}
 });
 it.each(['confidence','distance','ambiguity','missing','split','malformed'] as const)('refuse résultat %s',async mode=>{
  const b=input(),r=response(b);
  if(mode==='confidence')r.matchings[0]!.confidence=.79;
  if(mode==='distance')r.tracepoints[2]!.location[0]!+=.001;
  if(mode==='ambiguity')r.tracepoints[2]!.alternatives_count=1;
  if(mode==='missing')r.tracepoints.pop();
  if(mode==='split')r.tracepoints[2]!.matchings_index=1;
  if(mode==='malformed')r.tracepoints[2]!.location[0]=NaN;
  expect(await matchLive(b,async()=>r)).toEqual({status:'UNAVAILABLE',segmentId:b.segmentId,sequence:2,elapsedMs:2000});
 });
 it.each(['parked','slow','reverse','jump','poor','stale'] as const)('ne consulte pas le moteur pour %s',async mode=>{
  const b=input();
  if(mode==='parked')for(const p of b.points)p.latitude=46;
  if(mode==='slow')b.points[2]!.speed=.5;
  if(mode==='reverse')b.points[2]!.latitude=46;
  if(mode==='jump')b.points[2]!.latitude=47;
  if(mode==='poor')b.points[2]!.accuracyMeters=31;
  if(mode==='stale')for(const p of b.points)p.capturedAt=new Date(Date.now()-60000+p.elapsedMs).toISOString();
  let calls=0;expect((await matchLive(b,async()=>{calls++;return response(b);})).status).toBe('UNAVAILABLE');expect(calls).toBe(0);
 });
 it('absorbe erreurs contaminées et coupe tout le calcul à 750ms',async()=>{
  const b=input();expect((await matchLive(b,async()=>{throw new Error('sensitive upstream URL');})).status).toBe('UNAVAILABLE');
  vi.useFakeTimers();let signal:AbortSignal|undefined;
  const pending=matchLive(b,async(_points,s)=>{signal=s;return new Promise(()=>{});});
  await vi.advanceTimersByTimeAsync(751);
  expect((await pending).status).toBe('UNAVAILABLE');expect(signal?.aborted).toBe(true);
 });
});

describe('client OSRM et limites mémoire',()=>{
 it('n’utilise que match OSRM, sans géométrie et avec signal annulation, sans redirect',async()=>{
  const b=input();let destination='',settings:RequestInit|undefined;
  const matcher=createOSRMLiveMatcher('http://127.0.0.1:5000',async(url,init)=>{destination=String(url);settings=init;return new Response(JSON.stringify(response(b)));});
  const controller=new AbortController();await matcher(b.points,controller.signal);
  const url=new URL(destination);expect(url.origin).toBe('http://127.0.0.1:5000');expect(url.pathname.startsWith('/match/v1/driving/')).toBe(true);expect(url.searchParams.get('overview')).toBe('false');expect(url.searchParams.has('access_token')).toBe(false);expect(settings?.redirect).toBe('error');expect(settings?.signal).toBe(controller.signal);
 });
 it('refuse origine publique, credentials et réponses trop volumineuses',async()=>{
  for(const url of ['https://api.mapbox.com','http://public.example.com','http://user:password@localhost','http://localhost/?x=1'])expect(()=>createOSRMLiveMatcher(url)).toThrow('Configuration OSRM live invalide.');
  const matcher=createOSRMLiveMatcher('http://localhost:5000',async()=>new Response('x'.repeat(65537)));
  await expect(matcher(input().points,new AbortController().signal)).rejects.toThrow('LIVE_MATCH_UNAVAILABLE');
 });
 it('annule aussi un vrai transport HTTP bloqué après les en-têtes',async()=>{
  const server=createServer((_request,reply)=>{reply.writeHead(200,{'content-type':'application/json'});reply.write('{"code":');});
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
   const matcher=createOSRMLiveMatcher(`http://127.0.0.1:${(server.address() as AddressInfo).port}`),start=Date.now();
   expect((await matchLive(input(),matcher)).status).toBe('UNAVAILABLE');
   expect(Date.now()-start).toBeLessThan(2500);
  } finally {server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
 });
 it('n’évince jamais une identité active même au-delà du TTL',()=>{
  let now=0;const limiter=new LiveMatchLimiter({capacity:1,concurrency:2,now:()=>now});
  const release=limiter.acquire('active')!;now=61000;
  expect(limiter.acquire('new')).toBeUndefined();expect(limiter.acquire('active')).toBeUndefined();
  release();expect(limiter.acquire('new')).toBeTypeOf('function');
 });
 it('borne identités, concurrence, cadence et libère même deux fois sans casser les autres',()=>{
  let now=0;const limiter=new LiveMatchLimiter({capacity:2,concurrency:2,intervalMs:2000,ttlMs:60000,now:()=>now});
  const a=limiter.acquire('a')!;expect(a).toBeTypeOf('function');expect(limiter.acquire('a')).toBeUndefined();
  const b=limiter.acquire('b')!;expect(limiter.acquire('c')).toBeUndefined();a();a();expect(limiter.acquire('a')).toBeUndefined();
  now=2000;const next=limiter.acquire('a');expect(next).toBeTypeOf('function');next!();b();
  expect(limiter.acquire('c')).toBeUndefined();now=60001;expect(limiter.acquire('c')).toBeTypeOf('function');
 });
});
