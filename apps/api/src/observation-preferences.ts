import {createHash} from 'node:crypto';
import type {FastifyBaseLogger,FastifyInstance} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {Identity,TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type SchoolRow} from './commands.js';
import {ApiError,forbidden} from './errors.js';
import {arrangeObservationThemes,observationThemeKey,schoolObservationConfiguration,type ObservationThemeSettings} from './observation-themes.js';
import {rankThemes,reconcileOrder,type ThemeUsage} from './observation-ranking-engine.js';

/**
 * Préférences de signalements du compte (R08, #465). L'école garde sa politique et sa configuration de référence
 * (observation-themes.ts) ; le compte garde son ordre manuel, sa visibilité personnelle, son choix manuel/intelligent et son apprentissage.
 * Ces préférences sont communes à toutes les écoles de la personne et à tous ses appareils : la table ne porte aucune clé d'école.
 * La palette effective (ce que « Signaler » affiche, dans cet ordre) est toujours calculée ici, jamais réécrite dans les préférences.
 * Contrat : docs/implementation/r08-contrat-serveur-20261111.md.
 */
export type Mode='MANUAL'|'SMART';
interface PrefRow {version:number;theme_order:string[]|null;hidden_themes:string[]|null;mode:Mode;ranked_order:string[];ranked_on:string|null;learning_generation:number;learning_since:Date|null}
type Arranged=ObservationThemeSettings['themes'];
/** Un thème tel que le compte le voit dans l'école ouverte : `visible` est la visibilité EFFECTIVE (celle de l'école si elle l'impose). */
export type PreferenceTheme=Arranged[number]&{schoolVisible:boolean;visibilityEditable:boolean};
export interface AdoptionCandidate {schoolId:string;schoolName:string;mode:Mode;themes:{key:string;visible:boolean}[]}
export interface ObservationPreferences {
 id:string;schoolId:string;version:number;
 /** Politique de l'école ouverte : les moniteurs peuvent-ils personnaliser ordre et affichage ? */
 personalizationAllowed:boolean;
 /** Le compte a un ordre manuel à lui (sinon l'ordre de référence de l'école ouverte s'applique). L'ordre est personnel dans tous les cas. */
 orderCustomized:boolean;
 /** La visibilité personnelle du compte est celle qui s'applique ici : politique ouverte ET visibilité enregistrée. */
 visibilityCustomized:boolean;
 mode:Mode;
 /** Catalogue complet dans l'ordre manuel personnel (sinon celui de l'école), avec la visibilité effective de l'école ouverte : la base de l'écran de réglage. */
 themes:PreferenceTheme[];
 /** Clés affichées dans « Signaler », dans l'ordre à afficher : ordre manuel ou classement intelligent, filtré par la visibilité effective. */
 palette:string[];
 rankedOn:string|null;
 learning:{generation:number;since:string|null};
 /** Présent seulement tant que le compte n'a rien enregistré et que les écoles de la personne portent des classements différents. */
 adoption:{candidates:AdoptionCandidate[]}|null;
}
export interface Effective {personalizationAllowed:boolean;orderCustomized:boolean;visibilityCustomized:boolean;themes:PreferenceTheme[];
 /** Ordre manuel personnel du catalogue COMPLET : la base du classement du compte, indépendante de la visibilité d'une école. */
 order:string[];
 /** Classement du compte sur le catalogue complet (celui qui est enregistré, ramené au catalogue), ou l'ordre manuel hors mode intelligent. */
 ranked:string[];
 palette:string[];row:PrefRow|undefined}

const staff=['ADMIN','INSTRUCTOR'];
/** Fuseau du jour de classement : unique pour tout le compte (il peut avoir plusieurs écoles), donc indépendant du fuseau d'une école. */
export const rankingZone='Europe/Zurich';
const idOnly=z.object({operationId:z.uuid()}).strict();
const catalogSize=observationThemeKey.options.length;
/** Ordre manuel : les dix-huit clés du catalogue, chacune une fois. */
const orderBody=z.array(observationThemeKey).length(catalogSize).refine(keys=>new Set(keys).size===keys.length);
/** Visibilité personnelle : les dix-huit clés, au moins une visible. Indépendante de l'ordre (on peut envoyer l'un sans l'autre). */
const visibilityBody=z.array(z.object({key:observationThemeKey,visible:z.boolean()}).strict()).length(catalogSize)
 .refine(items=>new Set(items.map(item=>item.key)).size===items.length).refine(items=>items.some(item=>item.visible));
const save=z.object({operationId:z.uuid(),mode:z.enum(['MANUAL','SMART']).optional(),order:orderBody.optional(),visibility:visibilityBody.optional()}).strict()
 .refine(body=>body.mode!==undefined||body.order!==undefined||body.visibility!==undefined,{message:'mode, order ou visibility est requis.'});
export type SaveBody=z.infer<typeof save>;

async function readRow(db:PoolClient,personId:string,lock=false):Promise<PrefRow|undefined>{
 return (await db.query<PrefRow>(`SELECT version,theme_order,hidden_themes,mode,ranked_order,to_char(ranked_on,'YYYY-MM-DD') AS ranked_on,learning_generation,learning_since
  FROM drivy.person_observation_preference WHERE person_id=$1 ${lock?'FOR UPDATE':''}`,[personId])).rows[0];
}
async function localDay(db:PoolClient):Promise<string>{
 return (await db.query<{day:string}>("SELECT to_char((now() AT TIME ZONE $1)::date,'YYYY-MM-DD') AS day",[rankingZone])).rows[0]!.day;
}
/** Usages du compte, toutes écoles, depuis la borne d'apprentissage, jusqu'à la veille (drivy.observation_account_usage). */
async function usage(db:PoolClient):Promise<ThemeUsage[]>{
 // Ordre déterministe : pour une leçon qui traverse deux jours, la première ligne rencontrée par le moteur est celle du jour le plus récent.
 return (await db.query<ThemeUsage>(`SELECT theme_key AS "themeKey",lesson_id AS "lessonId",to_char(day,'YYYY-MM-DD') AS day,uses,palette_position AS position
  FROM drivy.observation_account_usage($1) ORDER BY lesson_id,day DESC,theme_key`,[rankingZone])).rows;
}
const elapsedDays=(from:string|null,to:string)=>from?Math.max(1,Math.round((Date.parse(to)-Date.parse(from))/86_400_000)):1;
/** Une seule opération par compte, par génération d'apprentissage et par passage d'un jour au suivant : un second appareil rejoue la première. */
function dailyOperation(personId:string,generation:number,from:string|null,day:string):string{
 const hex=createHash('sha256').update(`observation-ranking:${personId}:${generation}:${from??''}:${day}`).digest('hex');
 return `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-8${hex.slice(17,20)}-${hex.slice(20,32)}`;
}

/**
 * Palette effective du compte dans l'école ouverte (#465) : l'ordre est TOUJOURS personnel (manuel ou intelligent) ; seule la visibilité dépend
 * de la politique. Mode imposé : visibilité de l'école. Mode libre : visibilité personnelle si elle est enregistrée, sinon celle de l'école.
 * Sans ordre personnel, la référence de l'école s'applique. Le classement du compte reste sur le catalogue complet : le filtre par
 * visibilité n'intervient qu'ici, jamais dans ce qui est enregistré.
 */
export async function effectivePalette(db:PoolClient,schoolId:string,personId:string):Promise<Effective>{
 const school=await schoolObservationConfiguration(db,schoolId),row=await readRow(db,personId);
 const orderCustomized=row?.theme_order!=null,reference=new Map(school.themes.map(theme=>[theme.key as string,theme]));
 const arranged=orderCustomized?arrangeObservationThemes({theme_order:row!.theme_order!,hidden_themes:[]}):school.themes;
 const personal=school.personalizationAllowed&&row?.hidden_themes!=null?new Set(row.hidden_themes):null;
 let ownVisibility=personal!==null&&arranged.some(theme=>!personal.has(theme.key));
 const themes:PreferenceTheme[]=arranged.map(theme=>({...theme,schoolVisible:reference.get(theme.key)!.visible,visible:ownVisibility?!personal!.has(theme.key):reference.get(theme.key)!.visible,visibilityEditable:school.personalizationAllowed}));
 const order=themes.map(theme=>theme.key as string),ranked=row?.mode==='SMART'?reconcileOrder(row.ranked_order,order):order;
 const visible=new Set(themes.filter(theme=>theme.visible).map(theme=>theme.key as string));
 return {personalizationAllowed:school.personalizationAllowed,orderCustomized,visibilityCustomized:ownVisibility,themes,order,ranked,palette:ranked.filter(key=>visible.has(key)),row};
}
/** Rang (à partir de 1) de la tuile d'un thème dans « Signaler » pour ce compte, à cet instant ; `null` si elle n'y est pas affichée. */
export async function palettePosition(db:PoolClient,schoolId:string,personId:string,themeKey:string):Promise<number|null>{
 const index=(await effectivePalette(db,schoolId,personId)).palette.indexOf(themeKey);
 return index<0?null:index+1;
}

async function adoption(db:PoolClient,effective:Effective):Promise<ObservationPreferences['adoption']>{
 if(effective.row)return null;
 const rows=(await db.query<{school_id:string;school_name:string;theme_order:string[]|null;hidden_themes:string[]|null;ranking_mode:Mode|null;ranked_order:string[]|null}>(
  'SELECT school_id,school_name,theme_order,hidden_themes,ranking_mode,ranked_order FROM drivy.observation_adoption_candidates()')).rows;
 const configured=rows.filter(row=>row.theme_order!==null||row.ranking_mode!==null);
 if(new Set(configured.map(row=>JSON.stringify([row.theme_order,row.hidden_themes,row.ranking_mode,row.ranking_mode==='SMART'?row.ranked_order:null]))).size<2)return null;
 return {candidates:configured.map(row=>({schoolId:row.school_id,schoolName:row.school_name,mode:row.ranking_mode??'MANUAL',
  themes:arrangeObservationThemes(row.theme_order?{theme_order:row.theme_order,hidden_themes:row.hidden_themes??[]}:undefined).map(theme=>({key:theme.key,visible:theme.visible}))}))};
}
export async function currentPreferences(db:PoolClient,schoolId:string,personId:string):Promise<ObservationPreferences>{
 const effective=await effectivePalette(db,schoolId,personId),row=effective.row,smart=row?.mode==='SMART';
 return {id:personId,schoolId,version:row?.version??1,personalizationAllowed:effective.personalizationAllowed,orderCustomized:effective.orderCustomized,visibilityCustomized:effective.visibilityCustomized,mode:row?.mode??'MANUAL',
  themes:effective.themes,palette:effective.palette,rankedOn:smart?row.ranked_on:null,
  learning:{generation:row?.learning_generation??0,since:row?.learning_since?.toISOString()??null},adoption:await adoption(db,effective)};
}

interface Write {themeOrder:string[]|null;hiddenThemes:string[]|null;mode:Mode;rankedOrder:string[];rankedOn:string|null;generation:number;restartLearning:boolean}
/** Écriture unique de la ligne du compte : la première crée en version 2, les suivantes incrémentent. */
async function write(db:PoolClient,personId:string,values:Write){
 await db.query(`INSERT INTO drivy.person_observation_preference(person_id,version,theme_order,hidden_themes,mode,ranked_order,ranked_on,learning_generation,learning_since)
  VALUES($1,2,$2,$3,$4,$5,$6::date,$7,CASE WHEN $8::boolean THEN now() ELSE NULL END)
  ON CONFLICT(person_id) DO UPDATE SET version=person_observation_preference.version+1,theme_order=EXCLUDED.theme_order,hidden_themes=EXCLUDED.hidden_themes,mode=EXCLUDED.mode,
   ranked_order=EXCLUDED.ranked_order,ranked_on=EXCLUDED.ranked_on,learning_generation=EXCLUDED.learning_generation,
   learning_since=CASE WHEN $8::boolean THEN now() ELSE person_observation_preference.learning_since END,updated_at=now()`,
  [personId,values.themeOrder,values.hiddenThemes,values.mode,values.rankedOrder,values.rankedOn,values.generation,values.restartLearning]);
}
const keep=(row:PrefRow|undefined):Write=>({themeOrder:row?.theme_order??null,hiddenThemes:row?.hidden_themes??null,mode:row?.mode??'MANUAL',rankedOrder:row?.ranked_order??[],
 rankedOn:row?.ranked_on??null,generation:row?.learning_generation??0,restartLearning:false});
const disabled=()=>new ApiError(403,'OBSERVATION_PERSONALIZATION_DISABLED','Cette école impose les signalements affichés.');

/**
 * Enregistre l'ordre manuel personnel, la visibilité personnelle et/ou le mode. Partagé avec l'ancienne route /observation-ranking.
 * L'ordre est toujours accepté (même en visibilité imposée) ; la visibilité personnelle est refusée tant que l'école impose la sienne,
 * et celle déjà enregistrée reste en réserve, intacte.
 */
export async function applyPreferencesSave(db:PoolClient,actor:CommandActor,school:SchoolRow,body:Pick<SaveBody,'mode'|'order'|'visibility'>,expected:number):Promise<CommandEffect<ObservationPreferences>>{
 const row=await readRow(db,actor.personId,true);checkVersion(row?.version??1,expected);
 const policy=await schoolObservationConfiguration(db,school.id);
 if(body.visibility&&!policy.personalizationAllowed)throw disabled();
 const next=keep(row);
 if(body.order)next.themeOrder=body.order;
 if(body.visibility)next.hiddenThemes=body.visibility.filter(item=>!item.visible).map(item=>item.key);
 if(body.mode)next.mode=body.mode;
 if(body.mode==='SMART'&&row?.mode!=='SMART'){
  // À l'activation, le classement repart des scores seuls : l'ordre montré la veille en mode manuel ne retient rien.
  // Il porte sur le catalogue complet : la visibilité de l'école ouverte ne retire rien du classement du compte.
  const order=next.themeOrder?arrangeObservationThemes({theme_order:next.themeOrder,hidden_themes:[]}).map(theme=>theme.key as string):policy.themes.map(theme=>theme.key as string);
  next.rankedOrder=rankThemes({manual:order,usage:await usage(db)}).order;next.rankedOn=await localDay(db);
 }
 await write(db,actor.personId,next);
 const changedFields=[...(body.order?['order']:[]),...(body.visibility?['visibility']:[]),...(body.mode?['mode']:[])];
 return {data:await currentPreferences(db,school.id,actor.personId),action:'ObservationPresentationSaved',resourceType:'ObservationPreferences',resourceId:actor.personId,changedFields};
}

/**
 * Lit les préférences et, au premier passage du jour en mode intelligent, refait et garde le classement. Une erreur de rafraîchissement ne
 * fait jamais échouer la lecture : on rend le dernier classement lu. Seul un code est journalisé.
 */
export async function loadPreferences(pool:Pool,identity:Identity,schoolId:string,log:FastifyBaseLogger,requestId:string,afterRead?:()=>Promise<void>):Promise<{data:ObservationPreferences;membershipId:string}>{
 const read=await withActor(pool,identity,schoolId,async(db,actor,member)=>{
  if(!member?.roles.some(role=>staff.includes(role)))throw forbidden();
  const data=await currentPreferences(db,schoolId,actor.personId),smart=data.mode==='SMART',day=smart?await localDay(db):null;
  return {data,membershipId:member.id,personId:actor.personId,due:smart&&day!==data.rankedOn?{day:day!,from:data.rankedOn,generation:data.learning.generation}:null};
 });
 if(!read.due)return {data:read.data,membershipId:read.membershipId};
 const due=read.due;
 // Point d'arrêt réservé aux tests : une remise à zéro de l'apprentissage peut arriver entre la lecture et le recalcul.
 await afterRead?.();
 try{
  const data=await schoolCommand(pool,identity,schoolId,'REFRESH_OBSERVATION_RANKING',{operationId:dailyOperation(read.personId,due.generation,due.from,due.day)},null,async(db,actor)=>{
   const row=await readRow(db,actor.personId,true),day=await localDay(db),before=await effectivePalette(db,schoolId,actor.personId);let changed=false;
   // Un classement lancé avant « Recommencer l'apprentissage » ne s'applique pas : la génération a changé entre la lecture et le verrou.
   if(row?.mode==='SMART'&&row.learning_generation===due.generation&&row.ranked_on!==day){
    // Catalogue complet : le classement du compte ne perd jamais un thème que l'école ouverte masque.
    const {order}=rankThemes({manual:before.order,previous:row.ranked_order,usage:await usage(db),elapsedDays:elapsedDays(row.ranked_on,day)});
    changed=order.join()!==before.ranked.join();
    await db.query('UPDATE drivy.person_observation_preference SET ranked_order=$2,ranked_on=$3::date,version=version+$4,updated_at=now() WHERE person_id=$1',[actor.personId,order,day,changed?1:0]);
   }
   return {data:await currentPreferences(db,schoolId,actor.personId),action:'ObservationRankingRefreshed',resourceType:'ObservationPreferences',resourceId:actor.personId,changedFields:changed?['order']:[]};
  },staff,{replay:(db,actor)=>currentPreferences(db,schoolId,actor.personId)});
  return {data,membershipId:read.membershipId};
 }catch(error){
  if(!(error instanceof ApiError&&(error.code==='SCHOOL_ARCHIVED'||error.code==='IDEMPOTENCY_MISMATCH'))){
   const code=(error as {code?:unknown})?.code;
   log.warn({requestId,errorCode:typeof code==='string'&&/^[A-Za-z0-9_]{1,40}$/.test(code)?code:'UNKNOWN'},'Rafraîchissement du classement ignoré');
  }
  return {data:read.data,membershipId:read.membershipId};
 }
}

export function registerObservationPreferences(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const path='/v1/schools/:schoolId/observation-preferences';
 const schoolID=(params:unknown)=>z.object({schoolId:z.uuid()}).parse(params).schoolId;
 const respond=(r:{id:string},reply:{header:(name:string,value:string)=>unknown},data:ObservationPreferences)=>{reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};};
 app.get(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),identity=await options.verifyToken(r.headers.authorization);
  return respond(r,reply,(await loadPreferences(options.pool,identity,schoolId,r.log,r.id)).data);
 });
 app.put(path,{bodyLimit:4_096},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=save.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'SAVE_OBSERVATION_PRESENTATION',body,expected,(db,actor,school)=>applyPreferencesSave(db,actor,school,body,expected),staff,
   // Un rejeu rend les préférences actuelles du compte, jamais une copie ancienne présentée comme courante.
   {replay:(db,actor)=>currentPreferences(db,schoolId,actor.personId)});
  return respond(r,reply,data);
 });
 // « Rétablir » : l'ordre et la visibilité de référence de l'école ouverte sont COPIÉS sur le compte (il ne suit plus ensuite les changements
 // de référence). ADMIN dans tous les cas ; moniteur seulement si l'école autorise la personnalisation. Mode et apprentissage ne bougent pas.
 app.post(`${path}/presentation-reset`,{bodyLimit:1_024},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=idOnly.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'RESET_OBSERVATION_PRESENTATION',body,expected,async(db,actor,school)=>{
   const row=await readRow(db,actor.personId,true);checkVersion(row?.version??1,expected);
   const reference=await schoolObservationConfiguration(db,school.id),admin=(await db.query<{ok:boolean}>('SELECT drivy.can_manage_observation_themes($1) AS ok',[school.id])).rows[0]?.ok===true;
   if(!admin&&!reference.personalizationAllowed)throw disabled();
   await write(db,actor.personId,{...keep(row),themeOrder:reference.themes.map(theme=>theme.key as string),hiddenThemes:reference.themes.filter(theme=>!theme.visible).map(theme=>theme.key as string)});
   return {data:await currentPreferences(db,school.id,actor.personId),action:'ObservationPresentationReset',resourceType:'ObservationPreferences',resourceId:actor.personId,changedFields:['order','visibility']};
  },staff,{replay:(db,actor)=>currentPreferences(db,schoolId,actor.personId)});
  return respond(r,reply,data);
 });
 // « Recommencer l'apprentissage » : nouvelle borne durable. Aucun geste observé avant elle n'est relu, quel que soit son chemin
 // d'arrivée ; rien de pédagogique n'est supprimé (les signalements restent dans leurs leçons).
 app.post(`${path}/learning-reset`,{bodyLimit:1_024},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=idOnly.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'RESET_OBSERVATION_LEARNING',body,expected,async(db,actor,school)=>{
   const row=await readRow(db,actor.personId,true);checkVersion(row?.version??1,expected);
   const next=keep(row),effective=await effectivePalette(db,school.id,actor.personId);
   next.generation=(row?.learning_generation??0)+1;next.restartLearning=true;
   // Mode intelligent : le classement repart des seules références (aucun usage depuis la borne). Mode manuel : rien à classer.
   if(next.mode==='SMART'){next.rankedOrder=rankThemes({manual:effective.order,usage:[]}).order;next.rankedOn=await localDay(db);}
   else{next.rankedOrder=[];next.rankedOn=null;}
   await write(db,actor.personId,next);
   return {data:await currentPreferences(db,school.id,actor.personId),action:'ObservationLearningReset',resourceType:'ObservationPreferences',resourceId:actor.personId,changedFields:['learning']};
  },staff,{replay:(db,actor)=>currentPreferences(db,schoolId,actor.personId)});
  return respond(r,reply,data);
 });
}
