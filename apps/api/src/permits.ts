import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandGuards} from './commands.js';
import {ApiError,notFound} from './errors.js';
import {Cursors} from './cursor.js';

const id=z.uuid(),empty=z.object({}).strict();
/** PermitCommand canonique (AP30). La date de validité vient de la pièce vue ; elle n'est jamais calculée. */
const permitCommand=z.object({operationId:id,documentId:id.nullable().optional(),physicalSeen:z.boolean(),categoryCode:z.string().min(1).max(30),
 validUntil:z.iso.date().nullable().optional(),decision:z.enum(['APPROVED','REJECTED']),reason:z.string().max(2000).nullable().optional()}).strict()
 .refine(v=>v.decision!=='APPROVED'||v.physicalSeen||!!v.documentId,'Une approbation exige un examen physique attesté ou une pièce.')
 .refine(v=>v.decision!=='REJECTED'||/\S/.test(v.reason??''),'Un rejet exige un motif.');
interface PermitRow {id:string;school_id:string;version:number;training_id:string;document_id:string|null;physical_seen:boolean;category_code:string;valid_until:string|null;
 decision:'APPROVED'|'REJECTED';reviewer_membership_id:string;reviewed_at:Date;reason:string|null;is_expired:boolean;_createdAt:string}
const columns=`c.id,c.school_id,c.version,c.training_id,c.document_id,c.physical_seen,c.category_code,to_char(c.valid_until,'YYYY-MM-DD') AS valid_until,c.decision,
 c.reviewer_membership_id,c.reviewed_at,c.reason,coalesce(c.valid_until<(statement_timestamp() AT TIME ZONE s.time_zone)::date,false) AS is_expired,
 to_char(c.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt"`;
export const permitProjection=(r:PermitRow)=>({id:r.id,schoolId:r.school_id,version:r.version,trainingId:r.training_id,documentId:r.document_id,physicalSeen:r.physical_seen,
 categoryCode:r.category_code,validUntil:r.valid_until,decision:r.decision,reviewerMembershipId:r.reviewer_membership_id,reviewedAt:r.reviewed_at.toISOString(),reason:r.reason,isExpired:r.is_expired});
type Permit=ReturnType<typeof permitProjection>;
async function visibleTraining(db:PoolClient,schoolId:string,trainingId:string){
 const row=(await db.query<{learner_id:string}>('SELECT learner_id FROM drivy.training WHERE school_id=$1 AND id=$2 AND drivy.catalogue_training_visible(id)',[schoolId,trainingId])).rows[0];
 if(!row)throw notFound();return row;
}
async function permitRow(db:PoolClient,schoolId:string,permitId:string){
 const row=(await db.query<PermitRow>(`SELECT ${columns} FROM drivy.permit_check c JOIN drivy.school s ON s.id=c.school_id WHERE c.school_id=$1 AND c.id=$2`,[schoolId,permitId])).rows[0];
 if(!row)throw notFound();return row;
}
const reviewRequired=()=>new ApiError(403,'PERMIT_REVIEW_REQUIRED','Le contrôle du permis exige l’habilitation permit_review sur cette formation.');
function guards(schoolId:string,trainingId:string):CommandGuards<Permit>{return {
 additionalPersons:async db=>{
  const training=await visibleTraining(db,schoolId,trainingId);
  await db.query("SELECT set_config('app.learner_id',$1,true)",[training.learner_id]);
  const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;if(!person)throw notFound();return [person];
 },
 authorize:async db=>{await visibleTraining(db,schoolId,trainingId);if(!(await db.query<{ok:boolean}>('SELECT drivy.permit_review_allowed($1) AS ok',[trainingId])).rows[0]?.ok)throw reviewRequired();},
 replay:async(db,_actor,data)=>permitProjection(await permitRow(db,schoolId,data.id))
};}

export function registerPermits(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string}){
 const base='/v1/schools/:schoolId/trainings/:trainingId/permit-checks',cursors=new Cursors(options.cursorSecret);
 const params=(r:FastifyRequest)=>z.object({schoolId:id,trainingId:id}).parse(r.params);
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 // AP29 : historique complet dans l'ordre d'enregistrement ; la dernière décision est l'état courant.
 app.get(base,async r=>{
  const query=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict().parse(r.query);
  const {schoolId,trainingId}=params(r),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   await visibleTraining(db,schoolId,trainingId);
   if(!(await db.query<{ok:boolean}>('SELECT drivy.permit_read_allowed($1) AS ok',[trainingId])).rows[0]?.ok)throw notFound();
   const scope=JSON.stringify(['permit-checks',schoolId,actor.personId,member!.accessEpoch,trainingId,query.limit]),position=cursors.decode(query.cursor,scope);
   const rows=(await db.query<PermitRow>(`SELECT ${columns} FROM drivy.permit_check c JOIN drivy.school s ON s.id=c.school_id WHERE c.school_id=$1 AND c.training_id=$2
    AND ($3::timestamptz IS NULL OR (c.created_at,c.id)>($3::timestamptz,$4::uuid)) ORDER BY c.created_at,c.id LIMIT $5`,[schoolId,trainingId,position?.createdAt??null,position?.id??null,query.limit+1])).rows;
   const items=rows.slice(0,query.limit),last=items.at(-1);
   return {items:items.map(permitProjection),nextCursor:rows.length>query.limit&&last?cursors.encode(scope,{createdAt:last._createdAt,id:last.id}):null};
  });return envelope(data,r);
 });
 // AP30 : décision humaine ; contrôleur et date imposés par le serveur.
 app.post(base,async(r,reply)=>{
  empty.parse(r.query);const body=permitCommand.parse(r.body),{schoolId,trainingId}=params(r),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const bound={...body,trainingId};
  const data=await schoolCommand(options.pool,identity,schoolId,'RECORD_PERMIT_CHECK',bound,expected,async(db,actor,school)=>{
   if(body.documentId)throw new ApiError(409,'DOCUMENT_NOT_READY','Le contrôle par pièce déposée exige le circuit documentaire. Attestez l’examen physique de l’original.');
   const training=(await db.query<{version:number;status:string;archived_at:Date|null;category_code:string}>(`SELECT t.version,t.status,l.archived_at,o.category_code FROM drivy.training t
    JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
    WHERE t.school_id=$1 AND t.id=$2 FOR UPDATE OF t`,[school.id,trainingId])).rows[0];
   if(!training)throw notFound();checkVersion(training.version,expected);
   if(!['ACTIVE','PAUSED'].includes(training.status)||training.archived_at)throw new ApiError(409,'TRAINING_NOT_ACTIVE','Le contrôle concerne une formation en cours d’un dossier non archivé.');
   if(body.categoryCode!==training.category_code)throw new ApiError(422,'CATEGORY_MISMATCH','La catégorie contrôlée doit être celle de cette formation.');
   if(body.decision==='APPROVED'&&body.validUntil){
    const expired=(await db.query<{expired:boolean}>('SELECT $1::date<(statement_timestamp() AT TIME ZONE $2)::date AS expired',[body.validUntil,school.timeZone])).rows[0]!.expired;
    if(expired)throw new ApiError(422,'PERMIT_EXPIRED','La date de validité indiquée est déjà dépassée : une approbation n’est pas possible.');
   }
   const permitId=randomUUID();
   await db.query(`INSERT INTO drivy.permit_check(id,school_id,training_id,document_id,physical_seen,category_code,valid_until,decision,reviewer_membership_id,reason,operation_id)
    VALUES($1,$2,$3,NULL,$4,$5,$6,$7,$8,$9,$10)`,[permitId,school.id,trainingId,body.physicalSeen,body.categoryCode,body.validUntil??null,body.decision,actor.membershipId,body.reason?.trim()?body.reason:null,body.operationId]);
   await db.query('UPDATE drivy.training SET version=version+1 WHERE school_id=$1 AND id=$2',[school.id,trainingId]);
   const row=await permitRow(db,school.id,permitId);
   return {data:permitProjection(row),action:'PermitReviewed',resourceType:'PermitCheck',resourceId:permitId,changedFields:['decision','categoryCode','validUntil','physicalSeen'],...(body.reason?.trim()?{reason:body.reason.slice(0,1000)}:{})};
  },['ADMIN','INSTRUCTOR'],guards(schoolId,trainingId));
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}

/** AP72 : la preuve d'un contrôle reste lisible selon les droits de lecture actuels. */
export async function authorizePermitOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type!=='RECORD_PERMIT_CHECK')return false;await permitRow(db,schoolId,resourceId);return true;
}
