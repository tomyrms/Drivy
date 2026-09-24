import type { Pool, PoolClient } from 'pg';
import type { Identity } from './auth.js';
import { ApiError, forbidden } from './errors.js';

export interface Actor { personId: string; displayName: string; locale: string; version: number }
export interface Membership { id: string; roles: string[]; grants: string[]; accessEpoch: number }
export async function withActor<T>(pool: Pool, identity: Identity, schoolId: string | undefined,
  work: (db: PoolClient, actor: Actor, membership: Membership | undefined) => Promise<T>): Promise<T> {
  const db = await pool.connect();
  try {
    // Les projections d'une réponse partagent versions et droits d'un même instant.
    await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true), set_config('app.subject',$2,true), set_config('app.school_id',$3,true)", [identity.issuer, identity.subject, schoolId ?? '']);
    const link = await db.query<{ person_id: string }>('SELECT person_id FROM drivy.identity_link WHERE issuer=$1 AND subject=$2', [identity.issuer, identity.subject]);
    if (!link.rows[0]) throw new ApiError(403, 'IDENTITY_NOT_LINKED', 'Ce compte ne dispose pas encore d’un accès Drivy.');
    await db.query("SELECT set_config('app.person_id',$1,true)", [link.rows[0].person_id]);
    const result = await db.query<Actor>('SELECT id AS "personId", display_name AS "displayName", locale, version FROM drivy.person WHERE id=$1 AND status=\'ACTIVE\'', [link.rows[0].person_id]);
    const actor = result.rows[0];
    if (!actor) throw forbidden();
    let membership: Membership | undefined;
    if (schoolId) {
      const result = await db.query<Membership>('SELECT id,roles,grants,access_epoch AS "accessEpoch" FROM drivy.membership WHERE school_id=$1 AND person_id=$2 AND status=\'ACTIVE\'', [schoolId, actor.personId]);
      membership = result.rows[0];
      if (!membership) throw forbidden();
    }
    const value = await work(db, actor, membership);
    await db.query('COMMIT');
    return value;
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  } finally { db.release(); }
}
