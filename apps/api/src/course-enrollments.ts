import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {canManageCourses,getSeries} from './courses.js';

/**
 * Cours collectifs : inscriptions (#39), file prioritaire (#40), annulations et changements de dates (#41).
 * Les règles vivent dans les fonctions SQL de la migration 043 (verrou de série, compteur unique, exclusion d'agenda).
 * Ce module traduit les commandes, rend les erreurs stables et projette l'état personnel de l'élève.
 * Contrat : docs/implementation/cours-collectifs-inscriptions-39-41.md.
 */
const id=z.uuid(),empty=z.object({}).strict(),operation=z.object({operationId:id}).strict();
const staffEnroll=z.object({operationId:id,learnerId:id}).strict();
const staffCancel=z.object({operationId:id,reason:z.string().trim().min(1).max(1000)}).strict();
const reschedule=z.object({operationId:id,occurrences:z.array(z.object({position:z.number().int().min(1).max(64),startsAt:z.iso.datetime({offset:true}),endsAt:z.iso.datetime({offset:true}),
 instructorMembershipId:id}).strict()).min(1).max(64)}).strict();

const failures:Record<string,[number,string]>={
 NOT_FOUND:[404,'Objet introuvable dans le périmètre autorisé.'],
 INVALID_REQUEST:[400,'Requête invalide.'],
 COURSE_ACCESS_REQUIRED:[403,'Cette action demande un droit que ce compte n’a pas.'],
 LEARNER_NOT_ACTIVE:[409,'Le dossier de l’élève n’est pas actif dans cette école.'],
 COURSE_ALREADY_COMPLETED:[409,'Ce cours est déjà effectué.'],
 COURSE_ALREADY_ENROLLED:[409,'Déjà inscrit à ce cours.'],
 COURSE_EQUIVALENT_ENROLLED:[409,'Déjà inscrit à une autre session de ce cours.'],
 COURSE_NOT_OPEN:[409,'Ce cours n’accepte plus d’inscriptions.'],
 COURSE_STARTED:[409,'Ce cours a déjà commencé.'],
 COURSE_FULL:[409,'Ce cours est complet.'],
 COURSE_OFFER_EXPIRED:[409,'Cette place n’est plus disponible pour vous.'],
 COURSE_WAITLIST_DISABLED:[409,'La liste d’attente n’est pas ouverte dans cette école.'],
 COURSE_SEATS_AVAILABLE:[409,'Des places sont libres : inscrivez-vous directement.'],
 COURSE_ENROLLMENT_CLOSED:[409,'Cette inscription est déjà annulée.'],
 COURSE_SELF_CANCEL_CLOSED:[409,'Le délai d’annulation est passé. Contactez l’école.'],
 COURSE_REASON_REQUIRED:[422,'Indiquez le motif.'],
 COURSE_NOT_PUBLISHED:[409,'Ce cours n’est pas publié.'],
 COURSE_OCCURRENCE_COUNT:[422,'Indiquez chaque séance du cours, une seule fois.'],
 COURSE_IN_PAST:[422,'Une séance serait dans le passé.'],
 INSTRUCTOR_NOT_ACTIVE:[422,'Choisissez un moniteur actif de l’école.']
};
/** Traduit les refus SQL : P0001 (code métier), 23P01 (chevauchement d'agenda), 23514/22007 (horaires invalides). */
export function courseFailure(error:unknown,conflictMessage='Un autre rendez-vous occupe déjà ce créneau.'):never{
 if(typeof error==='object'&&error!==null&&'code'in error){
  if(error.code==='P0001'&&'message'in error&&typeof error.message==='string'){const known=failures[error.message];if(known)throw new ApiError(known[0],error.message,known[1]);}
  if(error.code==='23P01')throw new ApiError(409,'COURSE_SCHEDULE_CONFLICT',conflictMessage);
  if(error.code==='23514'||error.code==='22007'||error.code==='22008')throw new ApiError(422,'INVALID_INTERVAL','Chaque séance doit finir après son début, sans chevauchement.');
 }
 throw error;
}

export interface CourseEnrollmentView {id:string;seriesId:string;learnerId:string;version:number;status:'ACTIVE'|'CANCELLED';source:'SELF'|'STAFF'|'OFFER';
 policyVersion:number;selfCancelHours:number;selfCancelDeadline:string;canSelfCancel:boolean;createdAt:string;cancelledAt:string|null;cancelKind:string|null;cancelReason:string|null}
export interface CourseOfferView {id:string;seriesId:string;expiresAt:string;status:string}
/** État personnel de l'élève appelant pour une série : pas de liste nominative, pas de paiement. */
export interface CourseLearnerState {learnerId:string|null;state:'AVAILABLE'|'FULL'|'ENROLLED'|'WAITING'|'OFFERED'|'COMPLETED'|'CANCELLED'|'CLOSED';
 enrollment:CourseEnrollmentView|null;offer:CourseOfferView|null;waitlistPosition:number|null;waitlistEnabled:boolean;contactEmail:string|null}

interface EnrollmentRow {id:string;series_id:string;learner_id:string;version:number;status:'ACTIVE'|'CANCELLED';source:'SELF'|'STAFF'|'OFFER';policy_version:number;self_cancel_hours:number;
 self_cancel_deadline:Date;created_at:Date;cancelled_at:Date|null;cancel_kind:string|null;cancel_reason:string|null;learner_name?:string|null}
const enrollmentColumns='e.id,e.series_id,e.learner_id,e.version,e.status,e.source,e.policy_version,e.self_cancel_hours,e.self_cancel_deadline,e.created_at,e.cancelled_at,e.cancel_kind,e.cancel_reason';
function enrollmentView(row:EnrollmentRow,now=Date.now()):CourseEnrollmentView{
 return {id:row.id,seriesId:row.series_id,learnerId:row.learner_id,version:row.version,status:row.status,source:row.source,policyVersion:row.policy_version,selfCancelHours:row.self_cancel_hours,
  selfCancelDeadline:row.self_cancel_deadline.toISOString(),canSelfCancel:row.status==='ACTIVE'&&now<=row.self_cancel_deadline.getTime(),createdAt:row.created_at.toISOString(),
  cancelledAt:row.cancelled_at?.toISOString()??null,cancelKind:row.cancel_kind,cancelReason:row.cancel_reason};
}
async function ownLearner(db:PoolClient,schoolId:string,personId:string){
 return (await db.query<{id:string}>('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2 AND archived_at IS NULL',[schoolId,personId])).rows[0]?.id??null;
}
export async function learnerState(db:PoolClient,schoolId:string,seriesId:string,personId:string):Promise<CourseLearnerState>{
 const learnerId=await ownLearner(db,schoolId,personId);
 const series=(await db.query<{status:string;type_id:string;capacity:number;taken:number;first_start:Date|null;contact_email:string|null;waitlist:boolean}>(`SELECT s.status,s.type_id,s.capacity,
  drivy.course_seats_taken(s.id) AS taken,(SELECT min(starts_at) FROM drivy.course_occurrence o WHERE o.series_id=s.id) AS first_start,sc.contact_email,
  EXISTS(SELECT 1 FROM drivy.course_policy_version p WHERE p.school_id=s.school_id AND p.version=(SELECT max(version) FROM drivy.course_policy_version q WHERE q.school_id=s.school_id) AND p.offer_response_minutes IS NOT NULL) AS waitlist
  FROM drivy.course_series s JOIN drivy.school sc ON sc.id=s.school_id WHERE s.school_id=$1 AND s.id=$2`,[schoolId,seriesId])).rows[0];
 if(!series)throw notFound();
 const base={learnerId,enrollment:null,offer:null,waitlistPosition:null,waitlistEnabled:series.waitlist,contactEmail:series.contact_email};
 if(!learnerId)return {...base,state:'CLOSED'};
 const enrollment=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.series_id=$1 AND e.learner_id=$2 ORDER BY e.created_at DESC LIMIT 1`,[seriesId,learnerId])).rows[0];
 if(enrollment?.status==='ACTIVE')return {...base,state:'ENROLLED',enrollment:enrollmentView(enrollment)};
 const completed=(await db.query<{ok:boolean}>('SELECT drivy.course_type_completed($1,$2) AS ok',[learnerId,series.type_id])).rows[0]?.ok===true;
 if(completed)return {...base,state:'COMPLETED',enrollment:enrollment?enrollmentView(enrollment):null};
 const entry=(await db.query<{id:string;status:string;queued_at:Date;seq:string}>(`SELECT id,status,queued_at,seq FROM drivy.course_waitlist_entry WHERE series_id=$1 AND learner_id=$2 AND status IN('WAITING','OFFERED')`,[seriesId,learnerId])).rows[0];
 if(entry?.status==='OFFERED'){
  const offer=(await db.query<{id:string;expires_at:Date;status:string}>(`SELECT id,expires_at,status FROM drivy.course_seat_offer WHERE entry_id=$1 AND status='ACTIVE' AND expires_at>statement_timestamp()`,[entry.id])).rows[0];
  if(offer)return {...base,state:'OFFERED',offer:{id:offer.id,seriesId,expiresAt:offer.expires_at.toISOString(),status:offer.status}};
 }
 if(entry){
  // Rang seulement : aucun nom ni nombre de personnes devant ou derrière n'est exposé au-delà de ce rang.
  const rank=(await db.query<{n:number}>('SELECT drivy.course_waitlist_rank($1) AS n',[entry.id])).rows[0]!.n;
  return {...base,state:'WAITING',waitlistPosition:rank};
 }
 const closed=series.status!=='PUBLISHED'||!series.first_start||series.first_start.getTime()<=Date.now();
 if(closed)return {...base,state:enrollment?'CANCELLED':'CLOSED',enrollment:enrollment?enrollmentView(enrollment):null};
 return {...base,state:series.taken>=series.capacity?'FULL':(enrollment?'CANCELLED':'AVAILABLE'),enrollment:enrollment?enrollmentView(enrollment):null};
}

export function registerCourseEnrollments(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId',params=(r:FastifyRequest)=>z.object({schoolId:id}).passthrough().parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const seriesParam=(r:FastifyRequest)=>z.object({seriesId:id}).passthrough().parse(r.params).seriesId;
 const run=async<T>(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,expected:number|null,roles:string[],
  work:(db:PoolClient,actor:CommandActor)=>Promise<CommandEffect<T>>,replay:(db:PoolClient,actor:CommandActor,previous:T)=>Promise<T>,conflict?:string)=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  try{return await schoolCommand<T>(options.pool,identity,schoolId,type,body,expected,async(db,actor)=>{
   try{await db.query('SAVEPOINT course_command');const effect=await work(db,actor);await db.query('RELEASE SAVEPOINT course_command');return effect;}
   catch(error){await db.query('ROLLBACK TO SAVEPOINT course_command');throw error;}
  },roles,{replay});}
  catch(error){return courseFailure(error,conflict);}
 };
 const learnerReply=async(db:PoolClient,schoolId:string,seriesId:string,personId:string)=>({series:await getSeries(db,schoolId,seriesId),me:await learnerState(db,schoolId,seriesId,personId)});

 // Lecture personnelle : état de l'élève appelant pour une série (Disponible, Complet, Inscrit, En attente, Place proposée,
 // Déjà effectué, Annulé). La lecture fait d'abord avancer la file : une proposition due est visible sans push.
 app.get(`${base}/course-series/:seriesId/me`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),seriesId=seriesParam(r),identity=await options.verifyToken(r.headers.authorization);
  const data=await options.pool.connect().then(async db=>{try{
   // Avance de file en écriture courte et séparée, puis lecture cohérente.
   await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_app');
   await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true)",[identity.issuer,identity.subject,schoolId]);
   const person=(await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[identity.issuer,identity.subject])).rows[0]?.person_id;
   if(person){await db.query("SELECT set_config('app.person_id',$1,true)",[person]);await db.query('SELECT drivy.course_queue_advance($1)',[seriesId]);}
   await db.query('COMMIT');
  }catch(error){await db.query('ROLLBACK').catch(()=>undefined);throw error;}finally{db.release();}})
   .then(()=>withActor(options.pool,identity,schoolId,async(db,actor,member)=>{if(!member)throw forbidden();return learnerReply(db,schoolId,seriesId,actor.personId);}));
  return envelope(data,r);
 });
 // Inscriptions et propositions de l'élève appelant dans l'école (agenda personnel).
 app.get(`${base}/course-enrollments/me`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   if(!member)throw forbidden();const learnerId=await ownLearner(db,schoolId,actor.personId);
   if(!learnerId)return {items:[],offers:[]};
   const items=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.school_id=$1 AND e.learner_id=$2 ORDER BY e.created_at DESC LIMIT 200`,[schoolId,learnerId])).rows.map(row=>enrollmentView(row));
   const offers=(await db.query<{id:string;series_id:string;expires_at:Date;status:string}>(`SELECT o.id,o.series_id,o.expires_at,o.status FROM drivy.course_seat_offer o JOIN drivy.course_waitlist_entry w ON w.id=o.entry_id
    WHERE w.learner_id=$1 AND o.status='ACTIVE' AND o.expires_at>statement_timestamp() ORDER BY o.expires_at`,[learnerId])).rows.map(o=>({id:o.id,seriesId:o.series_id,expiresAt:o.expires_at.toISOString(),status:o.status}));
   return {items,offers};
  }),r);
 });
 // Liste du personnel : nominative, réservée à la gestion des cours ; jamais exposée à un élève.
 app.get(`${base}/course-series/:seriesId/enrollments`,async r=>{
  empty.parse(r.query);const {schoolId}=params(r),seriesId=seriesParam(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,_a,member)=>{
   if(!member||!(await canManageCourses(db,schoolId)))throw new ApiError(403,'COURSE_ACCESS_REQUIRED','La gestion des cours demande le droit correspondant.');
   await getSeries(db,schoolId,seriesId);
   const rows=(await db.query<EnrollmentRow&{learner_name:string|null}>(`SELECT ${enrollmentColumns},p.display_name AS learner_name FROM drivy.course_enrollment e
    JOIN drivy.learner_profile l ON l.id=e.learner_id LEFT JOIN drivy.person p ON p.id=l.person_id WHERE e.series_id=$1 ORDER BY e.status,e.created_at`,[seriesId])).rows;
   const waiting=(await db.query<{id:string;learner_id:string;status:string;queued_at:Date;learner_name:string|null;expires_at:Date|null}>(`SELECT w.id,w.learner_id,w.status,w.queued_at,p.display_name AS learner_name,
    (SELECT o.expires_at FROM drivy.course_seat_offer o WHERE o.entry_id=w.id AND o.status='ACTIVE') AS expires_at
    FROM drivy.course_waitlist_entry w JOIN drivy.learner_profile l ON l.id=w.learner_id LEFT JOIN drivy.person p ON p.id=l.person_id
    WHERE w.series_id=$1 AND w.status IN('WAITING','OFFERED') ORDER BY w.queued_at,w.seq`,[seriesId])).rows;
   return {items:rows.map(row=>({...enrollmentView(row),learnerDisplayName:row.learner_name??''})),
    waitlist:waiting.map((w,index)=>({id:w.id,learnerId:w.learner_id,learnerDisplayName:w.learner_name??'',position:index+1,status:w.status,queuedAt:w.queued_at.toISOString(),offerExpiresAt:w.expires_at?.toISOString()??null}))};
  }),r);
 });

 // #39 : l'élève s'inscrit à toute la série.
 app.post(`${base}/course-series/:seriesId/enroll`,{bodyLimit:1_024},async(r,reply)=>{
  const body=operation.parse(r.body),{schoolId}=params(r),seriesId=seriesParam(r);
  const data=await run(r,'ENROLL_COURSE',{...body,seriesId},null,['LEARNER'],async(db,actor)=>{
   const learnerId=await ownLearner(db,schoolId,actor.personId);if(!learnerId)throw new ApiError(403,'COURSE_ACCESS_REQUIRED','Ce compte n’a pas de dossier élève dans cette école.');
   const enrollment=(await db.query<{id:string}>('SELECT drivy.course_enroll($1,$2,$3) AS id',[seriesId,learnerId,'SELF'])).rows[0]!.id;
   return {data:await learnerReply(db,schoolId,seriesId,actor.personId),action:'CourseEnrolled',resourceType:'CourseEnrollment',resourceId:enrollment,resourceVersion:1,changedFields:['enrollment']};
  },async(db,actor)=>learnerReply(db,schoolId,seriesId,actor.personId),'Vous avez déjà un rendez-vous pendant une séance de ce cours.');
  reply.code(201);return envelope(data,r);
 });
 // #39 : inscription par le personnel habilité, à la demande de l'élève ; mêmes contrôles, origine STAFF tracée.
 app.post(`${base}/course-series/:seriesId/enrollments`,{bodyLimit:1_024},async(r,reply)=>{
  const body=staffEnroll.parse(r.body),seriesId=seriesParam(r);
  const data=await run(r,'STAFF_ENROLL_COURSE',{...body,seriesId},null,['ADMIN','INSTRUCTOR'],async db=>{
   const enrollment=(await db.query<{id:string}>('SELECT drivy.course_enroll($1,$2,$3) AS id',[seriesId,body.learnerId,'STAFF'])).rows[0]!.id;
   const row=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1`,[enrollment])).rows[0]!;
   return {data:enrollmentView(row),action:'CourseEnrolledByStaff',resourceType:'CourseEnrollment',resourceId:enrollment,resourceVersion:1,changedFields:['enrollment']};
  },async(db,_a,previous)=>{const row=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1`,[previous.id])).rows[0];return row?enrollmentView(row):previous;},
  'L’élève a déjà un rendez-vous pendant une séance de ce cours.');
  reply.code(201);return envelope(data,r);
 });

 // #40 : file prioritaire.
 app.post(`${base}/course-series/:seriesId/waitlist`,{bodyLimit:1_024},async(r,reply)=>{
  const body=operation.parse(r.body),{schoolId}=params(r),seriesId=seriesParam(r);
  const data=await run(r,'JOIN_COURSE_WAITLIST',{...body,seriesId},null,['LEARNER'],async(db,actor)=>{
   const learnerId=await ownLearner(db,schoolId,actor.personId);if(!learnerId)throw new ApiError(403,'COURSE_ACCESS_REQUIRED','Ce compte n’a pas de dossier élève dans cette école.');
   const entry=(await db.query<{id:string}>('SELECT drivy.course_join_waitlist($1,$2) AS id',[seriesId,learnerId])).rows[0]!.id;
   return {data:await learnerReply(db,schoolId,seriesId,actor.personId),action:'CourseWaitlistJoined',resourceType:'CourseWaitlistEntry',resourceId:entry,resourceVersion:1,changedFields:['waitlist']};
  },async(db,actor)=>learnerReply(db,schoolId,seriesId,actor.personId));
  reply.code(201);return envelope(data,r);
 });
 app.post(`${base}/course-series/:seriesId/waitlist/leave`,{bodyLimit:1_024},async r=>{
  const body=operation.parse(r.body),{schoolId}=params(r),seriesId=seriesParam(r);
  return envelope(await run(r,'LEAVE_COURSE_WAITLIST',{...body,seriesId},null,['LEARNER'],async(db,actor)=>{
   const learnerId=await ownLearner(db,schoolId,actor.personId);if(!learnerId)throw notFound();
   await db.query('SELECT drivy.course_leave_waitlist($1,$2)',[seriesId,learnerId]);
   return {data:await learnerReply(db,schoolId,seriesId,actor.personId),action:'CourseWaitlistLeft',resourceType:'CourseSeries',resourceId:seriesId,resourceVersion:1,changedFields:['waitlist']};
  },async(db,actor)=>learnerReply(db,schoolId,seriesId,actor.personId)),r);
 });
 app.post(`${base}/course-offers/:offerId/accept`,{bodyLimit:1_024},async(r,reply)=>{
  const body=operation.parse(r.body),{schoolId}=params(r),offerId=z.object({offerId:id}).passthrough().parse(r.params).offerId;
  let seriesId='';
  const data=await run(r,'ACCEPT_COURSE_OFFER',{...body,offerId},null,['LEARNER'],async(db,actor)=>{
   const enrollment=(await db.query<{id:string}>('SELECT drivy.course_accept_offer($1) AS id',[offerId])).rows[0]!.id;
   seriesId=(await db.query<{series_id:string}>('SELECT series_id FROM drivy.course_enrollment WHERE id=$1',[enrollment])).rows[0]!.series_id;
   return {data:await learnerReply(db,schoolId,seriesId,actor.personId),action:'CourseOfferAccepted',resourceType:'CourseEnrollment',resourceId:enrollment,resourceVersion:1,changedFields:['enrollment']};
  },async(db,actor,previous)=>learnerReply(db,schoolId,previous.series.id,actor.personId),'Vous avez déjà un rendez-vous pendant une séance de ce cours.');
  reply.code(201);return envelope(data,r);
 });
 app.post(`${base}/course-offers/:offerId/decline`,{bodyLimit:1_024},async r=>{
  const body=operation.parse(r.body),{schoolId}=params(r),offerId=z.object({offerId:id}).passthrough().parse(r.params).offerId;
  return envelope(await run(r,'DECLINE_COURSE_OFFER',{...body,offerId},null,['LEARNER'],async(db,actor)=>{
   const seriesId=(await db.query<{series_id:string}>('SELECT series_id FROM drivy.course_seat_offer WHERE id=$1',[offerId])).rows[0]?.series_id;if(!seriesId)throw notFound();
   await db.query('SELECT drivy.course_decline_offer($1)',[offerId]);
   return {data:await learnerReply(db,schoolId,seriesId,actor.personId),action:'CourseOfferDeclined',resourceType:'CourseSeatOffer',resourceId:offerId,resourceVersion:1,changedFields:['offer']};
  },async(db,actor,previous)=>learnerReply(db,schoolId,previous.series.id,actor.personId)),r);
 });

 // #41 : annulation autonome jusqu'à l'échéance acceptée (heure serveur), puis seulement par le personnel habilité avec motif.
 app.post(`${base}/course-enrollments/:enrollmentId/cancel`,{bodyLimit:1_024},async r=>{
  const body=operation.parse(r.body),{schoolId}=params(r),enrollmentId=z.object({enrollmentId:id}).passthrough().parse(r.params).enrollmentId,expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'CANCEL_COURSE_ENROLLMENT',{...body,enrollmentId},expected,['LEARNER'],async(db,actor)=>{
   const row=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1 AND e.school_id=$2`,[enrollmentId,schoolId])).rows[0];
   if(!row)throw notFound();checkVersion(row.version,expected);
   await db.query('SELECT drivy.course_cancel_enrollment($1,$2,NULL)',[enrollmentId,'SELF']);
   return {data:await learnerReply(db,schoolId,row.series_id,actor.personId),action:'CourseEnrollmentCancelled',resourceType:'CourseEnrollment',resourceId:enrollmentId,resourceVersion:row.version+1,changedFields:['status']};
  },async(db,actor,previous)=>learnerReply(db,schoolId,previous.series.id,actor.personId)),r);
 });
 app.post(`${base}/course-enrollments/:enrollmentId/staff-cancel`,{bodyLimit:2_048},async r=>{
  const body=staffCancel.parse(r.body),{schoolId}=params(r),enrollmentId=z.object({enrollmentId:id}).passthrough().parse(r.params).enrollmentId,expected=requireVersion(r.headers['if-match']);
  return envelope(await run(r,'STAFF_CANCEL_COURSE_ENROLLMENT',{...body,enrollmentId},expected,['ADMIN','INSTRUCTOR'],async db=>{
   const row=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1 AND e.school_id=$2`,[enrollmentId,schoolId])).rows[0];
   if(!row)throw notFound();checkVersion(row.version,expected);
   await db.query('SELECT drivy.course_cancel_enrollment($1,$2,$3)',[enrollmentId,'STAFF',body.reason]);
   const after=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1`,[enrollmentId])).rows[0]!;
   return {data:enrollmentView(after),action:'CourseEnrollmentCancelledByStaff',resourceType:'CourseEnrollment',resourceId:enrollmentId,resourceVersion:after.version,changedFields:['status'],reason:body.reason};
  },async(db,_a,previous)=>{const row=(await db.query<EnrollmentRow>(`SELECT ${enrollmentColumns} FROM drivy.course_enrollment e WHERE e.id=$1`,[previous.id])).rows[0];return row?enrollmentView(row):previous;}),r);
 });
 // #41 : annulation de la série et changement de dates par l'école.
 app.post(`${base}/course-series/:seriesId/cancel`,{bodyLimit:2_048},async(r,reply)=>{
  const body=staffCancel.parse(r.body),{schoolId}=params(r),seriesId=seriesParam(r),expected=requireVersion(r.headers['if-match']);
  const data=await run(r,'CANCEL_COURSE_SERIES',{...body,seriesId},expected,['ADMIN','INSTRUCTOR'],async db=>{
   const old=await getSeries(db,schoolId,seriesId);checkVersion(old.version,expected);
   await db.query('SELECT drivy.course_cancel_series($1,$2)',[seriesId,body.reason]);
   return {data:await getSeries(db,schoolId,seriesId),action:'CourseSeriesCancelled',resourceType:'CourseSeries',resourceId:seriesId,changedFields:['status'],reason:body.reason};
  },async db=>getSeries(db,schoolId,seriesId));
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/course-series/:seriesId/reschedule`,{bodyLimit:32_000},async(r,reply)=>{
  const body=reschedule.parse(r.body),{schoolId}=params(r),seriesId=seriesParam(r),expected=requireVersion(r.headers['if-match']);
  const data=await run(r,'RESCHEDULE_COURSE_SERIES',{...body,seriesId},expected,['ADMIN','INSTRUCTOR'],async db=>{
   const old=await getSeries(db,schoolId,seriesId);checkVersion(old.version,expected);
   await db.query('SELECT drivy.course_reschedule($1,$2::jsonb)',[seriesId,JSON.stringify(body.occurrences)]);
   return {data:await getSeries(db,schoolId,seriesId),action:'CourseSeriesRescheduled',resourceType:'CourseSeries',resourceId:seriesId,changedFields:['occurrences']};
  },async db=>getSeries(db,schoolId,seriesId),'Un moniteur ou un élève inscrit a déjà un rendez-vous sur ces nouvelles dates. Rien n’a été modifié.');
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}
