import {createHash} from 'node:crypto';
import type {FastifyInstance} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandEffect} from './commands.js';
import {ApiError,forbidden} from './errors.js';
import {visibleObservationThemes} from './observation-themes.js';
import {rankThemes,reconcileOrder,type ThemeUsage} from './observation-ranking-engine.js';

/**
 * Classement intelligent des signalements, propre à chaque moniteur. Le moteur (observation-ranking-engine.ts) classe ; ce fichier
 * lit les usages, garde le résultat et le publie. Le classement se refait au plus une fois par jour (date locale de l'école), à la
 * première lecture du jour, sur les usages des jours précédents : deux appareils lisent donc le même ordre, et une leçon en cours
 * ne déplace rien. L'ordre manuel de l'école n'est jamais modifié. Contrat : docs/implementation/classement-intelligent-20261013.md.
 */
const command=z.object({operationId:z.uuid(),mode:z.enum(['MANUAL','SMART'])}).strict();
type Mode=z.infer<typeof command>['mode'];
interface Row {version:number;mode:Mode;ranked_order:string[];ranked_on:string|null}
export interface ObservationRanking {id:string;schoolId:string;membershipId:string;version:number;mode:Mode;order:string[];rankedOn:string|null}
const staff=['ADMIN','INSTRUCTOR'];

async function ranking(db:PoolClient,schoolId:string,membershipId:string,lock=false):Promise<Row|undefined>{
 return (await db.query<Row>(`SELECT version,mode,ranked_order,to_char(ranked_on,'YYYY-MM-DD') AS ranked_on FROM drivy.observation_ranking
  WHERE school_id=$1 AND membership_id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,membershipId])).rows[0];
}
/** Le classement enregistré, ramené aux thèmes que l'école affiche aujourd'hui. En mode manuel, aucun ordre n'est publié. */
function projection(schoolId:string,membershipId:string,row:Row|undefined,manual:readonly string[]):ObservationRanking{
 const smart=row?.mode==='SMART';
 return {id:membershipId,schoolId,membershipId,version:row?.version??1,mode:row?.mode??'MANUAL',order:smart?reconcileOrder(row.ranked_order,manual):[],rankedOn:smart?row.ranked_on:null};
}
async function localDay(db:PoolClient,timeZone:string):Promise<string>{
 return (await db.query<{day:string}>("SELECT to_char((now() AT TIME ZONE $1)::date,'YYYY-MM-DD') AS day",[timeZone])).rows[0]!.day;
}
/**
 * Usages du compte courant par thème, leçon et jour local, jusqu'à la veille (drivy.observation_theme_usage). Seuls comptent les
 * signalements faits dans la palette pendant une leçon et toujours présents : un signalement annulé ne compte pas, et un renvoi
 * réseau n'a jamais créé de seconde ligne.
 */
async function usage(db:PoolClient,schoolId:string,timeZone:string):Promise<ThemeUsage[]>{
 return (await db.query<ThemeUsage>(`SELECT theme_key AS "themeKey",lesson_id AS "lessonId",to_char(day,'YYYY-MM-DD') AS day,uses,palette_position AS position
  FROM drivy.observation_theme_usage($1,$2)`,[schoolId,timeZone])).rows;
}
const elapsedDays=(from:string|null,to:string)=>from?Math.max(1,Math.round((Date.parse(to)-Date.parse(from))/86_400_000)):1;
/** Une seule opération par moniteur et par passage d'un jour au suivant : la lecture d'un second appareil rejoue la première au lieu de reclasser. */
function dailyOperation(membershipId:string,from:string|null,day:string):string{
 const hex=createHash('sha256').update(`observation-ranking:${membershipId}:${from??''}:${day}`).digest('hex');
 return `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-8${hex.slice(17,20)}-${hex.slice(20,32)}`;
}

/** Rang de la tuile d'un thème dans « Signaler » pour ce moniteur, à cet instant ; `null` si le thème n'y est pas affiché. */
export async function palettePosition(db:PoolClient,schoolId:string,membershipId:string,themeKey:string):Promise<number|null>{
 const manual=await visibleObservationThemes(db,schoolId),row=await ranking(db,schoolId,membershipId);
 const index=(row?.mode==='SMART'?reconcileOrder(row.ranked_order,manual):manual).indexOf(themeKey);
 return index<0?null:index+1;
}

export function registerObservationRanking(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const path='/v1/schools/:schoolId/observation-ranking';
 const schoolID=(params:unknown)=>z.object({schoolId:z.uuid()}).parse(params).schoolId;
 const current=async(db:PoolClient,schoolId:string,membershipId:string)=>projection(schoolId,membershipId,await ranking(db,schoolId,membershipId),await visibleObservationThemes(db,schoolId));
 app.get(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),identity=await options.verifyToken(r.headers.authorization);
  const read=await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
   if(!member?.roles.some(role=>staff.includes(role)))throw forbidden();
   const row=await ranking(db,schoolId,member.id),data=projection(schoolId,member.id,row,await visibleObservationThemes(db,schoolId));
   if(row?.mode!=='SMART')return {data,day:null,from:null};
   const zone=(await db.query<{time_zone:string}>('SELECT time_zone FROM drivy.school WHERE id=$1',[schoolId])).rows[0]?.time_zone;
   const day=zone?await localDay(db,zone):null;
   return {data,day:day&&row.ranked_on!==day?day:null,from:row.ranked_on};
  });
  let data=read.data;
  if(read.day){
   // Premier passage du jour : le classement est refait et gardé. Une école archivée garde simplement le dernier.
   try{
    data=await schoolCommand(options.pool,identity,schoolId,'REFRESH_OBSERVATION_RANKING',{operationId:dailyOperation(data.membershipId,read.from,read.day)},null,async(db,actor,school)=>{
     const row=await ranking(db,school.id,actor.membershipId,true),manual=await visibleObservationThemes(db,school.id),day=await localDay(db,school.timeZone);
     const before=projection(school.id,actor.membershipId,row,manual);let changed=false;
     if(row?.mode==='SMART'&&row.ranked_on!==day){
      const {order}=rankThemes({manual,previous:row.ranked_order,usage:await usage(db,school.id,school.timeZone),elapsedDays:elapsedDays(row.ranked_on,day)});
      changed=order.join()!==before.order.join();
      await db.query('UPDATE drivy.observation_ranking SET ranked_order=$3,ranked_on=$4::date,version=version+$5,updated_at=now() WHERE school_id=$1 AND membership_id=$2',[school.id,actor.membershipId,order,day,changed?1:0]);
     }
     return {data:await current(db,school.id,actor.membershipId),action:'ObservationRankingRefreshed',resourceType:'ObservationRanking',resourceId:actor.membershipId,changedFields:changed?['order']:[]};
    },staff,{replay:(db,actor)=>current(db,schoolId,actor.membershipId)});
   }catch(error){if(!(error instanceof ApiError&&error.code==='SCHOOL_ARCHIVED'))throw error;}
  }
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
 app.put(path,{bodyLimit:1_024},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=command.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'SAVE_OBSERVATION_RANKING',body,expected,async(db,actor,school):Promise<CommandEffect<ObservationRanking>>=>{
   const previous=await ranking(db,school.id,actor.membershipId,true);checkVersion(previous?.version??1,expected);
   // À l'activation, le classement repart des scores seuls : l'ordre montré la veille en mode manuel ne retient rien.
   // Au retour en mode manuel, le dernier classement reste en base sans être publié ; l'ordre de l'école n'a jamais été touché.
   let order=previous?.ranked_order??[],day:string|null=null;
   if(body.mode==='SMART'){
    day=await localDay(db,school.timeZone);
    order=rankThemes({manual:await visibleObservationThemes(db,school.id),usage:await usage(db,school.id,school.timeZone)}).order;
   }
   await db.query(`INSERT INTO drivy.observation_ranking(school_id,membership_id,version,mode,ranked_order,ranked_on) VALUES($1,$2,2,$3,$4,$5::date)
    ON CONFLICT(school_id,membership_id) DO UPDATE SET version=observation_ranking.version+1,mode=EXCLUDED.mode,ranked_order=EXCLUDED.ranked_order,ranked_on=EXCLUDED.ranked_on,updated_at=now()`,[school.id,actor.membershipId,body.mode,order,day]);
   return {data:await current(db,school.id,actor.membershipId),action:'ObservationRankingSaved',resourceType:'ObservationRanking',resourceId:actor.membershipId,changedFields:['mode']};
  },staff,{
   // Un rejeu rend le classement actuel du moniteur, jamais une copie ancienne présentée comme courante.
   replay:(db,actor)=>current(db,schoolId,actor.membershipId)
  });
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
}
