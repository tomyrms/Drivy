import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type SchoolRow} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';

/**
 * Examens théorique et pratique d'une formation (#54). Saisie manuelle du personnel, aucun lien avec une autorité : une date passée ne
 * devient jamais une réussite ni un échec, le résultat est un fait saisi, corrigé avec motif, daté et signé (exam_revision). Un examen
 * est une tentative ; un report garde la tentative d'origine et en ouvre une nouvelle. L'accompagnement du moniteur est facultatif et
 * occupe réellement son agenda (table reservation, même contrainte d'exclusion que les leçons et les cours). Un examen ne touche ni les
 * autres formations de l'élève, ni les leçons, ni les bilans. Contrat : contracts/exams.json.
 */
const id=z.uuid(),date=z.iso.datetime({offset:true}),empty=z.object({}).strict();
const text=(max:number)=>z.string().trim().max(max);
const escortSchema=z.object({instructorMembershipId:id,startsAt:date,endsAt:date}).strict();
const schedule={startsAt:date,timeZone:z.string().min(1).max(100),location:text(200).default(''),escort:escortSchema.nullish()};
const createBody=z.object({operationId:id,kind:z.enum(['THEORY','PRACTICAL']),...schedule}).strict();
const updateBody=z.object({operationId:id,...schedule,reason:text(1000).default('')}).strict();
const postponeBody=z.object({operationId:id,...schedule,reason:text(1000).default('')}).strict();
const resultBody=z.object({operationId:id,result:z.enum(['PASSED','FAILED','ABSENT']),note:text(1000).default(''),reason:text(1000).default('')}).strict();

type Kind='THEORY'|'PRACTICAL';
type Status='SCHEDULED'|'POSTPONED'|'ABSENT'|'PASSED'|'FAILED';
interface ExamRow {id:string;training_id:string;kind:Kind;category_code:string;status:Status;starts_at:Date;time_zone:string;location:string;
 escort_instructor_membership_id:string|null;escort_starts_at:Date|null;escort_ends_at:Date|null;result_note:string;result_recorded_at:Date|null;
 postponed_to_exam_id:string|null;version:number;created_at:Date}
export interface ExamView {id:string;trainingId:string;kind:Kind;categoryCode:string;status:Status;startsAt:string;timeZone:string;location:string;
 escort:{instructorMembershipId:string;startsAt:string;endsAt:string}|null;resultNote:string;resultRecordedAt:string|null;postponedToExamId:string|null;
 attempt:number|null;needsResult:boolean;version:number;createdAt:string}
export interface ExamSummary {kind:Kind;passed:boolean;attempts:number;scheduledExamId:string|null}
export interface ExamState {trainingId:string;canManage:boolean;exams:ExamView[];summary:ExamSummary[]}

const columns='id,training_id,kind,category_code,status,starts_at,time_zone,location,escort_instructor_membership_id,escort_starts_at,escort_ends_at,result_note,result_recorded_at,postponed_to_exam_id,version,created_at';
const kinds:Kind[]=['THEORY','PRACTICAL'];

/** Rang de chaque tentative réellement tenue ou prévue : un report n'en est pas une. */
export function attemptNumbers(rows:Pick<ExamRow,'id'|'kind'|'status'|'starts_at'|'created_at'>[]):Map<string,number>{
 const result=new Map<string,number>();
 for(const kind of kinds){
  rows.filter(row=>row.kind===kind&&row.status!=='POSTPONED')
   .sort((a,b)=>a.starts_at.getTime()-b.starts_at.getTime()||a.created_at.getTime()-b.created_at.getTime()||a.id.localeCompare(b.id))
   .forEach((row,index)=>result.set(row.id,index+1));
 }
 return result;
}
export function examView(row:ExamRow,attempt:number|undefined,now:Date):ExamView{
 return {id:row.id,trainingId:row.training_id,kind:row.kind,categoryCode:row.category_code,status:row.status,startsAt:row.starts_at.toISOString(),timeZone:row.time_zone,
  location:row.location,escort:row.escort_instructor_membership_id&&row.escort_starts_at&&row.escort_ends_at
   ?{instructorMembershipId:row.escort_instructor_membership_id,startsAt:row.escort_starts_at.toISOString(),endsAt:row.escort_ends_at.toISOString()}:null,
  resultNote:row.result_note,resultRecordedAt:row.result_recorded_at?.toISOString()??null,postponedToExamId:row.postponed_to_exam_id,
  attempt:attempt??null,needsResult:row.status==='SCHEDULED'&&row.starts_at.getTime()<=now.getTime(),version:row.version,createdAt:row.created_at.toISOString()};
}
export function summarize(rows:Pick<ExamRow,'id'|'kind'|'status'>[]):ExamSummary[]{
 return kinds.map(kind=>{
  const own=rows.filter(row=>row.kind===kind);
  return {kind,passed:own.some(row=>row.status==='PASSED'),attempts:own.filter(row=>row.status!=='POSTPONED').length,scheduledExamId:own.find(row=>row.status==='SCHEDULED')?.id??null};
 });
}
/** Examens d'une formation pour l'appelant : l'élève lit les siens, le personnel ceux de ses formations (portée relue par la base). */
export async function examState(db:PoolClient,schoolId:string,trainingId:string,now=new Date()):Promise<ExamState>{
 if(!(await db.query<{ok:boolean}>('SELECT drivy.catalogue_training_visible($1) AS ok',[trainingId])).rows[0]?.ok)throw notFound();
 const rows=(await db.query<ExamRow>(`SELECT ${columns} FROM drivy.exam WHERE school_id=$1 AND training_id=$2 ORDER BY starts_at DESC,created_at DESC,id DESC LIMIT 100`,[schoolId,trainingId])).rows;
 const attempts=attemptNumbers(rows),canManage=(await db.query<{ok:boolean}>('SELECT drivy.exam_manage($1) AS ok',[trainingId])).rows[0]?.ok===true;
 return {trainingId,canManage,exams:rows.map(row=>examView(row,attempts.get(row.id),now)),summary:summarize(rows)};
}

const failures:Record<string,[number,string]>={
 exam_one_scheduled:[409,'Une date est déjà prévue pour cette épreuve. Reportez-la ou renseignez son résultat.'],
 exam_one_passed:[409,'Cette épreuve est déjà réussie. Corrigez d’abord son résultat pour la replanifier.']
};
const failureCodes:Record<string,string>={exam_one_scheduled:'EXAM_ALREADY_SCHEDULED',exam_one_passed:'EXAM_ALREADY_PASSED'};
/** Traduit les refus de la base : unicité (une épreuve prévue, une épreuve réussie) et chevauchement de l'accompagnement. */
function examFailure(error:unknown):never{
 if(typeof error==='object'&&error!==null&&'code'in error){
  if(error.code==='23505'&&'constraint'in error&&typeof error.constraint==='string'){
   const known=failures[error.constraint];if(known)throw new ApiError(known[0],failureCodes[error.constraint]!,known[1]);
  }
  if(error.code==='23P01')throw new ApiError(409,'EXAM_ESCORT_CONFLICT','Le moniteur a déjà un rendez-vous pendant l’accompagnement.');
 }
 throw error;
}

interface Schedule {startsAt:string;timeZone:string;location:string;escort?:{instructorMembershipId:string;startsAt:string;endsAt:string}|null|undefined}
/** Fuseau de l'école et date plausible : un examen saisi après coup reste possible, une année fantaisiste non. */
function validateSchedule(value:Schedule,school:SchoolRow,now:Date){
 if(value.timeZone!==school.timeZone)throw new ApiError(422,'INVALID_TIME_ZONE','Utilisez le fuseau de l’école affiché.');
 const at=Date.parse(value.startsAt);
 if(at<now.getTime()-3*365*86_400_000||at>now.getTime()+2*365*86_400_000)throw new ApiError(422,'INVALID_EXAM_DATE','Choisissez une date d’examen récente ou à venir.');
 if(value.escort){
  const start=Date.parse(value.escort.startsAt),end=Date.parse(value.escort.endsAt);
  if(!(end>start)||end-start>12*3_600_000)throw new ApiError(422,'INVALID_ESCORT','L’accompagnement doit durer au plus 12 heures.');
 }
}
async function holdEscort(db:PoolClient,schoolId:string,exam:{id:string;training_id:string},escort:NonNullable<Schedule['escort']>){
 const person=(await db.query<{person:string|null}>('SELECT drivy.exam_escort_person($1,$2) AS person',[exam.training_id,escort.instructorMembershipId])).rows[0]?.person;
 if(!person)throw new ApiError(422,'INSTRUCTOR_NOT_ASSIGNED','Le moniteur d’accompagnement doit être actif et affecté à cette formation.');
 await db.query(`INSERT INTO drivy.reservation(school_id,exam_id,resource_id,resource_role,during) VALUES($1,$2,$3,'INSTRUCTOR',tstzrange($4::timestamptz,$5::timestamptz,'[)'))`,
  [schoolId,exam.id,person,escort.startsAt,escort.endsAt]);
}
const releaseEscort=(db:PoolClient,schoolId:string,examId:string)=>db.query('UPDATE drivy.reservation SET active=false WHERE school_id=$1 AND exam_id=$2 AND active',[schoolId,examId]);
async function revise(db:PoolClient,schoolId:string,examId:string,operationId:string,action:string,actor:CommandActor,reason:string){
 await db.query(`INSERT INTO drivy.exam_revision(school_id,exam_id,revision,operation_id,action,status,starts_at,time_zone,location,escort_instructor_membership_id,escort_starts_at,escort_ends_at,result_note,actor_membership_id,reason)
  SELECT school_id,id,version,$3,$4,status,starts_at,time_zone,location,escort_instructor_membership_id,escort_starts_at,escort_ends_at,result_note,$5,$6 FROM drivy.exam WHERE school_id=$1 AND id=$2`,
  [schoolId,examId,operationId,action,actor.membershipId,reason]);
}

export function registerExams(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId',params=(r:FastifyRequest)=>z.object({schoolId:id}).passthrough().parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const trainingParam=(r:FastifyRequest)=>z.object({trainingId:id}).passthrough().parse(r.params).trainingId;
 const examParam=(r:FastifyRequest)=>z.object({examId:id}).passthrough().parse(r.params).examId;
 const run=async(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,expected:number|null,
  work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<CommandEffect<ExamState>>)=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  try{
   return await schoolCommand<ExamState>(options.pool,identity,schoolId,type,body,expected,work,['ADMIN','INSTRUCTOR'],
    {replay:async(db,_actor,previous)=>examState(db,schoolId,previous.trainingId)});
  }catch(error){return examFailure(error);}
 };
 /** Formation active d'un dossier non archivé, écriture permise à l'appelant ; sinon refus clair avant toute écriture. */
 const writableTraining=async(db:PoolClient,schoolId:string,trainingId:string)=>{
  const row=(await db.query<{status:string;archived_at:Date|null;category_code:string}>(`SELECT t.status,l.archived_at,o.category_code FROM drivy.training t
   JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
   WHERE t.school_id=$1 AND t.id=$2`,[schoolId,trainingId])).rows[0];
  if(!row)throw notFound();
  if(!(await db.query<{ok:boolean}>('SELECT drivy.exam_manage($1) AS ok',[trainingId])).rows[0]?.ok)throw forbidden();
  if(row.status!=='ACTIVE'||row.archived_at)throw new ApiError(422,'TRAINING_NOT_ACTIVE','La formation doit être active dans un dossier non archivé.');
  return row;
 };
 const loadExam=async(db:PoolClient,schoolId:string,examId:string)=>{
  const row=(await db.query<ExamRow>(`SELECT ${columns} FROM drivy.exam WHERE school_id=$1 AND id=$2`,[schoolId,examId])).rows[0];
  if(!row)throw notFound();
  if(!(await db.query<{ok:boolean}>('SELECT drivy.exam_manage($1) AS ok',[row.training_id])).rows[0]?.ok)throw forbidden();
  return row;
 };
 const closed=()=>new ApiError(409,'EXAM_CLOSED','Seul un examen prévu peut être modifié, reporté ou renseigné pour la première fois.');

 // Examens d'une formation, avec le rang de chaque tentative et le résumé de chaque épreuve.
 app.get(`${base}/trainings/:trainingId/exams`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),trainingId=trainingParam(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async db=>examState(db,schoolId,trainingId)),r);
 });

 // Historique d'un examen : réservé au personnel de la formation. L'élève lit ses examens, pas qui les a corrigés ni pourquoi.
 app.get(`${base}/exams/:examId/revisions`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),examId=examParam(r),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async db=>{
   await loadExam(db,schoolId,examId);
   const rows=(await db.query<{revision:number;action:string;status:Status;starts_at:Date;time_zone:string;location:string;result_note:string;actor_membership_id:string;reason:string;created_at:Date}>(
    `SELECT revision,action,status,starts_at,time_zone,location,result_note,actor_membership_id,reason,created_at FROM drivy.exam_revision WHERE school_id=$1 AND exam_id=$2 ORDER BY revision DESC LIMIT 100`,[schoolId,examId])).rows;
   return {examId,items:rows.map(row=>({revision:row.revision,action:row.action,status:row.status,startsAt:row.starts_at.toISOString(),timeZone:row.time_zone,location:row.location,
    resultNote:row.result_note,actorMembershipId:row.actor_membership_id,reason:row.reason,createdAt:row.created_at.toISOString()}))};
  });
  return envelope(data,r);
 });

 // Prévoit un examen. Une seule date prévue par épreuve, et aucune nouvelle date pour une épreuve déjà réussie.
 app.post(`${base}/trainings/:trainingId/exams`,{bodyLimit:4_096},async(r,reply)=>{
  const body=createBody.parse(r.body),trainingId=trainingParam(r),{schoolId}=params(r);
  const data=await run(r,'CREATE_EXAM',{...body,trainingId},null,async(db,actor,school)=>{
   const training=await writableTraining(db,schoolId,trainingId);validateSchedule(body,school,new Date());
   if((await db.query("SELECT 1 FROM drivy.exam WHERE school_id=$1 AND training_id=$2 AND kind=$3 AND status='PASSED'",[schoolId,trainingId,body.kind])).rowCount)
    throw new ApiError(409,'EXAM_ALREADY_PASSED',failures.exam_one_passed![1]);
   const row=(await db.query<{id:string;training_id:string}>(`INSERT INTO drivy.exam(school_id,training_id,kind,category_code,starts_at,time_zone,location,created_by)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,training_id`,[schoolId,trainingId,body.kind,training.category_code,body.startsAt,body.timeZone,body.location,actor.membershipId])).rows[0]!;
   if(body.escort)await holdEscort(db,schoolId,row,body.escort);
   await revise(db,schoolId,row.id,body.operationId,'CREATED',actor,'');
   return {data:await examState(db,schoolId,trainingId),action:'ExamCreated',resourceType:'Exam',resourceId:row.id,resourceVersion:1,changedFields:['status','startsAt']};
  });
  reply.status(201);return envelope(data,r);
 });

 // Change la date, le lieu ou l'accompagnement d'un examen encore prévu.
 app.post(`${base}/exams/:examId/update`,{bodyLimit:4_096},async r=>{
  const body=updateBody.parse(r.body),examId=examParam(r),{schoolId}=params(r),expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'UPDATE_EXAM',{...body,examId},expected,async(db,actor,school)=>{
   const old=await loadExam(db,schoolId,examId);checkVersion(old.version,expected);
   if(old.status!=='SCHEDULED')throw closed();
   await writableTraining(db,schoolId,old.training_id);validateSchedule(body,school,new Date());
   await releaseEscort(db,schoolId,examId);
   await db.query(`UPDATE drivy.exam SET starts_at=$3,time_zone=$4,location=$5,escort_instructor_membership_id=$6,escort_starts_at=$7,escort_ends_at=$8,version=version+1,updated_at=statement_timestamp()
    WHERE school_id=$1 AND id=$2`,[schoolId,examId,body.startsAt,body.timeZone,body.location,body.escort?.instructorMembershipId??null,body.escort?.startsAt??null,body.escort?.endsAt??null]);
   if(body.escort)await holdEscort(db,schoolId,old,body.escort);
   await revise(db,schoolId,examId,body.operationId,'UPDATED',actor,body.reason);
   return {data:await examState(db,schoolId,old.training_id),action:'ExamUpdated',resourceType:'Exam',resourceId:examId,resourceVersion:old.version+1,changedFields:['startsAt','timeZone','location','escort'],reason:body.reason||undefined};
  }),r);
 });

 // Reporte : la tentative d'origine est gardée (Reporté) et une nouvelle tentative prévue s'ouvre à la nouvelle date.
 app.post(`${base}/exams/:examId/postpone`,{bodyLimit:4_096},async r=>{
  const body=postponeBody.parse(r.body),examId=examParam(r),{schoolId}=params(r),expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'POSTPONE_EXAM',{...body,examId},expected,async(db,actor,school)=>{
   const old=await loadExam(db,schoolId,examId);checkVersion(old.version,expected);
   if(old.status!=='SCHEDULED')throw closed();
   const training=await writableTraining(db,schoolId,old.training_id);validateSchedule(body,school,new Date());
   const next=randomUUID();
   await releaseEscort(db,schoolId,examId);
   await db.query("UPDATE drivy.exam SET status='POSTPONED',postponed_to_exam_id=$3,version=version+1,updated_at=statement_timestamp() WHERE school_id=$1 AND id=$2",[schoolId,examId,next]);
   await db.query(`INSERT INTO drivy.exam(id,school_id,training_id,kind,category_code,starts_at,time_zone,location,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [next,schoolId,old.training_id,old.kind,training.category_code,body.startsAt,body.timeZone,body.location,actor.membershipId]);
   if(body.escort)await holdEscort(db,schoolId,{id:next,training_id:old.training_id},body.escort);
   await revise(db,schoolId,examId,body.operationId,'POSTPONED',actor,body.reason);
   await revise(db,schoolId,next,body.operationId,'CREATED',actor,'');
   return {data:await examState(db,schoolId,old.training_id),action:'ExamPostponed',resourceType:'Exam',resourceId:examId,resourceVersion:old.version+1,changedFields:['status','postponedToExamId'],reason:body.reason||undefined};
  }),r);
 });

 // Renseigne le résultat d'un examen prévu dont la date est venue, ou le corrige (motif obligatoire, historique conservé).
 app.post(`${base}/exams/:examId/result`,{bodyLimit:4_096},async r=>{
  const body=resultBody.parse(r.body),examId=examParam(r),{schoolId}=params(r),expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'SET_EXAM_RESULT',{...body,examId},expected,async(db,actor)=>{
   const old=await loadExam(db,schoolId,examId);checkVersion(old.version,expected);
   if(old.status==='POSTPONED')throw new ApiError(409,'EXAM_CLOSED','Un examen reporté n’a pas de résultat : renseignez la nouvelle tentative.');
   const correction=old.status!=='SCHEDULED';
   if(!correction&&old.starts_at.getTime()>Date.now())throw new ApiError(409,'EXAM_NOT_STARTED','La date de l’examen n’est pas encore passée.');
   if(correction&&body.reason==='')throw new ApiError(422,'EXAM_REASON_REQUIRED','Indiquez le motif de la correction.');
   await db.query(`UPDATE drivy.exam SET status=$3,result_note=$4,result_recorded_at=coalesce(result_recorded_at,statement_timestamp()),version=version+1,updated_at=statement_timestamp()
    WHERE school_id=$1 AND id=$2`,[schoolId,examId,body.result,body.note]);
   await revise(db,schoolId,examId,body.operationId,correction?'RESULT_CORRECTED':'RESULT_RECORDED',actor,body.reason);
   return {data:await examState(db,schoolId,old.training_id),action:correction?'ExamResultCorrected':'ExamResultRecorded',resourceType:'Exam',resourceId:examId,resourceVersion:old.version+1,
    changedFields:['status','resultNote'],reason:body.reason||undefined};
  }),r);
 });
}

/** Le reçu d'une commande d'examen est relu par son auteur tant que l'examen reste dans son périmètre (GET …/operations/{operationId}). */
export async function authorizeExamOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(!['CREATE_EXAM','UPDATE_EXAM','POSTPONE_EXAM','SET_EXAM_RESULT'].includes(type))return false;
 if(!(await db.query('SELECT 1 FROM drivy.exam WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rowCount)throw notFound();
 return true;
}
