import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { Pool, type Client, type PoolClient } from 'pg';
import { buildApp } from '../src/app.js';
import { migrate } from './migrations.js';
import { seedFixtures, fixtureIds } from './fixtures.js';

/**
 * Restauration de sauvegarde de la messagerie sans réapparition des retraits (#68/#78/#97).
 *
 * Outillage d'exploitation, jamais chargé par le produit. Il fournit :
 *  - un export de journal indépendant (hors de la base restaurée) des retraits : purges média (séquence
 *    produit), suppressions de messages, révocations d'appareils, fins de lien et retraits du général ;
 *  - une validation complète des formes et contraintes réellement consommées ;
 *  - un rejeu transactionnel idempotent sur une connexion réservée, puis une vérification qu'aucun retrait
 *    n'est revenu ;
 *  - un scénario local complet (snapshot synthétique, mutations postérieures, restauration isolée, rejeu)
 *    exécutable avec PostgreSQL réel et `pg_dump`/`pg_restore`.
 *
 * Limite explicite et bloquante : une fin de lien dont la source d'éligibilité reste active (formation,
 * affectation, adhésion) est recréée par `messaging_sync_links` après le rejeu. La variante fermée
 * `ASSIGNMENT_ENDED` couvre une fin d'affectation réellement constatée ; les autres causes restent non couvertes et
 * le scénario refuse alors la réouverture (`MEMBER_LINK_REOPENED`). L'archivage durable de production (flux continu,
 * fsync, barrière, signature, rétention, résidence) reste à décider et à livrer (#68).
 */

export const ARCHIVE_FORMAT = 'drivy.messaging.restore-archive/2';
/** Connexion réservée : ni un `Pool`, ni une connexion ambigüe. */
export type ReservedConnection = Client | PoolClient;

export type ArchiveEntryKind = 'MEDIA_PURGED' | 'MESSAGE_DELETED' | 'DEVICE_REVOKED' | 'MEMBER_LINK_CUT' | 'GENERAL_REMOVAL' | 'ASSIGNMENT_ENDED';

export interface ArchiveScope {
  schoolIds: string[];
  conversationCount: number;
  messageCount: number;
  mediaCount: number;
  deviceCount: number;
  memberLinkCount: number;
  generalRemovalCount: number;
}
export interface MediaPurgedEntry { sequence: number; kind: 'MEDIA_PURGED'; schoolId: string; mediaId: string;
  messageId: string | null; reason: string; purgedAt: string; mediaPurgeSequence: number }
export interface MessageDeletedEntry { sequence: number; kind: 'MESSAGE_DELETED'; schoolId: string; conversationId: string;
  messageId: string; deletedAt: string; deletedByPersonId: string | null }
export interface DeviceRevokedEntry { sequence: number; kind: 'DEVICE_REVOKED'; schoolId: string; personId: string;
  deviceId: string; revokedAt: string }
export interface MemberLinkCutEntry { sequence: number; kind: 'MEMBER_LINK_CUT'; schoolId: string; conversationId: string;
  personId: string; linkNumber: number; cutSequence: number; cutAt: string }
export interface GeneralRemovalEntry { sequence: number; kind: 'GENERAL_REMOVAL'; schoolId: string; membershipId: string;
  personId: string; removedByPersonId: string; removedAt: string }
/** Variante fermée : fin d'affectation réellement constatée, avec ses identités liées et ses versions observées. */
export interface AssignmentEndedEntry { sequence: number; kind: 'ASSIGNMENT_ENDED'; schoolId: string; assignmentId: string;
  trainingId: string; instructorMembershipId: string; instructorPersonId: string; learnerPersonId: string;
  validFrom: string; validUntil: string; version: number; membershipVersion: number; membershipAccessEpoch: number }
export type ArchiveEntry = MediaPurgedEntry | MessageDeletedEntry | DeviceRevokedEntry | MemberLinkCutEntry | GeneralRemovalEntry | AssignmentEndedEntry;
/** Entrée sans sa position, pour construire le journal dans l'ordre. */
export type ArchivePayload = ArchiveEntry extends infer Entry ? (Entry extends ArchiveEntry ? Omit<Entry, 'sequence'> : never) : never;

export interface RestoreArchive {
  format: typeof ARCHIVE_FORMAT;
  createdAt: string;
  scope: ArchiveScope;
  source: { mediaPurgeThrough: number; mediaPurgeCount: number };
  archivedThrough: number;
  entries: ArchiveEntry[];
  digest: string;
}

export type ArchiveErrorCode = 'ARCHIVE_ABSENT' | 'ARCHIVE_UNREADABLE' | 'ARCHIVE_FORMAT' | 'ARCHIVE_TRUNCATED'
  | 'ARCHIVE_SEQUENCE_GAP' | 'ARCHIVE_DUPLICATE' | 'ARCHIVE_DIGEST_MISMATCH' | 'ARCHIVE_SCOPE_DIVERGENT'
  | 'ARCHIVE_SOURCE_INCONSISTENT';

export class ArchiveError extends Error {
  constructor(readonly code: ArchiveErrorCode, message: string) { super(message); this.name = 'ArchiveError'; }
}

/** Cible contradictoire ou plus récente : aucune écriture, la réouverture doit rester bloquée. */
export class RestoreStateError extends Error {
  constructor(readonly code: 'ASSIGNMENT_STATE_AMBIGUOUS') { super(code); this.name = 'RestoreStateError'; }
}

const entryKinds: readonly ArchiveEntryKind[] = ['MEDIA_PURGED', 'MESSAGE_DELETED', 'DEVICE_REVOKED', 'MEMBER_LINK_CUT', 'GENERAL_REMOVAL', 'ASSIGNMENT_ENDED'];
const purgeReasons = ['MESSAGE_DELETED', 'ORPHAN', 'CANCELLED'] as const;
const digestOf = (entries: readonly ArchiveEntry[]) => createHash('sha256').update(JSON.stringify(entries)).digest('hex');
const iso = (value: Date | string) => new Date(value).toISOString();
const emptyCounts = (): Record<ArchiveEntryKind, number> =>
  ({ MEDIA_PURGED: 0, MESSAGE_DELETED: 0, DEVICE_REVOKED: 0, MEMBER_LINK_CUT: 0, GENERAL_REMOVAL: 0, ASSIGNMENT_ENDED: 0 });

const isObject = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
const uuid = (value: unknown): value is string =>
  typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const uuidOrNull = (value: unknown): value is string | null => value === null || uuid(value);
const deviceId = (value: unknown): value is string => typeof value === 'string' && /^[A-Z0-9]{10,32}$/.test(value);
const stamp = (value: unknown): value is string => typeof value === 'string' && !Number.isNaN(new Date(value).getTime());
const integer = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value);
const integerAtLeast = (value: unknown, minimum: number): value is number => integer(value) && value >= minimum;

/**
 * Export cohérent : toutes les lectures se font dans le même instantané REPEATABLE READ, sur une connexion
 * réservée. Aucune clé, aucun octet, aucun contenu : identifiants, horodatages, raisons et séquences seulement.
 */
export async function exportArchive(db: ReservedConnection): Promise<RestoreArchive> {
  await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
  try {
    const archive = await readArchiveSnapshot(db);
    await db.query('COMMIT');
    return archive;
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  }
}

async function readArchiveSnapshot(db: ReservedConnection): Promise<RestoreArchive> {
  const schools = (await db.query<{ id: string }>('SELECT id FROM drivy.school ORDER BY id')).rows.map(row => row.id);
  const counts = (await db.query<{ conversations: number; messages: number; media: number; devices: number;
    links: number; removals: number }>(`SELECT
      (SELECT count(*)::int FROM drivy.messaging_conversation) AS conversations,
      (SELECT count(*)::int FROM drivy.messaging_message) AS messages,
      (SELECT count(*)::int FROM drivy.messaging_media) AS media,
      (SELECT count(*)::int FROM drivy.messaging_device) AS devices,
      (SELECT count(*)::int FROM drivy.messaging_member_link) AS links,
      (SELECT count(*)::int FROM drivy.messaging_general_removal) AS removals`)).rows[0]!;
  const purges = await db.query<{ sequence: string; schoolId: string; mediaId: string; messageId: string | null;
    reason: string; purgedAt: Date }>(`SELECT p.sequence,p.school_id AS "schoolId",p.media_id AS "mediaId",
      (SELECT m.message_id FROM drivy.messaging_media m WHERE m.school_id=p.school_id AND m.id=p.media_id) AS "messageId",
      p.reason,p.purged_at AS "purgedAt" FROM drivy.messaging_media_purge p ORDER BY p.sequence`);
  const messages = await db.query<{ schoolId: string; conversationId: string; messageId: string; deletedAt: Date;
    deletedByPersonId: string | null }>(`SELECT school_id AS "schoolId",conversation_id AS "conversationId",id AS "messageId",
      deleted_at AS "deletedAt",deleted_by_person_id AS "deletedByPersonId" FROM drivy.messaging_message
      WHERE deleted_at IS NOT NULL ORDER BY school_id,conversation_id,sequence`);
  const devices = await db.query<{ schoolId: string; personId: string; deviceId: string; revokedAt: Date }>(
    `SELECT school_id AS "schoolId",person_id AS "personId",device_id AS "deviceId",revoked_at AS "revokedAt"
     FROM drivy.messaging_device WHERE revoked_at IS NOT NULL ORDER BY school_id,person_id,device_id`);
  const links = await db.query<{ schoolId: string; conversationId: string; personId: string; linkNumber: number;
    cutSequence: string; cutAt: Date }>(`SELECT school_id AS "schoolId",conversation_id AS "conversationId",person_id AS "personId",
      link_number AS "linkNumber",cut_sequence AS "cutSequence",cut_at AS "cutAt" FROM drivy.messaging_member_link
      WHERE cut_sequence IS NOT NULL ORDER BY school_id,conversation_id,person_id,link_number`);
  const removals = await db.query<{ schoolId: string; membershipId: string; personId: string; removedByPersonId: string;
    removedAt: Date }>(`SELECT school_id AS "schoolId",membership_id AS "membershipId",person_id AS "personId",
      removed_by_person_id AS "removedByPersonId",removed_at AS "removedAt" FROM drivy.messaging_general_removal
      ORDER BY school_id,membership_id`);
  const assignments = await db.query<{ schoolId: string; assignmentId: string; trainingId: string; instructorMembershipId: string;
    instructorPersonId: string; learnerPersonId: string; validFrom: Date; validUntil: Date; version: number;
    membershipVersion: number; membershipAccessEpoch: number }>(`SELECT a.school_id AS "schoolId",a.id AS "assignmentId",a.training_id AS "trainingId",
      a.instructor_membership_id AS "instructorMembershipId",m.person_id AS "instructorPersonId",lp.person_id AS "learnerPersonId",
      a.valid_from AS "validFrom",a.valid_until AS "validUntil",a.version,m.version AS "membershipVersion",
      m.access_epoch AS "membershipAccessEpoch"
    FROM drivy.instructor_assignment a
    JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.instructor_membership_id
    JOIN drivy.training t ON t.school_id=a.school_id AND t.id=a.training_id
    JOIN drivy.learner_profile lp ON lp.school_id=t.school_id AND lp.id=t.learner_id
    WHERE a.valid_until IS NOT NULL ORDER BY a.school_id,a.id`);
  const payloads: ArchivePayload[] = [];
  for (const row of purges.rows) payloads.push({ kind: 'MEDIA_PURGED', schoolId: row.schoolId, mediaId: row.mediaId,
    messageId: row.messageId, reason: row.reason, purgedAt: iso(row.purgedAt), mediaPurgeSequence: Number(row.sequence) });
  for (const row of messages.rows) payloads.push({ kind: 'MESSAGE_DELETED', schoolId: row.schoolId, conversationId: row.conversationId,
    messageId: row.messageId, deletedAt: iso(row.deletedAt), deletedByPersonId: row.deletedByPersonId });
  for (const row of devices.rows) payloads.push({ kind: 'DEVICE_REVOKED', schoolId: row.schoolId, personId: row.personId,
    deviceId: row.deviceId, revokedAt: iso(row.revokedAt) });
  for (const row of links.rows) payloads.push({ kind: 'MEMBER_LINK_CUT', schoolId: row.schoolId, conversationId: row.conversationId,
    personId: row.personId, linkNumber: row.linkNumber, cutSequence: Number(row.cutSequence), cutAt: iso(row.cutAt) });
  for (const row of removals.rows) payloads.push({ kind: 'GENERAL_REMOVAL', schoolId: row.schoolId, membershipId: row.membershipId,
    personId: row.personId, removedByPersonId: row.removedByPersonId, removedAt: iso(row.removedAt) });
  for (const row of assignments.rows) payloads.push({ kind: 'ASSIGNMENT_ENDED', schoolId: row.schoolId,
    assignmentId: row.assignmentId, trainingId: row.trainingId, instructorMembershipId: row.instructorMembershipId,
    instructorPersonId: row.instructorPersonId, learnerPersonId: row.learnerPersonId, validFrom: iso(row.validFrom),
    validUntil: iso(row.validUntil), version: row.version, membershipVersion: row.membershipVersion,
    membershipAccessEpoch: row.membershipAccessEpoch });
  const entries = payloads.map((payload, index) => ({ ...payload, sequence: index + 1 }) as ArchiveEntry);
  return {
    format: ARCHIVE_FORMAT, createdAt: new Date().toISOString(),
    scope: { schoolIds: schools, conversationCount: counts.conversations, messageCount: counts.messages,
      mediaCount: counts.media, deviceCount: counts.devices, memberLinkCount: counts.links,
      generalRemovalCount: counts.removals },
    source: { mediaPurgeThrough: purges.rows.reduce((max, row) => Math.max(max, Number(row.sequence)), 0),
      mediaPurgeCount: purges.rows.length },
    archivedThrough: entries.length, entries, digest: digestOf(entries)
  };
}

const identityOf = (entry: ArchiveEntry): string => {
  switch (entry.kind) {
    case 'MEDIA_PURGED': return `MEDIA_PURGED|${entry.schoolId}|${entry.mediaId}`;
    case 'MESSAGE_DELETED': return `MESSAGE_DELETED|${entry.schoolId}|${entry.messageId}`;
    case 'DEVICE_REVOKED': return `DEVICE_REVOKED|${entry.schoolId}|${entry.personId}|${entry.deviceId}`;
    case 'MEMBER_LINK_CUT': return `MEMBER_LINK_CUT|${entry.schoolId}|${entry.conversationId}|${entry.personId}|${entry.linkNumber}`;
    case 'GENERAL_REMOVAL': return `GENERAL_REMOVAL|${entry.schoolId}|${entry.membershipId}`;
    case 'ASSIGNMENT_ENDED': return `ASSIGNMENT_ENDED|${entry.schoolId}|${entry.assignmentId}`;
  }
};

/**
 * Valide la forme, les contraintes et la cohérence interne de la source : tout ce qui sera consommé par le
 * rejeu. Aucune écriture. Le périmètre de la base cible est vérifié séparément par `validateArchive`.
 */
export function assertArchiveShape(raw: unknown): RestoreArchive {
  if (raw === undefined || raw === null || raw === '') throw new ArchiveError('ARCHIVE_ABSENT', 'Aucune source de rejeu fournie.');
  let candidate: unknown = raw;
  if (typeof raw === 'string') {
    try { candidate = JSON.parse(raw); } catch { throw new ArchiveError('ARCHIVE_UNREADABLE', 'Source de rejeu illisible.'); }
  }
  if (!isObject(candidate)) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Source de rejeu illisible.');
  if (candidate.format !== ARCHIVE_FORMAT) throw new ArchiveError('ARCHIVE_FORMAT', 'Format de source de rejeu inconnu.');
  if (!stamp(candidate.createdAt)) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Date de source de rejeu invalide.');
  const scope = candidate.scope;
  if (!isObject(scope) || !Array.isArray(scope.schoolIds) || scope.schoolIds.length === 0
    || !scope.schoolIds.every(uuid) || new Set(scope.schoolIds).size !== scope.schoolIds.length)
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Périmètre de la source de rejeu invalide.');
  for (const key of ['conversationCount', 'messageCount', 'mediaCount', 'deviceCount', 'memberLinkCount', 'generalRemovalCount'])
    if (!integerAtLeast((scope as Record<string, unknown>)[key], 0))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Compteurs de périmètre invalides.');
  if (!Array.isArray(candidate.entries)) throw new ArchiveError('ARCHIVE_TRUNCATED', 'Source de rejeu sans entrées.');
  if (!integer(candidate.archivedThrough) || candidate.archivedThrough !== candidate.entries.length)
    throw new ArchiveError('ARCHIVE_TRUNCATED', 'Source de rejeu tronquée.');
  const entries = candidate.entries as ArchiveEntry[];
  const seen = new Set<string>();
  for (const [index, entry] of entries.entries()) {
    if (!isObject(entry) || !entryKinds.includes(entry.kind as ArchiveEntryKind))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Entrée de rejeu invalide.');
    if (entry.sequence !== index + 1)
      throw new ArchiveError('ARCHIVE_SEQUENCE_GAP', 'Trou dans la séquence d’archive.');
    if (!uuid(entry.schoolId)) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Entrée de rejeu sans périmètre valide.');
    switch (entry.kind) {
      case 'MEDIA_PURGED':
        if (!uuid(entry.mediaId) || !uuidOrNull(entry.messageId) || !stamp(entry.purgedAt)
          || !(purgeReasons as readonly string[]).includes(entry.reason)
          || !integerAtLeast(entry.mediaPurgeSequence, 1))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Purge média invalide.');
        break;
      case 'MESSAGE_DELETED':
        if (!uuid(entry.conversationId) || !uuid(entry.messageId) || !stamp(entry.deletedAt) || !uuidOrNull(entry.deletedByPersonId))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Suppression de message invalide.');
        break;
      case 'DEVICE_REVOKED':
        if (!uuid(entry.personId) || !deviceId(entry.deviceId) || !stamp(entry.revokedAt))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Révocation d’appareil invalide.');
        break;
      case 'MEMBER_LINK_CUT':
        if (!uuid(entry.conversationId) || !uuid(entry.personId) || !integerAtLeast(entry.linkNumber, 1)
          || !integerAtLeast(entry.cutSequence, 0) || !stamp(entry.cutAt))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Fin de lien invalide.');
        break;
      case 'GENERAL_REMOVAL':
        if (!uuid(entry.membershipId) || !uuid(entry.personId) || !uuid(entry.removedByPersonId) || !stamp(entry.removedAt))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Retrait du général invalide.');
        break;
      case 'ASSIGNMENT_ENDED':
        if (!uuid(entry.assignmentId) || !uuid(entry.trainingId) || !uuid(entry.instructorMembershipId)
          || !uuid(entry.instructorPersonId) || !uuid(entry.learnerPersonId)
          || entry.instructorPersonId === entry.learnerPersonId
          || !stamp(entry.validFrom) || !stamp(entry.validUntil)
          || new Date(entry.validUntil).getTime() < new Date(entry.validFrom).getTime()
          || !integerAtLeast(entry.version, 1) || !integerAtLeast(entry.membershipVersion, 1)
          || !integerAtLeast(entry.membershipAccessEpoch, 1))
          throw new ArchiveError('ARCHIVE_UNREADABLE', 'Fin d’affectation invalide.');
        break;
    }
    const identity = identityOf(entry);
    if (seen.has(identity)) throw new ArchiveError('ARCHIVE_DUPLICATE', 'Entrée de rejeu en double.');
    seen.add(identity);
  }
  if (candidate.digest !== digestOf(entries)) throw new ArchiveError('ARCHIVE_DIGEST_MISMATCH', 'Empreinte de la source de rejeu invalide.');
  const source = candidate.source;
  if (!isObject(source) || !integerAtLeast(source.mediaPurgeThrough, 0) || !integerAtLeast(source.mediaPurgeCount, 0))
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Référence de séquence média absente.');
  const mediaPurgeThrough: number = source.mediaPurgeThrough;
  const mediaPurgeCount: number = source.mediaPurgeCount;
  const purges = entries.filter((entry): entry is MediaPurgedEntry => entry.kind === 'MEDIA_PURGED');
  // Les trous de séquence PostgreSQL sont légitimes (rollbacks) : seule la couverture exportée est vérifiée.
  if (purges.length !== mediaPurgeCount)
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Nombre de purges exportées incohérent.');
  if (mediaPurgeCount === 0 && mediaPurgeThrough !== 0)
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Borne média sans purge exportée.');
  if (mediaPurgeCount > 0 && (mediaPurgeThrough === 0
    || Math.max(...purges.map(entry => entry.mediaPurgeSequence)) !== mediaPurgeThrough
    || purges.some(entry => entry.mediaPurgeSequence > mediaPurgeThrough)))
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Cohérence des séquences média rompue.');
  return candidate as unknown as RestoreArchive;
}

/** Refuse toute source hors du périmètre de la base cible, après validation complète de la forme. */
export function validateArchive(raw: unknown, target: { schoolIds: readonly string[] }): RestoreArchive {
  const archive = assertArchiveShape(raw);
  const targetSchools = [...target.schoolIds].sort();
  const scopeSchools = [...archive.scope.schoolIds].sort();
  if (scopeSchools.length !== targetSchools.length || scopeSchools.some((id, index) => id !== targetSchools[index]))
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Périmètre de la source différent de la base cible.');
  const allowed = new Set(scopeSchools);
  if (archive.entries.some(entry => !allowed.has(entry.schoolId)))
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Entrée de rejeu hors du périmètre de la base cible.');
  return archive;
}

export async function collectScope(db: ReservedConnection): Promise<{ schoolIds: string[] }> {
  return { schoolIds: (await db.query<{ id: string }>('SELECT id FROM drivy.school ORDER BY id')).rows.map(row => row.id) };
}

export interface ReplayReport {
  applied: Record<ArchiveEntryKind, number>;
  alreadyApplied: Record<ArchiveEntryKind, number>;
  journalEntries: number;
}

/**
 * Rejeu transactionnel et idempotent des retraits. La source est revalidée **avant toute écriture**, puis le
 * rejeu s'exécute dans une seule transaction sur la connexion réservée fournie (jamais un Pool).
 */
export async function replayArchive(db: ReservedConnection, archive: RestoreArchive): Promise<ReplayReport> {
  const checked = assertArchiveShape(archive);
  const report: ReplayReport = { applied: emptyCounts(), alreadyApplied: emptyCounts(), journalEntries: 0 };
  await db.query('BEGIN');
  try {
    for (const entry of checked.entries) {
      let changed = 0;
      if (entry.kind === 'MEDIA_PURGED') {
        const media = await db.query(`UPDATE drivy.messaging_media SET ciphertext=NULL,
          purged_at=COALESCE(purged_at,$3::timestamptz),purge_reason=COALESCE(purge_reason,$4)
          WHERE school_id=$1 AND id=$2 AND (ciphertext IS NOT NULL OR purged_at IS NULL OR purge_reason IS NULL)`,
          [entry.schoolId, entry.mediaId, entry.purgedAt, entry.reason]);
        const journal = await db.query(`INSERT INTO drivy.messaging_media_purge(school_id,media_id,purged_at,reason)
          VALUES($1,$2,$3::timestamptz,$4) ON CONFLICT(school_id,media_id) DO NOTHING`,
          [entry.schoolId, entry.mediaId, entry.purgedAt, entry.reason]);
        changed = (media.rowCount ?? 0) + (journal.rowCount ?? 0);
        report.journalEntries += journal.rowCount ?? 0;
      } else if (entry.kind === 'MESSAGE_DELETED') {
        const message = await db.query(`UPDATE drivy.messaging_message SET envelope=NULL,
          deleted_at=COALESCE(deleted_at,$3::timestamptz),deleted_by_person_id=COALESCE(deleted_by_person_id,$4::uuid),
          pinned_at=NULL,pinned_by_person_id=NULL
          WHERE school_id=$1 AND id=$2 AND (deleted_at IS NULL OR envelope IS NOT NULL OR pinned_at IS NOT NULL)`,
          [entry.schoolId, entry.messageId, entry.deletedAt, entry.deletedByPersonId]);
        const reactions = await db.query('DELETE FROM drivy.messaging_reaction WHERE school_id=$1 AND message_id=$2',
          [entry.schoolId, entry.messageId]);
        await db.query('DELETE FROM drivy.messaging_poll_vote WHERE school_id=$1 AND message_id=$2', [entry.schoolId, entry.messageId]);
        const polls = await db.query('DELETE FROM drivy.messaging_poll WHERE school_id=$1 AND message_id=$2',
          [entry.schoolId, entry.messageId]);
        changed = (message.rowCount ?? 0) + (reactions.rowCount ?? 0) + (polls.rowCount ?? 0);
      } else if (entry.kind === 'DEVICE_REVOKED') {
        const device = await db.query(`UPDATE drivy.messaging_device SET revoked_at=COALESCE(revoked_at,$4::timestamptz),
          device_keys=NULL WHERE school_id=$1 AND person_id=$2 AND device_id=$3 AND (revoked_at IS NULL OR device_keys IS NOT NULL)`,
          [entry.schoolId, entry.personId, entry.deviceId, entry.revokedAt]);
        const oneTime = await db.query('DELETE FROM drivy.messaging_one_time_key WHERE school_id=$1 AND person_id=$2 AND device_id=$3',
          [entry.schoolId, entry.personId, entry.deviceId]);
        const fallback = await db.query('DELETE FROM drivy.messaging_fallback_key WHERE school_id=$1 AND person_id=$2 AND device_id=$3',
          [entry.schoolId, entry.personId, entry.deviceId]);
        const queue = await db.query(`DELETE FROM drivy.messaging_to_device WHERE school_id=$1 AND recipient_person_id=$2
          AND recipient_device_id=$3`, [entry.schoolId, entry.personId, entry.deviceId]);
        const tracking = await db.query('DELETE FROM drivy.messaging_device_tracking WHERE school_id=$1 AND person_id=$2 AND device_id=$3',
          [entry.schoolId, entry.personId, entry.deviceId]);
        changed = (device.rowCount ?? 0) + (oneTime.rowCount ?? 0) + (fallback.rowCount ?? 0) + (queue.rowCount ?? 0)
          + (tracking.rowCount ?? 0);
      } else if (entry.kind === 'MEMBER_LINK_CUT') {
        const link = await db.query(`UPDATE drivy.messaging_member_link SET cut_sequence=$5,cut_at=COALESCE(cut_at,$6::timestamptz)
          WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 AND link_number=$4 AND cut_sequence IS NULL`,
          [entry.schoolId, entry.conversationId, entry.personId, entry.linkNumber, entry.cutSequence, entry.cutAt]);
        changed = link.rowCount ?? 0;
      } else if (entry.kind === 'ASSIGNMENT_ENDED') {
        // Fin d'affectation réellement constatée à la source : le fait est rejoué avant toute synchronisation.
        const current = await db.query<{ validFrom: Date; validUntil: Date | null; version: number }>(
          `SELECT valid_from AS "validFrom",valid_until AS "validUntil",version FROM drivy.instructor_assignment
           WHERE school_id=$1 AND id=$2 FOR UPDATE`, [entry.schoolId, entry.assignmentId]);
        const row = current.rows[0];
        if (row) {
          const validFrom = iso(row.validFrom);
          const validUntil = row.validUntil ? iso(row.validUntil) : null;
          // Cible contradictoire ou plus récente : aucune écriture, la décision revient à l'exploitant.
          if (validFrom !== entry.validFrom || row.version > entry.version
            || (validUntil !== null && new Date(validUntil).getTime() > new Date(entry.validUntil).getTime()))
            throw new RestoreStateError('ASSIGNMENT_STATE_AMBIGUOUS');
          const assignment = await db.query(`UPDATE drivy.instructor_assignment
            SET valid_until=CASE WHEN valid_until IS NULL OR valid_until>$3::timestamptz THEN $3::timestamptz ELSE valid_until END,
                version=GREATEST(version,$4)
            WHERE school_id=$1 AND id=$2 AND ((valid_until IS NULL OR valid_until>$3::timestamptz) OR version<$4)`,
            [entry.schoolId, entry.assignmentId, entry.validUntil, entry.version]);
          // END_ASSIGNMENT incrémente aussi version/access_epoch de l'adhésion du moniteur : on rejoue les valeurs
          // observées de façon monotone, jamais un incrément aveugle, sans toucher rôles/grants/statut.
          const membership = await db.query(`UPDATE drivy.membership SET version=GREATEST(version,$3),access_epoch=GREATEST(access_epoch,$4)
            WHERE school_id=$1 AND id=$2 AND (version<$3 OR access_epoch<$4)`,
            [entry.schoolId, entry.instructorMembershipId, entry.membershipVersion, entry.membershipAccessEpoch]);
          changed = (assignment.rowCount ?? 0) + (membership.rowCount ?? 0);
        }
      } else {
        // Un retrait dont l'adhésion n'existe pas dans la cible est une absence légitime (créée après le dump).
        const removal = await db.query(`INSERT INTO drivy.messaging_general_removal(school_id,membership_id,person_id,
          removed_by_person_id,removed_at)
          SELECT $1,$2,$3,$4,$5::timestamptz
          WHERE EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=$1 AND m.id=$2)
          ON CONFLICT(school_id,membership_id) DO NOTHING`,
          [entry.schoolId, entry.membershipId, entry.personId, entry.removedByPersonId, entry.removedAt]);
        changed = removal.rowCount ?? 0;
      }
      if (changed > 0) report.applied[entry.kind] += 1; else report.alreadyApplied[entry.kind] += 1;
    }
    await db.query('COMMIT');
    return report;
  } catch (error) {
    await db.query('ROLLBACK');
    throw error;
  }
}

export interface VerificationReport {
  ok: boolean;
  checked: Record<ArchiveEntryKind, number>;
  violations: Record<ArchiveEntryKind, number>;
  problems: string[];
}

/**
 * Vérifie, après rejeu, qu'aucun retrait n'est revenu : ni octet purgé, ni message, ni appareil, ni droit.
 * Une fin de lien est vérifiée sur **tout** lien ouvert de la personne, pas seulement sur l'ancien numéro :
 * une resynchronisation peut en recréer un. Une absence légitime (objet créé après le dump) n'est pas une
 * violation ; un droit encore ouvert pour une personne retirée en est une.
 */
export async function verifyRestoredState(db: ReservedConnection, archive: RestoreArchive): Promise<VerificationReport> {
  const report: VerificationReport = { ok: true, checked: emptyCounts(), violations: emptyCounts(), problems: [] };
  const of = <K extends ArchiveEntryKind>(kind: K) => archive.entries.filter(entry => entry.kind === kind) as
    Extract<ArchiveEntry, { kind: K }>[];
  const media = of('MEDIA_PURGED');
  report.checked.MEDIA_PURGED = media.length;
  if (media.length > 0) {
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_media
      WHERE id = ANY($1::uuid[]) AND (ciphertext IS NOT NULL OR purged_at IS NULL OR purge_reason IS NULL)`,
      [media.map(entry => entry.mediaId)])).rows[0]!;
    report.violations.MEDIA_PURGED = row.count;
  }
  const messages = of('MESSAGE_DELETED');
  report.checked.MESSAGE_DELETED = messages.length;
  if (messages.length > 0) {
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_message
      WHERE id = ANY($1::uuid[]) AND (deleted_at IS NULL OR envelope IS NOT NULL)`,
      [messages.map(entry => entry.messageId)])).rows[0]!;
    report.violations.MESSAGE_DELETED = row.count;
  }
  const devices = of('DEVICE_REVOKED');
  report.checked.DEVICE_REVOKED = devices.length;
  if (devices.length > 0) {
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_device d
      WHERE (d.school_id,d.person_id,d.device_id) IN (SELECT * FROM unnest($1::uuid[],$2::uuid[],$3::text[]))
        AND (d.revoked_at IS NULL OR d.device_keys IS NOT NULL)`,
      [devices.map(entry => entry.schoolId), devices.map(entry => entry.personId), devices.map(entry => entry.deviceId)])).rows[0]!;
    report.violations.DEVICE_REVOKED = row.count;
  }
  const links = of('MEMBER_LINK_CUT');
  report.checked.MEMBER_LINK_CUT = links.length;
  if (links.length > 0) {
    // Tout lien ouvert pour une personne dont un lien a été coupé est une réactivation, quel que soit son numéro.
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_member_link l
      WHERE (l.school_id,l.conversation_id,l.person_id) IN
        (SELECT * FROM unnest($1::uuid[],$2::uuid[],$3::uuid[])) AND l.cut_sequence IS NULL`,
      [links.map(entry => entry.schoolId), links.map(entry => entry.conversationId), links.map(entry => entry.personId)])).rows[0]!;
    report.violations.MEMBER_LINK_CUT = row.count;
  }
  const removals = of('GENERAL_REMOVAL');
  report.checked.GENERAL_REMOVAL = removals.length;
  if (removals.length > 0) {
    // Une adhésion absente de la cible est une absence légitime : seul un participant restauré sans retrait compte.
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM unnest($1::uuid[],$2::uuid[]) AS expected(school_id,membership_id)
      WHERE EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=expected.school_id AND m.id=expected.membership_id)
        AND NOT EXISTS(SELECT 1 FROM drivy.messaging_general_removal r
          WHERE r.school_id=expected.school_id AND r.membership_id=expected.membership_id)`,
      [removals.map(entry => entry.schoolId), removals.map(entry => entry.membershipId)])).rows[0]!;
    report.violations.GENERAL_REMOVAL = row.count;
  }
  const assignments = of('ASSIGNMENT_ENDED');
  report.checked.ASSIGNMENT_ENDED = assignments.length;
  if (assignments.length > 0) {
    // Fin appliquée dans la cible (affectation absente = absence légitime, aucune création de droit).
    const ends = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM
      unnest($1::uuid[],$2::uuid[],$3::timestamptz[],$4::int[]) AS expected(school_id,assignment_id,valid_until,version)
      JOIN drivy.instructor_assignment a ON a.school_id=expected.school_id AND a.id=expected.assignment_id
      WHERE a.valid_until IS NULL OR a.valid_until>expected.valid_until OR a.version<expected.version`,
      [assignments.map(entry => entry.schoolId), assignments.map(entry => entry.assignmentId),
        assignments.map(entry => entry.validUntil), assignments.map(entry => entry.version)])).rows[0]!;
    // Aucune éligibilité résiduelle pour la paire concernée : une réattribution légitime serait une ambiguïté, pas un vert.
    const eligible = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM
      unnest($1::uuid[],$2::uuid[],$3::uuid[]) AS expected(school_id,learner_person_id,instructor_person_id)
      WHERE drivy.messaging_pair_eligible(expected.school_id,expected.learner_person_id,expected.instructor_person_id)`,
      [assignments.map(entry => entry.schoolId), assignments.map(entry => entry.learnerPersonId),
        assignments.map(entry => entry.instructorPersonId)])).rows[0]!;
    report.violations.ASSIGNMENT_ENDED = ends.count + eligible.count;
  }
  for (const kind of entryKinds) {
    if (report.violations[kind] > 0) report.problems.push(`${kind}:${report.violations[kind]}`);
  }
  report.ok = report.problems.length === 0;
  return report;
}

/** Écrit la source de rejeu hors de la base restaurée (fichier local, jamais dans le dump). */
export async function writeArchiveFile(file: string, archive: RestoreArchive): Promise<void> {
  await writeFile(file, JSON.stringify(archive, null, 2) + '\n', { mode: 0o600 });
}

/** Lit la source de rejeu ; un fichier absent n'est jamais remplacé par une source vide. */
export async function readArchiveFile(file: string): Promise<unknown> {
  try { return await readFile(file, 'utf8'); } catch (error) {
    if (typeof error === 'object' && error !== null && 'code' in error && (error as { code?: string }).code === 'ENOENT') return undefined;
    throw error;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Ressources de scénario : noms uniques, refus de collision, propriété des bases créées.
// ---------------------------------------------------------------------------------------------------------------

export interface DatabasePlan { source: string; target: string; sentinel: string }
export class DatabaseCollisionError extends Error {
  constructor(readonly database: string) { super('DATABASE_COLLISION'); this.name = 'DatabaseCollisionError'; }
}

/**
 * Noms propres à la tentative. Refuse toute collision **avant** toute mutation : une base préexistante, même
 * synthétique et même préfixée, n'est jamais réutilisée ni supprimée.
 */
export function planDatabaseNames(existing: readonly string[], suffix: string): DatabasePlan {
  if (!/^[a-z0-9]{8,16}$/.test(suffix)) throw new Error('DATABASE_SUFFIX_INVALID');
  const plan: DatabasePlan = { source: `drivy_restore_src_${suffix}`, target: `drivy_restore_target_${suffix}`,
    sentinel: `drivy_restore_sentinel_${suffix}` };
  const collision = [plan.source, plan.target, plan.sentinel].find(name => existing.includes(name));
  if (collision) throw new DatabaseCollisionError(collision);
  return plan;
}

// ---------------------------------------------------------------------------------------------------------------
// Scénario local exécutable : snapshot synthétique, mutations postérieures, restauration isolée, rejeu.
// ---------------------------------------------------------------------------------------------------------------

const scenario = {
  school: '1b000000-0000-4000-8000-000000000068',
  otherSchool: '1b000000-0000-4000-8000-000000000069',
  instructor: '2b000000-0000-4000-8000-000000000068',
  learner: '2b000000-0000-4000-8000-000000000069',
  instructorMember: '3b000000-0000-4000-8000-000000000068',
  adminMember: '3b000000-0000-4000-8000-00000000006a',
  learnerMember: '3b000000-0000-4000-8000-000000000069',
  conversation: '9b000000-0000-4000-8000-000000000068',
  learnerProfile: '4b000000-0000-4000-8000-000000000068',
  offering: '5b000000-0000-4000-8000-000000000068',
  training: '6b000000-0000-4000-8000-000000000068',
  assignment: '7a000000-0000-4000-8000-000000000068',
  messageDeleted: '8b000000-0000-4000-8000-000000000068',
  messageKept: '8b000000-0000-4000-8000-000000000069',
  mediaDeleted: '7b000000-0000-4000-8000-000000000068',
  mediaKept: '7b000000-0000-4000-8000-000000000069',
  mediaOrphan: '7b000000-0000-4000-8000-000000000070',
  deviceInstructor: 'RESTOREA001',
  deviceLearner: 'RESTOREB001'
} as const;

const fixtureAdmin = fixtureIds.admin;
const cipher = (seed: number) => Buffer.from(Array.from({ length: 64 }, (_value, index) => (index * 31 + seed) % 256));

async function prepareSyntheticSource(pool: Pool, issuer: string): Promise<void> {
  const admin = await pool.connect();
  try {
    await admin.query('DROP SCHEMA IF EXISTS drivy CASCADE');
    await admin.query('DROP TABLE IF EXISTS public.drivy_migrations');
    for (const role of ['drivy_app', 'drivy_invitation_mailer', 'drivy_course_worker'])
      await admin.query(`DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${role}') THEN
        CREATE ROLE ${role} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$`);
  } finally { admin.release(); }
  await migrate(pool);
  await seedFixtures(pool, issuer);
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    for (const [personId, name] of [[scenario.instructor, 'Moniteur Restauration · Synthétique'],
      [scenario.learner, 'Élève Restauration · Synthétique']])
      await db.query('INSERT INTO drivy.person(id,display_name) VALUES($1,$2) ON CONFLICT DO NOTHING', [personId, name]);
    for (const [schoolId, name] of [[scenario.school, 'Auto-école Restauration · Synthétique'],
      [scenario.otherSchool, 'Auto-école Témoin · Synthétique']])
      await db.query("INSERT INTO drivy.school(id,name,status,contact_email) VALUES($1,$2,'ACTIVE','restore@example.invalid') ON CONFLICT DO NOTHING",
        [schoolId, name]);
    for (const [memberId, personId, roles] of [[scenario.instructorMember, scenario.instructor, ['INSTRUCTOR']],
      [scenario.learnerMember, scenario.learner, ['LEARNER']],
      [scenario.adminMember, fixtureAdmin, ['ADMIN']]])
      await db.query('INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING',
        [memberId, scenario.school, personId, roles]);
    // Relations minimales qui rendent la conversation privée éligible (formation + affectation), comme la fondation.
    await db.query("INSERT INTO drivy.learner_profile(id,school_id,person_id,created_at) VALUES($1,$2,$3,'2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING",
      [scenario.learnerProfile, scenario.school, scenario.learner]);
    await db.query(`INSERT INTO drivy.offering_version(id,school_id,offering_key,category_code,version)
      VALUES($1,$2,'category-b','B',1) ON CONFLICT DO NOTHING`, [scenario.offering, scenario.school]);
    await db.query(`INSERT INTO drivy.training(id,school_id,learner_id,offering_id,offering_key,status,started_on,created_at)
      VALUES($1,$2,$3,$4,'category-b','ACTIVE','2026-01-01','2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING`,
      [scenario.training, scenario.school, scenario.learnerProfile, scenario.offering]);
    await db.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from)
      VALUES($1,$2,$3,$4,'2026-01-01T00:00:00Z') ON CONFLICT DO NOTHING`,
      [scenario.assignment, scenario.school, scenario.training, scenario.instructorMember]);
    const [low, high] = scenario.instructor < scenario.learner
      ? [scenario.instructor, scenario.learner] : [scenario.learner, scenario.instructor];
    await db.query(`INSERT INTO drivy.messaging_conversation(id,school_id,kind,person_low,person_high,last_sequence)
      VALUES($1,$2,'PRIVATE',$3,$4,2) ON CONFLICT DO NOTHING`, [scenario.conversation, scenario.school, low, high]);
    for (const personId of [scenario.instructor, scenario.learner])
      await db.query(`INSERT INTO drivy.messaging_member_link(school_id,conversation_id,person_id,link_number,readable_after)
        VALUES($1,$2,$3,1,0) ON CONFLICT DO NOTHING`, [scenario.school, scenario.conversation, personId]);
    const envelope = JSON.stringify({ scheme: 'synthetic', keyId: 'restore', payload: 'AA==' });
    for (const [messageId, sequence] of [[scenario.messageDeleted, 1], [scenario.messageKept, 2]] as const)
      await db.query(`INSERT INTO drivy.messaging_message(id,school_id,conversation_id,sequence,intent_id,sender_person_id,
        envelope,fingerprint) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8) ON CONFLICT DO NOTHING`,
        [messageId, scenario.school, scenario.conversation, sequence, randomUUID(), scenario.instructor, envelope,
          createHash('sha256').update(`restore-${sequence}`).digest('hex')]);
    for (const [mediaId, messageId, seed] of [[scenario.mediaDeleted, scenario.messageDeleted, 11],
      [scenario.mediaKept, scenario.messageKept, 12], [scenario.mediaOrphan, null, 13]] as const) {
      const bytes = cipher(seed);
      await db.query(`INSERT INTO drivy.messaging_media(id,school_id,conversation_id,uploader_person_id,byte_size,
        ciphertext_sha256,ciphertext,message_id,attached_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT DO NOTHING`,
        [mediaId, scenario.school, scenario.conversation, scenario.instructor, bytes.length,
          createHash('sha256').update(bytes).digest('hex'), bytes, messageId, messageId ? new Date() : null]);
    }
    for (const [personId, deviceId] of [[scenario.instructor, scenario.deviceInstructor],
      [scenario.learner, scenario.deviceLearner]] as const)
      await db.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject,device_keys)
        VALUES($1,$2,$3,$4,'restore','{"synthetic":"key"}') ON CONFLICT DO NOTHING`,
        [scenario.school, personId, deviceId, issuer]);
    await db.query('COMMIT');
  } catch (error) { await db.query('ROLLBACK'); throw error; } finally { db.release(); }
}

async function applyPostSnapshotMutations(pool: Pool, app: ReturnType<typeof buildApp>): Promise<void> {
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    await db.query('SET LOCAL ROLE drivy_app');
    await db.query("SELECT set_config('app.issuer',$1,true),set_config('app.subject',$2,true),set_config('app.school_id',$3,true),set_config('app.person_id',$4,true)",
      ['https://restore.example.invalid', 'restore-instructor', scenario.school, scenario.instructor]);
    await db.query('SELECT drivy.messaging_delete_for_everyone($1,$2,$3)',
      [scenario.school, scenario.conversation, scenario.messageDeleted]);
    await db.query('SELECT drivy.messaging_purge_media($1,$2,$3)', [scenario.school, scenario.mediaOrphan, 'CANCELLED']);
    await db.query('COMMIT');
  } catch (error) { await db.query('ROLLBACK'); throw error; } finally { db.release(); }
  await pool.query(`UPDATE drivy.messaging_device SET revoked_at=now(),device_keys=NULL
    WHERE school_id=$1 AND person_id=$2 AND device_id=$3`, [scenario.school, scenario.learner, scenario.deviceLearner]);
  // La fin d'affectation est acquise par le mécanisme métier existant (route END_ASSIGNMENT), pas déduite d'une coupe.
  const version = (await pool.query<{ version: number }>('SELECT version FROM drivy.instructor_assignment WHERE school_id=$1 AND id=$2',
    [scenario.school, scenario.assignment])).rows[0]!.version;
  const endOperation = randomUUID();
  const ended = await app.inject({ method: 'POST',
    url: `/v1/schools/${scenario.school}/trainings/${scenario.training}/assignments/${scenario.assignment}/end`,
    headers: { authorization: 'Bearer demo-admin', 'idempotency-key': endOperation, 'if-match': `"${version}"`, 'content-type': 'application/json' },
    payload: JSON.stringify({ operationId: endOperation }) });
  if (ended.statusCode !== 200) throw new Error(`END_ASSIGNMENT_${ended.statusCode}_${(ended.json() as { code?: string }).code ?? 'UNKNOWN'}`);
  // La synchronisation réelle du produit coupe ensuite le lien devenu inéligible.
  const sync = await pool.connect();
  try {
    await sync.query('BEGIN');
    await sync.query('SET LOCAL ROLE drivy_app');
    await sync.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [scenario.school, scenario.instructor]);
    await sync.query('SELECT drivy.messaging_sync_links($1,$2)', [scenario.school, scenario.conversation]);
    await sync.query('COMMIT');
  } catch (error) { await sync.query('ROLLBACK'); throw error; } finally { sync.release(); }
}

const withDatabase = (url: string, database: string) => {
  const copy = new URL(url); copy.pathname = `/${database}`; return copy.toString();
};

const dockerExec = (container: string, args: string[], input?: Buffer) =>
  execFileSync('docker', ['exec', ...(input ? ['-i'] : []), container, ...args],
    { input, maxBuffer: 512 * 1024 * 1024 });

async function clusterIdentifier(connection: Pool | Client): Promise<string> {
  const row = (await connection.query<{ id: string }>('SELECT system_identifier::text AS id FROM pg_control_system()')).rows[0];
  if (!row) throw new Error('CLUSTER_IDENTITY_UNAVAILABLE');
  return row.id;
}

async function scenarioMain(): Promise<number> {
  const sourceUrl = process.env.RESTORE_SOURCE_URL;
  const container = process.env.RESTORE_DOCKER;
  const issuer = process.env.RESTORE_ISSUER ?? 'https://restore.example.invalid';
  if (!sourceUrl || !container) {
    console.error('Refus : RESTORE_SOURCE_URL et RESTORE_DOCKER sont obligatoires ; aucune base implicite.');
    return 2;
  }
  const parsed = new URL(sourceUrl);
  if (!['127.0.0.1', 'localhost', '[::1]', '::1'].includes(parsed.hostname)) {
    console.error('Refus : cible locale uniquement (boucle locale).');
    return 2;
  }
  const user = decodeURIComponent(parsed.username);
  const suffix = randomUUID().replace(/-/g, '').slice(0, 10);
  const maintenance = new Pool({ connectionString: withDatabase(sourceUrl, 'postgres'), max: 1 });
  const summary: Record<string, unknown> = { steps: [] as string[], refusals: {} as Record<string, string> };
  const steps = summary.steps as string[];
  const refusals = summary.refusals as Record<string, string>;
  const created: string[] = [];
  let pool: Pool | undefined;
  const workdir = await mkdtemp(join(tmpdir(), 'drivy-restore-'));
  const createDatabase = async (name: string) => { await maintenance.query(`CREATE DATABASE ${name}`); created.push(name); };
  try {
    const existing = (await maintenance.query<{ datname: string }>('SELECT datname FROM pg_database')).rows.map(row => row.datname);
    let plan: DatabasePlan;
    try { plan = planDatabaseNames(existing, suffix); } catch (error) {
      if (error instanceof DatabaseCollisionError) { summary.error = 'DATABASE_COLLISION'; return 2; }
      throw error;
    }
    // Même cluster : la connexion SQL et le conteneur de pg_dump/pg_restore doivent désigner le même serveur.
    const sqlCluster = await clusterIdentifier(maintenance);
    const containerCluster = dockerExec(container, ['psql', '-U', user, '-d', 'postgres', '-tAc', 'SELECT system_identifier::text FROM pg_control_system()'])
      .toString().trim();
    if (sqlCluster !== containerCluster) { summary.error = 'CLUSTER_MISMATCH'; return 2; }
    summary.clusterChecked = true;
    await createDatabase(plan.sentinel);
    await createDatabase(plan.source);
    steps.push('databases-created');
    pool = new Pool({ connectionString: withDatabase(sourceUrl, plan.source), max: 4 });
    await prepareSyntheticSource(pool, issuer);
    steps.push('source-prepared');
    const dump = dockerExec(container, ['pg_dump', '-U', user, '--no-owner', '-Fc', '-d', plan.source]);
    summary.dumpBytes = dump.length;
    summary.dumpDigestPrefix = createHash('sha256').update(dump).digest('hex').slice(0, 12);
    steps.push('snapshot-taken');
    const adminApp = buildApp({ pool, cursorSecret: 'restore-replay-scenario-secret-32ch!',
      verifyToken: async authorization => {
        if (!authorization?.startsWith('Bearer demo-')) throw new Error('AUTHENTICATION_REQUIRED');
        return { issuer, subject: authorization.slice(7) };
      } });
    summary.appReady = true;
    await applyPostSnapshotMutations(pool, adminApp);
    await adminApp.close();
    const exporter = await pool.connect();
    let archive: RestoreArchive;
    try { archive = await exportArchive(exporter); } finally { exporter.release(); }
    const archiveFile = join(workdir, 'archive.json');
    await writeArchiveFile(archiveFile, archive);
    steps.push('archive-exported');
    await createDatabase(plan.target);
    dockerExec(container, ['pg_restore', '-U', user, '--no-owner', '-d', plan.target], dump);
    steps.push('snapshot-restored');
    const restored = new Pool({ connectionString: withDatabase(sourceUrl, plan.target), max: 2 });
    const restoredDb = await restored.connect();
    try {
      summary.restoredBeforeReplay = (await restoredDb.query<{ resurrectedMedia: number; resurrectedMessages: number;
        activeDevices: number; openLinks: number }>(`SELECT
          (SELECT count(*)::int FROM drivy.messaging_media WHERE id = ANY($1::uuid[]) AND ciphertext IS NOT NULL) AS "resurrectedMedia",
          (SELECT count(*)::int FROM drivy.messaging_message WHERE id = ANY($2::uuid[]) AND deleted_at IS NULL) AS "resurrectedMessages",
          (SELECT count(*)::int FROM drivy.messaging_device WHERE revoked_at IS NULL AND device_id = ANY($3::text[])) AS "activeDevices",
          (SELECT count(*)::int FROM drivy.messaging_member_link WHERE cut_sequence IS NULL AND person_id = $4) AS "openLinks"`,
          [[scenario.mediaDeleted, scenario.mediaOrphan], [scenario.messageDeleted], [scenario.deviceLearner], scenario.learner])).rows[0]!;
      const scope = await collectScope(restoredDb);
      const validate = (raw: unknown) => {
        try { validateArchive(raw, scope); return 'ACCEPTED'; } catch (error) {
          return error instanceof ArchiveError ? error.code : 'UNKNOWN';
        }
      };
      refusals.absent = validate(undefined);
      refusals.truncated = validate({ ...archive, entries: archive.entries.slice(0, -1) });
      const gapped = archive.entries.filter((_entry, index) => index !== 1);
      refusals.sequenceGap = validate({ ...archive, entries: gapped, archivedThrough: gapped.length, digest: digestOf(gapped) });
      refusals.divergentScope = validate({ ...archive, scope: { ...archive.scope, schoolIds: [...archive.scope.schoolIds, randomUUID()] } });
      refusals.inconsistentSource = validate({ ...archive, source: { mediaPurgeThrough: 0, mediaPurgeCount: archive.source.mediaPurgeCount } });
      refusals.incompleteLinkCut = validate({ ...archive, entries: archive.entries.map(entry => entry.kind === 'MEMBER_LINK_CUT'
        ? { ...entry, conversationId: undefined } : entry), digest: digestOf(archive.entries.map(entry => entry.kind === 'MEMBER_LINK_CUT'
        ? { ...entry, conversationId: undefined } : entry) as ArchiveEntry[]) });
      steps.push('archive-validated');
      // La source relue est validée contre la cible, puis le rejeu consomme cet objet validé.
      const restoredSource = validateArchive(await readArchiveFile(archiveFile), scope);
      summary.archiveAccepted = 'ACCEPTED';
      const replay = await replayArchive(restoredDb, restoredSource);
      const verification = await verifyRestoredState(restoredDb, restoredSource);
      summary.replay = replay;
      summary.verification = verification;
      // Synchronisation réelle répétée : la fin d'affectation rejouée doit empêcher toute recréation de lien.
      const syncLinks = async () => {
        const sync = await restored.connect();
        try {
          await sync.query('BEGIN');
          await sync.query('SET LOCAL ROLE drivy_app');
          await sync.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)",
            [scenario.school, scenario.instructor]);
          await sync.query('SELECT drivy.messaging_sync_links($1,$2)', [scenario.school, scenario.conversation]);
          await sync.query('COMMIT');
        } catch (error) { await sync.query('ROLLBACK'); throw error; } finally { sync.release(); }
      };
      await syncLinks();
      await syncLinks();
      const afterSync = await verifyRestoredState(restoredDb, restoredSource);
      summary.afterSync = afterSync;
      const stateBefore = (await restoredDb.query<{ assignmentVersion: number; validUntil: Date | null;
        membershipVersion: number; accessEpoch: number }>(`SELECT a.version AS "assignmentVersion",a.valid_until AS "validUntil",
          m.version AS "membershipVersion",m.access_epoch AS "accessEpoch"
          FROM drivy.instructor_assignment a JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.instructor_membership_id
          WHERE a.school_id=$1 AND a.id=$2`, [scenario.school, scenario.assignment])).rows[0]!;
      const secondReplay = await replayArchive(restoredDb, restoredSource);
      const stateAfter = (await restoredDb.query<{ assignmentVersion: number; validUntil: Date | null;
        membershipVersion: number; accessEpoch: number }>(`SELECT a.version AS "assignmentVersion",a.valid_until AS "validUntil",
          m.version AS "membershipVersion",m.access_epoch AS "accessEpoch"
          FROM drivy.instructor_assignment a JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.instructor_membership_id
          WHERE a.school_id=$1 AND a.id=$2`, [scenario.school, scenario.assignment])).rows[0]!;
      summary.secondReplay = secondReplay;
      summary.versionsStable = stateBefore.assignmentVersion === stateAfter.assignmentVersion
        && stateBefore.membershipVersion === stateAfter.membershipVersion
        && stateBefore.accessEpoch === stateAfter.accessEpoch
        && String(stateBefore.validUntil) === String(stateAfter.validUntil);
      // Preuves d'accès : aucun lien rouvert, ni écriture ni lecture postérieure, paire inéligible.
      // Preuves d'accès : contexte d'acteur posé pour les fonctions de droits, comme le fait l'API.
      const cutSequence = Number((await restoredDb.query<{ cut: string }>(
        `SELECT cut_sequence AS cut FROM drivy.messaging_member_link WHERE school_id=$1 AND conversation_id=$2
         AND person_id=$3 AND cut_sequence IS NOT NULL`, [scenario.school, scenario.conversation, scenario.learner])).rows[0]!.cut);
      const accessDb = await restored.connect();
      try {
        await accessDb.query('BEGIN');
        await accessDb.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)",
          [scenario.school, scenario.learner]);
        summary.accessAfterReplay = (await accessDb.query<{ openLinks: number; canWrite: boolean; readableLast: boolean;
          pairEligible: boolean }>(`SELECT
            (SELECT count(*)::int FROM drivy.messaging_member_link WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 AND cut_sequence IS NULL) AS "openLinks",
            drivy.messaging_can_write($1,$3,$2) AS "canWrite",
            drivy.messaging_readable_sequence($1,$3,$2,$5::bigint) AS "readableLast",
            drivy.messaging_pair_eligible($1,$4,$6) AS "pairEligible"`,
          [scenario.school, scenario.conversation, scenario.learner, scenario.learner, cutSequence + 1, scenario.instructor])).rows[0]!;
        await accessDb.query('COMMIT');
      } finally { accessDb.release(); }
      const access = summary.accessAfterReplay as { openLinks: number; canWrite: boolean; readableLast: boolean; pairEligible: boolean };
      const proven = verification.ok && afterSync.ok && summary.versionsStable === true
        && Object.values(secondReplay.applied).every(count => count === 0)
        && access.openLinks === 0 && access.canWrite === false && access.readableLast === false && access.pairEligible === false
        && Object.values(refusals).every(code => code !== 'ACCEPTED' && code !== 'UNKNOWN');
      summary.provenWithoutLinkReactivation = proven;
      summary.reopenAllowed = proven;
      if (!proven && !afterSync.ok) summary.blocker = 'MEMBER_LINK_REOPENED';
      steps.push('replay-verified');
      summary.ok = proven;
      return proven ? 0 : 3;
    } finally { restoredDb.release(); await restored.end(); }
  } catch (error) {
    summary.error = error instanceof Error ? error.message.slice(0, 80) : 'Error';
    const code = typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : undefined;
    if (code) summary.errorCode = code;
    if (error instanceof ArchiveError) summary.errorCode = error.code;
    return 1;
  } finally {
    if (pool) await pool.end();
    // Nettoyage des seules bases effectivement créées par cette tentative ; une base préexistante n'est jamais visée.
    for (const name of [...created].reverse()) await maintenance.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`).catch(() => undefined);
    summary.databasesCreated = created;
    summary.databasesDropped = [...created].reverse();
    await maintenance.end();
    await rm(workdir, { recursive: true, force: true }).catch(() => undefined);
    console.log(JSON.stringify(summary, null, 2));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await scenarioMain();
}
