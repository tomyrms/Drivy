import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import type { FastifyServerOptions } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Client, Pool } from 'pg';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { fullFormats } from 'ajv-formats/dist/formats.js';
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
// Instrumentation de FIXTURE seulement : impose un requestId de test (pour reproduire un identifiant réel contenant
// une sous-chaîne comme « 409 »). Aucun générateur d'ID ni gestionnaire d'erreurs du produit n'est modifié.
app.addHook('onRequest', async request => {
  const forced = request.headers['x-test-request-id'];
  if (typeof forced === 'string' && forced.length > 0) request.id = forced;
});
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
interface ProblemResponse { statusCode: number; body: string; json(): unknown }
/**
 * Vérifie un refus média réel par son STATUT et son TYPE/CODE de problème, jamais par des sous-chaînes du corps :
 * un requestId légal peut contenir « 409 » (ou tout autre fragment) sans qu'il s'agisse d'un conflit.
 * Seuls les champs de métadonnée média sont interdits.
 */
function expectProblem(response: ProblemResponse, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  const body = response.json() as Record<string, unknown>;
  expect(body).toMatchObject({ status, code, type: `urn:drivy:problem:${code.toLowerCase()}` });
  expect(typeof body.requestId).toBe('string');
  expect(Object.keys(body).sort()).toEqual(['code', 'requestId', 'status', 'title', 'type']);
  expect(JSON.stringify(body)).not.toMatch(/sha256|byteSize|ciphertext|purgedAt|mediaId|messageId/);
}
/** Réponse de problème fabriquée par la fixture : prouve que le vérificateur refuse un code erroné ou une fuite. */
function problemResponse(status: number, code: string, extra: Record<string, unknown> = {}): ProblemResponse {
  const body = { type: `urn:drivy:problem:${code.toLowerCase()}`, title: 'Refus', status, code,
    requestId: '40900000-0000-4000-8000-000000000409', ...extra };
  return { statusCode: status, body: JSON.stringify(body), json: () => body };
}

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
    // Hors média, aucun parser `application/octet-stream` n'existe : le transport refuse le type (415) au lieu
    // d'accepter 20 Kio ou 1 Mio puis de laisser le schéma répondre 400.
    for (const size of [20_000, 1_000_000]) {
      const ordinary = await app.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/read-state`,
        headers: { ...headers('demo-instructor'), 'content-type': 'application/octet-stream' }, payload: Buffer.alloc(size, 1) });
      expect(ordinary.statusCode, ordinary.body).toBe(415);
      expect(ordinary.json().code).toBe('UNSUPPORTED_MEDIA_TYPE');
    }
    const messagesOctet = await app.inject({ method: 'POST', url: `${path}/conversations/${conversationId}/messages`,
      headers: { ...headers('demo-instructor'), 'content-type': 'application/octet-stream' }, payload: Buffer.alloc(20_000, 1) });
    expect(messagesOctet.statusCode, messagesOctet.body).toBe(415);
    await pool.query(`UPDATE drivy.messaging_device SET revoked_at=NULL WHERE person_id=$1 AND device_id=$2`, [id.instructor, deviceA]);
    // Le corps média est binaire brut : un corps JSON est refusé par le transport, et une chaîne qui ressemble à
    // du base64 n'est jamais décodée (elle reste quatre octets opaques tels quels).
    const jsonBody = await app.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${randomUUID()}`,
      headers: { ...headers('demo-instructor'), 'content-type': 'application/json' }, payload: JSON.stringify({ bytes: 'AAAA' }) });
    expect(jsonBody.statusCode, jsonBody.body).toBe(415);
    const rawLookingId = randomUUID();
    const rawLooking = await app.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${rawLookingId}`,
      headers: { ...headers('demo-instructor'), 'content-type': 'application/octet-stream' }, payload: 'QUJD' });
    expect(rawLooking.statusCode, rawLooking.body).toBe(200);
    expect(rawLooking.json().data.byteSize).toBe(4);
    expect(rawLooking.json().data.sha256).toBe(sha256(Buffer.from('QUJD')));
    // Les limites dédiées des autres routes restent effectives (rapports : 640 Kio).
    const reportsTooBig = await app.inject({ method: 'POST', url: `${path}/reports`,
      headers: { ...headers('demo-instructor'), 'content-type': 'application/json' }, payload: Buffer.alloc(700_000, 1) });
    expect(reportsTooBig.statusCode).toBe(413);
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
    expectProblem(foreignSchool, 403, 'ACCESS_DENIED');
    // Un identifiant déjà pris par un média invisible reste un 404 uniforme, jamais un conflit de clé.
    const generalId = await openGeneral('demo-bob');
    const collision = await upload('demo-bob', generalId, mediaId, bytes, deviceC);
    expectProblem(collision, 404, 'MEDIA_NOT_FOUND');
    expect((await mediaRow(mediaId)).state).toBe('ATTACHED');
  });

  it('ne confond pas une sous-chaîne du requestId avec un conflit ou une fuite de métadonnées', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(64);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const generalId = await openGeneral('demo-bob');
    // requestId imposé par la fixture : contient « 409 » comme l'identifiant réel observé en intégration I2.
    const forced = '40900000-0000-4000-8000-000000000409';
    const collision = await app.inject({ method: 'PUT',
      url: `${path}/conversations/${generalId}/media/${mediaId}`,
      headers: { ...headers('demo-bob', deviceC), 'content-type': 'application/octet-stream', 'x-test-request-id': forced },
      payload: bytes });
    expectProblem(collision, 404, 'MEDIA_NOT_FOUND');
    expect(collision.json().requestId).toBe(forced);
    // Un vrai conflit (409) reste refusé par le vérificateur d'un 404 MEDIA_NOT_FOUND.
    const conflict = await upload('demo-instructor', conversationId, mediaId, cipherBytes(64, 99));
    expect(conflict.statusCode, conflict.body).toBe(409);
    expect(() => expectProblem(conflict, 404, 'MEDIA_NOT_FOUND')).toThrow();
    // Un code erroné avec le bon statut est refusé.
    expect(() => expectProblem(problemResponse(404, 'NOT_FOUND'), 404, 'MEDIA_NOT_FOUND')).toThrow();
    // Des métadonnées média divulguées sont refusées même avec le bon statut et le bon code.
    expect(() => expectProblem(problemResponse(404, 'MEDIA_NOT_FOUND', { sha256: 'a'.repeat(64) }), 404, 'MEDIA_NOT_FOUND')).toThrow();
    expect(() => expectProblem(problemResponse(404, 'MEDIA_NOT_FOUND', { byteSize: 64 }), 404, 'MEDIA_NOT_FOUND')).toThrow();
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
    // Borne haute valide : le plafond exact s'attache de bout en bout.
    const upperBound = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, 4_194_304));
    expect(upperBound.statusCode, upperBound.body).toBe(200);
    expect(upperBound.json().data.media).toEqual({ mediaId, byteSize: 4_194_304, deleted: false });
    expect((await mediaRow(mediaId)).state).toBe('ATTACHED');
  });

  it('stays behind the existing messaging qualification gate without widening it', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const closed = await app.inject({ method: 'PUT',
      url: `/v1/schools/${id.schoolB}/messaging/conversations/${conversationId}/media/${mediaId}`,
      headers: { ...headers('demo-foreign', deviceForeign), 'content-type': 'application/octet-stream' }, payload: cipherBytes(8) });
    expect(closed.statusCode, closed.body).toBe(503);
    expect(closed.json().code).toBe('MESSAGING_NOT_ENABLED');
    // La porte précède la validation métier de l'appareil : école fermée + appareil invalide reste 503, pas 403.
    const closedInvalidDevice = await app.inject({ method: 'PUT',
      url: `/v1/schools/${id.schoolB}/messaging/conversations/${conversationId}/media/${mediaId}`,
      headers: { authorization: 'Bearer demo-foreign', 'x-drivy-expected-person-id': id.foreign,
        'x-drivy-expected-access-epoch': '1', 'x-drivy-device-id': 'bad', 'content-type': 'application/octet-stream' },
      payload: cipherBytes(8) });
    expect(closedInvalidDevice.statusCode, closedInvalidDevice.body).toBe(503);
    expect(closedInvalidDevice.json().code).toBe('MESSAGING_NOT_ENABLED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media')).rows[0]!.count).toBe(0);
  });

  it('keeps the historical four-part fingerprint so a pre-media message replays with the same receipt', async () => {
    const conversationId = await openPrivate();
    // Forme historique exacte : [enveloppe, mentions, réponse, sondage], sans cinquième élément.
    const historical = (envelopeValue: unknown, mentions: string[], reply: string | null, poll: unknown) =>
      createHash('sha256').update(JSON.stringify([envelopeValue, mentions, reply, poll])).digest('hex');
    const textIntent = randomUUID();
    const textBody = { clientMessageId: textIntent, expectedMembersEpoch: 0, ciphertext: envelope };
    const textFirst = await postMessage('demo-instructor', conversationId, textBody);
    expect(textFirst.statusCode, textFirst.body).toBe(200);
    const storedText = (await pool.query<{ fingerprint: string }>('SELECT fingerprint FROM drivy.messaging_message WHERE id=$1',
      [textFirst.json().data.id])).rows[0]!.fingerprint;
    expect(storedText).toBe(historical(envelope, [], null, null));
    // Message enregistré avant l'ajout des médias : même empreinte, même rejeu, même reçu, aucun doublon.
    await pool.query('UPDATE drivy.messaging_message SET fingerprint=$2 WHERE id=$1', [textFirst.json().data.id, historical(envelope, [], null, null)]);
    const textReplay = await postMessage('demo-instructor', conversationId, textBody);
    expect(textReplay.statusCode, textReplay.body).toBe(200);
    expect(textReplay.json().data.id).toBe(textFirst.json().data.id);
    expect(textReplay.json().data.sequence).toBe(textFirst.json().data.sequence);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(1);
    // Forme historique avec sondage : elle reste exactement celle d'avant le lot.
    const pollIntent = randomUUID();
    const pollBody = { clientMessageId: pollIntent, expectedMembersEpoch: 0, ciphertext: envelope, poll: { optionCount: 2, multiple: false } };
    const pollFirst = await postMessage('demo-instructor', conversationId, pollBody);
    expect(pollFirst.statusCode, pollFirst.body).toBe(200);
    expect((await pool.query<{ fingerprint: string }>('SELECT fingerprint FROM drivy.messaging_message WHERE id=$1',
      [pollFirst.json().data.id])).rows[0]!.fingerprint).toBe(historical(envelope, [], null, [2, false]));
    expect((await postMessage('demo-instructor', conversationId, pollBody)).json().data.id).toBe(pollFirst.json().data.id);
    // Un message média garde le couple média dans l'empreinte : changer l'identifiant ou la taille reste un conflit.
    const mediaId = randomUUID();
    const bytes = cipherBytes(96);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    const mediaIntentBody = mediaBody(mediaId, bytes.length);
    const mediaFirst = await postMessage('demo-instructor', conversationId, mediaIntentBody);
    expect(mediaFirst.statusCode, mediaFirst.body).toBe(200);
    expect((await pool.query<{ fingerprint: string }>('SELECT fingerprint FROM drivy.messaging_message WHERE id=$1',
      [mediaFirst.json().data.id])).rows[0]!.fingerprint)
      .toBe(createHash('sha256').update(JSON.stringify([envelope, [], null, null, [mediaId, bytes.length]])).digest('hex'));
    expect((await postMessage('demo-instructor', conversationId, mediaIntentBody)).json().data.id).toBe(mediaFirst.json().data.id);
    const changedMedia = await postMessage('demo-instructor', conversationId, { ...mediaIntentBody, media: { mediaId: randomUUID(), byteSize: bytes.length } });
    expect(changedMedia.statusCode, changedMedia.body).toBe(409);
    expect(changedMedia.json().code).toBe('INTENT_CONFLICT');
  });

  it('answers a uniform 404 for a cancel aimed at another conversation, in every media state', async () => {
    const conversationA = await openPrivate();
    const conversationB = await openGeneral('demo-instructor');
    const assertUntouched = async (mediaId: string, state: string, journalEntries: number, sequence: string) => {
      const row = await mediaRow(mediaId);
      expect(row.state).toBe(state);
      expect((await journal(mediaId)).length).toBe(journalEntries);
      expect((await pool.query<{ last_sequence: string }>('SELECT last_sequence FROM drivy.messaging_conversation WHERE id=$1',
        [conversationA])).rows[0]!.last_sequence).toBe(sequence);
    };
    // UPLOADED dans A, annulation via B : 404 uniforme, aucun effet.
    const uploadedId = randomUUID();
    const bytes = cipherBytes(80);
    expect((await upload('demo-instructor', conversationA, uploadedId, bytes)).statusCode).toBe(200);
    const wrongUploaded = await cancel('demo-instructor', conversationB, uploadedId);
    expect(wrongUploaded.statusCode, wrongUploaded.body).toBe(404);
    expect(wrongUploaded.json().code).toBe('MEDIA_NOT_FOUND');
    await assertUntouched(uploadedId, 'UPLOADED', 0, '0');
    // ATTACHED dans A, annulation via B : 404 uniforme, jamais 409 (aucun état révélé hors conversation).
    const attachedId = randomUUID();
    expect((await upload('demo-instructor', conversationA, attachedId, bytes)).statusCode).toBe(200);
    expect((await postMessage('demo-instructor', conversationA, mediaBody(attachedId, bytes.length))).statusCode).toBe(200);
    const sequenceAfterAttach = (await pool.query<{ last_sequence: string }>('SELECT last_sequence FROM drivy.messaging_conversation WHERE id=$1',
      [conversationA])).rows[0]!.last_sequence;
    const wrongAttached = await cancel('demo-instructor', conversationB, attachedId);
    expect(wrongAttached.statusCode, wrongAttached.body).toBe(404);
    expect(wrongAttached.json().code).toBe('MEDIA_NOT_FOUND');
    await assertUntouched(attachedId, 'ATTACHED', 0, sequenceAfterAttach);
    // PURGED dans A, annulation via B : 404 uniforme, pas 200 idempotent.
    const purgedId = randomUUID();
    expect((await upload('demo-instructor', conversationA, purgedId, bytes)).statusCode).toBe(200);
    expect((await cancel('demo-instructor', conversationA, purgedId)).statusCode).toBe(200);
    const wrongPurged = await cancel('demo-instructor', conversationB, purgedId);
    expect(wrongPurged.statusCode, wrongPurged.body).toBe(404);
    expect(wrongPurged.json().code).toBe('MEDIA_NOT_FOUND');
    await assertUntouched(purgedId, 'PURGED', 1, sequenceAfterAttach);
    // À la bonne URL, l'annulation reste idempotente et le tiers reste refusé uniformément.
    expect((await cancel('demo-instructor', conversationA, uploadedId)).statusCode).toBe(200);
    expect((await cancel('demo-instructor', conversationA, uploadedId)).statusCode).toBe(200);
    const thirdParty = await cancel('demo-alice', conversationA, attachedId, deviceB);
    expect(thirdParty.statusCode, thirdParty.body).toBe(404);
    expect(thirdParty.json().code).toBe('MEDIA_NOT_FOUND');
    expect((await mediaRow(attachedId)).state).toBe('ATTACHED');
  });

  it('valide les réponses réelles des routes média contre le contrat exécutable', async () => {
    const contract = JSON.parse(await readFile(new URL('../contracts/messaging-media.json', import.meta.url), 'utf8')) as { $id: string };
    const ajv = new Ajv2020({ strict: false, allErrors: true, formats: fullFormats });
    ajv.addSchema(contract);
    const check = (definition: string, value: unknown) => {
      const validate = ajv.getSchema(`${contract.$id}#/$defs/${definition}`);
      expect(validate, definition).toBeTypeOf('function');
      expect(validate!(value), `${definition}: ${JSON.stringify(validate!.errors)}`).toBe(true);
    };
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(320);
    const created = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(created.statusCode, created.body).toBe(200);
    check('MediaUploadEnvelope', created.json());
    expect(created.json().data.state).toBe('UPLOADED');
    check('MediaUploadEnvelope', (await upload('demo-instructor', conversationId, mediaId, bytes)).json());
    const conflict = await upload('demo-instructor', conversationId, mediaId, cipherBytes(320, 9));
    expect(conflict.statusCode).toBe(409);
    check('MediaError', conflict.json());
    const posted = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(posted.statusCode, posted.body).toBe(200);
    check('MediaMessage', posted.json().data.media);
    const afterAttach = await upload('demo-instructor', conversationId, mediaId, bytes);
    expect(afterAttach.statusCode).toBe(200);
    check('MediaUploadEnvelope', afterAttach.json());
    expect(afterAttach.json().data.state).toBe('ATTACHED');
    const attachedCancel = await cancel('demo-instructor', conversationId, mediaId);
    expect(attachedCancel.statusCode).toBe(409);
    check('MediaError', attachedCancel.json());
    const removableId = randomUUID();
    expect((await upload('demo-instructor', conversationId, removableId, bytes)).statusCode).toBe(200);
    const removed = await cancel('demo-instructor', conversationId, removableId);
    expect(removed.statusCode, removed.body).toBe(200);
    check('MediaCancelEnvelope', removed.json());
    // Le refus de transport fait partie des codes réellement émis et modélisés.
    const unsupported = await app.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${randomUUID()}`,
      headers: { ...headers('demo-instructor'), 'content-type': 'application/json' }, payload: '{}' });
    expect(unsupported.statusCode).toBe(415);
    check('MediaError', unsupported.json());
  });

  it('répond INVALID_MEDIA à une intention média invalide du POST message, sans changer les refus ordinaires', async () => {
    const conversationId = await openPrivate();
    for (const media of [{ mediaId: 'not-a-uuid', byteSize: 10 }, { mediaId: randomUUID(), byteSize: 4_194_305 },
      { mediaId: randomUUID(), byteSize: 1.5 }, { mediaId: randomUUID(), byteSize: 'x' }, { mediaId: 12, byteSize: 4 },
      { mediaId: randomUUID(), byteSize: 0 }, { mediaId: randomUUID(), byteSize: -1 }]) {
      const attempt = await postMessage('demo-instructor', conversationId,
        { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope, media });
      expect(attempt.statusCode, JSON.stringify(media)).toBe(400);
      expect(attempt.json().code).toBe('INVALID_MEDIA');
    }
    // Borne basse valide : un octet réel, attaché de bout en bout.
    const oneByteId = randomUUID();
    expect((await upload('demo-instructor', conversationId, oneByteId, Buffer.from([7]))).statusCode).toBe(200);
    const lowerBound = await postMessage('demo-instructor', conversationId, mediaBody(oneByteId, 1));
    expect(lowerBound.statusCode, lowerBound.body).toBe(200);
    expect(lowerBound.json().data.media).toEqual({ mediaId: oneByteId, byteSize: 1, deleted: false });
    const ordinary = await postMessage('demo-instructor', conversationId, { clientMessageId: 'not-a-uuid', ciphertext: envelope });
    expect(ordinary.statusCode).toBe(400);
    expect(ordinary.json().code).toBe('INVALID_REQUEST');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(1);
  });

  it('verrouille les sources de droits avant la conversation : une fin d’éligibilité concurrente refuse le dépôt', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const updater = await pool.connect();
    let pending: ReturnType<typeof upload> | undefined;
    try {
      const updaterPid = (await updater.query<{ pid: number }>('SELECT pg_backend_pid() AS pid')).rows[0]!.pid;
      await updater.query('BEGIN');
      await updater.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
      pending = upload('demo-instructor', conversationId, mediaId, cipherBytes(64));
      let blocked = false;
      for (let attempt = 0; attempt < 150; attempt++) {
        const observed = await pool.query<{ blocked: boolean }>(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity a
          WHERE a.datname=current_database() AND a.wait_event_type='Lock' AND a.query LIKE '%messaging_lock_rights%'
            AND $1::int=ANY(pg_blocking_pids(a.pid))) AS blocked`, [updaterPid]);
        if (observed.rows[0]?.blocked) { blocked = true; break; }
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      expect(blocked, 'le dépôt doit attendre le verrou des sources de droits avant la conversation').toBe(true);
      await updater.query('COMMIT');
      const response = await pending;
      expect(response.statusCode, response.body).toBe(403);
      expect(response.json().code).toBe('ACCESS_DENIED');
      expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_media WHERE id=$1', [mediaId])).rows[0]!.count).toBe(0);
    } finally {
      await updater.query('ROLLBACK');
      updater.release();
      if (pending) await pending.catch(() => undefined);
    }
  });

  it('refuse le message après une fin de lien entre dépôt et message, le média reste UPLOADED', async () => {
    const conversationId = await openPrivate();
    const mediaId = randomUUID();
    const bytes = cipherBytes(48);
    expect((await upload('demo-instructor', conversationId, mediaId, bytes)).statusCode).toBe(200);
    await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
    const refused = await postMessage('demo-instructor', conversationId, mediaBody(mediaId, bytes.length));
    expect(refused.statusCode, refused.body).toBe(403);
    expect(refused.json().code).toBe('ACCESS_DENIED');
    expect((await mediaRow(mediaId)).state).toBe('UPLOADED');
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0]!.count).toBe(0);
  });

  it('ne purge jamais les octets d’un média qu’une attache concurrente a verrouillé puis rattaché', async () => {
    const conversationId = await openPrivate();
    const posted = await postMessage('demo-instructor', conversationId, { clientMessageId: randomUUID(), expectedMembersEpoch: 0, ciphertext: envelope });
    expect(posted.statusCode, posted.body).toBe(200);
    const messageId = posted.json().data.id as string;
    const mediaId = randomUUID();
    expect((await upload('demo-instructor', conversationId, mediaId, cipherBytes(56))).statusCode).toBe(200);
    await pool.query(`UPDATE drivy.messaging_media SET created_at=now()-interval '3 days' WHERE id=$1`, [mediaId]);
    const holder = new Client({ connectionString: url });
    await holder.connect();
    const purger = new Client({ connectionString: url });
    await purger.connect();
    try {
      await holder.query('BEGIN');
      await holder.query('SET LOCAL ROLE drivy_app');
      await holder.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.instructor]);
      await holder.query('SELECT drivy.messaging_attach_media($1,$2,$3,$4,$5)', [id.schoolA, conversationId, mediaId, messageId, 56]);
      const holderPid = (await holder.query<{ pid: number }>('SELECT pg_backend_pid() AS pid')).rows[0]!.pid;
      await purger.query('BEGIN');
      const purge = purger.query<{ purged: number }>('SELECT drivy.messaging_purge_orphan_media(now()+interval \'1 day\') AS purged');
      let blocked = false;
      for (let attempt = 0; attempt < 150; attempt++) {
        const observed = await pool.query<{ blocked: boolean }>(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity a
          WHERE a.datname=current_database() AND a.wait_event_type='Lock' AND $1::int=ANY(pg_blocking_pids(a.pid))) AS blocked`, [holderPid]);
        if (observed.rows[0]?.blocked) { blocked = true; break; }
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      expect(blocked, 'la purge orpheline doit attendre le verrou de la ligne média').toBe(true);
      await holder.query('COMMIT');
      const purged = await purge;
      await purger.query('COMMIT');
      expect(purged.rows[0]!.purged).toBe(0);
      const row = await mediaRow(mediaId);
      expect(row.state).toBe('ATTACHED');
      expect(row.ciphertext).not.toBeNull();
      expect((await journal(mediaId)).length).toBe(0);
    } finally {
      await holder.query('ROLLBACK').catch(() => undefined);
      await holder.end();
      await purger.query('ROLLBACK').catch(() => undefined);
      await purger.end();
    }
  });

  it('ne laisse aucun identifiant, nom, clé ni octet déposé dans les vrais logs applicatifs', async () => {
    const lines: string[] = [];
    const logged = buildApp({
      pool, cursorSecret: 'messaging-media-logs-secret-32-chars!',
      messaging: { mode: 'qualification', schoolIds: [id.schoolA] },
      verifyToken: async authorization => {
        if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
        return { issuer, subject: authorization.slice(7) };
      },
      logger: { level: 'info', stream: { write: (line: string) => { lines.push(line); } } } as unknown as FastifyServerOptions['logger']
    });
    // Sentinelles synthétiques UNIQUES réellement soumises dans cette requête : octets, nom, clé, jeton d'authentification.
    const byteSentinel = `SENTINEL-BYTES-${randomUUID()}-DO-NOT-LOG`;
    const nameSentinel = `SENTINEL-NAME-${randomUUID()}.pdf`;
    const keySentinel = `SENTINEL-KEY-${randomUUID()}`;
    const tokenSentinel = `SENTINEL-TOKEN-${randomUUID()}`;
    const bytes = Buffer.concat([Buffer.from(byteSentinel, 'utf8'), cipherBytes(512)]);
    let conversationId = '';
    let mediaId = '';
    try {
      const opened = await logged.inject({ method: 'PUT', url: `${path}/private/${id.alice}`, headers: headers('demo-instructor') });
      expect(opened.statusCode, opened.body).toBe(200);
      conversationId = opened.json().data.conversationId as string;
      mediaId = randomUUID();
      const put = await logged.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${mediaId}`,
        headers: { ...headers('demo-instructor'), 'content-type': 'application/octet-stream' }, payload: bytes });
      expect(put.statusCode, put.body).toBe(200);
      // Les octets déposés contiennent bien la sentinelle (preuve qu'elle a réellement été soumise).
      expect((await mediaRow(mediaId)).ciphertext!.includes(Buffer.from(byteSentinel))).toBe(true);
      const conflict = await logged.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${mediaId}`,
        headers: { ...headers('demo-instructor'), 'content-type': 'application/octet-stream' }, payload: cipherBytes(512, 99) });
      expect(conflict.statusCode).toBe(409);
      // Nom et clé de test réellement envoyés, dans un corps refusé par le transport (415) : jamais journalisés.
      const namedBody = await logged.inject({ method: 'PUT', url: `${path}/conversations/${conversationId}/media/${randomUUID()}`,
        headers: { ...headers('demo-instructor'), 'content-type': 'application/json' },
        payload: JSON.stringify({ name: nameSentinel, key: keySentinel, caption: nameSentinel }) });
      expect(namedBody.statusCode).toBe(415);
      // Jeton d'authentification synthétique réellement envoyé : refus 401, jamais journalisé.
      const badToken = await logged.inject({ method: 'GET', url: `${path}/conversations/${conversationId}/media/${mediaId}`,
        headers: { ...headers('demo-instructor'), authorization: `Bearer ${tokenSentinel}` } });
      expect(badToken.statusCode).toBe(401);
      const missingDevice = await logged.inject({ method: 'GET', url: `${path}/conversations/${conversationId}/media/${mediaId}`,
        headers: headers('demo-instructor', null) });
      expect(missingDevice.statusCode).toBe(403);
    } finally { await logged.close(); }
    const text = lines.join('');
    // Les vrais logs applicatifs sont bien capturés (méthode, modèle de route, statut, code), pas un logger désactivé.
    expect(text).toContain('/v1/schools/:schoolId/messaging/conversations/:conversationId/media/:mediaId');
    expect(text).toContain('statusCode');
    expect(text).toContain('MEDIA_INTENT_CONFLICT');
    expect(text).toContain('UNSUPPORTED_MEDIA_TYPE');
    expect(text).toContain('AUTHENTICATION_REQUIRED');
    // Formes de fuite réalistes des octets et sentinelles réellement soumis : texte, base64, hex, tableau de nombres.
    const leakForms = [byteSentinel, nameSentinel, keySentinel, tokenSentinel,
      bytes.toString('base64'), bytes.toString('hex'), Buffer.from(byteSentinel).toString('base64'),
      Buffer.from(byteSentinel).toString('hex'), [...bytes.subarray(0, 16)].join(','), [...bytes.subarray(0, 8)].join(' ')];
    const leaks = (haystack: string) => leakForms.some(form => haystack.includes(form));
    // Auto-test du détecteur : il reconnaît les formes qu'une fuite réelle prendrait (aucune modification du logger produit).
    expect(leaks(JSON.stringify({ msg: byteSentinel, name: nameSentinel, buffer: { type: 'Buffer', data: [...bytes.subarray(0, 16)] },
      encoded: bytes.toString('base64') }))).toBe(true);
    expect(leaks(text), 'aucune sentinelle ni forme encodée des octets déposés ne doit apparaître dans les logs').toBe(false);
    for (const secret of [mediaId, conversationId, id.instructor, deviceA, sha256(bytes)])
      expect(text).not.toContain(secret);
  });
});
