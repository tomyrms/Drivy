// PostgreSQL synthétique réel, migrations sous propriétaire non privilégié (#78/#84).
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { readFileSync } from 'node:fs';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerMessagingKeys } from '../src/messaging-keys-routes.js';
import { ApiError } from '../src/errors.js';
import { claimKeys } from '../src/messaging-keys.js';

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

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('relais de clés Matrix, PostgreSQL', () => {
  it('accepte les corps /keys/upload réellement produits par matrix-sdk-crypto (null compris, qa84)', async () => {
    // Corps générés par le SDK Rust (liaison wasm) pour alice/ALICEDEV01, mis à la forme exacte de la liaison FFI iOS 0.17 :
    // le 2e envoi porte "device_keys": null. Avant correctif : 400 INVALID_REQUEST et aucun appareil enregistré.
    const sdk = JSON.parse(readFileSync(new URL('./fixtures/matrix-keys-upload.json', import.meta.url), 'utf8'));
    const first = await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, sdk.first);
    expect(first.statusCode, first.body).toBe(200);
    expect(first.json().data.one_time_key_counts).toEqual({ signed_curve25519: 50 });
    const second = await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, sdk.second);
    expect(second.statusCode, second.body).toBe(200);
    expect(sdk.second.device_keys).toBeNull();
    const stored = await pool.query(`SELECT device_keys->>'user_id' AS user, device_keys->'signatures' ? $2 AS signed FROM drivy.messaging_device
      WHERE person_id=$1 AND device_id='ALICEDEV01'`, [id.alice, user(id.alice)]);
    expect(stored.rows).toEqual([{ user: user(id.alice), signed: true }]);
    expect((await pool.query('SELECT count(*)::int AS n FROM drivy.messaging_fallback_key WHERE person_id=$1', [id.alice])).rows[0].n).toBe(1);
    // null n'ouvre pas de contournement : identité d'un autre appareil toujours refusée, champ inconnu aussi.
    expect((await req('demo-alice', 'ALICEDEV02', 'POST', `${crypto}/keys/upload`, { ...sdk.first, one_time_keys: null, fallback_keys: null })).statusCode).toBe(400);
    expect((await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { ...sdk.second, extra: null })).statusCode).toBe(400);
  });
  it('refuse une réclamation directe hors périmètre et ne permet pas de modifier les clés du pair', async () => {
    const uploaded = await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, {
      one_time_keys: { 'signed_curve25519:AAAA': { key: 'synthetic-key' } }
    });
    expect(uploaded.statusCode, uploaded.body).toBe(200);
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.otherInstructor]);
      expect((await db.query("SELECT has_table_privilege(current_user,'drivy.messaging_one_time_key','UPDATE') AS allowed")).rows[0].allowed).toBe(false);
      expect((await db.query("SELECT * FROM drivy.messaging_claim_one_time_key($1,$2,'ALICEDEV01','signed_curve25519')", [id.schoolA, id.alice])).rows).toEqual([]);
      await db.query("SELECT set_config('app.person_id',$1,true)", [id.instructor]);
      expect((await db.query("SELECT * FROM drivy.messaging_claim_one_time_key($1,$2,'ALICEDEV01','signed_curve25519')", [id.schoolB, id.alice])).rows).toEqual([]);
    } finally { await db.query('ROLLBACK'); db.release(); }
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_one_time_key')).rows[0].count).toBe(1);
  });
  it('publie, interroge et distribue une clé à usage unique une seule fois, puis la clé de repli', async () => {
    const up = await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEV01'),
      one_time_keys: { 'signed_curve25519:AAAA': { key: 'k1' }, 'signed_curve25519:AAAB': { key: 'k2' } },
      fallback_keys: { 'signed_curve25519:FB01': { key: 'fb', fallback: true } } });
    expect(up.statusCode, up.body).toBe(200);
    expect(up.json().data.one_time_key_counts).toEqual({ signed_curve25519: 2 });
    expect(up.json().context.actorPersonId).toBe(id.alice);
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.instructor]);
      const claimed = await claimKeys(db, { schoolId: id.schoolA, personId: id.instructor, membershipId: id.instructorMember, deviceId: 'INSTRDEV01' },
        { one_time_keys: { [user(id.alice)]: { ALICEDEV01: 'signed_curve25519' } } });
      expect(Object.keys(claimed.one_time_keys[user(id.alice)]!.ALICEDEV01!)).toHaveLength(1);
    } finally { await db.query('ROLLBACK'); db.release(); }
    const query = await req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/query`, { device_keys: { [user(id.alice)]: [] } });
    expect(Object.keys(query.json().data.device_keys[user(id.alice)])).toEqual(['ALICEDEV01']);
    const claims = await Promise.all([0, 1, 2].map(() => req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/claim`,
      { one_time_keys: { [user(id.alice)]: { ALICEDEV01: 'signed_curve25519' } } })));
    for (const claim of claims) expect(claim.statusCode, claim.body).toBe(200);
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
  it('préserve K1 et ses sessions face à une seconde création, un autre appareil ou une réponse perdue', async () => {
    const auth = { algorithm: 'm.megolm_backup.v1.curve25519-aes-sha2', auth_data: { public_key: 'pk1' } };
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/room_keys/version`)).statusCode).toBe(404);
    const v1 = (await req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/room_keys/version`, auth)).json().data.version;
    const room = `!${'0'.repeat(8)}-0000-0000-0000-${'0'.repeat(12)}:drivy`;
    const rooms = { rooms: { [room]: { sessions: { S1: { first_message_index: 0, forwarded_count: 0, is_verified: false,
      session_data: { ephemeral: 'e', ciphertext: 'c', mac: 'm' } } } } } };
    expect((await req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=${v1}`, rooms)).json().data.count).toBe(1);
    for (const [device, data] of [['ALICEDEV02', { ...auth, auth_data: { public_key: 'pk2' } }], ['ALICEDEV01', auth]] as const) {
      const conflict = await req('demo-alice', device, 'POST', `${crypto}/room_keys/version`, data);
      expect(conflict.statusCode, conflict.body).toBe(409);
      expect(conflict.json().code).toBe('BACKUP_ALREADY_EXISTS');
    }
    const stale = await req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=999`, rooms);
    expect(stale.statusCode).toBe(409);
    expect(stale.body).toContain('BACKUP_VERSION_CONFLICT');
    expect((await req('demo-alice', 'ALICEDEV03', 'GET', `${crypto}/room_keys/version`)).json().data).toMatchObject({ version: v1, auth_data: { public_key: 'pk1' }, count: 1 });
    expect((await req('demo-alice', 'ALICEDEV03', 'GET', `${crypto}/room_keys/keys?version=${v1}`)).json().data.rooms).toEqual(rooms.rooms);
    expect((await req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=${v1}`, rooms)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/room_keys/keys?version=${v1}`)).statusCode).toBe(404);
  });
  it('ne crée qu’une sauvegarde courante lors de créations concurrentes sur deux appareils', async () => {
    const responses = await Promise.all(['ALICEDEV01', 'ALICEDEV02'].map((device, index) => req('demo-alice', device, 'POST', `${crypto}/room_keys/version`,
      { algorithm: 'm.megolm_backup.v1.curve25519-aes-sha2', auth_data: { public_key: `synthetic-pk${index}` } })));
    expect(responses.map(response => response.statusCode).sort()).toEqual([200, 409]);
    const winner = responses.findIndex(response => response.statusCode === 200);
    const current = await req('demo-alice', 'ALICEDEV03', 'GET', `${crypto}/room_keys/version`);
    expect(current.json().data).toMatchObject({ version: '1', auth_data: { public_key: `synthetic-pk${winner}` } });
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_key_backup WHERE school_id=$1 AND person_id=$2', [id.schoolA, id.alice])).rows[0].count).toBe(1);
  });
  it('plafonne les appareils actifs, lie l’appareil à la session, protège repli et suivi d’autrui', async () => {
    for (let i = 0; i < 10; i++) expect((await req('demo-alice', `ALICEDEV${String(i).padStart(2, '0')}`, 'GET', `${crypto}/sync`)).statusCode).toBe(200);
    const over = await req('demo-alice', 'ALICEDEV10', 'GET', `${crypto}/sync`);
    expect(over.statusCode).toBe(409);
    expect(over.body).toContain('DEVICE_LIMIT_REACHED');
    expect((await req('demo-alice', 'ALICEDEV00', 'DELETE', `${crypto}/devices/ALICEDEV09`)).statusCode).toBe(200);
    expect((await req('demo-alice', 'ALICEDEV10', 'GET', `${crypto}/sync`)).statusCode).toBe(200);
    const bound = await pool.query('SELECT created_by_issuer,created_by_subject FROM drivy.messaging_device WHERE device_id=$1', ['ALICEDEV10']);
    expect(bound.rows[0]).toEqual({ created_by_issuer: issuer, created_by_subject: 'demo-alice' });
    await req('demo-alice', 'ALICEDEV00', 'POST', `${crypto}/keys/upload`, { fallback_keys: { 'signed_curve25519:FB01': { key: 'fb' } } });
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.instructor]);
      const tampered = await db.query(`UPDATE drivy.messaging_fallback_key SET key='{"key":"evil"}'::jsonb,key_id='signed_curve25519:EVIL'
        WHERE person_id=$1`, [id.alice]);
      expect(tampered.rowCount).toBe(0);
      expect((await db.query('SELECT 1 FROM drivy.messaging_device_tracking WHERE person_id=$1', [id.alice])).rowCount).toBe(0);
      await expect(db.query("INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject) VALUES($1,$2,'INSTRDEV99','x','y')",
        [id.schoolA, id.instructor])).rejects.toMatchObject({ code: '42501' });
    } finally { await db.query('ROLLBACK'); db.release(); }
  });
  it('sendToDevice concurrent sur le même txnId : réponses idempotentes, un seul envoi', async () => {
    await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`);
    await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync`);
    const body = { messages: { [user(id.alice)]: { ALICEDEV01: { ciphertext: {} } } } };
    const results = await Promise.all([0, 1, 2, 3].map(() => req('demo-instructor', 'INSTRDEV01', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/race1`, body)));
    expect(results.map(r => r.statusCode)).toEqual([200, 200, 200, 200]);
    expect((await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data.to_device.events).toHaveLength(1);
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
