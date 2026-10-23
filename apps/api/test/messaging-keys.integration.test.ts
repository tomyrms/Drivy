// Écrit, NON exécuté (#84) : demande TEST_DATABASE_URL vers drivy_test et la migration 20261023b.
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { migrate } from '../scripts/migrations.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerMessagingKeys } from '../src/messaging-keys-routes.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
const verifyToken = async (authorization?: string) => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
};
registerMessaging(app, { pool, verifyToken, mode: 'test-synthetic' });
registerMessagingKeys(app, { pool, verifyToken, mode: 'test-synthetic' });
const base = `/v1/schools/${id.schoolA}/messaging`;
const crypto = `${base}/crypto`;
const subjects: Record<string, string> = { 'demo-instructor': id.instructor, 'demo-alice': id.alice, 'demo-other-instructor': id.otherInstructor };
const user = (person: string) => `@${person.toLowerCase()}:drivy`;
const req = (subject: string, device: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, payload?: object) => app.inject({ method, url: path,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1',
    'x-drivy-device-id': device }, ...(payload ? { payload } : {}) });
const deviceKeys = (person: string, device: string) => ({ user_id: user(person), device_id: device,
  algorithms: ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
  keys: { [`curve25519:${device}`]: `c${device}`, [`ed25519:${device}`]: `e${device}` }, signatures: {} });

beforeAll(async () => { await migrate(pool); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('relais de clés Matrix, PostgreSQL', () => {
  it('publie, interroge et distribue une clé à usage unique une seule fois, puis la clé de repli', async () => {
    const up = await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEV01'),
      one_time_keys: { 'signed_curve25519:AAAA': { key: 'k1' }, 'signed_curve25519:AAAB': { key: 'k2' } },
      fallback_keys: { 'signed_curve25519:FB01': { key: 'fb', fallback: true } } });
    expect(up.statusCode, up.body).toBe(200);
    expect(up.json().data.one_time_key_counts).toEqual({ signed_curve25519: 2 });
    expect(up.json().context.actorPersonId).toBe(id.alice);
    const query = await req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/query`, { device_keys: { [user(id.alice)]: [] } });
    expect(Object.keys(query.json().data.device_keys[user(id.alice)])).toEqual(['ALICEDEV01']);
    const claims = await Promise.all([0, 1, 2].map(() => req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/claim`,
      { one_time_keys: { [user(id.alice)]: { ALICEDEV01: 'signed_curve25519' } } })));
    const ids = claims.map(c => Object.keys(c.json().data.one_time_keys[user(id.alice)]?.ALICEDEV01 ?? {})[0]);
    expect(new Set(ids.filter(k => k !== 'signed_curve25519:FB01')).size).toBe(2);
    expect(ids.filter(k => k === 'signed_curve25519:FB01')).toHaveLength(1);
    const sync = await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`);
    expect(sync.json().data.device_one_time_keys_count).toEqual({});
    expect(sync.json().data.device_unused_fallback_key_types).toEqual([]);
  });
  it('refuse le remplacement des clés d’identité et les pairs non autorisés', async () => {
    await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEV01') });
    const swap = { ...deviceKeys(id.alice, 'ALICEDEV01'), keys: { 'ed25519:ALICEDEV01': 'autre' } };
    expect((await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: swap })).statusCode).toBe(409);
    const foreign = await req('demo-other-instructor', 'OTHERDEV01', 'POST', `${crypto}/keys/query`, { device_keys: { [user(id.alice)]: [] } });
    expect(foreign.json().data.device_keys).toEqual({});
    expect((await req('demo-alice', 'BAD', 'GET', `${crypto}/sync`)).statusCode).toBe(400);
  });
  it('file to-device par appareil, idempotente, acquittée par since', async () => {
    await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`);
    const body = { messages: { [user(id.alice)]: { '*': { algorithm: 'm.olm.v1.curve25519-aes-sha2', ciphertext: {} } } } };
    expect((await req('demo-instructor', 'INSTRDEV01', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/txn1`, body)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'INSTRDEV01', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/txn1`, body)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'INSTRDEV01', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/txn1`, { messages: {} })).statusCode).toBe(409);
    const first = (await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data;
    expect(first.to_device.events).toHaveLength(1);
    expect(first.to_device.events[0].sender).toBe(user(id.instructor));
    const again = (await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data;
    expect(again.to_device.events).toHaveLength(1);
    const acked = (await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync?since=${first.next_batch}`)).json().data;
    expect(acked.to_device.events).toHaveLength(0);
  });
  it('annonce changed puis left quand le lien scolaire se ferme', async () => {
    const start = (await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync`)).json().data.next_batch;
    await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEV01') });
    const changed = (await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync?since=${start}`)).json().data;
    expect(changed.device_lists.changed).toContain(user(id.alice));
    await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
    const left = (await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync?since=${changed.next_batch}`)).json().data;
    expect(left.device_lists.left).toEqual([user(id.alice)]);
    const send = { messages: { [user(id.alice)]: { '*': { ciphertext: {} } } } };
    await req('demo-instructor', 'INSTRDEV01', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/txn2`, send);
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data.to_device.events).toHaveLength(0);
  });
  it('sauvegarde chiffrée avec CAS sur la version', async () => {
    const auth = { algorithm: 'm.megolm_backup.v1.curve25519-aes-sha2', auth_data: { public_key: 'pk1' } };
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/room_keys/version`)).statusCode).toBe(404);
    const v1 = (await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/room_keys/version`, auth)).json().data.version;
    const room = `!${'0'.repeat(8)}-0000-0000-0000-${'0'.repeat(12)}:drivy`;
    const rooms = { rooms: { [room]: { sessions: { S1: { first_message_index: 0, forwarded_count: 0, is_verified: false,
      session_data: { ephemeral: 'e', ciphertext: 'c', mac: 'm' } } } } } };
    expect((await req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=${v1}`, rooms)).json().data.count).toBe(1);
    const v2 = (await req('demo-alice', 'ALICEDEV02', 'POST', `${crypto}/room_keys/version`, { ...auth, auth_data: { public_key: 'pk2' } })).json().data.version;
    const stale = await req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=${v1}`, rooms);
    expect(stale.statusCode).toBe(409);
    expect(stale.body).toContain('BACKUP_VERSION_CONFLICT');
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/room_keys/version`)).json().data).toMatchObject({ version: v2, auth_data: { public_key: 'pk2' } });
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/room_keys/keys?version=${v1}`)).json().data.rooms[room].sessions.S1).toBeDefined();
    expect((await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/room_keys/keys?version=${v1}`)).statusCode).toBe(404);
  });
  it('révoque un appareil : plus de clés publiées ni d’accès', async () => {
    await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEV01') });
    await req('demo-alice', 'ALICEDEV02', 'GET', `${crypto}/sync`);
    expect((await req('demo-alice', 'ALICEDEV02', 'DELETE', `${crypto}/devices/ALICEDEV01`)).json().data).toEqual({ deviceId: 'ALICEDEV01', revoked: true });
    expect((await req('demo-alice', 'ALICEDEV02', 'DELETE', `${crypto}/devices/ALICEDEV01`)).statusCode).toBe(200);
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).statusCode).toBe(403);
    const query = await req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/query`, { device_keys: { [user(id.alice)]: [] } });
    expect(query.json().data.device_keys[user(id.alice)]).toEqual({});
  });
});
