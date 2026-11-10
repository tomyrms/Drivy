// #440 : migration 20261110 appliquée sur une base synthétique peuplée au schéma antérieur (clés à usage unique non consommées).
// Patron de identity-migration : freshDatabase(skipMigrations), puis migrate() sous le propriétaire non privilégié du harnais.
import Fastify, { type FastifyInstance } from 'fastify';
import { createHash } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { migrate } from '../scripts/migrations.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerMessagingKeys } from '../src/messaging-keys-routes.js';
import { ApiError } from '../src/errors.js';

const issuer = 'https://messaging.test.invalid';
const subjects: Record<string, string> = { 'demo-instructor': id.instructor, 'demo-alice': id.alice };
const verifyToken = async (authorization?: string) => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
};
const crypto = `/v1/schools/${id.schoolA}/messaging/crypto`;
const content = (n: string) => ({ key: `synthetic-public-${n}` });
/** Empreinte attendue : SHA-256 du texte jsonb normalisé de PostgreSQL (`{"k": "v"}`), recalculé côté Node. */
const sha = (value: Record<string, string>) => createHash('sha256').update(`{${Object.entries(value).map(([k, v]) => `"${k}": "${v}"`).join(', ')}}`, 'utf8').digest('hex');
let pool: Pool, owner: Pool, service: Pool, app: FastifyInstance;
const before: Record<string, unknown> = {};

const req = (subject: string, device: string, method: 'GET' | 'POST', path: string, payload?: object) => app.inject({ method, url: path,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1', 'x-drivy-device-id': device },
  ...(payload ? { payload } : {}) });
const upload = (one_time_keys: Record<string, unknown>) => req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/keys/upload`, { one_time_keys });
const claim = () => req('demo-instructor', 'INSTRDEV01', 'POST', `${crypto}/keys/claim`,
  { one_time_keys: { [`@${id.alice.toLowerCase()}:drivy`]: { ALICEDEV01: 'signed_curve25519' } } });
const claimed = (response: { json: () => any }): { id: string; key: unknown }[] =>
  Object.values((Object.values(response.json().data.one_time_keys)[0] ?? {}) as Record<string, Record<string, unknown>>).flatMap(keys => Object.entries(keys).map(([keyId, key]) => ({ id: keyId, key })));
const rows = async () => (await pool.query<{ key_id: string; consumed: boolean; key: unknown; digest: string }>(
  `SELECT key_id,consumed_at IS NOT NULL AS consumed,key,encode(key_digest,'hex') AS digest FROM drivy.messaging_one_time_key
   WHERE person_id=$1 AND device_id='ALICEDEV01' ORDER BY key_id`, [id.alice])).rows;
const counts = async () => (await req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data.device_one_time_keys_count as Record<string, number>;

beforeAll(async () => {
  pool = await freshDatabase({ skipMigrations: /^20261110_messaging_otk_consumption_proof/ });
  await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer);
  // État antérieur : ni preuve de consommation, ni empreinte.
  expect((await pool.query("SELECT 1 FROM information_schema.columns WHERE table_schema='drivy' AND table_name='messaging_one_time_key' AND column_name IN('consumed_at','key_digest')")).rowCount).toBe(0);
  await pool.query(`INSERT INTO drivy.messaging_device(school_id,person_id,device_id,created_by_issuer,created_by_subject) VALUES($1,$2,'ALICEDEV01',$3,'demo-alice')`, [id.schoolA, id.alice, issuer]);
  for (const n of ['AAAA', 'AAAB'])
    await pool.query(`INSERT INTO drivy.messaging_one_time_key(school_id,person_id,device_id,key_id,key) VALUES($1,$2,'ALICEDEV01',$3,$4::jsonb)`, [id.schoolA, id.alice, `signed_curve25519:${n}`, JSON.stringify(content(n))]);
  for (const row of (await pool.query<{ key_id: string; key: unknown }>(`SELECT key_id,key FROM drivy.messaging_one_time_key WHERE person_id=$1 ORDER BY key_id`, [id.alice])).rows) before[row.key_id] = row.key;
  // Même propriétaire non privilégié que freshDatabase ; le registre déjà posé ne rejoue que la migration manquante.
  owner = new Pool({ connectionString: process.env.TEST_DATABASE_URL, options: '-c role=drivy_harness_migrator' });
  const applied = (await pool.query('SELECT count(*)::int n FROM public.drivy_migrations')).rows[0].n;
  await migrate(owner);
  expect((await pool.query('SELECT count(*)::int n FROM public.drivy_migrations')).rows[0].n).toBe(applied + 1);
  service = new Pool({ connectionString: process.env.TEST_DATABASE_URL, max: 8 });
  app = Fastify();
  app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
    .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
  registerMessaging(app, { pool: service, verifyToken, mode: 'test-synthetic' });
  registerMessagingKeys(app, { pool: service, verifyToken, mode: 'test-synthetic' });
  await req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync`);
});
afterAll(async () => { await app?.close(); await service?.end(); await owner?.end(); await pool?.end(); });

describe('#440 : migration sur des clés déjà présentes sous l’ancien schéma', () => {
  it('le rattrapage donne une empreinte à chaque clé présente et conserve son contenu, toutes disponibles', async () => {
    const found = await rows();
    expect(found.map(r => [r.key_id, r.consumed, r.key])).toEqual(Object.entries(before).map(([k, v]) => [k, false, v]));
    for (const row of found) expect(row.digest).toBe(sha(row.key as Record<string, string>));
    expect(await counts()).toEqual({ signed_curve25519: 2 });
  });
  it('rejeu identique après migration puis claim : aucune clé ressuscitée, consommation unique, ordre conservé', async () => {
    const batch = { 'signed_curve25519:AAAA': content('AAAA'), 'signed_curve25519:AAAB': content('AAAB') };
    const replay = await upload(batch);
    expect(replay.statusCode, replay.body).toBe(200); expect(replay.json().data.one_time_key_counts).toEqual({ signed_curve25519: 2 });
    const first = await claim();
    expect(claimed(first)).toEqual([{ id: 'signed_curve25519:AAAA', key: before['signed_curve25519:AAAA'] }]);
    const again = await upload(batch);
    expect(again.statusCode, again.body).toBe(200); expect(again.json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
    expect(claimed(await claim())).toEqual([{ id: 'signed_curve25519:AAAB', key: before['signed_curve25519:AAAB'] }]);
    expect(claimed(await claim())).toEqual([]);
    expect((await upload(batch)).json().data.one_time_key_counts).toEqual({});
    expect((await rows()).map(r => [r.key_id, r.consumed])).toEqual([['signed_curve25519:AAAA', true], ['signed_curve25519:AAAB', true]]);
  });
  it('contenu différent sous un identifiant migré, même consommé : 409 ; nouvelle clé distincte acceptée', async () => {
    const conflict = await upload({ 'signed_curve25519:AAAA': content('autre') });
    expect(conflict.statusCode).toBe(409); expect(conflict.json().code).toBe('ONE_TIME_KEY_CONFLICT');
    expect((await upload({ 'signed_curve25519:AAAC': content('AAAC') })).json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
    expect(claimed(await claim())).toEqual([{ id: 'signed_curve25519:AAAC', key: content('AAAC') }]);
  });
  it('limite documentée : un identifiant consommé AVANT la migration (ligne supprimée) n’a aucune preuve et se republie comme une clé neuve', async () => {
    expect((await rows()).map(r => r.key_id)).not.toContain('signed_curve25519:OLD1');
    expect((await upload({ 'signed_curve25519:OLD1': content('OLD1') })).json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
  });
});
