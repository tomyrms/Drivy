import {createHash,randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {Identity,TokenVerifier} from './auth.js';
import {canonical,checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type CommandGuards,type SchoolRow} from './commands.js';
import {ApiError,notFound} from './errors.js';
import {event,getLesson,lessonColumns,lessonCommandGuards,lessonProjection,openClosedAccount,releaseFutureOccupations,type LessonRow} from './lessons.js';

const id=z.uuid(),empty=z.object({}).strict(),date=z.iso.datetime({offset:true});
const reason=z.string().min(1).max(1000).refine(v=>/\S/.test(v),'Motif requis.');
const reasonCommand=z.object({operationId:id,reason}).strict();
const status=z.enum(['PLANNED','COMPLETED','CANCELLED','NO_SHOW']);
const booking=z.object({plannedStart:date,plannedEnd:date,timeZone:z.string(),meetingPoint:z.string().min(1).max(500),instructorMembershipId:id}).strict();
const proposalFields={targetStatus:status,reason,expectedAccountVersion:z.number().int().min(1).max(2_147_483_647),actualStart:date.nullable().optional(),actualEnd:date.nullable().optional(),futureBooking:booking.nullable().optional()};
const proposal=z.object(proposalFields).strict();
const approveCommand=z.object({operationId:id,proposal,expectedPublicationVersion:z.number().int().min(0)}).strict();
const correctCommand=z.object({operationId:id,...proposalFields,pedagogicalApprovalId:id.nullable().optional()}).strict();
type Proposal=z.infer<typeof proposal>;
type Lesson=ReturnType<typeof lessonProjection>;
interface AccountRow {id:string;version:number}
interface ApprovalRow {id:string;school_id:string;version:number;lesson_id:string;lesson_version:number;account_version:number;publication_version:number;proposal_hash:string;
 approved_by_membership_id:string;expires_at:Date;consumed_at:Date|null;approver_person_id?:string}
const approvalProjection=(r:ApprovalRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,lessonVersion:r.lesson_version,accountVersion:r.account_version,
 publicationVersion:r.publication_version,proposalHash:r.proposal_hash,approvedByMembershipId:r.approved_by_membership_id,expiresAt:r.expires_at.toISOString(),consumedAt:r.consumed_at?.toISOString()??null});
type Approval=ReturnType<typeof approvalProjection>;
/** Hash canonique du contenu proposé, hors operationId et pedagogicalApprovalId (api.md « Arbitrage encadré »). */
export function proposalHash(value:Proposal){
 return createHash('sha256').update(canonical({targetStatus:value.targetStatus,reason:value.reason,expectedAccountVersion:value.expectedAccountVersion,
  actualStart:value.actualStart??null,actualEnd:value.actualEnd??null,futureBooking:value.futureBooking??null})).digest('hex');
}
const conflict=(code:string,message:string)=>new ApiError(409,code,message);
async function lessonAccount(db:PoolClient,schoolId:string,lessonId:string,lock=false){
 return (await db.query<AccountRow>(`SELECT id,version FROM drivy.lesson_account WHERE school_id=$1 AND lesson_id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,lessonId])).rows[0];
}
async function author(db:PoolClient,lessonId:string){if(!(await db.query<{ok:boolean}>('SELECT drivy.report_lesson_author($1) AS ok',[lessonId])).rows[0]?.ok)throw notFound();}
/** Moniteur désigné et affecté : mêmes droits que la publication du bilan (AP54). */
function authorGuards<T>(schoolId:string,lessonId:string,replay:(db:PoolClient,data:T)=>Promise<T>):CommandGuards<T>{return {
 additionalPersons:async db=>{
  const lesson=await getLesson(db,schoolId,lessonId);await author(db,lesson.id);
  await db.query("SELECT set_config('app.learner_id',$1,true)",[lesson.learner_id]);
  const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;if(!person)throw notFound();return [person];
 },
 authorize:async db=>author(db,lessonId),
 replay:async(db,_actor,data)=>{await author(db,lessonId);return replay(db,data);}
};}
/** Transitions exécutables dans cette tranche ; les autres restent refusées explicitement, sans effet partiel. */
function validateTransition(lesson:LessonRow,value:Proposal){
 if(lesson.status==='PLANNED')throw conflict('LESSON_OUTCOME_CONFLICT','Cette leçon n’a pas encore de résultat : utilisez le constat, l’absence ou l’annulation.');
 if(value.targetStatus===lesson.status)throw new ApiError(422,'OUTCOME_UNCHANGED','Choisissez un résultat différent du résultat actuel.');
 if(value.targetStatus==='PLANNED'||value.targetStatus==='COMPLETED')throw conflict('OUTCOME_CORRECTION_NOT_READY','Le retour vers une leçon planifiée ou réalisée n’est pas encore disponible. Aucun changement n’a été fait.');
 if(value.actualStart!=null||value.actualEnd!=null||value.futureBooking!=null)throw new ApiError(422,'OUTCOME_FIELDS_INVALID','Heures réelles et nouveau créneau ne s’appliquent pas à ce résultat.');
 if(value.targetStatus==='NO_SHOW'&&lesson.planned_end.getTime()>Date.now())throw conflict('LESSON_NOT_ENDED','Une absence se constate après la fin prévue du rendez-vous.');
}
function reauthenticate(identity:Identity,age:number){
 if(identity.authenticatedAt===undefined||Math.floor(Date.now()/1000)-identity.authenticatedAt>age)throw new ApiError(401,'REAUTH_REQUIRED','Reconnectez-vous pour exécuter la correction que vous avez approuvée.');
}

export function registerLessonOutcomes(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;reauthMaxAgeSeconds?:number}){
 const base='/v1/schools/:schoolId/lessons/:lessonId',age=z.number().int().min(30).max(900).parse(options.reauthMaxAgeSeconds??300);
 const params=(r:FastifyRequest)=>z.object({schoolId:id,lessonId:id}).parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 async function run<T>(r:FastifyRequest,type:string,body:{operationId:string},roles:string[],guards:(schoolId:string,lessonId:string)=>CommandGuards<T>,
  work:(db:PoolClient,actor:CommandActor,school:SchoolRow,lessonId:string,expected:number,identity:Identity)=>Promise<CommandEffect<T>>){
  empty.parse(r.query);const {schoolId,lessonId}=params(r),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const bound={...body,lessonId};
  return schoolCommand(options.pool,identity,schoolId,type,bound,expected,(db,actor,school)=>work(db,actor,school,lessonId,expected,identity),roles,guards(schoolId,lessonId));
 }

 // AP44 : absence constatée après la fin prévue, par l'administration ou le moniteur de la leçon. Aucune pénalité.
 app.post(`${base}/no-show`,async(r,reply)=>{
  const body=reasonCommand.parse(r.body);
  const data=await run<Lesson>(r,'MARK_NO_SHOW',body,['ADMIN','INSTRUCTOR'],(schoolId,lessonId)=>lessonCommandGuards(schoolId,{lessonId}),async(db,_actor,school,lessonId,expected)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);
   if(old.status!=='PLANNED')throw conflict('LESSON_CLOSED','Cette leçon possède déjà un résultat.');
   if(old.planned_end.getTime()>Date.now())throw conflict('LESSON_NOT_ENDED','Une absence se constate après la fin prévue du rendez-vous.');
   const row=(await db.query<LessonRow>(`UPDATE drivy.lesson SET status='NO_SHOW',version=version+1,no_show_reason=$3 WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,[school.id,lessonId,body.reason])).rows[0]!;
   await releaseFutureOccupations(db,school.id,lessonId);await openClosedAccount(db,row);await event(db,row,body.operationId,'LessonNoShow');
   return {data:lessonProjection(row),action:'LessonMarkedNoShow',resourceType:'Lesson',resourceId:lessonId,changedFields:['status'],reason:body.reason};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // AP88 : le moniteur affecté approuve le contenu exact d'une correction, sans l'exécuter.
 app.post(`${base}/outcome-approvals`,async(r,reply)=>{
  const body=approveCommand.parse(r.body);
  const data=await run<Approval>(r,'APPROVE_OUTCOME_CORRECTION',body,['INSTRUCTOR'],(schoolId,lessonId)=>authorGuards<Approval>(schoolId,lessonId,async(db,previous)=>{
   const row=(await db.query<ApprovalRow>('SELECT * FROM drivy.outcome_approval WHERE school_id=$1 AND id=$2',[schoolId,previous.id])).rows[0];if(!row)throw notFound();return approvalProjection(row);
  }),async(db,actor,school,lessonId,expected)=>{
   const lesson=await getLesson(db,school.id,lessonId,true);checkVersion(lesson.version,expected);
   if(body.expectedPublicationVersion!==lesson.publication_version)throw conflict('PUBLICATION_VERSION_CONFLICT','La publication a changé. Relisez la version courante.');
   validateTransition(lesson,body.proposal);
   const account=await lessonAccount(db,school.id,lessonId);
   if(!account)throw conflict('FINANCIAL_RECONCILIATION_REQUIRED','Le compte de cette leçon doit être rapproché avant une correction.');
   if(account.version!==body.proposal.expectedAccountVersion)throw conflict('ACCOUNT_VERSION_CONFLICT','Le compte de la leçon a changé. Relisez-le avant d’approuver.');
   const row=(await db.query<ApprovalRow>(`INSERT INTO drivy.outcome_approval(id,school_id,lesson_id,lesson_version,account_version,publication_version,proposal_hash,approved_by_membership_id,expires_at,operation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,statement_timestamp()+interval '10 minutes',$9) RETURNING *`,[randomUUID(),school.id,lessonId,lesson.version,account.version,lesson.publication_version,proposalHash(body.proposal),actor.membershipId,body.operationId])).rows[0]!;
   return {data:approvalProjection(row),action:'OutcomeCorrectionApproved',resourceType:'OutcomeApproval',resourceId:row.id,changedFields:['proposalHash'],reason:body.proposal.reason};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // AP50 : correction motivée réservée à l'administration ; approbation pédagogique si un bilan publié doit être retiré.
 app.post(`${base}/correct-outcome`,async(r,reply)=>{
  const body=correctCommand.parse(r.body);
  const data=await run<Lesson>(r,'CORRECT_OUTCOME',body,['ADMIN'],(schoolId,lessonId)=>lessonCommandGuards(schoolId,{lessonId}),async(db,actor,school,lessonId,expected,identity)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);
   validateTransition(old,body);
   const account=await lessonAccount(db,school.id,lessonId,true);
   if(!account)throw conflict('FINANCIAL_RECONCILIATION_REQUIRED','Le compte de cette leçon doit être rapproché avant une correction.');
   if(account.version!==body.expectedAccountVersion)throw conflict('ACCOUNT_VERSION_CONFLICT','Le compte de la leçon a changé. Relisez-le avant de corriger.');
   const published=old.current_published_revision_id!==null;
   if(published&&!body.pedagogicalApprovalId)throw conflict('PEDAGOGICAL_APPROVAL_REQUIRED','Le bilan publié doit être retiré avec l’approbation du moniteur affecté.');
   let approval:ApprovalRow|undefined;
   if(body.pedagogicalApprovalId){
    approval=(await db.query<ApprovalRow>(`SELECT a.*,m.person_id AS approver_person_id FROM drivy.outcome_approval a JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.approved_by_membership_id
     WHERE a.school_id=$1 AND a.id=$2 AND a.lesson_id=$3 FOR UPDATE OF a`,[school.id,body.pedagogicalApprovalId,lessonId])).rows[0];
    if(!approval||approval.consumed_at)throw conflict('APPROVAL_INVALID','Cette approbation n’est pas utilisable. Demandez une nouvelle approbation.');
    if(approval.expires_at.getTime()<=Date.now())throw conflict('APPROVAL_EXPIRED','L’approbation a expiré. Demandez une nouvelle approbation.');
    const current=(await db.query<{ok:boolean}>('SELECT drivy.outcome_approver_current($1,$2) AS ok',[lessonId,approval.approved_by_membership_id])).rows[0]?.ok;
    if(!current||approval.lesson_version!==old.version||approval.account_version!==account.version||approval.publication_version!==old.publication_version||approval.proposal_hash!==proposalHash(body))
     throw conflict('APPROVAL_INVALID','La proposition, les versions ou les droits ont changé depuis l’approbation. Demandez une nouvelle approbation.');
    // Un responsable qui cumule les deux habilitations confirme séparément, après réauthentification.
    if(approval.approver_person_id===actor.personId)reauthenticate(identity,age);
   }
   let publicationVersion=old.publication_version,revisionId:string|null=old.current_published_revision_id;
   if(published){
    const revision=(await db.query<{sequence:number|null}>('SELECT drivy.lesson_current_revision_sequence($1) AS sequence',[lessonId])).rows[0];
    if(!revision?.sequence)throw conflict('PUBLICATION_VERSION_CONFLICT','La publication courante doit être relue.');
    publicationVersion+=1;
    await db.query(`INSERT INTO drivy.report_publication_withdrawal(school_id,lesson_id,revision_id,revision_sequence,publication_version,reason,actor_membership_id,operation_id)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[school.id,lessonId,revisionId,revision.sequence,publicationVersion,body.reason,actor.membershipId,body.operationId]);
    revisionId=null;
   }
   // La charge de réalisation est contre-passée exactement ; aucun paiement n'existe encore dans ce pilote.
   const charged=BigInt((await db.query<{sum:string}>('SELECT coalesce(sum(amount_signed_cents),0)::text AS sum FROM drivy.charge_entry WHERE school_id=$1 AND account_id=$2',[school.id,account.id])).rows[0]!.sum);
   if(charged<0n)throw conflict('FINANCIAL_RECONCILIATION_REQUIRED','Le compte de la leçon doit être rapproché avant une correction.');
   if(charged>0n){
    await db.query(`INSERT INTO drivy.charge_entry(school_id,account_id,kind,amount_signed_cents,reason,operation_id) VALUES($1,$2,'REVERSAL',$3,$4,$5)`,[school.id,account.id,(-charged).toString(),body.reason,body.operationId]);
    await db.query('UPDATE drivy.lesson_account SET version=version+1 WHERE school_id=$1 AND id=$2',[school.id,account.id]);
   }
   if(approval)await db.query('UPDATE drivy.outcome_approval SET version=2,consumed_at=statement_timestamp(),consumed_operation_id=$3 WHERE school_id=$1 AND id=$2',[school.id,approval.id,body.operationId]);
   await db.query(`INSERT INTO drivy.lesson_outcome_correction(school_id,lesson_id,from_status,to_status,previous_actual_start,previous_actual_end,previous_revision_id,reason,approval_id,reversed_charge_cents,actor_membership_id,operation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,[school.id,lessonId,old.status,body.targetStatus,old.actual_start,old.actual_end,old.current_published_revision_id,body.reason,approval?.id??null,charged.toString(),actor.membershipId,body.operationId]);
   const cancelled=body.targetStatus==='CANCELLED';
   const row=(await db.query<LessonRow>(`UPDATE drivy.lesson SET status=$3,version=version+1,actual_start=NULL,actual_end=NULL,completion_anomaly_reason=NULL,
    publication_version=$4,current_published_revision_id=$5,cancel_reason_code=$6,cancel_comment=$7,no_show_reason=$8 WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,
    [school.id,lessonId,body.targetStatus,publicationVersion,revisionId,cancelled?'OTHER':null,cancelled?body.reason:null,cancelled?null:body.reason])).rows[0]!;
   await event(db,row,body.operationId,'LessonOutcomeCorrected');
   return {data:lessonProjection(row),action:'LessonOutcomeCorrected',resourceType:'Lesson',resourceId:lessonId,changedFields:['status',...(old.actual_start?['actualStart','actualEnd']:[]),...(published?['currentPublishedRevisionId']:[]),...(charged>0n?['account']:[])],reason:body.reason};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // AP57 : retrait du bilan publié par le moniteur désigné ; révisions conservées, progression recalculée par la vue.
 app.post(`${base}/report-publication/withdraw`,async r=>{
  const body=reasonCommand.parse(r.body);
  const data=await run(r,'WITHDRAW_REPORT_PUBLICATION',body,['INSTRUCTOR'],(schoolId,lessonId)=>authorGuards<{operationId:string;accepted:boolean}>(schoolId,lessonId,async(_db,previous)=>previous),async(db,actor,school,lessonId,expected)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);
   if(!old.current_published_revision_id)throw conflict('NO_PUBLISHED_REPORT','Aucun bilan n’est actuellement publié pour cette leçon.');
   const revision=(await db.query<{sequence:number|null}>('SELECT drivy.lesson_current_revision_sequence($1) AS sequence',[lessonId])).rows[0];
   if(!revision?.sequence)throw notFound();
   const publicationVersion=old.publication_version+1;
   await db.query(`INSERT INTO drivy.report_publication_withdrawal(school_id,lesson_id,revision_id,revision_sequence,publication_version,reason,actor_membership_id,operation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[school.id,lessonId,old.current_published_revision_id,revision.sequence,publicationVersion,body.reason,actor.membershipId,body.operationId]);
   const row=(await db.query<LessonRow>(`UPDATE drivy.lesson SET version=version+1,publication_version=$3,current_published_revision_id=NULL WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,[school.id,lessonId,publicationVersion])).rows[0]!;
   // Le brouillon de l'auteur suit la nouvelle version : une republication exige un motif de correction.
   await db.query('UPDATE drivy.report_draft SET version=version+1,base_publication_version=$3 WHERE school_id=$1 AND lesson_id=$2 AND author_membership_id=$4 AND base_publication_version=$5',[school.id,lessonId,publicationVersion,actor.membershipId,old.publication_version]);
   await event(db,row,body.operationId,'ReportPublicationWithdrawn');
   return {data:{operationId:body.operationId,accepted:true},action:'ReportPublicationWithdrawn',resourceType:'Lesson',resourceId:lessonId,resourceVersion:row.version,changedFields:['publicationVersion','currentPublishedRevisionId'],reason:body.reason};
  });
  return envelope(data,r);
 });
}

/** AP72 : preuve de commit selon les droits actuels, sans restituer le corps. */
export async function authorizeOutcomeOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type==='MARK_NO_SHOW'||type==='CORRECT_OUTCOME'){
  const lesson=await getLesson(db,schoolId,resourceId);
  if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_access($1,$2,true) AS ok',[lesson.training_id,lesson.instructor_membership_id])).rows[0]?.ok)throw notFound();return true;
 }
 if(type==='WITHDRAW_REPORT_PUBLICATION'){await author(db,resourceId);return true;}
 if(type==='APPROVE_OUTCOME_CORRECTION'){if(!(await db.query('SELECT id FROM drivy.outcome_approval WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rowCount)throw notFound();return true;}
 return false;
}
