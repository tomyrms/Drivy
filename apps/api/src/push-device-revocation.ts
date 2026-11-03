import {createHash,randomBytes} from 'node:crypto';
import type {FastifyInstance} from 'fastify';
import type {Pool} from 'pg';
import {z} from 'zod';
import {AttemptLimiter} from './attempt-limiter.js';
import {rollbackQuietly} from './database.js';
import {ApiError} from './errors.js';

/**
 * Révocation d'un appareil push sans jeton d'accès (#120/#74). Quand la session iOS se termine sans déconnexion explicite
 * (restauration échouée, renouvellement refusé, Trousseau en échec), l'app ne peut plus appeler la route authentifiée :
 * elle présente le secret rendu à l'enregistrement, et le serveur révoque cette seule ligne. La réponse est identique
 * dans tous les cas ; ni le jeton ni le secret ne sont journalisés.
 * Décisions : docs/implementation/messaging-notifications-74.md (§ Révocation sans jeton).
 */
const empty=z.object({}).strict();
/** Corps strict. Le secret garde une longueur bornée mais aucune forme imposée : un secret mal formé reste « faux ». */
const revokeBody=z.object({token:z.string().regex(/^[0-9a-fA-F]{64,200}$/),revocationSecret:z.string().min(1).max(512)}).strict();
/** Freins de la route sans connexion : par IP et par jeton, sur une fenêtre de 15 minutes. */
export const revocationAttemptLimits={perIp:30,perToken:10,windowMs:15*60_000} as const;

/** Secret de 256 bits, base64url. Rendu une seule fois à l'enregistrement, jamais relu ensuite. */
export function newRevocationSecret(){return randomBytes(32).toString('base64url');}
/**
 * Empreinte SHA-256 du secret. Pas de HMAC : le secret est engendré par le serveur avec 256 bits d'entropie et n'est jamais
 * choisi par une personne, donc aucune attaque par dictionnaire n'est possible ; réutiliser une clé existante (curseurs,
 * invitations) mélangerait deux usages. L'empreinte n'est jamais lisible par le rôle applicatif.
 */
export function revocationDigest(secret:string){return createHash('sha256').update(secret,'utf8').digest();}

export function registerPushDeviceRevocation(app:FastifyInstance,options:{pool:Pool;attempts?:{ip:AttemptLimiter;token:AttemptLimiter}}){
 const attempts=options.attempts??{ip:new AttemptLimiter(revocationAttemptLimits.perIp,revocationAttemptLimits.windowMs),
  token:new AttemptLimiter(revocationAttemptLimits.perToken,revocationAttemptLimits.windowMs)};
 /** Le compteur ne garde ni IP ni jeton en clair : la clé est une empreinte de la valeur. */
 const key=(scope:string,value:string)=>AttemptLimiter.key(scope,createHash('sha256').update(value,'utf8').digest('base64url'));
 /** Le frein existant parle de codes d'invitation ; cette route n'en traite pas, le refus reste neutre. */
 const limited=(error:unknown)=>error instanceof ApiError&&error.code==='INVITATION_CODE_ATTEMPTS'
  ?new ApiError(429,'PUSH_REVOCATION_ATTEMPTS','Trop de tentatives. Réessayez dans quelques minutes.'):error;
 /** Transaction courte sous drivy_app : la fonction SECURITY DEFINER compare l'empreinte et révoque la seule ligne du jeton. */
 async function revoke(token:string,digest:Buffer):Promise<boolean>{
  const db=await options.pool.connect();let broken=false;
  try{
   await db.query('BEGIN');await db.query("SET LOCAL statement_timeout='5s'");await db.query('SET LOCAL ROLE drivy_app');
   const matched=(await db.query<{matched:boolean}>('SELECT drivy.push_device_revoke_anonymous($1,$2) AS matched',[token,digest])).rows[0]?.matched===true;
   await db.query('COMMIT');return matched;
  }catch(error){broken=!(await rollbackQuietly(db));throw error;}finally{db.release(broken);}
 }
 app.post('/v1/push-devices/revoke',{bodyLimit:1_024},async r=>{
  empty.parse(r.query);const body=revokeBody.parse(r.body),token=body.token.toLowerCase();
  // Réserver avant la base : une rafale parallèle ne contourne pas le frein. Un échec de correspondance consomme la tentative.
  let ipAttempt:(failed:boolean)=>void;
  try{ipAttempt=attempts.ip.begin(key('ip',r.ip));}
  catch(error){throw limited(error);}
  let tokenAttempt:(failed:boolean)=>void;
  try{tokenAttempt=attempts.token.begin(key('token',token));}
  catch(error){ipAttempt(false);throw limited(error);}
  let matched=false;
  try{matched=await revoke(token,revocationDigest(body.revocationSecret));}
  catch(error){ipAttempt(false);tokenAttempt(false);throw error;}
  ipAttempt(!matched);tokenAttempt(!matched);
  // Même statut et même charge que le jeton existe ou non, que le secret corresponde ou non : rien n'est révélé.
  return {data:{revoked:true},requestId:r.id,serverTime:new Date().toISOString()};
 });
}
