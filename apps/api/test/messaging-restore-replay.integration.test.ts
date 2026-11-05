import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Client, Pool, type PoolClient } from 'pg';
import { freshDatabase, issuer } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/errors.js';
import { ARCHIVE_FORMAT, ArchiveError, DatabaseCollisionError, collectScope, exportArchive, planDatabaseNames, readArchiveFile,
  replayArchive, validateArchive, verifyRestoredState, writeArchiveFile, type ArchiveEntry, type RestoreArchive,
  type ReservedConnection } from '../scripts/messaging-restore-replay.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool = new Pool({ connectionString: url, max: 8 });
const app = buildApp({
  pool,
  cursorSecret: 'messaging-restore-replay-secret-32ch!',
  messaging: { mode: 'qualification', schoolIds: [id.schoolA] },
  verifyToken: async authorization => {
    if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
    return { issuer, subject: authorization.slice(7) };
  }
});
const path = `/v1/schools/${id.schoolA}/messaging`;
const deviceA = 'RESTOREA001';
const deviceB = 'RESTOREB001';
const deviceC = 'RESTOREB002';
const subjects: Record<string, string> = { 'demo-instructor': id.instructor, 'demo-alice': id.alice };
const headers = (subject: string, device: string | null = deviceA, epoch = '1') => ({
  authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!,
  'x-drivy-expected-access-epoch': epoch, ...(device ? { 'x-drivy-device-id': device } : {}) });
const call = (subject: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', target: string, payload?: unknown,
  device: string | null = deviceA, epoch = '1') => {
  const base = headers(subject, device, epoch);
  if (payload === undefined) return app.inject({ method, url: `${path}${target}`, headers: base });
  if (Buffer.isBuffer(payload)) return app.inject({ method, url: `${path}${target}`,
    headers: { ...base, 'content-type': 'application/octet-stream' }, payload });
  return app.inject({ method, url: `${path}${target}`,
    headers: { ...base, 'content-type': 'application/json' }, payload: JSON.stringify(payload) });
};
const envelope = { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' };
const cipherBytes = (size: number, seed = 7) => Buffer.from(Array.from({ length: size }, (_value, index) => (index * 31 + seed) % 256));
const digestOf = (entries: readonly ArchiveEntry[]) => createHash('sha256').update(JSON.stringify(entries)).digest('hex');
const reserved = async <T>(work: (db: ReservedConnection) => Promise<T>): Promise<T> => {
  const db = await pool.connect();
  try { return await work(db); } finally { db.release(); }
};

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => {
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');
  await pool.query('TRUNCATE drivy.messaging_media_purge');
  await seedFixtures(pool, issuer);
  for (const [person, device] of [[id.instructor, deviceA], [id.alice, deviceB]] as const)
    await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject,device_keys)
      VALUES($1,$2,$3,$4,'restore',$5)`, [id.schoolA, person, device, issuer, JSON.stringify({ synthetic: `KEY-${device}` })]);
});
afterAll(async () => { await app.close(); await pool.end(); });

async function openPrivate(): Promise<string> {
  const opened = await call('demo-instructor', 'PUT', `/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}

/** Archive synthétique complet, pour éprouver la validation sans base supplémentaire. */
function syntheticArchive(): RestoreArchive {
  const entries: ArchiveEntry[] = [
    { sequence: 1, kind: 'MEDIA_PURGED', schoolId: id.schoolA, mediaId: randomUUID(), messageId: null, reason: 'CANCELLED',
      purgedAt: '2026-11-05T10:00:00.000Z', mediaPurgeSequence: 1 },
    { sequence: 2, kind: 'MESSAGE_DELETED', schoolId: id.schoolA, conversationId: randomUUID(), messageId: randomUUID(),
      deletedAt: '2026-11-05T10:01:00.000Z', deletedByPersonId: id.instructor },
    { sequence: 3, kind: 'DEVICE_REVOKED', schoolId: id.schoolA, personId: id.alice, deviceId: 'RESTOREB001',
      revokedAt: '2026-11-05T10:02:00.000Z' },
    { sequence: 4, kind: 'MEMBER_LINK_CUT', schoolId: id.schoolA, conversationId: randomUUID(), personId: id.alice,
      linkNumber: 1, cutSequence: 2, cutAt: '2026-11-05T10:03:00.000Z' },
    { sequence: 5, kind: 'GENERAL_REMOVAL', schoolId: id.schoolA, membershipId: id.bobMember, personId: id.bob,
      removedByPersonId: id.admin, removedAt: '2026-11-05T10:04:00.000Z' },
    { sequence: 6, kind: 'ASSIGNMENT_ENDED', schoolId: id.schoolA, assignmentId: id.assignment, trainingId: id.aliceTraining,
      instructorMembershipId: id.instructorMember, instructorPersonId: id.instructor, learnerPersonId: id.alice,
      validFrom: '2026-01-01T00:00:00.000Z', validUntil: '2026-11-05T10:05:00.000Z', version: 2,
      membershipVersion: 2, membershipAccessEpoch: 2 }
  ];
  return { format: ARCHIVE_FORMAT, createdAt: '2026-11-05T10:05:00.000Z',
    scope: { schoolIds: [id.schoolA, id.schoolB].sort(), conversationCount: 1, messageCount: 1, mediaCount: 1,
      deviceCount: 1, memberLinkCount: 1, generalRemovalCount: 1 },
    source: { mediaPurgeThrough: 1, mediaPurgeCount: 1 }, archivedThrough: entries.length, entries, digest: digestOf(entries) };
}

describe('restauration de sauvegarde : rejeu d’une source indépendante avant remise en lecture', () => {
  it('planifie des bases uniques et refuse toute collision avant mutation', () => {
    expect(planDatabaseNames([], 'abc12345')).toEqual({ source: 'drivy_restore_src_abc12345',
      target: 'drivy_restore_target_abc12345', sentinel: 'drivy_restore_sentinel_abc12345' });
    // Une base préexistante, même synthétique et même préfixée, n'est jamais réutilisée ni supprimée.
    expect(() => planDatabaseNames(['drivy_restore_src_abc12345'], 'abc12345')).toThrow(DatabaseCollisionError);
    expect(() => planDatabaseNames(['drivy_restore_target_abc12345'], 'abc12345')).toThrow(DatabaseCollisionError);
    expect(() => planDatabaseNames([], 'court')).toThrow('DATABASE_SUFFIX_INVALID');
  });

  it('refuse une source absente, tronquée, trouée, incomplète, dupliquée ou hors périmètre', () => {
    const scope = { schoolIds: [id.schoolA, id.schoolB].sort() };
    const archive = syntheticArchive();
    const refusal = (raw: unknown) => {
      try { validateArchive(raw, scope); return 'ACCEPTED'; } catch (error) {
        return error instanceof ArchiveError ? error.code : 'UNKNOWN';
      }
    };
    expect(refusal(undefined)).toBe('ARCHIVE_ABSENT');
    expect(refusal('')).toBe('ARCHIVE_ABSENT');
    expect(refusal('{ not json')).toBe('ARCHIVE_UNREADABLE');
    expect(refusal({ ...archive, format: 'other/1' })).toBe('ARCHIVE_FORMAT');
    expect(refusal({ ...archive, entries: archive.entries.slice(0, -1) })).toBe('ARCHIVE_TRUNCATED');
    expect(refusal({ ...archive, digest: '0'.repeat(64) })).toBe('ARCHIVE_DIGEST_MISMATCH');
    expect(refusal({ ...archive, scope: { ...archive.scope, schoolIds: [...scope.schoolIds, randomUUID()] } }))
      .toBe('ARCHIVE_SCOPE_DIVERGENT');
    expect(refusal({ ...archive, source: { mediaPurgeThrough: 0, mediaPurgeCount: 0 } })).toBe('ARCHIVE_SOURCE_INCONSISTENT');
    expect(refusal({ ...archive, source: { mediaPurgeThrough: 3, mediaPurgeCount: 0 } })).toBe('ARCHIVE_SOURCE_INCONSISTENT');
    // Trou de séquence d'archive : entrée intermédiaire retirée, empreinte recalculée et borne ajustée.
    const gapped = archive.entries.filter((_entry, index) => index !== 1);
    expect(refusal({ ...archive, entries: gapped, archivedThrough: gapped.length, digest: digestOf(gapped) }))
      .toBe('ARCHIVE_SEQUENCE_GAP');
    // Fin de lien sans conversation : refusée, pas silencieusement comparée à NULL.
    const incomplete = archive.entries.map(entry => entry.kind === 'MEMBER_LINK_CUT'
      ? { ...entry, conversationId: undefined } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: incomplete, digest: digestOf(incomplete) })).toBe('ARCHIVE_UNREADABLE');
    // Doublon d'identité, raison inconnue, identifiant non UUID, borne négative.
    const duplicated = [...archive.entries, { ...archive.entries[0]!, sequence: archive.entries.length + 1 }] as ArchiveEntry[];
    expect(refusal({ ...archive, entries: duplicated, archivedThrough: duplicated.length, digest: digestOf(duplicated) })).toBe('ARCHIVE_DUPLICATE');
    const badReason = archive.entries.map(entry => entry.kind === 'MEDIA_PURGED' ? { ...entry, reason: 'BOGUS' } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badReason, digest: digestOf(badReason) })).toBe('ARCHIVE_UNREADABLE');
    const badSchool = archive.entries.map(entry => ({ ...entry, schoolId: 'pas-un-uuid' })) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badSchool, digest: digestOf(badSchool) })).toBe('ARCHIVE_UNREADABLE');
    const badLink = archive.entries.map(entry => entry.kind === 'MEMBER_LINK_CUT' ? { ...entry, linkNumber: 0 } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badLink, digest: digestOf(badLink) })).toBe('ARCHIVE_UNREADABLE');
    // Fin d'affectation : identités liées, bornes et versions consommées validées.
    const badTraining = archive.entries.map(entry => entry.kind === 'ASSIGNMENT_ENDED' ? { ...entry, trainingId: undefined } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badTraining, digest: digestOf(badTraining) })).toBe('ARCHIVE_UNREADABLE');
    const badVersion = archive.entries.map(entry => entry.kind === 'ASSIGNMENT_ENDED' ? { ...entry, version: 0 } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badVersion, digest: digestOf(badVersion) })).toBe('ARCHIVE_UNREADABLE');
    const badPair = archive.entries.map(entry => entry.kind === 'ASSIGNMENT_ENDED' ? { ...entry, instructorPersonId: id.alice } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badPair, digest: digestOf(badPair) })).toBe('ARCHIVE_UNREADABLE');
    const badBounds = archive.entries.map(entry => entry.kind === 'ASSIGNMENT_ENDED' ? { ...entry, validUntil: '2025-12-31T00:00:00.000Z' } : entry) as ArchiveEntry[];
    expect(refusal({ ...archive, entries: badBounds, digest: digestOf(badBounds) })).toBe('ARCHIVE_UNREADABLE');
    expect(refusal(archive)).toBe('ACCEPTED');
  });

  it('rejoue les retraits postérieurs au snapshot, sans résurrection ni double effet', async () => {
    const conversationId = await openPrivate();
    const mediaDeleted = randomUUID();
    const mediaCancelled = randomUUID();
    const mediaKept = randomUUID();
    const bytesDeleted = Buffer.concat([Buffer.from(`SENTINEL-MEDIA-${randomUUID()}`), cipherBytes(96)]);
    const envelopeSentinel = Buffer.from(`SENTINEL-ENVELOPE-${randomUUID()}`).toString('base64');
    const messageBody = { clientMessageId: randomUUID(), expectedMembersEpoch: 0,
      ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: envelopeSentinel }, media: { mediaId: mediaDeleted, byteSize: bytesDeleted.length } };
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaDeleted}`, bytesDeleted)).statusCode).toBe(200);
    const posted = await call('demo-instructor', 'POST', `/conversations/${conversationId}/messages`, messageBody);
    expect(posted.statusCode, posted.body).toBe(200);
    const messageId = posted.json().data.id as string;
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaCancelled}`, cipherBytes(48))).statusCode).toBe(200);
    const keptBytes = cipherBytes(64, 9);
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaKept}`, keptBytes)).statusCode).toBe(200);
    const keptMessage = await call('demo-instructor', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope, media: { mediaId: mediaKept, byteSize: keptBytes.length } });
    expect(keptMessage.statusCode, keptMessage.body).toBe(200);

    // État que contiendrait la sauvegarde : tout est encore lisible, appareil actif, lien ouvert, aucun retrait.
    const preMedia = (await pool.query<{ id: string; ciphertext: Buffer; sha: string }>(
      'SELECT id,ciphertext,ciphertext_sha256 AS sha FROM drivy.messaging_media WHERE id=ANY($1::uuid[])',
      [[mediaDeleted, mediaCancelled]])).rows;
    const preMessage = (await pool.query<{ envelope: unknown }>('SELECT envelope FROM drivy.messaging_message WHERE id=$1',
      [messageId])).rows[0]!;
    const preDevice = (await pool.query<{ deviceKeys: unknown }>('SELECT device_keys AS "deviceKeys" FROM drivy.messaging_device WHERE person_id=$1 AND device_id=$2',
      [id.alice, deviceB])).rows[0]!;
    expect(preMedia).toHaveLength(2);

    // Mutations postérieures au snapshot : suppression pour tous, annulation, révocation d'appareil, fin de lien,
    // retrait du général.
    expect((await call('demo-instructor', 'DELETE', `/conversations/${conversationId}/messages/${messageId}?scope=everyone`)).statusCode).toBe(200);
    expect((await call('demo-instructor', 'DELETE', `/conversations/${conversationId}/media/${mediaCancelled}`)).statusCode).toBe(200);
    await pool.query(`UPDATE drivy.messaging_device SET revoked_at=now(),device_keys=NULL WHERE person_id=$1 AND device_id=$2`,
      [id.alice, deviceB]);
    await pool.query(`UPDATE drivy.messaging_member_link SET cut_sequence=2,cut_at=now()
      WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 AND cut_sequence IS NULL`, [id.schoolA, conversationId, id.alice]);
    await pool.query(`INSERT INTO drivy.messaging_general_removal(school_id,membership_id,person_id,removed_by_person_id,removed_at)
      VALUES($1,$2,$3,$4,now()) ON CONFLICT DO NOTHING`, [id.schoolA, id.bobMember, id.bob, id.admin]);

    const archive = await reserved(db => exportArchive(db));
    const kinds = archive.entries.map(entry => entry.kind);
    expect(kinds.filter(kind => kind === 'MEDIA_PURGED')).toHaveLength(2);
    expect(kinds).toContain('MESSAGE_DELETED');
    expect(kinds).toContain('DEVICE_REVOKED');
    expect(kinds).toContain('MEMBER_LINK_CUT');
    expect(kinds).toContain('GENERAL_REMOVAL');
    expect(archive.archivedThrough).toBe(archive.entries.length);
    // La source indépendante ne contient ni octet, ni enveloppe, ni clé d'appareil.
    const serialized = JSON.stringify(archive);
    for (const secret of [bytesDeleted.toString('base64'), bytesDeleted.toString('hex'), envelopeSentinel,
      Buffer.from(envelopeSentinel, 'base64').toString('utf8'), `KEY-${deviceB}`])
      expect(serialized, secret.slice(0, 12)).not.toContain(secret);

    const scope = await reserved(db => collectScope(db));
    const file = `${process.env.TEMP ?? '/tmp'}/drivy-restore-archive-${randomUUID()}.json`;
    await writeArchiveFile(file, archive);
    const restoredSource: RestoreArchive = validateArchive(await readArchiveFile(file), scope);

    // Restauration simulée de l'ancien snapshot (le pg_restore réel est dans le scénario) : les retraits reviennent.
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      for (const row of preMedia)
        await db.query(`UPDATE drivy.messaging_media SET ciphertext=$2,ciphertext_sha256=$3,purged_at=NULL,purge_reason=NULL WHERE id=$1`,
          [row.id, row.ciphertext, row.sha]);
      await db.query(`UPDATE drivy.messaging_message SET envelope=$2::jsonb,deleted_at=NULL,deleted_by_person_id=NULL,pinned_at=NULL,
        pinned_by_person_id=NULL WHERE id=$1`, [messageId, JSON.stringify(preMessage.envelope)]);
      await db.query(`UPDATE drivy.messaging_device SET revoked_at=NULL,device_keys=$3::jsonb WHERE person_id=$1 AND device_id=$2`,
        [id.alice, deviceB, JSON.stringify(preDevice.deviceKeys)]);
      await db.query(`UPDATE drivy.messaging_member_link SET cut_sequence=NULL,cut_at=NULL
        WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3`, [id.schoolA, conversationId, id.alice]);
      await db.query('DELETE FROM drivy.messaging_general_removal WHERE school_id=$1 AND membership_id=$2', [id.schoolA, id.bobMember]);
      await db.query('DELETE FROM drivy.messaging_media_purge WHERE media_id=ANY($1::uuid[])', [[mediaDeleted, mediaCancelled]]);
      await db.query('COMMIT');
    } finally { db.release(); }
    // Résurrection prouvée : octets servis de nouveau et appareil de nouveau actif.
    const beforeReplay = await call('demo-instructor', 'GET', `/conversations/${conversationId}/media/${mediaDeleted}`);
    expect(beforeReplay.statusCode, beforeReplay.body).toBe(200);
    expect(Buffer.compare(beforeReplay.rawPayload, bytesDeleted)).toBe(0);

    const replay = await reserved(db => replayArchive(db, restoredSource));
    expect(replay.applied.MEDIA_PURGED).toBe(2);
    expect(replay.applied.MESSAGE_DELETED).toBe(1);
    expect(replay.applied.DEVICE_REVOKED).toBe(1);
    expect(replay.applied.MEMBER_LINK_CUT).toBe(1);
    expect(replay.applied.GENERAL_REMOVAL).toBe(1);
    expect(replay.journalEntries).toBe(2);
    const verification = await reserved(db => verifyRestoredState(db, restoredSource));
    expect(verification.ok, JSON.stringify(verification.problems)).toBe(true);
    expect(verification.violations).toEqual({ MEDIA_PURGED: 0, MESSAGE_DELETED: 0, DEVICE_REVOKED: 0, MEMBER_LINK_CUT: 0, GENERAL_REMOVAL: 0, ASSIGNMENT_ENDED: 0 });

    // Aucun octet purgé à nouveau servi, aucun message, aucun droit réactivé par l'état seul.
    const afterReplay = await call('demo-instructor', 'GET', `/conversations/${conversationId}/media/${mediaDeleted}`);
    expect(afterReplay.statusCode, afterReplay.body).toBe(404);
    expect(afterReplay.json().code).toBe('MEDIA_NOT_FOUND');
    const revokedDevice = await call('demo-alice', 'GET', `/conversations/${conversationId}/media/${mediaKept}`, undefined, deviceB);
    expect(revokedDevice.statusCode, revokedDevice.body).toBe(403);
    expect(revokedDevice.json().code).toBe('MESSAGING_DEVICE_REQUIRED');
    const page = await call('demo-instructor', 'GET', `/conversations/${conversationId}/messages`);
    const deleted = (page.json().data.items as { id: string; ciphertext: unknown; media: unknown }[]).find(item => item.id === messageId)!;
    expect(deleted.ciphertext).toBeNull();
    expect(deleted.media).toEqual({ mediaId: mediaDeleted, byteSize: bytesDeleted.length, deleted: true });
    const kept = (page.json().data.items as { id: string; media: { deleted: boolean } }[]).find(item => item.id === keptMessage.json().data.id)!;
    expect(kept.media.deleted).toBe(false);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media_purge WHERE media_id=ANY($1::uuid[])',
      [[mediaDeleted, mediaCancelled]])).rows[0]!.count).toBe(2);

    // C3 : la synchronisation réelle recrée un lien ouvert pour une personne encore éligible. Un appareil
    // distinct et actif prouve la réactivation ; le vérificateur doit la voir, pas seulement l'ancien numéro.
    await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject,device_keys)
      VALUES($1,$2,$3,$4,'restore','{"synthetic":"new"}')`, [id.schoolA, id.alice, deviceC, issuer]);
    const reopened = await reserved(db => verifyRestoredState(db, restoredSource));
    expect(reopened.ok).toBe(false);
    expect(reopened.problems).toContain('MEMBER_LINK_CUT:1');
    const learnerRead = await call('demo-alice', 'GET', `/conversations/${conversationId}/messages`, undefined, deviceC);
    expect(learnerRead.statusCode, learnerRead.body).toBe(200);
    const epoch = (await pool.query<{ epoch: string }>('SELECT members_epoch AS epoch FROM drivy.messaging_conversation WHERE id=$1',
      [conversationId])).rows[0]!.epoch;
    const learnerWrite = await call('demo-alice', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), expectedMembersEpoch: Number(epoch), ciphertext: envelope }, deviceC);
    expect(learnerWrite.statusCode, learnerWrite.body).toBe(200);

    // Idempotence des retraits restaurables : un second rejeu n'applique plus rien et ne change aucun état.
    const second = await reserved(db => replayArchive(db, restoredSource));
    expect(Object.values(second.applied).every(count => count === 0)).toBe(true);
    expect(second.journalEntries).toBe(0);
    expect((await call('demo-instructor', 'GET', `/conversations/${conversationId}/media/${mediaDeleted}`)).statusCode).toBe(404);
  });

  it('annule tout le rejeu après une erreur au milieu, sous concurrence', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(32);
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaId}`, bytes)).statusCode).toBe(200);
    const posted = await call('demo-instructor', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope });
    expect(posted.statusCode, posted.body).toBe(200);
    const messageId = posted.json().data.id as string;
    const entries: ArchiveEntry[] = [
      { sequence: 1, kind: 'MEDIA_PURGED', schoolId: id.schoolA, mediaId, messageId: null, reason: 'CANCELLED',
        purgedAt: '2026-11-05T11:00:00.000Z', mediaPurgeSequence: 1 },
      // Auteur inexistant : la contrainte de clé étrangère échoue après la première application.
      { sequence: 2, kind: 'MESSAGE_DELETED', schoolId: id.schoolA, conversationId, messageId,
        deletedAt: '2026-11-05T11:01:00.000Z', deletedByPersonId: randomUUID() }
    ];
    const archive: RestoreArchive = { format: ARCHIVE_FORMAT, createdAt: '2026-11-05T11:02:00.000Z',
      scope: { schoolIds: [id.schoolA, id.schoolB].sort(), conversationCount: 1, messageCount: 1, mediaCount: 1,
        deviceCount: 2, memberLinkCount: 2, generalRemovalCount: 0 },
      source: { mediaPurgeThrough: 1, mediaPurgeCount: 1 }, archivedThrough: 2, entries, digest: digestOf(entries) };
    // Plusieurs connexions occupées pendant le rejeu : la transaction doit rester sur sa connexion réservée.
    const busy: PoolClient[] = [];
    for (let index = 0; index < 3; index++) {
      const client = await pool.connect();
      await client.query('BEGIN');
      await client.query('SELECT count(*) FROM drivy.messaging_media');
      busy.push(client);
    }
    try {
      await expect(reserved(db => replayArchive(db, archive))).rejects.toMatchObject({ code: '23503' });
    } finally {
      for (const client of busy) { await client.query('ROLLBACK'); client.release(); }
    }
    const media = (await pool.query<{ ciphertext: Buffer | null; purgedAt: Date | null }>(
      'SELECT ciphertext,purged_at AS "purgedAt" FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!;
    expect(media.ciphertext).not.toBeNull();
    expect(media.purgedAt).toBeNull();
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media_purge WHERE media_id=$1', [mediaId])).rows[0]!.count).toBe(0);
  });

  it('exécute le rejeu sur la connexion réservée, jamais sur une autre connexion du pool', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(24);
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaId}`, bytes)).statusCode).toBe(200);
    const entries: ArchiveEntry[] = [{ sequence: 1, kind: 'MEDIA_PURGED', schoolId: id.schoolA, mediaId, messageId: null,
      reason: 'CANCELLED', purgedAt: '2026-11-05T12:00:00.000Z', mediaPurgeSequence: 1 }];
    const archive: RestoreArchive = { format: ARCHIVE_FORMAT, createdAt: '2026-11-05T12:01:00.000Z',
      scope: { schoolIds: [id.schoolA, id.schoolB].sort(), conversationCount: 1, messageCount: 0, mediaCount: 1,
        deviceCount: 2, memberLinkCount: 2, generalRemovalCount: 0 },
      source: { mediaPurgeThrough: 1, mediaPurgeCount: 1 }, archivedThrough: 1, entries, digest: digestOf(entries) };
    const holder = new Client({ connectionString: url });
    await holder.connect();
    const worker = await pool.connect();
    try {
      const holderPid = (await holder.query<{ pid: number }>('SELECT pg_backend_pid() AS pid')).rows[0]!.pid;
      const workerPid = (await worker.query<{ pid: number }>('SELECT pg_backend_pid() AS pid')).rows[0]!.pid;
      await holder.query('BEGIN');
      await holder.query('SELECT 1 FROM drivy.messaging_media WHERE id=$1 FOR UPDATE', [mediaId]);
      const replay = replayArchive(worker, archive);
      let blockedByHolder: number | undefined;
      for (let attempt = 0; attempt < 150; attempt++) {
        const observed = await pool.query<{ pid: number }>(`SELECT pid FROM pg_stat_activity
          WHERE datname=current_database() AND wait_event_type='Lock' AND $1::int=ANY(pg_blocking_pids(pid)) LIMIT 1`, [holderPid]);
        if (observed.rows[0]) { blockedByHolder = observed.rows[0].pid; break; }
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      expect(blockedByHolder, 'le rejeu doit attendre le verrou du détenteur').toBeDefined();
      expect(blockedByHolder).toBe(workerPid);
      await holder.query('COMMIT');
      const report = await replay;
      expect(report.applied.MEDIA_PURGED).toBe(1);
    } finally {
      await holder.query('ROLLBACK').catch(() => undefined);
      await holder.end();
      worker.release();
    }
    expect((await pool.query('SELECT ciphertext FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.ciphertext).toBeNull();
  });

  it('fin d’affectation réelle : rejeu, synchronisation répétée, aucun lien rouvert ni accès postérieur', async () => {
    const conversationId = await openPrivate();
    const mediaBefore = randomUUID();
    const bytesBefore = cipherBytes(40);
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaBefore}`, bytesBefore)).statusCode).toBe(200);
    const before = await call('demo-instructor', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope,
        media: { mediaId: mediaBefore, byteSize: bytesBefore.length } });
    expect(before.statusCode, before.body).toBe(200);
    const pre = (await pool.query<{ assignmentVersion: number; validUntil: Date | null; membershipVersion: number;
      accessEpoch: number }>(`SELECT a.version AS "assignmentVersion",a.valid_until AS "validUntil",
        m.version AS "membershipVersion",m.access_epoch AS "accessEpoch"
        FROM drivy.instructor_assignment a JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.instructor_membership_id
        WHERE a.school_id=$1 AND a.id=$2`, [id.schoolA, id.assignment])).rows[0]!;
    expect(pre.validUntil).toBeNull();
    // Fin d'affectation par le mécanisme métier existant (route END_ASSIGNMENT), pas par une coupe arbitraire.
    const endOperation = randomUUID();
    const ended = await app.inject({ method: 'POST',
      url: `/v1/schools/${id.schoolA}/trainings/${id.aliceTraining}/assignments/${id.assignment}/end`,
      headers: { authorization: 'Bearer demo-admin', 'idempotency-key': endOperation,
        'if-match': `"${pre.assignmentVersion}"`, 'content-type': 'application/json' },
      payload: JSON.stringify({ operationId: endOperation }) });
    expect(ended.statusCode, ended.body).toBe(200);
    // END_ASSIGNMENT incrémente aussi l'époque d'accès de l'adhésion du moniteur : les appels suivants la relisent.
    const instructorEpoch = String((await pool.query<{ epoch: number }>(
      'SELECT access_epoch AS epoch FROM drivy.membership WHERE id=$1', [id.instructorMember])).rows[0]!.epoch);
    expect(instructorEpoch).not.toBe('1');
    // La synchronisation produit coupe le lien devenu inéligible.
    expect((await call('demo-instructor', 'GET', `/conversations/${conversationId}/messages`, undefined, deviceA, instructorEpoch)).statusCode).toBe(200);
    const archive = await reserved(db => exportArchive(db));
    const kinds = archive.entries.map(entry => entry.kind);
    expect(kinds).toContain('ASSIGNMENT_ENDED');
    expect(kinds).toContain('MEMBER_LINK_CUT');
    const assignmentEntry = archive.entries.find(entry => entry.kind === 'ASSIGNMENT_ENDED') as Extract<ArchiveEntry, { kind: 'ASSIGNMENT_ENDED' }>;
    expect(assignmentEntry).toMatchObject({ assignmentId: id.assignment, trainingId: id.aliceTraining,
      instructorMembershipId: id.instructorMember, instructorPersonId: id.instructor, learnerPersonId: id.alice });
    expect(assignmentEntry.version).toBeGreaterThan(pre.assignmentVersion);
    // Restauration simulée : affectation, adhésion et lien reviennent à l'état du dump.
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('UPDATE drivy.instructor_assignment SET valid_until=NULL,version=$3 WHERE school_id=$1 AND id=$2',
        [id.schoolA, id.assignment, pre.assignmentVersion]);
      await db.query('UPDATE drivy.membership SET version=$3,access_epoch=$4 WHERE school_id=$1 AND id=$2',
        [id.schoolA, id.instructorMember, pre.membershipVersion, pre.accessEpoch]);
      await db.query('UPDATE drivy.messaging_member_link SET cut_sequence=NULL,cut_at=NULL WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3',
        [id.schoolA, conversationId, id.alice]);
      await db.query('COMMIT');
    } finally { db.release(); }
    const restoredSource = validateArchive(archive, await reserved(d => collectScope(d)));
    const replay = await reserved(d => replayArchive(d, restoredSource));
    expect(replay.applied.ASSIGNMENT_ENDED).toBe(1);
    expect(replay.applied.MEMBER_LINK_CUT).toBe(1);
    // Synchronisation réelle répétée : aucun nouveau lien, aucune éligibilité résiduelle.
    for (let index = 0; index < 2; index++)
      expect((await call('demo-instructor', 'GET', `/conversations/${conversationId}/messages`, undefined, deviceA, instructorEpoch)).statusCode).toBe(200);
    const verification = await reserved(d => verifyRestoredState(d, restoredSource));
    expect(verification.ok, JSON.stringify(verification.problems)).toBe(true);
    const cutSequence = Number((await pool.query<{ cut: string }>(
      `SELECT cut_sequence AS cut FROM drivy.messaging_member_link WHERE school_id=$1 AND conversation_id=$2
       AND person_id=$3 AND cut_sequence IS NOT NULL`, [id.schoolA, conversationId, id.alice])).rows[0]!.cut);
    const state = (await pool.query<{ openLinks: number; canWrite: boolean; readableNew: boolean; pairEligible: boolean }>(
      `SELECT (SELECT count(*)::int FROM drivy.messaging_member_link WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3
          AND cut_sequence IS NULL) AS "openLinks",
        drivy.messaging_can_write($1,$3,$2) AS "canWrite",
        drivy.messaging_readable_sequence($1,$3,$2,$5::bigint) AS "readableNew",
        drivy.messaging_pair_eligible($1,$3,$4) AS "pairEligible"`,
      [id.schoolA, conversationId, id.alice, id.instructor, cutSequence + 1])).rows[0]!;
    expect(state).toEqual({ openLinks: 0, canWrite: false, readableNew: false, pairEligible: false });
    // Appareil distinct et actif : l'ancienne plage reste lisible (droit légitime), aucune plage postérieure,
    // aucune écriture. Un appareil actif ne ressuscite pas un droit que la fin d'affectation a retiré.
    await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject,device_keys)
      VALUES($1,$2,$3,$4,'restore','{"synthetic":"new"}')`, [id.schoolA, id.alice, deviceC, issuer]);
    const learnerPage = await call('demo-alice', 'GET', `/conversations/${conversationId}/messages`, undefined, deviceC);
    expect(learnerPage.statusCode, learnerPage.body).toBe(200);
    const sequences = (learnerPage.json().data.items as { sequence: number }[]).map(item => item.sequence);
    expect(sequences.length).toBeGreaterThan(0);
    expect(sequences.every(sequence => sequence <= cutSequence)).toBe(true);
    const learnerOldMedia = await call('demo-alice', 'GET', `/conversations/${conversationId}/media/${mediaBefore}`, undefined, deviceC);
    expect(learnerOldMedia.statusCode, learnerOldMedia.body).toBe(200);
    const learnerWrite = await call('demo-alice', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope }, deviceC);
    expect(learnerWrite.statusCode, learnerWrite.body).toBe(403);
    // Second rejeu : aucune application, versions et époques stables.
    const versions = async () => (await pool.query<{ a: number; m: number; e: number; until: Date | null }>(
      `SELECT a.version AS a,m.version AS m,m.access_epoch AS e,a.valid_until AS until FROM drivy.instructor_assignment a
       JOIN drivy.membership m ON m.school_id=a.school_id AND m.id=a.instructor_membership_id WHERE a.school_id=$1 AND a.id=$2`,
      [id.schoolA, id.assignment])).rows[0]!;
    const versionsBefore = await versions();
    const second = await reserved(d => replayArchive(d, restoredSource));
    expect(Object.values(second.applied).every(count => count === 0)).toBe(true);
    expect(await versions()).toEqual(versionsBefore);
  });

  it('refuse une cible contradictoire au lieu de l’écraser', async () => {
    const version = (await pool.query<{ version: number }>('SELECT version FROM drivy.instructor_assignment WHERE school_id=$1 AND id=$2',
      [id.schoolA, id.assignment])).rows[0]!.version;
    const entries: ArchiveEntry[] = [{ sequence: 1, kind: 'ASSIGNMENT_ENDED', schoolId: id.schoolA, assignmentId: id.assignment,
      trainingId: id.aliceTraining, instructorMembershipId: id.instructorMember, instructorPersonId: id.instructor,
      learnerPersonId: id.alice, validFrom: '2026-01-01T00:00:00.000Z', validUntil: '2026-11-05T13:00:00.000Z',
      version, membershipVersion: 1, membershipAccessEpoch: 1 }];
    const archive: RestoreArchive = { format: ARCHIVE_FORMAT, createdAt: '2026-11-05T13:01:00.000Z',
      scope: { schoolIds: [id.schoolA, id.schoolB].sort(), conversationCount: 0, messageCount: 0, mediaCount: 0,
        deviceCount: 2, memberLinkCount: 0, generalRemovalCount: 0 },
      source: { mediaPurgeThrough: 0, mediaPurgeCount: 0 }, archivedThrough: 1, entries, digest: digestOf(entries) };
    // Cible plus récente que la source : la décision revient à l'exploitant, aucune écriture.
    await pool.query('UPDATE drivy.instructor_assignment SET version=version+1 WHERE school_id=$1 AND id=$2', [id.schoolA, id.assignment]);
    await expect(reserved(db => replayArchive(db, archive))).rejects.toMatchObject({ name: 'RestoreStateError',
      code: 'ASSIGNMENT_STATE_AMBIGUOUS' });
    const row = (await pool.query<{ validUntil: Date | null }>('SELECT valid_until AS "validUntil" FROM drivy.instructor_assignment WHERE school_id=$1 AND id=$2',
      [id.schoolA, id.assignment])).rows[0]!;
    expect(row.validUntil).toBeNull();
  });
});
