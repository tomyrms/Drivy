import { randomUUID } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import type { Identity } from './auth.js';
import { commandHash } from './commands.js';
import { rollbackQuietly } from './database.js';
import { ApiError } from './errors.js';

/**
 * Point d'entrée commun des commandes de la plateforme (R01-T01). Les lots suivants (écoles et codes, offres, paiements,
 * suspension, annulation) écrivent leurs actions par ici : ils décrivent l'effet, la transaction fait le reste.
 *
 *  1. l'identité OIDC vérifiée par le service est reliée à l'équipe EN BASE, à chaque requête ;
 *  2. la clé d'opération (Idempotency-Key = operationId) est sérialisée, comparée au contenu, et rejouée depuis un reçu durable ;
 *  3. l'effet, le reçu et la ligne du journal commercial sont validés dans un seul commit ;
 *  4. un refus métier (conflit de version, dernier opérateur, état terminal…) est tracé au journal en « REFUSED ».
 */
export interface PlatformActor { operatorId: string; displayName: string }
export interface PlatformJournalEntry {
  action: string;
  /** École concernée, quand l'action en vise une : permet de filtrer le journal par école. */
  schoolId?: string | null;
  subject?: { type: string; id: string } | null;
  /** Modification utile, en valeurs simples. Jamais de code, de jeton, de secret ni d'adresse complète. */
  changes?: Record<string, unknown>;
}
export interface PlatformEffect<T> {
  data: T;
  status?: 200 | 201;
  journal: PlatformJournalEntry;
  /**
   * Mutation appliquée après l'écriture du reçu et du journal. Nécessaire quand l'effet retire les droits de l'acteur lui-même :
   * son reçu et sa ligne de journal doivent être écrits tant qu'il est encore opérateur.
   */
  apply?: (db: PoolClient) => Promise<void>;
}
export interface PlatformCommandSpec {
  /** Genre du reçu, aussi l'action du journal par défaut : MAJUSCULES_ET_TIRETS_BAS. */
  kind: string;
  operationId: string;
  /** Contenu comparé à l'identique lors d'un rejeu. Ne jamais y placer un code ou un secret en clair : y mettre son empreinte. */
  body: unknown;
  expectedVersion: number | null;
  /** Commande qui modifie l'équipe : elle prend le verrou d'équipe avant tout verrou de ligne. */
  teamWide?: boolean;
  /** Ce que le journal retient si la commande est refusée. */
  refusal?: Pick<PlatformJournalEntry, 'action' | 'schoolId' | 'subject'>;
  /** Contexte transactionnel complémentaire (codes d'ouverture d'école : R01-T02). */
  context?: Pick<PlatformContext, 'openingOperator'>;
}
export interface PlatformCommandResult<T> { data: T; status: number; replayed: boolean }

export const teamLockKey = 'drivy.platform_operator.team';
export const operatorRequired = () => new ApiError(403, 'PLATFORM_OPERATOR_REQUIRED', 'Cet espace est réservé à l’équipe Drivy.');
export const operationMismatch = () => new ApiError(409, 'IDEMPOTENCY_MISMATCH', 'Cette demande a déjà été utilisée avec un autre contenu.');

export interface PlatformContext {
  readOnly?: boolean; verifiedEmail?: string; invitationHash?: string;
  /** Route d'opérateur qui lit ou écrit les codes d'ouverture : pose l'indicateur que les politiques exigent EN PLUS de l'équipe en base. */
  openingOperator?: boolean;
}

/** Transaction sous le rôle applicatif : toute lecture et toute écriture passent par les politiques RLS de la base. */
export async function platformTransaction<T>(pool: Pool, identity: Identity, work: (db: PoolClient) => Promise<T>, context: PlatformContext = {}): Promise<T> {
  const db = await pool.connect(); let broken = false;
  try {
    await db.query(context.readOnly ? 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY' : 'BEGIN');
    await db.query("SET LOCAL lock_timeout='5s'"); await db.query("SET LOCAL statement_timeout='10s'");
    await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.verified_email',$3,true),set_config('app.platform_invitation_hash',$4,true),set_config('app.school_opening_operator',$5,true)",
      [identity.issuer, identity.subject, context.verifiedEmail ?? '', context.invitationHash ?? '', context.openingOperator ? 'true' : 'false']);
    const result = await work(db);
    await db.query('COMMIT');
    return result;
  } catch (error) { broken = !(await rollbackQuietly(db)); throw error; } finally { db.release(broken); }
}

/** L'opérateur actif de cette identité, relu dans la base ; `undefined` pour tout autre compte, y compris un ancien opérateur. */
export async function currentOperator(db: PoolClient, identity: Identity): Promise<PlatformActor | undefined> {
  const row = (await db.query<{ id: string; display_name: string }>(
    "SELECT id,display_name FROM drivy.platform_operator WHERE issuer=$1 AND subject=$2 AND status='ACTIVE'", [identity.issuer, identity.subject])).rows[0];
  return row ? { operatorId: row.id, displayName: row.display_name } : undefined;
}

/** Porte d'entrée de toute route de la plateforme : 403 pour un compte scolaire, un élève ou un ancien opérateur. */
export async function requirePlatformOperator(pool: Pool, identity: Identity): Promise<PlatformActor> {
  return platformTransaction(pool, identity, async db => {
    const actor = await currentOperator(db, identity);
    if (!actor) throw operatorRequired();
    return actor;
  }, { readOnly: true });
}

/** Lecture cohérente (un seul instantané) réservée à l'équipe. */
export async function platformRead<T>(pool: Pool, identity: Identity, work: (db: PoolClient, actor: PlatformActor) => Promise<T>,
  context: Pick<PlatformContext, 'openingOperator'> = {}): Promise<T> {
  return platformTransaction(pool, identity, async db => {
    const actor = await currentOperator(db, identity);
    if (!actor) throw operatorRequired();
    return work(db, actor);
  }, { ...context, readOnly: true });
}

const secretKey = /token|secret|password|passphrase|authorization|code_?hash|^code$/i;
function safeChanges(changes: Record<string, unknown>): string {
  const walk = (value: unknown, depth: number): void => {
    if (value === null || ['string', 'number', 'boolean'].includes(typeof value)) return;
    if (depth > 2 || typeof value !== 'object') throw new Error('Modification de journal non sérialisable.');
    for (const [key, item] of Object.entries(value)) {
      if (secretKey.test(key)) throw new Error('Un secret ne s’écrit jamais au journal commercial.');
      walk(item, depth + 1);
    }
  };
  walk(changes, 0);
  const text = JSON.stringify(changes);
  if (text.length > 4000) throw new Error('Modification de journal trop longue.');
  return text;
}

export interface JournalOutcome { result?: 'SUCCESS' | 'REFUSED'; reasonCode?: string; operationId?: string }
/** Écrit une ligne du journal commercial dans la transaction courante. L'acteur est celui que la base confirme à cet instant. */
export async function recordPlatformAction(db: PoolClient, actor: PlatformActor, entry: PlatformJournalEntry, outcome: JournalOutcome = {}): Promise<string> {
  const id = randomUUID();
  await db.query(`INSERT INTO drivy.platform_audit_event(id,actor_kind,actor_operator_id,actor_name,action,result,reason_code,school_id,subject_type,subject_id,operation_id,changes)
    VALUES($1,'OPERATOR',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
  [id, actor.operatorId, actor.displayName, entry.action, outcome.result ?? 'SUCCESS', outcome.reasonCode ?? null, entry.schoolId ?? null,
    entry.subject?.type ?? null, entry.subject?.id ?? null, outcome.operationId ?? null, safeChanges(entry.changes ?? {})]);
  return id;
}

export interface Receipt { kind: string; request_hash: string; status_code: number; response: unknown }
export async function readReceipt(db: PoolClient, identity: Identity, operationId: string): Promise<Receipt | undefined> {
  return (await db.query<Receipt>('SELECT kind,request_hash,status_code,response FROM drivy.platform_operation WHERE issuer=$1 AND subject=$2 AND operation_id=$3',
    [identity.issuer, identity.subject, operationId])).rows[0];
}
export async function writeReceipt(db: PoolClient, identity: Identity, kind: string, operationId: string, hash: string, status: number, data: unknown) {
  await db.query('INSERT INTO drivy.platform_operation(issuer,subject,operation_id,kind,request_hash,status_code,response) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb)',
    [identity.issuer, identity.subject, operationId, kind, hash, status, JSON.stringify(data)]);
}
export const lockOperation = (db: PoolClient, identity: Identity, operationId: string) =>
  db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [`platform-op:${identity.issuer}:${identity.subject}:${operationId.toLowerCase()}`]);
export const lockTeam = (db: PoolClient) => db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [teamLockKey]);

/** Garde-fous de la base rendus en refus métier lisibles (les déclencheurs restent la dernière barrière). */
export function databaseRefusal(error: unknown): ApiError | undefined {
  if (error instanceof ApiError) return undefined;
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : undefined;
  const message = error instanceof Error ? error.message : '';
  const constraint = typeof error === 'object' && error !== null && 'constraint' in error && typeof error.constraint === 'string' ? error.constraint : '';
  if (code === '23514' && message.includes('last_platform_operator')) return new ApiError(409, 'LAST_PLATFORM_OPERATOR', 'Le dernier opérateur actif ne peut pas être retiré.');
  if (code === '23514' && message.includes('platform_operator_terminal')) return new ApiError(409, 'PLATFORM_OPERATOR_REVOKED', 'Cet opérateur n’a plus d’accès.');
  if (code === '23514' && message.includes('platform_invitation_terminal')) return new ApiError(409, 'PLATFORM_INVITATION_CLOSED', 'Cette invitation n’est plus ouverte.');
  if (code === '23505' && constraint === 'platform_operator_active_identity') return new ApiError(409, 'PLATFORM_ALREADY_MEMBER', 'Ce compte fait déjà partie de l’équipe.');
  if (code === '23505' && constraint === 'platform_operator_active_email') return new ApiError(409, 'PLATFORM_OPERATOR_EXISTS', 'Cette adresse appartient déjà à un opérateur actif.');
  if (code === '23505' && constraint === 'platform_operator_one_per_invitation') return new ApiError(409, 'PLATFORM_INVITATION_USED', 'Cette invitation a déjà été utilisée.');
  if (code === '23505' && constraint === 'platform_operator_invitation_code_hash_key') return new ApiError(409, 'PLATFORM_CODE_TAKEN', 'Ce code est déjà attribué. Générez-en un autre.');
  // Fiches des écoles clientes (R01-T02).
  if (code === '23514' && message.includes('platform_client_code_pending')) return new ApiError(409, 'CLIENT_CODE_PENDING', 'Un code d’ouverture est encore utilisable pour cette fiche. Révoquez-le avant de rattacher une école existante.');
  if (code === '23514' && message.includes('platform_client_school_linked')) return new ApiError(409, 'CLIENT_SCHOOL_LINKED', 'Une école est déjà reliée à cette fiche.');
  if (code === '23505' && constraint === 'platform_client_school_id_key') return new ApiError(409, 'CLIENT_SCHOOL_ALREADY_LINKED', 'Cette école est déjà reliée à une autre fiche.');
  if (code === '23505' && constraint === 'school_opening_link_token_hash_key') return new ApiError(409, 'OPENING_CODE_TAKEN', 'Ce code est déjà attribué. Générez-en un autre.');
  if (code === '23503' && constraint === 'platform_client_school_id_fkey') return new ApiError(404, 'NOT_FOUND', 'Cette école n’existe pas.');
  // Offres, attributions et ajustements de modules (R01-T03) : les déclencheurs et contraintes restent la dernière barrière.
  if (code === '23505' && constraint === 'platform_offer_name') return new ApiError(409, 'OFFER_NAME_TAKEN', 'Une offre porte déjà ce nom.');
  if (code === '23514' && message.includes('platform_offer_modules_invalid')) return new ApiError(400, 'INVALID_REQUEST', 'Les modules de l’offre ne sont pas valides.');
  if (code === '23514' && message.includes('platform_offer_archived')) return new ApiError(409, 'OFFER_ARCHIVED', 'Cette offre est archivée.');
  if (code === '23514' && message.includes('platform_assignment_backdated')) return new ApiError(409, 'EFFECTIVE_DATE_PAST', 'La date d’effet doit être à venir.');
  if (code === '23514' && message.includes('platform_assignment_in_force')) return new ApiError(409, 'ASSIGNMENT_NOT_PENDING', 'Cette attribution a déjà pris effet.');
  if (code === '23514' && message.includes('platform_adjustment_assignment_ended')) return new ApiError(409, 'ADJUSTMENT_REQUIRES_OFFER', 'Cette école n’a pas d’offre en vigueur à ajuster.');
  if (code === '23505' && constraint === 'platform_adjustment_active') return new ApiError(409, 'ADJUSTMENT_ACTIVE', 'Un ajustement est déjà actif pour ce module.');
  if (code === '23503' && constraint === 'platform_module_adjustment_module_code_fkey') return new ApiError(404, 'MODULE_UNKNOWN', 'Ce module n’existe pas.');
  return undefined;
}

const journaledStatuses = new Set([409, 410, 412]);
/** Un refus métier se journalise ; une erreur de protocole (clé réutilisée avec un autre contenu) ou un accès refusé ne sont pas des actions. */
const unjournaled = new Set(['PLATFORM_OPERATOR_REQUIRED', 'IDEMPOTENCY_MISMATCH']);
const journalable = (error: unknown): error is ApiError => error instanceof ApiError && journaledStatuses.has(error.status) && !unjournaled.has(error.code);

/** Meilleur effort : ne masque jamais le refus d'origine et n'invente pas d'acteur si l'accès vient de lui être retiré. */
async function journalRefusal(pool: Pool, identity: Identity, spec: PlatformCommandSpec, refusal: ApiError) {
  try {
    await platformTransaction(pool, identity, async db => {
      const actor = await currentOperator(db, identity);
      if (!actor) return;
      const known = await db.query("SELECT 1 FROM drivy.platform_audit_event WHERE operation_id=$1 AND result='REFUSED' AND reason_code=$2 AND actor_operator_id=$3",
        [spec.operationId, refusal.code, actor.operatorId]);
      if (known.rowCount) return;
      await recordPlatformAction(db, actor, { action: spec.refusal?.action ?? spec.kind, schoolId: spec.refusal?.schoolId ?? null, subject: spec.refusal?.subject ?? null },
        { result: 'REFUSED', reasonCode: refusal.code, operationId: spec.operationId });
    });
  } catch { /* le journal des refus est un complément, jamais une cause d'échec */ }
}

async function runCommand<T>(pool: Pool, identity: Identity, spec: PlatformCommandSpec, hash: string,
  work: (db: PoolClient, actor: PlatformActor) => Promise<PlatformEffect<T>>, state: { actor?: PlatformActor }): Promise<PlatformCommandResult<T>> {
  return platformTransaction(pool, identity, async db => {
    const first = await currentOperator(db, identity);
    if (!first) throw operatorRequired();
    state.actor = first;
    await lockOperation(db, identity, spec.operationId);
    const known = await readReceipt(db, identity, spec.operationId);
    if (known) {
      if (known.kind !== spec.kind || known.request_hash !== hash) throw operationMismatch();
      return { data: known.response as T, status: known.status_code, replayed: true };
    }
    // Ordre des verrous : équipe, puis ligne de l'acteur, puis cible. Une révocation concurrente de l'acteur attend ou refuse cette commande.
    if (spec.teamWide) await lockTeam(db);
    const live = await db.query("SELECT id FROM drivy.platform_operator WHERE id=$1 AND status='ACTIVE' FOR SHARE", [first.operatorId]);
    if (!live.rowCount) throw operatorRequired();
    const effect = await work(db, first);
    const status = effect.status ?? 200;
    await writeReceipt(db, identity, spec.kind, spec.operationId, hash, status, effect.data);
    await recordPlatformAction(db, first, effect.journal, { operationId: spec.operationId });
    await effect.apply?.(db);
    return { data: effect.data, status, replayed: false };
  }, spec.context ?? {});
}

/** Exécute une commande de la plateforme : droits relus, idempotence durable, effet + reçu + journal dans un même commit. */
export async function platformCommand<T>(pool: Pool, identity: Identity, spec: PlatformCommandSpec,
  work: (db: PoolClient, actor: PlatformActor) => Promise<PlatformEffect<T>>): Promise<PlatformCommandResult<T>> {
  if (!/^[A-Z][A-Z0-9_]{2,63}$/.test(spec.kind)) throw new Error('Genre de commande invalide.');
  const hash = commandHash(spec.body, spec.expectedVersion);
  const state: { actor?: PlatformActor } = {};
  try { return await runCommand(pool, identity, spec, hash, work, state); }
  catch (error) {
    const refusal = databaseRefusal(error) ?? error;
    if (state.actor && journalable(refusal)) await journalRefusal(pool, identity, spec, refusal);
    throw refusal;
  }
}
