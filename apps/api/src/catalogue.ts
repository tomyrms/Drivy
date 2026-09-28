import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier,Identity} from './auth.js';
import {withActor,type Actor,type Membership} from './database.js';
import {schoolCommand,checkIdempotency,checkVersion,requireVersion,schoolColumns,type CommandGuards,type SchoolRow} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {Cursors} from './cursor.js';
import {getTraining} from './queries.js';
import {recordSettings} from './school-setup.js';

const empty=z.object({}).strict();const operation={operationId:z.uuid()};
const text=(max:number)=>z.string().trim().refine(value=>[...value].length>0 && [...value].length<=max);
const category=text(30);const roles=z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER'])).min(1).max(3).refine(v=>new Set(v).size===v.length);
const grants=z.array(z.enum(['permit_review','cash_record','CONFIGURE_CATALOG','SELL_SERVICES','MANAGE_COURSES','TAKE_ATTENDANCE','VALIDATE_REQUIREMENT','REVIEW_REGULATORY_PROFILE','MANAGE_LEARNER_ARCHIVES','VIEW_SCHOOL_METRICS','VIEW_FINANCIAL_METRICS','EXPORT_MANAGEMENT'])).max(12).refine(v=>new Set(v).size===v.length);
const memberBody=z.object({...operation,roles,grants,reason:text(1000)}).strict();
const curriculumBody=z.object({...operation,categoryCode:category,approved:z.boolean(),approvalReason:text(1000),competencies:z.array(z.object({key:text(80),label:text(200),description:text(4000),sortOrder:z.number().int().min(0).max(100000)}).strict()).min(1).max(200)}).strict().refine(v=>new Set(v.competencies.map(c=>c.key)).size===v.competencies.length);
const webURL=z.url().max(2048).refine(value=>{const url=new URL(value);return ['https:','http:'].includes(url.protocol) && !url.username && !url.password;});
const policyBody=z.object({...operation,categoryCode:category,procedureText:text(4000),cancellationPolicyText:text(4000),sourceUrls:z.array(webURL).max(30),approved:z.boolean(),approvalReason:text(1000)}).strict();
const offeringBody=z.object({...operation,offeringKey:text(80),categoryCode:category,curriculumVersionId:z.uuid(),policyVersionId:z.uuid(),enabled:z.boolean(),defaultDurationMinutes:z.number().int().min(1).max(480),defaultPriceCents:z.number().int().min(0).max(Number.MAX_SAFE_INTEGER)}).strict();
const trainingBody=z.object({...operation,learnerId:z.uuid(),offeringId:z.uuid(),startedOn:z.iso.date().nullable().optional()}).strict();
const assignmentBody=z.object({...operation,instructorMembershipId:z.uuid(),validFrom:z.iso.datetime({offset:true}),validUntil:z.iso.datetime({offset:true}).nullable().optional()}).strict().refine(v=>!v.validUntil || Date.parse(v.validUntil)>Date.parse(v.validFrom));
const pagination=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict();
const memberColumns=`m.id,m.school_id AS "schoolId",m.version,m.person_id AS "personId",p.display_name AS "displayName",m.status,m.roles,m.grants,m.access_epoch AS "accessEpoch"`;
const assignmentColumns=`id,school_id AS "schoolId",version,training_id AS "trainingId",instructor_membership_id AS "instructorMembershipId",valid_from AS "validFrom",valid_until AS "validUntil"`;
const offeringColumns=`id,school_id AS "schoolId",version,offering_key AS "offeringKey",category_code AS "categoryCode",curriculum_version_id AS "curriculumVersionId",policy_version_id AS "policyVersionId",enabled,default_duration_minutes AS "defaultDurationMinutes",default_price_cents AS "defaultPriceCents"`;
const policyColumns=`id,school_id AS "schoolId",version,category_code AS "categoryCode",procedure_text AS "procedureText",cancellation_policy_text AS "cancellationPolicyText",source_urls AS "sourceUrls",approved,approved_at AS "approvedAt"`;
const curriculumColumns=`id,school_id AS "schoolId",version,category_code AS "categoryCode",revision,approved`;
type Row=Record<string,unknown>&{id:string;version:number};
function currentSchool(school:SchoolRow){if(school.status!=='ACTIVE')throw new ApiError(409,'SCHOOL_NOT_ACTIVE','Cette école doit être active.');}
function reauthenticate(identity:Identity,age:number){if(identity.authenticatedAt===undefined || identity.authenticatedAt>Math.floor(Date.now()/1000)+5 || Math.floor(Date.now()/1000)-identity.authenticatedAt>age)throw new ApiError(401,'REAUTH_REQUIRED','Reconnectez-vous pour confirmer ce changement d’accès.');}
async function member(db:PoolClient,schoolId:string,memberId:string){const row=(await db.query<Row>(`SELECT ${memberColumns} FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=$1 AND m.id=$2`,[schoolId,memberId])).rows[0];if(!row)throw notFound();return row;}
async function curriculum(db:PoolClient,row:Row){return {...row,competencies:(await db.query(`SELECT id,school_id AS "schoolId",version,curriculum_version_id AS "curriculumVersionId",stable_key AS key,label,description,sort_order AS "sortOrder" FROM drivy.competency_definition WHERE curriculum_version_id=$1 ORDER BY sort_order,id`,[row.id])).rows};}
const offering=(row:Row)=>({...row,defaultPriceCents:Number(row.defaultPriceCents)});
async function configurationChanged(db:PoolClient,schoolId:string,memberId:string){const school=(await db.query<SchoolRow>(`UPDATE drivy.school SET version=version+1,configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[schoolId])).rows[0]!;await recordSettings(db,school,memberId);}
async function learnerTarget(db:PoolClient,schoolId:string,learnerId:string){
 await db.query("SELECT set_config('app.learner_id',$1,true)",[learnerId]);
 const row=(await db.query<{person_id:string;archived_at:Date|null}>('SELECT person_id,archived_at FROM drivy.learner_profile WHERE school_id=$1 AND id=$2',[schoolId,learnerId])).rows[0];
 if(!row)throw notFound();return row;
}
export function registerCatalogue(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string;reauthMaxAgeSeconds?:number}){
 const age=z.number().int().min(30).max(900).parse(options.reauthMaxAgeSeconds ?? 300);const cursors=new Cursors(options.cursorSecret);
 const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
 const params=(r:FastifyRequest)=>z.object({schoolId:z.uuid(),membershipId:z.uuid().optional(),trainingId:z.uuid().optional()}).parse(r.params);
 const read=async(r:FastifyRequest,work:(db:PoolClient,a:Actor,m:Membership,s:string)=>Promise<unknown>)=>{
  const {schoolId}=params(r);return withActor(options.pool,await options.verifyToken(r.headers.authorization),schoolId,async(db,a,m)=>{if(!m)throw forbidden();return work(db,a,m,schoolId);});
 };
 for(const kind of ['members','offerings','curricula','policy-versions','assignments'] as const){
  const route=kind==='assignments'?'/v1/schools/:schoolId/trainings/:trainingId/assignments':`/v1/schools/:schoolId/${kind}`;
  app.get(route,async request=>{const query=pagination.parse(request.query);const {trainingId}=params(request);
   const data=await read(request,async(db,actor,m,schoolId)=>{
    if(kind==='members' && !m.roles.includes('ADMIN'))throw forbidden();
    if(kind==='assignments')await getTraining(db,schoolId,actor,m,trainingId!);
    const scope=JSON.stringify(['catalogue',kind,schoolId,actor.personId,m.accessEpoch,trainingId ?? null,query.limit]);const position=cursors.decode(query.cursor,scope);
    const table={members:'membership',offerings:'offering_version',curricula:'curriculum_version','policy-versions':'school_policy_version',assignments:'instructor_assignment'}[kind];
    const columns={members:memberColumns,offerings:offeringColumns,curricula:curriculumColumns,'policy-versions':policyColumns,assignments:assignmentColumns}[kind];
    const alias=kind==='members'?'m.':'';const join=kind==='members'?' m JOIN drivy.person p ON p.id=m.person_id':'';
    const extra=kind==='offerings'?' AND curriculum_version_id IS NOT NULL AND policy_version_id IS NOT NULL AND default_price_cents IS NOT NULL AND default_duration_minutes IS NOT NULL':kind==='assignments'?' AND training_id=$5':'';
    const rows=(await db.query<Row&{_createdAt:string}>(`SELECT ${columns},to_char(${alias}created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.${table}${join}
     WHERE ${alias}school_id=$1 AND ($2::timestamptz IS NULL OR (${alias}created_at,${alias}id)>($2,$3::uuid))${extra} ORDER BY ${alias}created_at,${alias}id LIMIT $4`,[schoolId,position?.createdAt ?? null,position?.id ?? null,query.limit+1,...(kind==='assignments'?[trainingId]:[])])).rows;
    const last=rows.length>query.limit?rows[query.limit-1]:undefined;const items=[];
    for(const {_createdAt:ignored,...row} of rows.slice(0,query.limit))items.push(kind==='curricula'?await curriculum(db,row):kind==='offerings'?offering(row):row);
    return {items,nextCursor:last?cursors.encode(scope,{id:last.id,createdAt:last._createdAt}):null};
   });return envelope(data,request);
  });
 }
 app.post('/v1/schools/:schoolId/curricula',{bodyLimit:1_000_000},async(request,reply)=>{
  empty.parse(request.query);const body=curriculumBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const {schoolId}=params(request);
  const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_CURRICULUM_VERSION',body,null,async(db,actor)=>{
   const row=(await db.query<Row>(`INSERT INTO drivy.curriculum_version(school_id,category_code,revision,approved,approval_reason,created_by,approved_at)
    SELECT $1,$2,coalesce(max(revision),0)+1,$3,$4,$5,CASE WHEN $3 THEN now() END FROM drivy.curriculum_version WHERE school_id=$1 AND category_code=$2 RETURNING ${curriculumColumns}`,[schoolId,body.categoryCode,body.approved,body.approvalReason,actor.membershipId])).rows[0]!;
   for(const c of body.competencies)await db.query('INSERT INTO drivy.competency_definition(school_id,curriculum_version_id,stable_key,label,description,sort_order) VALUES($1,$2,$3,$4,$5,$6)',[schoolId,row.id,c.key,c.label,c.description,c.sortOrder]);
   await configurationChanged(db,schoolId,actor.membershipId);return {data:await curriculum(db,row),resourceType:'Curriculum',resourceId:row.id,action:'CurriculumVersionCreated',changedFields:['competencies','approved']};
  });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
 });
 app.post('/v1/schools/:schoolId/policy-versions',{bodyLimit:100_000},async(request,reply)=>{
  empty.parse(request.query);const body=policyBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const {schoolId}=params(request);
  const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_SCHOOL_POLICY',body,null,async(db,actor)=>{
   const row=(await db.query<Row>(`INSERT INTO drivy.school_policy_version(school_id,category_code,version,procedure_text,cancellation_policy_text,source_urls,approved,approval_reason,created_by,approved_at)
    SELECT $1,$2,coalesce(max(version),0)+1,$3,$4,$5,$6,$7,$8,CASE WHEN $6 THEN now() END FROM drivy.school_policy_version WHERE school_id=$1 AND category_code=$2 RETURNING ${policyColumns}`,
    [schoolId,body.categoryCode,body.procedureText,body.cancellationPolicyText,body.sourceUrls,body.approved,body.approvalReason,actor.membershipId])).rows[0]!;
   await configurationChanged(db,schoolId,actor.membershipId);return {data:row,resourceType:'SchoolPolicy',resourceId:row.id,action:'SchoolPolicyCreated',changedFields:['procedureText','cancellationPolicyText','approved']};
  });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
 });
 app.post('/v1/schools/:schoolId/offerings',async(request,reply)=>{
  empty.parse(request.query);const body=offeringBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const {schoolId}=params(request);
  const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_OFFERING_VERSION',body,null,async(db,actor)=>{
   const refs=(await db.query<{approved:boolean}>('SELECT c.approved AND p.approved AS approved FROM drivy.curriculum_version c JOIN drivy.school_policy_version p ON p.school_id=c.school_id WHERE c.school_id=$1 AND c.id=$2 AND p.id=$3 AND c.category_code=$4 AND p.category_code=$4',[schoolId,body.curriculumVersionId,body.policyVersionId,body.categoryCode])).rows[0];
   if(!refs || (body.enabled && !refs.approved))throw new ApiError(409,'OFFERING_NOT_READY','Le référentiel et la procédure de cette catégorie doivent être approuvés.');
   const existing=(await db.query<{category_code:string}>('SELECT category_code FROM drivy.offering_version WHERE school_id=$1 AND offering_key=$2 LIMIT 1',[schoolId,body.offeringKey])).rows[0];
   if(existing && existing.category_code!==body.categoryCode)throw new ApiError(409,'OFFERING_CATEGORY_CHANGED','Une clé d’offre conserve sa catégorie.');
   const row=(await db.query<Row>(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version,enabled,curriculum_version_id,policy_version_id,default_duration_minutes,default_price_cents)
    SELECT $1,$2,$3,$4,coalesce(max(version),0)+1,$5,$6,$7,$8,$9 FROM drivy.offering_version WHERE school_id=$2 AND offering_key=$3 RETURNING ${offeringColumns}`,
    [randomUUID(),schoolId,body.offeringKey,body.categoryCode,body.enabled,body.curriculumVersionId,body.policyVersionId,body.defaultDurationMinutes,body.defaultPriceCents])).rows[0]!;
   await configurationChanged(db,schoolId,actor.membershipId);return {data:offering(row),resourceType:'Offering',resourceId:row.id,action:'OfferingVersionCreated',changedFields:['enabled','curriculumVersionId','policyVersionId','defaultDurationMinutes','defaultPriceCents']};
  });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
 });
 app.post('/v1/schools/:schoolId/trainings',async(request,reply)=>{
  empty.parse(request.query);const body=trainingBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const {schoolId}=params(request);
  const guards:CommandGuards<Row>={additionalPersons:async db=>[(await learnerTarget(db,schoolId,body.learnerId)).person_id],authorize:async db=>{await learnerTarget(db,schoolId,body.learnerId);}};
  const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_TRAINING',body,null,async(db,_actor,school)=>{
   currentSchool(school);if((await learnerTarget(db,schoolId,body.learnerId)).archived_at)throw new ApiError(409,'LEARNER_ARCHIVED','Ce dossier est archivé.');
   if(!(await db.query<{active:boolean}>('SELECT drivy.catalogue_learner_active($1) AS active',[body.learnerId])).rows[0]?.active)throw new ApiError(409,'LEARNER_NOT_ACTIVE','L’appartenance élève doit être active.');
   const offer=(await db.query<{offering_key:string;category_code:string}>(`SELECT o.offering_key,o.category_code FROM drivy.offering_version o JOIN drivy.curriculum_version c ON c.id=o.curriculum_version_id
    JOIN drivy.school_policy_version p ON p.id=o.policy_version_id WHERE o.school_id=$1 AND o.id=$2 AND o.enabled AND c.approved AND p.approved
    AND drivy.catalogue_offering_ready(o.id)`,[schoolId,body.offeringId])).rows[0];
   if(!offer)throw new ApiError(409,'OFFERING_NOT_READY','Cette offre doit être active, approuvée et correspondre à sa version actuelle.');
   if((await db.query("SELECT id FROM drivy.training WHERE school_id=$1 AND learner_id=$2 AND offering_key=$3 AND status IN('ACTIVE','PAUSED')",[schoolId,body.learnerId,offer.offering_key])).rowCount)throw new ApiError(409,'ACTIVE_TRAINING_EXISTS','Une formation de cette offre est déjà active ou en pause.');
   const row=(await db.query<Row>(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on) VALUES($1,$2,$3,$4,$5,'ACTIVE',$6)
    RETURNING id,school_id AS "schoolId",version,learner_id AS "learnerId",offering_id AS "offeringId",status,to_char(started_on,'YYYY-MM-DD') AS "startedOn",NULL AS "closedOn"`,[randomUUID(),schoolId,body.learnerId,body.offeringId,offer.offering_key,body.startedOn ?? null])).rows[0]!;
   return {data:{...row,categoryCode:offer.category_code},resourceType:'Training',resourceId:row.id,action:'TrainingCreated',changedFields:['learnerId','offeringId','status','startedOn']};
  },['ADMIN','INSTRUCTOR'],guards);reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
 });
 app.post('/v1/schools/:schoolId/trainings/:trainingId/assignments',async(request,reply)=>{
  empty.parse(request.query);const body=assignmentBody.parse(request.body);const {schoolId,trainingId}=params(request);checkIdempotency(request.headers['idempotency-key'],body.operationId);
  const command={...body,trainingId};
  const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_ASSIGNMENT',command,null,async(db,_actor,school)=>{
   currentSchool(school);const training=(await db.query<{status:string}>('SELECT status FROM drivy.training WHERE school_id=$1 AND id=$2',[schoolId,trainingId])).rows[0];if(!training)throw notFound();
   if(training.status!=='ACTIVE')throw new ApiError(409,'TRAINING_NOT_ACTIVE','Cette formation doit être active.');
   const target=await member(db,schoolId,body.instructorMembershipId);if(target.status!=='ACTIVE' || !(target.roles as string[]).includes('INSTRUCTOR'))throw new ApiError(409,'INSTRUCTOR_REQUIRED','Choisissez un moniteur actif de cette école.');
   const conflict=await db.query('SELECT id FROM drivy.instructor_assignment WHERE school_id=$1 AND training_id=$2 AND instructor_membership_id=$3 AND tstzrange(valid_from,valid_until,\'[)\') && tstzrange($4::timestamptz,$5::timestamptz,\'[)\')',[schoolId,trainingId,body.instructorMembershipId,body.validFrom,body.validUntil ?? null]);
   if(conflict.rowCount)throw new ApiError(409,'ASSIGNMENT_CONFLICT','Ce moniteur possède déjà une affectation pendant cet intervalle.');
   const row=(await db.query<Row>(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from,valid_until) VALUES($1,$2,$3,$4,$5,$6) RETURNING ${assignmentColumns}`,[randomUUID(),schoolId,trainingId,body.instructorMembershipId,body.validFrom,body.validUntil ?? null])).rows[0]!;
   await db.query('UPDATE drivy.membership SET version=version+1,access_epoch=access_epoch+1 WHERE id=$1',[body.instructorMembershipId]);
   return {data:row,resourceType:'Assignment',resourceId:row.id,action:'AssignmentChanged',changedFields:['instructorMembershipId','validFrom','validUntil']};
  },['ADMIN'],{additionalPersons:async db=>{
   const target=await member(db,schoolId,body.instructorMembershipId);const learner=(await db.query<{person_id:string}>('SELECT l.person_id FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id WHERE t.school_id=$1 AND t.id=$2',[schoolId,trainingId])).rows[0];if(!learner)throw notFound();return [target.personId as string,learner.person_id];
  },writeMemberships:async()=>[body.instructorMembershipId]});reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
 });
 app.patch('/v1/schools/:schoolId/members/:membershipId',async(request,reply)=>{
  empty.parse(request.query);const body=memberBody.parse(request.body);const {schoolId,membershipId}=params(request);checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
  const identity=await options.verifyToken(request.headers.authorization);reauthenticate(identity,age);
  const command={...body,membershipId};
  const data=await schoolCommand(options.pool,identity,schoolId,'UPDATE_MEMBER',command,expected,async(db,_actor,school)=>{
   currentSchool(school);const old=await member(db,schoolId,membershipId!);checkVersion(old.version,expected);const oldRoles=old.roles as string[];
   if(oldRoles.includes('ADMIN') && !body.roles.includes('ADMIN') && (await db.query("SELECT m.id FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=$1 AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)",[schoolId])).rowCount!<=1)throw new ApiError(409,'LAST_ADMIN','Conservez au moins un administrateur actif.');
   if(oldRoles.includes('INSTRUCTOR') && !body.roles.includes('INSTRUCTOR') && (await db.query('SELECT id FROM drivy.instructor_assignment WHERE school_id=$1 AND instructor_membership_id=$2 AND (valid_until IS NULL OR valid_until>now())',[schoolId,membershipId])).rowCount)throw new ApiError(409,'MEMBER_RELATIONS_REQUIRE_REVIEW','Traitez les affectations de ce moniteur avant de retirer son rôle.');
   if(oldRoles.includes('LEARNER') && !body.roles.includes('LEARNER') && (await db.query('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2 AND archived_at IS NULL',[schoolId,old.personId])).rowCount)throw new ApiError(409,'MEMBER_RELATIONS_REQUIRE_REVIEW','Traitez le dossier élève avant de retirer son rôle.');
   await db.query('UPDATE drivy.membership SET roles=$2,grants=$3,version=version+1,access_epoch=access_epoch+1 WHERE id=$1',[membershipId,body.roles,body.grants]);
   if(body.roles.includes('LEARNER') && !oldRoles.includes('LEARNER'))await db.query('INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name) VALUES($1,$2,$3,$4) ON CONFLICT(school_id,person_id) DO NOTHING',[randomUUID(),schoolId,old.personId,old.displayName]);
   return {data:await member(db,schoolId,membershipId!),resourceType:'Member',resourceId:membershipId!,action:'MembershipChanged',reason:body.reason,changedFields:['roles','grants','accessEpoch']};
  },['ADMIN'],{additionalPersons:async db=>{const target=await member(db,schoolId,membershipId!);const admins=(await db.query<{person_id:string}>("SELECT person_id FROM drivy.membership WHERE school_id=$1 AND status='ACTIVE' AND 'ADMIN'=ANY(roles)",[schoolId])).rows;return [target.personId as string,...admins.map(m=>m.person_id)];},writeMemberships:async()=>[membershipId!]});
  reply.header('ETag',`"${data.version}"`);return envelope(data,request);
 });
}
