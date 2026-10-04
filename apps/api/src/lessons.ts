import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {schoolCommand,schoolColumns,checkIdempotency,checkVersion,requireVersion,type CommandActor,type CommandGuards,type SchoolRow} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {Cursors} from './cursor.js';
import {ensureOpen,instructorPermission} from './lesson-setup.js';
const id=z.uuid(),date=z.iso.datetime({offset:true}),amount=z.number().int().min(0).max(Number.MAX_SAFE_INTEGER),empty=z.object({}).strict();
const selection=z.object({mode:z.enum(['UNIT_PRICE','ENTITLEMENT']),serviceProductVersionId:id,quantity:z.number().int().min(1).max(100),entitlementLotId:id.nullable(),acceptedTermsVersionId:id}).strict()
 .refine(v=>v.mode==='UNIT_PRICE'?v.entitlementLotId===null:v.entitlementLotId!==null);
const interval={plannedStart:date,plannedEnd:date,timeZone:z.string().min(1).max(100),meetingPoint:z.string().trim().max(500).nullish().transform(value=>value??''),instructorMembershipId:id};
const createCommand=z.object({operationId:id,trainingId:id,...interval,agreedPriceCents:amount,bufferMinutes:z.number().int().min(0).max(240),policyVersionId:id,commercialSelection:selection}).strict();
const commercialChange=z.object({commercialSelection:selection,agreedPriceCents:amount,expectedAccountVersion:z.number().int().positive().nullable(),reason:z.string().trim().min(1).max(1000)}).strict();
const startNowCommand=z.object({operationId:id,trainingId:id,meetingPoint:z.string().trim().max(500).nullable().optional()}).strict();
const moveCommand=z.object({operationId:id,...interval,agreementConfirmed:z.literal(true),reason:z.string().max(1000).nullable().optional(),commercialChange:commercialChange.optional()}).strict();
const cancelCommand=z.object({operationId:id,reasonCode:z.enum(['LEARNER_REQUEST','INSTRUCTOR_UNAVAILABLE','SCHOOL_CLOSURE','OTHER']),comment:z.string().max(1000).nullable().optional()}).strict();
const availabilityQuery=z.object({trainingId:id,instructorMembershipId:id,plannedStart:date,plannedEnd:date,
 timeZone:z.string().min(1).max(100),bufferMinutes:z.coerce.number().int().min(0).max(240),excludeLessonId:id.optional()}).strict();
type Selection=z.infer<typeof selection>;
export interface LessonRow {id:string;school_id:string;version:number;training_id:string;learner_id:string;learner_person_id:string;instructor_membership_id:string;
 planned_start:Date;planned_end:Date;time_zone:string;meeting_point:string;status:'PLANNED'|'COMPLETED'|'CANCELLED'|'NO_SHOW';price_cents_snapshot:string;buffer_minutes_snapshot:number;
 policy_version_id:string;commercial_selection:Selection;commercial_revision_version:number;actual_start:Date|null;actual_end:Date|null;publication_version:number;current_published_revision_id:string|null;permit_warning?:boolean;cancel_reason_code?:string|null;learner_display_name?:string|null;instructor_display_name?:string|null;capture_summary?:{hasCapture:boolean;syncState:string|null;publicationState:string}|null;_createdAt:string}
export function lessonProjection(row:LessonRow){return {id:row.id,schoolId:row.school_id,version:row.version,trainingId:row.training_id,learnerId:row.learner_id,instructorMembershipId:row.instructor_membership_id,learnerDisplayName:row.learner_display_name??'',instructorDisplayName:row.instructor_display_name??'',
 plannedStart:row.planned_start.toISOString(),plannedEnd:row.planned_end.toISOString(),timeZone:row.time_zone,meetingPoint:row.meeting_point,status:row.status,
 priceCentsSnapshot:Number(row.price_cents_snapshot),bufferMinutesSnapshot:row.buffer_minutes_snapshot,actualStart:row.actual_start?.toISOString()??null,actualEnd:row.actual_end?.toISOString()??null,
 permitWarning:row.permit_warning??true,publicationVersion:row.publication_version,currentPublishedRevisionId:row.current_published_revision_id,commercialSelection:row.commercial_selection,commercialRevisionVersion:row.commercial_revision_version,
 captureSummary:row.capture_summary ?? {hasCapture:false,syncState:null,publicationState:'NONE'}};}
type Lesson=ReturnType<typeof lessonProjection>;
/** R07 : l'avertissement de permis est relu à chaque projection (décision courante, catégorie, date locale de la leçon). */
/** Extension : les noms affichés (élève, moniteur) sont résolus par des fonctions qui revérifient le droit de lecture de la leçon. */
export const lessonColumns=`*,drivy.lesson_permit_warning(training_id,(planned_start AT TIME ZONE time_zone)::date) AS permit_warning,
 drivy.lesson_learner_name(school_id,training_id,instructor_membership_id,learner_id) AS learner_display_name,
 drivy.lesson_instructor_name(school_id,training_id,instructor_membership_id) AS instructor_display_name,
 (SELECT jsonb_build_object('hasCapture',true,'syncState',c.sync_state,'publicationState',c.publication_state)
  FROM drivy.capture_session c WHERE c.school_id=drivy.lesson.school_id AND c.lesson_id=drivy.lesson.id AND c.publication_state<>'DELETED'
  ORDER BY c.authorized_at DESC,c.id DESC LIMIT 1) AS capture_summary`;
export async function getLesson(db:PoolClient,schoolId:string,lessonId:string,lock=false):Promise<LessonRow>{
 const row=(await db.query<LessonRow>(`SELECT ${lessonColumns} FROM drivy.lesson WHERE school_id=$1 AND id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,lessonId])).rows[0];if(!row)throw notFound();return row;
}
async function access(db:PoolClient,trainingId:string,instructorId:string){
 if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_access($1,$2,true) AS ok',[trainingId,instructorId])).rows[0]?.ok)throw notFound();
}
async function learnerPerson(db:PoolClient,schoolId:string,trainingId:string){
 const row=(await db.query<{learner_id:string}>('SELECT learner_id FROM drivy.training WHERE school_id=$1 AND id=$2 AND drivy.catalogue_training_visible(id)',[schoolId,trainingId])).rows[0];if(!row)throw notFound();
 await db.query("SELECT set_config('app.learner_id',$1,true)",[row.learner_id]);const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;
 if(!person)throw notFound();return [person];
}
export function lessonCommandGuards(schoolId:string,target:{trainingId:string;instructorMembershipId:string}|{lessonId:string}):CommandGuards<Lesson>{return {
 additionalPersons:async db=>learnerPerson(db,schoolId,'trainingId'in target?target.trainingId:(await getLesson(db,schoolId,target.lessonId)).training_id),
 authorize:async db=>{const row='trainingId'in target?{training_id:target.trainingId,instructor_membership_id:target.instructorMembershipId}:await getLesson(db,schoolId,target.lessonId);await access(db,row.training_id,row.instructor_membership_id);},
 replay:async(db,_actor,previous)=>{await getLesson(db,schoolId,previous.id);return previous;}
};}
function validateInterval(body:{plannedStart:string;plannedEnd:string;timeZone:string},school:SchoolRow){
 let valid=false;try{new Intl.DateTimeFormat('fr',{timeZone:body.timeZone});valid=body.timeZone===school.timeZone;}catch{ /* Invalid zone is never coerced. */ }
 const minutes=(Date.parse(body.plannedEnd)-Date.parse(body.plannedStart))/60_000;
 if(!valid)throw new ApiError(422,'INVALID_TIME_ZONE','Utilisez le fuseau de l’école affiché.');
 if(!Number.isInteger(minutes)||minutes<1||minutes>480||Date.parse(body.plannedStart)<=Date.now())throw new ApiError(422,'INVALID_INTERVAL','Choisissez un créneau futur de 1 à 480 minutes.');
 return minutes;
}
interface TrainingContext {learner_id:string;person_id:string;category_code:string;policy_version_id:string;instructor_person_id:string}
async function trainingContext(db:PoolClient,school:SchoolRow,trainingId:string,instructorId:string,start:string,end:string):Promise<TrainingContext>{
 if(school.status!=='ACTIVE')throw new ApiError(409,'SCHOOL_NOT_ACTIVE','Activez l’école avant de planifier.');
 await access(db,trainingId,instructorId);
 if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_learner_active($1) AS ok',[trainingId])).rows[0]?.ok)throw new ApiError(422,'LEARNER_NOT_ACTIVE','Le compte élève doit avoir une appartenance active.');
 await instructorPermission(db,school.id,instructorId);
 const row=(await db.query<TrainingContext&{status:string;archived_at:Date|null;enabled:boolean;approved:boolean}>(`SELECT t.status,t.learner_id,l.person_id,l.archived_at,o.category_code,o.policy_version_id,o.enabled,p.approved,
 m.person_id AS instructor_person_id FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.id=$3 AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)
 WHERE t.school_id=$1 AND t.id=$2`,[school.id,trainingId,instructorId])).rows[0];
 if(!row)throw notFound();if(row.status!=='ACTIVE'||row.archived_at)throw new ApiError(422,'TRAINING_NOT_ACTIVE','La formation doit être active dans un dossier non archivé.');
 if(!row.enabled||!row.approved)throw new ApiError(422,'OFFERING_NOT_READY','L’offre et sa procédure doivent être approuvées.');
 const assigned=await db.query(`SELECT id FROM drivy.instructor_assignment WHERE school_id=$1 AND training_id=$2 AND instructor_membership_id=$3
 AND valid_from<=statement_timestamp() AND valid_from<=$4::timestamptz AND (valid_until IS NULL OR (valid_until>statement_timestamp() AND valid_until>=$5::timestamptz))`,[school.id,trainingId,instructorId,start,end]);
 if(!assigned.rowCount)throw new ApiError(422,'INSTRUCTOR_NOT_ASSIGNED','Le moniteur doit être actuellement affecté à cette formation et couvrir ce rendez-vous.');
 // Administrative fields are checked by need; no protected values are returned in errors.
 const policy=(await db.query<{fields:{field:string;requirement:string;stage:string}[]}>(`SELECT fields FROM drivy.profile_field_policy WHERE school_id=$1 AND status='PUBLISHED' AND effective_from<=now() ORDER BY effective_from DESC LIMIT 1`,[school.id])).rows[0];
 if(!policy)throw new ApiError(409,'PROFILE_POLICY_NOT_READY','Publiez la politique des informations nécessaires avant de planifier.');
 const profile=(await db.query<Record<string,unknown>>('SELECT first_name,last_name,birth_date,postal_address,contact_email,contact_phone FROM drivy.learner_profile WHERE school_id=$1 AND id=$2',[school.id,row.learner_id])).rows[0]!;
 const names:Record<string,string>={firstName:'first_name',lastName:'last_name',birthDate:'birth_date',postalAddress:'postal_address',contactEmail:'contact_email',contactPhone:'contact_phone'};
 if(policy.fields.some(rule=>rule.requirement==='REQUIRED'&&['JOIN','BEFORE_LESSON'].includes(rule.stage)&&(!names[rule.field]||profile[names[rule.field]!]==null||profile[names[rule.field]!] ==='')))throw new ApiError(409,'PROFILE_ACTION_REQUIRED','Complétez les informations requises du dossier avant de planifier.');
 return row;
}
async function validateCommercial(db:PoolClient,schoolId:string,commercial:Selection,price:number,category:string,minutes:number,start:string,timeZone:string,allowOverride:boolean){
 if(commercial.mode!=='UNIT_PRICE')throw new ApiError(409,'ENTITLEMENT_NOT_READY','La réservation de droits de pack doit être disponible avant d’utiliser ce mode.');
 const row=(await db.query<{duration_minutes:number|null;unit_price_cents:string;terms_version_id:string}>(`SELECT s.duration_minutes,s.unit_price_cents,s.terms_version_id FROM drivy.service_product_version s
 JOIN drivy.commercial_terms_version t ON t.school_id=s.school_id AND t.id=s.terms_version_id WHERE s.school_id=$1 AND s.id=$2 AND s.type='INDIVIDUAL_LESSON'
 AND s.enabled AND s.category_code=$3 AND s.site_id IS NULL AND drivy.service_product_current(s.id) AND s.valid_from<=($4::timestamptz AT TIME ZONE $5)::date
 AND (s.valid_until IS NULL OR s.valid_until>=($4::timestamptz AT TIME ZONE $5)::date) AND t.approved
 AND t.valid_from<=($4::timestamptz AT TIME ZONE $5)::date AND (t.valid_until IS NULL OR t.valid_until>=($4::timestamptz AT TIME ZONE $5)::date)`,[schoolId,commercial.serviceProductVersionId,category,start,timeZone])).rows[0];
 if(!row||row.terms_version_id!==commercial.acceptedTermsVersionId)throw new ApiError(422,'COMMERCIAL_SELECTION_INVALID','Relisez la prestation et ses conditions commerciales applicables.');
 if(!row.duration_minutes||row.duration_minutes*commercial.quantity!==minutes)throw new ApiError(422,'COMMERCIAL_QUANTITY_MISMATCH','La quantité doit correspondre à la durée du produit choisi.');
 const catalog=BigInt(row.unit_price_cents)*BigInt(commercial.quantity);
 if(catalog>BigInt(Number.MAX_SAFE_INTEGER))throw new ApiError(422,'INVALID_AMOUNT','Le montant dépasse la limite acceptée.');
 if(BigInt(price)!==catalog&&!allowOverride)throw new ApiError(422,'PRICE_OVERRIDE_REQUIRED','Le prix doit correspondre à la prestation. Une exception nécessite un motif et un accord explicites.');
}
interface NewLesson {trainingId:string;instructorId:string;start:string;end:string;meetingPoint:string;priceCents:number;bufferMinutes:number;policyVersionId:string;selection:Selection}
async function insertLesson(db:PoolClient,school:SchoolRow,context:TrainingContext,value:NewLesson){
 return (await db.query<LessonRow>(`INSERT INTO drivy.lesson(id,school_id,training_id,learner_id,learner_person_id,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,price_cents_snapshot,buffer_minutes_snapshot,policy_version_id,commercial_selection)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING ${lessonColumns}`,[randomUUID(),school.id,value.trainingId,context.learner_id,context.person_id,value.instructorId,value.start,value.end,school.timeZone,value.meetingPoint,value.priceCents,value.bufferMinutes,value.policyVersionId,JSON.stringify(value.selection)])).rows[0]!;
}
/** Prestation de leçon en vigueur (dernière version, conditions approuvées) dont la durée divise celle de la séance ; la durée exacte est préférée. */
async function currentLessonProduct(db:PoolClient,schoolId:string,category:string,minutes:number,start:string,timeZone:string,membershipId:string){
 const row=(await db.query<{id:string;duration_minutes:number;unit_price_cents:string;terms_version_id:string}>(`SELECT s.id,s.duration_minutes,s.unit_price_cents,s.terms_version_id FROM drivy.service_product_version s
  JOIN drivy.commercial_terms_version t ON t.school_id=s.school_id AND t.id=s.terms_version_id WHERE s.school_id=$1 AND s.type='INDIVIDUAL_LESSON' AND s.enabled AND s.category_code=$2 AND s.site_id IS NULL
  AND drivy.service_product_current(s.id) AND s.duration_minutes IS NOT NULL AND $3::int % s.duration_minutes=0
  AND s.valid_from<=($4::timestamptz AT TIME ZONE $5)::date AND (s.valid_until IS NULL OR s.valid_until>=($4::timestamptz AT TIME ZONE $5)::date) AND t.approved
  AND t.valid_from<=($4::timestamptz AT TIME ZONE $5)::date AND (t.valid_until IS NULL OR t.valid_until>=($4::timestamptz AT TIME ZONE $5)::date)
  ORDER BY coalesce(s.product_key=(SELECT service_product_key FROM drivy.planning_defaults WHERE school_id=$1 AND membership_id=$6),false) DESC,
   (s.duration_minutes=$3::int) DESC,s.duration_minutes DESC,s.unit_price_cents,s.product_key LIMIT 1`,[schoolId,category,minutes,start,timeZone,membershipId])).rows[0];
 if(!row)throw new ApiError(409,'COMMERCIAL_SETUP_REQUIRED','Préparez une prestation de leçon et ses conditions approuvées pour cette catégorie.');
 return row;
}
async function occupations(db:PoolClient,row:LessonRow,instructorPersonId:string){
 await db.query(`INSERT INTO drivy.reservation(school_id,lesson_id,resource_id,resource_role,during)
 VALUES($1,$2,$3,'LEARNER',tstzrange($5::timestamptz,$6::timestamptz,'[)')),
 ($1,$2,$4,'INSTRUCTOR',tstzrange($5::timestamptz,$6::timestamptz+make_interval(mins=>$7),'[)'))`,
 [row.school_id,row.id,row.learner_person_id,instructorPersonId,row.planned_start,row.planned_end,row.buffer_minutes_snapshot]);
}
/** Release only the future; preserve any elapsed part as an immutable occupation. */
export async function releaseFutureOccupations(db:PoolClient,schoolId:string,lessonId:string){
 await db.query(`WITH released AS (
  UPDATE drivy.reservation SET active=false WHERE school_id=$1 AND lesson_id=$2 AND active AND upper(during)>statement_timestamp()
  RETURNING school_id,lesson_id,resource_id,resource_role,during)
  INSERT INTO drivy.reservation(school_id,lesson_id,resource_id,resource_role,during)
  SELECT school_id,lesson_id,resource_id,resource_role,tstzrange(lower(during),statement_timestamp(),'[)') FROM released WHERE lower(during)<statement_timestamp()`,[schoolId,lessonId]);
}
/** Une issue sans réalisation possède un compte de leçon sans charge : aucune pénalité n'est déduite (R14/R23). */
export async function openClosedAccount(db:PoolClient,row:LessonRow){
 await db.query('INSERT INTO drivy.lesson_account(school_id,lesson_id,planned_price_cents) VALUES($1,$2,$3) ON CONFLICT (lesson_id) DO NOTHING',[row.school_id,row.id,row.price_cents_snapshot]);
}
export async function event(db:PoolClient,row:LessonRow,operationId:string,type:string){await db.query(`INSERT INTO drivy.lesson_event_outbox(school_id,lesson_id,lesson_version,event_type,operation_id) VALUES($1,$2,$3,$4,$5)`,[row.school_id,row.id,row.version,type,operationId]);}
async function revision(db:PoolClient,row:LessonRow,actor:CommandActor,operationId:string,reason:string){await db.query(`INSERT INTO drivy.lesson_commercial_revision(school_id,lesson_id,revision,operation_id,commercial_selection,price_cents,duration_minutes,actor_membership_id,reason)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[row.school_id,row.id,row.commercial_revision_version,operationId,JSON.stringify(row.commercial_selection),row.price_cents_snapshot,(row.planned_end.getTime()-row.planned_start.getTime())/60000,actor.membershipId,reason]);}

/** General entry prerequisites; the chosen slot and price are rechecked by AP40. */
export async function planningReadiness(db:PoolClient,schoolId:string,learnerId:string,trainingId:string|undefined,roles:string[]){
 const problem=(code:string,message:string)=>[{code,message,field:null,purpose:null,resourceId:trainingId??null,destinationKey:'TRAINING'}];
 if(!roles.some(role=>role==='ADMIN'||role==='INSTRUCTOR'))return problem('PLANNING_ACCESS_REQUIRED','La planification est effectuée par l’administration ou le moniteur affecté.');
 const assignment=`a.school_id=t.school_id AND a.training_id=t.id AND a.valid_from<=statement_timestamp()
  AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp()) AND drivy.lesson_instructor_manage(t.school_id,a.instructor_membership_id)`;
 const rows=(await db.query<{active:boolean;learner_active:boolean;offering_ready:boolean;assigned:boolean;opened:boolean;product:boolean}>(`SELECT t.status='ACTIVE' AS active,
  drivy.lesson_learner_active(t.id) AS learner_active,o.enabled AND p.approved AS offering_ready,
  EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE ${assignment}) AS assigned,
  EXISTS(SELECT 1 FROM drivy.instructor_assignment a JOIN drivy.availability_rule r ON r.school_id=a.school_id AND r.instructor_membership_id=a.instructor_membership_id
   WHERE ${assignment} AND r.removed_at IS NULL AND (r.valid_until IS NULL OR r.valid_until>=(now() AT TIME ZONE sc.time_zone)::date)) AS opened,
  EXISTS(SELECT 1 FROM drivy.service_product_version s JOIN drivy.commercial_terms_version c ON c.school_id=s.school_id AND c.id=s.terms_version_id
   WHERE s.school_id=t.school_id AND s.type='INDIVIDUAL_LESSON' AND s.enabled AND s.category_code=o.category_code AND s.site_id IS NULL AND drivy.service_product_current(s.id) AND c.approved
   AND (s.valid_until IS NULL OR s.valid_until>=(now() AT TIME ZONE sc.time_zone)::date) AND (c.valid_until IS NULL OR c.valid_until>=(now() AT TIME ZONE sc.time_zone)::date)
   AND (s.valid_until IS NULL OR s.valid_until>=c.valid_from) AND (c.valid_until IS NULL OR c.valid_until>=s.valid_from)) AS product
  FROM drivy.training t JOIN drivy.school sc ON sc.id=t.school_id JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
  LEFT JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id
  WHERE t.school_id=$1 AND t.learner_id=$2 AND ($3::uuid IS NULL OR t.id=$3) AND drivy.catalogue_training_visible(t.id)`,[schoolId,learnerId,trainingId??null])).rows;
 let candidates=rows.filter(row=>row.active);if(!candidates.length)return problem('TRAINING_NOT_ACTIVE','Choisissez une formation active pour ce dossier.');
 candidates=candidates.filter(row=>row.learner_active);if(!candidates.length)return problem('LEARNER_NOT_ACTIVE','L’élève doit avoir une appartenance active.');
 candidates=candidates.filter(row=>row.offering_ready);if(!candidates.length)return problem('OFFERING_NOT_READY','La formation nécessite une offre active et une procédure approuvée.');
 candidates=candidates.filter(row=>row.assigned);if(!candidates.length)return problem('INSTRUCTOR_NOT_ASSIGNED','Affectez un moniteur actif à cette formation.');
 candidates=candidates.filter(row=>row.opened);if(!candidates.length)return problem('AVAILABILITY_REQUIRED','Renseignez les ouvertures du moniteur avant de choisir un créneau.');
 if(!candidates.some(row=>row.product))return problem('COMMERCIAL_SETUP_REQUIRED','Préparez une prestation et ses conditions commerciales approuvées pour cette catégorie.');
 return [];
}
/** Prérequis de planification au niveau de l'école (capacité CAN_PLAN_LESSON) : ce qui manque, sans choisir d'élève. Les dates
 * civiles sont celles du fuseau de l'école. Appelé par un ADMIN actif ; les fonctions de portée relisent ses droits. */
export async function schoolPlanningBlockers(db:PoolClient,schoolId:string){
 const missing=(code:string,message:string,destinationKey:string)=>({code,message,field:null,purpose:null,resourceId:null,destinationKey});
 const row=(await db.query<{offering:boolean;instructor:boolean;availability:boolean;product:boolean;profile_policy:boolean}>(`WITH today AS (
   SELECT (now() AT TIME ZONE time_zone)::date AS d FROM drivy.school WHERE id=$1),
  ready AS (SELECT o.category_code FROM drivy.offering_version o WHERE o.school_id=$1 AND drivy.catalogue_offering_ready(o.id))
  SELECT EXISTS(SELECT 1 FROM ready) AS offering,
  EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
   WHERE m.school_id=$1 AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)) AS instructor,
  EXISTS(SELECT 1 FROM drivy.availability_rule r JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.instructor_membership_id
   JOIN drivy.person p ON p.id=m.person_id CROSS JOIN today
   WHERE r.school_id=$1 AND r.removed_at IS NULL AND (r.valid_until IS NULL OR r.valid_until>=today.d)
   AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)) AS availability,
  EXISTS(SELECT 1 FROM drivy.service_product_version s JOIN drivy.commercial_terms_version c ON c.school_id=s.school_id AND c.id=s.terms_version_id CROSS JOIN today
   WHERE s.school_id=$1 AND s.type='INDIVIDUAL_LESSON' AND s.enabled AND s.site_id IS NULL AND drivy.service_product_current(s.id) AND c.approved
   AND s.category_code IN(SELECT category_code FROM ready) AND (s.valid_until IS NULL OR s.valid_until>=today.d) AND (c.valid_until IS NULL OR c.valid_until>=today.d)) AS product,
  EXISTS(SELECT 1 FROM drivy.profile_field_policy f WHERE f.school_id=$1 AND f.status='PUBLISHED' AND f.effective_from<=now()) AS profile_policy`,[schoolId])).rows[0]!;
 return [
  ...(row.offering?[]:[missing('OFFERING_REQUIRED','Activez une offre dont le référentiel et la procédure sont approuvés.','OFFERINGS')]),
  ...(row.instructor?[]:[missing('INSTRUCTOR_REQUIRED','Ajoutez au moins un moniteur actif.','TEAM')]),
  ...(row.availability?[]:[missing('AVAILABILITY_REQUIRED','Renseignez les disponibilités d’au moins un moniteur actif.','AVAILABILITY')]),
  ...(row.product?[]:[missing('COMMERCIAL_SETUP_REQUIRED','Préparez une prestation de leçon en vigueur, avec des conditions approuvées, pour la catégorie de l’offre.','COMMERCIAL')]),
  ...(row.profile_policy?[]:[missing('PROFILE_POLICY_NOT_READY','Publiez la politique des informations nécessaires.','PROFILE_POLICY')])
 ];
}
export function registerLessons(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string}){
 const base='/v1/schools/:schoolId',cursors=new Cursors(options.cursorSecret),schoolID=(r:FastifyRequest)=>z.object({schoolId:id}).parse(r.params).schoolId;
  const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
  // Lecture indicative avant le tarif : les occupations privées ne quittent jamais le serveur.
  // Aucun créneau n'est retenu ; CREATE/MOVE rejouent toutes les validations sous leurs verrous.
  app.get(`${base}/lessons/availability`,async r=>{
   const query=availabilityQuery.parse(r.query),schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
   const data=await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
    if(!member?.roles.some(role=>role==='ADMIN'||role==='INSTRUCTOR'))throw forbidden();
    const school=(await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1`,[schoolId])).rows[0];
    if(!school)throw notFound();
    validateInterval(query,school);
    await learnerPerson(db,schoolId,query.trainingId);
    await trainingContext(db,school,query.trainingId,query.instructorMembershipId,query.plannedStart,query.plannedEnd);
    if(query.excludeLessonId){
     const original=await getLesson(db,schoolId,query.excludeLessonId);
     await access(db,original.training_id,original.instructor_membership_id);
     if(original.training_id!==query.trainingId)throw notFound();
     if(original.status!=='PLANNED')throw new ApiError(409,'LESSON_CLOSED','Seule une leçon planifiée peut être déplacée.');
     if(original.planned_start.getTime()<=Date.now()||original.actual_start)throw new ApiError(409,'LESSON_STARTED','La leçon a déjà commencé.');
     if(original.buffer_minutes_snapshot!==query.bufferMinutes)throw new ApiError(422,'INVALID_INTERVAL','Le déplacement conserve l’intervalle de la leçon.');
    }
    try{await ensureOpen(db,schoolId,query.instructorMembershipId,query.plannedStart,query.plannedEnd,query.timeZone);}
    catch(error){if(error instanceof ApiError&&error.code==='SLOT_UNAVAILABLE')return {available:false,reasonCode:'SLOT_UNAVAILABLE'};throw error;}
    const result=(await db.query<{conflict:boolean}>(`SELECT drivy.lesson_slot_conflict($1,$2,$3,$4,$5,$6,$7) AS conflict`,
     [schoolId,query.trainingId,query.instructorMembershipId,query.plannedStart,query.plannedEnd,query.bufferMinutes,query.excludeLessonId??null])).rows[0];
    if(typeof result?.conflict!=='boolean')throw new ApiError(503,'SERVICE_UNAVAILABLE','Le créneau n’a pas pu être vérifié.');
    return {available:!result.conflict,reasonCode:result.conflict?'SLOT_CONFLICT':null};
   });return envelope(data,r);
  });
  app.get(`${base}/lessons`,async r=>{
  const query=z.object({from:date.optional(),to:date.optional(),trainingId:id.optional(),instructorMembershipId:id.optional(),limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict().parse(r.query);
  if(query.from&&query.to&&Date.parse(query.to)<=Date.parse(query.from))throw new ApiError(422,'INVALID_INTERVAL','La fenêtre de planning est invalide.');
  const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   if(!member)throw forbidden();const scope=JSON.stringify(['lessons',schoolId,actor.personId,member.accessEpoch,{...query,cursor:undefined}]);const position=cursors.decode(query.cursor,scope);
   const values:unknown[]=[schoolId],where=['school_id=$1'],bind=(v:unknown)=>{values.push(v);return `$${values.length}`;};
   if(query.from)where.push(`planned_end>${bind(query.from)}::timestamptz`);if(query.to)where.push(`planned_start<${bind(query.to)}::timestamptz`);
   if(query.trainingId)where.push(`training_id=${bind(query.trainingId)}`);if(query.instructorMembershipId)where.push(`instructor_membership_id=${bind(query.instructorMembershipId)}`);
   if(position)where.push(`(planned_start,id)>(${bind(position.createdAt)}::timestamptz,${bind(position.id)}::uuid)`);
   const rows=(await db.query<LessonRow>(`SELECT ${lessonColumns},to_char(planned_start AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.lesson WHERE ${where.join(' AND ')} ORDER BY planned_start,id LIMIT ${bind(query.limit+1)}`,values)).rows;
   const last=rows.length>query.limit?rows[query.limit-1]:undefined;return {items:rows.slice(0,query.limit).map(lessonProjection),nextCursor:last?cursors.encode(scope,{id:last.id,createdAt:last._createdAt}):null};
  });return envelope(data,r);
 });
 app.get(`${base}/lessons/:lessonId`,async(r,reply)=>{
  empty.parse(r.query);const schoolId=schoolID(r),lessonId=z.object({lessonId:id}).parse(r.params).lessonId,identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async db=>lessonProjection(await getLesson(db,schoolId,lessonId)));reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 const slotConflict=(error:unknown,message='Ce créneau n’est plus disponible. Vos autres informations sont conservées.'):never=>{if(typeof error==='object'&&error!==null&&'code'in error&&error.code==='23P01')throw new ApiError(409,'SLOT_CONFLICT',message);throw error;};
 const command=async(r:FastifyRequest,type:string,body:{operationId:string},expected:number|null,target:Parameters<typeof lessonCommandGuards>[1],work:Parameters<typeof schoolCommand<Lesson>>[6])=>{
  empty.parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  try{return await schoolCommand(options.pool,identity,schoolId,type,body,expected,work,['ADMIN','INSTRUCTOR'],lessonCommandGuards(schoolId,target));}
  catch(error){return slotConflict(error);}
 };
 app.post(`${base}/lessons`,async(r,reply)=>{
  const body=createCommand.parse(r.body);
  const data=await command(r,'CREATE_LESSON',body,null,{trainingId:body.trainingId,instructorMembershipId:body.instructorMembershipId},async(db,actor,school)=>{
   const minutes=validateInterval(body,school),context=await trainingContext(db,school,body.trainingId,body.instructorMembershipId,body.plannedStart,body.plannedEnd);
   if(context.policy_version_id!==body.policyVersionId)throw new ApiError(422,'SCHOOL_POLICY_CHANGED','La procédure de cette formation doit être relue.');
   await validateCommercial(db,school.id,body.commercialSelection,body.agreedPriceCents,context.category_code,minutes,body.plannedStart,body.timeZone,false);
   await ensureOpen(db,school.id,body.instructorMembershipId,body.plannedStart,body.plannedEnd,body.timeZone);
   const row=await insertLesson(db,school,context,{trainingId:body.trainingId,instructorId:body.instructorMembershipId,start:body.plannedStart,end:body.plannedEnd,meetingPoint:body.meetingPoint,priceCents:body.agreedPriceCents,bufferMinutes:body.bufferMinutes,policyVersionId:body.policyVersionId,selection:body.commercialSelection});
   await occupations(db,row,context.instructor_person_id);await revision(db,row,actor,body.operationId,'Initial booking');await event(db,row,body.operationId,'LessonCreated');
   return {data:lessonProjection(row),resourceId:row.id,resourceType:'Lesson',action:'LessonCreated',changedFields:['plannedStart','plannedEnd','instructorMembershipId','meetingPoint','commercialSelection']};
  });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 /** Extension : le moniteur affecté démarre une leçon maintenant. Le serveur fixe le début exact, la durée de l'offre,
  * la prestation en vigueur au prix du catalogue, la procédure de la formation, le moniteur (l'appelant) et un tampon nul.
  * Les ouvertures du moniteur ne s'appliquent pas à lui-même ; les occupations (exclusion PostgreSQL) et tous les droits restent contrôlés. */
 /** Raison anonyme (contrat : aucun nom d’un autre rendez-vous), mais dite au moniteur en clair : la leçon dure toute la durée de l’offre. */
 const startNowConflictMessage='Toi ou l’élève avez un rendez-vous pendant la durée de cette leçon. Planifie-la à un autre moment.';
 app.post(`${base}/lessons/start-now`,async(r,reply)=>{
  empty.parse(r.query);const body=startNowCommand.parse(r.body);checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  const guards:CommandGuards<Lesson>={
   additionalPersons:db=>learnerPerson(db,schoolId,body.trainingId),
   authorize:async(db,actor)=>access(db,body.trainingId,actor.membershipId),
   replay:async(db,_actor,previous)=>{await getLesson(db,schoolId,previous.id);return previous;}
  };
  let data:Lesson;
  try{
   data=await schoolCommand<Lesson>(options.pool,identity,schoolId,'START_LESSON_NOW',body,null,async(db,actor,school)=>{
    const start=new Date();
    const offer=(await db.query<{default_duration_minutes:number|null}>(`SELECT o.default_duration_minutes FROM drivy.training t JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id WHERE t.school_id=$1 AND t.id=$2`,[school.id,body.trainingId])).rows[0];
    if(!offer)throw notFound();if(!offer.default_duration_minutes)throw new ApiError(422,'OFFERING_NOT_READY','L’offre doit indiquer la durée d’une leçon.');
    const minutes=offer.default_duration_minutes,end=new Date(start.getTime()+minutes*60_000),startIso=start.toISOString(),endIso=end.toISOString();
    const context=await trainingContext(db,school,body.trainingId,actor.membershipId,startIso,endIso);
    const product=await currentLessonProduct(db,school.id,context.category_code,minutes,startIso,school.timeZone,actor.membershipId);
    const quantity=minutes/product.duration_minutes,catalog=BigInt(product.unit_price_cents)*BigInt(quantity);
    if(catalog>BigInt(Number.MAX_SAFE_INTEGER))throw new ApiError(422,'INVALID_AMOUNT','Le montant dépasse la limite acceptée.');
    const selection:Selection={mode:'UNIT_PRICE',serviceProductVersionId:product.id,quantity,entitlementLotId:null,acceptedTermsVersionId:product.terms_version_id};
    await validateCommercial(db,school.id,selection,Number(catalog),context.category_code,minutes,startIso,school.timeZone,false);
    const row=await insertLesson(db,school,context,{trainingId:body.trainingId,instructorId:actor.membershipId,start:startIso,end:endIso,meetingPoint:body.meetingPoint??'',priceCents:Number(catalog),bufferMinutes:0,policyVersionId:context.policy_version_id,selection});
    await occupations(db,row,context.instructor_person_id);await revision(db,row,actor,body.operationId,'Initial booking');await event(db,row,body.operationId,'LessonCreated');
    return {data:lessonProjection(row),resourceId:row.id,resourceType:'Lesson',action:'LessonStartedNow',changedFields:['plannedStart','plannedEnd','instructorMembershipId','meetingPoint','commercialSelection']};
   },['INSTRUCTOR'],guards);
  }catch(error){return slotConflict(error,startNowConflictMessage);}
  reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/lessons/:lessonId/move`,async(r,reply)=>{
  const body=moveCommand.parse(r.body),lessonId=z.object({lessonId:id}).parse(r.params).lessonId,expected=requireVersion(r.headers['if-match']);
  const boundCommand={...body,lessonId};
  const data=await command(r,'MOVE_LESSON',boundCommand,expected,{lessonId},async(db,actor,school)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);if(old.status!=='PLANNED')throw new ApiError(409,'LESSON_CLOSED','Seule une leçon planifiée peut être déplacée.');
   if(old.planned_start.getTime()<=Date.now()||old.actual_start)throw new ApiError(409,'LESSON_STARTED','Une leçon dont le début prévu est passé doit recevoir son constat ; son ancien créneau reste conservé.');
   const minutes=validateInterval(body,school),context=await trainingContext(db,school,old.training_id,body.instructorMembershipId,body.plannedStart,body.plannedEnd);
   const changed=minutes!==(old.planned_end.getTime()-old.planned_start.getTime())/60000;
   if(changed&&!body.commercialChange)throw new ApiError(422,'LESSON_COMMERCIAL_CHANGE_REQUIRED','Une nouvelle durée exige un accord commercial explicite.');
   if(body.commercialChange){
    if(old.planned_start.getTime()<=Date.now()||old.actual_start)throw new ApiError(409,'LESSON_COMMERCIAL_REVISION_CLOSED','Les conditions ne peuvent plus être révisées après le début prévu.');
    if(body.commercialChange.expectedAccountVersion!==null)throw new ApiError(409,'FINANCIAL_RECONCILIATION_REQUIRED','Le compte financier doit être rapproché avant cette révision.');
    await validateCommercial(db,school.id,body.commercialChange.commercialSelection,body.commercialChange.agreedPriceCents,context.category_code,minutes,body.plannedStart,body.timeZone,actor.roles.includes('ADMIN'));
   }
   await ensureOpen(db,school.id,body.instructorMembershipId,body.plannedStart,body.plannedEnd,body.timeZone);
   await db.query('UPDATE drivy.reservation SET active=false WHERE school_id=$1 AND lesson_id=$2 AND active',[school.id,lessonId]);
   const row=(await db.query<LessonRow>(`UPDATE drivy.lesson SET version=version+1,planned_start=$3,planned_end=$4,time_zone=$5,meeting_point=$6,instructor_membership_id=$7,
    commercial_selection=$8,price_cents_snapshot=$9,commercial_revision_version=commercial_revision_version+$10 WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,
    [school.id,lessonId,body.plannedStart,body.plannedEnd,body.timeZone,body.meetingPoint,body.instructorMembershipId,JSON.stringify(body.commercialChange?.commercialSelection??old.commercial_selection),body.commercialChange?.agreedPriceCents??Number(old.price_cents_snapshot),body.commercialChange?1:0])).rows[0]!;
   await occupations(db,row,context.instructor_person_id);if(body.commercialChange)await revision(db,row,actor,body.operationId,body.commercialChange.reason);await event(db,row,body.operationId,'LessonMoved');
   return {data:lessonProjection(row),resourceId:row.id,resourceType:'Lesson',action:'LessonMoved',changedFields:['plannedStart','plannedEnd','instructorMembershipId','meetingPoint',...(body.commercialChange?['commercialSelection','priceCentsSnapshot']:[])]};
  });reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/lessons/:lessonId/cancel`,async(r,reply)=>{
  const body=cancelCommand.parse(r.body),lessonId=z.object({lessonId:id}).parse(r.params).lessonId,expected=requireVersion(r.headers['if-match']);
  const boundCommand={...body,lessonId};
  const data=await command(r,'CANCEL_LESSON',boundCommand,expected,{lessonId},async(db,_actor,school)=>{
   const old=await getLesson(db,school.id,lessonId,true);checkVersion(old.version,expected);if(old.status!=='PLANNED')throw new ApiError(409,'LESSON_CLOSED','Cette leçon possède déjà un résultat.');
   const row=(await db.query<LessonRow>(`UPDATE drivy.lesson SET status='CANCELLED',version=version+1,cancel_reason_code=$3,cancel_comment=$4 WHERE school_id=$1 AND id=$2 RETURNING ${lessonColumns}`,[school.id,lessonId,body.reasonCode,body.comment??null])).rows[0]!;
   await releaseFutureOccupations(db,school.id,lessonId);await openClosedAccount(db,row);await event(db,row,body.operationId,'LessonCancelled');
   return {data:lessonProjection(row),resourceId:row.id,resourceType:'Lesson',action:'LessonCancelled',changedFields:['status']};
  });reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}

/** AP72 checks the current target without exposing stored command bodies. */
export async function authorizePlanningOperation(db:PoolClient,schoolId:string,type:string,resourceId:string):Promise<boolean>{
 if(type==='SAVE_PLANNING_DEFAULTS'){
  if(!(await db.query('SELECT 1 FROM drivy.planning_defaults WHERE school_id=$1 AND membership_id=$2',[schoolId,resourceId])).rowCount)throw notFound();
  return true;
 }
 if(['CREATE_LESSON','START_LESSON_NOW','MOVE_LESSON','CANCEL_LESSON'].includes(type)){
  const row=await getLesson(db,schoolId,resourceId);await access(db,row.training_id,row.instructor_membership_id);return true;
 }
 if(['CREATE_COMMERCIAL_TERMS','CREATE_SERVICE_PRODUCT'].includes(type)){
  if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_catalogue_manage($1) AS ok',[schoolId])).rows[0]?.ok)throw forbidden();return true;
 }
 const resources:Record<string,string>={CREATE_AVAILABILITY_RULE:'availability_rule',UPDATE_AVAILABILITY_RULE:'availability_rule',REMOVE_AVAILABILITY_RULE:'availability_rule',CREATE_CLOSURE:'closure',REMOVE_CLOSURE:'closure'};
 const table=resources[type];if(!table)return false;
 const row=(await db.query<{instructor_membership_id:string}>(`SELECT instructor_membership_id FROM drivy.${table} WHERE school_id=$1 AND id=$2`,[schoolId,resourceId])).rows[0];
 if(!row)throw notFound();await instructorPermission(db,schoolId,row.instructor_membership_id);return true;
}
