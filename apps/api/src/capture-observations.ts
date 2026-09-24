import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {ApiError,notFound} from './errors.js';
import {Cursors} from './cursor.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type CommandGuards,type SchoolRow} from './commands.js';
import {getLesson,type LessonRow} from './lessons.js';
import {geoObservationCommand,geoObservationProjection,uuid,type GeoObservationInput,type GeoObservationRow,type CaptureRow,type ChunkRow} from './capture-contracts.js';
import {chunkAAD,decryptPoints,type CaptureConfig} from './capture-crypto.js';

const empty=z.object({}).strict();
const reasonCommand=z.object({operationId:uuid,reason:z.string().refine(v=>v.trim().length>0&&[...v].length<=1000)}).strict();
const conflict=(code:string,message:string)=>new ApiError(409,code,message);
type Target={lessonId:string}|{observationId:string};
async function observation(db:PoolClient,schoolId:string,id:string,lock=false){
 const row=(await db.query<GeoObservationRow>(`SELECT * FROM drivy.geo_observation WHERE school_id=$1 AND id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,id])).rows[0];
 if(!row)throw notFound();return row;
}
async function author(db:PoolClient,lessonId:string){if(!(await db.query<{ok:boolean}>('SELECT drivy.report_lesson_author($1) AS ok',[lessonId])).rows[0]?.ok)throw notFound();}
async function targetLesson(db:PoolClient,schoolId:string,target:Target){return getLesson(db,schoolId,'lessonId'in target?target.lessonId:(await observation(db,schoolId,target.observationId)).lesson_id);}
function guards<T>(schoolId:string,target:Target):CommandGuards<T>{return {
 additionalPersons:async db=>{const lesson=await targetLesson(db,schoolId,target);await author(db,lesson.id);
  await db.query("SELECT set_config('app.learner_id',$1,true)",[lesson.learner_id]);
  const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;if(!person)throw notFound();return [person];},
 authorize:async db=>author(db,(await targetLesson(db,schoolId,target)).id),
 // Un replay relit l'objet : une réponse ancienne ne ressuscite ni texte retiré ni ancre purgée.
 replay:async(db,_actor,data)=>{if(data&&typeof data==='object'&&'id'in data){const current=await observation(db,schoolId,String(data.id));if(current.removed_at)throw conflict('OBSERVATION_REMOVED','Cette observation a été retirée. Sa preuve d’opération reste consultable.');return geoObservationProjection(current) as T;}return data;}
};}
interface DraftContext {id:string;lesson_id:string;author_membership_id:string;base_publication_version:number}
async function resolveDraft(db:PoolClient,lesson:LessonRow,memberId:string,body:GeoObservationInput):Promise<string|null>{
 if(lesson.status!=='PLANNED'&&lesson.status!=='COMPLETED')throw conflict('LESSON_STATE_CONFLICT','Une leçon annulée ou non réalisée ne peut recevoir cette observation.');
 if(body.draftId===null){
  if(lesson.status==='PLANNED')return null;
  if(lesson.publication_version>0)throw conflict('OBSERVATION_REVIEW_REQUIRED','Un bilan a déjà été publié. Relisez cette intention dans le brouillon avant de la renvoyer.');
 }
 const row=(await db.query<DraftContext>(`SELECT id,lesson_id,author_membership_id,base_publication_version FROM drivy.report_draft
  WHERE school_id=$1 AND lesson_id=$2 AND author_membership_id=$3 AND ($4::uuid IS NULL OR id=$4) FOR UPDATE`,[lesson.school_id,lesson.id,memberId,body.draftId])).rows[0];
 if(lesson.status!=='COMPLETED'||!row||row.base_publication_version!==lesson.publication_version)throw conflict('OBSERVATION_REVIEW_REQUIRED','Le brouillon doit être relu avant de recevoir cette observation.');
 return row.id;
}
async function validateTheme(db:PoolClient,lesson:LessonRow,id:string|null){
 if(id===null)return;
 const found=await db.query(`SELECT c.id FROM drivy.competency_definition c JOIN drivy.offering_version o ON o.school_id=c.school_id AND o.curriculum_version_id=c.curriculum_version_id
  JOIN drivy.training t ON t.school_id=o.school_id AND t.offering_id=o.id WHERE t.school_id=$1 AND t.id=$2 AND c.id=$3`,[lesson.school_id,lesson.training_id,id]);
 if(!found.rowCount)throw conflict('CURRICULUM_VERSION_MISMATCH','Choisissez un thème du référentiel de cette formation.');
}
async function validateAnchor(db:PoolClient,lesson:LessonRow,body:GeoObservationInput,config:CaptureConfig|undefined){
 if(body.captureId===null)return;
 const capture=(await db.query<CaptureRow>('SELECT * FROM drivy.capture_session WHERE school_id=$1 AND id=$2 FOR SHARE',[lesson.school_id,body.captureId])).rows[0];
 if(!capture||capture.lesson_id!==lesson.id)throw notFound();
 if(capture.publication_state!=='PRIVATE'||capture.capture_state==='REVOKED'||capture.sync_state==='REJECTED')throw conflict('ANCHOR_INVALID','Cette capture ne permet plus de conserver cette ancre. Relisez l’observation sans position.');
 const chunk=(await db.query<ChunkRow>(`SELECT * FROM drivy.capture_chunk WHERE school_id=$1 AND capture_id=$2 AND segment_id=$3 AND first_sequence<=$4 AND last_sequence>=$4`,[lesson.school_id,capture.id,body.segmentId,body.pointSequence])).rows[0];
 if(!chunk)throw conflict('ANCHOR_NOT_READY','Le lot contenant cette mesure doit être acquitté avant l’observation.');
 if(!chunk.encrypted_points)throw conflict('ANCHOR_INVALID','La mesure a été retirée. Relisez l’observation sans position.');
 if(!config)throw new ApiError(503,'CAPTURE_KEY_UNAVAILABLE','La mesure chiffrée ne peut pas être vérifiée actuellement.');
 const points=decryptPoints(config,chunk.encrypted_points,chunk.key_id,chunkAAD(lesson.school_id,capture.id,chunk.segment_id,chunk.chunk_index,chunk.content_hash));
 const point=points.find(p=>p.sequence===body.pointSequence);
 if(!point)throw conflict('ANCHOR_INVALID','Cette séquence ne correspond à aucune mesure reçue.');
 const measured=Date.parse(point.capturedAt),cutoff=Math.min(capture.expires_at.getTime(),capture.cutoff_at?.getTime()??Infinity);
 if(measured<capture.authorized_at.getTime()||measured>=cutoff||(body.observedAt&&measured>Date.parse(body.observedAt)))throw conflict('ANCHOR_INVALID','La mesure sort du contexte temporel de cette observation.');
}
async function touchDraft(db:PoolClient,schoolId:string,ids:(string|null)[]){
 const distinct=[...new Set(ids.filter((id):id is string=>id!==null))];
 if(distinct.length)await db.query('UPDATE drivy.report_draft SET version=version+1 WHERE school_id=$1 AND id=ANY($2::uuid[])',[schoolId,distinct]);
}
/** Appelé uniquement sous le verrou de leçon du constat, dans sa transaction. */
export async function attachLiveObservations(db:PoolClient,lesson:LessonRow,draftId:string,memberId:string){
 await db.query(`UPDATE drivy.geo_observation SET draft_id=$4,version=version+1 WHERE school_id=$1 AND lesson_id=$2 AND training_id=$3
  AND draft_id IS NULL AND author_membership_id=$5 AND removed_at IS NULL`,[lesson.school_id,lesson.id,lesson.training_id,draftId,memberId]);
}
export async function draftObservationIDs(db:PoolClient,schoolId:string,draftId:string):Promise<string[]>{
 return (await db.query<{id:string}>('SELECT id FROM drivy.geo_observation WHERE school_id=$1 AND draft_id=$2 AND removed_at IS NULL ORDER BY created_at,id',[schoolId,draftId])).rows.map(r=>r.id);
}

export function registerCaptureObservations(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string;capture?:CaptureConfig}){
 const base='/v1/schools/:schoolId',cursors=new Cursors(options.cursorSecret);
 const param=(r:FastifyRequest,key:string)=>uuid.parse(z.record(z.string(),z.string()).parse(r.params)[key]);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 async function command<T>(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,expected:number|null,target:Target,work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<CommandEffect<T>>){
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const schoolId=param(r,'schoolId');
  return schoolCommand(options.pool,await options.verifyToken(r.headers.authorization),schoolId,type,body,expected,work,['INSTRUCTOR'],guards<T>(schoolId,target));
 }
 app.get(`${base}/lessons/:lessonId/geo-observations`,async r=>{
  const schoolId=param(r,'schoolId'),lessonId=param(r,'lessonId'),query=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(2000).optional()}).strict().parse(r.query);
  const data=await withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolId,async(db,actor,member)=>{
   await author(db,lessonId);const scope=JSON.stringify(['geo-observations',schoolId,actor.personId,member!.accessEpoch,lessonId,query.limit]),position=cursors.decode(query.cursor,scope);
   const rows=(await db.query<GeoObservationRow&{_createdAt:string}>(`SELECT *,to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.geo_observation
    WHERE school_id=$1 AND lesson_id=$2 AND removed_at IS NULL AND ($3::timestamptz IS NULL OR (created_at,id)>($3::timestamptz,$4::uuid)) ORDER BY created_at,id LIMIT $5`,[schoolId,lessonId,position?.createdAt??null,position?.id??null,query.limit+1])).rows;
   const items=rows.slice(0,query.limit),last=items.at(-1);return {items:items.map(geoObservationProjection),nextCursor:rows.length>query.limit&&last?cursors.encode(scope,{createdAt:last._createdAt,id:last.id}):null};
  });return envelope(data,r);
 });
 app.post(`${base}/lessons/:lessonId/geo-observations`,{bodyLimit:24_000},async(r,reply)=>{
  const body=geoObservationCommand.parse(r.body),lessonId=param(r,'lessonId');
  const data=await command(r,'CREATE_GEO_OBSERVATION',{...body,lessonId},null,{lessonId},async(db,actor,school)=>{
   const lesson=await getLesson(db,school.id,lessonId,true),draftId=await resolveDraft(db,lesson,actor.membershipId,body);
   const count=(await db.query<{n:number}>('SELECT count(*)::int AS n FROM drivy.geo_observation WHERE school_id=$1 AND lesson_id=$2 AND author_membership_id=$3 AND removed_at IS NULL',[school.id,lessonId,actor.membershipId])).rows[0]!.n;
   if(count>=100)throw conflict('OBSERVATION_LIMIT_REACHED','Cette leçon contient déjà 100 observations privées. Relisez-les avant un nouvel ajout.');
   if(body.observedAt&&Date.parse(body.observedAt)>Date.now()+300_000)throw new ApiError(422,'OBSERVATION_TIME_INVALID','L’instant indiqué est futur. Conservez l’intention et relisez son heure.');
   await validateTheme(db,lesson,body.competencyId);await validateAnchor(db,lesson,body,options.capture);
   const row=(await db.query<GeoObservationRow>(`INSERT INTO drivy.geo_observation(school_id,lesson_id,training_id,author_membership_id,draft_id,capture_id,segment_id,point_sequence,competency_id,text,origin,observed_at,event_kind,event_status)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING *`,[school.id,lessonId,lesson.training_id,actor.membershipId,draftId,body.captureId,body.segmentId,body.pointSequence,body.competencyId,body.text,body.origin??'REVIEW',body.observedAt??null,body.eventKind??null,body.eventStatus??null])).rows[0]!;
   await touchDraft(db,school.id,[draftId]);return {data:geoObservationProjection(row),action:'GeoObservationCreated',resourceType:'GeoObservation',resourceId:row.id,changedFields:['observation']};
  });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.put(`${base}/geo-observations/:observationId`,{bodyLimit:24_000},async(r,reply)=>{
  const body=geoObservationCommand.parse(r.body),observationId=param(r,'observationId'),expected=requireVersion(r.headers['if-match']);
  const data=await command(r,'UPDATE_GEO_OBSERVATION',{...body,observationId},expected,{observationId},async(db,actor,school)=>{
   const initial=await observation(db,school.id,observationId),lesson=await getLesson(db,school.id,initial.lesson_id,true),old=await observation(db,school.id,observationId,true);checkVersion(old.version,expected);
   if(old.removed_at)throw conflict('OBSERVATION_REMOVED','Cette observation a été retirée.');
   const draftId=await resolveDraft(db,lesson,actor.membershipId,body);
   if(body.observedAt&&Date.parse(body.observedAt)>Date.now()+300_000)throw new ApiError(422,'OBSERVATION_TIME_INVALID','L’instant indiqué est futur.');
   if(body.origin==='LIVE'&&old.observed_at&&Date.parse(body.observedAt!)!==old.observed_at.getTime())throw new ApiError(422,'OBSERVATION_TIME_CHANGED','La qualification conserve l’instant du signalement. Une correction explicite exige une revue dans le brouillon.');
   await validateTheme(db,lesson,body.competencyId);await validateAnchor(db,lesson,body,options.capture);
   const row=(await db.query<GeoObservationRow>(`UPDATE drivy.geo_observation SET version=version+1,draft_id=$3,capture_id=$4,segment_id=$5,point_sequence=$6,competency_id=$7,text=$8,origin=$9,observed_at=$10,event_kind=$11,event_status=$12
    WHERE school_id=$1 AND id=$2 RETURNING *`,[school.id,observationId,draftId,body.captureId,body.segmentId,body.pointSequence,body.competencyId,body.text,body.origin??'REVIEW',body.observedAt??null,body.eventKind??null,body.eventStatus??null])).rows[0]!;
   await touchDraft(db,school.id,[old.draft_id,draftId]);return {data:geoObservationProjection(row),action:'GeoObservationUpdated',resourceType:'GeoObservation',resourceId:row.id,changedFields:['observation']};
  });reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/geo-observations/:observationId/remove`,async r=>{
  const body=reasonCommand.parse(r.body),observationId=param(r,'observationId'),expected=requireVersion(r.headers['if-match']);
  const data=await command(r,'REMOVE_GEO_OBSERVATION',{...body,observationId},expected,{observationId},async(db,_actor,school)=>{
   const initial=await observation(db,school.id,observationId);await getLesson(db,school.id,initial.lesson_id,true);const old=await observation(db,school.id,observationId,true);checkVersion(old.version,expected);
   if(old.removed_at)throw conflict('OBSERVATION_REMOVED','Cette observation a déjà été retirée.');
   await db.query('UPDATE drivy.geo_observation SET version=version+1,removed_at=now(),text=NULL,capture_id=NULL,segment_id=NULL,point_sequence=NULL WHERE school_id=$1 AND id=$2',[school.id,observationId]);await touchDraft(db,school.id,[old.draft_id]);
   return {data:{operationId:body.operationId,accepted:true},action:'GeoObservationRemoved',resourceType:'GeoObservation',resourceId:observationId,resourceVersion:old.version+1,changedFields:['removed'],reason:body.reason};
  });return envelope(data,r);
 });
}
export async function authorizeCaptureObservationOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(!['CREATE_GEO_OBSERVATION','UPDATE_GEO_OBSERVATION','REMOVE_GEO_OBSERVATION'].includes(type))return false;
 await observation(db,schoolId,resourceId);return true;
}
