import {performance} from 'node:perf_hooks';
import {z} from 'zod';

/** Couche d'affichage éphémère. Aucune mesure corrigée ne remplace la mesure source. */
export const LIVE_MATCH_TIMEOUT_MS=750;
export const liveMatchRequest=z.object({
 segmentId:z.uuid().transform(value=>value.toLowerCase()),
 points:z.array(z.object({
  sequence:z.number().int().min(0).max(2_147_483_646),
  elapsedMs:z.number().int().min(0).max(10_800_000),
  capturedAt:z.iso.datetime({offset:true}),
  latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),
  accuracyMeters:z.number().min(0).max(10_000),speed:z.number().min(0).max(100).optional()
 }).strict()).min(3).max(20)
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
export type LiveMatchResult=Anchor&({status:'UNAVAILABLE'}|{status:'MATCHED';position:{latitude:number;longitude:number};confidence:number;distanceMeters:number});
/** Le transport ne connaît pas les captures, identités ou droits. Son résultat est validé avant toute projection. */
export type LiveMatcher=(points:LivePoint[],signal:AbortSignal)=>Promise<unknown>;

const osrmResponse=z.object({
 code:z.literal('Ok'),
 matchings:z.array(z.object({confidence:z.number().min(0).max(1)})).min(1).max(20),
 tracepoints:z.array(z.object({
  location:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90)]),
  matchings_index:z.number().int().min(0).max(19),alternatives_count:z.number().int().min(0)
 }).nullable()).min(3).max(20)
});
type Position={latitude:number;longitude:number};
function distance(a:Position,b:Position):number {
 const r=Math.PI/180,lat=(b.latitude-a.latitude)*r,lon=(b.longitude-a.longitude)*r;
 const h=Math.sin(lat/2)**2+Math.cos(a.latitude*r)*Math.cos(b.latitude*r)*Math.sin(lon/2)**2;
 return 6_371_000*2*Math.asin(Math.sqrt(Math.min(1,h)));
}
const maximumCorrection=(p:LivePoint)=>Math.min(20,Math.max(5,p.accuracyMeters));
function direction(a:Position,b:Position):readonly[number,number] {
 const longitude=((b.longitude-a.longitude+540)%360)-180;
 return [longitude*Math.cos((a.latitude+b.latitude)*Math.PI/360),b.latitude-a.latitude];
}
const opposed=(a:readonly[number,number],b:readonly[number,number])=>a[0]*b[0]+a[1]*b[1]<0;
function suitable(points:LivePoint[],now:number):boolean {
 const first=points[0]!,last=points.at(-1)!;
 if(now-Date.parse(last.capturedAt)>10_000||Date.parse(last.capturedAt)>now+10_000||now-Date.parse(first.capturedAt)>40_000)return false;
 if(points.some(p=>p.accuracyMeters>30)||(last.speed!==undefined&&last.speed<2))return false;
 let length=0;
 for(let i=1;i<points.length;i++){
  const a=points[i-1]!,b=points[i]!,seconds=(b.elapsedMs-a.elapsedMs)/1000,meters=distance(a,b);
  if(seconds>5||meters/seconds>50)return false;
  if(i===points.length-1&&meters/seconds<2)return false;
  length+=meters;
 }
 const net=distance(first,last);
 // Une longue progression ne doit pas masquer les premiers mètres d'un demi-tour.
 // Les quatre dernières transitions et la direction avant la dernière mesure sont relues séparément.
 for(let i=Math.max(2,points.length-4);i<points.length;i++){
  if(opposed(direction(points[i-2]!,points[i-1]!),direction(points[i-1]!,points[i]!)))return false;
 }
 if(opposed(direction(first,points.at(-2)!),direction(points.at(-2)!,last)))return false;
 // Un stationnement, un retour sur ses pas ou une manœuvre restent des mesures, jamais un collage routier.
 return net>=10&&net/length>=.75;
}

export async function matchLive(input:LiveMatchInput,matcher?:LiveMatcher):Promise<LiveMatchResult> {
 const last=input.points.at(-1)!;
 const anchor:Anchor={segmentId:input.segmentId,sequence:last.sequence,elapsedMs:last.elapsedMs};
 const unavailable:LiveMatchResult={...anchor,status:'UNAVAILABLE'};
 if(!matcher||!suitable(input.points,Date.now()))return unavailable;
 const controller=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
 try {
  // Le délai couvre aussi la lecture du corps. L'abandon arrête le fetch natif, sans exposer URL ni erreur du moteur.
  const timedOut=new Promise<undefined>(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(undefined);},LIVE_MATCH_TIMEOUT_MS);});
  const raw=await Promise.race([Promise.resolve().then(()=>matcher(input.points,controller.signal)),timedOut]);
  const parsed=osrmResponse.safeParse(raw);
  if(!parsed.success||!suitable(input.points,Date.now()))return unavailable;
  const result=parsed.data;
  if(result.tracepoints.length!==input.points.length)return unavailable;
  const tail=result.tracepoints.at(-1);
  if(!tail)return unavailable;
  const matching=result.matchings[tail.matchings_index];
  if(!matching||matching.confidence<.8)return unavailable;
  for(let i=0;i<result.tracepoints.length;i++){
   const t=result.tracepoints[i],p=input.points[i]!;
   if(!t||t.matchings_index!==tail.matchings_index||t.alternatives_count!==0)return unavailable;
   if(distance(p,{latitude:t.location[1],longitude:t.location[0]})>maximumCorrection(p))return unavailable;
  }
  const position={latitude:tail.location[1],longitude:tail.location[0]};
  return {...anchor,status:'MATCHED',position,confidence:matching.confidence,distanceMeters:distance(last,position)};
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
   const parameters=new URLSearchParams({overview:'false',steps:'false',annotations:'false',tidy:'false',gaps:'split',radiuses:points.map(p=>Math.max(1,p.accuracyMeters)).join(';')});
   const timestamps=points.map(p=>Math.floor(Date.parse(p.capturedAt)/1000));
   if(timestamps.every((value,index)=>index===0||value>timestamps[index-1]!))parameters.set('timestamps',timestamps.join(';'));
   const reply=await fetcher(`${root}/match/v1/driving/${coordinates}?${parameters}`,{method:'GET',redirect:'error',signal});
   if(!reply.ok||!reply.body||Number(reply.headers.get('content-length'))>65_536){await reply.body?.cancel();throw new Error();}
   reader=reply.body.getReader();const chunks:Uint8Array[]=[];let size=0;
   while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>65_536)throw new Error();chunks.push(part.value);}
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
