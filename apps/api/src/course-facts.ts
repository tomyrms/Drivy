import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,schoolCommand,type CommandActor,type CommandEffect} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {getSeries} from './courses.js';

/**
 * Cours collectifs : appel (#42), règlements sur place (#81), accomplissement validé (#82). Trois faits distincts : aucun ne
 * déduit l'autre. Règles dans la migration 044. Contrat : docs/implementation/cours-collectifs-faits-42-81-82.md.
 */
const id=z.uuid(),empty=z.object({}).strict(),note=z.string().trim().max(500).nullish().transform(v=>v??null);
const attendanceBody=z.object({operationId:id,status:z.enum(['PRESENT','ABSENT','EXCUSED']),expectedVersion:z.number().int().min(1).nullable(),note}).strict();
const paymentBody=z.object({operationId:id,amountCents:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),note}).strict();
const reasonBody=z.object({operationId:id,reason:z.string().trim().min(1).max(1000)}).strict();
const validateBody=z.object({operationId:id,note:z.string().trim().max(1000).nullish().transform(v=>v??null)}).strict();

const failures:Record<string,[number,string]>={
 NOT_FOUND:[404,'Objet introuvable dans le périmètre autorisé.'],
 INVALID_REQUEST:[400,'Requête invalide.'],
 COURSE_ACCESS_REQUIRED:[403,'Cette action demande un droit que ce compte n’a pas.'],
 COURSE_OCCURRENCE_NOT_STARTED:[409,'Cette séance n’a pas encore commencé.'],
 COURSE_ENROLLMENT_CLOSED:[409,'Cette inscription est annulée.'],
 VERSION_CONFLICT:[412,'Cette présence a changé. Rechargez avant de corriger.'],
 COURSE_PAYMENT_VOIDED:[409,'Ce règlement est déjà annulé.'],
 COURSE_REASON_REQUIRED:[422,'Indiquez le motif.'],
 COURSE_NO_REQUIRED_OCCURRENCE:[409,'Ce cours n’a aucune séance obligatoire.'],
 COURSE_REQUIREMENTS_MISSING:[409,'Toutes les séances obligatoires ne sont pas marquées présentes.'],
 COURSE_ALREADY_COMPLETED:[409,'Ce cours est déjà validé pour cet élève.'],
 COURSE_COMPLETION_REVOKED:[409,'Cette validation est déjà retirée.']
};
function factFailure(error:unknown):never{
 if(typeof error==='object'&&error!==null&&'code'in error){
  if(error.code==='P0001'&&'message'in error&&typeof error.message==='string'){const known=failures[error.message];if(known)throw new ApiError(known[0],error.message,known[1]);}
  if(error.code==='23505')throw new ApiError(409,'COURSE_ALREADY_COMPLETED',failures.COURSE_ALREADY_COMPLETED![1]);
 }
 throw error;
}

interface SheetRights {canTakeAttendance:boolean;canRecordPayment:boolean;canValidate:boolean}
export interface CourseSheetRow {enrollmentId:string;learnerId:string;learnerDisplayName:string;status:'ACTIVE'|'CANCELLED';cancelledAt:string|null;
 attendance:{occurrenceId:string;status:'PRESENT'|'ABSENT'|'EXCUSED'|null;version:number|null;recordedAt:string|null}[];
 requirements:{required:number;present:number;missing:number};
 payments:{id:string;amountCents:number;recordedAt:string;note:string|null;voidedAt:string|null;voidReason:string|null}[];
 completion:{id:string;validatedAt:string;seriesId:string|null;revokedAt:string|null}|null}

/** Feuille du cours pour le personnel : un état par élève et par séance, règlements et validation, droits de l'appelant. */
async function sheet(db:PoolClient,schoolId:string,seriesId:string){
 const series=await getSeries(db,schoolId,seriesId);
 const rights=(await db.query<SheetRights>(`SELECT bool_or(drivy.course_can_take_attendance(o.id)) AS "canTakeAttendance",drivy.course_can_record_payment($1) AS "canRecordPayment",
  drivy.course_can_validate($1) AS "canValidate" FROM drivy.course_occurrence o WHERE o.series_id=$2`,[schoolId,seriesId])).rows[0]!;
 if(!rights.canTakeAttendance&&!rights.canRecordPayment&&!rights.canValidate)throw new ApiError(403,'COURSE_ACCESS_REQUIRED',failures.COURSE_ACCESS_REQUIRED![1]);
 const enrollments=(await db.query<{id:string;learner_id:string;name:string|null;status:'ACTIVE'|'CANCELLED';cancelled_at:Date|null;type_id:string}>(`SELECT e.id,e.learner_id,
  drivy.lesson_learner_display_name_for_course(e.id) AS name,e.status,e.cancelled_at,s.type_id FROM drivy.course_enrollment e JOIN drivy.course_series s ON s.id=e.series_id
  WHERE e.series_id=$1 ORDER BY e.status,e.created_at`,[seriesId])).rows;
 const ids=enrollments.map(e=>e.id);
 const attendance=(await db.query<{enrollment_id:string;occurrence_id:string;status:'PRESENT'|'ABSENT'|'EXCUSED';version:number;recorded_at:Date}>(
  'SELECT enrollment_id,occurrence_id,status,version,recorded_at FROM drivy.course_attendance WHERE enrollment_id=ANY($1::uuid[])',[ids])).rows;
 const payments=rights.canRecordPayment?(await db.query<{id:string;enrollment_id:string;amount_cents:string;recorded_at:Date;note:string|null;voided_at:Date|null;void_reason:string|null}>(
  'SELECT id,enrollment_id,amount_cents,recorded_at,note,voided_at,void_reason FROM drivy.course_payment_record WHERE enrollment_id=ANY($1::uuid[]) ORDER BY recorded_at',[ids])).rows:[];
 const rows:CourseSheetRow[]=[];
 for(const e of enrollments){
  const req=(await db.query<{required:number;present:number;missing:number}>('SELECT * FROM drivy.course_requirements($1)',[e.id])).rows[0]!;
  const completion=(await db.query<{id:string;validated_at:Date;series_id:string|null;revoked_at:Date|null}>(`SELECT id,validated_at,series_id,revoked_at FROM drivy.course_completion
   WHERE learner_id=$1 AND type_id=$2 AND revoked_at IS NULL`,[e.learner_id,e.type_id])).rows[0];
  rows.push({enrollmentId:e.id,learnerId:e.learner_id,learnerDisplayName:e.name??'',status:e.status,cancelledAt:e.cancelled_at?.toISOString()??null,
   attendance:series.occurrences.map(o=>{const a=attendance.find(x=>x.enrollment_id===e.id&&x.occurrence_id===o.id);
    return {occurrenceId:o.id,status:a?.status??null,version:a?.version??null,recordedAt:a?.recorded_at.toISOString()??null};}),
   requirements:req,
   payments:payments.filter(p=>p.enrollment_id===e.id).map(p=>({id:p.id,amountCents:Number(p.amount_cents),recordedAt:p.recorded_at.toISOString(),note:p.note,voidedAt:p.voided_at?.toISOString()??null,voidReason:p.void_reason})),
   completion:completion?{id:completion.id,validatedAt:completion.validated_at.toISOString(),seriesId:completion.series_id,revokedAt:null}:null});
 }
 return {series,rights,rows};
}
/** Progression de l'élève appelant : ses présences, exigences et validations ; jamais les autres participants ni ses règlements. */
async function myProgress(db:PoolClient,schoolId:string,personId:string){
 const learner=(await db.query<{id:string}>('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2',[schoolId,personId])).rows[0];
 if(!learner)return {completions:[],enrollments:[]};
 const completions=(await db.query<{id:string;type_id:string;title:string;validated_at:Date;series_id:string|null}>(`SELECT c.id,c.type_id,t.title,c.validated_at,c.series_id FROM drivy.course_completion c
  JOIN drivy.course_type t ON t.id=c.type_id WHERE c.learner_id=$1 AND c.revoked_at IS NULL ORDER BY c.validated_at DESC`,[learner.id])).rows;
 const enrollments=(await db.query<{id:string;series_id:string;status:string}>(`SELECT id,series_id,status FROM drivy.course_enrollment WHERE learner_id=$1 AND status='ACTIVE' ORDER BY created_at DESC`,[learner.id])).rows;
 const progress=[];
 for(const e of enrollments){
  const req=(await db.query<{required:number;present:number;missing:number}>('SELECT * FROM drivy.course_requirements($1)',[e.id])).rows[0]!;
  const marks=(await db.query<{occurrence_id:string;status:string}>('SELECT occurrence_id,status FROM drivy.course_attendance WHERE enrollment_id=$1',[e.id])).rows;
  progress.push({enrollmentId:e.id,seriesId:e.series_id,requirements:req,attendance:marks.map(m=>({occurrenceId:m.occurrence_id,status:m.status}))});
 }
 return {completions:completions.map(c=>({id:c.id,typeId:c.type_id,typeTitle:c.title,validatedAt:c.validated_at.toISOString(),seriesId:c.series_id})),enrollments:progress};
}

export function registerCourseFacts(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId',params=(r:FastifyRequest)=>z.object({schoolId:id}).passthrough().parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const run=async<T>(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,work:(db:PoolClient,actor:CommandActor)=>Promise<CommandEffect<T>>,replay:(db:PoolClient)=>Promise<T>)=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  try{return await schoolCommand<T>(options.pool,identity,schoolId,type,body,null,async(db,actor)=>{
   try{await db.query('SAVEPOINT course_fact');const effect=await work(db,actor);await db.query('RELEASE SAVEPOINT course_fact');return effect;}
   catch(error){await db.query('ROLLBACK TO SAVEPOINT course_fact');throw error;}
  },['ADMIN','INSTRUCTOR'],{replay:async db=>replay(db)});}
  catch(error){return factFailure(error);}
 };
 const seriesOf=async(db:PoolClient,enrollmentId:string)=>{const row=(await db.query<{series_id:string}>('SELECT series_id FROM drivy.course_enrollment WHERE id=$1',[enrollmentId])).rows[0];if(!row)throw notFound();return row.series_id;};

 app.get(`${base}/course-series/:seriesId/sheet`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),seriesId=z.object({seriesId:id}).passthrough().parse(r.params).seriesId,identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,_a,member)=>{if(!member?.roles.some(x=>x==='ADMIN'||x==='INSTRUCTOR'))throw forbidden();return sheet(db,schoolId,seriesId);}),r);
 });
 app.get(`${base}/course-progress/me`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{if(!member)throw forbidden();return myProgress(db,schoolId,actor.personId);}),r);
 });

 // #42 : présence d'un élève à une séance. expectedVersion null = première saisie ; sinon correction de cette version.
 app.put(`${base}/course-enrollments/:enrollmentId/attendance/:occurrenceId`,{bodyLimit:2_048},async r=>{
  const body=attendanceBody.parse(r.body),{schoolId}=params(r),{enrollmentId,occurrenceId}=z.object({enrollmentId:id,occurrenceId:id}).passthrough().parse(r.params);
  return envelope(await run(r,'RECORD_COURSE_ATTENDANCE',{...body,enrollmentId,occurrenceId},async db=>{
   const version=(await db.query<{v:number}>('SELECT drivy.course_record_attendance($1,$2,$3,$4,$5) AS v',[enrollmentId,occurrenceId,body.status,body.expectedVersion,body.note])).rows[0]!.v;
   return {data:await sheet(db,schoolId,await seriesOf(db,enrollmentId)),action:'CourseAttendanceRecorded',resourceType:'CourseAttendance',resourceId:enrollmentId,resourceVersion:version,changedFields:['status']};
  },async db=>sheet(db,schoolId,await seriesOf(db,enrollmentId))),r);
 });
 // #81 : règlement sur place, puis annulation éventuelle avec motif. Aucun effet sur présence ou validation.
 app.post(`${base}/course-enrollments/:enrollmentId/payments`,{bodyLimit:2_048},async(r,reply)=>{
  const body=paymentBody.parse(r.body),{schoolId}=params(r),enrollmentId=z.object({enrollmentId:id}).passthrough().parse(r.params).enrollmentId;
  const data=await run(r,'RECORD_COURSE_PAYMENT',{...body,enrollmentId},async db=>{
   const payment=(await db.query<{id:string}>('SELECT drivy.course_record_payment($1,$2,$3) AS id',[enrollmentId,body.amountCents,body.note])).rows[0]!.id;
   return {data:await sheet(db,schoolId,await seriesOf(db,enrollmentId)),action:'CoursePaymentRecorded',resourceType:'CoursePayment',resourceId:payment,resourceVersion:1,changedFields:['payment']};
  },async db=>sheet(db,schoolId,await seriesOf(db,enrollmentId)));
  reply.code(201);return envelope(data,r);
 });
 app.post(`${base}/course-payments/:paymentId/void`,{bodyLimit:2_048},async r=>{
  const body=reasonBody.parse(r.body),{schoolId}=params(r),paymentId=z.object({paymentId:id}).passthrough().parse(r.params).paymentId;
  const enrollmentOf=async(db:PoolClient)=>{const row=(await db.query<{enrollment_id:string}>('SELECT enrollment_id FROM drivy.course_payment_record WHERE id=$1',[paymentId])).rows[0];if(!row)throw notFound();return row.enrollment_id;};
  return envelope(await run(r,'VOID_COURSE_PAYMENT',{...body,paymentId},async db=>{
   await db.query('SELECT drivy.course_void_payment($1,$2)',[paymentId,body.reason]);
   return {data:await sheet(db,schoolId,await seriesOf(db,await enrollmentOf(db))),action:'CoursePaymentVoided',resourceType:'CoursePayment',resourceId:paymentId,resourceVersion:2,changedFields:['voided'],reason:body.reason};
  },async db=>sheet(db,schoolId,await seriesOf(db,await enrollmentOf(db)))),r);
 });
 // #82 : validation explicite, après présence à toutes les séances obligatoires ; retrait avec motif.
 app.post(`${base}/course-enrollments/:enrollmentId/validate`,{bodyLimit:2_048},async(r,reply)=>{
  const body=validateBody.parse(r.body),{schoolId}=params(r),enrollmentId=z.object({enrollmentId:id}).passthrough().parse(r.params).enrollmentId;
  const data=await run(r,'VALIDATE_COURSE',{...body,enrollmentId},async db=>{
   const completion=(await db.query<{id:string}>('SELECT drivy.course_validate($1,$2) AS id',[enrollmentId,body.note])).rows[0]!.id;
   return {data:await sheet(db,schoolId,await seriesOf(db,enrollmentId)),action:'CourseCompletionValidated',resourceType:'CourseCompletion',resourceId:completion,resourceVersion:1,changedFields:['completion']};
  },async db=>sheet(db,schoolId,await seriesOf(db,enrollmentId)));
  reply.code(201);return envelope(data,r);
 });
 app.post(`${base}/course-completions/:completionId/revoke`,{bodyLimit:2_048},async r=>{
  const body=reasonBody.parse(r.body),{schoolId}=params(r),completionId=z.object({completionId:id}).passthrough().parse(r.params).completionId;
  const seriesOfCompletion=async(db:PoolClient)=>{const row=(await db.query<{series_id:string|null}>('SELECT series_id FROM drivy.course_completion WHERE id=$1',[completionId])).rows[0];if(!row?.series_id)throw notFound();return row.series_id;};
  return envelope(await run(r,'REVOKE_COURSE_COMPLETION',{...body,completionId},async db=>{
   await db.query('SELECT drivy.course_revoke_completion($1,$2)',[completionId,body.reason]);
   return {data:await sheet(db,schoolId,await seriesOfCompletion(db)),action:'CourseCompletionRevoked',resourceType:'CourseCompletion',resourceId:completionId,resourceVersion:2,changedFields:['revoked'],reason:body.reason};
  },async db=>sheet(db,schoolId,await seriesOfCompletion(db))),r);
 });
}
