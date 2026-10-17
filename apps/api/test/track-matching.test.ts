import {describe,expect,it} from 'vitest';
import type {TrackPoint} from '../src/capture-contracts.js';
import {batches,continuousRuns,decodePolyline,encodePolyline,matchTrack,matcherPoints,mergeSpans,meters,selectTrack,spansFromBatch,type MatcherPoint,type MatcherResult} from '../src/track-matching.js';
import {createMapMatcher,MapMatchingError,readMapMatchingConfig} from '../src/map-matching-client.js';

// Mètres synthétiques autour de l'équateur : aucune route réelle, aucune position de personne.
const M=1/111_320,START=Date.parse('2026-10-11T08:00:00.000Z');
const fix=(sequence:number,second:number,east:number,north=0,accuracy=4):TrackPoint=>({sequence,elapsedMs:Math.round(second*1000),capturedAt:new Date(START+Math.round(second*1000)).toISOString(),latitude:north*M,longitude:east*M,accuracyMeters:accuracy});
const kept=(points:TrackPoint[])=>selectTrack(points).map(s=>s.point.sequence);
const starts=(points:TrackPoint[])=>selectTrack(points).map(s=>s.startsFragment);
/** Bruit déterministe, borné à ±amplitude. */
const noise=(index:number,amplitude:number)=>Math.sin(index*12.9898)*amplitude;

describe('sélection des mesures (copie du filtre de l’app)',()=>{
 it('trajet urbain : chaque virage à angle droit reste, dans l’ordre des séquences',()=>{
  const points:TrackPoint[]=[];
  for(let i=0;i<=20;i++)points.push(fix(i,i,i*10));
  for(let i=1;i<=20;i++)points.push(fix(20+i,20+i,200,i*10));
  for(let i=1;i<=20;i++)points.push(fix(40+i,40+i,200-i*10,200));
  const selected=selectTrack(points);
  expect(selected.map(s=>s.point.sequence)).toEqual(points.map(p=>p.sequence));
  expect(selected.filter(s=>s.startsFragment)).toHaveLength(1);
 });
 it('autoroute à 130 km/h : aucune mesure n’est prise pour un saut',()=>{
  const points=Array.from({length:60},(_,i)=>fix(i,i,i*36.1,noise(i,1.5)));
  expect(kept(points)).toHaveLength(60);expect(starts(points).filter(Boolean)).toHaveLength(1);
 });
 it('rond-point lent : la courbure mesurée est conservée, sans lissage',()=>{
  const points=Array.from({length:13},(_,i)=>fix(i,i*5,12*Math.cos(i*Math.PI/6),12*Math.sin(i*Math.PI/6),3));
  expect(kept(points)).toEqual(points.map(p=>p.sequence));
 });
 it('demi-tour : l’aller et le retour sur la même rue restent tous les deux',()=>{
  const out=Array.from({length:10},(_,i)=>fix(i,i,i*8)),turn=[fix(10,13,76,4),fix(11,16,72,7)],back=Array.from({length:10},(_,i)=>fix(12+i,19+i,64-i*8,8));
  expect(kept([...out,...turn,...back])).toEqual([...out,...turn,...back].map(p=>p.sequence));
 });
 it('marche arrière : un recul lent de quelques mètres n’est pas supprimé comme du bruit',()=>{
  const forward=Array.from({length:6},(_,i)=>fix(i,i,i*6));
  const reverse=Array.from({length:8},(_,i)=>fix(6+i,7+i,30-(i+1)*1.2));
  const selected=kept([...forward,...reverse]);
  // Le recul est retenu dès qu'il sort du rayon d'incertitude, puis suivi tant qu'il garde sa direction.
  expect(selected.slice(0,6)).toEqual([0,1,2,3,4,5]);expect(selected.some(sequence=>sequence>=9)).toBe(true);
  const last=selectTrack([...forward,...reverse]).at(-1)!;expect(last.point.longitude).toBeLessThan(26*M);
 });
 it('parking : une manœuvre lente garde ses sommets, sans rupture',()=>{
  const points=Array.from({length:30},(_,i)=>fix(i,i*2,Math.min(i,15)*2.5,Math.max(0,i-15)*2.5,3));
  const selected=selectTrack(points);expect(selected.length).toBeGreaterThan(20);expect(selected.filter(s=>s.startsFragment)).toHaveLength(1);
 });
 it('arrêt au feu : la dérive du capteur ne dessine rien, et le départ ne coupe pas le tracé',()=>{
  const arrive=Array.from({length:5},(_,i)=>fix(i,i,i*10));
  const stop=Array.from({length:40},(_,i)=>fix(5+i,5+i,40+noise(i,3),noise(i+7,3),6));
  const leave=Array.from({length:5},(_,i)=>fix(45+i,45+i,50+i*10));
  const selected=selectTrack([...arrive,...stop,...leave]);
  expect(selected.map(s=>s.point.sequence)).toEqual([0,1,2,3,4,45,46,47,48,49]);
  expect(selected.filter(s=>s.startsFragment)).toHaveLength(1);
  expect(selected[4]!.heldUntilMs).toBe(44_000);
 });
 it('perte de signal : la reprise ouvre un nouveau tronçon, sans ligne à travers la lacune',()=>{
  const points=[fix(0,0,0),fix(1,1,10),fix(2,2,20),fix(3,40,900),fix(4,41,910)];
  expect(starts(points)).toEqual([true,false,false,true,false]);
 });
 it('point aberrant : un saut impossible est écarté sans couper la ligne',()=>{
  const points=[fix(0,0,0),fix(1,1,10),fix(2,2,1000),fix(3,3,30),fix(4,4,40)];
  expect(kept(points)).toEqual([0,1,3,4]);expect(starts(points)).toEqual([true,false,false,false]);
 });
 it('pic latéral : une mesure jetée de côté puis revenue en deux secondes est retirée',()=>{
  const points=[fix(0,0,0),fix(1,1,10),fix(2,2,20),fix(3,3,30,35),fix(4,4,40),fix(5,5,50)];
  expect(kept(points)).toEqual([0,1,2,4,5]);expect(starts(points).filter(Boolean)).toHaveLength(1);
 });
 it('mesures imprécises ou dans le désordre : écartées, jamais reliées',()=>{
  expect(kept([fix(0,0,0,0,80),fix(1,1,0),fix(2,2,10)])).toEqual([1,2]);
  const ordered=[0,1,2,3].map(i=>fix(i,i,i*10));
  expect(kept([ordered[2]!,ordered[3]!,ordered[0]!,ordered[1]!])).toEqual([0,1,2,3]);
  expect(starts([fix(0,0,0),fix(2,2,20)])).toEqual([true,true]);
  // Un temps qui n'avance pas ne produit ni point ni raccord.
  expect(kept([fix(0,0,0),fix(1,1,10),{...fix(2,1,20)},fix(3,3,30)])).toEqual([0,1,3]);
 });
 it('longue zone brouillée : au-delà de quelques secondes sans mesure fiable, le tracé est coupé',()=>{
  const points=[fix(0,0,0),fix(1,1,10),...Array.from({length:8},(_,i)=>fix(2+i,2+i,20+i*10,0,90)),fix(10,10,100),fix(11,11,110)];
  expect(kept(points)).toEqual([0,1,10,11]);expect(starts(points)).toEqual([true,false,true,false]);
 });
});

describe('préparation des lots',()=>{
 it('garde les extrémités, les arrêts et un point tous les vingt mètres, jamais deux dans la même seconde',()=>{
  const run=continuousRuns(selectTrack(Array.from({length:101},(_,i)=>fix(i,i,i*5))))[0]!;
  const points=matcherPoints(run);
  expect(points[0]!.sequence).toBe(0);expect(points.at(-1)!.sequence).toBe(100);
  for(let i=1;i<points.length;i++)expect(points[i]!.timestampMs-points[i-1]!.timestampMs).toBeGreaterThanOrEqual(1000);
  expect(points.length).toBeGreaterThan(20);expect(points.length).toBeLessThan(30);
  expect(points.every(p=>p.radiusMeters>=10&&p.radiusMeters<=40)).toBe(true);
 });
 it('respecte la limite de cent points et raccorde deux lots voisins sur un point commun',()=>{
  expect(batches(1)).toEqual([]);expect(batches(100)).toEqual([{start:0,end:100,from:0,to:99}]);
  const parts=batches(260);
  expect(parts.every(p=>p.end-p.start<=100&&p.end-p.start>=2)).toBe(true);
  expect(parts[0]!.from).toBe(0);expect(parts.at(-1)!.to).toBe(259);
  for(let i=1;i<parts.length;i++){expect(parts[i]!.from).toBe(parts[i-1]!.to);expect(parts[i]!.from).toBeGreaterThan(parts[i]!.start);expect(parts[i-1]!.to).toBeLessThan(parts[i-1]!.end-1);}
 });
 it('encode et décode une polyligne à la précision 6',()=>{
  const line:[number,number][]=[[46.5191,6.6323],[46.52,6.63301],[-33.865143,151.2099],[0,0]];
  const decoded=decodePolyline(encodePolyline(line));
  decoded.forEach((p,i)=>{expect(p[0]).toBeCloseTo(line[i]![0],6);expect(p[1]).toBeCloseTo(line[i]![1],6);});
  expect(decodePolyline('\u0001')).toEqual([]);
 });
});

/** Moteur factice : une route est-ouest à 3 m au nord des mesures ; il y accroche chaque point. */
const road=(offsetNorth=3)=>async(points:MatcherPoint[]):Promise<MatcherResult>=>({
 matchings:[{confidence:0.9,geometry:[[offsetNorth*M,points[0]!.longitude],[offsetNorth*M,points.at(-1)!.longitude]]}],
 tracepoints:points.map(p=>({matchingIndex:0,latitude:offsetNorth*M,longitude:p.longitude}))
});
const straight=(count:number,step=25)=>Array.from({length:count},(_,i)=>fix(i,i*2,i*step,noise(i,2)));
const SEGMENT='11111111-1111-4111-8111-111111111111';

describe('assemblage des tronçons recalés',()=>{
 it('accroche le trajet à la route, avec un repère par mesure le long de la géométrie',async()=>{
  const spans=await matchTrack([{segmentId:SEGMENT,points:straight(40)}],road(),0.5);
  expect(spans).toHaveLength(1);
  const span=spans[0]!,geometry=decodePolyline(span.geometry);
  expect(span).toMatchObject({segmentId:SEGMENT,firstSequence:0,lastSequence:39,confidence:0.9});
  expect(geometry.every(p=>Math.abs(p[0]-3*M)<1e-6)).toBe(true);
  expect(span.anchors[0]).toEqual([0,0]);
  for(let i=1;i<span.anchors.length;i++){expect(span.anchors[i]![0]).toBeGreaterThan(span.anchors[i-1]![0]);expect(span.anchors[i]![1]).toBeGreaterThanOrEqual(span.anchors[i-1]![1]);}
  expect(span.anchors.at(-1)![1]).toBeCloseTo(meters(geometry[0]![0],geometry[0]![1],geometry.at(-1)![0],geometry.at(-1)![1]),0);
 });
 it('trajet long : les lots se suivent sans trou ni chevauchement',async()=>{
  let calls=0;const matcher=road(),counted=async(points:MatcherPoint[])=>{calls++;expect(points.length).toBeLessThanOrEqual(100);return matcher(points);};
  const spans=await matchTrack([{segmentId:SEGMENT,points:straight(450)}],counted,0.5);
  expect(calls).toBeGreaterThan(4);expect(spans.length).toBe(calls);
  expect(spans[0]!.firstSequence).toBe(0);expect(spans.at(-1)!.lastSequence).toBe(449);
  for(let i=1;i<spans.length;i++)expect(spans[i]!.firstSequence).toBe(spans[i-1]!.lastSequence);
 });
 it('faible confiance : rien n’est forcé sur une route',async()=>{
  const unsure=async(points:MatcherPoint[])=>{const r=await road()(points);r.matchings[0]!.confidence=0.2;return r;};
  expect(await matchTrack([{segmentId:SEGMENT,points:straight(30)}],unsure,0.5)).toEqual([]);
 });
 it('parking ou zone non couverte : les points sans route coupent le tronçon, la mesure reste',async()=>{
  const partial=async(points:MatcherPoint[])=>{const r=await road()(points);r.tracepoints=r.tracepoints.map((t,i)=>i>=10&&i<15?null:t);return r;};
  const spans=await matchTrack([{segmentId:SEGMENT,points:straight(30)}],partial,0.5);
  expect(spans).toHaveLength(2);
  expect(spans[0]!.lastSequence).toBeLessThan(spans[1]!.firstSequence);
  const none=async(points:MatcherPoint[]):Promise<MatcherResult>=>({matchings:[],tracepoints:points.map(()=>null)});
  expect(await matchTrack([{segmentId:SEGMENT,points:straight(30)}],none,0.5)).toEqual([]);
 });
 it('une accroche trop loin de la mesure est refusée',async()=>{
  expect(await matchTrack([{segmentId:SEGMENT,points:straight(30)}],road(80),0.5)).toEqual([]);
 });
 it('une lacune sépare deux recalages : aucun tronçon ne la traverse',async()=>{
  const first=straight(20),second=straight(20).map(p=>({...p,sequence:p.sequence+20,elapsedMs:p.elapsedMs+120_000,capturedAt:new Date(START+p.elapsedMs+120_000).toISOString(),longitude:p.longitude+5000*M}));
  const spans=await matchTrack([{segmentId:SEGMENT,points:[...first,...second]}],road(),0.5);
  expect(spans.map(s=>[s.firstSequence,s.lastSequence])).toEqual([[0,19],[20,39]]);
 });
 it('réponse incohérente : ignorée plutôt qu’interprétée',()=>{
  const points=matcherPoints(continuousRuns(selectTrack(straight(10)))[0]!);
  expect(spansFromBatch(SEGMENT,points,{matchings:[{confidence:1,geometry:[[0,0],[0,1]]}],tracepoints:[null]},{from:0,to:points.length-1},0.5)).toEqual([]);
  const a={segmentId:SEGMENT,firstSequence:0,lastSequence:10,confidence:0.6,geometry:'x',anchors:[[0,0],[10,5]] as [number,number][]};
  expect(mergeSpans([{...a,firstSequence:5,lastSequence:20,confidence:0.9},a]).map(s=>s.confidence)).toEqual([0.9]);
 });
 it('panne du moteur : l’erreur remonte, sans résultat partiel présenté comme complet',async()=>{
  const failing=async()=>{throw new MapMatchingError('PROVIDER_UNAVAILABLE');};
  await expect(matchTrack([{segmentId:SEGMENT,points:straight(30)}],failing,0.5)).rejects.toMatchObject({failure:'PROVIDER_UNAVAILABLE'});
 });
});

describe('client du moteur de recalage',()=>{
 // Valeur de forme valide assemblée ici : aucun jeton, même factice, n'est écrit dans le dépôt.
 const placeholder=['synthetic','value','for','tests','only'].join('-');
 const points:MatcherPoint[]=[{sequence:0,latitude:0,longitude:0,timestampMs:START,radiusMeters:15},{sequence:1,latitude:0,longitude:0.001,timestampMs:START+5000,radiusMeters:15}];
 const reply=(status:number,body:unknown)=>async()=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
 it('sans configuration : pas de recalage ; partielle ou invalide : refus sans afficher de secret',()=>{
  expect(readMapMatchingConfig({})).toBeUndefined();
  expect(readMapMatchingConfig({MAP_MATCHING_PROVIDER:'osrm',MAP_MATCHING_BASE_URL:'http://127.0.0.1:5000'})).toMatchObject({provider:'osrm',baseURL:'http://127.0.0.1:5000',minimumConfidence:0.5});
  for(const env of [{MAP_MATCHING_PROVIDER:'mapbox'},{MAP_MATCHING_PROVIDER:'osrm'},{MAP_MATCHING_PROVIDER:'osrm',MAP_MATCHING_BASE_URL:'http://example.invalid'},{MAP_MATCHING_PROVIDER:'other',MAP_MATCHING_BASE_URL:'https://example.invalid'},{MAP_MATCHING_ACCESS_TOKEN:placeholder}]){
   expect(()=>readMapMatchingConfig(env)).toThrow('aucun secret');
  }
 });
 it('Mapbox : le jeton reste dans l’URL du serveur, les coordonnées dans le corps',async()=>{
  const config=readMapMatchingConfig({MAP_MATCHING_PROVIDER:'mapbox',MAP_MATCHING_ACCESS_TOKEN:placeholder})!;
  let seen:{url:string;init:RequestInit}|undefined;
  const matcher=createMapMatcher(config,(async(url:string,init:RequestInit)=>{seen={url,init};return reply(200,{code:'Ok',matchings:[{confidence:0.8,geometry:encodePolyline([[0,0],[0,0.001]])}],tracepoints:[{matchings_index:0,location:[0,0]},null]})();}) as never);
  const result=await matcher(points);
  expect(seen!.url).toBe(`https://api.mapbox.com/matching/v5/mapbox/driving?access_token=${placeholder}`);
  expect(seen!.init.method).toBe('POST');expect(String(seen!.init.body)).toContain('geometries=polyline6');expect(String(seen!.init.body)).toContain('timestamps=');
  expect(result.matchings[0]!.geometry).toHaveLength(2);expect(result.tracepoints).toEqual([{matchingIndex:0,latitude:0,longitude:0},null]);
 });
 it('OSRM auto-hébergé : même format, sans jeton',async()=>{
  const config=readMapMatchingConfig({MAP_MATCHING_PROVIDER:'osrm',MAP_MATCHING_BASE_URL:'http://127.0.0.1:5000/'})!;
  let url='';await createMapMatcher(config,(async(u:string)=>{url=u;return reply(200,{code:'NoMatch'})();}) as never)(points);
  expect(url.startsWith('http://127.0.0.1:5000/match/v1/driving/0.000000,0.000000;0.001000,0.000000?')).toBe(true);expect(url).not.toContain('access_token');
 });
 it('« aucune route » est un résultat ; limite, panne et réponse illisible sont des échecs distincts',async()=>{
  const config=readMapMatchingConfig({MAP_MATCHING_PROVIDER:'osrm',MAP_MATCHING_BASE_URL:'http://127.0.0.1:5000'})!;
  const run=(status:number,body:unknown)=>createMapMatcher(config,reply(status,body) as never)(points);
  expect(await run(200,{code:'NoSegment'})).toEqual({matchings:[],tracepoints:[null,null]});
  await expect(run(429,{code:'x'})).rejects.toMatchObject({failure:'RATE_LIMITED'});
  await expect(run(503,{})).rejects.toMatchObject({failure:'PROVIDER_UNAVAILABLE'});
  await expect(run(401,{code:'InvalidToken'})).rejects.toMatchObject({failure:'PROVIDER_REFUSED'});
  await expect(run(200,{code:'Ok',matchings:[],tracepoints:[null]})).rejects.toMatchObject({failure:'INVALID_RESPONSE'});
  await expect(createMapMatcher(config,(async()=>{throw new Error('réseau');}) as never)(points)).rejects.toMatchObject({failure:'PROVIDER_UNAVAILABLE'});
 });
 it('géométrie illisible : rejet en réponse incohérente, jamais un résultat « aucune route »',async()=>{
  const config=readMapMatchingConfig({MAP_MATCHING_PROVIDER:'osrm',MAP_MATCHING_BASE_URL:'http://127.0.0.1:5000'})!;
  expect(decodePolyline('!!!')).toEqual([]);
  const body={code:'Ok',matchings:[{confidence:0.9,geometry:'!!!'}],tracepoints:[{matchings_index:0,waypoint_index:0,location:[0,0]},{matchings_index:0,waypoint_index:1,location:[0.001,0]}]};
  await expect(createMapMatcher(config,reply(200,body) as never)(points)).rejects.toMatchObject({failure:'INVALID_RESPONSE'});
 });
});
