import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { Pool, PoolClient } from 'pg';
import { z } from 'zod';
import type { Identity, TokenVerifier } from './auth.js';
import { ApiError, forbidden, notFound } from './errors.js';
import { rollbackQuietly } from './database.js';
import { checkIdempotency, commandHash, recordCommand } from './commands.js';
import { createOpeningLinkBody, openingPreviewBody, schoolOpeningBody, openingHash, openingLinkProjection,
  type OpeningLinkRow, type SchoolOpeningConfig, type SchoolOpeningCommand } from './school-opening-model.js';
export { readSchoolOpeningConfig } from './school-opening-model.js';

const empty=z.object({}).strict();
const operationBody=z.object({operationId:z.uuid()}).strict();
const invalid=()=>new ApiError(404,'OPENING_LINK_INVALID','Ce lien d’ouverture n’est pas valide.');
const mismatch=()=>new ApiError(409,'IDEMPOTENCY_MISMATCH','Cette demande a déjà été utilisée avec un autre contenu.');
function assertAvailable(row:OpeningLinkRow) {
  if(row.status==='REVOKED') throw new ApiError(410,'OPENING_LINK_REVOKED','Ce lien a été révoqué. Demandez un nouveau lien à Drivy.');
  if(row.status==='USED') throw new ApiError(409,'OPENING_LINK_USED','Ce lien a déjà été utilisé.');
  if(row.expires_at.getTime()<=Date.now()) throw new ApiError(410,'OPENING_LINK_EXPIRED','Ce lien a expiré. Demandez un nouveau lien à Drivy.');
}
async function transaction<T>(pool:Pool,identity:Identity,operator:boolean,token:string|undefined,work:(db:PoolClient)=>Promise<T>) {
  const db=await pool.connect();let broken=false;
  try {
    await db.query('BEGIN');await db.query("SET LOCAL lock_timeout='5s'");await db.query("SET LOCAL statement_timeout='10s'");
    await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_opening_operator',$3,true),set_config('app.school_opening_hash',$4,true)",
      [identity.issuer,identity.subject,operator?'true':'false',token?openingHash(token):'']);
    const result=await work(db);await db.query('COMMIT');return result;
  } catch(error) { broken=!(await rollbackQuietly(db));throw error; } finally {db.release(broken);}
}
async function currentResult(db:PoolClient,row:OpeningLinkRow,identity:Identity) {
  if(row.used_by_issuer!==identity.issuer || row.used_by_subject!==identity.subject) throw new ApiError(409,'OPENING_LINK_USED','Ce lien a déjà été utilisé.');
  await db.query("SELECT set_config('app.person_id',$1,true),set_config('app.school_id',$2,true)",[row.used_by_person_id,row.reserved_school_id]);
  const person=(await db.query("SELECT id FROM drivy.person WHERE id=$1 AND status='ACTIVE' FOR SHARE",[row.used_by_person_id])).rows[0];
  if(!person) throw forbidden();
  const result=(await db.query<{schoolId:string;schoolName:string;status:string;membershipId:string;roles:string[];grants:string[];accessEpoch:number}>(`SELECT s.id AS "schoolId",s.name AS "schoolName",s.status,m.id AS "membershipId",m.roles,m.grants,m.access_epoch AS "accessEpoch"
    FROM drivy.school s JOIN drivy.membership m ON m.school_id=s.id WHERE s.id=$1 AND m.id=$2 AND m.person_id=$3 AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles) FOR SHARE OF s,m`,
    [row.reserved_school_id,row.reserved_membership_id,row.used_by_person_id])).rows[0];
  if(!result) throw forbidden();
  return { ...result,operationId:row.consume_operation_id,committedAt:row.used_at!.toISOString() };
}
async function createSchool(pool:Pool,identity:Identity,body:SchoolOpeningCommand) {
  return transaction(pool,identity,false,body.token,async db=>{
    // Same lock as invitation acceptance: the same OIDC identity cannot create two Person rows in parallel.
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`oidc:${identity.issuer}:${identity.subject}`]);
    const linked=(await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[identity.issuer,identity.subject])).rows[0]?.person_id;
    const personId=linked ?? randomUUID();
    await db.query("SELECT set_config('app.person_id',$1,true)",[personId]);
    if(linked && !(await db.query("SELECT id FROM drivy.person WHERE id=$1 AND status='ACTIVE' FOR UPDATE",[personId])).rowCount) throw forbidden();
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`${personId}:${body.operationId}`]);
    const hash=commandHash(body,null);
    const previous=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE used_by_issuer=$1 AND used_by_subject=$2 AND consume_operation_id=$3',
      [identity.issuer,identity.subject,body.operationId])).rows[0];
    if(previous){if(previous.consume_hash!==hash)throw mismatch();return currentResult(db,previous,identity);}
    const row=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE token_hash=$1 FOR UPDATE',[openingHash(body.token)])).rows[0];
    if(!row) throw invalid();
    // A revisited link can recover its original receipt after the browser lost its operation UUID.
    // This is read-only recovery: newly submitted fields never alter the already-created school.
    if(row.status==='USED') return currentResult(db,row,identity);
    assertAvailable(row);
    // An operation UUID already used for an ordinary school command remains unavailable here.
    if(linked && (await db.query('SELECT 1 FROM drivy.operation WHERE actor_person_id=$1 AND operation_id=$2',[personId,body.operationId])).rowCount) throw mismatch();
    await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.membership_id',$2,true)",[row.reserved_school_id,row.reserved_membership_id]);
    if(!linked) {
      await db.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)',[personId,body.displayName]);
      await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)',[identity.issuer,identity.subject,personId]);
    } else await db.query('UPDATE drivy.person SET display_name=$2,version=version+1 WHERE id=$1 AND display_name<>$2',[personId,body.displayName]);
    await db.query("INSERT INTO drivy.school(id,name,time_zone,status,contact_email,contact_phone) VALUES($1,$2,$3,'DRAFT',$4,$5)",
      [row.reserved_school_id,body.schoolName,body.timeZone,body.contactEmail,body.contactPhone]);
    const roles=body.instructs?['ADMIN','INSTRUCTOR']:['ADMIN'];
    // The existing trigger creates SchoolSetup and the empty, unapproved policy in this same commit.
    await db.query("INSERT INTO drivy.membership(id,school_id,person_id,roles,grants) VALUES($1,$2,$3,$4,ARRAY['CONFIGURE_CATALOG'])",
      [row.reserved_membership_id,row.reserved_school_id,personId,roles]);
    const used=(await db.query<OpeningLinkRow>(`UPDATE drivy.school_opening_link SET status='USED',used_at=clock_timestamp(),used_by_issuer=$2,used_by_subject=$3,
      used_by_person_id=$4,consume_operation_id=$5,consume_hash=$6 WHERE id=$1 RETURNING *`,[row.id,identity.issuer,identity.subject,personId,body.operationId,hash])).rows[0]!;
    const data=await currentResult(db,used,identity);
    await recordCommand(db,{personId,membershipId:row.reserved_membership_id,roles},row.reserved_school_id,'OPEN_SCHOOL',body.operationId,hash,
      {data,resourceId:row.reserved_school_id,resourceType:'School',resourceVersion:1,action:'SchoolOpened',changedFields:['identity','membership','instructs']});
    return data;
  });
}

/** Opening is closed to operators by default; consumers still need an issued, unexpired bearer link and OIDC. */
export function registerSchoolOpening(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;schoolOpening?:SchoolOpeningConfig}) {
  const config=options.schoolOpening ?? {operators:[],validityDays:7};
  const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
  const operator=async(request:FastifyRequest)=>{
    const identity=await options.verifyToken(request.headers.authorization);
    if(!config.operators.some(candidate=>candidate.issuer===identity.issuer && candidate.subject===identity.subject))
      throw new ApiError(403,'OPERATOR_REQUIRED','Cet espace est réservé à l’opérateur Drivy.');
    return identity;
  };
  app.get('/v1/operator/school-opening-links',async request=>{
    const identity=await operator(request);empty.parse(request.query);
    const data=await transaction(options.pool,identity,true,undefined,async db=>({items:(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link ORDER BY created_at DESC,id LIMIT 100')).rows.map(openingLinkProjection)}));
    return envelope(data,request);
  });
  app.post('/v1/operator/school-opening-links',async(request,reply)=>{
    const identity=await operator(request);empty.parse(request.query);const body=createOpeningLinkBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const hash=commandHash(body,null);
    const data=await transaction(options.pool,identity,true,undefined,async db=>{
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`opening-operator:${identity.issuer}:${identity.subject}:${body.operationId}`]);
      const known=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE created_by_issuer=$1 AND created_by_subject=$2 AND create_operation_id=$3',[identity.issuer,identity.subject,body.operationId])).rows[0];
      if(known){if(known.create_hash!==hash)throw mismatch();return openingLinkProjection(known);}
      const row=(await db.query<OpeningLinkRow>(`INSERT INTO drivy.school_opening_link(id,token_hash,reserved_school_id,reserved_membership_id,created_by_issuer,created_by_subject,create_operation_id,create_hash,expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,now()+make_interval(days=>$9)) RETURNING *`,[randomUUID(),openingHash(body.token),randomUUID(),randomUUID(),identity.issuer,identity.subject,body.operationId,hash,config.validityDays])).rows[0]!;
      return openingLinkProjection(row);
    });reply.status(201);return envelope(data,request);
  });
  app.post('/v1/operator/school-opening-links/:linkId/revoke',async request=>{
    const identity=await operator(request);empty.parse(request.query);const {linkId}=z.object({linkId:z.uuid()}).parse(request.params);
    const body=operationBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const data=await transaction(options.pool,identity,true,undefined,async db=>{
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`opening-revoke:${identity.issuer}:${identity.subject}:${body.operationId}`]);
      const known=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE revoked_by_issuer=$1 AND revoked_by_subject=$2 AND revoke_operation_id=$3',
        [identity.issuer,identity.subject,body.operationId])).rows[0];
      if(known){if(known.id!==linkId)throw mismatch();return openingLinkProjection(known);}
      const initial=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE id=$1',[linkId])).rows[0];
      if(!initial)throw notFound();if(initial.status==='USED')throw new ApiError(409,'OPENING_LINK_USED','Ce lien a déjà été utilisé.');
      const row=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE id=$1 FOR UPDATE',[linkId])).rows[0];
      if(!row)throw new ApiError(409,'OPENING_LINK_USED','Ce lien a déjà été utilisé.');
      if(row.status==='REVOKED')throw new ApiError(409,'OPENING_LINK_REVOKED','Ce lien a déjà été révoqué.');
      return openingLinkProjection((await db.query<OpeningLinkRow>("UPDATE drivy.school_opening_link SET status='REVOKED',revoked_at=clock_timestamp(),revoke_operation_id=$2,revoked_by_issuer=$3,revoked_by_subject=$4 WHERE id=$1 RETURNING *",[linkId,body.operationId,identity.issuer,identity.subject])).rows[0]!);
    });return envelope(data,request);
  });
  app.post('/v1/school-openings/preview',async request=>{
    const identity=await options.verifyToken(request.headers.authorization);empty.parse(request.query);const {token}=openingPreviewBody.parse(request.body);
    const data=await transaction(options.pool,identity,false,token,async db=>{
      const row=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE token_hash=$1',[openingHash(token)])).rows[0];
      if(!row)throw invalid();
      if(row.status==='USED')return {status:'USED',school:await currentResult(db,row,identity)};
      assertAvailable(row);return {status:'AVAILABLE',expiresAt:row.expires_at.toISOString()};
    });return envelope(data,request);
  });
  app.post('/v1/school-openings',async(request,reply)=>{
    const identity=await options.verifyToken(request.headers.authorization);empty.parse(request.query);
    const body=schoolOpeningBody.parse(request.body);checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const data=await createSchool(options.pool,identity,body);reply.status(201);return envelope(data,request);
  });
  app.get('/v1/school-openings/operations/:operationId',async request=>{
    const identity=await options.verifyToken(request.headers.authorization);empty.parse(request.query);
    const {operationId}=operationBody.parse(request.params);
    const data=await transaction(options.pool,identity,false,undefined,async db=>{
      const row=(await db.query<OpeningLinkRow>('SELECT * FROM drivy.school_opening_link WHERE used_by_issuer=$1 AND used_by_subject=$2 AND consume_operation_id=$3',[identity.issuer,identity.subject,operationId])).rows[0];
      if(!row)throw notFound();return currentResult(db,row,identity);
    });return envelope(data,request);
  });
}
