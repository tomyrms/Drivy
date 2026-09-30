import type {FastifyInstance} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand} from './commands.js';
import {ApiError,forbidden} from './errors.js';

const command=z.object({operationId:z.uuid(),trainingCategoryCode:z.string().trim().min(1).max(30).nullable(),serviceProductKey:z.string().trim().min(1).max(100).nullable()}).strict();
interface Defaults {id:string;schoolId:string;version:number;trainingCategoryCode:string|null;serviceProductKey:string|null}
export async function planningDefaults(db:PoolClient,schoolId:string,membershipId:string):Promise<Defaults>{
 const row=(await db.query<Defaults>(`SELECT membership_id AS id,school_id AS "schoolId",version,training_category_code AS "trainingCategoryCode",service_product_key AS "serviceProductKey" FROM drivy.planning_defaults WHERE school_id=$1 AND membership_id=$2`,[schoolId,membershipId])).rows[0];
 // Every active staff membership has an initial empty preference representation; its first mutation is version 2.
 return row??{id:membershipId,schoolId,version:1,trainingCategoryCode:null,serviceProductKey:null};
}
export function registerPlanningDefaults(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier}){
 const path='/v1/schools/:schoolId/planning-defaults';
 const schoolID=(params:unknown)=>z.object({schoolId:z.uuid()}).parse(params).schoolId;
 app.get(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),identity=await options.verifyToken(r.headers.authorization);
  const data=await withActor(options.pool,identity,schoolId,async(db,_actor,member)=>{
   if(!member?.roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role)))throw forbidden();
   return planningDefaults(db,schoolId,member.id);
  });
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
 app.put(path,async(r,reply)=>{
  z.object({}).strict().parse(r.query);const schoolId=schoolID(r.params),body=command.parse(r.body),expected=requireVersion(r.headers['if-match']);
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const data=await schoolCommand(options.pool,identity,schoolId,'SAVE_PLANNING_DEFAULTS',body,expected,async(db,actor,school)=>{
   const previous=await planningDefaults(db,schoolId,actor.membershipId);checkVersion(previous.version,expected);
   if(body.trainingCategoryCode && !(await db.query(`SELECT 1 FROM drivy.offering_version o JOIN drivy.school_policy_version p ON p.school_id=o.school_id AND p.id=o.policy_version_id WHERE o.school_id=$1 AND o.category_code=$2 AND o.enabled AND p.approved LIMIT 1`,[schoolId,body.trainingCategoryCode])).rowCount)
    throw new ApiError(422,'PLANNING_DEFAULT_INVALID','Choisis une formation active de cette école.');
   if(body.serviceProductKey && !(await db.query(`SELECT 1 FROM drivy.service_product_version s JOIN drivy.commercial_terms_version t ON t.school_id=s.school_id AND t.id=s.terms_version_id
    WHERE s.school_id=$1 AND s.product_key=$2 AND drivy.service_product_current(s.id) AND s.enabled AND s.type='INDIVIDUAL_LESSON' AND s.site_id IS NULL
    AND ($3::text IS NULL OR s.category_code=$3) AND t.approved
    AND s.valid_from<=(now() AT TIME ZONE $4)::date AND (s.valid_until IS NULL OR s.valid_until>=(now() AT TIME ZONE $4)::date)
    AND t.valid_from<=(now() AT TIME ZONE $4)::date AND (t.valid_until IS NULL OR t.valid_until>=(now() AT TIME ZONE $4)::date) LIMIT 1`,[schoolId,body.serviceProductKey,body.trainingCategoryCode,school.timeZone])).rowCount)
    throw new ApiError(422,'PLANNING_DEFAULT_INVALID','Choisis un tarif actuel compatible avec cette formation.');
   await db.query(`INSERT INTO drivy.planning_defaults(school_id,membership_id,version,training_category_code,service_product_key) VALUES($1,$2,2,$3,$4)
    ON CONFLICT(school_id,membership_id) DO UPDATE SET version=planning_defaults.version+1,training_category_code=EXCLUDED.training_category_code,service_product_key=EXCLUDED.service_product_key`,[schoolId,actor.membershipId,body.trainingCategoryCode,body.serviceProductKey]);
   return {data:await planningDefaults(db,schoolId,actor.membershipId),action:'PlanningDefaultsSaved',resourceType:'PlanningDefaults',resourceId:actor.membershipId,changedFields:['trainingCategoryCode','serviceProductKey']};
  },['ADMIN','INSTRUCTOR']);
  reply.header('ETag',`"${data.version}"`);return {data,requestId:r.id,serverTime:new Date().toISOString()};
 });
}
