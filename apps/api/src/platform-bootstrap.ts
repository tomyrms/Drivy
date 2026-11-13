import { randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import { readPlatformBootstrap, type PlatformBootstrapEntry } from './platform-model.js';
import { readSchoolOpeningConfig } from './school-opening-model.js';

export type BootstrapSource = 'PRIVATE_CONFIG' | 'LEGACY_OPENING_LIST';
export interface BootstrapReport { added: number; alreadyActive: number }

/**
 * Identités à mettre en service. La configuration privée (`PLATFORM_OPERATORS_BOOTSTRAP_JSON`) est la voie normale ;
 * l'ancienne liste d'ouverture (`SCHOOL_OPENING_OPERATORS_JSON`) n'est reprise que sur demande explicite (`legacyOpeningOperators`).
 */
export function readBootstrapEntries(env: NodeJS.ProcessEnv, options: { legacyOpeningOperators?: boolean } = {}): Array<PlatformBootstrapEntry & { source: BootstrapSource }> {
  const entries: Array<PlatformBootstrapEntry & { source: BootstrapSource }> = readPlatformBootstrap(env).map(entry => ({ ...entry, source: 'PRIVATE_CONFIG' as const }));
  if (options.legacyOpeningOperators) {
    for (const operator of readSchoolOpeningConfig(env).operators) {
      if (!entries.some(entry => entry.issuer === operator.issuer && entry.subject === operator.subject))
        entries.push({ issuer: operator.issuer, subject: operator.subject, source: 'LEGACY_OPENING_LIST' });
    }
  }
  if (entries.length > 10) throw new Error('Au plus dix opérateurs peuvent être mis en service à la fois.');
  return entries;
}

/**
 * Mise en service explicite des premiers opérateurs, avec la connexion propriétaire (celle des migrations) : tant qu'elle n'a pas été
 * lancée, personne n'a accès à la console. Idempotente : une identité déjà active est laissée telle quelle. Chaque ajout est tracé au
 * journal commercial par un événement SYSTEM. Le rapport ne contient que des nombres, jamais d'identifiant.
 */
export async function bootstrapPlatformOperators(pool: Pool, entries: Array<PlatformBootstrapEntry & { source?: BootstrapSource }>): Promise<BootstrapReport> {
  if (entries.length === 0) throw new Error('Aucune identité à mettre en service : renseigner PLATFORM_OPERATORS_BOOTSTRAP_JSON.');
  const db = await pool.connect();
  const report: BootstrapReport = { added: 0, alreadyActive: 0 };
  try {
    await db.query('BEGIN');
    // Même verrou d'équipe que les révocations : l'amorçage ne croise jamais un retrait en cours.
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['drivy.platform_operator.team']);
    let position = Number((await db.query<{ n: string }>("SELECT count(*) AS n FROM drivy.platform_operator WHERE status='ACTIVE'")).rows[0]!.n);
    for (const entry of entries) {
      const known = await db.query("SELECT 1 FROM drivy.platform_operator WHERE issuer=$1 AND subject=$2 AND status='ACTIVE'", [entry.issuer, entry.subject]);
      if (known.rowCount) { report.alreadyActive += 1; continue; }
      position += 1;
      const id = randomUUID();
      const displayName = entry.displayName ?? `Opérateur ${position}`;
      await db.query(`INSERT INTO drivy.platform_operator(id,issuer,subject,display_name,added_via) VALUES($1,$2,$3,$4,'BOOTSTRAP')`, [id, entry.issuer, entry.subject, displayName]);
      await db.query(`INSERT INTO drivy.platform_audit_event(id,actor_kind,actor_name,action,result,subject_type,subject_id,changes)
        VALUES($1,'SYSTEM','Mise en service','BOOTSTRAP_PLATFORM_OPERATOR','SUCCESS','PlatformOperator',$2,$3::jsonb)`,
      [randomUUID(), id, JSON.stringify({ level: 'COMMERCIAL', source: entry.source ?? 'PRIVATE_CONFIG' })]);
      report.added += 1;
    }
    await db.query('COMMIT');
    return report;
  } catch (error) { await db.query('ROLLBACK').catch(() => undefined); throw error; }
  finally { db.release(); }
}
