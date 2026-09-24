import {authorizeCaptureObservationOperation} from './capture-observations.js';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import { authorizePlanningOperation } from './lessons.js';
import { authorizeReportOperation } from './lesson-reports.js';
import { authorizeCaptureOperation } from './captures.js';
import type { TokenVerifier } from './auth.js';
import { withActor } from './database.js';
import { ApiError, notFound } from './errors.js';
import { checkIdempotency, checkVersion, requireVersion, schoolColumns, schoolCommand, schoolProjection, type SchoolRow } from './commands.js';

const steps = ['IDENTITY','ORGANISATION','OFFERINGS','COLLECTIVE','DATA','REVIEW'] as const;
const setupCommand = z.object({ operationId:z.uuid(),currentStep:z.enum(steps),completedSteps:z.array(z.enum(steps)).max(6)
  .refine(value=>new Set(value).size===value.length) }).strict();
const activationCommand = z.object({ operationId:z.uuid(),expectedConfigurationVersion:z.number().int().min(1).max(2_147_483_647),reviewAcknowledged:z.literal(true) }).strict();
const nonBlank = (maximum:number) => z.string().min(1).max(maximum).refine(value=>value.trim().length>0);
const schoolUpdate = z.object({ operationId:z.uuid(),name:nonBlank(150),timeZone:z.string().min(1).max(100),contactEmail:z.email().max(320),
  contactPhone:z.string().max(32).nullable().optional(),impactConfirmed:z.boolean(),logoAssetId:z.uuid().nullable().optional(),
  modules:z.object({gpsEnabled:z.boolean(),packsEnabled:z.boolean(),collectiveCoursesEnabled:z.boolean(),courseOffersVisibleByDefault:z.boolean()}).strict().optional() }).strict();
const policyCommand = z.object({operationId:z.uuid(),noticeText:nonBlank(20000),retentionText:nonBlank(20000),contactEmail:z.email().max(320),reviewAcknowledged:z.literal(true)}).strict();
const empty = z.object({}).strict();
interface SetupRow { school_id:string;version:number;current_step:string;completed_steps:string[];configured_by:string;last_saved_at:Date;completed_at:Date|null }
interface PolicyRow { school_id:string;version:number;notice_version_id:string;notice_text:string;retention_text:string;contact_email:string|null;approved_by:string|null;approved_at:Date|null }
interface Blocker { code:string;message:string;field:string|null;purpose:string|null;resourceId:string|null;destinationKey:string|null }
const blocker = (code:string,message:string,field:string|null=null):Blocker=>({code,message,field,purpose:null,resourceId:null,destinationKey:'SCHOOL_SETUP'});
function validTimeZone(value:string) { try { new Intl.DateTimeFormat('fr',{timeZone:value}); return !/^[+-]/.test(value); } catch { return false; } }
function policyProjection(row:PolicyRow) {
  return {id:row.school_id,schoolId:row.school_id,version:row.version,noticeVersionId:row.notice_version_id,status:row.approved_at?'APPROVED':'DRAFT',noticeText:row.notice_text,
    retentionText:row.retention_text,contactEmail:row.contact_email,approvedAt:row.approved_at?.toISOString()??null,approvedByMembershipId:row.approved_by};
}
async function policy(db:PoolClient,schoolId:string):Promise<PolicyRow> {
  const result=await db.query<PolicyRow>('SELECT * FROM drivy.school_data_policy WHERE school_id=$1 ORDER BY version DESC LIMIT 1',[schoolId]);
  if (!result.rows[0]) throw new ApiError(409,'SETUP_NOT_INITIALIZED','Le provisionnement de cette école doit être complété.');
  return result.rows[0];
}
async function readiness(db:PoolClient,school:SchoolRow) {
  const dataPolicy=await policy(db,school.id);
  const blockers:Blocker[]=[];
  if (!school.name.trim()) blockers.push(blocker('SCHOOL_IDENTITY_REQUIRED','Indiquez le nom de l’école.','name'));
  if (!validTimeZone(school.timeZone)) blockers.push(blocker('INVALID_TIME_ZONE','Choisissez le fuseau de l’école.','timeZone'));
  if (!z.email().safeParse(school.contactEmail).success) blockers.push(blocker('SCHOOL_CONTACT_REQUIRED','Indiquez un contact valide.','contactEmail'));
  // L'acteur de cette lecture est déjà un ADMIN actif : aucun rôle provenant du JWT n'est utilisé.
  if (!dataPolicy.approved_by || !dataPolicy.approved_at || !dataPolicy.notice_text.trim() || !dataPolicy.retention_text.trim()) {
    blockers.push(blocker('POLICY_REVIEW_REQUIRED','Renseignez puis adoptez explicitement la notice et la politique de données.','dataPolicy'));
  }
  if (school.status==='ARCHIVED') blockers.push(blocker('SCHOOL_ARCHIVED','Cette école est archivée.'));
  const workspaceBlockers=[...blockers];
  if (school.status!=='ACTIVE') workspaceBlockers.push(blocker('SCHOOL_NOT_ACTIVE','Activez l’école après vérification de sa configuration.'));
  // Les autres verticales ne sont pas livrées : aucune aptitude n'est déduite d'un module coché.
  const later = (capability:string,code:string,message:string)=>({capability,ready:false,blockers:[...workspaceBlockers,blocker(code,message)]});
  return {schoolId:school.id,configurationVersion:school.configurationVersion,computedAt:new Date().toISOString(),
    activationReady:blockers.length===0,activationBlockers:blockers,capabilities:[
      {capability:'CAN_USE_WORKSPACE',ready:workspaceBlockers.length===0,blockers:workspaceBlockers},
      later('CAN_PLAN_LESSON','LESSON_SETUP_REQUIRED','La configuration des offres, moniteurs et disponibilités sera nécessaire à la planification.'),
      later('CAN_CAPTURE',school.modules.gpsEnabled?'DEVICE_REQUIRED':'GPS_MODULE_DISABLED',school.modules.gpsEnabled?'Le dispositif de capture scolaire reste à qualifier.':'Le GPS scolaire est désactivé.'),
      later('CAN_PUBLISH_COURSE','COURSE_SETUP_REQUIRED','La configuration et le profil des cours collectifs restent à qualifier.')
    ]};
}
async function setup(db:PoolClient,school:SchoolRow) {
  const result=await db.query<SetupRow>('SELECT * FROM drivy.school_setup WHERE school_id=$1',[school.id]);
  const row=result.rows[0];
  if (!row) throw new ApiError(409,'SETUP_NOT_INITIALIZED','Le provisionnement de cette école doit être complété.');
  const ready=await readiness(db,school);
  return {id:row.school_id,schoolId:row.school_id,version:row.version,status:row.completed_at?'COMPLETED':ready.activationReady?'READY':'IN_PROGRESS',
    currentStep:row.current_step,completedSteps:row.completed_steps,lastSavedAt:row.last_saved_at.toISOString(),configuredByMembershipId:row.configured_by,readiness:ready};
}
export async function recordSettings(db:PoolClient,school:SchoolRow,memberId:string,profileFieldPolicyVersionId?:string) {
  const currentPolicy=await policy(db,school.id);
  await db.query('INSERT INTO drivy.school_settings_version(school_id,version,settings,created_by) VALUES($1,$2,$3,$4)',
    [school.id,school.configurationVersion,JSON.stringify({name:school.name,timeZone:school.timeZone,contactEmail:school.contactEmail,
      contactPhone:school.contactPhone,modules:school.modules,dataPolicyVersion:currentPolicy.version,
      ...(profileFieldPolicyVersionId?{profileFieldPolicyVersionId}:{})}),memberId]);
}

export function registerSchoolSetup(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}) {
  const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
  const schoolID=(request:FastifyRequest)=>z.object({schoolId:z.uuid()}).parse(request.params).schoolId;
  const read=async(request:FastifyRequest,work:(db:PoolClient,school:SchoolRow)=>Promise<unknown>,withDevice=false)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    if (withDevice) z.object({deviceId:z.uuid().optional()}).strict().parse(request.query);
    else empty.parse(request.query);
    const id=schoolID(request);
    return withActor(options.pool,identity,id,async(db,_actor,member)=>{
      if (!member?.roles.includes('ADMIN')) throw new ApiError(403,'SETUP_ACCESS_REQUIRED','La configuration est réservée aux administrateurs.');
      const result=await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1`,[id]);
      if (!result.rows[0]) throw notFound();
      return work(db,result.rows[0]);
    });
  };
  app.get('/v1/schools/:schoolId/setup',async(request,reply)=>{
    const data=await read(request,setup) as Awaited<ReturnType<typeof setup>>;
    reply.header('ETag',`"${data.version}"`); return envelope(data,request);
  });
  app.get('/v1/schools/:schoolId/readiness',async request=>envelope(await read(request,readiness,true),request));
  app.get('/v1/schools/:schoolId/data-policy',async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);const id=schoolID(request);
    const query=z.object({noticeVersionId:z.uuid().optional()}).strict().parse(request.query);
    const data=await withActor(options.pool,identity,id,async(db,_actor,member)=>{
      const row=(await db.query<PolicyRow>(`SELECT * FROM drivy.school_data_policy WHERE school_id=$1
        AND ($2::uuid IS NULL OR notice_version_id=$2) AND ($3::boolean OR approved_at IS NOT NULL) ORDER BY version DESC LIMIT 1`,
        [id,query.noticeVersionId ?? null,member?.roles.includes('ADMIN') ?? false])).rows[0];
      if(!row) throw notFound();return policyProjection(row);
    });
    reply.header('ETag',`"${data.version}"`); return envelope(data,request);
  });
  app.get('/v1/schools/:schoolId/operations/:operationId',async request=>{
    const identity=await options.verifyToken(request.headers.authorization);empty.parse(request.query);
    const {schoolId,operationId}=z.object({schoolId:z.uuid(),operationId:z.uuid()}).parse(request.params);
    const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
      if (!member) throw new ApiError(403,'SETUP_ACCESS_REQUIRED','La consultation de cette opération exige un accès actuel.');
      const result=await db.query<{operationId:string;commandType:string;resourceType:string;resourceId:string;committedAt:Date;resourceVersion:number}>(
        `SELECT o.operation_id AS "operationId",o.command_type AS "commandType",a.resource_type AS "resourceType",o.resource_id AS "resourceId",
          o.committed_at AS "committedAt",o.resource_version AS "resourceVersion"
         FROM drivy.operation o JOIN drivy.audit_event a ON a.school_id=o.school_id AND a.actor_person_id=o.actor_person_id AND a.operation_id=o.operation_id
         WHERE o.school_id=$1 AND o.actor_person_id=$2 AND o.operation_id=$3`,[schoolId,actor.personId,operationId]);
      if (!result.rows[0]) throw notFound();
      const planningCommand=await authorizePlanningOperation(db,schoolId,result.rows[0].commandType,result.rows[0].resourceId);
      const reportCommand=await authorizeReportOperation(db,schoolId,result.rows[0].commandType,result.rows[0].resourceId);
      const captureCommand=await authorizeCaptureOperation(db,schoolId,result.rows[0].commandType,result.rows[0].resourceId);
      const captureObservationCommand=await authorizeCaptureObservationOperation(db,schoolId,result.rows[0].commandType,result.rows[0].resourceId);
      const invitationCommand=['CREATE_INVITATION','RESEND_INVITATION','REVOKE_INVITATION'].includes(result.rows[0].commandType);
      const profileCommand=['UPDATE_ADMINISTRATIVE_PROFILE','UPDATE_LEARNER'].includes(result.rows[0].commandType);
      const onboardingCommand=['SAVE_ONBOARDING','COMPLETE_ONBOARDING'].includes(result.rows[0].commandType);
      const trainingCommand=result.rows[0].commandType==='CREATE_TRAINING';
      if(trainingCommand && !(await db.query('SELECT t.id FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id WHERE t.school_id=$1 AND t.id=$2',[schoolId,result.rows[0].resourceId])).rowCount)throw notFound();
      const ownMemberChange=result.rows[0].commandType==='UPDATE_MEMBER' && result.rows[0].resourceId===member.id;
      if(profileCommand && !(await db.query('SELECT id FROM drivy.learner_profile WHERE school_id=$1 AND (id=$2 OR profile_id=$2)',[schoolId,result.rows[0].resourceId])).rowCount) throw notFound();
      if(onboardingCommand) {
        const progress=(await db.query<{kind:string}>('SELECT kind FROM drivy.onboarding_progress WHERE school_id=$1 AND id=$2',[schoolId,result.rows[0].resourceId])).rows[0];
        if(!progress || !(progress.kind==='STUDENT'?member.roles.includes('LEARNER'):member.roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role)))) throw notFound();
      }
      if (!member.roles.includes('ADMIN') && !(invitationCommand && member.roles.includes('INSTRUCTOR')) && result.rows[0].commandType!=='ACCEPT_INVITATION' && !profileCommand && !onboardingCommand && !(trainingCommand && member.roles.includes('INSTRUCTOR')) && !ownMemberChange && !planningCommand && !reportCommand && !captureCommand && !captureObservationCommand)
        throw new ApiError(403,'SETUP_ACCESS_REQUIRED','Les droits nécessaires à cette opération ne sont plus disponibles.');
      return {...result.rows[0],committedAt:result.rows[0].committedAt.toISOString()};
    });
    return envelope(data,request);
  });
  app.patch('/v1/schools/:schoolId/setup',async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    empty.parse(request.query); const body=setupCommand.parse(request.body);const id=schoolID(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId); const expected=requireVersion(request.headers['if-match']);
    const data=await schoolCommand(options.pool,identity,id,'SAVE_SCHOOL_SETUP',body,expected,async(db,actor,school)=>{
      const previous=await setup(db,school);checkVersion(previous.version,expected);
      await db.query('UPDATE drivy.school_setup SET current_step=$2,completed_steps=$3,version=version+1,configured_by=$4,last_saved_at=now() WHERE school_id=$1',
        [id,body.currentStep,body.completedSteps,actor.membershipId]);
      return {data:await setup(db,school),action:'SchoolSetupSaved',resourceType:'SchoolSetup',resourceId:id,changedFields:['currentStep','completedSteps']};
    });
    reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.patch('/v1/schools/:schoolId',async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    empty.parse(request.query);const body=schoolUpdate.parse(request.body);const id=schoolID(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const data=await schoolCommand(options.pool,identity,id,'UPDATE_SCHOOL',body,expected,async(db,actor,school)=>{
      checkVersion(school.version,expected);
      if (!body.impactConfirmed) throw new ApiError(409,'CONFIG_IMPACT_REVIEW_REQUIRED','Confirmez la modification de la configuration affichée.');
      if (!validTimeZone(body.timeZone)) throw new ApiError(422,'INVALID_TIME_ZONE','Le fuseau horaire est invalide.');
      if (body.logoAssetId || (body.modules && Object.entries(body.modules).some(([key,value])=>value!==school.modules[key as keyof typeof school.modules]))) {
        throw new ApiError(409,'MODULE_NOT_READY','Les logos et changements de modules ne sont pas disponibles dans cette tranche.');
      }
      if (school.status==='ACTIVE' && body.timeZone!==school.timeZone) throw new ApiError(409,'CONFIG_IMPACT_REVIEW_REQUIRED','Le changement de fuseau d’une école active demande une analyse d’impact dédiée.');
      const result=await db.query<SchoolRow>(`UPDATE drivy.school SET name=$2,time_zone=$3,contact_email=$4,contact_phone=$5,version=version+1,
        configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[id,body.name,body.timeZone,body.contactEmail,body.contactPhone===undefined?school.contactPhone:body.contactPhone]);
      const current=result.rows[0]!;await recordSettings(db,current,actor.membershipId);
      return {data:schoolProjection(current),action:'SchoolSettingsVersionPublished',resourceType:'School',resourceId:id,changedFields:['name','timeZone','contactEmail','contactPhone']};
    });
    reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  app.put('/v1/schools/:schoolId/data-policy',{bodyLimit:200_000},async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    empty.parse(request.query);const body=policyCommand.parse(request.body);const id=schoolID(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const data=await schoolCommand(options.pool,identity,id,'ADOPT_SCHOOL_DATA_POLICY',body,expected,async(db,actor,school)=>{
      const previous=await policy(db,id);checkVersion(previous.version,expected);
      const result=await db.query<PolicyRow>(`INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text,contact_email,approved_by,approved_at)
        VALUES($1,$2,$3,$4,$5,$6,now()) RETURNING *`,[id,previous.version+1,body.noticeText,body.retentionText,body.contactEmail,actor.membershipId]);
      const current=await db.query<SchoolRow>(`UPDATE drivy.school SET version=version+1,configuration_version=configuration_version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[school.id]);
      await recordSettings(db,current.rows[0]!,actor.membershipId);
      return {data:policyProjection(result.rows[0]!),action:'SchoolDataPolicyAdopted',resourceType:'SchoolDataPolicy',resourceId:id,changedFields:['noticeText','retentionText','contactEmail']};
    });
    // Les anciennes preuves G1B restent immuables ; leur projection reçoit l'UUID réel de la même révision.
    const projected=data.noticeVersionId?data:await withActor(options.pool,identity,id,async(db)=>{
      const row=(await db.query<PolicyRow>('SELECT * FROM drivy.school_data_policy WHERE school_id=$1 AND version=$2',[id,data.version])).rows[0];
      if(!row) throw notFound();return policyProjection(row);
    });
    reply.header('ETag',`"${projected.version}"`);return envelope(projected,request);
  });
  app.post('/v1/schools/:schoolId/activate',async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    empty.parse(request.query);const body=activationCommand.parse(request.body);const id=schoolID(request);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const data=await schoolCommand(options.pool,identity,id,'ACTIVATE_SCHOOL',body,expected,async(db,actor,school)=>{
      checkVersion(school.version,expected);checkVersion(school.configurationVersion,body.expectedConfigurationVersion);
      if (school.status==='ACTIVE') throw new ApiError(409,'SCHOOL_ALREADY_ACTIVE','Cette école est déjà active.');
      const ready=await readiness(db,school);
      if (!ready.activationReady) throw new ApiError(409,ready.activationBlockers.some(item=>item.code==='POLICY_REVIEW_REQUIRED')?'POLICY_REVIEW_REQUIRED':'SETUP_INCOMPLETE','La configuration doit être complétée avant activation.');
      const result=await db.query<SchoolRow>(`UPDATE drivy.school SET status='ACTIVE',version=version+1 WHERE id=$1 RETURNING ${schoolColumns}`,[id]);
      await db.query("UPDATE drivy.school_setup SET completed_at=now(),current_step='REVIEW',version=version+1,configured_by=$2,last_saved_at=now() WHERE school_id=$1",[id,actor.membershipId]);
      return {data:schoolProjection(result.rows[0]!),action:'SchoolActivated',resourceType:'School',resourceId:id,changedFields:['status']};
    });
    reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
}
