import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {ApiError,notFound} from './errors.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand} from './commands.js';
import {getLesson,lessonColumns,type LessonRow} from './lessons.js';
import {syncSharedReport,withdrawPublication} from './lesson-reports.js';
import {captureProjection,type CaptureRow} from './capture-contracts.js';

/**
 * Extension hors canon : ce que l'élève voit d'une leçon réalisée (décision du porteur du 28 septembre 2026).
 * Tout est partagé par défaut ; le moniteur garde pour lui le bilan, le trajet ou certaines observations.
 * Les projections canoniques (leçon, observation, trajet) restent inchangées.
 */
const id=z.uuid().transform(value=>value.toLowerCase()),empty=z.object({}).strict();
const sharingCommand=z.object({operationId:id,reportPrivate:z.boolean(),captureHidden:z.boolean(),
 privateObservationIds:z.array(id).max(100).refine(values=>new Set(values).size===values.length)}).strict();
interface SharingRow extends LessonRow {report_private:boolean;capture_hidden:boolean;sharing_version:number}

async function isAuthor(db:PoolClient,lessonId:string){return (await db.query<{ok:boolean}>('SELECT drivy.report_lesson_author($1) AS ok',[lessonId])).rows[0]?.ok===true;}
async function sharingProjection(db:PoolClient,lesson:SharingRow){
 const hidden=(await db.query<{id:string}>('SELECT id FROM drivy.geo_observation WHERE school_id=$1 AND lesson_id=$2 AND private AND removed_at IS NULL ORDER BY created_at,id',[lesson.school_id,lesson.id])).rows;
 return {lessonId:lesson.id,schoolId:lesson.school_id,version:lesson.sharing_version,reportPrivate:lesson.report_private,captureHidden:lesson.capture_hidden,privateObservationIds:hidden.map(row=>row.id)};
}

export function registerSharing(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId';
 const target=(r:FastifyRequest)=>z.object({schoolId:id,lessonId:id}).parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});

 app.get(`${base}/lessons/:lessonId/sharing`,async(r,reply)=>{
  empty.parse(r.query);const {schoolId,lessonId}=target(r);
  const data=await withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolId,async db=>{
   if(!(await isAuthor(db,lessonId)))throw notFound();
   return sharingProjection(db,await getLesson(db,schoolId,lessonId) as SharingRow);
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 app.put(`${base}/lessons/:lessonId/sharing`,async(r,reply)=>{
  empty.parse(r.query);const body=sharingCommand.parse(r.body),{schoolId,lessonId}=target(r),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const authorOnly=async(db:PoolClient)=>{if(!(await isAuthor(db,lessonId)))throw notFound();};
  const bound={...body,lessonId};
  const data=await schoolCommand<Awaited<ReturnType<typeof sharingProjection>>>(options.pool,await options.verifyToken(r.headers.authorization),schoolId,'UPDATE_LESSON_SHARING',bound,expected,async(db,actor)=>{
   const old=await getLesson(db,schoolId,lessonId,true) as SharingRow;checkVersion(old.sharing_version,expected);
   const known=(await db.query<{id:string}>('SELECT id FROM drivy.geo_observation WHERE school_id=$1 AND lesson_id=$2 AND removed_at IS NULL AND id=ANY($3::uuid[])',[schoolId,lessonId,body.privateObservationIds])).rows;
   if(known.length!==body.privateObservationIds.length)throw new ApiError(422,'OBSERVATION_NOT_IN_LESSON','Choisissez des observations de cette leçon.');
   await db.query(`UPDATE drivy.geo_observation SET private=(id=ANY($3::uuid[])) WHERE school_id=$1 AND lesson_id=$2 AND removed_at IS NULL
    AND private IS DISTINCT FROM (id=ANY($3::uuid[]))`,[schoolId,lessonId,body.privateObservationIds]);
   const updated=(await db.query<SharingRow>(`UPDATE drivy.lesson SET report_private=$3,capture_hidden=$4,sharing_version=sharing_version+1 WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,
    [schoolId,lessonId,body.reportPrivate,body.captureHidden])).rows[0]!;
   if(body.reportPrivate&&!old.report_private&&updated.current_published_revision_id)await withdrawPublication(db,updated,actor.membershipId,body.operationId,'Bilan passé en privé par le moniteur.');
   if(!body.reportPrivate&&old.report_private)await syncSharedReport(db,schoolId,lessonId,body.operationId);
   const current=await getLesson(db,schoolId,lessonId) as SharingRow;
   return {data:await sharingProjection(db,current),action:'LessonSharingUpdated',resourceType:'LessonSharing',resourceId:lessonId,resourceVersion:current.sharing_version,
    changedFields:['reportPrivate','captureHidden','privateObservationIds']};
  },['INSTRUCTOR'],{authorize:authorOnly,replay:async(db,_actor,data)=>{await authorOnly(db);return data;}});
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Trajets d'une leçon : le moniteur affecté lit les siens, l'élève ceux qui sont partagés (RLS).
 app.get(`${base}/lessons/:lessonId/captures`,async r=>{
  empty.parse(r.query);const {schoolId,lessonId}=target(r);
  const data=await withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolId,async db=>{
   await getLesson(db,schoolId,lessonId);
   const rows=(await db.query<CaptureRow>('SELECT * FROM drivy.capture_session WHERE school_id=$1 AND lesson_id=$2 ORDER BY authorized_at,id',[schoolId,lessonId])).rows;
   return {items:rows.map(captureProjection)};
  });
  return envelope(data,r);
 });
}

/** AP72 : la preuve d'un changement de partage reste réservée à l'auteur actuel de la leçon. */
export async function authorizeSharingOperation(db:PoolClient,_schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type!=='UPDATE_LESSON_SHARING')return false;
 if(!(await isAuthor(db,resourceId)))throw notFound();
 return true;
}
