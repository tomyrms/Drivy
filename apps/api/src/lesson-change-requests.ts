import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {getLesson,type LessonRow} from './lessons.js';

/**
 * Demandes de l'élève sur sa leçon (#52) : déplacement ou annulation. Une demande ne change ni la leçon, ni ses occupations, ni son
 * compte : le créneau d'origine reste valable jusqu'à la réponse du personnel, qui passe par les commandes de déplacement et d'annulation
 * existantes (lessons.ts, champ facultatif changeRequestId). Aucun délai et aucun frais ne sont inventés : le délai montré est celui de la
 * procédure approuvée de la leçon, figé dans la demande. Contrat : contracts/lesson-change-requests.json.
 */
const id=z.uuid(),empty=z.object({}).strict(),operation=z.object({operationId:id}).strict();
const note=z.string().trim().max(1000);
const createBody=z.object({operationId:id,kind:z.enum(['RESCHEDULE','CANCEL']),note:note.default('')}).strict()
 .refine(value=>value.kind!=='RESCHEDULE'||value.note!=='',{path:['note'],message:'Indiquez vos disponibilités ou une proposition.'});
const refuseBody=z.object({operationId:id,note:note.nullish()}).strict();

type Kind='RESCHEDULE'|'CANCEL';
type Status='PENDING'|'ACCEPTED'|'REFUSED'|'WITHDRAWN'|'SUPERSEDED';
type BlockedReason='NOT_LEARNER'|'LESSON_CLOSED'|'LESSON_STARTED'|'LESSON_IN_PAST'|'REQUEST_PENDING';
interface RequestRow {id:string;lesson_id:string;requester_person_id:string;kind:Kind;status:Status;note:string;late:boolean|null;deadline_at:Date|null;
 cancellation_hours:number|null;policy_version_id:string|null;resolved_at:Date|null;resolution_note:string|null;version:number;created_at:Date}
interface ConditionRow {policy_version_id:string;policy_version:number;cancellation_policy_text:string;
 cancellation_rules:{cancellationHours:number|null;lateAction:'CONTACT'|'NO_FEE'}|null}
export interface ChangeRequestView {id:string;lessonId:string;kind:Kind;status:Status;note:string;mine:boolean;late:boolean|null;deadlineAt:string|null;
 cancellationHours:number|null;policyVersionId:string|null;resolvedAt:string|null;resolutionNote:string|null;version:number;createdAt:string}
export interface ChangeConditions {policyVersionId:string|null;policyVersion:number|null;cancellationPolicyText:string;cancellationHours:number|null;
 lateAction:'CONTACT'|'NO_FEE'|null;deadlineAt:string|null;late:boolean|null;canRequest:boolean;blockedReason:BlockedReason|null}
export interface ChangeState {lessonId:string;conditions:ChangeConditions;requests:ChangeRequestView[]}

const requestColumns='id,lesson_id,requester_person_id,kind,status,note,late,deadline_at,cancellation_hours,policy_version_id,resolved_at,resolution_note,version,created_at';
const requestView=(row:RequestRow,personId:string):ChangeRequestView=>({id:row.id,lessonId:row.lesson_id,kind:row.kind,status:row.status,note:row.note,
 mine:row.requester_person_id===personId,late:row.late,deadlineAt:row.deadline_at?.toISOString()??null,cancellationHours:row.cancellation_hours,
 policyVersionId:row.policy_version_id,resolvedAt:row.resolved_at?.toISOString()??null,resolutionNote:row.resolution_note,version:row.version,createdAt:row.created_at.toISOString()});

const blockedFailures:Record<Exclude<BlockedReason,'NOT_LEARNER'>,[number,string,string]>={
 LESSON_CLOSED:[409,'LESSON_CLOSED','Cette leçon n’est plus planifiée.'],
 LESSON_STARTED:[409,'LESSON_STARTED','Cette leçon est déjà commencée.'],
 LESSON_IN_PAST:[409,'LESSON_IN_PAST','Le début de cette leçon est passé.'],
 REQUEST_PENDING:[409,'LESSON_CHANGE_REQUEST_PENDING','Une demande est déjà en attente pour cette leçon.']
};
/** Pourquoi cette personne ne peut pas demander de changement maintenant, ou null. L'ordre donne la raison la plus utile. */
export function blockedReason(lesson:Pick<LessonRow,'learner_person_id'|'status'|'actual_start'|'planned_start'>,personId:string,pending:boolean,now:Date):BlockedReason|null{
 if(lesson.learner_person_id!==personId)return 'NOT_LEARNER';
 if(lesson.status!=='PLANNED')return 'LESSON_CLOSED';
 if(lesson.actual_start)return 'LESSON_STARTED';
 if(lesson.planned_start.getTime()<=now.getTime())return 'LESSON_IN_PAST';
 return pending?'REQUEST_PENDING':null;
}
/** Échéance lue dans la procédure de la leçon. Inconnue (null) quand l'école n'a pas fixé de délai : rien n'est supposé. */
export function describeConditions(row:ConditionRow|undefined,lesson:Pick<LessonRow,'planned_start'>,now:Date){
 const rules=row?.cancellation_rules??null,hours=rules?.cancellationHours??null;
 const deadline=hours===null?null:new Date(lesson.planned_start.getTime()-hours*3_600_000);
 return {policyVersionId:row?.policy_version_id??null,policyVersion:row?.policy_version??null,cancellationPolicyText:row?.cancellation_policy_text??'',
  cancellationHours:hours,lateAction:rules?.lateAction??null,deadlineAt:deadline?.toISOString()??null,late:deadline?now.getTime()>deadline.getTime():null};
}
async function conditionRow(db:PoolClient,lessonId:string){
 return (await db.query<ConditionRow>('SELECT * FROM drivy.lesson_change_conditions($1)',[lessonId])).rows[0];
}
/** État d'une leçon pour l'appelant : conditions applicables, droit de demander et vingt dernières demandes. */
export async function changeState(db:PoolClient,schoolId:string,lessonId:string,personId:string,now=new Date()):Promise<ChangeState>{
 const lesson=await getLesson(db,schoolId,lessonId);
 const rows=(await db.query<RequestRow>(`SELECT ${requestColumns} FROM drivy.lesson_change_request WHERE school_id=$1 AND lesson_id=$2 ORDER BY created_at DESC,id DESC LIMIT 20`,[schoolId,lessonId])).rows;
 const reason=blockedReason(lesson,personId,rows.some(row=>row.status==='PENDING'),now);
 return {lessonId,conditions:{...describeConditions(await conditionRow(db,lessonId),lesson,now),canRequest:reason===null,blockedReason:reason},
  requests:rows.map(row=>requestView(row,personId))};
}

export function registerLessonChangeRequests(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId',params=(r:FastifyRequest)=>z.object({schoolId:id}).passthrough().parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const run=async(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,expected:number|null,roles:string[],
  work:(db:PoolClient,actor:CommandActor)=>Promise<CommandEffect<ChangeState>>)=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  return schoolCommand<ChangeState>(options.pool,identity,schoolId,type,body,expected,(db,actor)=>work(db,actor),roles,
   {replay:async(db,actor,previous)=>changeState(db,schoolId,previous.lessonId,actor.personId)});
 };
 const lessonParam=(r:FastifyRequest)=>z.object({lessonId:id}).passthrough().parse(r.params).lessonId;
 const requestParam=(r:FastifyRequest)=>z.object({requestId:id}).passthrough().parse(r.params).requestId;
 const pending=async(db:PoolClient,schoolId:string,requestId:string)=>{
  const row=(await db.query<RequestRow>(`SELECT ${requestColumns} FROM drivy.lesson_change_request WHERE school_id=$1 AND id=$2`,[schoolId,requestId])).rows[0];
  if(!row)throw notFound();return row;
 };
 const closed=()=>new ApiError(409,'LESSON_CHANGE_REQUEST_CLOSED','Cette demande est déjà traitée.');

 // Conditions applicables et demandes d'une leçon, pour l'élève (ses demandes) comme pour le personnel qui la gère.
 app.get(`${base}/lessons/:lessonId/change-requests`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),lessonId=lessonParam(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,actor)=>changeState(db,schoolId,lessonId,actor.personId)),r);
 });

 // Boîte du personnel : demandes en attente sur des leçons encore planifiées, dans le périmètre de lecture (administration : toute l'école ;
 // moniteur : ses leçons). Pas de pagination : une seule demande en attente par leçon.
 app.get(`${base}/lesson-change-requests`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   if(!member?.roles.some(role=>role==='ADMIN'||role==='INSTRUCTOR'))throw forbidden();
   const rows=(await db.query<RequestRow&{planned_start:Date;planned_end:Date;time_zone:string;lesson_version:number;instructor_membership_id:string;learner_display_name:string|null}>(
    `SELECT ${requestColumns.split(',').map(column=>`r.${column}`).join(',')},l.planned_start,l.planned_end,l.time_zone,l.version AS lesson_version,l.instructor_membership_id,
      drivy.lesson_learner_name(l.school_id,l.training_id,l.instructor_membership_id,l.learner_id) AS learner_display_name
     FROM drivy.lesson_change_request r JOIN drivy.lesson l ON l.school_id=r.school_id AND l.id=r.lesson_id
     WHERE r.school_id=$1 AND r.status='PENDING' AND l.status='PLANNED' AND l.actual_start IS NULL
     ORDER BY l.planned_start,r.created_at,r.id LIMIT 100`,[schoolId])).rows;
   return {items:rows.map(row=>({request:requestView(row,actor.personId),lesson:{id:row.lesson_id,plannedStart:row.planned_start.toISOString(),plannedEnd:row.planned_end.toISOString(),
    timeZone:row.time_zone,version:row.lesson_version,instructorMembershipId:row.instructor_membership_id,learnerDisplayName:row.learner_display_name??''}}))};
  });
  return envelope(data,r);
 });

 // L'élève de la leçon demande un déplacement (disponibilités ou proposition, obligatoires) ou son annulation (note facultative).
 app.post(`${base}/lessons/:lessonId/change-requests`,{bodyLimit:4_096},async(r,reply)=>{
  const body=createBody.parse(r.body),lessonId=lessonParam(r),{schoolId}=params(r);
  const data=await run(r,'CREATE_LESSON_CHANGE_REQUEST',{...body,lessonId},null,['LEARNER'],async(db,actor)=>{
   const now=new Date(),lesson=await getLesson(db,schoolId,lessonId);
   const existing=(await db.query('SELECT 1 FROM drivy.lesson_change_request WHERE school_id=$1 AND lesson_id=$2 AND status=\'PENDING\'',[schoolId,lessonId])).rowCount!==0;
   const reason=blockedReason(lesson,actor.personId,existing,now);
   if(reason==='NOT_LEARNER')throw forbidden();
   if(reason){const [status,code,message]=blockedFailures[reason];throw new ApiError(status,code,message);}
   const conditions=describeConditions(await conditionRow(db,lessonId),lesson,now);
   let created:{id:string};
   try{
    created=(await db.query<{id:string}>(`INSERT INTO drivy.lesson_change_request(school_id,lesson_id,requester_person_id,kind,note,lesson_version,policy_version_id,cancellation_hours,deadline_at,late)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,[schoolId,lessonId,actor.personId,body.kind,body.note,lesson.version,conditions.policyVersionId,conditions.cancellationHours,conditions.deadlineAt,conditions.late])).rows[0]!;
   }catch(error){
    if(typeof error==='object'&&error!==null&&'code'in error&&error.code==='23505'){const [status,code,message]=blockedFailures.REQUEST_PENDING;throw new ApiError(status,code,message);}
    throw error;
   }
   return {data:await changeState(db,schoolId,lessonId,actor.personId,now),action:'LessonChangeRequested',resourceType:'LessonChangeRequest',resourceId:created.id,resourceVersion:1,changedFields:['status']};
  });
  reply.status(201);return envelope(data,r);
 });

 // L'élève retire sa demande tant qu'elle est en attente : la leçon n'est pas touchée.
 app.post(`${base}/lesson-change-requests/:requestId/withdraw`,{bodyLimit:1_024},async r=>{
  const body=operation.parse(r.body),requestId=requestParam(r),{schoolId}=params(r),expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'WITHDRAW_LESSON_CHANGE_REQUEST',{...body,requestId},expected,['LEARNER'],async(db,actor)=>{
   const row=await pending(db,schoolId,requestId);
   if(row.requester_person_id!==actor.personId)throw forbidden();
   checkVersion(row.version,expected);if(row.status!=='PENDING')throw closed();
   const updated=await db.query(`UPDATE drivy.lesson_change_request SET status='WITHDRAWN',version=version+1,resolved_by_membership_id=$3,resolved_at=statement_timestamp(),updated_at=statement_timestamp()
    WHERE school_id=$1 AND id=$2 AND status='PENDING'`,[schoolId,requestId,actor.membershipId]);
   if(updated.rowCount!==1)throw closed();
   return {data:await changeState(db,schoolId,row.lesson_id,actor.personId),action:'LessonChangeRequestWithdrawn',resourceType:'LessonChangeRequest',resourceId:requestId,resourceVersion:row.version+1,changedFields:['status']};
  }),r);
 });

 // Le personnel refuse : la leçon reste telle quelle, le motif est lisible par l'élève. Accepter passe par le déplacement ou l'annulation.
 app.post(`${base}/lesson-change-requests/:requestId/refuse`,{bodyLimit:2_048},async r=>{
  const body=refuseBody.parse(r.body),requestId=requestParam(r),{schoolId}=params(r),expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'REFUSE_LESSON_CHANGE_REQUEST',{...body,requestId},expected,['ADMIN','INSTRUCTOR'],async(db,actor)=>{
   const row=await pending(db,schoolId,requestId);
   if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_change_staff($1) AS ok',[row.lesson_id])).rows[0]?.ok)throw forbidden();
   checkVersion(row.version,expected);if(row.status!=='PENDING')throw closed();
   const resolution=body.note?body.note:null;
   const updated=await db.query(`UPDATE drivy.lesson_change_request SET status='REFUSED',version=version+1,resolved_by_membership_id=$3,resolved_at=statement_timestamp(),
    resolution_note=$4,updated_at=statement_timestamp() WHERE school_id=$1 AND id=$2 AND status='PENDING'`,[schoolId,requestId,actor.membershipId,resolution]);
   if(updated.rowCount!==1)throw closed();
   return {data:await changeState(db,schoolId,row.lesson_id,actor.personId),action:'LessonChangeRequestRefused',resourceType:'LessonChangeRequest',resourceId:requestId,resourceVersion:row.version+1,changedFields:['status','resolutionNote']};
  }),r);
 });
}

/** Le reçu d'une commande de demande est relu par son auteur tant que la demande reste dans son périmètre (GET …/operations/{operationId}). */
export async function authorizeLessonChangeOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(!['CREATE_LESSON_CHANGE_REQUEST','WITHDRAW_LESSON_CHANGE_REQUEST','REFUSE_LESSON_CHANGE_REQUEST'].includes(type))return false;
 if(!(await db.query('SELECT 1 FROM drivy.lesson_change_request WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rowCount)throw notFound();
 return true;
}
