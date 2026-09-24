import { createHash,randomBytes,randomUUID } from 'node:crypto';
import type { FastifyInstance,FastifyRequest } from 'fastify';
import type { Pool,PoolClient } from 'pg';
import { z } from 'zod';
import type { Identity,TokenVerifier } from './auth.js';
import { withActor } from './database.js';
import { checkIdempotency,checkVersion,commandHash,recordCommand,requireVersion,schoolColumns,schoolCommand,type SchoolRow } from './commands.js';
import { Cursors } from './cursor.js';
import { ApiError,forbidden,notFound } from './errors.js';
import { cancelInvitationMail,queueInvitationMail,type InvitationMailConfig } from './invitation-mail.js';

const empty=z.object({}).strict();const operation={operationId:z.uuid()};
const tokenBody=z.object({token:z.string().min(32).max(256)}).strict();
const acceptBody=tokenBody.extend(operation);
const createBody=z.object({...operation,email:z.email().max(254),roles:z.array(z.enum(['ADMIN','INSTRUCTOR','LEARNER'])).min(1).max(3).refine(value=>new Set(value).size===value.length)}).strict();
const reasonBody=z.object({...operation,reason:z.string().trim().refine(value=>[...value].length>=1 && [...value].length<=1000)}).strict();
const pagination=z.object({limit:z.coerce.number().int().min(1).max(100).default(50),cursor:z.string().max(6000).optional()}).strict();
const parameters=z.object({schoolId:z.uuid(),invitationId:z.uuid().optional()});
const digest=(token:string)=>createHash('sha256').update(token).digest('hex');
const normalizeEmail=(email:string)=>email.trim().normalize('NFC').toLowerCase();
interface InvitationRow {
  id:string;school_id:string;email:string;roles:string[];token_hash:string;status:'PENDING'|'ACCEPTED'|'REVOKED';version:number;
  expires_at:Date;inviter_membership_id:string;inviter_person_id:string;accepted_by_person_id:string|null;notice_version:number;_createdAt?:string;
}
function projection(row:InvitationRow) {
  const [local,domain]=row.email.split('@');const maskedEmail=`${[...(local ?? '')][0] ?? '*'}***@${domain}`;
  return {id:row.id,schoolId:row.school_id,version:row.version,maskedEmail,roles:row.roles,
    status:row.status==='PENDING' && row.expires_at.getTime()<=Date.now()?'EXPIRED':row.status,expiresAt:row.expires_at.toISOString()};
}
function activeSchool(school:SchoolRow) {if(school.status!=='ACTIVE') throw new ApiError(409,'SCHOOL_NOT_ACTIVE','Cette école doit être active pour gérer ses invitations.');}
function allowedRoles(actorRoles:string[],roles:string[]) {
  if(!actorRoles.includes('ADMIN') && !(actorRoles.includes('INSTRUCTOR') && roles.length===1 && roles[0]==='LEARNER'))
    throw new ApiError(403,'INVITATION_ROLE_FORBIDDEN','Vous pouvez uniquement inviter un élève.');
}
function usable(row:InvitationRow,personId?:string) {
  if(row.status==='REVOKED') throw new ApiError(409,'INVITATION_REVOKED','Cette invitation a été révoquée.');
  if(row.status==='ACCEPTED' && row.accepted_by_person_id!==personId) throw new ApiError(409,'INVITATION_USED','Cette invitation a déjà été utilisée.');
  if(row.status==='PENDING' && row.expires_at.getTime()<=Date.now()) throw new ApiError(410,'INVITATION_EXPIRED','Cette invitation a expiré. Demandez un nouveau lien à l’école.');
}
async function target(db:PoolClient):Promise<InvitationRow> {
  const row=(await db.query<InvitationRow>('SELECT * FROM drivy.invitation WHERE token_hash=current_setting(\'app.invitation_hash\') AND email=current_setting(\'app.verified_email\')')).rows[0];
  if(!row) throw new ApiError(403,'INVITATION_IDENTITY_MISMATCH','Le lien ne correspond pas à cette identité vérifiée, ou n’est plus utilisable.');
  return row;
}
async function context(db:PoolClient,identity:Identity,token:string) {
  if(!identity.verifiedEmail) throw new ApiError(403,'INVITATION_IDENTITY_MISMATCH','Une adresse vérifiée par le fournisseur d’identité est requise.');
  await db.query('SET LOCAL ROLE drivy_app');
  await db.query(`SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.invitation_hash',$3,true),set_config('app.verified_email',$4,true)`,
    [identity.issuer,identity.subject,digest(token),identity.verifiedEmail]);
  const person=(await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[identity.issuer,identity.subject])).rows[0]?.person_id;
  await db.query("SELECT set_config('app.person_id',$1,true)",[person ?? '']);return person;
}
async function memberContext(db:PoolClient,school:SchoolRow,personId:string) {
  const member=(await db.query<{membershipId:string;roles:string[];grants:string[];accessEpoch:number;version:number}>(`SELECT id AS "membershipId",roles,grants,access_epoch AS "accessEpoch",version
    FROM drivy.membership WHERE school_id=$1 AND person_id=$2 AND status='ACTIVE'`,[school.id,personId])).rows[0];
  if(!member) throw forbidden();
  const {version,...data}=member;return {data:{...data,schoolId:school.id,schoolName:school.name},version};
}
async function preview(pool:Pool,identity:Identity,token:string) {
  const db=await pool.connect();try {
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');const personId=await context(db,identity,token);
    const invitation=await target(db);usable(invitation,personId);await db.query("SELECT set_config('app.school_id',$1,true)",[invitation.school_id]);
    const school=(await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1`,[invitation.school_id])).rows[0];
    if(!school) throw notFound();activeSchool(school);
    const inviter=(await db.query<{roles:string[]}>(`SELECT m.roles FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
      WHERE m.id=$1 AND m.status='ACTIVE' AND p.status='ACTIVE'`,[invitation.inviter_membership_id])).rows[0];
    if(invitation.status==='PENDING') {if(!inviter) throw new ApiError(409,'INVITATION_REVOKED','Les droits de l’émetteur ne permettent plus cette invitation.');allowedRoles(inviter.roles,invitation.roles);}
    if(personId) {if(!(await db.query("SELECT id FROM drivy.person WHERE id=$1 AND status='ACTIVE'",[personId])).rowCount) throw forbidden();}
    if(invitation.status==='ACCEPTED') await memberContext(db,school,personId!);
    const notice=(await db.query(`SELECT version,notice_text AS "noticeText",retention_text AS "retentionText",contact_email AS "contactEmail"
      FROM drivy.school_data_policy WHERE school_id=$1 AND version=$2 AND approved_at IS NOT NULL`,[school.id,invitation.notice_version])).rows[0];
    if(!notice) throw new ApiError(409,'POLICY_REVIEW_REQUIRED','La notice de l’école n’est pas disponible.');
    await db.query('COMMIT');const dto=projection(invitation);
    return {invitationId:invitation.id,schoolId:school.id,schoolName:school.name,roles:invitation.roles,maskedEmail:dto.maskedEmail,expiresAt:dto.expiresAt,notice};
  } catch(error) {await db.query('ROLLBACK');throw error;} finally {db.release();}
}
async function accept(pool:Pool,identity:Identity,body:z.infer<typeof acceptBody>) {
  const db=await pool.connect();try {
    await db.query('BEGIN');await db.query("SET LOCAL lock_timeout='5s'");await db.query("SET LOCAL statement_timeout='10s'");
    // L'identité OIDC est sérialisée avant la création d'une personne, même entre deux écoles.
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`oidc:${identity.issuer}:${identity.subject}`]);
    const linked=await context(db,identity,body.token);const personId=linked ?? randomUUID();
    await db.query("SELECT set_config('app.person_id',$1,true)",[personId]);
    const initial=await target(db);usable(initial,personId);
    await db.query("SELECT set_config('app.school_id',$1,true)",[initial.school_id]);
    const persons=await db.query<{id:string;status:string}>('SELECT id,status FROM drivy.person WHERE id=ANY($1::uuid[]) ORDER BY id FOR SHARE',[[personId,initial.inviter_person_id]]);
    if(linked && !persons.rows.some(p=>p.id===personId && p.status==='ACTIVE')) throw forbidden();
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`${personId}:${body.operationId.toLowerCase()}`]);
    const school=(await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1 FOR UPDATE`,[initial.school_id])).rows[0];
    if(!school) throw notFound();activeSchool(school);
    const members=await db.query<{id:string;person_id:string;roles:string[];grants:string[];status:string;version:number}>(`SELECT id,person_id,roles,grants,status,version FROM drivy.membership
      WHERE school_id=$1 AND (person_id=$2 OR id=$3) ORDER BY id FOR UPDATE`,[school.id,personId,initial.inviter_membership_id]);
    const invitation=(await db.query<InvitationRow>('SELECT * FROM drivy.invitation WHERE id=$1 FOR UPDATE',[initial.id])).rows[0];
    if(!invitation || invitation.token_hash!==digest(body.token) || invitation.email!==identity.verifiedEmail)
      throw new ApiError(403,'INVITATION_IDENTITY_MISMATCH','Le lien ne correspond pas à cette identité vérifiée, ou n’est plus utilisable.');
    usable(invitation,personId);
    const hash=commandHash(body,null);
    const known=(await db.query<{school_id:string;command_type:string;payload_hash:string}>(`SELECT school_id,command_type,payload_hash FROM drivy.operation
      WHERE actor_person_id=$1 AND operation_id=$2`,[personId,body.operationId])).rows[0];
    if(known && (known.school_id!==school.id || known.command_type!=='ACCEPT_INVITATION' || known.payload_hash!==hash))
      throw new ApiError(409,'IDEMPOTENCY_MISMATCH','Cette opération a déjà été utilisée avec un autre contenu ou contexte.');
    if(invitation.status!=='ACCEPTED') {
      const inviter=members.rows.find(m=>m.id===invitation.inviter_membership_id);
      if(!inviter || inviter.status!=='ACTIVE' || !persons.rows.some(p=>p.id===invitation.inviter_person_id && p.status==='ACTIVE'))
        throw new ApiError(409,'INVITATION_REVOKED','Les droits de l’émetteur ne permettent plus cette invitation.');
      allowedRoles(inviter.roles,invitation.roles);
      if(!linked) {
        await db.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2)',[personId,identity.displayName ?? 'Profil à compléter']);
        await db.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)',[identity.issuer,identity.subject,personId]);
      }
      const existing=members.rows.find(m=>m.person_id===personId);
      const onboarding=JSON.stringify({status:'IN_PROGRESS',currentStep:'PROFILE',completedSteps:[],noticeVersion:invitation.notice_version,source:'SELF'});
      if(existing) {
        const roles=existing.status==='ACTIVE'?[...new Set([...existing.roles,...invitation.roles])]:invitation.roles;
        await db.query(`UPDATE drivy.membership SET status='ACTIVE',roles=$2,grants=$3,version=version+1,access_epoch=access_epoch+1,
          invitation_email=$4,onboarding=CASE WHEN onboarding='{}'::jsonb THEN $5::jsonb ELSE onboarding END WHERE id=$1`,
          [existing.id,roles,existing.status==='ACTIVE'?existing.grants:[],identity.verifiedEmail,onboarding]);
      } else await db.query(`INSERT INTO drivy.membership(id,school_id,person_id,roles,invitation_email,onboarding) VALUES($1,$2,$3,$4,$5,$6)`,
        [randomUUID(),school.id,personId,invitation.roles,identity.verifiedEmail,onboarding]);
      if(invitation.roles.includes('LEARNER')) {
        const learner=(await db.query('SELECT id,archived_at FROM drivy.learner_profile WHERE school_id=$1 AND person_id=$2',[school.id,personId])).rows[0];
        if(learner?.archived_at) throw new ApiError(409,'LEARNER_ARCHIVED','Le dossier existant doit être traité par l’administration.');
        if(!learner) await db.query(`INSERT INTO drivy.learner_profile(id,school_id,person_id,display_name,contact_email,profile_readiness)
          SELECT $1,$2,id,display_name,$3,'MINIMAL' FROM drivy.person WHERE id=$4`,[randomUUID(),school.id,identity.verifiedEmail,personId]);
      }
      await db.query("UPDATE drivy.invitation SET status='ACCEPTED',accepted_by_person_id=$2,version=version+1 WHERE id=$1",[invitation.id,personId]);
      await cancelInvitationMail(db,invitation.id);
    }
    const current=await memberContext(db,school,personId);
    if(!known) await recordCommand(db,{personId,membershipId:current.data.membershipId,roles:current.data.roles},school.id,'ACCEPT_INVITATION',body.operationId,hash,
      {data:current.data,resourceType:'Membership',resourceId:current.data.membershipId,resourceVersion:current.version,
        action:invitation.status==='ACCEPTED'?'InvitationAcceptanceConfirmed':'InvitationAccepted',changedFields:invitation.status==='ACCEPTED'?[]:['membership','learnerProfile','status']});
    await db.query('COMMIT');return current.data;
  } catch(error) {await db.query('ROLLBACK');throw error;} finally {db.release();}
}
export function registerInvitations(app:FastifyInstance,options:{pool:Pool;verifyToken:TokenVerifier;cursorSecret:string;invitationMail?:InvitationMailConfig}) {
  const cursors=new Cursors(options.cursorSecret);const envelope=(data:unknown,request:FastifyRequest)=>({data,requestId:request.id,serverTime:new Date().toISOString()});
  app.post('/v1/invitations/preview',async request=>{empty.parse(request.query);const body=tokenBody.parse(request.body);
    return envelope(await preview(options.pool,await options.verifyToken(request.headers.authorization),body.token),request);});
  app.post('/v1/invitations/accept',async(request,reply)=>{empty.parse(request.query);const body=acceptBody.parse(request.body);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const data=await accept(options.pool,await options.verifyToken(request.headers.authorization),body);
    reply.code(201);return envelope(data,request);});
  app.get('/v1/schools/:schoolId/invitations',async request=>{
    const {schoolId}=parameters.parse(request.params);const query=pagination.parse(request.query);const identity=await options.verifyToken(request.headers.authorization);
    const data=await withActor(options.pool,identity,schoolId,async(db,actor,member)=>{
      if(!member || !member.roles.some(role=>['ADMIN','INSTRUCTOR'].includes(role))) throw forbidden();
      const scope=JSON.stringify(['invitations',schoolId,actor.personId,member.accessEpoch,query.limit]);const cursor=cursors.decode(query.cursor,scope);
      const rows=await db.query<InvitationRow>(`SELECT *,to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "_createdAt"
        FROM drivy.invitation WHERE school_id=$1 AND ($2::boolean OR (inviter_membership_id=$3 AND roles=ARRAY['LEARNER']::text[]))
        AND ($4::timestamptz IS NULL OR (created_at,id)>($4,$5::uuid)) ORDER BY created_at,id LIMIT $6`,
        [schoolId,member.roles.includes('ADMIN'),member.id,cursor?.createdAt ?? null,cursor?.id ?? null,query.limit+1]);
      const last=rows.rows.length>query.limit?rows.rows[query.limit-1]:undefined;
      return {items:rows.rows.slice(0,query.limit).map(projection),nextCursor:last?cursors.encode(scope,{id:last.id,createdAt:last._createdAt!}):null};
    });return envelope(data,request);
  });
  app.post('/v1/schools/:schoolId/invitations',async(request,reply)=>{
    empty.parse(request.query);const {schoolId}=parameters.parse(request.params);const parsed=createBody.parse(request.body);
    const body={...parsed,email:normalizeEmail(parsed.email),roles:[...parsed.roles].sort()};checkIdempotency(request.headers['idempotency-key'],body.operationId);
    const identity=await options.verifyToken(request.headers.authorization);
    const data=await schoolCommand(options.pool,identity,schoolId,'CREATE_INVITATION',body,null,async(db,actor,school)=>{
      activeSchool(school);allowedRoles(actor.roles,body.roles);
      if(!options.invitationMail) throw new ApiError(503,'INVITATION_DELIVERY_UNAVAILABLE','L’envoi des invitations n’est pas configuré.');
      if((await db.query('SELECT drivy.invitation_member_exists($1,$2) AS present',[school.id,body.email])).rows[0].present)
        throw new ApiError(409,'ALREADY_MEMBER','Cette adresse correspond déjà à un membre de l’école.');
      if((await db.query('SELECT drivy.invitation_pending_exists($1,$2) AS present',[school.id,body.email])).rows[0].present)
        throw new ApiError(409,'INVITATION_ALREADY_PENDING','Une invitation est déjà en attente pour cette adresse.');
      const notice=(await db.query('SELECT version FROM drivy.school_data_policy WHERE school_id=$1 AND approved_at IS NOT NULL ORDER BY version DESC LIMIT 1',[school.id])).rows[0];
      if(!notice) throw new ApiError(409,'POLICY_REVIEW_REQUIRED','La notice de l’école doit être approuvée avant une invitation.');
      const id=randomUUID();const token=randomBytes(32).toString('base64url');
      const row=(await db.query<InvitationRow>(`INSERT INTO drivy.invitation(id,school_id,email,roles,token_hash,expires_at,inviter_membership_id,inviter_person_id,notice_version)
        VALUES($1,$2,$3,$4,$5,now()+interval '7 days',$6,$7,$8) RETURNING *`,[id,school.id,body.email,body.roles,digest(token),actor.membershipId,actor.personId,notice.version])).rows[0]!;
      await queueInvitationMail(db,options.invitationMail,school.id,id,row.version,{email:body.email,token,roles:body.roles,schoolName:school.name});
      return {data:projection(row),action:'InvitationCreated',resourceType:'Invitation',resourceId:id,changedFields:['email','roles','status']};
    },['ADMIN','INSTRUCTOR']);reply.code(201).header('ETag',`"${data.version}"`);return envelope(data,request);
  });
  for(const action of ['resend','revoke'] as const) app.post(`/v1/schools/:schoolId/invitations/:invitationId/${action}`,async(request,reply)=>{
    empty.parse(request.query);const {schoolId,invitationId}=parameters.parse(request.params);
    const body=action==='revoke'?reasonBody.parse(request.body):z.object(operation).strict().parse(request.body);
    checkIdempotency(request.headers['idempotency-key'],body.operationId);const expected=requireVersion(request.headers['if-match']);
    const commandType=action==='resend'?'RESEND_INVITATION':'REVOKE_INVITATION';
    const data=await schoolCommand(options.pool,await options.verifyToken(request.headers.authorization),schoolId,commandType,{...body,invitationId} as typeof body,expected,async(db,actor,school)=>{
      activeSchool(school);const current=(await db.query<InvitationRow>('SELECT * FROM drivy.invitation WHERE id=$1 AND school_id=$2 FOR UPDATE',[invitationId,schoolId])).rows[0];
      if(!current) throw notFound();allowedRoles(actor.roles,current.roles);
      if(!actor.roles.includes('ADMIN') && current.inviter_membership_id!==actor.membershipId) throw notFound();
      checkVersion(current.version,expected);
      if(current.status==='ACCEPTED') throw new ApiError(409,'INVITATION_USED','Cette invitation a déjà été utilisée.');
      if(current.status==='REVOKED') throw new ApiError(409,'INVITATION_REVOKED','Cette invitation a été révoquée.');
      await cancelInvitationMail(db,current.id);let row:InvitationRow;
      if(action==='revoke') row=(await db.query<InvitationRow>("UPDATE drivy.invitation SET status='REVOKED',version=version+1,revoked_reason=$2 WHERE id=$1 RETURNING *",[current.id,'reason' in body?body.reason:''])).rows[0]!;
      else {
        if(!options.invitationMail) throw new ApiError(503,'INVITATION_DELIVERY_UNAVAILABLE','L’envoi des invitations n’est pas configuré.');
        const token=randomBytes(32).toString('base64url');row=(await db.query<InvitationRow>(`UPDATE drivy.invitation SET token_hash=$2,version=version+1,expires_at=now()+interval '7 days',
          notice_version=(SELECT max(version) FROM drivy.school_data_policy WHERE school_id=$3 AND approved_at IS NOT NULL) WHERE id=$1 RETURNING *`,[current.id,digest(token),school.id])).rows[0]!;
        await queueInvitationMail(db,options.invitationMail,school.id,row.id,row.version,{email:row.email,token,schoolName:school.name,roles:row.roles});
      }
      return {data:projection(row),action:action==='resend'?'InvitationResent':'InvitationRevoked',resourceType:'Invitation',resourceId:row.id,changedFields:action==='resend'?['expiresAt','token']:['status','reason']};
    },['ADMIN','INSTRUCTOR']);reply.header('ETag',`"${data.version}"`);return envelope(data,request);
  });
}
