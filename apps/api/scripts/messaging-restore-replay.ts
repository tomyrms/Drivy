import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { Pool, type Client } from 'pg';
import { migrate } from './migrations.js';
import { seedFixtures } from './fixtures.js';

/**
 * Restauration de sauvegarde de la messagerie sans réapparition des retraits (#68/#78/#97).
 *
 * Outillage d'exploitation, jamais chargé par le produit. Il fournit :
 *  - un export de journal indépendant (hors de la base restaurée) des retraits : purges média (séquence
 *    produit), suppressions de messages, révocations d'appareils, fins de lien et retraits du général ;
 *  - une validation stricte (source absente, illisible, tronquée, trou de séquence, périmètre divergent) ;
 *  - un rejeu idempotent, puis une vérification qu'aucun octet purgé, message supprimé, appareil révoqué ou
 *    lien coupé n'est revenu ;
 *  - un scénario local complet (snapshot synthétique, mutations postérieures, restauration isolée, rejeu)
 *    exécutable avec PostgreSQL réel et `pg_dump`/`pg_restore`.
 *
 * Limite explicite : ceci prouve le **mécanisme** en local. L'archivage durable de production (processus
 * continu, fsync, barrière de commit, rétention, résidence) reste à décider et à livrer (#68).
 */

export const ARCHIVE_FORMAT = 'drivy.messaging.restore-archive/1';
export type Queryable = Pick<Client, 'query'>;

export type ArchiveEntryKind = 'MEDIA_PURGED' | 'MESSAGE_DELETED' | 'DEVICE_REVOKED' | 'MEMBER_LINK_CUT' | 'GENERAL_REMOVAL';

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
export type ArchiveEntry = MediaPurgedEntry | MessageDeletedEntry | DeviceRevokedEntry | MemberLinkCutEntry | GeneralRemovalEntry;
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
  | 'ARCHIVE_SEQUENCE_GAP' | 'ARCHIVE_DIGEST_MISMATCH' | 'ARCHIVE_SCOPE_DIVERGENT' | 'ARCHIVE_SOURCE_INCONSISTENT';

export class ArchiveError extends Error {
  constructor(readonly code: ArchiveErrorCode, message: string) { super(message); this.name = 'ArchiveError'; }
}

const entryKinds: readonly ArchiveEntryKind[] = ['MEDIA_PURGED', 'MESSAGE_DELETED', 'DEVICE_REVOKED', 'MEMBER_LINK_CUT', 'GENERAL_REMOVAL'];
const digestOf = (entries: readonly ArchiveEntry[]) => createHash('sha256').update(JSON.stringify(entries)).digest('hex');
const iso = (value: Date | string) => new Date(value).toISOString();
const emptyCounts = (): Record<ArchiveEntryKind, number> =>
  ({ MEDIA_PURGED: 0, MESSAGE_DELETED: 0, DEVICE_REVOKED: 0, MEMBER_LINK_CUT: 0, GENERAL_REMOVAL: 0 });

/** État complet des retraits au moment de l'archivage : aucune clé, aucun octet, aucun contenu. */
export async function exportArchive(db: Queryable): Promise<RestoreArchive> {
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

const isObject = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const stamp = (value: unknown): value is string => typeof value === 'string' && !Number.isNaN(new Date(value).getTime());
const integer = (value: unknown): value is number => typeof value === 'number' && Number.isSafeInteger(value);

/** Refuse toute source absente, illisible, tronquée, trouée ou hors du périmètre de la base cible. */
export function validateArchive(raw: unknown, target: { schoolIds: readonly string[] }): RestoreArchive {
  if (raw === undefined || raw === null || raw === '') throw new ArchiveError('ARCHIVE_ABSENT', 'Aucune source de rejeu fournie.');
  let candidate: unknown = raw;
  if (typeof raw === 'string') {
    try { candidate = JSON.parse(raw); } catch { throw new ArchiveError('ARCHIVE_UNREADABLE', 'Source de rejeu illisible.'); }
  }
  if (!isObject(candidate)) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Source de rejeu illisible.');
  if (candidate.format !== ARCHIVE_FORMAT) throw new ArchiveError('ARCHIVE_FORMAT', 'Format de source de rejeu inconnu.');
  const scope = candidate.scope;
  if (!isObject(scope) || !Array.isArray(scope.schoolIds) || !scope.schoolIds.every(text))
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Périmètre de la source de rejeu invalide.');
  if (!Array.isArray(candidate.entries)) throw new ArchiveError('ARCHIVE_TRUNCATED', 'Source de rejeu sans entrées.');
  if (!integer(candidate.archivedThrough) || candidate.archivedThrough !== candidate.entries.length)
    throw new ArchiveError('ARCHIVE_TRUNCATED', 'Source de rejeu tronquée.');
  const entries = candidate.entries as ArchiveEntry[];
  for (const [index, entry] of entries.entries()) {
    if (!isObject(entry) || !entryKinds.includes(entry.kind as ArchiveEntryKind))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Entrée de rejeu invalide.');
    if (entry.sequence !== index + 1)
      throw new ArchiveError('ARCHIVE_SEQUENCE_GAP', 'Trou de séquence dans la source de rejeu.');
    if (!text(entry.schoolId)) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Entrée de rejeu sans périmètre.');
    if (entry.kind === 'MEDIA_PURGED' && (!text(entry.mediaId) || !integer(entry.mediaPurgeSequence) || !stamp(entry.purgedAt)))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Purge média invalide.');
    if (entry.kind === 'MESSAGE_DELETED' && (!text(entry.messageId) || !stamp(entry.deletedAt)))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Suppression de message invalide.');
    if (entry.kind === 'DEVICE_REVOKED' && (!text(entry.personId) || !text(entry.deviceId) || !stamp(entry.revokedAt)))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Révocation d’appareil invalide.');
    if (entry.kind === 'MEMBER_LINK_CUT' && (!text(entry.personId) || !integer(entry.linkNumber) || !integer(entry.cutSequence)
      || !stamp(entry.cutAt))) throw new ArchiveError('ARCHIVE_UNREADABLE', 'Fin de lien invalide.');
    if (entry.kind === 'GENERAL_REMOVAL' && (!text(entry.membershipId) || !text(entry.removedByPersonId) || !stamp(entry.removedAt)))
      throw new ArchiveError('ARCHIVE_UNREADABLE', 'Retrait du général invalide.');
  }
  if (candidate.digest !== digestOf(entries)) throw new ArchiveError('ARCHIVE_DIGEST_MISMATCH', 'Empreinte de la source de rejeu invalide.');
  const source = candidate.source;
  if (!isObject(source) || !integer(source.mediaPurgeThrough) || !integer(source.mediaPurgeCount))
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Référence de séquence média absente.');
  const mediaPurgeThrough: number = source.mediaPurgeThrough;
  const mediaPurgeCount: number = source.mediaPurgeCount;
  const purges = entries.filter((entry): entry is MediaPurgedEntry => entry.kind === 'MEDIA_PURGED');
  if (purges.some(entry => entry.mediaPurgeSequence > mediaPurgeThrough)
    || mediaPurgeCount !== purges.length
    || (purges.length > 0 && Math.max(...purges.map(entry => entry.mediaPurgeSequence)) !== mediaPurgeThrough))
    throw new ArchiveError('ARCHIVE_SOURCE_INCONSISTENT', 'Cohérence des séquences média rompue.');
  const targetSchools = [...target.schoolIds].sort();
  const scopeSchools = [...scope.schoolIds].sort();
  if (scopeSchools.length !== targetSchools.length || scopeSchools.some((id, index) => id !== targetSchools[index]))
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Périmètre de la source différent de la base cible.');
  const allowed = new Set(scopeSchools);
  if (entries.some(entry => !allowed.has(entry.schoolId)))
    throw new ArchiveError('ARCHIVE_SCOPE_DIVERGENT', 'Entrée de rejeu hors du périmètre de la base cible.');
  return candidate as unknown as RestoreArchive;
}

export async function collectScope(db: Queryable): Promise<{ schoolIds: string[] }> {
  return { schoolIds: (await db.query<{ id: string }>('SELECT id FROM drivy.school ORDER BY id')).rows.map(row => row.id) };
}

export interface ReplayReport {
  applied: Record<ArchiveEntryKind, number>;
  alreadyApplied: Record<ArchiveEntryKind, number>;
  journalEntries: number;
}

/**
 * Rejeu transactionnel et idempotent des retraits. À exécuter avec un rôle propriétaire, sur un client hors
 * transaction : la fonction ouvre et referme sa propre transaction.
 */
export async function replayArchive(db: Queryable, archive: RestoreArchive): Promise<ReplayReport> {
  const report: ReplayReport = { applied: emptyCounts(), alreadyApplied: emptyCounts(), journalEntries: 0 };
  await db.query('BEGIN');
  try {
    for (const entry of archive.entries) {
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
      } else {
        const removal = await db.query(`INSERT INTO drivy.messaging_general_removal(school_id,membership_id,person_id,
          removed_by_person_id,removed_at) VALUES($1,$2,$3,$4,$5::timestamptz)
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

/** Vérifie, après rejeu, qu'aucun retrait n'est revenu : ni octet purgé, ni message, ni appareil, ni droit. */
export async function verifyRestoredState(db: Queryable, archive: RestoreArchive): Promise<VerificationReport> {
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
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM drivy.messaging_member_link l
      WHERE (l.school_id,l.conversation_id,l.person_id,l.link_number) IN
        (SELECT * FROM unnest($1::uuid[],$2::uuid[],$3::uuid[],$4::int[])) AND l.cut_sequence IS NULL`,
      [links.map(entry => entry.schoolId), links.map(entry => entry.conversationId), links.map(entry => entry.personId),
        links.map(entry => entry.linkNumber)])).rows[0]!;
    report.violations.MEMBER_LINK_CUT = row.count;
  }
  const removals = of('GENERAL_REMOVAL');
  report.checked.GENERAL_REMOVAL = removals.length;
  if (removals.length > 0) {
    const row = (await db.query<{ count: number }>(`SELECT count(*)::int AS count FROM unnest($1::uuid[],$2::uuid[]) AS expected(school_id,membership_id)
      WHERE NOT EXISTS(SELECT 1 FROM drivy.messaging_general_removal r
        WHERE r.school_id=expected.school_id AND r.membership_id=expected.membership_id)`,
      [removals.map(entry => entry.schoolId), removals.map(entry => entry.membershipId)])).rows[0]!;
    report.violations.GENERAL_REMOVAL = row.count;
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
// Scénario local exécutable : snapshot synthétique, mutations postérieures, restauration isolée, rejeu.
// ---------------------------------------------------------------------------------------------------------------

const scenario = {
  school: '1b000000-0000-4000-8000-000000000068',
  otherSchool: '1b000000-0000-4000-8000-000000000069',
  instructor: '2b000000-0000-4000-8000-000000000068',
  learner: '2b000000-0000-4000-8000-000000000069',
  instructorMember: '3b000000-0000-4000-8000-000000000068',
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
      [scenario.learnerMember, scenario.learner, ['LEARNER']]])
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

async function applyPostSnapshotMutations(pool: Pool): Promise<void> {
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
  await pool.query(`UPDATE drivy.messaging_member_link SET cut_sequence=2,cut_at=now()
    WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 AND cut_sequence IS NULL`,
    [scenario.school, scenario.conversation, scenario.learner]);
}

const withDatabase = (url: string, database: string) => {
  const copy = new URL(url); copy.pathname = `/${database}`; return copy.toString();
};

const dockerExec = (container: string, args: string[], input?: Buffer) =>
  execFileSync('docker', ['exec', ...(input ? ['-i'] : []), container, ...args],
    { input, maxBuffer: 512 * 1024 * 1024 });

async function scenarioMain(): Promise<number> {
  const sourceUrl = process.env.RESTORE_SOURCE_URL;
  const container = process.env.RESTORE_DOCKER;
  const issuer = process.env.RESTORE_ISSUER ?? 'https://restore.example.invalid';
  if (!sourceUrl || !container) {
    console.error('Refus : RESTORE_SOURCE_URL et RESTORE_DOCKER sont obligatoires ; aucune base implicite.');
    return 2;
  }
  const parsed = new URL(sourceUrl);
  const database = parsed.pathname.replace(/^\//, '');
  if (!['127.0.0.1', 'localhost', '[::1]', '::1'].includes(parsed.hostname) || !/^drivy_restore_[a-z0-9_]+$/.test(database)) {
    console.error('Refus : cible locale synthétique nommée drivy_restore_* exigée.');
    return 2;
  }
  const user = decodeURIComponent(parsed.username);
  const maintenance = new Pool({ connectionString: withDatabase(sourceUrl, 'postgres'), max: 1 });
  const summary: Record<string, unknown> = { steps: [] as string[], refusals: {} as Record<string, string> };
  const steps = summary.steps as string[];
  const refusals = summary.refusals as Record<string, string>;
  const restoreDb = `drivy_restore_target_${randomUUID().replace(/-/g, '').slice(0, 8)}`;
  let pool: Pool | undefined;
  let accepted = 'UNKNOWN';
  const workdir = await mkdtemp(join(tmpdir(), 'drivy-restore-'));
  try {
    await maintenance.query(`DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
    await maintenance.query(`CREATE DATABASE ${database}`);
    pool = new Pool({ connectionString: sourceUrl, max: 4 });
    await prepareSyntheticSource(pool, issuer);
    steps.push('source-prepared');
    const dump = dockerExec(container, ['pg_dump', '-U', user, '--no-owner', '--no-privileges', '-Fc', '-d', database]);
    summary.dumpBytes = dump.length;
    summary.dumpDigestPrefix = createHash('sha256').update(dump).digest('hex').slice(0, 12);
    steps.push('snapshot-taken');
    await applyPostSnapshotMutations(pool);
    const archive = await exportArchive(pool);
    const archiveFile = join(workdir, 'archive.json');
    await writeArchiveFile(archiveFile, archive);
    steps.push('archive-exported');
    await maintenance.query(`CREATE DATABASE ${restoreDb}`);
    dockerExec(container, ['pg_restore', '-U', user, '--no-owner', '--no-privileges', '-d', restoreDb], dump);
    steps.push('snapshot-restored');
    const restored = new Pool({ connectionString: withDatabase(sourceUrl, restoreDb), max: 2 });
    try {
      summary.restoredBeforeReplay = (await restored.query<{ resurrectedMedia: number; resurrectedMessages: number;
        activeDevices: number; openLinks: number }>(`SELECT
          (SELECT count(*)::int FROM drivy.messaging_media WHERE id = ANY($1::uuid[]) AND ciphertext IS NOT NULL) AS "resurrectedMedia",
          (SELECT count(*)::int FROM drivy.messaging_message WHERE id = ANY($2::uuid[]) AND deleted_at IS NULL) AS "resurrectedMessages",
          (SELECT count(*)::int FROM drivy.messaging_device WHERE revoked_at IS NULL AND device_id = ANY($3::text[])) AS "activeDevices",
          (SELECT count(*)::int FROM drivy.messaging_member_link WHERE cut_sequence IS NULL AND person_id = $4) AS "openLinks"`,
          [[scenario.mediaDeleted, scenario.mediaOrphan], [scenario.messageDeleted], [scenario.deviceLearner], scenario.learner])).rows[0]!;
      const scope = await collectScope(restored);
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
      steps.push('archive-validated');
      accepted = validate(await readArchiveFile(archiveFile));
      const replay = await replayArchive(restored, archive);
      const verification = await verifyRestoredState(restored, archive);
      const secondReplay = await replayArchive(restored, archive);
      const secondVerification = await verifyRestoredState(restored, archive);
      summary.replay = replay;
      summary.verification = verification;
      summary.secondReplay = secondReplay;
      summary.secondVerification = secondVerification;
      const allSecondApplied = Object.values(secondReplay.applied).every(count => count === 0);
      summary.ok = accepted === 'ACCEPTED' && verification.ok && secondVerification.ok && allSecondApplied
        && Object.values(refusals).every(code => code !== 'ACCEPTED' && code !== 'UNKNOWN');
      steps.push('replay-verified');
    } finally { await restored.end(); }
    summary.archiveEntries = archive.entries.length;
    summary.archiveDigestPrefix = archive.digest.slice(0, 12);
    summary.archiveAccepted = accepted;
    return summary.ok === true ? 0 : 1;
  } catch (error) {
    summary.error = error instanceof Error ? error.name : 'Error';
    const code = typeof error === 'object' && error !== null && 'code' in error ? String(error.code) : undefined;
    if (code) summary.errorCode = code;
    if (error instanceof ArchiveError) summary.errorCode = error.code;
    return 1;
  } finally {
    if (pool) await pool.end();
    await maintenance.query(`DROP DATABASE IF EXISTS ${restoreDb} WITH (FORCE)`).catch(() => undefined);
    await maintenance.query(`DROP DATABASE IF EXISTS ${database} WITH (FORCE)`).catch(() => undefined);
    await maintenance.end();
    await rm(workdir, { recursive: true, force: true }).catch(() => undefined);
    console.log(JSON.stringify(summary, null, 2));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await scenarioMain();
}
