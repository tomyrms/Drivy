import type {FastifyInstance} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand} from './commands.js';
import {ApiError,forbidden} from './errors.js';

/**
 * Catalogue des signalements : dix-huit thèmes à clés stables. L'ordre du tableau est l'ordre d'origine. La clé est aussi le nom du
 * pictogramme dans l'app et sur le web. Un thème existe seul : il ne dépend d'aucune compétence de formation (#56).
 * `competencyKeys` est déprécié : plus aucune règle ne le lit, mais il reste publié tel quel parce que les apps antérieures au
 * 21 octobre 2026 refusent une configuration qui ne le porte pas. Il ne sert qu'à un pictogramme d'observation ancienne sans clé.
 * Contrats : docs/implementation/signalements-configurables-20261012.md et signalements-autonomes-20261021.md.
 */
export const observationThemes=[
 {key:'vehicle',title:'Maîtrise du véhicule',competencyKeys:['vehicule'],defaultVisible:true},
 {key:'observation',title:'Observation et contrôles',competencyKeys:['observation'],defaultVisible:true},
 {key:'right-priority',title:'Priorité à droite',competencyKeys:['priorites'],defaultVisible:true},
 {key:'signage',title:'Signalisation',competencyKeys:['priorites'],defaultVisible:true},
 {key:'give-way',title:'Céder le passage',competencyKeys:['priorites'],defaultVisible:true},
 {key:'intersections',title:'Intersections et giratoires',competencyKeys:['intersections'],defaultVisible:true},
 {key:'speed',title:'Vitesse',competencyKeys:['vitesse'],defaultVisible:true},
 {key:'placement',title:'Placement sur la chaussée',competencyKeys:['placement'],defaultVisible:true},
 {key:'manoeuvres',title:'Manœuvres',competencyKeys:['manoeuvres','parking'],defaultVisible:true},
 {key:'motorway',title:'Autoroute',competencyKeys:['autoroute','motorway'],defaultVisible:true},
 {key:'anticipation',title:'Anticipation',competencyKeys:['anticipation'],defaultVisible:true},
 {key:'indicators',title:'Clignotants',competencyKeys:['observation'],defaultVisible:true},
 {key:'following-distance',title:'Distance de sécurité',competencyKeys:['vitesse'],defaultVisible:false},
 {key:'braking',title:'Freinage',competencyKeys:['vehicule'],defaultVisible:false},
 {key:'lane-change',title:'Changement de voie',competencyKeys:['placement'],defaultVisible:false},
 {key:'moving-off',title:'Démarrage',competencyKeys:['vehicule'],defaultVisible:false},
 {key:'bends',title:'Virages',competencyKeys:['placement'],defaultVisible:false},
 {key:'eco-driving',title:'Éco-conduite',competencyKeys:['vehicule'],defaultVisible:false}
] as const;
export type ObservationThemeKey=typeof observationThemes[number]['key'];
const keys=observationThemes.map(theme=>theme.key) as [ObservationThemeKey,...ObservationThemeKey[]];
export const observationThemeKey=z.enum(keys);

const command=z.object({operationId:z.uuid(),themes:z.array(z.object({key:observationThemeKey,visible:z.boolean()}).strict()).length(keys.length)
 .refine(themes=>new Set(themes.map(theme=>theme.key)).size===themes.length).refine(themes=>themes.some(theme=>theme.visible))}).strict();
interface SettingsRow {version:number;theme_order:string[];hidden_themes:string[]}
export interface ObservationThemeSettings {id:string;schoolId:string;version:number;canManage:boolean;
 themes:{key:ObservationThemeKey;title:string;competencyKeys:readonly string[];visible:boolean;defaultVisible:boolean;defaultPosition:number}[]}

/**
 * Ordre et affichage enregistrés, ramenés au catalogue courant : une clé inconnue est ignorée, un thème absent de la ligne
 * (ajouté au catalogue après elle) retrouve sa place et son affichage d'origine.
 */
export function arrangeObservationThemes(row:Pick<SettingsRow,'theme_order'|'hidden_themes'>|undefined):ObservationThemeSettings['themes']{
 const projected=observationThemes.map((theme,defaultPosition)=>({key:theme.key,title:theme.title,competencyKeys:theme.competencyKeys,visible:theme.defaultVisible as boolean,defaultVisible:theme.defaultVisible as boolean,defaultPosition}));
 if(!row)return projected;
 const hidden=new Set(row.hidden_themes),stored=row.theme_order.flatMap(key=>{const theme=projected.find(item=>item.key===key);return theme?[{...theme,visible:!hidden.has(key)}]:[];});
 const known=new Set(stored.map(theme=>theme.key));
 for(const theme of projected)if(!known.has(theme.key))stored.splice(Math.min(theme.defaultPosition,stored.length),0,theme);
 // Une ligne ancienne dont tous les thèmes connus seraient masqués ne vide pas « Signaler ».
 if(!stored.some(theme=>theme.visible))return projected;
 return stored;
}
/** Clés des thèmes que l'école affiche, dans son ordre : l'ordre manuel de « Signaler ». */
export async function visibleObservationThemes(db:PoolClient,schoolId:string):Promise<ObservationThemeKey[]>{
 const row=(await db.query<SettingsRow>('SELECT version,theme_order,hidden_themes FROM drivy.observation_theme_settings WHERE school_id=$1',[schoolId])).rows[0];
 return arrangeObservationThemes(row).filter(theme=>theme.visible).map(theme=>theme.key);
}
async function canManage(db:PoolClient,schoolId:string):Promise<boolean>{
 return (await db.query<{ok:boolean}>('SELECT drivy.can_manage_observation_themes($1) AS ok',[schoolId])).rows[0]?.ok===true;
}
export async function observationThemeSettings(db:PoolClient,schoolId:string,lock=false):Promise<ObservationThemeSettings>{
 const row=(await db.query<SettingsRow>(`SELECT version,theme_order,hidden_themes FROM drivy.observation_theme_settings WHERE school_id=$1 ${lock?'FOR UPDATE':''}`,[schoolId])).rows[0];
 return {id:schoolId,schoolId,version:row?.version??1,canManage:await canManage(db,schoolId),themes:arrangeObservationThemes(row)};
}

export function registerObservationThemes(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const path='/v1/schools/:schoolId/observation-themes';
 const schoolID=(params:unknown)=>z.object({schoolId:z.uuid()}).parse(params).schoolId;
 app.get(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
   if(!member?.roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role)))throw forbidden();
   return observationThemeSettings(db,schoolId);
  });
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
 app.put(path,{bodyLimit:4_096},async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=command.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'SAVE_OBSERVATION_THEMES',body,expected,async(db,actor)=>{
   // La ligne de l'école est déjà verrouillée par la commande : deux enregistrements concurrents se suivent, le second relit la version.
   const previous=await observationThemeSettings(db,schoolId,true);checkVersion(previous.version,expected);
   const order=body.themes.map(theme=>theme.key),hidden=body.themes.filter(theme=>!theme.visible).map(theme=>theme.key);
   await db.query(`INSERT INTO drivy.observation_theme_settings(school_id,version,theme_order,hidden_themes,updated_by) VALUES($1,2,$2,$3,$4)
    ON CONFLICT(school_id) DO UPDATE SET version=observation_theme_settings.version+1,theme_order=EXCLUDED.theme_order,hidden_themes=EXCLUDED.hidden_themes,updated_by=EXCLUDED.updated_by,updated_at=now()`,[schoolId,order,hidden,actor.membershipId]);
   return {data:await observationThemeSettings(db,schoolId),action:'ObservationThemesSaved',resourceType:'ObservationThemeSettings',resourceId:schoolId,changedFields:['order','visibility']};
  },['ADMIN','INSTRUCTOR'],{
   // Le rôle ouvre la commande, le droit l'autorise : relu en base à chaque écriture, y compris pour un rejeu.
   authorize:async db=>{if(!(await canManage(db,schoolId)))throw new ApiError(403,'OBSERVATION_THEMES_ACCESS_REQUIRED','La gestion des signalements demande le droit correspondant.');},
   // Un rejeu rend la configuration actuelle de l'école, jamais une copie ancienne présentée comme courante.
   replay:async db=>observationThemeSettings(db,schoolId)
  });
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
}
