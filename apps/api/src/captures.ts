import type { FastifyInstance,FastifyRequest } from 'fastify';
import type { Pool,PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { withActor } from './database.js';
import { ApiError,notFound } from './errors.js';
import { Cursors } from './cursor.js';
import { checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type CommandGuards,type SchoolRow } from './commands.js';
import { getLesson } from './lessons.js';
import { assessmentCommand,assessmentProjection,choiceCommand,choiceProjection,chunkCommand,captureProjection,finalizeCommand,startCommand,stopCommand,uuid,type AssessmentInput,type AssessmentRow,type CaptureRow,type ChoiceRow,type ChunkInput,type ChunkRow,type Manifest,type TrackPoint } from './capture-contracts.js';
import { CaptureAuthority,canonicalCaptureJSON,chunkAAD,decryptPoints,encryptPoints,trackContentHash,type CaptureConfig,type QualificationProfile } from './capture-crypto.js';

const empty=z.object({}).strict();
const error=(code:string,message:string,status=409)=>new ApiError(status,code,message);
type Target={learnerId:string}|{lessonId:string}|{captureId:string}|{deviceId:string};
async function getCapture(db:PoolClient,schoolId:string,captureId:string,lock=false){const row=(await db.query<CaptureRow>(`SELECT * FROM drivy.capture_session WHERE school_id=$1 AND id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,captureId])).rows[0];if(!row)throw notFound();return row;}
async function getAssessment(db:PoolClient,schoolId:string,deviceId:string,assessmentId:string){const row=(await db.query<AssessmentRow>('SELECT * FROM drivy.capture_device_assessment WHERE school_id=$1 AND device_id=$2 AND id=$3',[schoolId,deviceId,assessmentId])).rows[0];if(!row)throw notFound();return row;}
async function requireLatestAssessment(db:PoolClient,row:AssessmentRow){const latest=(await db.query<{id:string}>('SELECT id FROM drivy.capture_device_assessment WHERE school_id=$1 AND device_id=$2 AND membership_id=$3 ORDER BY assessed_at DESC,id DESC LIMIT 1',[row.school_id,row.device_id,row.membership_id])).rows[0];if(latest?.id!==row.id)throw error('DEVICE_ASSESSMENT_SUPERSEDED','Utilisez le diagnostic le plus récent de cet appareil.');}
async function getChoice(db:PoolClient,schoolId:string,learnerId:string,lessonId:string|null){const row=(await db.query<ChoiceRow>('SELECT * FROM drivy.recording_choice WHERE id=drivy.capture_effective_choice($1,$2,$3)',[schoolId,learnerId,lessonId])).rows[0];if(!row)throw error('RECORDING_CHOICE_NOT_SET','Le choix GPS n’est pas encore renseigné.',404);return row;}
async function author(db:PoolClient,lessonId:string){if(!(await db.query<{ok:boolean}>('SELECT drivy.report_lesson_author($1) AS ok',[lessonId])).rows[0]?.ok)throw notFound();}
async function learnerAccess(db:PoolClient,learnerId:string,own=false){if(!(await db.query<{ok:boolean}>('SELECT drivy.capture_learner_access($1,$2) AS ok',[learnerId,own])).rows[0]?.ok)throw notFound();}
async function notice(db:PoolClient,schoolId:string){const row=(await db.query<{notice_version_id:string;notice_text:string;retention_text:string;contact_email:string;approved_at:Date}>('SELECT * FROM drivy.school_data_policy WHERE school_id=$1 AND approved_at IS NOT NULL ORDER BY version DESC LIMIT 1',[schoolId])).rows[0];if(!row)throw error('RECORDING_NOTICE_NOT_READY','L’école doit adopter la notice avant tout choix GPS.');return row;}
async function targetLearner(db:PoolClient,schoolId:string,target:Exclude<Target,{deviceId:string}>){if('learnerId'in target)return target.learnerId;return (await getLesson(db,schoolId,'lessonId'in target?target.lessonId:(await getCapture(db,schoolId,target.captureId)).lesson_id)).learner_id;}
function guards<T>(schoolId:string,target:Target,own=false):CommandGuards<T>{return {
 additionalPersons:async db=>{if('deviceId'in target)return [];const learnerId=await targetLearner(db,schoolId,target);await learnerAccess(db,learnerId,own);await db.query("SELECT set_config('app.learner_id',$1,true)",[learnerId]);const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;if(!person)throw notFound();return [person];},
 authorize:async(db,actor)=>{if('deviceId'in target){if(!actor.roles.includes('INSTRUCTOR'))throw notFound();return;}if('learnerId'in target){await learnerAccess(db,target.learnerId,own);return;}await author(db,'lessonId'in target?target.lessonId:(await getCapture(db,schoolId,target.captureId)).lesson_id);}
};}
function configured(config:CaptureConfig|undefined):CaptureConfig{if(!config)throw error('CAPTURE_SERVICE_NOT_CONFIGURED','La capture scolaire n’est pas encore configurée. La leçon reste disponible sans GPS.',503);return config;}
function findProfile(config:CaptureConfig|undefined,input:Pick<AssessmentInput,'platform'|'deviceClass'|'modelCode'|'osVersion'|'appBuild'>):QualificationProfile|undefined{return config?.profiles.find(p=>p.platform===input.platform&&p.deviceClass===input.deviceClass&&p.modelCode===input.modelCode&&p.osVersion===input.osVersion&&p.appBuild===input.appBuild&&Date.parse(p.expiresAt)>Date.now());}
function assessmentBlockers(config:CaptureConfig|undefined,input:AssessmentInput){
 const p=findProfile(config,input),blockers:{code:string;message:string;field:string|null;purpose:string|null;resourceId:null;destinationKey:string}[]=[];
 const add=(code:string,message:string,field:string|null)=>blockers.push({code,message,field,purpose:'Capturer la position pendant une leçon explicitement autorisée.',resourceId:null,destinationKey:'DEVICE_DIAGNOSTIC'});
 if(!config)add('CAPTURE_SERVICE_NOT_CONFIGURED','Le service de capture scolaire doit être configuré.',null);
 if(!p)add('DEVICE_PROFILE_NOT_QUALIFIED','Cette combinaison appareil, système et build n’a pas de profil de qualification valide.',null);
 if(input.permission==='NONE'||(p?.requireBackground&&input.permission!=='BACKGROUND'))add('LOCATION_PERMISSION_REQUIRED','Les permissions de localisation requises ne sont pas disponibles.','permission');
 if(p?.requirePreciseLocation&&!input.preciseLocation)add('PRECISE_LOCATION_REQUIRED','Ce profil exige une localisation précise.','preciseLocation');
 if(input.sampleAgeSeconds===null||(p&&input.sampleAgeSeconds>p.maxSampleAgeSeconds))add('LOCATION_SAMPLE_REQUIRED','Une mesure assez récente est requise.','sampleAgeSeconds');
 if(input.horizontalAccuracyMeters===null||(p&&input.horizontalAccuracyMeters>p.maxHorizontalAccuracyMeters))add('LOCATION_ACCURACY_REQUIRED','La précision mesurée est insuffisante pour ce profil.','horizontalAccuracyMeters');
 if(p&&input.freeBytes<p.minimumFreeBytes)add('LOCAL_STORAGE_REQUIRED','L’espace libre requis manque sur cet appareil.','freeBytes');
 if(!input.networkAvailable)add('NETWORK_REQUIRED','Le départ d’une capture exige une connexion.','networkAvailable');
 return {profile:p,blockers};
}
function validatePoints(body:ChunkInput,row:CaptureRow){
 if(trackContentHash(body)!==body.contentHash)throw error('CHUNK_HASH_MISMATCH','Le hash ne correspond pas au contenu du lot.',422);
 const start=Date.parse(body.segmentStartedAt),cutoff=Math.min(row.expires_at.getTime(),row.cutoff_at?.getTime()??Infinity),now=Date.now();
 if(start<row.authorized_at.getTime()||start>=cutoff||start>now||(body.segmentIndex===0)!==(body.segmentStartReason==='START'))throw error('SEGMENT_INTERVAL_INVALID','Le début du segment sort de l’intervalle autorisé.',422);
 let previous:TrackPoint|undefined;
 for(const point of body.points){const measured=Date.parse(point.capturedAt);
  if(measured<start||measured>=cutoff||measured>now||Math.abs(measured-start-point.elapsedMs)>1)throw error('POINT_OUTSIDE_CAPTURE','Une mesure sort du segment ou de la borne de collecte.',422);
  if(previous&&(point.sequence<=previous.sequence||point.elapsedMs<=previous.elapsedMs||measured<=Date.parse(previous.capturedAt)))throw error('POINT_ORDER_INVALID','Les séquences et les temps doivent être strictement croissants.',422);previous=point;
 }
}
async function chunks(db:PoolClient,row:CaptureRow){return (await db.query<ChunkRow>('SELECT * FROM drivy.capture_chunk WHERE school_id=$1 AND capture_id=$2 ORDER BY segment_index,chunk_index',[row.school_id,row.id])).rows;}
function validateChunkMetadata(existing:ChunkRow[],body:ChunkInput,segmentId:string,chunkIndex:number){
 const first=body.points[0]!,last=body.points.at(-1)!,started=Date.parse(body.segmentStartedAt);
 for(const row of existing){
  if(row.segment_id===segmentId){
   if(row.segment_index!==body.segmentIndex||row.segment_started_at.getTime()!==started||row.segment_start_reason!==body.segmentStartReason)throw error('SEGMENT_METADATA_MISMATCH','Les métadonnées de ce segment sont immuables.');
   if(row.chunk_index===chunkIndex)continue;
   const before=row.chunk_index<chunkIndex;
   if(before?(row.last_sequence>=first.sequence||row.last_elapsed_ms>=first.elapsedMs):(row.first_sequence<=last.sequence||row.first_elapsed_ms<=last.elapsedMs))throw error('CHUNK_ORDER_CONFLICT','Les lots de ce segment se chevauchent ou sont désordonnés.');
  }else{
   if(row.segment_index===body.segmentIndex)throw error('SEGMENT_METADATA_MISMATCH','Cet indice appartient déjà à un autre segment.');
   if(row.segment_index<body.segmentIndex?row.last_captured_at.getTime()>=started:Date.parse(last.capturedAt)>=row.segment_started_at.getTime())throw error('SEGMENT_INTERVAL_INVALID','Deux segments ne peuvent pas se recouvrir.');
  }
 }
}
function manifestQuality(rows:ChunkRow[],manifest:Manifest[]):'SYNCED'|'PARTIAL'{
 let missing=false;
 for(const row of rows){const m=manifest.find(m=>m.segmentId===row.segment_id);if(!m||m.segmentIndex!==row.segment_index||!m.expectedChunkIndices.includes(row.chunk_index))throw error('CAPTURE_MANIFEST_MISMATCH','Le manifeste ne décrit pas les lots déjà reçus.');}
 for(const m of manifest){const all=rows.filter(r=>r.segment_id===m.segmentId),present=all.filter(r=>r.encrypted_points!==null);
  if(all.length===m.expectedChunkIndices.length){if(all.reduce((n,r)=>n+r.point_count,0)!==m.expectedPointCount||(all.length?Math.max(...all.map(r=>r.last_sequence)):null)!==m.lastSequence)throw error('CAPTURE_MANIFEST_MISMATCH','Le nombre de points ou la dernière séquence diffère du manifeste.');}
  if(present.length!==m.expectedChunkIndices.length)missing=true;
 }
 return missing?'PARTIAL':'SYNCED';
}
function receipt(row:ChunkRow,duplicate:boolean){return {captureId:row.capture_id,segmentId:row.segment_id,chunkIndex:row.chunk_index,contentHash:row.content_hash,acknowledgedAt:row.acknowledged_at.toISOString(),duplicate};}

export function registerCaptures(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string;capture?:CaptureConfig}){
 const base='/v1/schools/:schoolId',cursors=new Cursors(options.cursorSecret);
 const param=(r:FastifyRequest,key:string)=>uuid.parse(z.record(z.string(),z.string()).parse(r.params)[key]);
 const schoolID=(r:FastifyRequest)=>param(r,'schoolId');
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 async function read<T>(r:FastifyRequest,work:(db:PoolClient)=>Promise<T>){return withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolID(r),work);}
 async function command<T>(r:FastifyRequest,type:string,body:{operationId:string},expected:number|null,target:Target,work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<CommandEffect<T>>,own=false,override?:CommandGuards<T>){
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  try{return await schoolCommand(options.pool,await options.verifyToken(r.headers.authorization),schoolID(r),type,body,expected,work,['INSTRUCTOR','LEARNER'],{...guards<T>(schoolID(r),target,own),...override});}
  catch(e){if(typeof e==='object'&&e!==null&&'code'in e&&e.code==='23505'&&'constraint'in e&&String(e.constraint).startsWith('capture_one_'))throw error('CAPTURE_ALREADY_ACTIVE','Une capture est déjà autorisée pour cette leçon, ce moniteur ou cet appareil.');throw e;}
 }
 // Extension de découverte : seules les clés publiques de l'origine API configurée sont exposées.
 app.get('/v1/capture-keys',async r=>{empty.parse(r.query);return envelope(await new CaptureAuthority(configured(options.capture)).publicKeys(),r);});
 // Extension de lecture : information effective avant un choix explicite, sans adoption sur GET.
 app.get(`${base}/recording-notice`,async r=>{empty.parse(r.query);return envelope(await read(r,async db=>{const n=await notice(db,schoolID(r));return {noticeVersionId:n.notice_version_id,noticeText:n.notice_text,retentionText:n.retention_text,contactEmail:n.contact_email,approvedAt:n.approved_at.toISOString()};}),r);});
 app.post(`${base}/devices/:deviceId/assessments`,async(r,reply)=>{
  const body=assessmentCommand.parse(r.body),deviceId=param(r,'deviceId'),bound={...body,deviceId};
  const value=await command(r,'ASSESS_CAPTURE_DEVICE',bound,null,{deviceId},async(db,actor,school)=>{
   if(!actor.roles.includes('INSTRUCTOR'))throw notFound();
   // ON CONFLICT n'expose pas le propriétaire d'un deviceId attribué à un autre compte.
   await db.query('INSERT INTO drivy.capture_installation(device_id,person_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[deviceId,actor.personId]);
   if(!(await db.query('SELECT device_id FROM drivy.capture_installation WHERE device_id=$1 AND person_id=$2 FOR UPDATE',[deviceId,actor.personId])).rowCount)throw error('DEVICE_OWNERSHIP_CONFLICT','Cette installation ne peut pas être liée à ce compte.',403);
   const assessment=assessmentBlockers(options.capture,body),row=(await db.query<AssessmentRow>(`INSERT INTO drivy.capture_device_assessment(school_id,device_id,membership_id,person_id,platform,device_class,model_code,os_version,app_build,qualification_profile_version,status,expires_at,blockers)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,statement_timestamp()+interval '5 minutes',$12) RETURNING *`,[school.id,deviceId,actor.membershipId,actor.personId,body.platform,body.deviceClass,body.modelCode,body.osVersion,body.appBuild,assessment.profile?.version??'UNQUALIFIED',assessment.blockers.length?'NEEDS_CHECK':'QUALIFIED',JSON.stringify(assessment.blockers)])).rows[0]!;
   return {data:assessmentProjection(row),action:'CaptureDeviceAssessed',resourceType:'DeviceAssessment',resourceId:row.id,changedFields:['status','qualificationProfileVersion']};
  });reply.code(201).header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.get(`${base}/devices/:deviceId/assessments/:assessmentId`,async(r,reply)=>{
  empty.parse(r.query);const value=await read(r,async db=>{const row=await getAssessment(db,schoolID(r),param(r,'deviceId'),param(r,'assessmentId'));
   await requireLatestAssessment(db,row);
   const p=findProfile(options.capture,{platform:row.platform as 'IOS'|'ANDROID',deviceClass:row.device_class as 'PHONE'|'TABLET',modelCode:row.model_code,osVersion:row.os_version,appBuild:row.app_build});
   if(row.expires_at.getTime()<=Date.now()||(row.status==='QUALIFIED'&&(!p||p.version!==row.qualification_profile_version)))throw error('DEVICE_ASSESSMENT_EXPIRED','Refaites le diagnostic de cet appareil.');
   return assessmentProjection(row);});reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.get(`${base}/learners/:learnerId/recording-choice`,async(r,reply)=>{
  const query=z.object({lessonId:uuid.optional()}).strict().parse(r.query),learnerId=param(r,'learnerId');
  const value=await read(r,async db=>{await learnerAccess(db,learnerId);if(query.lessonId&&(await getLesson(db,schoolID(r),query.lessonId)).learner_id!==learnerId)throw notFound();return choiceProjection(await getChoice(db,schoolID(r),learnerId,query.lessonId??null));});reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.post(`${base}/learners/:learnerId/recording-choice`,async(r,reply)=>{
  const body=choiceCommand.parse(r.body),learnerId=param(r,'learnerId'),bound={...body,learnerId};
  const value=await command(r,'RECORD_RECORDING_CHOICE',bound,null,{learnerId},async(db,actor,school)=>{
   if(body.source==='RECORDED_VERBAL'&&!actor.roles.includes('INSTRUCTOR'))throw notFound();
   if(body.lessonId&&(await getLesson(db,school.id,body.lessonId)).learner_id!==learnerId)throw notFound();
   if((await notice(db,school.id)).notice_version_id!==body.noticeVersionId)throw error('RECORDING_NOTICE_CHANGED','Relisez la notice actuelle avant de confirmer.');
   let previous:ChoiceRow|undefined;try{previous=await getChoice(db,school.id,learnerId,body.lessonId);}catch(e){if(!(e instanceof ApiError)||e.code!=='RECORDING_CHOICE_NOT_SET')throw e;}
   if(body.source==='RECORDED_VERBAL'&&body.status==='ALLOWED'&&previous?.source==='SELF'&&previous.status==='REFUSED')throw error('RECORDING_CHOICE_PROTECTED','Seul l’élève peut lever son refus explicite.');
   const row=(await db.query<ChoiceRow>(`INSERT INTO drivy.recording_choice(school_id,version,learner_id,lesson_id,status,notice_version_id,recorded_by,source)
    SELECT $1,coalesce(max(version),0)+1,$2,$3,$4,$5,$6,$7 FROM drivy.recording_choice WHERE school_id=$1 AND learner_id=$2 RETURNING *`,[school.id,learnerId,body.lessonId,body.status,body.noticeVersionId,actor.membershipId,body.source])).rows[0]!;
   return {data:choiceProjection(row),action:'RecordingChoiceRecorded',resourceType:'RecordingChoice',resourceId:row.id,changedFields:['status','source','noticeVersionId']};
  },body.source==='SELF');reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.post(`${base}/lessons/:lessonId/captures`,async(r,reply)=>{
  const config=configured(options.capture),body=startCommand.parse(r.body),lessonId=param(r,'lessonId'),bound={...body,lessonId},expected=requireVersion(r.headers['if-match']);
  const capture=await command(r,'START_CAPTURE',bound,expected,{lessonId},async(db,actor,school)=>{
   if(school.status!=='ACTIVE'||!school.modules.gpsEnabled)throw error('CAPTURE_DISABLED','Le GPS scolaire n’est pas activé. La leçon reste disponible sans GPS.');
   const lesson=await getLesson(db,school.id,lessonId,true);checkVersion(lesson.version,expected);if(lesson.status!=='PLANNED')throw error('LESSON_CLOSED','Cette leçon ne permet plus de démarrer une capture.');
   const training=(await db.query<{status:string}>('SELECT status FROM drivy.training WHERE school_id=$1 AND id=$2',[school.id,lesson.training_id])).rows[0];if(training?.status!=='ACTIVE')throw error('TRAINING_NOT_ACTIVE','La formation doit être active.');
   const now=Date.now();if(now<lesson.planned_start.getTime()-1_800_000||now>=lesson.planned_end.getTime()+1_800_000)throw error('CAPTURE_START_WINDOW','La capture démarre à proximité de la leçon planifiée.');
   const choice=await getChoice(db,school.id,lesson.learner_id,lessonId),n=await notice(db,school.id);
   if(choice.status!=='ALLOWED')throw error('RECORDING_NOT_ALLOWED','Le choix actuel de l’élève ne permet pas de capturer le GPS.',403);
   if(choice.id!==body.choiceId||choice.version!==body.choiceVersion||choice.notice_version_id!==body.noticeVersionId||n.notice_version_id!==body.noticeVersionId)throw error('RECORDING_CHOICE_CHANGED','Relisez le choix et la notice avant de commencer.');
   const assessment=await getAssessment(db,school.id,body.deviceId,body.deviceAssessmentId),profile=findProfile(config,{platform:assessment.platform as 'IOS'|'ANDROID',deviceClass:assessment.device_class as 'PHONE'|'TABLET',modelCode:assessment.model_code,osVersion:assessment.os_version,appBuild:assessment.app_build});
   await requireLatestAssessment(db,assessment);
   if(assessment.membership_id!==actor.membershipId||assessment.person_id!==actor.personId||assessment.status!=='QUALIFIED'||assessment.expires_at.getTime()<=now||!profile||profile.version!==assessment.qualification_profile_version)throw error('DEVICE_NOT_QUALIFIED','Cet appareil exige un diagnostic courant et un profil qualifié.');
   await db.query('SELECT device_id FROM drivy.capture_installation WHERE device_id=$1 FOR UPDATE',[body.deviceId]);
   await db.query('SELECT drivy.expire_capture_device($1)',[body.deviceId]);
   await db.query(`UPDATE drivy.capture_session SET capture_state='EXPIRED',cutoff_at=least(coalesce(cutoff_at,expires_at),expires_at),version=version+1 WHERE school_id=$1 AND person_id=$2 AND capture_state='AUTHORIZED' AND expires_at<=statement_timestamp()`,[school.id,actor.personId]);
   if((await db.query("SELECT id FROM drivy.capture_session WHERE school_id=$1 AND capture_state='AUTHORIZED' AND (lesson_id=$2 OR instructor_membership_id=$3 OR device_id=$4)",[school.id,lessonId,actor.membershipId,body.deviceId])).rowCount)throw error('CAPTURE_ALREADY_ACTIVE','Une capture est déjà autorisée pour cette leçon, ce moniteur ou cet appareil.');
   const assignment=(await db.query<{valid_until:Date|null}>(`SELECT valid_until FROM drivy.instructor_assignment WHERE school_id=$1 AND training_id=$2 AND instructor_membership_id=$3 AND valid_from<=statement_timestamp() AND (valid_until IS NULL OR valid_until>statement_timestamp()) ORDER BY valid_until DESC NULLS FIRST LIMIT 1`,[school.id,lesson.training_id,actor.membershipId])).rows[0];
   if(!assignment)throw notFound();const expiry=new Date(Math.min(now+10_800_000,Date.parse(profile.expiresAt),assignment.valid_until?.getTime()??Infinity));
   const row=(await db.query<CaptureRow>(`INSERT INTO drivy.capture_session(school_id,lesson_id,learner_id,instructor_membership_id,person_id,device_id,choice_id,notice_version_id,device_assessment_id,authorized_at,expires_at,upload_deadline)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,[school.id,lessonId,lesson.learner_id,actor.membershipId,actor.personId,body.deviceId,choice.id,body.noticeVersionId,assessment.id,new Date(now),expiry,new Date(expiry.getTime()+config.uploadHours*3_600_000)])).rows[0]!;
   return {data:captureProjection(row),action:'CaptureAuthorized',resourceType:'CaptureSession',resourceId:row.id,changedFields:['authorizedAt','expiresAt','choiceId','deviceAssessmentId']};
  },false,{replay:async(db,_actor,data)=>captureProjection(await getCapture(db,schoolID(r),data.id))});
  // Les preuves sont dérivées après commit ; elles ne figurent jamais dans Operation/audit.
  const row=await read(r,db=>getCapture(db,schoolID(r),capture.id)),authority=new CaptureAuthority(config);
  reply.code(201).header('ETag',`"${row.version}"`);return envelope({capture:captureProjection(row),signedCaptureAuthorization:await authority.sign(row,'capture:collect'),signedUploadAuthorization:await authority.sign(row,'capture:upload'),serverTime:new Date().toISOString()},r);
 });
 app.get(`${base}/captures/:captureId`,async(r,reply)=>{empty.parse(r.query);const value=await read(r,async db=>captureProjection(await getCapture(db,schoolID(r),param(r,'captureId'))));reply.header('ETag',`"${value.version}"`);return envelope(value,r);});
 app.put(`${base}/captures/:captureId/segments/:segmentId/chunks/:chunkIndex`,{bodyLimit:524_288},async(r,reply)=>{
  const config=configured(options.capture),body=chunkCommand.parse(r.body),captureId=param(r,'captureId'),segmentId=param(r,'segmentId'),chunkIndex=z.coerce.number().int().min(0).max(999).parse(z.record(z.string(),z.string()).parse(r.params).chunkIndex),bound={...body,captureId,segmentId,chunkIndex};
  const authority=new CaptureAuthority(config),baseGuards=guards<ReturnType<typeof receipt>>(schoolID(r),{captureId});
  const verify=async(db:PoolClient,actor:CommandActor)=>{await author(db,(await getCapture(db,schoolID(r),captureId)).lesson_id);const row=await getCapture(db,schoolID(r),captureId);await authority.verifyUpload(body.signedUploadAuthorization,row,actor.personId);if(row.publication_state==='DELETED'||row.publication_state==='WITHDRAWN')throw error('CAPTURE_UNAVAILABLE','Cette capture n’accepte plus de données.');};
  const value=await command(r,'UPLOAD_TRACK_CHUNK',bound,null,{captureId},async(db,actor,school)=>{
   const row=await getCapture(db,school.id,captureId,true);await authority.verifyUpload(body.signedUploadAuthorization,row,actor.personId);validatePoints(body,row);
   const rows=await chunks(db,row),old=rows.find(x=>x.segment_id===segmentId&&x.chunk_index===chunkIndex);
   if(old){if(old.content_hash!==body.contentHash)throw error('CHUNK_IDENTITY_MISMATCH','Ce lot a déjà été reçu avec un autre contenu.');if(!old.encrypted_points)throw error('CHUNK_CUTOFF_REJECTED','Ce lot a été écarté par la borne de collecte.');return {data:receipt(old,true),action:'TrackChunkAccepted',resourceType:'CaptureSession',resourceId:row.id,resourceVersion:row.version,changedFields:[]};}
   if(row.finalized_at)throw error('CAPTURE_FINALIZED','La reconstruction est finalisée ; aucun nouveau lot n’est accepté.');
   if(rows.reduce((n,v)=>n+v.point_count,0)+body.points.length>100_000||rows.length>=2000)throw error('CAPTURE_CAPACITY_REACHED','La limite technique de cette capture est atteinte.',413);
   validateChunkMetadata(rows,body,segmentId,chunkIndex);
   if(row.manifest){const m=row.manifest.find(m=>m.segmentId===segmentId);if(!m||m.segmentIndex!==body.segmentIndex||!m.expectedChunkIndices.includes(chunkIndex))throw error('CAPTURE_MANIFEST_MISMATCH','Ce lot n’appartient pas au manifeste arrêté.');}
   const first=body.points[0]!,last=body.points.at(-1)!,inserted=(await db.query<ChunkRow>(`INSERT INTO drivy.capture_chunk(school_id,capture_id,segment_id,chunk_index,segment_index,segment_started_at,segment_start_reason,content_hash,point_count,first_sequence,last_sequence,first_elapsed_ms,last_elapsed_ms,first_captured_at,last_captured_at,encrypted_points,key_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING *`,[school.id,captureId,segmentId,chunkIndex,body.segmentIndex,body.segmentStartedAt,body.segmentStartReason,body.contentHash,body.points.length,first.sequence,last.sequence,first.elapsedMs,last.elapsedMs,first.capturedAt,last.capturedAt,encryptPoints(config,body.points,chunkAAD(school.id,captureId,segmentId,chunkIndex,body.contentHash)),config.encryptionKeyId])).rows[0]!;
   const updated=(await db.query<CaptureRow>("UPDATE drivy.capture_session SET version=version+1,reconstruction_version=reconstruction_version+1,sync_state='UPLOADING' WHERE id=$1 RETURNING *",[row.id])).rows[0]!;
   return {data:receipt(inserted,false),action:'TrackChunkAccepted',resourceType:'CaptureSession',resourceId:row.id,resourceVersion:updated.version,changedFields:['chunks']};
  },false,{...baseGuards,authorize:verify,replay:async(db,actor,data)=>{await verify(db,actor);const row=(await db.query<ChunkRow>('SELECT * FROM drivy.capture_chunk WHERE capture_id=$1 AND segment_id=$2 AND chunk_index=$3',[captureId,segmentId,chunkIndex])).rows[0];if(!row?.encrypted_points)throw error('CHUNK_CUTOFF_REJECTED','Ce lot n’est plus disponible.');return {...data,duplicate:true};}});reply.header('Cache-Control','no-store');return envelope(value,r);
 });
 app.post(`${base}/captures/:captureId/stop`,{bodyLimit:524_288},async(r,reply)=>{
  const body=stopCommand.parse(r.body),captureId=param(r,'captureId'),bound={...body,captureId};
  const value=await command(r,'STOP_CAPTURE',bound,null,{captureId},async(db,_actor,school)=>{
   const row=await getCapture(db,school.id,captureId,true),stopped=Date.parse(body.stoppedAt);
   if(stopped<row.authorized_at.getTime()||stopped>Date.now())throw error('CAPTURE_STOP_INVALID','L’arrêt doit être postérieur à l’autorisation et déjà survenu.',422);
   if(row.manifest&&canonicalCaptureJSON(row.manifest)!==canonicalCaptureJSON(body.segments))throw error('CAPTURE_MANIFEST_MISMATCH','Le manifeste arrêté est immuable.');
   const cutoff=new Date(Math.min(stopped,row.expires_at.getTime(),row.cutoff_at?.getTime()??Infinity));
   const changed=(await db.query<CaptureRow>(`UPDATE drivy.capture_session SET capture_state=CASE WHEN capture_state='AUTHORIZED' THEN 'STOPPED' ELSE capture_state END,version=version+1,stopped_at=least(coalesce(stopped_at,$2),$2),cutoff_at=$3,manifest=coalesce(manifest,$4::jsonb) WHERE id=$1 RETURNING *`,[row.id,new Date(stopped),cutoff,JSON.stringify(body.segments)])).rows[0]!;
   return {data:captureProjection(changed),action:'CaptureStopped',resourceType:'CaptureSession',resourceId:row.id,changedFields:['stoppedAt','cutoffAt','manifest']};
  },false,{replay:async db=>captureProjection(await getCapture(db,schoolID(r),captureId))});reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.post(`${base}/captures/:captureId/finalize`,{bodyLimit:524_288},async(r,reply)=>{
  const body=finalizeCommand.parse(r.body),captureId=param(r,'captureId'),bound={...body,captureId},expected=requireVersion(r.headers['if-match']);
  const value=await command(r,'FINALIZE_CAPTURE',bound,expected,{captureId},async(db,_actor,school)=>{
   const row=await getCapture(db,school.id,captureId,true);checkVersion(row.version,expected);
   if(row.capture_state==='AUTHORIZED'&&row.expires_at.getTime()>Date.now())throw error('CAPTURE_STOP_REQUIRED','Arrêtez le collecteur avant de finaliser la capture.');
   if(!row.manifest||canonicalCaptureJSON(row.manifest)!==canonicalCaptureJSON(body.segments))throw error('CAPTURE_MANIFEST_MISMATCH','La finalisation exige le manifeste de l’arrêt durable.');
   const quality=manifestQuality(await chunks(db,row),body.segments);if(quality==='PARTIAL'&&!body.allowPartial)throw error('CAPTURE_INCOMPLETE','Des lots manquent ; poursuivez le transfert ou confirmez la finalisation partielle.');
   const updated=(await db.query<CaptureRow>(`UPDATE drivy.capture_session SET version=version+1,capture_state=CASE WHEN capture_state='AUTHORIZED' THEN 'EXPIRED' ELSE capture_state END,cutoff_at=coalesce(cutoff_at,expires_at),sync_state=$2,finalized_at=coalesce(finalized_at,statement_timestamp()) WHERE id=$1 RETURNING *`,[row.id,quality])).rows[0]!;
   return {data:captureProjection(updated),action:'CaptureFinalized',resourceType:'CaptureSession',resourceId:row.id,changedFields:['syncState','finalizedAt']};
  },false,{replay:async db=>captureProjection(await getCapture(db,schoolID(r),captureId))});reply.header('ETag',`"${value.version}"`);return envelope(value,r);
 });
 app.get(`${base}/captures/:captureId/replay`,async r=>{
  const query=z.object({cursor:z.string().min(1).max(2000).optional(),limit:z.coerce.number().int().min(1).max(100).default(50),reportRevisionId:uuid.optional()}).strict().parse(r.query),captureId=param(r,'captureId'),config=configured(options.capture);
  // Une révision publiée ne donne jamais accès par repli à la reconstruction privée.
  if(query.reportRevisionId)throw notFound();
  const result=await withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolID(r),async(db,actor,member)=>{
   const row=await getCapture(db,schoolID(r),captureId);if(row.publication_state!=='PRIVATE')throw notFound();
   const scope=canonicalCaptureJSON(['captureReplay',row.id,row.reconstruction_version,actor.personId,member!.accessEpoch,query.limit]),position=cursors.decode(query.cursor,scope),rows=(await chunks(db,row)).filter(c=>c.encrypted_points!==null);
   const after=position?{segmentId:position.id,sequence:Date.parse(position.createdAt)}:undefined;
   const ordered=rows.flatMap(c=>decryptPoints(config,c.encrypted_points!,c.key_id,chunkAAD(c.school_id,c.capture_id,c.segment_id,c.chunk_index,c.content_hash)).map(point=>({segmentId:c.segment_id,segmentIndex:c.segment_index,point})));
   const begin=after?ordered.findIndex(p=>p.segmentId===after.segmentId&&p.point.sequence===after.sequence)+1:0;if(after&&begin===0)throw error('INVALID_CURSOR','La reconstruction a changé ; rechargez le trajet.',400);
   let page=ordered.slice(begin,begin+query.limit);const segments:{segmentId:string;segmentIndex:number;points:TrackPoint[];hasGapBefore:boolean;qualityLabel:'AVAILABLE'|'LOW_ACCURACY'|'PARTIAL';continuesFromPreviousPage:boolean;continuesOnNextPage:boolean}[]=[];
   const assessment=(await db.query<{qualification_profile_version:string}>('SELECT qualification_profile_version FROM drivy.capture_device_assessment WHERE id=$1',[row.device_assessment_id])).rows[0];
   const qualityProfile=config.profiles.find(p=>p.version===assessment?.qualification_profile_version);
   for(let i=0;i<page.length;i++){const item=page[i]!,previous=ordered[begin+i-1],same=previous?.segmentId===item.segmentId,continuous=same&&previous.point.sequence+1===item.point.sequence,last=segments.at(-1);
    const quality=qualityProfile&&item.point.accuracyMeters>qualityProfile.maxHorizontalAccuracyMeters?'LOW_ACCURACY':row.sync_state==='SYNCED'&&qualityProfile?'AVAILABLE':'PARTIAL';
    if(last?.segmentId===item.segmentId&&continuous){last.points.push(item.point);if(quality==='LOW_ACCURACY')last.qualityLabel=quality;}
    else{if(segments.length===100){page=page.slice(0,i);break;}segments.push({segmentId:item.segmentId,segmentIndex:item.segmentIndex,points:[item.point],hasGapBefore:previous?(!same||!continuous):item.segmentIndex>0||item.point.sequence>0,qualityLabel:quality,continuesFromPreviousPage:i===0&&!!continuous,continuesOnNextPage:false});}
   }
   const last=page.at(-1),next=ordered[begin+page.length];if(last&&next&&last.segmentId===next.segmentId&&last.point.sequence+1===next.point.sequence)segments.at(-1)!.continuesOnNextPage=true;
   return {captureId,quality:row.sync_state==='SYNCED'?'SYNCED':'PARTIAL',publicationState:'PRIVATE',segments,observations:[],nextCursor:last&&next?cursors.encode(scope,{id:last.segmentId,createdAt:new Date(last.point.sequence).toISOString()}):null,generatedAt:new Date().toISOString(),reportRevisionId:null,geometrySnapshotId:null};
  });return envelope(result,r);
 });
}

/** AP72 expose uniquement la preuve d'une ressource encore autorisée, jamais ses positions. */
export async function authorizeCaptureOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type==='ASSESS_CAPTURE_DEVICE'){if(!(await db.query('SELECT id FROM drivy.capture_device_assessment WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rowCount)throw notFound();return true;}
 if(type==='RECORD_RECORDING_CHOICE'){if(!(await db.query('SELECT id FROM drivy.recording_choice WHERE school_id=$1 AND id=$2',[schoolId,resourceId])).rowCount)throw notFound();return true;}
 if(['START_CAPTURE','UPLOAD_TRACK_CHUNK','STOP_CAPTURE','FINALIZE_CAPTURE'].includes(type)){const row=await getCapture(db,schoolId,resourceId);await author(db,row.lesson_id);return true;}
 return false;
}
