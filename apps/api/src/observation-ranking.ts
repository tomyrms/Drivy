import type {FastifyInstance} from 'fastify';
import type {Pool} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {checkIdempotency,requireVersion,schoolCommand,type CommandEffect} from './commands.js';
import {applyPreferencesSave,currentPreferences,loadPreferences,type Mode,type ObservationPreferences} from './observation-preferences.js';

/**
 * Ancienne route du classement intelligent, propre à chaque école et à chaque adhésion. Depuis le 11 novembre 2026 le classement vit sur
 * le compte (observation-preferences.ts) : cette route reste pour les apps déjà installées, avec leur forme d'origine, mais lit et écrit
 * les préférences du compte, communes à toutes les écoles. Elle ne crée plus aucune ligne propre à l'école.
 * Contrat : docs/implementation/r08-contrat-serveur-20261111.md (compatibilité), classement-intelligent-20261013.md (méthode).
 */
const command=z.object({operationId:z.uuid(),mode:z.enum(['MANUAL','SMART'])}).strict();
export interface ObservationRanking {id:string;schoolId:string;membershipId:string;version:number;mode:Mode;order:string[];rankedOn:string|null}
const staff=['ADMIN','INSTRUCTOR'];

/** Forme d'origine : en mode manuel, aucun ordre n'est publié. */
function legacy(data:ObservationPreferences,membershipId:string):ObservationRanking{
 const smart=data.mode==='SMART';
 return {id:membershipId,schoolId:data.schoolId,membershipId,version:data.version,mode:data.mode,order:smart?data.palette:[],rankedOn:smart?data.rankedOn:null};
}

export function registerObservationRanking(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const path='/v1/schools/:schoolId/observation-ranking';
 const schoolID=(params:unknown)=>z.object({schoolId:z.uuid()}).parse(params).schoolId;
 app.get(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),identity=await options.verifyToken(r.headers.authorization);
  const {data,membershipId}=await loadPreferences(options.pool,identity,schoolId,r.log,r.id);
  reply.header('ETag',`"${data.version}"`);return {data:legacy(data,membershipId),requestId:r.id,serverTime:new Date().toISOString()};
 });
 app.put(path,{bodyLimit:1_024},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=command.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'SAVE_OBSERVATION_RANKING',body,expected,async(db,actor,school):Promise<CommandEffect<ObservationRanking>>=>{
   const effect=await applyPreferencesSave(db,actor,school,{mode:body.mode},expected);
   return {...effect,data:legacy(effect.data,actor.membershipId),action:'ObservationRankingSaved',changedFields:['mode']};
  },staff,{
   // Un rejeu rend le classement actuel du compte, jamais une copie ancienne présentée comme courante.
   replay:async(db,actor)=>legacy(await currentPreferences(db,schoolId,actor.personId),actor.membershipId)
  });
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
}
