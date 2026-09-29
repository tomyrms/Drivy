import type { FastifyInstance,FastifyRequest } from 'fastify';
import type { Pool,PoolClient } from 'pg';
import { z } from 'zod';
import type { TokenVerifier } from './auth.js';
import { withActor,type Actor,type Membership } from './database.js';
import { checkIdempotency,checkVersion,requireVersion,schoolCommand,schoolColumns,type CommandActor,type CommandGuards,type SchoolRow } from './commands.js';
import { recordSettings } from './school-setup.js';
import { ApiError,forbidden,notFound } from './errors.js';
import { Cursors } from './cursor.js';
import { getLearner,getTraining } from './queries.js';
import { planningReadiness } from './lessons.js';

const empty=z.object({}).strict();const operation={operationId:z.uuid()};
const text=(maximum:number)=>z.string().trim().refine(value=>[...value].length>0 && [...value].length<=maximum);
const nullableText=(maximum:number)=>z.string().refine(value=>[...value].length<=maximum).nullable();
const fields=['firstName','lastName','birthDate','postalAddress','contactEmail','contactPhone','profilePhotoDocumentId'] as const;
const fieldRule=z.object({field:z.enum(fields),requirement:z.enum(['REQUIRED','CONDITIONAL','OPTIONAL']),stage:z.enum(['JOIN','BEFORE_LESSON','BEFORE_COURSE','OPTIONAL']),
  purposeCode:z.enum(['IDENTIFICATION','LESSON_CONTACT','COURSE_ELIGIBILITY','CERTIFICATE','POSTAL_CONTACT','PERSONALISATION']),explanation:text(1000)}).strict();
type Rule=z.infer<typeof fieldRule>;
const policyCommand=z.object({...operation,effectiveFrom:z.iso.datetime({offset:true}),fields:z.array(fieldRule).min(2).max(7),noticeVersionId:z.uuid(),impactAcknowledged:z.literal(true)}).strict();
const address=z.object({line1:text(200),line2:nullableText(200),postalCode:text(20),locality:text(150),countryCode:z.string().regex(/^[A-Z]{2}$/)}).strict();
const profileCommand=z.object({...operation,policyVersionId:z.uuid(),firstName:text(150).optional(),lastName:text(150).optional(),birthDate:z.iso.date().nullable().optional(),
  postalAddress:address.nullable().optional(),contactEmail:z.email().nullable().optional(),contactPhone:nullableText(32).optional(),profilePhotoDocumentId:z.uuid().nullable().optional()}).strict().refine(value=>Object.keys(value).length>=3);
const learnerCommand=z.object({...operation,displayName:text(150).optional(),contactEmail:z.email().nullable().optional(),contactPhone:nullableText(32).optional()}).strict().refine(value=>Object.keys(value).length>=2);
const kinds=['STUDENT','STAFF'] as const;type Kind=typeof kinds[number];
const onboardingCommand=z.object({...operation,kind:z.enum(kinds),currentStep:z.enum(['IDENTITY','FORMATIONS','INFORMATION','DEVICE','REVIEW']),
  skippedOptionalSteps:z.array(z.enum(['PHOTO','NOTIFICATIONS','DEVICE'])).max(3).refine(value=>new Set(value).size===value.length).optional(),policyVersionId:z.uuid(),
  returnDestinationKey:z.enum(['HOME','CALENDAR','COURSE','TRAINING']).nullable().optional(),returnResourceId:z.uuid().nullable().optional()}).strict();
const completeCommand=z.object({...operation,kind:z.enum(kinds),policyVersionId:z.uuid()}).strict();
interface PolicyRow { id:string;school_id:string;version:number;status:'DRAFT'|'PUBLISHED'|'RETIRED';effective_from:Date;fields:Rule[];notice_version_id:string;approved_by_membership_id:string|null;_createdAt?:string }
interface ProfileRow {
  id:string;school_id:string;person_id:string;profile_id:string;version:number;display_name:string;contact_email:string|null;contact_phone:string|null;archived_at:Date|null;
  first_name:string|null;last_name:string|null;birthDate:string|null;postal_address:z.infer<typeof address>|null;profile_photo_document_id:string|null;
  administrative_policy_id:string|null;profile_updated_at:Date;entered_by_membership_id:string|null;entry_source:'SELF'|'STAFF_ASSISTED';
}
interface ProgressRow {id:string;school_id:string;person_id:string;membership_id:string;kind:Kind;version:number;current_step:string;skipped_optional_steps:string[];policy_version_id:string;
  last_saved_at:Date;completed_at:Date|null;return_destination_key:string|null;return_resource_id:string|null}
interface Blocker {code:string;message:string;field:string|null;purpose:string|null;resourceId:string|null;destinationKey:string|null}
const block=(code:string,message:string,field:string|null=null,purpose:string|null=null):Blocker=>({code,message,field,purpose,resourceId:null,destinationKey:'PROFILE'});
const policyDTO=(row:PolicyRow)=>({id:row.id,schoolId:row.school_id,version:row.version,status:row.status,effectiveFrom:row.effective_from.toISOString(),fields:row.fields,
  noticeVersionId:row.notice_version_id,approvedByMembershipId:row.approved_by_membership_id});
function validateRules(rules:Rule[]) {
  const fail=()=>{throw new ApiError(422,'PROFILE_POLICY_RULE_INVALID','Vérifiez les champs, leurs finalités et leurs étapes.');};
  if(new Set(rules.map(rule=>rule.field)).size!==rules.length) fail();
  for(const name of ['firstName','lastName']) if(!rules.some(rule=>rule.field===name && rule.requirement==='REQUIRED' && rule.stage==='JOIN' && rule.purposeCode==='IDENTIFICATION')) fail();
  for(const rule of rules) {
    if(['firstName','lastName'].includes(rule.field)) continue;
    if(rule.field==='profilePhotoDocumentId') {if(rule.requirement!=='OPTIONAL' || rule.stage!=='OPTIONAL' || rule.purposeCode!=='PERSONALISATION') fail();continue;}
    if(rule.requirement==='OPTIONAL' && rule.stage!=='OPTIONAL') fail();
    if(rule.requirement!=='OPTIONAL' && !['BEFORE_LESSON','BEFORE_COURSE'].includes(rule.stage)) fail();
    const purposes:Record<string,string[]>={birthDate:['COURSE_ELIGIBILITY','CERTIFICATE'],postalAddress:['POSTAL_CONTACT','CERTIFICATE'],contactEmail:['LESSON_CONTACT'],contactPhone:['LESSON_CONTACT']};
    if(!purposes[rule.field]?.includes(rule.purposeCode)) fail();
    if(rule.requirement==='CONDITIONAL' && rule.stage!=='BEFORE_COURSE') fail();
  }
}
async function currentPolicy(db:PoolClient,schoolId:string):Promise<PolicyRow> {
  const row=(await db.query<PolicyRow>("SELECT * FROM drivy.profile_field_policy WHERE school_id=$1 AND status='PUBLISHED' AND effective_from<=statement_timestamp() ORDER BY effective_from DESC LIMIT 1",[schoolId])).rows[0];
  if(!row) throw new ApiError(409,'PROFILE_POLICY_NOT_READY','L’administration doit publier une politique de champs applicable.');return row;
}
function policyMatches(policy:PolicyRow,id:string) {if(policy.id!==id) throw new ApiError(409,'PROFILE_POLICY_CHANGED','La politique de champs a changé. Relisez les informations avant de confirmer.');}
async function access(db:PoolClient,learnerId:string):Promise<'FULL'|'CONTACT'> {
  const value=(await db.query<{level:'FULL'|'CONTACT'|null}>('SELECT drivy.profile_access($1) AS level',[learnerId])).rows[0]?.level;
  if(!value) throw notFound();return value;
}
async function profile(db:PoolClient,schoolId:string,learnerId:string,lock=false):Promise<ProfileRow> {
  const row=(await db.query<ProfileRow>(`SELECT *,to_char(birth_date,'YYYY-MM-DD') AS "birthDate" FROM drivy.learner_profile WHERE school_id=$1 AND id=$2 ${lock?'FOR UPDATE':''}`,[schoolId,learnerId])).rows[0];
  if(!row) throw notFound();return row;
}
function profileDTO(row:ProfileRow,policy:PolicyRow,level:'FULL'|'CONTACT') {
  const common={id:row.profile_id,schoolId:row.school_id,version:row.version,learnerId:row.id,firstName:row.first_name,lastName:row.last_name,
    contactEmail:row.contact_email,contactPhone:row.contact_phone,updatedAt:row.profile_updated_at.toISOString(),enteredByMembershipId:row.entered_by_membership_id!,entrySource:row.entry_source,policyVersionId:policy.id};
  return level==='CONTACT'?common:{...common,birthDate:row.birthDate,postalAddress:row.postal_address,profilePhotoDocumentId:row.profile_photo_document_id};
}
const writableFields=(body:object)=>Object.keys(body).filter(key=>!['operationId','policyVersionId','learnerId'].includes(key));
function fieldPermission(level:'FULL'|'CONTACT',body:object) {
  if(level==='CONTACT' && writableFields(body).some(field=>!['contactEmail','contactPhone'].includes(field)))
    throw new ApiError(403,'PROFILE_FIELD_FORBIDDEN','Votre affectation autorise uniquement la modification des coordonnées de contact.');
}
function activeSchool(school:SchoolRow) {if(school.status!=='ACTIVE') throw new ApiError(409,'SCHOOL_NOT_ACTIVE','Cette école doit être active pour modifier un profil.');}
function profileGuards<T>(learnerId:string,body:object):CommandGuards<T> {
  return {
    additionalPersons:async db=>{await db.query("SELECT set_config('app.learner_id',$1,true)",[learnerId]);const person=(await db.query<{id:string|null}>('SELECT drivy.profile_target_person() AS id')).rows[0]?.id;
      if(!person) throw notFound();return [person];},
    authorize:async(db)=>{fieldPermission(await access(db,learnerId),body);},
    replay:async(db,_actor,data)=>{if(await access(db,learnerId)==='CONTACT' && typeof data==='object' && data!==null) {
      const sanitized={...data} as Record<string,unknown>;delete sanitized.birthDate;delete sanitized.postalAddress;delete sanitized.profilePhotoDocumentId;return sanitized as T;
    }return data;}
  };
}
function missingProfileFields(row:ProfileRow,policy:PolicyRow,stages:string[]) {
  const values:Record<string,unknown>={firstName:row.first_name,lastName:row.last_name,birthDate:row.birthDate,postalAddress:row.postal_address,contactEmail:row.contact_email,contactPhone:row.contact_phone};
  return policy.fields.filter(rule=>rule.requirement==='REQUIRED' && stages.includes(rule.stage) && (values[rule.field]===null || values[rule.field]===undefined || values[rule.field]===''))
    .map(rule=>block('PROFILE_ACTION_REQUIRED','Complétez ce champ pour l’étape concernée.',rule.field,rule.explanation));
}
async function saveProfile(db:PoolClient,actor:CommandActor,school:SchoolRow,learnerId:string,body:z.infer<typeof profileCommand>|z.infer<typeof learnerCommand>,expected:number,legacy:boolean) {
  activeSchool(school);const policy=await currentPolicy(db,school.id);if('policyVersionId' in body) policyMatches(policy,body.policyVersionId);
  // FOR UPDATE applique aussi la politique d’écriture, qui exclut les dossiers archivés.
  const visible=await profile(db,school.id,learnerId);
  if(visible.archived_at) throw new ApiError(409,'LEARNER_ARCHIVED','Le dossier archivé ne peut pas être modifié.');
  const row=await profile(db,school.id,learnerId,true);checkVersion(row.version,expected);
  const level=await access(db,learnerId);fieldPermission(level,body);
  if('profilePhotoDocumentId' in body && body.profilePhotoDocumentId!==null && body.profilePhotoDocumentId!==undefined)
    throw new ApiError(409,'DOCUMENT_NOT_READY','Le dépôt et la vérification de photo ne sont pas encore disponibles. La photo reste facultative.');
  if('birthDate' in body && body.birthDate && (await db.query('SELECT $1::date>(now() AT TIME ZONE $2)::date AS future',[body.birthDate,school.timeZone])).rows[0].future)
    throw new ApiError(422,'INVALID_BIRTH_DATE','La date de naissance ne peut pas être future.');
  const map:Record<string,string>={displayName:'display_name',firstName:'first_name',lastName:'last_name',birthDate:'birth_date',postalAddress:'postal_address',contactEmail:'contact_email',contactPhone:'contact_phone',profilePhotoDocumentId:'profile_photo_document_id'};
  const values:unknown[]=[learnerId,school.id,policy.id,actor.membershipId,row.person_id===actor.personId?'SELF':'STAFF_ASSISTED'];
  const assignments=writableFields(body).map(field=>{values.push((body as Record<string,unknown>)[field]);return `${map[field]}=$${values.length}`;});
  await db.query(`UPDATE drivy.learner_profile SET ${assignments.join(',')},version=version+1,administrative_policy_id=$3,entered_by_membership_id=$4,entry_source=$5,profile_updated_at=now() WHERE id=$1 AND school_id=$2`,values);
  const updated=await profile(db,school.id,learnerId);
  const ready=missingProfileFields(updated,policy,['JOIN']).length===0;
  await db.query('UPDATE drivy.learner_profile SET profile_readiness=$2 WHERE id=$1',[learnerId,ready?'READY':'MINIMAL']);
  if(legacy) {
    const value=await getLearner(db,school.id,{personId:actor.personId,displayName:'',locale:'',version:1},{id:actor.membershipId,roles:actor.roles,grants:[],accessEpoch:1},learnerId);
    return {data:value,action:'LearnerUpdated',resourceType:'Learner',resourceId:learnerId,changedFields:writableFields(body)};
  }
  return {data:profileDTO(updated,policy,level),action:'AdministrativeProfileUpdated',resourceType:'AdministrativeProfile',resourceId:row.profile_id,changedFields:writableFields(body)};
}
function kindAllowed(kind:Kind,roles:string[]) {if(!(kind==='STUDENT'?roles.includes('LEARNER'):roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role)))) throw forbidden();}
async function progress(db:PoolClient,schoolId:string,memberId:string,kind:Kind,lock=false):Promise<ProgressRow> {
  const row=(await db.query<ProgressRow>(`SELECT * FROM drivy.onboarding_progress WHERE school_id=$1 AND membership_id=$2 AND kind=$3 ${lock?'FOR UPDATE':''}`,[schoolId,memberId,kind])).rows[0];
  if(!row) throw new ApiError(409,'PROFILE_POLICY_NOT_READY','L’administration doit publier la politique de champs pour préparer cet accueil.');return row;
}
async function progressDTO(db:PoolClient,row:ProgressRow,policy:PolicyRow) {
  const pending:Blocker[]=[];
  if(row.kind==='STUDENT') {
    const learner=(await db.query<{id:string}>('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2',[row.school_id,row.person_id])).rows[0];
    if(!learner) pending.push(block('PROFILE_ACTION_REQUIRED','Le dossier scolaire doit être préparé.'));
    else pending.push(...missingProfileFields(await profile(db,row.school_id,learner.id),policy,['JOIN']));
  }
  if(row.current_step!=='REVIEW') pending.push(block('ONBOARDING_REVIEW_REQUIRED','Relisez les informations de l’accueil avant de le terminer.'));
  return {id:row.id,schoolId:row.school_id,version:row.version,personId:row.person_id,membershipId:row.membership_id,kind:row.kind,
    status:row.completed_at && pending.length===0?'COMPLETED':pending.length===0?'READY':'IN_PROGRESS',
    currentStep:row.current_step,skippedOptionalSteps:row.skipped_optional_steps,policyVersionId:policy.id,lastSavedAt:row.last_saved_at.toISOString(),pendingActions:pending,
    returnDestinationKey:row.return_destination_key,returnResourceId:row.return_resource_id};
}
export function registerProfiles(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string}) {
  const cursors=new Cursors(options.cursorSecret);const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
  const params=(request:FastifyRequest)=>z.object({schoolId:z.uuid(),learnerId:z.uuid().optional(),policyId:z.uuid().optional()}).parse(request.params);
  const read=async(request:FastifyRequest,work:(db:PoolClient,actor:Actor,member:Membership,schoolId:string)=>Promise<unknown>)=>{
    const identity=await options.verifyToken(request.headers.authorization);const {schoolId}=params(request);
    return withActor(options.pool,identity,schoolId,async(db,actor,member)=>{if(!member) throw forbidden();return work(db,actor,member,schoolId);});
  };
  app.get('/v1/schools/:schoolId/profile-field-policies',async request=>{
    const query=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(500).optional()}).strict().parse(request.query);
    const data=await read(request,async(db,actor,member,schoolId)=>{
      const scope=JSON.stringify(['profile-policies',schoolId,actor.personId,member.accessEpoch,query.limit]);const cursor=cursors.decode(query.cursor,scope);
      const rows=(await db.query<PolicyRow>(`SELECT *,to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt" FROM drivy.profile_field_policy
        WHERE school_id=$1 AND ($2::timestamptz IS NULL OR (created_at,id)>($2,$3::uuid)) ORDER BY created_at,id LIMIT $4`,[schoolId,cursor?.createdAt ?? null,cursor?.id ?? null,query.limit+1])).rows;
      const last=rows.length>query.limit?rows[query.limit-1]:undefined;return {items:rows.slice(0,query.limit).map(policyDTO),nextCursor:last?cursors.encode(scope,{id:last.id,createdAt:last._createdAt!}):null};
    });return envelope(data,request);
  });
  app.post('/v1/schools/:schoolId/profile-field-policies',async(request,reply)=>{
    empty.parse(request.query);const body=policyCommand.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const {schoolId}=params(request);const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'CREATE_PROFILE_FIELD_POLICY',body,expected,async(db,actor,school)=>{
      checkVersion(school.version,expected);validateRules(body.fields);
      if(!(await db.query('SELECT notice_version_id FROM drivy.school_data_policy WHERE school_id=$1 AND notice_version_id=$2 AND approved_at IS NOT NULL',[schoolId,body.noticeVersionId])).rowCount)
        throw new ApiError(409,'POLICY_REVIEW_REQUIRED','Choisissez une notice effectivement adoptée dans cette école.');
      const row=(await db.query<PolicyRow>(`INSERT INTO drivy.profile_field_policy(school_id,effective_from,fields,notice_version_id,created_by_membership_id)
        VALUES($1,$2,$3,$4,$5) RETURNING *`,[schoolId,body.effectiveFrom,JSON.stringify(body.fields),body.noticeVersionId,actor.membershipId])).rows[0]!;
      await db.query('UPDATE drivy.school SET version=version+1 WHERE id=$1',[schoolId]);
      return {data:policyDTO(row),action:'ProfileFieldPolicyCreated',resourceType:'ProfileFieldPolicy',resourceId:row.id,changedFields:['fields','noticeVersionId','effectiveFrom']};
    });reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.post('/v1/schools/:schoolId/profile-field-policies/:policyId/publish',async(request,reply)=>{
    empty.parse(request.query);const body=z.object(operation).strict().parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const {schoolId,policyId}=params(request);const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,'PUBLISH_PROFILE_FIELD_POLICY',{...body,policyId} as typeof body,expected,async(db,actor)=>{
      // Le verrou scolaire sérialise la publication ; une version déjà publiée reste lisible pour le conflit.
      const row=(await db.query<PolicyRow>('SELECT * FROM drivy.profile_field_policy WHERE school_id=$1 AND id=$2',[schoolId,policyId])).rows[0];
      if(!row) throw notFound();checkVersion(row.version,expected);if(row.status!=='DRAFT') throw new ApiError(409,'PROFILE_POLICY_ALREADY_PUBLISHED','Cette politique est déjà publiée.');validateRules(row.fields);
      if((await db.query("SELECT id FROM drivy.profile_field_policy WHERE school_id=$1 AND status='PUBLISHED' AND effective_from=$2",[schoolId,row.effective_from])).rowCount)
        throw new ApiError(409,'PROFILE_POLICY_DATE_CONFLICT','Une politique publiée utilise déjà cette date d’effet.');
      const updated=(await db.query<PolicyRow>("UPDATE drivy.profile_field_policy SET status='PUBLISHED',version=version+1,approved_at=now(),approved_by_membership_id=$2 WHERE id=$1 RETURNING *",[row.id,actor.membershipId])).rows[0]!;
      const school=(await db.query<SchoolRow>(`UPDATE drivy.school SET version=version+1,configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[schoolId])).rows[0]!;
      await recordSettings(db,school,actor.membershipId,row.id);
      return {data:policyDTO(updated),action:'ProfileFieldPolicyPublished',resourceType:'ProfileFieldPolicy',resourceId:row.id,changedFields:['status','approvedByMembershipId']};
    });reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.get('/v1/schools/:schoolId/learners/:learnerId/administrative-profile',async(request,reply)=>{
    empty.parse(request.query);const {learnerId}=params(request);const data=await read(request,async(db,_actor,_member,schoolId)=>{
      const level=await access(db,learnerId!);const row=await profile(db,schoolId,learnerId!);const policy=await currentPolicy(db,schoolId);return profileDTO(row,policy,level);
    }) as ReturnType<typeof profileDTO>;reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  for(const legacy of [false,true]) app.patch(`/v1/schools/:schoolId/learners/:learnerId${legacy?'':'/administrative-profile'}`,async(request,reply)=>{
    empty.parse(request.query);const body=legacy?learnerCommand.parse(request.body):profileCommand.parse(request.body);const {schoolId,learnerId}=params(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const hashedBody={...body,learnerId};
    const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,legacy?'UPDATE_LEARNER':'UPDATE_ADMINISTRATIVE_PROFILE',
      hashedBody,expected,(db,actor,school)=>saveProfile(db,actor,school,learnerId!,body,expected,legacy),['ADMIN','INSTRUCTOR','LEARNER'],profileGuards(learnerId!,body));
    reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.get('/v1/schools/:schoolId/learners/:learnerId/action-readiness',async request=>{
    const query=z.object({action:z.enum(['ENTER','PLAN_LESSON','ENROLL_COURSE']),resourceId:z.uuid().optional()}).strict().parse(request.query);const {learnerId}=params(request);
    const data=await read(request,async(db,actor,member,schoolId)=>{
      const level=await access(db,learnerId!);const row=await profile(db,schoolId,learnerId!);const policy=await currentPolicy(db,schoolId);const blockers:Blocker[]=[];
      if(query.resourceId) {if(query.action!=='PLAN_LESSON') throw notFound();const training=await getTraining(db,schoolId,actor,member,query.resourceId);if(training.learnerId!==learnerId) throw notFound();}
      if(row.archived_at) blockers.push(block('LEARNER_ARCHIVED','Le dossier est archivé.'));
      const school=(await db.query<{status:string}>('SELECT status FROM drivy.school WHERE id=$1',[schoolId])).rows[0];if(school?.status!=='ACTIVE') blockers.push(block('SCHOOL_NOT_ACTIVE','L’école doit être active.'));
      if(query.action!=='ENTER') {
        const stage=query.action==='PLAN_LESSON'?'BEFORE_LESSON':'BEFORE_COURSE';blockers.push(...missingProfileFields(row,policy,['JOIN',stage]));
        if(policy.fields.some(rule=>rule.requirement==='CONDITIONAL' && rule.stage===stage)) blockers.push(block('PROFILE_CONDITION_NOT_READY','Les exigences conditionnelles doivent être évaluées dans un contexte réglementaire qualifié.'));
        if(query.action==='PLAN_LESSON') blockers.push(...await planningReadiness(db,schoolId,learnerId!,query.resourceId,member.roles));
        else blockers.push(block('COURSE_SETUP_REQUIRED','Les inscriptions aux cours restent à préparer.'));
      }
      // Les champs administratifs protégés ne deviennent pas des indices révélés par les blockers.
      const visible=level==='CONTACT'?blockers.filter(item=>item.field===null || ['firstName','lastName','contactEmail','contactPhone'].includes(item.field)):blockers;
      return {learnerId:row.id,action:query.action,resourceId:query.resourceId ?? null,ready:blockers.length===0,blockers:visible,policyVersionId:policy.id,computedAt:new Date().toISOString()};
    });return envelope(data,request);
  });
  app.get('/v1/schools/:schoolId/my-onboarding',async(request,reply)=>{
    const {kind}=z.object({kind:z.enum(kinds)}).strict().parse(request.query);const data=await read(request,async(db,_actor,member,schoolId)=>{
      kindAllowed(kind,member.roles);const policy=await currentPolicy(db,schoolId);return progressDTO(db,await progress(db,schoolId,member.id,kind),policy);
    }) as Awaited<ReturnType<typeof progressDTO>>;reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  for(const complete of [false,true]) app.route({method:complete?'POST':'PATCH',url:`/v1/schools/:schoolId/my-onboarding${complete?'/complete':''}`,handler:async(request,reply)=>{
    empty.parse(request.query);const body=complete?completeCommand.parse(request.body):onboardingCommand.parse(request.body);const {schoolId}=params(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,complete?'COMPLETE_ONBOARDING':'SAVE_ONBOARDING',body,expected,async(db,actor,school)=>{
      activeSchool(school);const policy=await currentPolicy(db,schoolId);policyMatches(policy,body.policyVersionId);const row=await progress(db,schoolId,actor.membershipId,body.kind,true);checkVersion(row.version,expected);
      if(complete) {
        const state=await progressDTO(db,row,policy);if(state.pendingActions.length) throw new ApiError(409,'ONBOARDING_NOT_READY','Le profil utile et la revue de l’accueil doivent être terminés.');
        await db.query('UPDATE drivy.onboarding_progress SET completed_at=now(),policy_version_id=$2,version=version+1,last_saved_at=now() WHERE id=$1',[row.id,policy.id]);
      } else {
        const update=body as z.infer<typeof onboardingCommand>;const destination=update.returnDestinationKey===undefined?row.return_destination_key:update.returnDestinationKey;
        const resource=update.returnResourceId===undefined?row.return_resource_id:update.returnResourceId;
        if((destination==='HOME' || destination==='CALENDAR' || destination===null) && resource!==null) throw new ApiError(400,'INVALID_REQUEST','Cette destination ne reçoit pas de référence.');
        if(destination==='COURSE') throw new ApiError(409,'COURSE_SETUP_REQUIRED','Le retour vers un cours n’est pas encore disponible.');
        if(destination==='TRAINING') {if(!resource) throw new ApiError(400,'INVALID_REQUEST','La formation de retour est requise.');
          await getTraining(db,schoolId,{personId:actor.personId,displayName:'',locale:'',version:1},{id:actor.membershipId,roles:actor.roles,grants:[],accessEpoch:1},resource);}
        await db.query(`UPDATE drivy.onboarding_progress SET current_step=$2,skipped_optional_steps=$3,policy_version_id=$4,return_destination_key=$5,
          return_resource_id=$6,completed_at=NULL,version=version+1,last_saved_at=now() WHERE id=$1`,[row.id,update.currentStep,update.skippedOptionalSteps ?? row.skipped_optional_steps,policy.id,destination,resource]);
      }
      return {data:await progressDTO(db,await progress(db,schoolId,actor.membershipId,body.kind),policy),action:complete?'OnboardingCompleted':'OnboardingSaved',resourceType:'OnboardingProgress',resourceId:row.id,
        changedFields:complete?['status']:['currentStep','skippedOptionalSteps','returnDestinationKey']};
    },['ADMIN','INSTRUCTOR','LEARNER'],{authorize:async(_db,actor)=>{kindAllowed(body.kind,actor.roles);}});
    reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  }});
}
