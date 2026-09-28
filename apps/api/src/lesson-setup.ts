import {randomUUID} from 'node:crypto';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {Pool,PoolClient} from 'pg';
import {z} from 'zod';
import type {TokenVerifier} from './auth.js';
import {withActor} from './database.js';
import {checkIdempotency,checkVersion,requireVersion,schoolCommand,type CommandActor,type SchoolRow} from './commands.js';
import {ApiError,forbidden,notFound} from './errors.js';
import {Cursors} from './cursor.js';
const id=z.uuid(),text=(max:number)=>z.string().trim().min(1).max(max),op={operationId:id};
const amount=z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const termsCommand=z.object({...op,label:text(200),termsText:text(20000),validFrom:z.iso.date(),validUntil:z.iso.date().nullable(),approved:z.boolean(),approvalReason:text(1000)}).strict();
const productCommand=z.object({...op,productKey:text(100),label:text(200),type:z.enum(['INDIVIDUAL_LESSON','COLLECTIVE_COURSE','EXAM_SUPPORT','EXTERNAL_SERVICE']),
 categoryCode:text(30).nullable(),siteId:id.nullable(),durationMinutes:z.number().int().min(1).max(1440).nullable(),unitLabel:text(100),unitPriceCents:amount,
 validFrom:z.iso.date(),validUntil:z.iso.date().nullable(),termsVersionId:id,enabled:z.boolean()}).strict();
const time=z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/);
const availabilityCommand=z.object({...op,instructorMembershipId:id,weekdays:z.array(z.number().int().min(1).max(7)).min(1).max(7).refine(v=>new Set(v).size===v.length),
 localStart:time,localEnd:time,validFrom:z.iso.date(),validUntil:z.iso.date().nullable()}).strict();
const closureCommand=z.object({...op,instructorMembershipId:id,startsAt:z.iso.datetime({offset:true}),endsAt:z.iso.datetime({offset:true}),reason:z.string().max(1000).nullable().optional()}).strict();
const reasonCommand=z.object({...op,reason:text(1000)}).strict();
const pagination={limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()};
const stamp=(alias:string)=>`to_char(${alias}.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt"`;
type Row=Record<string,unknown>&{id:string;version:number;_createdAt:string};
function dates(from:string,until:string|null){if(until&&until<from)throw new ApiError(422,'INVALID_INTERVAL','La fin de validité précède le début.');}
export async function cataloguePermission(db:PoolClient,schoolId:string){
 if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_catalogue_manage($1) AS ok',[schoolId])).rows[0]?.ok)throw forbidden();
}
export async function instructorPermission(db:PoolClient,schoolId:string,instructorId:string){
 if(!(await db.query<{ok:boolean}>('SELECT drivy.lesson_instructor_manage($1,$2) AS ok',[schoolId,instructorId])).rows[0]?.ok)throw forbidden();
}
export async function ensureOpen(db:PoolClient,schoolId:string,instructorId:string,start:string,end:string,timeZone:string,buffer:number){
 const result=await db.query<{same_day:boolean;ordered:boolean;opened:boolean;closed:boolean}>(`WITH bounds AS (
 SELECT $3::timestamptz AS starts,$4::timestamptz+make_interval(mins=>$6) AS ends), local AS (
 SELECT *,starts AT TIME ZONE $5 AS local_start,ends AT TIME ZONE $5 AS local_end FROM bounds)
 SELECT b.local_start::date=b.local_end::date AS same_day,b.local_end>b.local_start AS ordered,
 EXISTS(SELECT 1 FROM drivy.availability_rule a WHERE a.school_id=$1 AND a.instructor_membership_id=$2 AND a.removed_at IS NULL
 AND extract(isodow FROM b.local_start)::int=ANY(a.weekdays) AND a.valid_from<=b.local_start::date AND (a.valid_until IS NULL OR a.valid_until>=b.local_start::date)
 AND a.local_start<=b.local_start::time AND a.local_end>=b.local_end::time) AS opened,
 EXISTS(SELECT 1 FROM drivy.closure c WHERE c.school_id=$1 AND c.instructor_membership_id=$2 AND c.removed_at IS NULL
 AND tstzrange(c.starts_at,c.ends_at,'[)')&&tstzrange(b.starts,b.ends,'[)')) AS closed FROM local b`,[schoolId,instructorId,start,end,timeZone,buffer]);
 const value=result.rows[0]!;
 if(!value.same_day||!value.ordered)throw new ApiError(422,'INVALID_INTERVAL','Le trajet et son tampon doivent tenir dans une journée locale.');
 if(!value.opened||value.closed)throw new ApiError(409,'SLOT_UNAVAILABLE','Ce créneau ne fait pas partie des disponibilités du moniteur.');
}
const columns={
 'commercial-terms':`id,school_id AS "schoolId",version,label,terms_text AS "termsText",to_char(valid_from,'YYYY-MM-DD') AS "validFrom",to_char(valid_until,'YYYY-MM-DD') AS "validUntil",approved,approval_reason AS "approvalReason",approved_by AS "approvedByMembershipId",approved_at AS "approvedAt"`,
 'service-products':`id,school_id AS "schoolId",version,product_key AS "productKey",label,type,category_code AS "categoryCode",site_id AS "siteId",duration_minutes AS "durationMinutes",unit_label AS "unitLabel",unit_price_cents AS "unitPriceCents",to_char(valid_from,'YYYY-MM-DD') AS "validFrom",to_char(valid_until,'YYYY-MM-DD') AS "validUntil",terms_version_id AS "termsVersionId",enabled`,
 'availability-rules':`id,school_id AS "schoolId",version,instructor_membership_id AS "instructorMembershipId",weekdays,to_char(local_start,'HH24:MI') AS "localStart",to_char(local_end,'HH24:MI') AS "localEnd",to_char(valid_from,'YYYY-MM-DD') AS "validFrom",to_char(valid_until,'YYYY-MM-DD') AS "validUntil"`,
 'closures':`id,school_id AS "schoolId",version,instructor_membership_id AS "instructorMembershipId",starts_at AS "startsAt",ends_at AS "endsAt",reason`
};
const tables={'commercial-terms':'commercial_terms_version','service-products':'service_product_version','availability-rules':'availability_rule','closures':'closure'} as const;
const project=(row:Row)=>{const {_createdAt:_,...data}=row;if('unitPriceCents'in data)data.unitPriceCents=Number(data.unitPriceCents);return data;};
export function registerLessonSetup(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string}){
 const cursors=new Cursors(options.cursorSecret),base='/v1/schools/:schoolId';
 const schoolID=(r:FastifyRequest)=>z.object({schoolId:id}).parse(r.params).schoolId;
 const envelope=(data:unknown,r:FastifyRequest)=>({data,requestId:r.id,serverTime:new Date().toISOString()});
 const created=async(r:FastifyRequest,body:{operationId:string},type:string,work:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<{data:Row;action:string;resourceType:string;changedFields:string[]}>,authorize:(db:PoolClient,schoolId:string)=>Promise<void>)=>{
  z.object({}).strict().parse(r.query);checkIdempotency(r.headers['idempotency-key'],body.operationId);const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  return schoolCommand(options.pool,identity,schoolId,type,body,null,async(db,actor,school)=>{
   const effect=await work(db,actor,school);return {...effect,resourceId:effect.data.id,data:project(effect.data)};
  },['ADMIN','INSTRUCTOR'],{authorize:(db)=>authorize(db,schoolId)});
 };
 for(const name of Object.keys(tables) as (keyof typeof tables)[])app.get(`${base}/${name}`,async r=>{
  const schedule=name==='availability-rules'||name==='closures';
  const query=(schedule?z.object({...pagination,instructorMembershipId:id.optional(),...(name==='closures'?{from:z.iso.datetime({offset:true}).optional(),to:z.iso.datetime({offset:true}).optional()}:{})}).strict():z.object(pagination).strict()).parse(r.query);
  const schoolId=schoolID(r),identity=await options.verifyToken(r.headers.authorization);
  return envelope(await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
   if(!member)throw forbidden();if(schedule&&!member.roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role)))throw forbidden();
   const scope=JSON.stringify([name,schoolId,actor.personId,member.accessEpoch,query.limit,{...query,cursor:undefined}]);
   const position=cursors.decode(query.cursor,scope),values:unknown[]=[schoolId];const where=['x.school_id=$1'];
   const bind=(v:unknown)=>{values.push(v);return `$${values.length}`;};
   if(schedule)where.push('x.removed_at IS NULL');
   if('instructorMembershipId'in query&&query.instructorMembershipId)where.push(`x.instructor_membership_id=${bind(query.instructorMembershipId)}`);
   if('from'in query&&query.from)where.push(`x.ends_at>${bind(query.from)}::timestamptz`);
   if('to'in query&&query.to)where.push(`x.starts_at<${bind(query.to)}::timestamptz`);
   if(position)where.push(`(x.created_at,x.id)>(${bind(position.createdAt)}::timestamptz,${bind(position.id)}::uuid)`);
   const rows=(await db.query<Row>(`SELECT ${columns[name]},${stamp('x')} FROM drivy.${tables[name]} x WHERE ${where.join(' AND ')} ORDER BY x.created_at,x.id LIMIT ${bind(query.limit+1)}`,values)).rows;
   const last=rows.length>query.limit?rows[query.limit-1]:undefined;
   return {items:rows.slice(0,query.limit).map(project),nextCursor:last?cursors.encode(scope,{createdAt:last._createdAt,id:last.id}):null,...(name==='service-products'?{generatedAt:new Date().toISOString()}:{})};
  }),r);
 });
 app.post(`${base}/commercial-terms`,{bodyLimit:100_000},async(r,reply)=>{
  const body=termsCommand.parse(r.body);dates(body.validFrom,body.validUntil);
  const data=await created(r,body,'CREATE_COMMERCIAL_TERMS',async(db,actor,school)=>{
   const row=(await db.query<Row>(`INSERT INTO drivy.commercial_terms_version(id,school_id,version,label,terms_text,valid_from,valid_until,approved,approval_reason,approved_by,approved_at,created_by)
    VALUES($1,$2,(SELECT coalesce(max(version),0)+1 FROM drivy.commercial_terms_version WHERE school_id=$2),$3,$4,$5,$6,$7,$8,$9,CASE WHEN $7 THEN now() ELSE NULL END,$10) RETURNING ${columns['commercial-terms']}`,
    [randomUUID(),school.id,body.label,body.termsText,body.validFrom,body.validUntil,body.approved,body.approvalReason,body.approved?actor.membershipId:null,actor.membershipId])).rows[0]!;
   return {data:row,action:'CommercialTermsCreated',resourceType:'CommercialTermsVersion',changedFields:['termsText','validFrom','validUntil','approved']};
  },cataloguePermission);reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/service-products`,async(r,reply)=>{
  const body=productCommand.parse(r.body);dates(body.validFrom,body.validUntil);
  const data=await created(r,body,'CREATE_SERVICE_PRODUCT',async(db,_actor,school)=>{
   if(body.siteId)throw new ApiError(422,'SITE_SETUP_REQUIRED','Les prestations par site ne sont pas encore configurées.');
   if(body.type==='INDIVIDUAL_LESSON'&&(!body.durationMinutes||!body.categoryCode))throw new ApiError(422,'INVALID_SERVICE_PRODUCT','Une leçon exige une catégorie et une durée explicites.');
   const terms=(await db.query<{approved:boolean}>(`SELECT approved FROM drivy.commercial_terms_version WHERE school_id=$1 AND id=$2`,[school.id,body.termsVersionId])).rows[0];
   if(!terms||(body.enabled&&!terms.approved))throw new ApiError(422,'COMMERCIAL_TERMS_NOT_APPROVED','Sélectionnez des conditions commerciales approuvées.');
   const row=(await db.query<Row>(`INSERT INTO drivy.service_product_version(id,school_id,version,product_key,label,type,category_code,site_id,duration_minutes,unit_label,unit_price_cents,valid_from,valid_until,terms_version_id,enabled)
    VALUES($1,$2,(SELECT coalesce(max(version),0)+1 FROM drivy.service_product_version WHERE school_id=$2 AND product_key=$3),$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING ${columns['service-products']}`,
    [randomUUID(),school.id,body.productKey,body.label,body.type,body.categoryCode,body.siteId,body.durationMinutes,body.unitLabel,body.unitPriceCents,body.validFrom,body.validUntil,body.termsVersionId,body.enabled])).rows[0]!;
   return {data:row,action:'ServiceProductCreated',resourceType:'ServiceProductVersion',changedFields:['label','durationMinutes','unitPriceCents','termsVersionId','enabled']};
  },cataloguePermission);reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/availability-rules`,async(r,reply)=>{
  const body=availabilityCommand.parse(r.body);dates(body.validFrom,body.validUntil);if(body.localEnd<=body.localStart)throw new ApiError(422,'INVALID_INTERVAL','La plage doit rester dans la même journée.');
  const data=await created(r,body,'CREATE_AVAILABILITY_RULE',async(db,_actor,school)=>{
   const row=(await db.query<Row>(`INSERT INTO drivy.availability_rule(id,school_id,instructor_membership_id,weekdays,local_start,local_end,valid_from,valid_until)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING ${columns['availability-rules']}`,[randomUUID(),school.id,body.instructorMembershipId,body.weekdays,body.localStart,body.localEnd,body.validFrom,body.validUntil])).rows[0]!;
   return {data:row,action:'AvailabilityCreated',resourceType:'AvailabilityRule',changedFields:['weekdays','localStart','localEnd','validFrom','validUntil']};
  },(db,schoolId)=>instructorPermission(db,schoolId,body.instructorMembershipId));reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 app.post(`${base}/closures`,async(r,reply)=>{
  const body=closureCommand.parse(r.body);if(Date.parse(body.endsAt)<=Date.parse(body.startsAt))throw new ApiError(422,'INVALID_INTERVAL','La fermeture doit avoir une durée positive.');
  const data=await created(r,body,'CREATE_CLOSURE',async(db,_actor,school)=>{
   const overlap=await db.query(`SELECT 1 FROM drivy.lesson WHERE school_id=$1 AND instructor_membership_id=$2 AND status='PLANNED'
    AND tstzrange(planned_start,planned_end+make_interval(mins=>buffer_minutes_snapshot),'[)')&&tstzrange($3::timestamptz,$4::timestamptz,'[)') LIMIT 1`,[school.id,body.instructorMembershipId,body.startsAt,body.endsAt]);
   if(overlap.rowCount)throw new ApiError(409,'EXISTING_BOOKINGS','Des rendez-vous doivent être traités avant cette fermeture.');
   const row=(await db.query<Row>(`INSERT INTO drivy.closure(id,school_id,instructor_membership_id,starts_at,ends_at,reason) VALUES($1,$2,$3,$4,$5,$6) RETURNING ${columns.closures}`,
    [randomUUID(),school.id,body.instructorMembershipId,body.startsAt,body.endsAt,body.reason??null])).rows[0]!;
   return {data:row,action:'ClosureCreated',resourceType:'Closure',changedFields:['startsAt','endsAt','reason']};
  },(db,schoolId)=>instructorPermission(db,schoolId,body.instructorMembershipId));reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,r);
 });
 for(const resource of ['availability-rules','closures'] as const)app.post(`${base}/${resource}/:resourceId/remove`,async(r,reply)=>{
  z.object({}).strict().parse(r.query);
  const body=reasonCommand.parse(r.body),expected=requireVersion(r.headers['if-match']),schoolId=schoolID(r),resourceId=z.object({resourceId:id}).parse(r.params).resourceId;
  checkIdempotency(r.headers['idempotency-key'],body.operationId);const identity=await options.verifyToken(r.headers.authorization);
  const boundCommand={...body,resourceId};
  const data=await schoolCommand(options.pool,identity,schoolId,resource==='closures'?'REMOVE_CLOSURE':'REMOVE_AVAILABILITY_RULE',boundCommand,expected,async(db)=>{
   const row=(await db.query<{version:number;instructor_membership_id:string}>(`SELECT version,instructor_membership_id FROM drivy.${tables[resource]} WHERE school_id=$1 AND id=$2 AND removed_at IS NULL FOR UPDATE`,[schoolId,resourceId])).rows[0];
   if(!row)throw notFound();checkVersion(row.version,expected);
   await db.query(`UPDATE drivy.${tables[resource]} SET removed_at=now(),version=version+1 WHERE id=$1`,[resourceId]);
   if(resource==='availability-rules')await checkBookings(db,schoolId,row.instructor_membership_id);
   return {data:{operationId:body.operationId,accepted:true},resourceVersion:expected+1,resourceId,resourceType:resource==='closures'?'Closure':'AvailabilityRule',action:resource==='closures'?'ClosureRemoved':'AvailabilityRemoved',changedFields:['removedAt']};
  },['ADMIN','INSTRUCTOR'],{authorize:async db=>{const row=(await db.query<{instructor_membership_id:string}>(`SELECT instructor_membership_id FROM drivy.${tables[resource]} WHERE school_id=$1 AND id=$2`,[schoolId,resourceId])).rows[0];if(!row)throw notFound();await instructorPermission(db,schoolId,row.instructor_membership_id);}});
  reply.header('ETag',`"${expected+1}"`);return envelope(data,r);
 });
 app.put(`${base}/availability-rules/:availabilityRuleId`,async(r,reply)=>{
  z.object({}).strict().parse(r.query);
  const body=availabilityCommand.parse(r.body),schoolId=schoolID(r),ruleId=z.object({availabilityRuleId:id}).parse(r.params).availabilityRuleId,expected=requireVersion(r.headers['if-match']);
  dates(body.validFrom,body.validUntil);if(body.localEnd<=body.localStart)throw new ApiError(422,'INVALID_INTERVAL','Plage locale invalide.');checkIdempotency(r.headers['idempotency-key'],body.operationId);
  const identity=await options.verifyToken(r.headers.authorization);
  const boundCommand={...body,ruleId};
  const data=await schoolCommand(options.pool,identity,schoolId,'UPDATE_AVAILABILITY_RULE',boundCommand,expected,async db=>{
   const old=(await db.query<{version:number;instructor_membership_id:string}>('SELECT version,instructor_membership_id FROM drivy.availability_rule WHERE school_id=$1 AND id=$2 AND removed_at IS NULL FOR UPDATE',[schoolId,ruleId])).rows[0];
   if(!old)throw notFound();if(old.instructor_membership_id!==body.instructorMembershipId)throw new ApiError(422,'INVALID_REQUEST','Le moniteur de la plage ne peut pas changer.');checkVersion(old.version,expected);
   const row=(await db.query<Row>(`UPDATE drivy.availability_rule SET weekdays=$3,local_start=$4,local_end=$5,valid_from=$6,valid_until=$7,version=version+1 WHERE school_id=$1 AND id=$2 RETURNING ${columns['availability-rules']}`,
    [schoolId,ruleId,body.weekdays,body.localStart,body.localEnd,body.validFrom,body.validUntil])).rows[0]!;
   await checkBookings(db,schoolId,body.instructorMembershipId);return {data:project(row),resourceId:ruleId,resourceType:'AvailabilityRule',action:'AvailabilityUpdated',changedFields:['weekdays','localStart','localEnd','validFrom','validUntil']};
  },['ADMIN','INSTRUCTOR'],{authorize:db=>instructorPermission(db,schoolId,body.instructorMembershipId)});
  reply.header('ETag',`"${data.version}"`);return envelope(data,r);
 });
}
async function checkBookings(db:PoolClient,schoolId:string,instructorId:string){
 const rows=(await db.query<{planned_start:Date;planned_end:Date;time_zone:string;buffer_minutes_snapshot:number}>(`SELECT planned_start,planned_end,time_zone,buffer_minutes_snapshot FROM drivy.lesson WHERE school_id=$1 AND instructor_membership_id=$2 AND status='PLANNED' AND planned_end>now()`,[schoolId,instructorId])).rows;
 for(const row of rows)try{await ensureOpen(db,schoolId,instructorId,row.planned_start.toISOString(),row.planned_end.toISOString(),row.time_zone,row.buffer_minutes_snapshot);}catch{throw new ApiError(409,'EXISTING_BOOKINGS','Des rendez-vous doivent être traités avant de modifier ces ouvertures.');}
}
