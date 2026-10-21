import {performance} from 'node:perf_hooks';
import {z} from 'zod';

/**
 * Couche d'affichage éphémère. Aucune mesure corrigée ne remplace la mesure source.
 *
 * Politique (issue #90, calibrée par le diagnostic #89) : le moteur reçoit des mesures espacées d'au moins
 * 20 m, jamais des mesures à 1 Hz serrées, sur lesquelles son modèle donne une confiance nulle. Un arrêt ne produit
 * donc aucune requête (pas d'étalement), une conduite lente en produit dès 40 m parcourus. La réponse porte la
 * position recalée de la dernière mesure et le tronçon routier qui relie les mesures retenues.
 */
export const LIVE_MATCH_TIMEOUT_MS=750;
export const LIVE_POLICY={spacingMeters:20,minimumPoints:3,minimumConfidence:.6,maximumAccuracyMeters:30,maximumGapMs:5000,
 maximumSpeed:50,straightness:.6,detourRatio:1.6,detourSlackMeters:30,maximumRouteVertices:400} as const;
export const liveMatchRequest=z.object({
 segmentId:z.uuid().transform(value=>value.toLowerCase()),
 points:z.array(z.object({
  sequence:z.number().int().min(0).max(2_147_483_646),
  elapsedMs:z.number().int().min(0).max(10_800_000),
  capturedAt:z.iso.datetime({offset:true}),
  latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),
  accuracyMeters:z.number().min(0).max(10_000),speed:z.number().min(0).max(100).optional()
 }).strict()).min(3).max(30)
}).strict().superRefine(({points},ctx)=>{
 const first=points[0],last=points.at(-1);
 if(!first||!last)return;
 const invalid=()=>ctx.addIssue({code:'custom',message:'Fenêtre de mesures invalide.'});
 if(last.elapsedMs-first.elapsedMs>30_000||Date.parse(last.capturedAt)-Date.parse(first.capturedAt)>30_000)invalid();
 for(let i=1;i<points.length;i++){
  const a=points[i-1]!,b=points[i]!,elapsed=b.elapsedMs-a.elapsedMs,wall=Date.parse(b.capturedAt)-Date.parse(a.capturedAt);
  if(b.sequence<=a.sequence||elapsed<=0||wall<=0||Math.abs(elapsed-wall)>1000)invalid();
 }
});
export type LiveMatchInput=z.infer<typeof liveMatchRequest>;
export type LivePoint=LiveMatchInput['points'][number];
type Anchor={segmentId:string;sequence:number;elapsedMs:number};
/** Tronçon routier : `coordinates` en [latitude, longitude] ; `anchors` relie chaque mesure retenue à son sommet. */
export type LiveRoute={coordinates:[number,number][];anchors:[number,number][]};
export type LiveMatchResult=Anchor&({status:'UNAVAILABLE'}|{status:'MATCHED';position:{latitude:number;longitude:number};confidence:number;distanceMeters:number;route:LiveRoute});
/** Le transport ne connaît pas les captures, identités ou droits. Son résultat est validé avant toute projection. */
export type LiveMatcher=(points:LivePoint[],signal:AbortSignal)=>Promise<unknown>;

const lonLat=z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90)]);
const osrmResponse=z.object({
 code:z.literal('Ok'),
 matchings:z.array(z.object({confidence:z.number().min(0).max(1),
  geometry:z.object({type:z.literal('LineString'),coordinates:z.array(lonLat).min(2).max(4000)})})).min(1).max(30),
 tracepoints:z.array(z.object({location:lonLat,matchings_index:z.number().int().min(0).max(29),alternatives_count:z.number().int().min(0)}).nullable()).min(3).max(30)
});
type Position={latitude:number;longitude:number};
function distance(a:Position,b:Position):number {
 const r=Math.PI/180,lat=(b.latitude-a.latitude)*r,lon=(b.longitude-a.longitude)*r;
 const h=Math.sin(lat/2)**2+Math.cos(a.latitude*r)*Math.cos(b.latitude*r)*Math.sin(lon/2)**2;
 return 6_371_000*2*Math.asin(Math.sqrt(Math.min(1,h)));
}
/** Écart toléré entre une mesure et sa place sur la route : deux fois et demie sa précision annoncée, 10 à 25 m. */
export const maximumCorrection=(accuracyMeters:number)=>Math.min(25,Math.max(10,accuracyMeters*2.5));
function direction(a:Position,b:Position):readonly[number,number] {
 const longitude=((b.longitude-a.longitude+540)%360)-180;
 return [longitude*Math.cos((a.latitude+b.latitude)*Math.PI/360),b.latitude-a.latitude];
}
const opposed=(a:readonly[number,number],b:readonly[number,number])=>a[0]*b[0]+a[1]*b[1]<0;
const pathLength=(points:Position[])=>points.reduce((sum,p,i)=>i?sum+distance(points[i-1]!,p):0,0);

/**
 * Mesures confiées au moteur, ou `undefined` quand la fenêtre ne doit pas être recalée : trop ancienne, avec une
 * lacune ou un bond, immobile (moins de trois mesures à 20 m les unes des autres), demi-tour ou manœuvre.
 */
export function liveCandidates(points:LivePoint[],now:number):LivePoint[]|undefined {
 const first=points[0]!,last=points.at(-1)!;
 if(now-Date.parse(last.capturedAt)>10_000||Date.parse(last.capturedAt)>now+10_000||now-Date.parse(first.capturedAt)>40_000)return;
 if(last.accuracyMeters>LIVE_POLICY.maximumAccuracyMeters)return;
 const usable=points.filter(p=>p.accuracyMeters<=LIVE_POLICY.maximumAccuracyMeters);
 for(let i=1;i<usable.length;i++){
  const a=usable[i-1]!,b=usable[i]!,seconds=(b.elapsedMs-a.elapsedMs)/1000;
  if(seconds>LIVE_POLICY.maximumGapMs/1000||distance(a,b)/seconds>LIVE_POLICY.maximumSpeed)return;
 }
 const kept=[last];
 for(let i=usable.length-2;i>=0;i--)if(distance(kept[0]!,usable[i]!)>=LIVE_POLICY.spacingMeters)kept.unshift(usable[i]!);
 if(kept.length<LIVE_POLICY.minimumPoints)return;
 // Un demi-tour ou une marche arrière restent des mesures, jamais un collage routier.
 for(let i=Math.max(2,kept.length-4);i<kept.length;i++)if(opposed(direction(kept[i-2]!,kept[i-1]!),direction(kept[i-1]!,kept[i]!)))return;
 if(distance(kept[0]!,last)/pathLength(kept)<LIVE_POLICY.straightness)return;
 return kept;
}

/** Insère chaque mesure recalée à sa place sur la géométrie, dans l'ordre, et donne l'indice de son sommet. */
function anchoredRoute(geometry:[number,number][],placed:{sequence:number;position:Position}[]):LiveRoute|undefined {
 const line=geometry.map(([longitude,latitude])=>({latitude,longitude}));
 const out:Position[]=[],anchors:[number,number][]=[];
 let cursor=0;
 for(const {sequence,position} of placed){
  let best=-1,bestOffset=Infinity;
  for(let j=Math.max(1,cursor);j<line.length;j++){
   const a=line[j-1]!,b=line[j]!,scale=Math.cos(a.latitude*Math.PI/180)||1;
   const dx=(b.longitude-a.longitude)*scale,dy=b.latitude-a.latitude,square=dx*dx+dy*dy;
   const t=square>0?Math.max(0,Math.min(1,((position.longitude-a.longitude)*scale*dx+(position.latitude-a.latitude)*dy)/square)):0;
   const offset=distance(position,{latitude:a.latitude+dy*t,longitude:a.longitude+dx*t/scale});
   if(offset<bestOffset){bestOffset=offset;best=j;}
   if(offset<.5)break;
  }
  if(best<0||bestOffset>3)return;
  // Sommets de la route entre l'ancre précédente et celle-ci ; un sommet confondu avec un point déjà posé est omis.
  if(anchors.length>0)for(let k=cursor;k<best;k++){const v=line[k]!;if(distance(v,out.at(-1)!)>.5&&distance(v,position)>.5)out.push(v);}
  out.push(position);
  anchors.push([sequence,out.length-1]);
  cursor=best;
 }
 if(out.length<2||out.length>LIVE_POLICY.maximumRouteVertices)return;
 return {coordinates:out.map(p=>[Math.round(p.latitude*1e7)/1e7,Math.round(p.longitude*1e7)/1e7]),anchors};
}

export async function matchLive(input:LiveMatchInput,matcher?:LiveMatcher):Promise<LiveMatchResult> {
 const last=input.points.at(-1)!;
 const anchor:Anchor={segmentId:input.segmentId,sequence:last.sequence,elapsedMs:last.elapsedMs};
 const unavailable:LiveMatchResult={...anchor,status:'UNAVAILABLE'};
 const kept=matcher?liveCandidates(input.points,Date.now()):undefined;
 if(!matcher||!kept)return unavailable;
 const controller=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
 try {
  // Le délai couvre aussi la lecture du corps. L'abandon arrête le fetch natif, sans exposer URL ni erreur du moteur.
  const timedOut=new Promise<undefined>(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(undefined);},LIVE_MATCH_TIMEOUT_MS);});
  const raw=await Promise.race([Promise.resolve().then(()=>matcher(kept,controller.signal)),timedOut]);
  const parsed=osrmResponse.safeParse(raw);
  if(!parsed.success||!liveCandidates(input.points,Date.now()))return unavailable;
  const result=parsed.data;
  if(result.tracepoints.length!==kept.length)return unavailable;
  const tail=result.tracepoints.at(-1);
  if(!tail)return unavailable;
  const matching=result.matchings[tail.matchings_index];
  if(!matching||matching.confidence<LIVE_POLICY.minimumConfidence)return unavailable;
  // Suite continue de mesures placées sur le même tronçon, jusqu'à la dernière.
  const placed:{sequence:number;position:Position;point:LivePoint}[]=[];
  for(let i=kept.length-1;i>=0;i--){
   const t=result.tracepoints[i];
   if(!t||t.matchings_index!==tail.matchings_index)break;
   placed.unshift({sequence:kept[i]!.sequence,position:{latitude:t.location[1],longitude:t.location[0]},point:kept[i]!});
  }
  if(placed.length<LIVE_POLICY.minimumPoints)return unavailable;
  for(const p of placed)if(distance(p.point,p.position)>maximumCorrection(p.point.accuracyMeters))return unavailable;
  // Un tronçon nettement plus long que le chemin mesuré est un détour inventé (boucle autour d'un pâté de maisons).
  const measured=pathLength(placed.map(p=>p.point)),road=pathLength(matching.geometry.coordinates.map(([longitude,latitude])=>({latitude,longitude})));
  if(road>measured*LIVE_POLICY.detourRatio+LIVE_POLICY.detourSlackMeters)return unavailable;
  const route=anchoredRoute(matching.geometry.coordinates,placed);
  if(!route)return unavailable;
  const [latitude,longitude]=route.coordinates.at(-1)!,position={latitude,longitude};
  return {...anchor,status:'MATCHED',position,confidence:Math.round(matching.confidence*1000)/1000,distanceMeters:Math.round(distance(last,position)*10)/10,route};
 } catch {return unavailable;} finally {if(timer!==undefined)clearTimeout(timer);}
}

/** OSRM privé uniquement. Pas de fournisseur public, de redirection ni de reprise vers un autre moteur. */
export function createOSRMLiveMatcher(baseURL:string,fetcher:typeof fetch=fetch):LiveMatcher {
 let base:URL;
 try {
  base=new URL(baseURL);
  const host=base.hostname;
  const privateHost=['localhost','127.0.0.1','[::1]'].includes(host)||/^(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$/.test(host);
  if(!privateHost||!['http:','https:'].includes(base.protocol)||base.username||base.password||base.search||base.hash)throw new Error();
 } catch {throw new Error('Configuration OSRM live invalide.');}
 const root=base.toString().replace(/\/+$/,'');
 return async(points,signal)=>{
  let reader:ReadableStreamDefaultReader<Uint8Array>|undefined;
  try {
   const coordinates=points.map(p=>`${p.longitude.toFixed(6)},${p.latitude.toFixed(6)}`).join(';');
   const parameters=new URLSearchParams({overview:'full',geometries:'geojson',steps:'false',annotations:'false',tidy:'false',gaps:'split',
    radiuses:points.map(p=>Math.round(Math.max(10,Math.min(30,p.accuracyMeters*2)))).join(';')});
   const timestamps=points.map(p=>Math.floor(Date.parse(p.capturedAt)/1000));
   if(timestamps.every((value,index)=>index===0||value>timestamps[index-1]!))parameters.set('timestamps',timestamps.join(';'));
   const reply=await fetcher(`${root}/match/v1/driving/${coordinates}?${parameters}`,{method:'GET',redirect:'error',signal});
   if(!reply.ok||!reply.body||Number(reply.headers.get('content-length'))>131_072){await reply.body?.cancel();throw new Error();}
   reader=reply.body.getReader();const chunks:Uint8Array[]=[];let size=0;
   while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>131_072)throw new Error();chunks.push(part.value);}
   return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
  } catch {throw new Error('LIVE_MATCH_UNAVAILABLE');}
  finally {if(reader){try{await reader.cancel();}catch{/* aucune donnée du transport */}reader.releaseLock();}}
 };
}

/** Une entrée par identité vérifiée, sans données GPS. Saturation: refus, jamais éviction d'un appel actif. */
export class LiveMatchLimiter {
 private readonly entries=new Map<string,{started:number;active:boolean}>();
 private active=0;
 private readonly config:{capacity:number;concurrency:number;intervalMs:number;ttlMs:number;now:()=>number};
 constructor(options:Partial<LiveMatchLimiter['config']>={}){
  this.config={capacity:1024,concurrency:8,intervalMs:2000,ttlMs:60_000,now:()=>performance.now(),...options};
 }
 acquire(identity:string):(()=>void)|undefined {
  const now=this.config.now();
  for(const [key,entry] of this.entries)if(!entry.active&&now-entry.started>=this.config.ttlMs)this.entries.delete(key);
  const previous=this.entries.get(identity);
  if(this.active>=this.config.concurrency||previous&&(previous.active||now-previous.started<this.config.intervalMs)||!previous&&this.entries.size>=this.config.capacity)return undefined;
  const entry={started:now,active:true};this.entries.set(identity,entry);this.active++;
  return ()=>{if(entry.active){entry.active=false;this.active--;}};
 }
}
