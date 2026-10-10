import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {schoolCommand,checkIdempotency,checkVersion,requireVersion,schoolColumns,schoolProjection,type SchoolRow} from './commands.js';
import {ApiError,notFound} from './errors.js';
import {assignmentColumns,member} from './catalogue.js';
import {getLearner,getTraining} from './queries.js';
import {recordSettings} from './school-setup.js';
import {reauthAge,reauthenticate} from './reauth.js';

/**
 * Extensions hors canon OpenAPI 3.11.0 : retrait d'accès, cycle de vie des formations, archivage des dossiers et module GPS.
 * Toutes sont réservées à l'ADMIN, versionnées (If-Match), idempotentes (operationId = Idempotency-Key), auditées et rejouables
 * par AP72. Le détail des contrats est dans docs/implementation/corrections-api-2026-09-29.md.
 */
const id=z.uuid(),empty=z.object({}).strict(),operation={operationId:id};
const reason=z.string().trim().min(1).max(1000);
const deactivateBody=z.object({...operation,reason}).strict();
const endAssignmentBody=z.object({...operation,reason:reason.nullable().optional()}).strict();
const archiveBody=z.object({...operation,reason}).strict();
const transitionBody=z.object({...operation,targetStatus:z.enum(['ACTIVE','PAUSED','COMPLETED','CANCELLED']),reason}).strict();
const modulesBody=z.object({...operation,gpsEnabled:z.boolean()}).strict();
type TrainingStatus='ACTIVE'|'PAUSED'|'COMPLETED'|'CANCELLED';
/** Une formation terminée ou annulée ne rouvre que vers ACTIVE ; la pause est réversible ; on ne passe pas d'un état final à l'autre. */
const transitions:Record<TrainingStatus,TrainingStatus[]>={ACTIVE:['PAUSED','COMPLETED','CANCELLED'],PAUSED:['ACTIVE','COMPLETED','CANCELLED'],COMPLETED:['ACTIVE'],CANCELLED:['ACTIVE']};

export function registerAdministration(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;reauthMaxAgeSeconds?:number}){
 const base='/v1/schools/:schoolId',age=reauthAge(options.reauthMaxAgeSeconds);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const params=(r:FastifyRequest)=>z.object({schoolId:id,membershipId:id.optional(),trainingId:id.optional(),assignmentId:id.optional(),learnerId:id.optional()}).parse(r.params);
 // Le dossier et la formation sont relus avec les droits d'un ADMIN : les projections canoniques de queries.ts ne dépendent que du rôle.
 const adminScope=(actor:{personId:string;membershipId:string;roles:string[]})=>({
  actor:{personId:actor.personId,displayName:'',locale:'',version:1},member:{id:actor.membershipId,roles:actor.roles,grants:[] as string[],accessEpoch:1}});
 const plannedLessons=async(db:PoolClient,schoolId:string,filter:string,values:unknown[])=>
  (await db.query<{n:number}>(`SELECT count(*)::int AS n FROM drivy.lesson WHERE school_id=$1 AND status='PLANNED' AND ${filter}`,[schoolId,...values])).rows[0]!.n;

 // Retrait d'accès : l'appartenance passe à REVOKED (access_epoch+1), ses affectations de moniteur prennent fin, jamais le dernier ADMIN.
 // Toutes les leçons sans résultat restent planifiées : leur nombre est rendu pour que l'école les traite (l'ADMIN y conserve l'accès).
 app.post(`${base}/members/:membershipId/deactivate`,async(r,reply)=>{
  empty.parse(r.query);const body=deactivateBody.parse(r.body),{schoolId,membershipId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);reauthenticate(identity,age);
  const command={...body,membershipId:membershipId!};
  const data=await schoolCommand(options.pool,identity,schoolId,'DEACTIVATE_MEMBER',command,expected,async(db,actor)=>{
   const old=await member(db,schoolId,membershipId!);checkVersion(old.version,expected);
   if(old.status==='REVOKED')throw new ApiError(409,'MEMBER_ALREADY_DEACTIVATED','Cet accès est déjà retiré.');
   const roles=old.roles as string[],personId=old.personId as string;
   if(roles.includes('ADMIN')&&(await db.query("SELECT m.id FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=$1 AND m.id<>$2 AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)",[schoolId,membershipId])).rowCount===0)
    throw new ApiError(409,'LAST_ADMIN','Conservez au moins un administrateur actif.');
   if(membershipId===actor.membershipId)throw new ApiError(409,'CANNOT_DEACTIVATE_SELF','Un autre administrateur doit retirer votre accès.');
   const ended=await db.query(`UPDATE drivy.instructor_assignment SET valid_until=greatest(statement_timestamp(),valid_from),version=version+1
    WHERE school_id=$1 AND instructor_membership_id=$2 AND (valid_until IS NULL OR (valid_until>statement_timestamp() AND valid_until>valid_from))`,[schoolId,membershipId]);
   const changed=await db.query("UPDATE drivy.membership SET status='REVOKED',version=version+1,access_epoch=access_epoch+1 WHERE school_id=$1 AND id=$2 AND status='ACTIVE' AND version=$3",[schoolId,membershipId,expected]);
   if(changed.rowCount!==1)throw new ApiError(412,'VERSION_CONFLICT','Cette configuration a changé. Rechargez-la avant de confirmer.');
   const planned=await plannedLessons(db,schoolId,'(instructor_membership_id=$2 OR learner_person_id=$3)',[membershipId,personId]);
   return {data:{...await member(db,schoolId,membershipId!),endedAssignmentCount:ended.rowCount??0,plannedLessonCount:planned},resourceType:'Member',resourceId:membershipId!,action:'MembershipDeactivated',
    reason:body.reason,changedFields:['status','accessEpoch','assignments']};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Fin d'une affectation : valid_until = maintenant ; une affectation future reçoit un intervalle vide et ne donnera jamais accès.
 app.post(`${base}/trainings/:trainingId/assignments/:assignmentId/end`,async(r,reply)=>{
  empty.parse(r.query);const body=endAssignmentBody.parse(r.body),{schoolId,trainingId,assignmentId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);
  const command={...body,trainingId:trainingId!,assignmentId:assignmentId!};
  const data=await schoolCommand(options.pool,identity,schoolId,'END_ASSIGNMENT',command,expected,async(db)=>{
   const old=(await db.query<{version:number;instructor_membership_id:string;ended:boolean}>(`SELECT version,instructor_membership_id,(valid_until IS NOT NULL AND (valid_until<=statement_timestamp() OR valid_until<=valid_from)) AS ended
    FROM drivy.instructor_assignment WHERE school_id=$1 AND training_id=$2 AND id=$3`,[schoolId,trainingId,assignmentId])).rows[0];
   if(!old)throw notFound();checkVersion(old.version,expected);
   if(old.ended)throw new ApiError(409,'ASSIGNMENT_ALREADY_ENDED','Cette affectation est déjà terminée.');
   const row=(await db.query<Record<string,unknown>&{version:number}>(`UPDATE drivy.instructor_assignment SET valid_until=greatest(statement_timestamp(),valid_from),version=version+1
    WHERE school_id=$1 AND id=$2 RETURNING ${assignmentColumns}`,[schoolId,assignmentId])).rows[0]!;
   // Comme à la création d'une affectation : l'époque d'accès du moniteur change (les curseurs de ses listes sont invalidés).
   await db.query("UPDATE drivy.membership SET version=version+1,access_epoch=access_epoch+1 WHERE school_id=$1 AND id=$2 AND status='ACTIVE'",[schoolId,old.instructor_membership_id]);
   const planned=await plannedLessons(db,schoolId,'training_id=$2 AND instructor_membership_id=$3',[trainingId,old.instructor_membership_id]);
   return {data:{...row,plannedLessonCount:planned},resourceType:'Assignment',resourceId:assignmentId!,action:'AssignmentEnded',changedFields:['validUntil'],...(body.reason?{reason:body.reason}:{})};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Archivage d'un dossier : plus de nouvelle formation ni de nouvelle leçon ; l'historique reste lisible. Les formations doivent être closes.
 app.post(`${base}/learners/:learnerId/archive`,async(r,reply)=>{
  empty.parse(r.query);const body=archiveBody.parse(r.body),{schoolId,learnerId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);
  const command={...body,learnerId:learnerId!};
  const data=await schoolCommand(options.pool,identity,schoolId,'ARCHIVE_LEARNER',command,expected,async(db,actor)=>{
   const old=(await db.query<{version:number;archived_at:Date|null}>('SELECT version,archived_at FROM drivy.learner_profile WHERE school_id=$1 AND id=$2',[schoolId,learnerId])).rows[0];
   if(!old)throw notFound();checkVersion(old.version,expected);
   if(old.archived_at)throw new ApiError(409,'LEARNER_ALREADY_ARCHIVED','Ce dossier est déjà archivé.');
   if((await db.query("SELECT id FROM drivy.training WHERE school_id=$1 AND learner_id=$2 AND status IN('ACTIVE','PAUSED') LIMIT 1",[schoolId,learnerId])).rowCount)
    throw new ApiError(409,'LEARNER_HAS_OPEN_TRAININGS','Terminez ou annulez les formations de cet élève avant d’archiver son dossier.');
   await db.query('UPDATE drivy.learner_profile SET archived_at=now(),version=version+1 WHERE school_id=$1 AND id=$2',[schoolId,learnerId]);
   const scope=adminScope(actor);
   return {data:await getLearner(db,schoolId,scope.actor,scope.member,learnerId!),resourceType:'Learner',resourceId:learnerId!,action:'LearnerArchived',reason:body.reason,changedFields:['archivedAt']};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Restauration du dossier : conserve ses formations et ne réactive pas une appartenance révoquée.
 app.post(`${base}/learners/:learnerId/restore`,async(r,reply)=>{
  empty.parse(r.query);const body=archiveBody.parse(r.body),{schoolId,learnerId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);
  const command={...body,learnerId:learnerId!};
  const data=await schoolCommand(options.pool,identity,schoolId,'RESTORE_LEARNER',command,expected,async(db,actor)=>{
   const old=(await db.query<{version:number;archived_at:Date|null}>('SELECT version,archived_at FROM drivy.learner_profile WHERE school_id=$1 AND id=$2',[schoolId,learnerId])).rows[0];
   if(!old)throw notFound();checkVersion(old.version,expected);
   if(!old.archived_at)throw new ApiError(409,'LEARNER_NOT_ARCHIVED','Ce dossier est déjà actif.');
   await db.query('UPDATE drivy.learner_profile SET archived_at=NULL,version=version+1 WHERE school_id=$1 AND id=$2',[schoolId,learnerId]);
   const scope=adminScope(actor);
   return {data:await getLearner(db,schoolId,scope.actor,scope.member,learnerId!),resourceType:'Learner',resourceId:learnerId!,action:'LearnerRestored',reason:body.reason,changedFields:['archivedAt']};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Une formation ne se clôt pas tant qu'une leçon attend un résultat, même après son créneau prévu.
 app.post(`${base}/trainings/:trainingId/transition`,async(r,reply)=>{
  empty.parse(r.query);const body=transitionBody.parse(r.body),{schoolId,trainingId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);
  const command={...body,trainingId:trainingId!};
  const data=await schoolCommand(options.pool,identity,schoolId,'TRANSITION_TRAINING',command,expected,async(db,actor,school)=>{
   const old=(await db.query<{version:number;status:TrainingStatus;learner_id:string;offering_key:string;archived_at:Date|null}>(`SELECT t.version,t.status,t.learner_id,t.offering_key,l.archived_at
    FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id WHERE t.school_id=$1 AND t.id=$2 FOR UPDATE OF t`,[schoolId,trainingId])).rows[0];
   if(!old)throw notFound();checkVersion(old.version,expected);
   if(old.status===body.targetStatus)throw new ApiError(409,'TRAINING_STATUS_UNCHANGED','La formation est déjà dans cet état.');
   if(!transitions[old.status].includes(body.targetStatus))throw new ApiError(409,'TRAINING_TRANSITION_INVALID','Cette formation ne peut pas passer à cet état.');
   const terminal=body.targetStatus==='COMPLETED'||body.targetStatus==='CANCELLED';
   const planned=await plannedLessons(db,schoolId,'training_id=$2',[trainingId]);
   if(terminal&&planned>0)throw new ApiError(409,'TRAINING_HAS_PLANNED_LESSONS','Annulez ou terminez les leçons planifiées de cette formation avant de la clore.');
   if(old.status!=='PAUSED'&&body.targetStatus==='ACTIVE'){
    if(old.archived_at)throw new ApiError(409,'LEARNER_ARCHIVED','Ce dossier est archivé.');
    if((await db.query("SELECT id FROM drivy.training WHERE school_id=$1 AND learner_id=$2 AND offering_key=$3 AND id<>$4 AND status IN('ACTIVE','PAUSED')",[schoolId,old.learner_id,old.offering_key,trainingId])).rowCount)
     throw new ApiError(409,'ACTIVE_TRAINING_EXISTS','Une formation de cette offre est déjà active ou en pause.');
   }
   await db.query(`UPDATE drivy.training t SET status=$3::text,version=t.version+1,
    closed_on=CASE WHEN $3::text IN('COMPLETED','CANCELLED') THEN greatest(coalesce(t.started_on,x.today),x.today) END
    FROM (SELECT (now() AT TIME ZONE $4::text)::date AS today) x WHERE t.school_id=$1 AND t.id=$2`,[schoolId,trainingId,body.targetStatus,school.timeZone]);
   const scope=adminScope(actor);
   return {data:{...await getTraining(db,schoolId,scope.actor,scope.member,trainingId!),plannedLessonCount:planned},resourceType:'Training',resourceId:trainingId!,action:'TrainingStatusChanged',reason:body.reason,changedFields:['status','closedOn']};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Module GPS de l'école : les autres modules ne changent pas. Réauthentification exigée comme pour les autres changements d'accès.
 app.put(`${base}/modules`,async(r,reply)=>{
  empty.parse(r.query);const body=modulesBody.parse(r.body),{schoolId}=params(r);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const expected=requireVersion(r.headers['if-match']),identity=await options.verifyToken(r.headers.authorization);reauthenticate(identity,age);
  const data=await schoolCommand(options.pool,identity,schoolId,'UPDATE_SCHOOL_MODULES',body,expected,async(db,actor,school)=>{
   checkVersion(school.version,expected);
   if(school.modules.gpsEnabled===body.gpsEnabled)throw new ApiError(409,'MODULE_UNCHANGED','Ce module est déjà dans cet état.');
   const result=await db.query<SchoolRow>(`UPDATE drivy.school SET modules=jsonb_set(modules,'{gpsEnabled}',to_jsonb($2::boolean)),version=version+1,configuration_version=configuration_version+1
    WHERE id=$1 RETURNING ${schoolColumns}`,[schoolId,body.gpsEnabled]);
   const current=result.rows[0]!;await recordSettings(db,current,actor.membershipId);
   return {data:schoolProjection(current),resourceType:'School',resourceId:schoolId,action:'SchoolModulesUpdated',changedFields:['modules.gpsEnabled']};
  });
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}
