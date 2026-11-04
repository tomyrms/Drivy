import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase, issuer } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const pool = new Pool({ connectionString: url, max: 8 });
const app = buildApp({
  pool,
  cursorSecret: 'messaging-media-recipe-secret-32-chars!!',
  messaging: { mode: 'qualification', schoolIds: [id.schoolA] },
  verifyToken: async authorization => {
    if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
    return { issuer, subject: authorization.slice(7) };
  }
});
const path = `/v1/schools/${id.schoolA}/messaging`;
const deviceA = 'DEVICEA0001';
const deviceB = 'DEVICEB0001';
const deviceForeign = 'DEVICEF0001';
const deviceC = 'DEVICEC0001';
const deviceD = 'DEVICED0001';
const subjects: Record<string, string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor,
  'demo-alice': id.alice, 'demo-bob': id.bob, 'demo-other-instructor': id.otherInstructor, 'demo-foreign': id.foreign };
const headers = (subject: string, device: string | null = deviceA, expectedPersonId?: string) => ({
  authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': expectedPersonId ?? subjects[subject]!,
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
/** Octets chiffrés synthétiques : opaques pour le serveur, jamais du clair réel. */
const cipherBytes = (size: number, seed = 7) => Buffer.from(Array.from({ length: size }, (_value, index) => (index * 31 + seed) % 256));
const envelope = { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' };
const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

async function openPrivate(): Promise<string> {
  const opened = await call('demo-instructor', 'PUT', `/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
async function openGeneral(subject = 'demo-admin'): Promise<string> {
  const opened = await call(subject, 'PUT', '/general');
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
const upload = (subject: string, conversationId: string, mediaId: string, bytes: Buffer, device: string | null = deviceA) =>
  call(subject, 'PUT', `/conversations/${conversationId}/media/${mediaId}`, bytes, device);
const download = (subject: string, conversationId: string, mediaId: string, device: string | null = deviceA) =>
  call(subject, 'GET', `/conversations/${conversationId}/media/${mediaId}`, undefined, device);
const cancel = (subject: string, conversationId: string, mediaId: string, device: string | null = deviceA) =>
  call(subject, 'DELETE', `/conversations/${conversationId}/media/${mediaId}`, undefined, device);
const postMessage = (subject: string, conversationId: string, body: Record<string, unknown>, device: string | null = deviceA) =>
  call(subject, 'POST', `/conversations/${conversationId}/messages`, body, device);
const mediaBody = (mediaId: string, byteSize: number) => ({ clientMessageId: randomUUID(), expectedMembersEpoch: 0,
  ciphertext: envelope, media: { mediaId, byteSize } });
interface StoredRow { state: string; ciphertext: Buffer | null; sha: string; byteSize: string; messageId: string | null;
  purgedAt: Date | null; reason: string | null; createdAt: Date }
const mediaRow = async (mediaId: string): Promise<StoredRow> => {
  const rows = (await pool.query<StoredRow>(
    `SELECT CASE WHEN purged_at IS NOT NULL THEN 'PURGED' WHEN message_id IS NOT NULL THEN 'ATTACHED' ELSE 'UPLOADED' END AS state,
      ciphertext,ciphertext_sha256 AS sha,byte_size AS "byteSize",message_id AS "messageId",purged_at AS "purgedAt",
      purge_reason AS reason,created_at AS "createdAt" FROM drivy.messaging_media WHERE id=$1`, [mediaId])).rows;
  const row = rows[0];
  if (!row) throw new Error('ligne média attendue absente');
  return row;
};
const journal = async (mediaId: string) => (await pool.query<{ reason: string; sequence: string }>(
  'SELECT reason,sequence FROM drivy.messaging_media_purge WHERE media_id=$1 ORDER BY sequence', [mediaId])).rows;

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => {
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE');
  await pool.query('TRUNCATE drivy.messaging_media_purge');
  await seedFixtures(pool, issuer);
  for (const [person, device] of [[id.instructor, deviceA], [id.alice, deviceB], [id.bob, deviceC], [id.otherInstructor, deviceD], [id.foreign, deviceForeign]] as const)
    await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject)
      VALUES($1,$2,$3,$4,$5)`, [person === id.foreign ? id.schoolB : id.schoolA, person, device, issuer, 'demo']);
});
afterAll(async () => { await app.close(); await pool.end(); });

describe('messaging media PostgreSQL, opaque encrypted bytes only', () => {
  it('answers a uniform media 404 before any byte, hash or size is disclosed', async () => {
    const conversationId = await openPrivate();
    const absent = await download('demo-instructor', conversationId, randomUUID());
    expect(absent.statusCode, absent.body).toBe(404);
    expect(absent.json().code).toBe('MEDIA_NOT_FOUND');
    expect(absent.body).not.toMatch(/sha256|byteSize|UPLOADED|ATTACHED/);
  });

  it('stores an opaque deposit, recognises an identical retry and refuses other bytes under the same identifier', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(2048);
    const created = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(created.statusCode, created.body).toBe(200);
    expect(created.json().data).toEqual({ mediaId, byteSize: 2048, sha256: sha256(bytes), state: 'UPLOADED' });
    const stored = await mediaRow(mediaId);
    expect(stored.state).toBe('UPLOADED');
    expect(stored.sha).toBe(sha256(bytes));
    expect(Buffer.compare(stored.ciphertext!, bytes)).toBe(0);
    expect(Object.keys(created.json().data).sort()).toEqual(['byteSize', 'mediaId', 'sha256', 'state']);
    const retried = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(retried.statusCode, retried.body).toBe(200);
    expect(retried.json().data.state).toBe('UPLOADED');
    expect((await mediaRow(mediaId)).createdAt).toEqual(stored.createdAt);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(1);
    const conflict = await upload('demo-instructor', conversationId, mediaId, cipherBytes(2048, 11));
    expect(conflict.statusCode, conflict.body).toBe(409);
    expect(conflict.json().code).toBe('MEDIA_INTENT_CONFLICT');
    expect(Buffer.compare((await mediaRow(mediaId)).ciphertext!, bytes)).toBe(0);
  });

  it('attaches in the message transaction and recognises the deposit after attachment', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(4096);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const posted = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(posted.statusCode, posted.body).toBe(200);
    const message = posted.json().data;
    expect(message.media).toEqual({ mediaId, byteSize: 4096, deleted: false });
    expect((await mediaRow(mediaId)).state).toBe('ATTACHED');
    expect((await mediaRow(mediaId)).messageId).toBe(message.id);
    const again = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(again.statusCode, again.body).toBe(200);
    expect(again.json().data.state).toBe('ATTACHED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(1);
    const served = await download('demo-alice', conversationId, mediaId, deviceB);
    expect(served.statusCode, served.body).toBe(200);
    expect(Buffer.compare(served.rawPayload, bytes)).toBe(0);
    expect(served.headers['content-type']).toBe('application/octet-stream');
    expect(served.headers['cache-control']).toBe('private, no-store');
    expect(served.headers['x-drivy-school-id']).toBe(id.schoolA);
    expect(served.headers['x-drivy-access-epoch']).toBe('1');
    expect(served.headers['x-drivy-media-sha256']).toBe(sha256(bytes));
    expect(Number(served.headers['content-length'])).toBe(4096);
    const page = await call('demo-alice', 'GET', `/conversations/${conversationId}/messages`, undefined, deviceB);
    expect(page.json().data.items[0].media).toEqual({ mediaId, byteSize: 4096, deleted: false });
    expect(page.body).not.toMatch(/ciphertext_sha256|purged_at|byte_size/);
  });

  it('replays one message intent with one attachment and refuses a second attachment', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(512);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const body = mediaBody(mediaId, bytes.length);
    const first = await postMessage('demo-instructor', conversationId, body);
    expect(first.statusCode, first.body).toBe(200);
    const replay = await postMessage('demo-instructor', conversationId, body);
    expect(replay.statusCode, replay.body).toBe(200);
    expect(replay.json().data).toEqual(first.json().data);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(1);
    const second = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(second.statusCode, second.body).toBe(409);
    expect(second.json().code).toBe('MEDIA_ALREADY_ATTACHED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(1);
    const otherIntent = await postMessage('demo-instructor', conversationId,
      { ...body, media: { mediaId: randomUUID(), byteSize: bytes.length } });
    expect(otherIntent.statusCode, otherIntent.body).toBe(409);
    expect(otherIntent.json().code).toBe('INTENT_CONFLICT');
  });

  it('refuses a declared size that differs from the stored bytes without inserting a message', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(100);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const mismatch = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, 101));
    expect(mismatch.statusCode, mismatch.body).toBe(409);
    expect(mismatch.json().code).toBe('MEDIA_SIZE_MISMATCH');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(0);
    expect((await pool.query('SELECT last_sequence FROM drivy.messaging_conversation WHERE id=$1', [conversationId])).rows[0]!.last_sequence).toBe('0');
    expect((await mediaRow(mediaId)).state).toBe('UPLOADED');
    expect((await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length))).statusCode).toBe(200);
  });

  it('bounds the body, the empty deposit and the declared device on media routes only', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const oversized = await upload('demo-instructor', conversationId, mediaId, Buffer.alloc(4_194_305, 1));
    expect(oversized.statusCode, oversized.body).toBe(413);
    expect(oversized.json().code).toBe('PAYLOAD_TOO_LARGE');
    const beyondRouteLimit = await upload('demo-instructor', conversationId, randomUUID(), Buffer.alloc(4_202_497, 1));
    expect(beyondRouteLimit.statusCode, beyondRouteLimit.body).toBe(413);
    const empty = await upload('demo-instructor', conversationId, mediaId, Buffer.alloc(0));
    expect(empty.statusCode, empty.body).toBe(400);
    expect(empty.json().code).toBe('INVALID_MEDIA');
    const invalidId = await upload('demo-instructor', conversationId, 'not-a-uuid', cipherBytes(8));
    expect(invalidId.statusCode, invalidId.body).toBe(400);
    expect(invalidId.json().code).toBe('INVALID_MEDIA');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(0);
    const missingDevice = await upload('demo-instructor', conversationId, mediaId, cipherBytes(8), null);
    expect(missingDevice.statusCode, missingDevice.body).toBe(403);
    expect(missingDevice.json().code).toBe('MESSAGING_DEVICE_REQUIRED');
    const unknownDevice = await upload('demo-instructor', conversationId, mediaId, cipherBytes(8), 'UNKNOWN0001');
    expect(unknownDevice.statusCode, unknownDevice.body).toBe(403);
    expect(unknownDevice.json().code).toBe('MESSAGING_DEVICE_REQUIRED');
    await pool.query(`UPDATE drivy.messaging_device SET revoked_at=now() WHERE person_id=$1 AND device_id=$2`, [id.instructor, deviceA]);
    const revoked = await upload('demo-instructor', conversationId, mediaId, cipherBytes(8));
    expect(revoked.statusCode, revoked.body).toBe(403);
    expect(revoked.json().code).toBe('MESSAGING_DEVICE_REQUIRED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(0);
    // La limite globale de l'API reste inchangée : un corps JSON ordinaire au-delà de 16 Kio est toujours refusé.
    const tooBigJson = await call('demo-instructor', 'POST', `/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), ciphertext: { ...envelope, payload: 'A'.repeat(20_000) } });
    expect(tooBigJson.statusCode).toBe(413);
  });

  it('serves no byte before attachment, after deletion for everyone, outside the range or when masked', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(1024);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const beforeAttach = await download('demo-alice', conversationId, mediaId, deviceB);
    expect(beforeAttach.statusCode, beforeAttach.body).toBe(404);
    expect(beforeAttach.json().code).toBe('MEDIA_NOT_FOUND');
    const posted = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(posted.statusCode, posted.body).toBe(200);
    const messageId = posted.json().data.id as string;
    // Hors plage : la plage lisible du lien est reculée au-delà de la séquence du message.
    await pool.query(`UPDATE drivy.messaging_member_link SET readable_after=(SELECT sequence FROM drivy.messaging_message WHERE id=$2)
      WHERE school_id=$1 AND conversation_id=$3 AND person_id=$4`, [id.schoolA, messageId, conversationId, id.alice]);
    const outOfRange = await download('demo-alice', conversationId, mediaId, deviceB);
    expect(outOfRange.statusCode, outOfRange.body).toBe(404);
    expect(outOfRange.json().code).toBe('MEDIA_NOT_FOUND');
    await pool.query(`UPDATE drivy.messaging_member_link SET readable_after=0
      WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3`, [id.schoolA, conversationId, id.alice]);
    // Masqué pour moi : l'autre participant continue de le recevoir.
    expect((await call('demo-alice', 'DELETE', `/conversations/${conversationId}/messages/${messageId}?scope=me`, undefined, deviceB)).statusCode).toBe(200);
    const masked = await download('demo-alice', conversationId, mediaId, deviceB);
    expect(masked.statusCode, masked.body).toBe(404);
    expect((await download('demo-instructor', conversationId, mediaId)).statusCode).toBe(200);
    // Suppression pour tout le monde : octets effacés, marque conservée, journal écrit, plus aucun octet servi.
    const removed = await call('demo-instructor', 'DELETE', `/conversations/${conversationId}/messages/${messageId}?scope=everyone`);
    expect(removed.statusCode, removed.body).toBe(200);
    const purged = await mediaRow(mediaId);
    expect(purged.state).toBe('PURGED');
    expect(purged.ciphertext).toBeNull();
    expect(purged.reason).toBe('MESSAGE_DELETED');
    expect((await journal(mediaId)).map(entry => entry.reason)).toEqual(['MESSAGE_DELETED']);
    const afterDelete = await download('demo-instructor', conversationId, mediaId);
    expect(afterDelete.statusCode, afterDelete.body).toBe(404);
    expect(afterDelete.json().code).toBe('MEDIA_NOT_FOUND');
    const page = await call('demo-instructor', 'GET', `/conversations/${conversationId}/messages`);
    expect(page.json().data.items[0].ciphertext).toBeNull();
    expect(page.json().data.items[0].media).toEqual({ mediaId, byteSize: 1024, deleted: true });
    // Rejouer la suppression ne produit ni second effet ni seconde entrée de journal.
    expect((await call('demo-instructor', 'DELETE', `/conversations/${conversationId}/messages/${messageId}?scope=everyone`)).statusCode).toBe(200);
    expect((await journal(mediaId)).length).toBe(1);
  });

  it('keeps a media inside the conversation and the school, never revealing a foreign row', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(64);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const posted = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(posted.statusCode, posted.body).toBe(200);
    const nonParticipant = await download('demo-other-instructor', conversationId, mediaId, deviceD);
    expect(nonParticipant.statusCode, nonParticipant.body).toBe(404);
    expect(nonParticipant.json().code).toBe('MEDIA_NOT_FOUND');
    const foreignSchool = await download('demo-foreign', conversationId, mediaId, deviceForeign);
    expect(foreignSchool.statusCode).toBe(403);
    expect(foreignSchool.body).not.toMatch(/sha256|byteSize/);
    // Un identifiant déjà pris par un média invisible reste un 404 uniforme, jamais un conflit de clé.
    const generalId = await openGeneral('demo-bob');
    const collision = await upload('demo-bob', generalId, mediaId, bytes, deviceC);
    expect(collision.statusCode, collision.body).toBe(404);
    expect(collision.json().code).toBe('MEDIA_NOT_FOUND');
    expect(collision.body).not.toMatch(/sha256|byteSize|409/);
    expect((await mediaRow(mediaId)).state).toBe('ATTACHED');
  });

  it('cancels only before attachment, stays idempotent and never resurrects purged bytes', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(256);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const cancelled = await cancel('demo-instructor', conversationId, mediaId);
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(cancelled.json().data).toEqual({ mediaId, deleted: true });
    expect((await mediaRow(mediaId)).state).toBe('PURGED');
    expect((await mediaRow(mediaId)).reason).toBe('CANCELLED');
    expect((await journal(mediaId)).map(entry => entry.reason)).toEqual(['CANCELLED']);
    expect((await cancel('demo-instructor', conversationId, mediaId)).statusCode).toBe(200);
    expect((await journal(mediaId)).length).toBe(1);
    const resurrect = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(resurrect.statusCode, resurrect.body).toBe(409);
    expect(resurrect.json().code).toBe('MEDIA_PURGED');
    expect((await mediaRow(mediaId)).ciphertext).toBeNull();
    // Attache d'un média purgé : 404 uniforme, aucun message inséré.
    const attachPurged = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(attachPurged.statusCode, attachPurged.body).toBe(404);
    expect(attachPurged.json().code).toBe('MEDIA_NOT_FOUND');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(0);
    const attachedId = randomUUID();
    expect((await upload('demo-instructor', conversationId, attachedId, bytes)).statusCode).toBe(200);
    expect((await postMessage('demo-instructor', conversationId, mediaBody(attachedId, bytes.length))).statusCode).toBe(200);
    const tooLate = await cancel('demo-instructor', conversationId, attachedId);
    expect(tooLate.statusCode, tooLate.body).toBe(409);
    expect(tooLate.json().code).toBe('MEDIA_ALREADY_ATTACHED');
    expect((await mediaRow(attachedId)).ciphertext).not.toBeNull();
  });

  it('purges orphans only before an explicit cutoff, without touching attached bytes, and replays without effect', async () => {
    const conversationId = await openPrivate();
    const oldId = randomUUID();
    const freshId = randomUUID();
    const attachedId = randomUUID();
    expect((await upload('demo-instructor', conversationId, oldId, cipherBytes(32))).statusCode).toBe(200);
    expect((await upload('demo-instructor', conversationId, freshId, cipherBytes(33))).statusCode).toBe(200);
    expect((await upload('demo-instructor', conversationId, attachedId, cipherBytes(34))).statusCode).toBe(200);
    expect((await postMessage('demo-instructor', conversationId, mediaBody(attachedId, 34))).statusCode).toBe(200);
    await pool.query(`UPDATE drivy.messaging_media SET created_at=now()-interval '3 days' WHERE id=$1`, [oldId]);
    const purged = await pool.query<{ purged: number }>('SELECT drivy.messaging_purge_orphan_media(now()-interval \'1 day\') AS purged');
    expect(purged.rows[0]!.purged).toBe(1);
    expect((await mediaRow(oldId)).state).toBe('PURGED');
    expect((await mediaRow(oldId)).reason).toBe('ORPHAN');
    expect((await mediaRow(freshId)).state).toBe('UPLOADED');
    expect((await mediaRow(attachedId)).state).toBe('ATTACHED');
    expect((await mediaRow(attachedId)).ciphertext).not.toBeNull();
    expect((await journal(oldId)).map(entry => entry.reason)).toEqual(['ORPHAN']);
    const replay = await pool.query<{ purged: number }>('SELECT drivy.messaging_purge_orphan_media(now()-interval \'1 day\') AS purged');
    expect(replay.rows[0]!.purged).toBe(0);
    expect((await journal(oldId)).length).toBe(1);
    // Le rôle applicatif ne peut pas déclencher la maintenance des orphelins.
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SET LOCAL ROLE drivy_app');
      await expect(client.query('SELECT drivy.messaging_purge_orphan_media(now())'))
        .rejects.toMatchObject({ code: '42501' });
    } finally { await client.query('ROLLBACK'); client.release(); }
  });

  it('serializes two identical deposits and races attachment against cancellation without a mixed state', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(300);
    const [first, second] = await Promise.all([
      upload('demo-instructor', conversationId, mediaId, bytes),
      upload('demo-instructor', conversationId, mediaId, bytes)
    ]);
    expect([first.statusCode, second.statusCode]).toEqual([200, 200]);
    expect(first.json().data).toEqual(second.json().data);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(1);
    const racingId = randomUUID();
    expect((await upload('demo-instructor', conversationId, racingId, bytes)).statusCode).toBe(200);
    const [attached, cancelled] = await Promise.all([
      postMessage('demo-instructor', conversationId, mediaBody(racingId, bytes.length)),
      cancel('demo-instructor', conversationId, racingId)
    ]);
    expect([attached.statusCode, cancelled.statusCode].filter(status => status === 200).length).toBe(1);
    const raced = await mediaRow(racingId);
    if (attached.statusCode === 200) {
      expect(cancelled.statusCode).toBe(409);
      expect(cancelled.json().code).toBe('MEDIA_ALREADY_ATTACHED');
      expect(raced.state).toBe('ATTACHED');
      expect(raced.ciphertext).not.toBeNull();
    } else {
      expect(attached.statusCode).toBe(404);
      expect(attached.json().code).toBe('MEDIA_NOT_FOUND');
      expect(raced.state).toBe('PURGED');
      expect(raced.ciphertext).toBeNull();
      expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(0);
    }
  });

  it('forces row level security for the application role and grants no direct media mutation', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    expect((await upload('demo-instructor', conversationId, mediaId, cipherBytes(128))).statusCode).toBe(200);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SET LOCAL ROLE drivy_app');
      await client.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.bob]);
      const foreign = await client.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId]);
      expect(foreign.rows[0]!.count).toBe(0);
      const privileges = await client.query<{ update: boolean; delete: boolean }>(
        `SELECT has_table_privilege('drivy_app','drivy.messaging_media','UPDATE') AS update,
          has_table_privilege('drivy_app','drivy.messaging_media','DELETE') AS delete`);
      expect(privileges.rows[0]).toEqual({ update: false, delete: false });
      const policies = await client.query<{ relrowsecurity: boolean; relforcerowsecurity: boolean }>(
        `SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='drivy.messaging_media'::regclass`);
      expect(policies.rows[0]).toEqual({ relrowsecurity: true, relforcerowsecurity: true });
    } finally { await client.query('ROLLBACK'); client.release(); }
    // Sans acteur lié, aucune ligne n'est visible même pour un identifiant connu.
    const anonymous = await pool.connect();
    try {
      await anonymous.query('BEGIN');
      await anonymous.query('SET LOCAL ROLE drivy_app');
      await anonymous.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id','',true)", [id.schoolA]);
      expect((await anonymous.query('SELECT count(*)::int AS count FROM drivy.messaging_media')).rows[0]!.count).toBe(0);
    } finally { await anonymous.query('ROLLBACK'); anonymous.release(); }
  });

  it('refuses a poll together with a media and accepts the exact 4 MiB ceiling once', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const both = await postMessage('demo-instructor', conversationId, { ...mediaBody(mediaId, 10),
      poll: { optionCount: 2, multiple: false } });
    expect(both.statusCode, both.body).toBe(400);
    expect(both.json().code).toBe('INVALID_REQUEST');
    const ceiling = await upload('demo-instructor', conversationId, mediaId, Buffer.alloc(4_194_304, 3));
    expect(ceiling.statusCode, ceiling.body).toBe(200);
    expect(ceiling.json().data.byteSize).toBe(4_194_304);
    expect((await mediaRow(mediaId)).state).toBe('UPLOADED');
  });

  it('stays behind the existing messaging qualification gate without widening it', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const closed = await app.inject({ method: 'PUT',
      url: `/v1/schools/${id.schoolB}/messaging/conversations/${conversationId}/media/${mediaId}`,
      headers: { ...headers('demo-foreign', deviceForeign), 'content-type': 'application/octet-stream' }, payload: cipherBytes(8) });
    expect(closed.statusCode, closed.body).toBe(503);
    expect(closed.json().code).toBe('MESSAGING_NOT_ENABLED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media')).rows[0]!.count).toBe(0);
  });
});
