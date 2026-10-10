import type { Pool, PoolClient } from 'pg';
import type { Identity } from './auth.js';
import { ApiError, forbidden } from './errors.js';

export interface Actor { personId: string; displayName: string; locale: string; version: number }
export interface Membership { id: string; roles: string[]; grants: string[]; accessEpoch: number }

/**
 * Annule la transaction sans jamais masquer l'erreur d'origine. Si ROLLBACK échoue (connexion coupée, PostgreSQL redémarré),
 * le client est inutilisable : l'appelant le détruit avec `release(true)` au lieu de le rendre sain au pool.
 */
export async function rollbackQuietly(db: PoolClient): Promise<boolean> {
  try { await db.query('ROLLBACK'); return true; } catch { return false; }
}

/**
 * Un client inactif dont la connexion tombe (redémarrage de PostgreSQL, sauvegarde, coupure réseau) émet « error » sur le Pool.
 * Sans écouteur, Node traite cet événement comme une exception non rattrapée et arrête tout le service.
 * Seul le nom de l'erreur est rapporté : un message SQL ou réseau peut contenir une adresse ou une donnée.
 */
export function guardPool(pool: Pool, report: (name: string) => void = name => { console.error(`Connexion inactive perdue (${name}).`); }): Pool {
  pool.on('error', error => { try { report(error instanceof Error ? error.name : 'Error'); } catch { /* le rapport ne doit jamais arrêter le service */ } });
  return pool;
}

export async function withActor<T>(pool: Pool, identity: Identity, schoolId: string | undefined,
  work: (db: PoolClient, actor: Actor, membership: Membership | undefined) => Promise<T>): Promise<T> {
  const db = await pool.connect();
  let broken = false;
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
    broken = !(await rollbackQuietly(db));
    throw error;
  } finally { db.release(broken); }
}
