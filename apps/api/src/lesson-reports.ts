import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {schoolCommand,checkIdempotency,checkVersion,requireVersion,type CommandGuards,type CommandEffect,type CommandActor,type SchoolRow} from './commands.js';
import {ApiError,notFound} from './errors.js';
import {Cursors} from './cursor.js';
import {getLesson,lessonProjection,type LessonRow} from './lessons.js';
import {attachLiveObservations,draftObservationIDs} from './capture-observations.js';

const id=z.uuid(),empty=z.object({}).strict(),date=z.iso.datetime({offset:true});
const text=(max:number)=>z.string().refine(value=>[...value].length<=max,`Le texte dépasse ${max} caractères.`);
const goal=z.object({label:text(500).refine(v=>v.trim().length>0),competencyId:id.nullable().optional(),context:text(500).optional()}).strict();
const waypoint=z.object({id,label:text(120).refine(v=>v.trim().length>0),latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),note:text(500).nullable()}).strict();
const observation=z.object({competencyId:id,level:z.enum(['DISCOVERING','GUIDED','INDEPENDENT']),context:text(500).refine(v=>v.trim().length>0)}).strict();
const unique=(values:string[])=>new Set(values).size===values.length;
const observations=z.array(observation).max(100).refine(values=>unique(values.map(v=>v.competencyId)),'Une seule observation par compétence.');
const preparationCommand=z.object({operationId:id,goals:z.array(goal).max(3),administrativeCheckNote:text(4000).nullable().optional(),plannedWaypoints:z.array(waypoint).max(20).refine(v=>unique(v.map(w=>w.id))).optional()}).strict();
const wishCommand=z.object({operationId:id,text:text(500),lessonId:id.nullable().optional()}).strict();
const completeCommand=z.object({operationId:id,actualStart:date,actualEnd:date,workedOn:text(4000).optional(),observationText:text(4000).optional(),nextStep:text(4000).optional(),anomalyReason:text(1000).nullable().optional()}).strict();
const saveCommand=z.object({operationId:id,workedOn:text(4000),observationText:text(4000),nextStep:text(4000),observations,attachmentIds:z.array(id).max(10).refine(unique)}).strict();
const reference=z.object({observationId:id,version:z.number().int().positive()}).strict();
const capture=z.object({captureId:id,selectedObservationIds:z.array(id).max(100).refine(unique),expectedCaptureVersion:z.number().int().positive(),observationVersions:z.array(reference).max(100)}).strict();
const publishCommand=z.object({operationId:id,expectedPublicationVersion:z.number().int().min(0),excludePendingAttachmentIds:z.array(id).max(10).refine(unique).optional(),correctionReason:text(1000).nullable().optional(),captureSelection:capture.nullable(),textObservationSelection:z.array(reference).max(100)}).strict();
type Observation=z.infer<typeof observation>;
interface PreparationRow {id:string;school_id:string;lesson_id:string;version:number;goals:z.infer<typeof goal>[];administrative_check_note:string|null;planned_waypoints:z.infer<typeof waypoint>[]}
interface WishRow {id:string;school_id:string;training_id:string;version:number;lesson_id:string|null;text:string}
interface DraftRow {id:string;school_id:string;lesson_id:string;author_membership_id:string;version:number;base_publication_version:number;worked_on:string;observation_text:string;next_step:string;observations:Observation[]}
interface RevisionRow extends Omit<DraftRow,'base_publication_version'> {sequence:number;published_at:Date;correction_reason:string|null;_createdAt:string}
const preparationProjection=(r:PreparationRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,goals:r.goals,administrativeCheckNote:r.administrative_check_note,plannedWaypoints:r.planned_waypoints});
const wishProjection=(r:WishRow)=>({id:r.id,schoolId:r.school_id,version:r.version,trainingId:r.training_id,lessonId:r.lesson_id,text:r.text});
const draftProjection=async(db:PoolClient,r:DraftRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,authorMembershipId:r.author_membership_id,basePublicationVersion:r.base_publication_version,workedOn:r.worked_on,observationText:r.observation_text,nextStep:r.next_step,observations:r.observations,attachmentIds:[],geoObservationIds:await draftObservationIDs(db,r.school_id,r.id)});
const revisionProjection=(r:RevisionRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,sequence:r.sequence,authorMembershipId:r.author_membership_id,publishedAt:r.published_at.toISOString(),workedOn:r.worked_on,observationText:r.observation_text,nextStep:r.next_step,observations:r.observations,attachmentIds:[],correctionReason:r.correction_reason,capturePublication:null,textObservations:[]});
async function preparation(db:PoolClient,schoolId:string,lessonId:string,lock=false){const row=(await db.query<PreparationRow>(`SELECT * FROM drivy.lesson_preparation WHERE school_id=$1 AND lesson_id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,lessonId])).rows[0];if(!row)throw notFound();return row;}
async function wish(db:PoolClient,schoolId:string,trainingId:string,lock=false){const row=(await db.query<WishRow>(`SELECT * FROM drivy.training_wish WHERE school_id=$1 AND training_id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,trainingId])).rows[0];if(!row)throw notFound();return row;}
async function draft(db:PoolClient,schoolId:string,draftId:string,lock=false){const row=(await db.query<DraftRow>(`SELECT * FROM drivy.report_draft WHERE school_id=$1 AND id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,draftId])).rows[0];if(!row)throw notFound();return row;}
async function revision(db:PoolClient,schoolId:string,revisionId:string){const row=(await db.query<RevisionRow>('SELECT * FROM drivy.report_revision WHERE school_id=$1 AND id=$2',[schoolId,revisionId])).rows[0];if(!row)throw notFound();return row;}
async function author(db:PoolClient,lessonId:string){if(!(await db.query<{ok:boolean}>('SELECT drivy.report_lesson_author($1) AS ok',[lessonId])).rows[0]?.ok)throw notFound();}
async function trainingAccess(db:PoolClient,trainingId:string,own=false){if(!(await db.query<{ok:boolean}>('SELECT drivy.report_training_access($1,$2) AS ok',[trainingId,own])).rows[0]?.ok)throw notFound();}
type Target={lessonId:string}|{draftId:string}|{trainingId:string};
async function targetLesson(db:PoolClient,schoolId:string,target:Exclude<Target,{trainingId:string}>){return getLesson(db,schoolId,'lessonId'in target?target.lessonId:(await draft(db,schoolId,target.draftId)).lesson_id);}
function guards<T>(schoolId:string,target:Target):CommandGuards<T>{return {
 additionalPersons:async db=>{
  const trainingId='trainingId'in target?target.trainingId:(await targetLesson(db,schoolId,target)).training_id;
  const learner=(await db.query<{learner_id:string}>('SELECT learner_id FROM drivy.training WHERE school_id=$1 AND id=$2 AND drivy.report_training_access(id,false)',[schoolId,trainingId])).rows[0];if(!learner)throw notFound();
  await db.query("SELECT set_config('app.learner_id',$1,true)",[learner.learner_id]);
  const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;if(!person)throw notFound();return [person];
 },authorize:async db=>{if('trainingId'in target)await trainingAccess(db,target.trainingId,true);else await author(db,(await targetLesson(db,schoolId,target)).id);},
 replay:async(db,_actor,data)=>{if('trainingId'in target)await trainingAccess(db,target.trainingId,true);else await author(db,(await targetLesson(db,schoolId,target)).id);return data;}
};}
async function validateCompetencies(db:PoolClient,schoolId:string,trainingId:string,ids:string[]){
 if(!ids.length)return [];
 const rows=(await db.query<{id:string;label:string;version:number;curriculum_version_id:string}>(`SELECT c.id,c.label,c.version,c.curriculum_version_id FROM drivy.competency_definition c
 JOIN drivy.offering_version o ON o.school_id=c.school_id AND o.curriculum_version_id=c.curriculum_version_id
 JOIN drivy.training t ON t.school_id=o.school_id AND t.offering_id=o.id
 WHERE t.school_id=$1 AND t.id=$2 AND c.id=ANY($3::uuid[]) ORDER BY c.id`,[schoolId,trainingId,ids])).rows;
 if(rows.length!==new Set(ids).size)throw new ApiError(409,'CURRICULUM_VERSION_MISMATCH','Choisissez les compétences du référentiel de cette formation.');
 return rows.map(row=>({id:row.id,label:row.label,version:row.version,curriculumVersionId:row.curriculum_version_id}));
}
async function account(db:PoolClient,schoolId:string,lessonId:string){
 const row=(await db.query<{id:string;version:number;planned_price_cents:string}>('SELECT * FROM drivy.lesson_account WHERE school_id=$1 AND lesson_id=$2',[schoolId,lessonId])).rows[0];if(!row)throw notFound();
 const charges=(await db.query<{id:string;version:number;kind:'INITIAL'|'ADJUSTMENT'|'REVERSAL';amount_signed_cents:string;reason:string|null}>('SELECT * FROM drivy.charge_entry WHERE school_id=$1 AND account_id=$2 ORDER BY created_at,id',[schoolId,row.id])).rows;
 const sum=charges.reduce((total,entry)=>total+BigInt(entry.amount_signed_cents),0n);
 if(sum<0n||sum>BigInt(Number.MAX_SAFE_INTEGER))throw new ApiError(409,'ACCOUNT_RECONCILIATION_REQUIRED','Le compte doit être rapproché.');
 return {id:row.id,ownerType:'LESSON' as const,ownerId:lessonId,lessonId,version:row.version,currency:'CHF' as const,plannedPriceCents:Number(row.planned_price_cents),chargeCents:Number(sum),netReceivedCents:0,balanceCents:Number(sum),charges:charges.map(entry=>({id:entry.id,schoolId,version:entry.version,accountId:row.id,lessonId,kind:entry.kind,amountSignedCents:Number(entry.amount_signed_cents),reason:entry.reason})),payments:[]};
}
async function event(db:PoolClient,row:LessonRow,operationId:string,eventType:string){await db.query('INSERT INTO drivy.lesson_event_outbox(school_id,lesson_id,lesson_version,event_type,operation_id) VALUES($1,$2,$3,$4,$5)',[row.school_id,row.id,row.version,eventType,operationId]);}

export function registerLessonReports(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string}){
 const base='/v1/schools/:schoolId',cursors=new Cursors(options.cursorSecret);
 const schoolID=(r:FastifyRequest)=>z.object({schoolId:id}).parse(r.params).schoolId;
 const param=(r:FastifyRequest,key:string)=>z.record(z.string(),z.string()).parse(r.params)[key]!;
 const targetID=(r:FastifyRequest,key:string)=>id.parse(param(r,key));
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 async function read<T>(r:FastifyRequest,work:(db:PoolClient)=>Promise<T>){const identity=await options.verifyToken(r.headers.authorization);return withActor(options.pool,identity,schoolID(r),work);}
 async function command<T>(r:FastifyRequest,type:string,body:{operationId:string},expected:number,target:Target,work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<CommandEffect<T>>){
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  return schoolCommand(options.pool,await options.verifyToken(r.headers.authorization),schoolID(r),type,body,expected,work,['INSTRUCTOR','LEARNER'],guards<T>(schoolID(r),target));
 }
 app.get(`${base}/lessons/:lessonId/preparation`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,async db=>preparationProjection(await preparation(db,schoolID(r),targetID(r,'lessonId'))));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 app.put(`${base}/lessons/:lessonId/preparation`,{bodyLimit:100_000},async(r,reply)=>{
  const body=preparationCommand.parse(r.body),lessonId=targetID(r,'lessonId'),expected=requireVersion(r.headers['if-match']),bound={...body,lessonId};
  const value=await command(r,'SAVE_PREPARATION',bound,expected,{lessonId},async(db,_actor,school)=>{
   const lesson=await getLesson(db,school.id,lessonId,true),old=await preparation(db,school.id,lessonId,true);checkVersion(old.version,expected);
   if(lesson.status!=='PLANNED')throw new ApiError(409,'LESSON_CLOSED','La préparation ne peut plus être modifiée après le résultat de la leçon.');
   await validateCompetencies(db,school.id,lesson.training_id,body.goals.flatMap(g=>g.competencyId?[g.competencyId]:[]));
   const row=(await db.query<PreparationRow>(`UPDATE drivy.lesson_preparation SET version=version+1,goals=$3,administrative_check_note=$4,planned_waypoints=$5 WHERE school_id=$1 AND lesson_id=$2 RETURNING *`,[school.id,lessonId,JSON.stringify(body.goals),body.administrativeCheckNote===undefined?old.administrative_check_note:body.administrativeCheckNote,JSON.stringify(body.plannedWaypoints??old.planned_waypoints)])).rows[0]!;
   return {data:preparationProjection(row),action:'PreparationSaved',resourceType:'Preparation',resourceId:row.id,changedFields:['goals','administrativeCheckNote','plannedWaypoints']};
  });reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.get(`${base}/trainings/:trainingId/wish`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,async db=>wishProjection(await wish(db,schoolID(r),targetID(r,'trainingId'))));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 app.put(`${base}/trainings/:trainingId/wish`,async(r,reply)=>{
  const body=wishCommand.parse(r.body),trainingId=targetID(r,'trainingId'),expected=requireVersion(r.headers['if-match']),bound={...body,trainingId};
  const value=await command(r,'SAVE_WISH',bound,expected,{trainingId},async(db,_actor,school)=>{
   const old=await wish(db,school.id,trainingId,true);checkVersion(old.version,expected);
   if(body.lessonId){const lesson=await getLesson(db,school.id,body.lessonId,true);if(lesson.training_id!==trainingId||lesson.status!=='PLANNED')throw new ApiError(422,'WISH_LESSON_INVALID','Choisissez une leçon planifiée de cette formation.');}
   const row=(await db.query<WishRow>('UPDATE drivy.training_wish SET version=version+1,text=$3,lesson_id=$4 WHERE school_id=$1 AND training_id=$2 RETURNING *',[school.id,trainingId,body.text,body.lessonId===undefined?old.lesson_id:body.lessonId])).rows[0]!;
   return {data:wishProjection(row),action:'WishSaved',resourceType:'Wish',resourceId:row.id,changedFields:['text','lessonId']};
  });reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.post(`${base}/lessons/:lessonId/complete`,{bodyLimit:100_000},async(r,reply)=>{
  const body=completeCommand.parse(r.body),lessonId=targetID(r,'lessonId'),expected=requireVersion(r.headers['if-match']),bound={...body,lessonId};
  const value=await command(r,'COMPLETE_LESSON',bound,expected,{lessonId},async(db,actor,school)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);
   if(old.status!=='PLANNED')throw new ApiError(409,'LESSON_CLOSED','Cette leçon possède déjà un résultat.');
   if(Date.parse(body.actualEnd)<=Date.parse(body.actualStart)||Date.parse(body.actualEnd)>Date.now()+300_000)throw new ApiError(422,'INVALID_ACTUAL_INTERVAL','La fin réelle doit suivre le début et ne pas être future.');
   // Le contrôle de permis n'est pas encore livré : une réalisation reste déclarable avec anomalie motivée.
   if(!body.anomalyReason?.trim())throw new ApiError(422,'ANOMALY_REASON_REQUIRED','Indiquez le motif du constat avec contrôle de permis non confirmé et, le cas échéant, des écarts horaires.');
   if(old.commercial_selection.mode!=='UNIT_PRICE')throw new ApiError(409,'ENTITLEMENT_NOT_READY','Le constat couvert par un pack exige le registre de consommation des droits.');
   const lesson=(await db.query<LessonRow>(`UPDATE drivy.lesson SET status='COMPLETED',version=version+1,actual_start=$3,actual_end=$4,completion_anomaly_reason=$5 WHERE school_id=$1 AND id=$2 RETURNING *`,[school.id,lessonId,body.actualStart,body.actualEnd,body.anomalyReason])).rows[0]!;
   const created=(await db.query<DraftRow>(`INSERT INTO drivy.report_draft(school_id,lesson_id,author_membership_id,worked_on,observation_text,next_step) VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,[school.id,lessonId,actor.membershipId,body.workedOn??'',body.observationText??'',body.nextStep??''])).rows[0]!;
   await attachLiveObservations(db,lesson,created.id,actor.membershipId);
   const accountId=randomUUID();await db.query('INSERT INTO drivy.lesson_account(id,school_id,lesson_id,planned_price_cents) VALUES($1,$2,$3,$4)',[accountId,school.id,lessonId,old.price_cents_snapshot]);
   await db.query(`INSERT INTO drivy.charge_entry(school_id,account_id,kind,amount_signed_cents,reason,operation_id) VALUES($1,$2,'INITIAL',$3,$4,$5)`,[school.id,accountId,old.price_cents_snapshot,'Prix unitaire convenu à la réservation ; leçon réalisée.',body.operationId]);
   await db.query('UPDATE drivy.reservation SET active=false WHERE school_id=$1 AND lesson_id=$2 AND active',[school.id,lessonId]);await event(db,lesson,body.operationId,'LessonCompleted');
   return {data:{lesson:lessonProjection(lesson),draft:await draftProjection(db,created),account:await account(db,school.id,lessonId)},action:'LessonCompleted',resourceType:'Lesson',resourceId:lessonId,resourceVersion:lesson.version,changedFields:['status','actualStart','actualEnd','draft','account'],reason:body.anomalyReason};
  });reply.header('ETag',`"${value.lesson.version}"`);return envelope(value,r);
 });
 app.get(`${base}/report-drafts/:draftId`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,async db=>draftProjection(db,await draft(db,schoolID(r),targetID(r,'draftId'))));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 // Extension de reprise : retrouver son brouillon après perte de la réponse de constat.
 app.get(`${base}/lessons/:lessonId/report-drafts`,async r=>{
  const query=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict().parse(r.query),schoolId=schoolID(r),lessonId=targetID(r,'lessonId');
  const identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   await author(db,lessonId);
   const scope=JSON.stringify(['drafts',schoolId,actor.personId,member!.accessEpoch,lessonId,query.limit]),position=cursors.decode(query.cursor,scope);
   const rows=(await db.query<DraftRow&{_createdAt:string}>(`SELECT *,to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.report_draft
    WHERE school_id=$1 AND lesson_id=$2 AND ($3::timestamptz IS NULL OR (created_at,id)>($3::timestamptz,$4::uuid)) ORDER BY created_at,id LIMIT $5`,[schoolId,lessonId,position?.createdAt??null,position?.id??null,query.limit+1])).rows;
   const items=rows.slice(0,query.limit),last=items.at(-1);return {items:await Promise.all(items.map(row=>draftProjection(db,row))),nextCursor:rows.length>query.limit&&last?cursors.encode(scope,{createdAt:last._createdAt,id:last.id}):null};
  });return envelope(data,r);
 });
 app.put(`${base}/report-drafts/:draftId`,{bodyLimit:350_000},async(r,reply)=>{
  const body=saveCommand.parse(r.body),draftId=targetID(r,'draftId'),expected=requireVersion(r.headers['if-match']),bound={...body,draftId};
  const value=await command(r,'SAVE_REPORT_DRAFT',bound,expected,{draftId},async(db,_actor,school)=>{
   const initial=await draft(db,school.id,draftId),lesson=await getLesson(db,school.id,initial.lesson_id,true),old=await draft(db,school.id,draftId,true);checkVersion(old.version,expected);
   if(lesson.status!=='COMPLETED')throw new ApiError(409,'LESSON_NOT_COMPLETED','Le bilan exige une leçon réalisée.');
   if(body.attachmentIds.length)throw new ApiError(409,'ATTACHMENT_NOT_READY','Le contrôle des pièces doit être disponible avant de les rattacher. Le texte peut être conservé sans pièce.');
   await validateCompetencies(db,school.id,lesson.training_id,body.observations.map(o=>o.competencyId));
   const row=(await db.query<DraftRow>('UPDATE drivy.report_draft SET version=version+1,worked_on=$3,observation_text=$4,next_step=$5,observations=$6 WHERE school_id=$1 AND id=$2 RETURNING *',[school.id,draftId,body.workedOn,body.observationText,body.nextStep,JSON.stringify(body.observations)])).rows[0]!;
   return {data:await draftProjection(db,row),action:'ReportDraftSaved',resourceType:'ReportDraft',resourceId:draftId,changedFields:['workedOn','observationText','nextStep','observations']};
  });reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.post(`${base}/report-drafts/:draftId/publish`,{bodyLimit:100_000},async(r,reply)=>{
  const body=publishCommand.parse(r.body),draftId=targetID(r,'draftId'),expected=requireVersion(r.headers['if-match']),bound={...body,draftId};
  const value=await command(r,'PUBLISH_REPORT_DRAFT',bound,expected,{draftId},async(db,actor,school)=>{
   const initial=await draft(db,school.id,draftId),lesson=await getLesson(db,school.id,initial.lesson_id,true),old=await draft(db,school.id,draftId,true);checkVersion(old.version,expected);
   if(lesson.status!=='COMPLETED')throw new ApiError(409,'LESSON_NOT_COMPLETED','Seule une leçon réalisée peut avoir un bilan publié.');
   if(body.expectedPublicationVersion!==lesson.publication_version||old.base_publication_version!==lesson.publication_version)throw new ApiError(409,'PUBLICATION_VERSION_CONFLICT','La publication a changé. Relisez la version courante.');
   if(!old.worked_on.trim()||!old.observation_text.trim()||!old.next_step.trim())throw new ApiError(422,'REPORT_INCOMPLETE','Renseignez le travail réalisé, le constat et la prochaine étape avant publication.');
   if(lesson.publication_version>0&&!body.correctionReason?.trim())throw new ApiError(422,'CORRECTION_REASON_REQUIRED','Précisez le motif de cette nouvelle révision.');
   if(body.captureSelection!==null||body.textObservationSelection.length)throw new ApiError(409,'OBSERVATION_PUBLICATION_NOT_READY','Les annotations et captures doivent être qualifiées par leur protocole avant publication. Publiez le bilan textuel sans sélection.');
   if(body.excludePendingAttachmentIds?.length)throw new ApiError(422,'ATTACHMENT_SELECTION_INVALID','Aucune pièce ne fait partie de ce brouillon.');
   const snapshot=await validateCompetencies(db,school.id,lesson.training_id,old.observations.map(o=>o.competencyId));
   const sequence=lesson.publication_version+1;
   const row=(await db.query<RevisionRow>(`INSERT INTO drivy.report_revision(school_id,lesson_id,author_membership_id,sequence,worked_on,observation_text,next_step,observations,competency_snapshot,correction_reason,operation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`,[school.id,lesson.id,actor.membershipId,sequence,old.worked_on,old.observation_text,old.next_step,JSON.stringify(old.observations),JSON.stringify(snapshot),body.correctionReason??null,body.operationId])).rows[0]!;
   const updated=(await db.query<LessonRow>('UPDATE drivy.lesson SET version=version+1,publication_version=$3,current_published_revision_id=$4 WHERE school_id=$1 AND id=$2 RETURNING *',[school.id,lesson.id,sequence,row.id])).rows[0]!;
   await db.query('UPDATE drivy.report_draft SET version=version+1,base_publication_version=$3 WHERE school_id=$1 AND id=$2',[school.id,draftId,sequence]);await event(db,updated,body.operationId,'ReportPublished');
   return {data:revisionProjection(row),action:'ReportPublished',resourceType:'ReportRevision',resourceId:row.id,changedFields:['publicationVersion','currentPublishedRevisionId'],...(body.correctionReason?{reason:body.correctionReason}:{})};
  });reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.get(`${base}/lessons/:lessonId/reports`,async r=>{
  const query=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict().parse(r.query),schoolId=schoolID(r),lessonId=targetID(r,'lessonId');
  const identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   const lesson=await getLesson(db,schoolId,lessonId);await trainingAccess(db,lesson.training_id);
   const scope=JSON.stringify(['reports',schoolId,actor.personId,member!.accessEpoch,lessonId,query.limit]),position=cursors.decode(query.cursor,scope);
   const rows=(await db.query<RevisionRow>(`SELECT *,to_char(published_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.report_revision
    WHERE school_id=$1 AND lesson_id=$2 AND ($3::timestamptz IS NULL OR (published_at,id)>($3::timestamptz,$4::uuid)) ORDER BY published_at,id LIMIT $5`,[schoolId,lessonId,position?.createdAt??null,position?.id??null,query.limit+1])).rows;
   const items=rows.slice(0,query.limit),last=items.at(-1);return {items:items.map(revisionProjection),nextCursor:rows.length>query.limit&&last?cursors.encode(scope,{createdAt:last._createdAt,id:last.id}):null};
  });return envelope(data,r);
 });
 app.get(`${base}/report-revisions/:revisionId`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,async db=>revisionProjection(await revision(db,schoolID(r),targetID(r,'revisionId'))));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 app.get(`${base}/lessons/:lessonId/account`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,db=>account(db,schoolID(r),targetID(r,'lessonId')));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 app.get(`${base}/trainings/:trainingId/progress`,async r=>{
  empty.parse(r.query);const trainingId=targetID(r,'trainingId'),schoolId=schoolID(r);
  const value=await read(r,async db=>{
   await trainingAccess(db,trainingId);
   const rows=(await db.query<{competency_id:string;label:string;level:Observation['level'];context:string;observed_at:Date;source_lesson_id:string;source_revision_id:string}>('SELECT * FROM drivy.training_progress WHERE school_id=$1 AND training_id=$2 ORDER BY competency_id',[schoolId,trainingId])).rows;
   const definitions=(await db.query<{id:string}>(`SELECT c.id FROM drivy.competency_definition c JOIN drivy.offering_version o ON o.school_id=c.school_id AND o.curriculum_version_id=c.curriculum_version_id
    JOIN drivy.training t ON t.school_id=o.school_id AND t.offering_id=o.id WHERE t.school_id=$1 AND t.id=$2 ORDER BY c.sort_order,c.id`,[schoolId,trainingId])).rows;
   const observed=new Set(rows.map(row=>row.competency_id));
   return {trainingId,items:rows.map(row=>({competencyId:row.competency_id,label:row.label,level:row.level,context:row.context,observedAt:row.observed_at.toISOString(),sourceLessonId:row.source_lesson_id,sourceRevisionId:row.source_revision_id})),unobservedCompetencyIds:definitions.filter(row=>!observed.has(row.id)).map(row=>row.id),computedAt:new Date().toISOString()};
  });return envelope(value,r);
 });
}

/** AP72 rend seulement la preuve, après relecture des droits pédagogiques actuels. */
export async function authorizeReportOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type==='COMPLETE_LESSON'){await author(db,(await getLesson(db,schoolId,resourceId)).id);return true;}
 if(type==='SAVE_REPORT_DRAFT'){await draft(db,schoolId,resourceId);return true;}
 if(type==='PUBLISH_REPORT_DRAFT'){await author(db,(await revision(db,schoolId,resourceId)).lesson_id);return true;}
 if(type==='SAVE_PREPARATION'){const row=(await db.query<PreparationRow>('SELECT * FROM drivy.lesson_preparation WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rows[0];if(!row)throw notFound();return true;}
 if(type==='SAVE_WISH'){const row=(await db.query<WishRow>('SELECT * FROM drivy.training_wish WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rows[0];if(!row)throw notFound();await trainingAccess(db,row.training_id,true);return true;}
 return false;
}
