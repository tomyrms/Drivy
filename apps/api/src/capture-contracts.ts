import { z } from 'zod';
// PostgreSQL restitue les UUID en minuscules : l'AAD chiffrée emploie la même forme.
export const uuid=z.uuid().transform(value=>value.toLowerCase());
export const instant=z.iso.datetime({offset:true});
/** Les anciens corps sans origin restent REVIEW ; aucune qualification n'est déduite. */
export const geoObservationCommand=z.object({operationId:uuid,draftId:uuid.nullable(),captureId:uuid.nullable(),segmentId:uuid.nullable(),
 pointSequence:z.number().int().min(0).max(2_147_483_646).nullable(),competencyId:uuid.nullable(),
 text:z.string().refine(v=>v.trim().length>0&&[...v].length<=4000),origin:z.enum(['LIVE','REVIEW']).optional(),observedAt:instant.optional(),
 eventKind:z.enum(['MARKER','QUALIFIED']).optional(),eventStatus:z.enum(['ATTENTION','TO_REWORK','POSITIVE']).nullable().optional()
}).strict().superRefine((v,ctx)=>{
 const invalid=(message:string)=>ctx.addIssue({code:'custom',message});
 if(!([v.captureId,v.segmentId,v.pointSequence].every(x=>x===null)||[v.captureId,v.segmentId,v.pointSequence].every(x=>x!==null)))invalid('L’ancre doit être complète ou absente.');
 if((v.origin??'REVIEW')==='REVIEW'&&v.draftId===null)invalid('La revue exige un brouillon.');
 if(v.origin==='LIVE'&&(!v.observedAt||!v.eventKind||v.eventStatus===undefined))invalid('L’observation live exige instant, type et statut explicites.');
 if(v.eventKind==='MARKER'&&(v.origin!=='LIVE'||v.competencyId!==null||v.eventStatus!==null))invalid('Un repère reste LIVE, sans compétence ni statut.');
 if(v.origin==='LIVE'&&v.eventKind==='QUALIFIED'&&(v.competencyId===null||v.eventStatus===null))invalid('Choisissez une compétence et un statut.');
});
export type GeoObservationInput=z.infer<typeof geoObservationCommand>;
export interface GeoObservationRow {id:string;school_id:string;version:number;lesson_id:string;training_id:string;author_membership_id:string;
 draft_id:string|null;capture_id:string|null;segment_id:string|null;point_sequence:number|null;competency_id:string|null;text:string|null;
 origin:'LIVE'|'REVIEW';observed_at:Date|null;event_kind:'MARKER'|'QUALIFIED'|null;event_status:'ATTENTION'|'TO_REWORK'|'POSITIVE'|null;created_at:Date;removed_at:Date|null}
export const geoObservationProjection=(r:GeoObservationRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,trainingId:r.training_id,
 draftId:r.draft_id,captureId:r.capture_id,segmentId:r.segment_id,pointSequence:r.point_sequence,competencyId:r.competency_id,text:r.text!,origin:r.origin,
 ...(r.observed_at?{observedAt:r.observed_at.toISOString()}:{}),...(r.event_kind?{eventKind:r.event_kind}:{}),eventStatus:r.event_status,authorMembershipId:r.author_membership_id});
const index=z.number().int().min(0).max(2_147_483_646);
const unique=(items:unknown[])=>new Set(items).size===items.length;
export const trackPoint=z.object({sequence:index,elapsedMs:z.number().int().min(0).max(10_800_000),capturedAt:instant,latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),accuracyMeters:z.number().min(0)}).strict();
export const segmentManifest=z.object({segmentId:uuid,segmentIndex:z.number().int().min(0).max(199),expectedChunkIndices:z.array(z.number().int().min(0).max(999)).max(1000).refine(unique),expectedPointCount:z.number().int().min(0).max(100_000),lastSequence:index.nullable(),endReason:z.enum(['STOP','PAUSE','APP_TERMINATED','PERMISSION_LOST','SIGNAL_LOST','EXPIRED','OTHER'])}).strict().refine(x=>x.expectedPointCount===0?x.lastSequence===null&&x.expectedChunkIndices.length===0:x.lastSequence!==null&&x.expectedChunkIndices.length>0);
export const manifests=z.array(segmentManifest).max(200).refine(x=>unique(x.map(v=>v.segmentId))&&unique(x.map(v=>v.segmentIndex))&&x.every(v=>v.segmentIndex<x.length)&&x.reduce((n,v)=>n+v.expectedPointCount,0)<=100_000&&x.reduce((n,v)=>n+v.expectedChunkIndices.length,0)<=2000);
export const choiceCommand=z.object({operationId:uuid,lessonId:uuid.nullable(),status:z.enum(['ALLOWED','REFUSED','UNKNOWN']),noticeVersionId:uuid,source:z.enum(['SELF','RECORDED_VERBAL'])}).strict();
export const assessmentCommand=z.object({operationId:uuid,platform:z.enum(['IOS','ANDROID']),deviceClass:z.enum(['PHONE','TABLET']),modelCode:z.string().min(1).max(100),osVersion:z.string().min(1).max(100),appBuild:z.string().min(1).max(100),permission:z.enum(['NONE','FOREGROUND','BACKGROUND']),preciseLocation:z.boolean(),sampleAgeSeconds:z.number().int().min(0).max(3600).nullable(),horizontalAccuracyMeters:z.number().min(0).max(10000).nullable(),freeBytes:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).nullable(),networkAvailable:z.boolean()}).strict().superRefine((value,ctx)=>{if((value.platform==='IOS'&&value.freeBytes!==null)||(value.platform==='ANDROID'&&value.freeBytes===null))ctx.addIssue({code:'custom',path:['freeBytes'],message:'Disk capacity stays on iOS; Android requires a numeric value.'});});
export const startCommand=z.object({operationId:uuid,deviceId:uuid,choiceId:uuid,choiceVersion:z.number().int().positive(),noticeVersionId:uuid,explicitStartConfirmed:z.literal(true),deviceAssessmentId:uuid}).strict();
export const chunkCommand=z.object({operationId:uuid,segmentIndex:z.number().int().min(0).max(199),segmentStartedAt:instant,segmentStartReason:z.enum(['START','RESUME','RESTART','PERMISSION_RESTORED','SIGNAL_RECOVERED']),contentHash:z.string().regex(/^[a-f0-9]{64}$/),points:z.array(trackPoint).min(1).max(1000),signedUploadAuthorization:z.string().min(1).max(12000)}).strict();
export const stopCommand=z.object({operationId:uuid,stoppedAt:instant,reason:z.enum(['LESSON_ENDED','USER_STOP','LEARNER_REFUSAL','PERMISSION_LOST','EXPIRED','DEVICE_ERROR']),segments:manifests,localCollectorStopped:z.literal(true)}).strict();
export const finalizeCommand=z.object({operationId:uuid,segments:manifests,allowPartial:z.boolean()}).strict();
export type TrackPoint=z.infer<typeof trackPoint>;
export type Manifest=z.infer<typeof segmentManifest>;
export type AssessmentInput=z.infer<typeof assessmentCommand>;
export type ChunkInput=z.infer<typeof chunkCommand>;
export interface CaptureRow {id:string;school_id:string;version:number;lesson_id:string;learner_id:string;instructor_membership_id:string;person_id:string;device_id:string;choice_id:string;notice_version_id:string;authorized_at:Date;expires_at:Date;upload_deadline:Date;stopped_at:Date|null;cutoff_at:Date|null;capture_state:'AUTHORIZED'|'STOPPED'|'REVOKED'|'EXPIRED';sync_state:'LOCAL_ONLY'|'UPLOADING'|'SYNCED'|'PARTIAL'|'REJECTED';publication_state:'PRIVATE'|'WITHDRAWN'|'DELETED';device_assessment_id:string;manifest:Manifest[]|null;finalized_at:Date|null;reconstruction_version:number}
export interface ChunkRow {school_id:string;capture_id:string;segment_id:string;chunk_index:number;segment_index:number;segment_started_at:Date;segment_start_reason:string;content_hash:string;point_count:number;first_sequence:number;last_sequence:number;first_elapsed_ms:number;last_elapsed_ms:number;first_captured_at:Date;last_captured_at:Date;encrypted_points:Buffer|null;key_id:string;acknowledged_at:Date}
export interface ChoiceRow {id:string;school_id:string;version:number;learner_id:string;lesson_id:string|null;status:'ALLOWED'|'REFUSED'|'UNKNOWN';notice_version_id:string;recorded_by:string;recorded_at:Date;source:'SELF'|'RECORDED_VERBAL'}
export interface AssessmentRow {id:string;school_id:string;version:number;device_id:string;membership_id:string;person_id:string;platform:string;device_class:string;model_code:string;os_version:string;app_build:string;qualification_profile_version:string;status:'QUALIFIED'|'UNSUPPORTED'|'NEEDS_CHECK';assessed_at:Date;expires_at:Date;blockers:unknown[]}
export const captureProjection=(r:CaptureRow)=>({id:r.id,schoolId:r.school_id,version:r.version,lessonId:r.lesson_id,learnerId:r.learner_id,instructorMembershipId:r.instructor_membership_id,deviceId:r.device_id,choiceId:r.choice_id,authorizedAt:r.authorized_at.toISOString(),expiresAt:r.expires_at.toISOString(),stoppedAt:r.stopped_at?.toISOString()??null,cutoffAt:r.cutoff_at?.toISOString()??null,uploadDeadline:r.upload_deadline.toISOString(),captureState:r.capture_state==='AUTHORIZED'&&r.expires_at.getTime()<=Date.now()?'EXPIRED' as const:r.capture_state,syncState:r.sync_state,publicationState:r.publication_state,deviceAssessmentId:r.device_assessment_id});
export const choiceProjection=(r:ChoiceRow)=>({id:r.id,schoolId:r.school_id,version:r.version,learnerId:r.learner_id,lessonId:r.lesson_id,status:r.status,noticeVersionId:r.notice_version_id,recordedBy:r.recorded_by,recordedAt:r.recorded_at.toISOString(),source:r.source});
export const assessmentProjection=(r:AssessmentRow)=>({id:r.id,schoolId:r.school_id,version:r.version,deviceId:r.device_id,membershipId:r.membership_id,platform:r.platform,deviceClass:r.device_class,modelCode:r.model_code,osVersion:r.os_version,appBuild:r.app_build,qualificationProfileVersion:r.qualification_profile_version,status:r.status,assessedAt:r.assessed_at.toISOString(),expiresAt:r.expires_at.toISOString(),blockers:r.blockers});
