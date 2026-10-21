import {randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {afterEach,describe,expect,it,vi} from 'vitest';
import {createOSRMLiveMatcher,liveMatchRequest,matchLive,LiveMatchLimiter,type LiveMatchInput} from '../src/live-matching.js';

/** Mesures synthétiques vers le nord, `spacing` mètres par seconde, horodatées juste avant maintenant. */
const input=(count=5,spacing=12):LiveMatchInput=>{const now=Date.now();return {segmentId:randomUUID(),points:Array.from({length:count},(_,i)=>({sequence:i,elapsedMs:i*1000,capturedAt:new Date(now-(count-i)*1000).toISOString(),latitude:46+i*spacing/111_195,longitude:7,accuracyMeters:5,speed:spacing}))};};
/** Réponse OSRM qui place chaque mesure envoyée sur une route droite passant par elles. */
const response=(points:LiveMatchInput['points'])=>({code:'Ok',matchings:[{confidence:.95,geometry:{type:'LineString',coordinates:points.map(p=>[p.longitude,p.latitude])}}],
 tracepoints:points.map(p=>({location:[p.longitude,p.latitude],matchings_index:0,alternatives_count:1}))});
const through=async(points:LiveMatchInput['points'])=>response(points);
afterEach(()=>vi.useRealTimers());

describe('fenêtre live réelle et ordonnée',()=>{
 it('accepte trois à trente mesures, mais pas les champs arbitraires',()=>{
  expect(liveMatchRequest.safeParse(input()).success).toBe(true);
  const thirty=input(),now=Date.now();thirty.points=Array.from({length:30},(_,i)=>({...thirty.points[0]!,sequence:i,elapsedMs:i*1000,capturedAt:new Date(now-(29-i)*1000).toISOString()}));
  expect(liveMatchRequest.safeParse(thirty).success).toBe(true);
  for(const count of [0,1,2,31]){const b=input();b.points=Array.from({length:count},(_,i)=>({...b.points[0]!,sequence:i,elapsedMs:i*1000,capturedAt:new Date(Date.now()-(count-i)*1000).toISOString()}));expect(liveMatchRequest.safeParse(b).success).toBe(false);}
  expect(liveMatchRequest.safeParse({...input(),predicted:true}).success).toBe(false);
 });
 it.each(['sequence','elapsedMs','capturedAt'] as const)('refuse désordre strict %s',key=>{
  const b=input();Object.assign(b.points[2]!,{[key]:b.points[1]![key]});expect(liveMatchRequest.safeParse(b).success).toBe(false);
 });
 it('refuse fenêtres longues, horloges incohérentes, valeurs non finies et coordonnées invalides',()=>{
  const b=input();b.points[2]!.elapsedMs=31000;b.points[3]!.elapsedMs=32000;b.points[4]!.elapsedMs=33000;expect(liveMatchRequest.safeParse(b).success).toBe(false);
  for(const patch of [{latitude:91},{longitude:-181},{accuracyMeters:-1},{speed:-1},{latitude:NaN},{elapsedMs:Infinity},{speed:1000}]){const c=input();Object.assign(c.points[0]!,patch);expect(liveMatchRequest.safeParse(c).success).toBe(false);}
 });
});

describe('recalage de la ligne et du marqueur (#90)',()=>{
 it('espace les mesures envoyées d’au moins 20 m et garde toujours la dernière',async()=>{
  const b=input(9,8);let sent:LiveMatchInput['points']=[];
  const result=await matchLive(b,async points=>{sent=points;return response(points);});
  expect(sent.at(-1)).toEqual(b.points.at(-1));
  for(let i=1;i<sent.length;i++)expect((sent[i]!.latitude-sent[i-1]!.latitude)*111_195).toBeGreaterThanOrEqual(19.99);
  expect(sent.length).toBe(3);
  expect(result).toMatchObject({status:'MATCHED',segmentId:b.segmentId,sequence:8,elapsedMs:8000,confidence:.95});
 });
 it('renvoie le tronçon routier ancré sur les mesures retenues, en [latitude, longitude]',async()=>{
  const b=input(5,12);
  const result=await matchLive(b,async points=>{
   const r=response(points);
   // La route marque une légère courbe entre deux mesures : un sommet supplémentaire, pas une mesure.
   r.matchings[0]!.geometry.coordinates.splice(1,0,[7.00002,(points[0]!.latitude+points[1]!.latitude)/2]);
   return r;
  });
  expect(result.status).toBe('MATCHED');
  if(result.status!=='MATCHED')return;
  expect(result.route.coordinates.length).toBe(result.route.anchors.length+1);
  expect(result.route.anchors.map(a=>a[0])).toEqual([0,2,4]);
  expect(result.route.anchors.map(a=>a[1])).toEqual([0,2,3]);
  const [lat,lon]=result.route.coordinates.at(-1)!;expect(lat).toBeCloseTo(b.points[4]!.latitude,6);expect(lon).toBeCloseTo(7,6);
  expect(result.position).toEqual({latitude:result.route.coordinates.at(-1)![0],longitude:result.route.coordinates.at(-1)![1]});
 });
 it('accepte une conduite lente sans vitesse Doppler, dès quarante mètres parcourus',async()=>{
  const b=input(14,3.5);for(const p of b.points)delete p.speed;
  expect((await matchLive(b,through)).status).toBe('MATCHED');
 });
 it.each(['confidence','distance','split','missing','detour','malformed'] as const)('refuse résultat %s',async mode=>{
  const b=input();
  const result=await matchLive(b,async points=>{
   const r=response(points) as any;
   if(mode==='confidence')r.matchings[0].confidence=.59;
   if(mode==='distance')r.tracepoints.at(-1).location[0]+=.001;
   if(mode==='split'){r.tracepoints[1].matchings_index=1;r.matchings.push({...r.matchings[0]});}
   if(mode==='missing')r.tracepoints.pop();
   if(mode==='detour')r.matchings[0].geometry.coordinates.splice(1,0,[7.002,points[0]!.latitude],[7.002,points[1]!.latitude]);
   if(mode==='malformed')r.tracepoints.at(-1).location[0]=NaN;
   return r;
  });
  expect(result).toEqual({status:'UNAVAILABLE',segmentId:b.segmentId,sequence:4,elapsedMs:4000});
 });
 it.each(['parked','drifting','reverse','jump','poor','stale','gap'] as const)('ne consulte pas le moteur pour %s',async mode=>{
  const b=input();
  if(mode==='parked')for(const p of b.points)p.latitude=46;
  // À l’arrêt, la dérive GPS de quelques mètres ne fabrique jamais un trajet.
  if(mode==='drifting')b.points.forEach((p,i)=>{p.latitude=46+(i%2?6:-6)/111_195;p.longitude=7+(i%3-1)*6/76_000;});
  if(mode==='reverse'){b.points[3]!.latitude=b.points[1]!.latitude;b.points[4]!.latitude=46-12/111_195;}
  if(mode==='jump')b.points[4]!.latitude=47;
  if(mode==='poor')b.points[4]!.accuracyMeters=31;
  if(mode==='stale')for(const p of b.points)p.capturedAt=new Date(Date.now()-60000+p.elapsedMs).toISOString();
  if(mode==='gap'){for(const p of b.points.slice(3)){p.elapsedMs+=6000;p.capturedAt=new Date(Date.parse(p.capturedAt)).toISOString();}b.points.forEach((p,i)=>{p.capturedAt=new Date(Date.now()-40_000+p.elapsedMs+i).toISOString();});}
  let calls=0;expect((await matchLive(b,async points=>{calls++;return response(points);})).status).toBe('UNAVAILABLE');expect(calls).toBe(0);
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
 it('n’utilise que match OSRM avec géométrie GeoJSON, signal d’annulation et sans redirection',async()=>{
  const b=input();let destination='',settings:RequestInit|undefined;
  const matcher=createOSRMLiveMatcher('http://127.0.0.1:5000',async(url,init)=>{destination=String(url);settings=init;return new Response(JSON.stringify(response(b.points)));});
  const controller=new AbortController();await matcher(b.points,controller.signal);
  const url=new URL(destination);expect(url.origin).toBe('http://127.0.0.1:5000');expect(url.pathname.startsWith('/match/v1/driving/')).toBe(true);
  expect(url.searchParams.get('overview')).toBe('full');expect(url.searchParams.get('geometries')).toBe('geojson');
  expect(url.searchParams.get('radiuses')?.split(';').every(r=>Number(r)>=10&&Number(r)<=30)).toBe(true);
  expect(url.searchParams.has('access_token')).toBe(false);expect(settings?.redirect).toBe('error');expect(settings?.signal).toBe(controller.signal);
 });
 it('refuse origine publique, credentials et réponses trop volumineuses',async()=>{
  for(const url of ['https://api.mapbox.com','http://public.example.com','http://user:password@localhost','http://localhost/?x=1'])expect(()=>createOSRMLiveMatcher(url)).toThrow('Configuration OSRM live invalide.');
  const matcher=createOSRMLiveMatcher('http://localhost:5000',async()=>new Response('x'.repeat(131_073)));
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
