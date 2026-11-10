// #436 (sauvegarde restaurable au-delà de 5000 sessions) et #440 (clé à usage unique jamais redistribuée), PostgreSQL synthétique réel.
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerMessagingKeys } from '../src/messaging-keys-routes.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging.test.invalid';
const subjects: Record<string, string> = { 'demo-instructor': id.instructor, 'demo-alice': id.alice, 'demo-other-instructor': id.otherInstructor };
const verifyToken = async (authorization?: string) => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
};
/** Un « service » = un pool + une application : en relancer un simule un redémarrage (aucun état en mémoire n'est partagé). */
function service() {
  const pool = new Pool({ connectionString: url, max: 12 }), app = Fastify();
  app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
    .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
  registerMessaging(app, { pool, verifyToken, mode: 'test-synthetic' });
  registerMessagingKeys(app, { pool, verifyToken, mode: 'test-synthetic' });
  const req = (subject: string, device: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, payload?: object) => app.inject({ method, url: path,
    headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1', 'x-drivy-device-id': device },
    ...(payload ? { payload } : {}) });
  return { pool, app, req, close: async () => { await app.close(); await pool.end(); } };
}
let current = service();
const crypto = `/v1/schools/${id.schoolA}/messaging/crypto`;
const key = (n: string) => ({ key: `synthetic-public-${n}` });
const upload = (one_time_keys: Record<string, unknown>, who = 'demo-alice', device = 'ALICEDEV01') =>
  current.req(who, device, 'POST', `${crypto}/keys/upload`, { one_time_keys });
const claim = (device = 'ALICEDEV01', who = 'demo-instructor', instructorDevice = 'INSTRDEV01', target = id.alice) =>
  current.req(who, instructorDevice, 'POST', `${crypto}/keys/claim`, { one_time_keys: { [`@${target.toLowerCase()}:drivy`]: { [device]: 'signed_curve25519' } } });
const claimed = (response: { json: () => any }): string[] =>
  Object.values((Object.values(response.json().data.one_time_keys)[0] ?? {}) as Record<string, Record<string, unknown>>).flatMap(keys => Object.keys(keys));
const rows = async () => (await current.pool.query<{ key_id: string; consumed: boolean }>(
  'SELECT key_id,consumed_at IS NOT NULL AS consumed FROM drivy.messaging_one_time_key WHERE person_id=$1 AND device_id=$2 ORDER BY key_id', [id.alice, 'ALICEDEV01'])).rows;
const counts = async () => (await current.req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/sync`)).json().data.device_one_time_keys_count as Record<string, number>;

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => {
  await current.pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(current.pool, issuer);
  await current.req('demo-instructor', 'INSTRDEV01', 'GET', `${crypto}/sync`);
});
afterAll(async () => { await current.close(); });

describe('#440 : une clé à usage unique distribuée ne revient jamais', () => {
  it('upload → claim → même upload (réponse perdue) → claim : la clé n’est pas ressuscitée, y compris après redémarrage', async () => {
    const batch = { 'signed_curve25519:AAAA': key('a'), 'signed_curve25519:AAAB': key('b') };
    expect((await upload(batch)).statusCode).toBe(200);
    const first = await claim(); expect(claimed(first)).toEqual(['signed_curve25519:AAAA']);
    // Rejeu identique du lot (la réponse d'origine avait été perdue) : 200, aucune clé disponible de plus.
    const replay = await upload(batch);
    expect(replay.statusCode, replay.body).toBe(200); expect(replay.json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
    expect(claimed(await claim())).toEqual(['signed_curve25519:AAAB']);
    expect(claimed(await claim())).toEqual([]);
    // Redémarrage du service (nouveau pool, nouvelle application) puis nouveau rejeu : toujours rien.
    await current.close(); current = service();
    expect((await upload(batch)).json().data.one_time_key_counts).toEqual({}); expect(claimed(await claim())).toEqual([]);
    expect(await rows()).toEqual([{ key_id: 'signed_curve25519:AAAA', consumed: true }, { key_id: 'signed_curve25519:AAAB', consumed: true }]);
    expect(await counts()).toEqual({});
  });
  it('le renvoi avant consommation reste idempotent : pas de doublon, compteurs exacts', async () => {
    const batch = { 'signed_curve25519:BBB1': key('1'), 'signed_curve25519:BBB2': key('2'), 'signed_curve25519:BBB3': key('3') };
    for (let i = 0; i < 3; i++) expect((await upload(batch)).json().data.one_time_key_counts).toEqual({ signed_curve25519: 3 });
    expect((await rows()).length).toBe(3); expect(await counts()).toEqual({ signed_curve25519: 3 });
    await claim();
    expect(await counts()).toEqual({ signed_curve25519: 2 });
  });
  it('un même identifiant avec un contenu différent est refusé explicitement, disponible ou consommé, sans ressusciter la clé', async () => {
    await upload({ 'signed_curve25519:CCC1': key('original') });
    const available = await upload({ 'signed_curve25519:CCC1': key('autre') });
    expect(available.statusCode).toBe(409); expect(available.json().code).toBe('ONE_TIME_KEY_CONFLICT');
    expect(claimed(await claim())).toEqual(['signed_curve25519:CCC1']);
    const consumed = await upload({ 'signed_curve25519:CCC1': key('autre') });
    expect(consumed.statusCode).toBe(409); expect(consumed.json().code).toBe('ONE_TIME_KEY_CONFLICT');
    const identical = await upload({ 'signed_curve25519:CCC1': key('original') });
    expect(identical.statusCode).toBe(200);
    expect(claimed(await claim())).toEqual([]); expect(await counts()).toEqual({});
  });
  it('les nouvelles clés distinctes restent acceptées après consommation', async () => {
    await upload({ 'signed_curve25519:DDD1': key('1') }); await claim();
    expect((await upload({ 'signed_curve25519:DDD1': key('1'), 'signed_curve25519:DDD2': key('2') })).json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
    expect(claimed(await claim())).toEqual(['signed_curve25519:DDD2']);
  });
  it('course : réuploads et réclamations parallèles ne distribuent chaque clé qu’une fois au total', async () => {
    const batch = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`signed_curve25519:E${String(i).padStart(3, '0')}`, key(String(i))]));
    await upload(batch);
    const results = await Promise.all([...Array.from({ length: 12 }, () => claim()), ...Array.from({ length: 6 }, () => upload(batch))]);
    for (const r of results) expect(r.statusCode, r.body).toBe(200);
    const distributed = results.slice(0, 12).flatMap(claimed);
    expect(new Set(distributed).size).toBe(distributed.length); expect(distributed.length).toBe(12);
    // Tout le reste est disponible une seule fois ; rejouer ne ressuscite rien.
    await upload(batch);
    const rest = [];
    for (;;) { const k = claimed(await claim()); if (!k.length) break; rest.push(...k); }
    expect(new Set([...distributed, ...rest]).size).toBe(20); expect(distributed.length + rest.length).toBe(20);
    expect((await rows()).length).toBe(20); expect(await counts()).toEqual({});
  });
  it('portée compte/appareil : un autre appareil, un autre compte et un non-pair ne partagent ni la consommation ni les clés', async () => {
    await upload({ 'signed_curve25519:FFF1': key('f') }); await claim();
    // Même identifiant, autre appareil de la même personne, et autre personne : indépendants.
    expect((await upload({ 'signed_curve25519:FFF1': key('f') }, 'demo-alice', 'ALICEDEV02')).json().data.one_time_key_counts).toEqual({ signed_curve25519: 1 });
    expect((await upload({ 'signed_curve25519:FFF1': key('autre-compte') }, 'demo-instructor', 'INSTRDEV01')).statusCode).toBe(200);
    expect(claimed(await claim('ALICEDEV02'))).toEqual(['signed_curve25519:FFF1']);
    // Un compte hors école n'obtient rien et ne consomme rien.
    await upload({ 'signed_curve25519:FFF2': key('g') });
    const outsider = await current.req('demo-other-instructor', 'OTHERDEV01', 'POST', `${crypto}/keys/claim`,
      { one_time_keys: { [`@${id.alice.toLowerCase()}:drivy`]: { ALICEDEV01: 'signed_curve25519' } } });
    expect(claimed(outsider)).toEqual([]);
    expect((await rows()).filter(r => !r.consumed).map(r => r.key_id)).toEqual(['signed_curve25519:FFF2']);
    // Le tombstone n'est ni lisible par un pair ni porteur de la clé publique.
    const db = await current.pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, id.instructor]);
      expect((await db.query('SELECT key_id FROM drivy.messaging_one_time_key WHERE person_id=$1', [id.alice])).rows.map(r => r.key_id)).toEqual(['signed_curve25519:FFF2']);
    } finally { await db.query('ROLLBACK'); db.release(); }
    expect((await current.pool.query("SELECT key FROM drivy.messaging_one_time_key WHERE key_id='signed_curve25519:FFF1' AND device_id='ALICEDEV01' AND person_id=$1", [id.alice])).rows[0].key).toBe('');
  });
  it('le plafond de 200 clés ne compte que les clés disponibles', async () => {
    // 200 publiées, 100 distribuées, 100 nouvelles : 200 disponibles (300 lignes au total) restent acceptées ; une de plus dépasse le plafond.
    for (let round = 0; round < 4; round++) {
      const size = round === 3 ? 1 : 100;
      const batch = Object.fromEntries(Array.from({ length: size }, (_, i) => [`signed_curve25519:R${round}${String(i).padStart(3, '0')}`, key(`${round}-${i}`)]));
      expect((await upload(batch)).statusCode, `tour ${round}`).toBe(round < 3 ? 200 : 400);
      if (round === 1) for (let i = 0; i < 100; i++) await claim();
    }
  });
});

describe('#436 : toute sauvegarde acceptée est restaurable, page par page', () => {
  const auth = { algorithm: 'm.megolm_backup.v1.curve25519-aes-sha2', auth_data: { public_key: 'pk' } };
  const room = (n: number) => `!${String(n).padStart(8, '0')}-0000-0000-0000-000000000000:drivy`;
  const session = (n: number) => `S${String(n).padStart(5, '0')}`;
  const data = (n: number) => ({ first_message_index: n, forwarded_count: 0, is_verified: false, session_data: { ephemeral: `e${n}`, ciphertext: `c${n}`, mac: `m${n}` } });
  const total = 5001;
  let version = '';
  /** Onze PUT de 500 sessions au plus, comme le client : le dernier porte le total à 5001. */
  async function fill(from: number, to: number) {
    for (let start = from; start < to; start += 500) {
      const rooms: Record<string, { sessions: Record<string, unknown> }> = {};
      for (let n = start; n < Math.min(start + 500, to); n++) (rooms[room(n % 7)] ??= { sessions: {} }).sessions[session(n)] = data(n);
      const put = await current.req('demo-alice', 'ALICEDEV01', 'PUT', `${crypto}/room_keys/keys?version=${version}`, { rooms });
      expect(put.statusCode, put.body).toBe(200);
    }
  }
  beforeEach(async () => {
    version = (await current.req('demo-alice', 'ALICEDEV01', 'POST', `${crypto}/room_keys/version`, auth)).json().data.version;
    await fill(0, total);
  });
  const read = (query: string, who = 'demo-alice', device = 'ALICEDEV02') => current.req(who, device, 'GET', `${crypto}/room_keys/keys?version=${version}${query}`);
  const flat = (rooms: Record<string, { sessions: Record<string, unknown> }>) => Object.entries(rooms).flatMap(([r, v]) => Object.entries(v.sessions).map(([s, d]) => [`${r}|${s}`, d] as const));
  async function readAll(limit: number, until = Infinity, start?: string) {
    const seen = new Map<string, unknown>(); let from = start, pages = 0, last: any;
    for (; pages < until; pages++) {
      const page = await read(`&limit=${limit}${from ? `&from=${encodeURIComponent(from)}` : ''}`);
      expect(page.statusCode, page.body).toBe(200); last = page.json().data;
      for (const [k, d] of flat(last.rooms)) { expect(seen.has(k), `doublon ${k}`).toBe(false); seen.set(k, d); }
      if (last.complete) { expect(last.next_from).toBeNull(); return { seen, pages: pages + 1, last, from: undefined }; }
      expect(last.next_from).toEqual(expect.any(String)); from = last.next_from;
    }
    return { seen, pages, last, from };
  }

  it('le total accepté vaut 5001 et la lecture historique non paginée refuse explicitement au lieu d’un 503 muet', async () => {
    expect((await current.req('demo-alice', 'ALICEDEV01', 'GET', `${crypto}/room_keys/version`)).json().data).toMatchObject({ count: total, etag: '11' });
    const legacy = await read('');
    expect(legacy.statusCode).toBe(422); expect(legacy.json().code).toBe('BACKUP_PAGINATION_REQUIRED');
  });
  it('restaure les 5001 sessions, identifiants et contenus exacts, sans omission ni doublon, complet seulement à la dernière page', async () => {
    const { seen, pages, last } = await readAll(500);
    expect(seen.size).toBe(total); expect(pages).toBe(11); expect(last).toMatchObject({ complete: true, next_from: null, count: total, etag: '11' });
    for (let n = 0; n < total; n++) expect(seen.get(`${room(n % 7)}|${session(n)}`), String(n)).toEqual(data(n));
    // Une page intermédiaire ne se dit jamais complète.
    const first = (await read('&limit=500')).json().data;
    expect(first).toMatchObject({ complete: false }); expect(first.next_from).toEqual(expect.any(String));
  });
  it('reprend après interruption (nouveau service, autre appareil) depuis le dernier curseur reçu', async () => {
    const partial = await readAll(300, 4);
    expect(partial.from).toEqual(expect.any(String)); expect(partial.seen.size).toBe(1200);
    await current.close(); current = service();
    const rest = await readAll(500, Infinity, partial.from);
    expect(rest.seen.size).toBe(total - 1200);
    const merged = new Set([...partial.seen.keys(), ...rest.seen.keys()]); expect(merged.size).toBe(total);
  });
  it('un changement de la sauvegarde pendant la lecture est signalé (409) ; redémarrer depuis le début récupère tout', async () => {
    const partial = await readAll(500, 2);
    await fill(total, total + 1);
    const stale = await read(`&limit=500&from=${encodeURIComponent(partial.from!)}`);
    expect(stale.statusCode, stale.body).toBe(409); expect(stale.json().code).toBe('BACKUP_CHANGED_DURING_READ');
    const again = await readAll(500);
    expect(again.seen.size).toBe(total + 1); expect(again.last.etag).toBe('12');
  });
  it('curseur et taille invalides, autre compte ou autre version : erreurs explicites, sans fuite', async () => {
    const first = (await read('&limit=10')).json().data.next_from as string;
    for (const bad of ['%%%', 'abc', Buffer.from('[1]').toString('base64url'), Buffer.from(JSON.stringify([1, id.schoolA, id.alice, 1, 11, 'x', 'y'])).toString('base64url')]) {
      const r = await read(`&limit=10&from=${encodeURIComponent(bad)}`);
      expect(r.statusCode, bad).toBe(400); expect(r.json().code).toBe('BACKUP_CURSOR_INVALID');
    }
    const decoded = JSON.parse(Buffer.from(first, 'base64url').toString('utf8'));
    const otherAccount = Buffer.from(JSON.stringify([decoded[0], decoded[1], id.instructor, ...decoded.slice(3)])).toString('base64url');
    const otherVersion = Buffer.from(JSON.stringify([decoded[0], decoded[1], decoded[2], 2, ...decoded.slice(4)])).toString('base64url');
    for (const bad of [otherAccount, otherVersion]) expect((await read(`&limit=10&from=${bad}`)).json().code).toBe('BACKUP_CURSOR_INVALID');
    for (const limit of ['0', '501', 'abc', '-1', '10.5']) { const r = await read(`&limit=${limit}`); expect(r.statusCode, limit).toBe(400); }
    // Un autre compte ne lit pas cette sauvegarde, avec ou sans curseur.
    expect((await read(`&limit=10&from=${first}`, 'demo-instructor', 'INSTRDEV01')).statusCode).toBe(404);
    // Le curseur ne contient ni contenu ni secret : seulement portée, version et position.
    expect(JSON.stringify(decoded)).not.toContain('ciphertext');
  });
  it('les petites sauvegardes restent compatibles : lecture historique inchangée et lecture paginée complète en une page', async () => {
    await current.pool.query('DELETE FROM drivy.messaging_key_backup_session WHERE person_id=$1 AND session_id > $2', [id.alice, session(2)]);
    const legacy = await read('');
    expect(legacy.statusCode, legacy.body).toBe(200); expect(Object.keys(legacy.json().data)).toEqual(['rooms']);
    expect(flat(legacy.json().data.rooms).length).toBe(3);
    expect((await read('&limit=500')).json().data).toMatchObject({ complete: true, next_from: null, count: 3 });
  });
  it('la taille d’une page est aussi bornée en octets : une grosse page est coupée, jamais tronquée en silence', async () => {
    const big = { first_message_index: 0, forwarded_count: 0, is_verified: false, session_data: { ephemeral: 'e', ciphertext: 'x'.repeat(7000), mac: 'm' } };
    await current.pool.query('DELETE FROM drivy.messaging_key_backup_session WHERE person_id=$1', [id.alice]);
    for (let n = 0; n < 400; n++) await current.pool.query(`INSERT INTO drivy.messaging_key_backup_session(school_id,person_id,version,room_id,session_id,data) VALUES($1,$2,$3,$4,$5,$6)`,
      [id.schoolA, id.alice, version, room(1), session(n), big]);
    const page = (await read('&limit=500')).json().data;
    expect(Object.keys(page.rooms[room(1)].sessions).length).toBeLessThan(400); expect(page.complete).toBe(false);
    const all = await readAll(500); expect(all.seen.size).toBe(400);
  });
});
