import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type CommandEffect,type SchoolRow} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';

/**
 * Cours collectifs : socle (#80) et création/publication depuis l'agenda (#38).
 * Extension hors canon OpenAPI 3.11.0 (AP126–AP138 décrivent un modèle produit/profil réglementaire non retenu par les décisions
 * du 23 octobre 2026). Contrat : docs/implementation/cours-collectifs-socle-80.md.
 * Une seule source de places (drivy.course_seats_taken : inscriptions actives + propositions actives) et une seule source
 * d'occupation (drivy.reservation, exclusion PostgreSQL partagée avec les leçons).
 */
export const DEFAULT_SELF_CANCEL_HOURS=24;
const id=z.uuid(),date=z.iso.datetime({offset:true}),text=(max:number)=>z.string().trim().max(max);
const typeBody=z.object({operationId:id,title:text(120).min(1),description:text(2000)}).strict();
const policyBody=z.object({operationId:id,selfCancelHours:z.number().int().min(0).max(720),offerResponseMinutes:z.number().int().min(15).max(10080).nullable()}).strict();
const occurrence=z.object({startsAt:date,endsAt:date,instructorMembershipId:id,attendanceRequired:z.boolean()}).strict();
const seriesBody=z.object({operationId:id,typeId:id,title:text(200).min(1),description:text(4000),location:text(500),conditions:text(4000),
 teachingLanguage:z.enum(['fr','de','it','en']).nullable(),responsibleMembershipId:id,capacity:z.number().int().min(1).max(200),
 minParticipants:z.number().int().min(1).max(200).nullable(),timeZone:z.string().min(1).max(100),occurrences:z.array(occurrence).min(1).max(64)}).strict()
 .refine(v=>v.minParticipants===null||v.minParticipants<=v.capacity,{message:'minParticipants'});
const publishBody=z.object({operationId:id}).strict();
const capacityBody=z.object({operationId:id,capacity:z.number().int().min(1).max(200)}).strict();
const listQuery=z.object({from:date.optional(),to:date.optional(),status:z.enum(['DRAFT','PUBLISHED','CANCELLED','CLOSED']).optional()}).strict();
const empty=z.object({}).strict();
type SeriesInput=z.infer<typeof seriesBody>;

export interface CourseType {id:string;schoolId:string|null;stableKey:'AWARENESS'|'FIRST_AID'|null;title:string;description:string;version:number;predefined:boolean}
export interface CoursePolicy {version:number;selfCancelHours:number;offerResponseMinutes:number|null}
export interface CourseOccurrence {id:string;position:number;startsAt:string;endsAt:string;timeZone:string;instructorMembershipId:string;instructorDisplayName:string;attendanceRequired:boolean}
export interface CourseSeries {id:string;schoolId:string;version:number;status:'DRAFT'|'PUBLISHED'|'CANCELLED'|'CLOSED';typeId:string;typeTitle:string;
 title:string;description:string;location:string;conditions:string;teachingLanguage:string|null;responsibleMembershipId:string;responsibleDisplayName:string;
 capacity:number;seatsTaken:number;remainingSeats:number;minParticipants:number|null;policyVersion:number;selfCancelHours:number;
 selfCancellationDeadline:string;firstStartsAt:string;lastEndsAt:string;totalMinutes:number;publishedAt:string|null;occurrences:CourseOccurrence[];canManage:boolean}

const typeColumns=`id,school_id AS "schoolId",stable_key AS "stableKey",title,description,version,school_id IS NULL AS predefined`;
export async function canManageCourses(db:PoolClient,schoolId:string){return (await db.query<{ok:boolean}>('SELECT drivy.can_manage_courses($1) AS ok',[schoolId])).rows[0]?.ok===true;}
const accessRequired=()=>new ApiError(403,'COURSE_ACCESS_REQUIRED','La gestion des cours demande le droit correspondant.');
async function requireManage(db:PoolClient,schoolId:string){if(!(await canManageCourses(db,schoolId)))throw accessRequired();}

export async function currentPolicy(db:PoolClient,schoolId:string):Promise<CoursePolicy>{
 // Les écritures passent sous le verrou de l'école posé par schoolCommand : deux enregistrements se suivent.
 const row=(await db.query<CoursePolicy>(`SELECT version,self_cancel_hours AS "selfCancelHours",offer_response_minutes AS "offerResponseMinutes"
  FROM drivy.course_policy_version WHERE school_id=$1 ORDER BY version DESC LIMIT 1`,[schoolId])).rows[0];
 return row??{version:1,selfCancelHours:DEFAULT_SELF_CANCEL_HOURS,offerResponseMinutes:null};
}
/** Échéance d'annulation autonome : première séance moins le délai accepté. */
export function selfCancellationDeadline(firstStartsAt:Date,hours:number){return new Date(firstStartsAt.getTime()-hours*3_600_000);}

interface SeriesRow {id:string;school_id:string;version:number;status:CourseSeries['status'];type_id:string;type_title:string;title:string;description:string;location:string;conditions:string;
 teaching_language:string|null;responsible_membership_id:string;responsible_name:string|null;capacity:number;seats_taken:number|null;min_participants:number|null;policy_version:number;
 self_cancel_hours:number;published_at:Date|null}
interface OccurrenceRow {id:string;series_id:string;position:number;starts_at:Date;ends_at:Date;time_zone:string;instructor_membership_id:string;instructor_name:string|null;attendance_required:boolean}
const seriesSelect=`SELECT s.id,s.school_id,s.version,s.status,s.type_id,t.title AS type_title,s.title,s.description,s.location,s.conditions,s.teaching_language,
 s.responsible_membership_id,drivy.course_staff_name(s.school_id,s.responsible_membership_id) AS responsible_name,s.capacity,drivy.course_seats_taken(s.id) AS seats_taken,
 s.min_participants,s.policy_version,s.self_cancel_hours,s.published_at FROM drivy.course_series s JOIN drivy.course_type t ON t.id=s.type_id`;

async function project(db:PoolClient,rows:SeriesRow[],canManage:boolean):Promise<CourseSeries[]>{
 if(!rows.length)return [];
 const occurrences=(await db.query<OccurrenceRow>(`SELECT id,series_id,position,starts_at,ends_at,time_zone,instructor_membership_id,
  drivy.course_staff_name(school_id,instructor_membership_id) AS instructor_name,attendance_required FROM drivy.course_occurrence WHERE series_id=ANY($1::uuid[]) ORDER BY series_id,position`,[rows.map(r=>r.id)])).rows;
 return rows.map(row=>{
  const own=occurrences.filter(o=>o.series_id===row.id);
  const first=own[0]?.starts_at??new Date(0),last=own.reduce((max,o)=>o.ends_at>max?o.ends_at:max,first);
  const taken=row.seats_taken??0;
  return {id:row.id,schoolId:row.school_id,version:row.version,status:row.status,typeId:row.type_id,typeTitle:row.type_title,title:row.title,description:row.description,
   location:row.location,conditions:row.conditions,teachingLanguage:row.teaching_language,responsibleMembershipId:row.responsible_membership_id,responsibleDisplayName:row.responsible_name??'',
   capacity:row.capacity,seatsTaken:taken,remainingSeats:Math.max(0,row.capacity-taken),minParticipants:row.min_participants,policyVersion:row.policy_version,selfCancelHours:row.self_cancel_hours,
   selfCancellationDeadline:selfCancellationDeadline(first,row.self_cancel_hours).toISOString(),firstStartsAt:first.toISOString(),lastEndsAt:last.toISOString(),
   totalMinutes:own.reduce((sum,o)=>sum+Math.round((o.ends_at.getTime()-o.starts_at.getTime())/60000),0),publishedAt:row.published_at?.toISOString()??null,
   occurrences:own.map(o=>({id:o.id,position:o.position,startsAt:o.starts_at.toISOString(),endsAt:o.ends_at.toISOString(),timeZone:o.time_zone,
    instructorMembershipId:o.instructor_membership_id,instructorDisplayName:o.instructor_name??'',attendanceRequired:o.attendance_required})),canManage};
 });
}
export async function getSeries(db:PoolClient,schoolId:string,seriesId:string,lock=false):Promise<CourseSeries>{
 if(lock)await db.query('SELECT 1 FROM drivy.course_series WHERE school_id=$1 AND id=$2 FOR UPDATE',[schoolId,seriesId]);
 const row=(await db.query<SeriesRow>(`${seriesSelect} WHERE s.school_id=$1 AND s.id=$2`,[schoolId,seriesId])).rows[0];
 if(!row)throw notFound();
 return (await project(db,[row],await canManageCourses(db,schoolId)))[0]!;
}

/** Contrôles communs d'une série saisie : fuseau de l'école, ordre, chevauchement interne, formateurs, type visible. */
async function validateSeries(db:PoolClient,school:SchoolRow,body:SeriesInput){
 if(body.timeZone!==school.timeZone)throw new ApiError(422,'INVALID_TIME_ZONE','Utilisez le fuseau de l’école affiché.');
 const sorted=[...body.occurrences].map(o=>({...o,start:Date.parse(o.startsAt),end:Date.parse(o.endsAt)})).sort((a,b)=>a.start-b.start);
 for(const [index,o] of sorted.entries()){
  if(!(o.end>o.start))throw new ApiError(422,'INVALID_INTERVAL','Chaque séance doit finir après son début.');
  if(o.end-o.start>12*3_600_000)throw new ApiError(422,'INVALID_INTERVAL','Une séance dure au plus 12 heures.');
  const previous=sorted[index-1];if(previous&&o.start<previous.end)throw new ApiError(422,'COURSE_OCCURRENCES_OVERLAP','Deux séances de ce cours se chevauchent.');
 }
 const type=(await db.query<{id:string}>('SELECT id FROM drivy.course_type WHERE id=$1 AND archived_at IS NULL AND (school_id IS NULL OR school_id=$2)',[body.typeId,school.id])).rows[0];
 if(!type)throw new ApiError(422,'COURSE_TYPE_UNKNOWN','Choisissez un type de cours de l’école.');
 const instructors=new Set((await db.query<{membership_id:string}>('SELECT membership_id FROM drivy.course_instructors($1)',[school.id])).rows.map(r=>r.membership_id));
 for(const o of body.occurrences)if(!instructors.has(o.instructorMembershipId))throw new ApiError(422,'INSTRUCTOR_NOT_ACTIVE','Choisissez un moniteur actif de l’école.');
 const responsible=(await db.query<{ok:boolean}>('SELECT drivy.course_staff_active($1,$2) AS ok',[school.id,body.responsibleMembershipId])).rows[0];
 if(!responsible?.ok)throw new ApiError(422,'RESPONSIBLE_NOT_ACTIVE','Choisissez un responsable actif de l’école.');
 return sorted;
}
async function writeOccurrences(db:PoolClient,schoolId:string,seriesId:string,sorted:Awaited<ReturnType<typeof validateSeries>>,timeZone:string){
 await db.query('DELETE FROM drivy.course_occurrence WHERE school_id=$1 AND series_id=$2',[schoolId,seriesId]);
 for(const [index,o] of sorted.entries())await db.query(`INSERT INTO drivy.course_occurrence(school_id,series_id,position,starts_at,ends_at,time_zone,instructor_membership_id,attendance_required)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[schoolId,seriesId,index+1,o.startsAt,o.endsAt,timeZone,o.instructorMembershipId,o.attendanceRequired]);
}
const exclusion=(error:unknown,code:string,message:string):never=>{
 if(typeof error==='object'&&error!==null&&'code'in error){
  if(error.code==='23P01')throw new ApiError(409,code,message);
  if(error.code==='23505')throw new ApiError(409,'COURSE_TYPE_EXISTS','Un type de cours porte déjà ce nom.');
 }
 throw error;
};

export function registerCourses(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const base='/v1/schools/:schoolId',schoolID=(r:FastifyRequest)=>z.object({schoolId:id}).parse(r.params).schoolId;
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const staff=['ADMIN','INSTRUCTOR'];
 const command=async<T>(r:FastifyRequest,type:string,body:{operationId:string}&Record<string,unknown>,expected:number|null,work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<CommandEffect<T>>,replay:(db:PoolClient,previous:T)=>Promise<T>,conflict?:[string,string])=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  try{return await schoolCommand<T>(options.pool,identity,schoolId,type,body,expected,work,staff,{authorize:async db=>requireManage(db,schoolId),replay:async(db,_a,previous)=>replay(db,previous)});}
  catch(error){return exclusion(error,conflict?.[0]??'COURSE_CONFLICT',conflict?.[1]??'Ce changement entre en conflit avec l’agenda.');}
 };

 // Catalogue pour les écrans de création : types, conditions courantes, formateurs proposables, droit de gestion.
 app.get(`${base}/course-catalogue`,async r=>{
  empty.parse(r.query);const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
   if(!member)throw forbidden();
   const canManage=await canManageCourses(db,schoolId);
   const types=(await db.query<CourseType>(`SELECT ${typeColumns} FROM drivy.course_type WHERE archived_at IS NULL AND (school_id IS NULL OR school_id=$1) ORDER BY school_id IS NOT NULL,title,id`,[schoolId])).rows;
   const instructors=canManage?(await db.query<{membershipId:string;displayName:string}>('SELECT membership_id AS "membershipId",display_name AS "displayName" FROM drivy.course_instructors($1)',[schoolId])).rows:[];
   return {schoolId,canManage,types,policy:await currentPolicy(db,schoolId),instructors};
  }),r);
 });

 app.post(`${base}/course-types`,{bodyLimit:8_192},async(r,reply)=>{
  const body=typeBody.parse(r.body),schoolId=schoolID(r);
  const data=await command<CourseType>(r,'CREATE_COURSE_TYPE',body,null,async(db,actor)=>{
   const row=(await db.query<CourseType>(`INSERT INTO drivy.course_type(school_id,title,description,created_by) VALUES($1,$2,$3,$4) RETURNING ${typeColumns}`,[schoolId,body.title,body.description,actor.membershipId])).rows[0]!;
   return {data:row,action:'CourseTypeCreated',resourceType:'CourseType',resourceId:row.id,changedFields:['title','description']};
  },async(db,previous)=>(await db.query<CourseType>(`SELECT ${typeColumns} FROM drivy.course_type WHERE id=$1`,[previous.id])).rows[0]??previous);
  reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 // Renommer garde l'identité : séries passées et accomplissements restent liés. Les types prédéfinis ne se modifient pas.
 app.patch(`${base}/course-types/:typeId`,{bodyLimit:8_192},async(r,reply)=>{
  const body=typeBody.parse(r.body),schoolId=schoolID(r),typeId=z.object({typeId:id}).parse(r.params).typeId,expected=requireVersion(r.headers['if-match']);
  const data=await command<CourseType>(r,'UPDATE_COURSE_TYPE',{...body,typeId},expected,async db=>{
   const old=(await db.query<CourseType>(`SELECT ${typeColumns} FROM drivy.course_type WHERE id=$1 AND (school_id IS NULL OR school_id=$2)`,[typeId,schoolId])).rows[0];
   if(!old)throw notFound();if(old.predefined)throw new ApiError(409,'COURSE_TYPE_PREDEFINED','Les types prédéfinis ne se modifient pas.');
   await db.query('SELECT 1 FROM drivy.course_type WHERE id=$1 FOR UPDATE',[typeId]);checkVersion(old.version,expected);
   const row=(await db.query<CourseType>(`UPDATE drivy.course_type SET title=$2,description=$3,version=version+1 WHERE id=$1 RETURNING ${typeColumns}`,[typeId,body.title,body.description])).rows[0]!;
   return {data:row,action:'CourseTypeUpdated',resourceType:'CourseType',resourceId:row.id,changedFields:['title','description']};
  },async(db,previous)=>(await db.query<CourseType>(`SELECT ${typeColumns} FROM drivy.course_type WHERE id=$1`,[previous.id])).rows[0]??previous);
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Conditions d'annulation de l'école. Chaque changement crée une version ; les séries publiées et inscriptions gardent la leur.
 app.put(`${base}/course-policy`,{bodyLimit:2_048},async(r,reply)=>{
  const body=policyBody.parse(r.body),schoolId=schoolID(r),expected=requireVersion(r.headers['if-match']);
  const data=await command<CoursePolicy>(r,'SAVE_COURSE_POLICY',body,expected,async(db,actor)=>{
   const old=await currentPolicy(db,schoolId);checkVersion(old.version,expected);
   const row=(await db.query<CoursePolicy>(`INSERT INTO drivy.course_policy_version(school_id,version,self_cancel_hours,offer_response_minutes,created_by) VALUES($1,$2,$3,$4,$5)
    RETURNING version,self_cancel_hours AS "selfCancelHours",offer_response_minutes AS "offerResponseMinutes"`,[schoolId,old.version+1,body.selfCancelHours,body.offerResponseMinutes,actor.membershipId])).rows[0]!;
   return {data:row,action:'CoursePolicySaved',resourceType:'CoursePolicy',resourceId:schoolId,resourceVersion:row.version,changedFields:['selfCancelHours','offerResponseMinutes']};
  },async db=>currentPolicy(db,schoolId));
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Agenda : séries dont une séance touche la fenêtre. La RLS masque les brouillons à qui ne gère pas les cours.
 app.get(`${base}/course-series`,async r=>{
  const query=listQuery.parse(r.query),schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  if(query.from&&query.to&&Date.parse(query.to)<=Date.parse(query.from))throw new ApiError(400,'INVALID_REQUEST','Fenêtre invalide.');
  return envelope(await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
   if(!member)throw forbidden();
   const rows=(await db.query<SeriesRow>(`${seriesSelect} WHERE s.school_id=$1 AND ($2::text IS NULL OR s.status=$2)
    AND EXISTS(SELECT 1 FROM drivy.course_occurrence o WHERE o.series_id=s.id AND ($3::timestamptz IS NULL OR o.ends_at>$3) AND ($4::timestamptz IS NULL OR o.starts_at<$4))
    ORDER BY (SELECT min(starts_at) FROM drivy.course_occurrence o WHERE o.series_id=s.id),s.id LIMIT 200`,[schoolId,query.status??null,query.from??null,query.to??null])).rows;
   return {items:await project(db,rows,await canManageCourses(db,schoolId))};
  }),r);
 });
 app.get(`${base}/course-series/:seriesId`,async(r,reply)=>{
  empty.parse(r.query);const schoolId=schoolID(r),seriesId=z.object({seriesId:id}).parse(r.params).seriesId,identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,_a,member)=>{if(!member)throw forbidden();return getSeries(db,schoolId,seriesId);});
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Brouillon : invisible des élèves, sans occupation d'agenda. Les conditions courantes y sont copiées.
 app.post(`${base}/course-series`,{bodyLimit:64_000},async(r,reply)=>{
  const body=seriesBody.parse(r.body),schoolId=schoolID(r);
  const data=await command<CourseSeries>(r,'CREATE_COURSE_SERIES',body,null,async(db,actor,school)=>{
   const sorted=await validateSeries(db,school,body),policy=await currentPolicy(db,schoolId);
   const created=(await db.query<{id:string}>(`INSERT INTO drivy.course_series(school_id,type_id,title,description,location,conditions,teaching_language,responsible_membership_id,capacity,
    min_participants,policy_version,self_cancel_hours,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
    [schoolId,body.typeId,body.title,body.description,body.location,body.conditions,body.teachingLanguage,body.responsibleMembershipId,body.capacity,body.minParticipants,
     policy.version,policy.selfCancelHours,actor.membershipId])).rows[0]!;
   await writeOccurrences(db,schoolId,created.id,sorted,school.timeZone);
   return {data:await getSeries(db,schoolId,created.id),action:'CourseSeriesCreated',resourceType:'CourseSeries',resourceId:created.id,changedFields:['draft']};
  },async(db,previous)=>getSeries(db,schoolId,previous.id),['COURSE_OCCURRENCES_OVERLAP','Deux séances de ce cours se chevauchent.']);
  reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.put(`${base}/course-series/:seriesId`,{bodyLimit:64_000},async(r,reply)=>{
  const body=seriesBody.parse(r.body),schoolId=schoolID(r),seriesId=z.object({seriesId:id}).parse(r.params).seriesId,expected=requireVersion(r.headers['if-match']);
  const data=await command<CourseSeries>(r,'UPDATE_COURSE_SERIES',{...body,seriesId},expected,async(db,_actor,school)=>{
   const old=await getSeries(db,schoolId,seriesId,true);checkVersion(old.version,expected);
   // Une série publiée change par #41 (déplacement, annulation) et par la capacité, jamais par la réécriture du brouillon.
   if(old.status!=='DRAFT')throw new ApiError(409,'COURSE_NOT_DRAFT','Seul un brouillon se modifie ainsi.');
   const sorted=await validateSeries(db,school,body),policy=await currentPolicy(db,schoolId);
   await db.query(`UPDATE drivy.course_series SET version=version+1,type_id=$3,title=$4,description=$5,location=$6,conditions=$7,teaching_language=$8,responsible_membership_id=$9,
    capacity=$10,min_participants=$11,policy_version=$12,self_cancel_hours=$13,updated_at=now() WHERE school_id=$1 AND id=$2`,
    [schoolId,seriesId,body.typeId,body.title,body.description,body.location,body.conditions,body.teachingLanguage,body.responsibleMembershipId,body.capacity,body.minParticipants,policy.version,policy.selfCancelHours]);
   await writeOccurrences(db,schoolId,seriesId,sorted,school.timeZone);
   return {data:await getSeries(db,schoolId,seriesId),action:'CourseSeriesUpdated',resourceType:'CourseSeries',resourceId:seriesId,changedFields:['draft']};
  },async(db,previous)=>getSeries(db,schoolId,previous.id),['COURSE_OCCURRENCES_OVERLAP','Deux séances de ce cours se chevauchent.']);
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Publication : relit tout sous verrou, refuse le passé, occupe chaque formateur dans drivy.reservation. L'exclusion PostgreSQL
 // tranche les conflits avec leçons et autres cours, y compris sous concurrence. Aucune inscription n'est créée.
 app.post(`${base}/course-series/:seriesId/publish`,{bodyLimit:1_024},async(r,reply)=>{
  const body=publishBody.parse(r.body),schoolId=schoolID(r),seriesId=z.object({seriesId:id}).parse(r.params).seriesId,expected=requireVersion(r.headers['if-match']);
  const data=await command<CourseSeries>(r,'PUBLISH_COURSE_SERIES',{...body,seriesId},expected,async(db,_actor,school)=>{
   const old=await getSeries(db,schoolId,seriesId,true);checkVersion(old.version,expected);
   if(old.status!=='DRAFT')throw new ApiError(409,'COURSE_NOT_DRAFT','Ce cours est déjà publié.');
   if(!old.occurrences.length)throw new ApiError(422,'COURSE_OCCURRENCES_REQUIRED','Ajoutez au moins une séance.');
   if(Date.parse(old.firstStartsAt)<=Date.now())throw new ApiError(422,'COURSE_IN_PAST','La première séance est déjà passée.');
   const instructors=new Set((await db.query<{membership_id:string}>('SELECT membership_id FROM drivy.course_instructors($1)',[schoolId])).rows.map(row=>row.membership_id));
   if(old.occurrences.some(o=>!instructors.has(o.instructorMembershipId)))throw new ApiError(422,'INSTRUCTOR_NOT_ACTIVE','Un moniteur de ce cours n’est plus actif.');
   if(old.occurrences.some(o=>o.timeZone!==school.timeZone))throw new ApiError(422,'INVALID_TIME_ZONE','Le fuseau de l’école a changé. Relisez les séances.');
   for(const o of old.occurrences)await db.query(`INSERT INTO drivy.reservation(school_id,course_occurrence_id,resource_id,resource_role,during)
    SELECT $1,$2,m.person_id,'INSTRUCTOR',tstzrange($3::timestamptz,$4::timestamptz,'[)') FROM drivy.membership m WHERE m.school_id=$1 AND m.id=$5`,[schoolId,o.id,o.startsAt,o.endsAt,o.instructorMembershipId]);
   const policy=await currentPolicy(db,schoolId);
   const row=(await db.query<{version:number}>(`UPDATE drivy.course_series SET status='PUBLISHED',published_at=now(),version=version+1,policy_version=$3,self_cancel_hours=$4,updated_at=now()
    WHERE school_id=$1 AND id=$2 RETURNING version`,[schoolId,seriesId,policy.version,policy.selfCancelHours])).rows[0]!;
   await db.query(`INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,operation_id) VALUES($1,$2,$3,'CourseSeriesPublished',$4)`,[schoolId,seriesId,row.version,body.operationId]);
   return {data:await getSeries(db,schoolId,seriesId),action:'CourseSeriesPublished',resourceType:'CourseSeries',resourceId:seriesId,changedFields:['status']};
  },async(db,previous)=>getSeries(db,schoolId,previous.id),['COURSE_INSTRUCTOR_CONFLICT','Un moniteur a déjà un rendez-vous pendant une séance. Le brouillon est conservé.']);
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });

 // Capacité d'une série publiée : jamais sous les places occupées (inscriptions + propositions actives), relu sous verrou.
 app.post(`${base}/course-series/:seriesId/capacity`,{bodyLimit:1_024},async(r,reply)=>{
  const body=capacityBody.parse(r.body),schoolId=schoolID(r),seriesId=z.object({seriesId:id}).parse(r.params).seriesId,expected=requireVersion(r.headers['if-match']);
  const data=await command<CourseSeries>(r,'CHANGE_COURSE_CAPACITY',{...body,seriesId},expected,async db=>{
   const old=await getSeries(db,schoolId,seriesId,true);checkVersion(old.version,expected);
   if(old.status!=='PUBLISHED')throw new ApiError(409,'COURSE_NOT_PUBLISHED','La capacité d’un brouillon se règle dans le brouillon.');
   if(body.capacity<old.seatsTaken)throw new ApiError(409,'COURSE_CAPACITY_BELOW_TAKEN','La capacité ne peut pas descendre sous les places déjà prises.');
   if(old.minParticipants!==null&&body.capacity<old.minParticipants)throw new ApiError(422,'COURSE_CAPACITY_BELOW_MINIMUM','La capacité doit rester au moins égale au minimum.');
   await db.query('UPDATE drivy.course_series SET capacity=$3,version=version+1,updated_at=now() WHERE school_id=$1 AND id=$2',[schoolId,seriesId,body.capacity]);
   return {data:await getSeries(db,schoolId,seriesId),action:'CourseCapacityChanged',resourceType:'CourseSeries',resourceId:seriesId,changedFields:['capacity']};
  },async(db,previous)=>getSeries(db,schoolId,previous.id));
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}
