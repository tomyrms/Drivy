import { createHash, randomUUID } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import type { Identity } from './auth.js';
import { ApiError, forbidden, notFound } from './errors.js';

export interface CommandActor { personId: string; membershipId: string; roles:string[] }
export interface SchoolRow {
  id: string; version: number; name: string; timeZone: string; status: 'DRAFT'|'ACTIVE'|'ARCHIVED';
  contactEmail: string; contactPhone: string|null; configurationVersion: number;
  modules: { gpsEnabled: boolean; packsEnabled: boolean; collectiveCoursesEnabled: boolean; courseOffersVisibleByDefault: boolean };
}
export const schoolColumns = `id,version,name,time_zone AS "timeZone",status,contact_email AS "contactEmail",
  contact_phone AS "contactPhone",configuration_version AS "configurationVersion",modules`;
export function schoolProjection(school: SchoolRow) { return { ...school, schoolId:school.id, logoAssetId:null }; }
export function requireVersion(header: string|string[]|undefined): number {
  if (header === undefined) throw new ApiError(428,'PRECONDITION_REQUIRED','La version affichée est requise.');
  if (typeof header !== 'string' || !/^"[1-9][0-9]*"$/.test(header)) throw new ApiError(400,'INVALID_REQUEST','Version forte invalide.');
  const value = Number(header.slice(1,-1));
  if (!Number.isSafeInteger(value) || value > 2_147_483_647) throw new ApiError(400,'INVALID_REQUEST','Version invalide.');
  return value;
}
export function checkVersion(actual: number, expected: number) {
  if (actual !== expected) throw new ApiError(412,'VERSION_CONFLICT','Cette configuration a changé. Rechargez-la avant de confirmer.');
}
export function checkIdempotency(header: string|string[]|undefined, operationId: string) {
  if (typeof header !== 'string' || header.toLowerCase() !== operationId.toLowerCase()) {
    throw new ApiError(400,'INVALID_REQUEST','Idempotency-Key doit correspondre à operationId.');
  }
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.entries(value).sort(([a],[b])=>a.localeCompare(b))
    .map(([key,item])=>`${JSON.stringify(key)}:${canonical(item)}`).join(',')}}`;
  return JSON.stringify(value);
}
export interface CommandEffect<T> { data:T; action:string; resourceType:string; resourceId:string; resourceVersion?:number; changedFields:string[];reason?:string }
export interface CommandGuards<T> {
  additionalPersons?:(db:PoolClient)=>Promise<string[]>;
  writeMemberships?:(db:PoolClient)=>Promise<string[]>;
  authorize?:(db:PoolClient,actor:CommandActor,school:SchoolRow)=>Promise<void>;
  replay?:(db:PoolClient,actor:CommandActor,data:T)=>Promise<T>;
}
export const commandHash = (body:unknown,expectedVersion:number|null) => createHash('sha256').update(canonical({body,expectedVersion})).digest('hex');
export async function recordCommand<T>(db:PoolClient,actor:CommandActor,schoolId:string,commandType:string,operationId:string,hash:string,effect:CommandEffect<T>) {
  const resourceVersion=effect.resourceVersion ?? (effect.data as {version?:number}).version ?? 1;
  await db.query(`INSERT INTO drivy.operation(actor_person_id,operation_id,school_id,command_type,payload_hash,resource_id,response_data,resource_version)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,[actor.personId,operationId,schoolId,commandType,hash,effect.resourceId,JSON.stringify(effect.data),resourceVersion]);
  await db.query(`INSERT INTO drivy.audit_event(id,school_id,actor_person_id,actor_membership_id,operation_id,action,resource_type,resource_id,changed_fields,reason)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,[randomUUID(),schoolId,actor.personId,actor.membershipId,operationId,effect.action,effect.resourceType,effect.resourceId,effect.changedFields,effect.reason ?? null]);
}

/** Un seul commit contient l'effet, sa preuve durable et son audit ; aucun appel réseau sous verrou. */
export async function schoolCommand<T>(pool: Pool, identity: Identity, schoolId: string,
  commandType: string, body: { operationId:string }, expectedVersion: number|null,
  work: (db:PoolClient, actor:CommandActor, school:SchoolRow)=>Promise<CommandEffect<T>>, allowedRoles:string[]=['ADMIN'],guards:CommandGuards<T>={}): Promise<T> {
  const hash = commandHash(body,expectedVersion);
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    await db.query("SET LOCAL lock_timeout='5s'");
    await db.query("SET LOCAL statement_timeout='10s'");
    await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true)",
      [identity.issuer,identity.subject,schoolId]);
    const link = await db.query<{person_id:string}>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2',[identity.issuer,identity.subject]);
    const personId = link.rows[0]?.person_id;
    if (!personId) throw new ApiError(403,'IDENTITY_NOT_LINKED','Ce compte ne dispose pas encore d’un accès Drivy.');
    await db.query("SELECT set_config('app.person_id',$1,true)",[personId]);
    const personIds=[...new Set([personId,...(await guards.additionalPersons?.(db) ?? [])])].sort();
    const person = await db.query("SELECT id FROM drivy.person WHERE id=ANY($1::uuid[]) AND status='ACTIVE' ORDER BY id FOR SHARE",[personIds]);
    if (person.rowCount!==personIds.length) throw forbidden();
    // La clé est globale pour cet auteur, même si deux commandes ciblent deux écoles.
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`${personId}:${body.operationId.toLowerCase()}`]);
    const preliminary = await db.query<{id:string;roles:string[]}>("SELECT id,roles FROM drivy.membership WHERE school_id=$1 AND person_id=$2 AND status='ACTIVE'",[schoolId,personId]);
    if (!preliminary.rows[0]) throw notFound();
    if (!allowedRoles.some(role=>preliminary.rows[0]!.roles.includes(role))) throw new ApiError(403,'SETUP_ACCESS_REQUIRED','Les droits nécessaires ne sont pas disponibles.');
    const result = await db.query<SchoolRow>(`SELECT ${schoolColumns} FROM drivy.school WHERE id=$1 FOR UPDATE`,[schoolId]);
    const school = result.rows[0];
    if (!school) throw notFound();
    const writeMemberships=await guards.writeMemberships?.(db) ?? [];
    const membershipIds=[...new Set([preliminary.rows[0].id,...writeMemberships])].sort();
    const locked=await db.query<{id:string;roles:string[]}>(`SELECT id,roles FROM drivy.membership WHERE school_id=$1 AND id=ANY($2::uuid[]) AND status='ACTIVE' ORDER BY id FOR ${writeMemberships.length?'UPDATE':'SHARE'}`,[schoolId,membershipIds]);
    const member=locked.rows.find(row=>row.id===preliminary.rows[0]!.id);
    if (!member || locked.rowCount!==membershipIds.length || !allowedRoles.some(role=>member.roles.includes(role))) throw new ApiError(403,'SETUP_ACCESS_REQUIRED','Les droits nécessaires ne sont plus disponibles.');
    const actor = { personId,membershipId:member.id,roles:member.roles };
    await db.query("SELECT set_config('app.membership_id',$1,true)",[actor.membershipId]);
    await guards.authorize?.(db,actor,school);
    const previous = await db.query<{school_id:string;command_type:string;payload_hash:string;response_data:T}>(
      'SELECT school_id,command_type,payload_hash,response_data FROM drivy.operation WHERE actor_person_id=$1 AND operation_id=$2',[personId,body.operationId]);
    const known = previous.rows[0];
    if (known) {
      if (known.school_id !== schoolId || known.command_type !== commandType || known.payload_hash !== hash) {
        throw new ApiError(409,'IDEMPOTENCY_MISMATCH','Cette opération a déjà été utilisée avec un autre contenu ou contexte.');
      }
      const data=guards.replay?await guards.replay(db,actor,known.response_data):known.response_data;
      await db.query('COMMIT');
      return data;
    }
    if (school.status === 'ARCHIVED') throw new ApiError(409,'SCHOOL_ARCHIVED','Cette école archivée ne peut plus être configurée.');
    const effect = await work(db,actor,school);
    await recordCommand(db,actor,schoolId,commandType,body.operationId,hash,effect);
    await db.query('COMMIT');
    return effect.data;
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  } finally { db.release(); }
}
