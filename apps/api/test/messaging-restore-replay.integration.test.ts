import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase, issuer } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/errors.js';
import { ArchiveError, collectScope, exportArchive, readArchiveFile, replayArchive, validateArchive,
  verifyRestoredState, writeArchiveFile, type RestoreArchive } from '../scripts/messaging-restore-replay.js';

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
const subjects: Record<string, string> = { 'demo-instructor': id.instructor, 'demo-alice': id.alice };
const headers = (subject: string, device: string | null = deviceA) => ({
  authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!,
  'x-drivy-expected-access-epoch': '1', ...(device ? { 'x-drivy-device-id': device } : {}) });
const call = (subject: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', target: string, payload?: unknown,
  device: string | null = deviceA) => {
  const base = headers(subject, device);
  if (payload === undefined) return app.inject({ method, url: `${path}${target}`, headers: base });
  if (Buffer.isBuffer(payload)) return app.inject({ method, url: `${path}${target}`,
    headers: { ...base, 'content-type': 'application/octet-stream' }, payload });
  return app.inject({ method, url: `${path}${target}`,
    headers: { ...base, 'content-type': 'application/json' }, payload: JSON.stringify(payload) });
};
const envelope = { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' };
const cipherBytes = (size: number, seed = 7) => Buffer.from(Array.from({ length: size }, (_value, index) => (index * 31 + seed) % 256));
const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

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

describe('restauration de sauvegarde : rejeu d’une source indépendante avant remise en lecture', () => {
  it('refuse une source absente, tronquée, trouée, illisible ou hors périmètre', async () => {
    // Retraits synthétiques (une purge média + deux révocations + un retrait) pour observer troncature et trou.
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const mediaBytes = cipherBytes(8);
    await pool.query(`INSERT INTO drivy.messaging_media(id,school_id,conversation_id,uploader_person_id,byte_size,
      ciphertext_sha256,ciphertext) VALUES($1,$2,$3,$4,$5,$6,$7)`,
      [mediaId, id.schoolA, conversationId, id.instructor, mediaBytes.length, sha256(mediaBytes), mediaBytes]);
    const purge = await pool.connect();
    try {
      await purge.query('BEGIN');
      await purge.query('SET LOCAL ROLE drivy_app');
      await purge.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.instructor]);
      await purge.query('SELECT drivy.messaging_purge_media($1,$2,$3)', [id.schoolA, mediaId, 'CANCELLED']);
      await purge.query('COMMIT');
    } finally { purge.release(); }
    await pool.query(`UPDATE drivy.messaging_device SET revoked_at=now() WHERE person_id=$1 AND device_id=$2`, [id.instructor, deviceA]);
    await pool.query(`UPDATE drivy.messaging_device SET revoked_at=now() WHERE person_id=$1 AND device_id=$2`, [id.alice, deviceB]);
    await pool.query(`INSERT INTO drivy.messaging_general_removal(school_id,membership_id,person_id,removed_by_person_id,removed_at)
      VALUES($1,$2,$3,$4,now()) ON CONFLICT DO NOTHING`, [id.schoolA, id.bobMember, id.bob, id.admin]);
    const scope = await collectScope(pool);
    const archive = await exportArchive(pool);
    expect(archive.entries.length).toBe(4);
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
    expect(refusal({ ...archive, scope: { ...archive.scope, schoolIds: [...archive.scope.schoolIds, randomUUID()] } }))
      .toBe('ARCHIVE_SCOPE_DIVERGENT');
    expect(refusal({ ...archive, source: { mediaPurgeThrough: 0, mediaPurgeCount: 0 } })).toBe('ARCHIVE_SOURCE_INCONSISTENT');
    // Trou de séquence : entrée intermédiaire retirée, empreinte recalculée et borne ajustée.
    const gapped = archive.entries.filter((_entry, index) => index !== 1);
    const digest = createHash('sha256').update(JSON.stringify(gapped)).digest('hex');
    expect(refusal({ ...archive, entries: gapped, archivedThrough: gapped.length, digest })).toBe('ARCHIVE_SEQUENCE_GAP');
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
    expect((await call('demo-instructor', 'PUT', `/conversations/${conversationId}/media/${mediaKept}`, cipherBytes(64, 9))).statusCode).toBe(200);
    const keptBytes = cipherBytes(64, 9);
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

    const archive = await exportArchive(pool);
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

    const scope = await collectScope(pool);
    const file = `${process.env.TEMP ?? '/tmp'}/drivy-restore-archive-${randomUUID()}.json`;
    await writeArchiveFile(file, archive);
    const restoredSource: RestoreArchive = validateArchive(await readArchiveFile(file), scope);

    // Restauration simulée de l'ancien snapshot : les retraits postérieurs réapparaissent.
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

    const replay = await replayArchive(pool, restoredSource);
    expect(replay.applied.MEDIA_PURGED).toBe(2);
    expect(replay.applied.MESSAGE_DELETED).toBe(1);
    expect(replay.applied.DEVICE_REVOKED).toBe(1);
    expect(replay.applied.MEMBER_LINK_CUT).toBe(1);
    expect(replay.applied.GENERAL_REMOVAL).toBe(1);
    expect(replay.journalEntries).toBe(2);
    const verification = await verifyRestoredState(pool, restoredSource);
    expect(verification.ok, JSON.stringify(verification.problems)).toBe(true);
    expect(verification.violations).toEqual({ MEDIA_PURGED: 0, MESSAGE_DELETED: 0, DEVICE_REVOKED: 0, MEMBER_LINK_CUT: 0, GENERAL_REMOVAL: 0 });

    // Aucun octet purgé à nouveau servi, aucun message, aucun droit réactivé.
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

    // Idempotence : un second rejeu n'a plus rien à appliquer et ne change aucun état.
    const second = await replayArchive(pool, restoredSource);
    expect(Object.values(second.applied).every(count => count === 0)).toBe(true);
    expect(second.journalEntries).toBe(0);
    expect((await verifyRestoredState(pool, restoredSource)).ok).toBe(true);
    expect((await call('demo-instructor', 'GET', `/conversations/${conversationId}/media/${mediaDeleted}`)).statusCode).toBe(404);
  });
});
