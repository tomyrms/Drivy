import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool, type PoolClient } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { ApiError } from '../src/errors.js';
import { conversationMembers } from '../src/messaging.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-epoch.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
registerMessaging(app, { pool, verifyToken: async () => ({ issuer, subject: 'demo-admin' }), mode: 'test-synthetic' });
const base = `/v1/schools/${id.schoolA}/messaging`;
const req = (method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, payload?: object) => app.inject({ method, url: base + path,
  headers: { authorization: 'Bearer synthetic-admin', 'x-drivy-expected-person-id': id.admin, 'x-drivy-expected-access-epoch': '1' },
  ...(payload ? { payload } : {}) });
const envelope = { scheme: 'synthetic', keyId: 'epoch-fixture', payload: 'AAAA' };
async function general() {
  const opened = await req('PUT', '/general');
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
async function epoch(conversation: string) {
  const response = await req('GET', `/conversations/${conversation}/members`);
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data.membersEpoch as number;
}
async function removeBob() {
  const removed = await req('DELETE', `/general/members/${id.bob}`);
  expect(removed.statusCode, removed.body).toBe(200);
}
async function counts(conversation: string) {
  return (await pool.query(`SELECT last_sequence::int AS sequence,
    (SELECT count(*)::int FROM drivy.messaging_message WHERE conversation_id=$1) AS messages,
    (SELECT count(*)::int FROM drivy.messaging_poll WHERE conversation_id=$1) AS polls
    FROM drivy.messaging_conversation WHERE id=$1`, [conversation])).rows[0];
}
beforeAll(async () => { const db = await freshDatabase(); await db.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('époque liée au ciphertext, intentions et reprises', () => {
  it('ne mélange jamais ancienne liste de membres et nouvelle époque entre deux lectures', async () => {
    const conversation = await general();
    const before = await epoch(conversation);
    const db = await pool.connect();
    let removed = false;
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true),set_config('app.membership_id',$3,true)",
        [id.schoolA, id.admin, id.adminMember]);
      // Aucun résultat SQL fabriqué : intercaler un vrai retrait après le snapshot de membres.
      const interleaved = { query: async (text: string, values?: unknown[]) => {
        const result = await db.query(text, values);
        if (!removed && text.includes('FROM drivy.messaging_conversation_members')) {
          removed = true;
          await removeBob();
        }
        return result;
      } } as unknown as PoolClient;
      const snapshot = await conversationMembers(interleaved,
        { schoolId: id.schoolA, personId: id.admin, membershipId: id.adminMember }, conversation);
      expect(removed, 'le retrait réel doit être intercalé après la lecture des membres').toBe(true);
      expect(snapshot.members.map(member => member.personId)).toContain(id.bob);
      expect(snapshot.membersEpoch).toBe(before);
      await db.query('COMMIT');
      const send = await req('POST', `/conversations/${conversation}/messages`,
        { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch: snapshot.membersEpoch });
      expect(send.statusCode, send.body).toBe(409);
      expect(send.json().code).toBe('MESSAGING_MEMBERS_CHANGED');
    } finally { await db.query('ROLLBACK'); db.release(); }
  });

  it('refuse une intention nouvelle sans époque sans consommer de séquence', async () => {
    const conversation = await general();
    const result = await req('POST', `/conversations/${conversation}/messages`, { clientMessageId: randomUUID(), ciphertext: envelope });
    expect(result.statusCode, result.body).toBe(409);
    expect(result.json().code).toBe('MESSAGING_MEMBERS_CHANGED');
    expect(await counts(conversation)).toEqual({ sequence: 0, messages: 0, polls: 0 });
  });

  it('refuse une enveloppe préparée avant retrait sans écrire message ni sondage', async () => {
    const conversation = await general();
    const expectedMembersEpoch = await epoch(conversation);
    const pending = { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch,
      poll: { optionCount: 2, multiple: false } };
    await removeBob();
    expect(await epoch(conversation)).toBeGreaterThan(expectedMembersEpoch);
    for (let attempt = 0; attempt < 2; attempt++) {
      const result = await req('POST', `/conversations/${conversation}/messages`, pending);
      expect(result.statusCode, result.body).toBe(409);
      expect(result.json().code).toBe('MESSAGING_MEMBERS_CHANGED');
    }
    expect(await counts(conversation)).toEqual({ sequence: 0, messages: 0, polls: 0 });
  });

  it('rejoue un envoi déjà accepté après retrait, même pour une archive sans époque', async () => {
    const conversation = await general();
    const expectedMembersEpoch = await epoch(conversation);
    const pending = { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch };
    const first = await req('POST', `/conversations/${conversation}/messages`, pending);
    expect(first.statusCode, first.body).toBe(200);
    await removeBob();
    expect(await epoch(conversation)).toBeGreaterThan(expectedMembersEpoch);
    const retry = await req('POST', `/conversations/${conversation}/messages`, pending);
    expect(retry.statusCode, retry.body).toBe(200);
    expect(retry.json().data).toEqual(first.json().data);
    const legacyRetry = await req('POST', `/conversations/${conversation}/messages`,
      { clientMessageId: pending.clientMessageId, ciphertext: envelope });
    expect(legacyRetry.statusCode, legacyRetry.body).toBe(200);
    expect(legacyRetry.json().data).toEqual(first.json().data);
    expect(await counts(conversation)).toEqual({ sequence: 1, messages: 1, polls: 0 });
  });

  it('ne transforme pas un autre contenu en reprise idempotente après changement de membres', async () => {
    const conversation = await general();
    const pending = { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch: await epoch(conversation) };
    expect((await req('POST', `/conversations/${conversation}/messages`, pending)).statusCode).toBe(200);
    await removeBob();
    const conflict = await req('POST', `/conversations/${conversation}/messages`,
      { ...pending, ciphertext: { ...envelope, payload: 'BBBB' } });
    expect(conflict.statusCode, conflict.body).toBe(409);
    expect(conflict.json().code).toBe('INTENT_CONFLICT');
    expect(await counts(conversation)).toEqual({ sequence: 1, messages: 1, polls: 0 });
  });

  it('accepte une nouvelle intention avec époque actuelle après retrait et réintégration', async () => {
    const conversation = await general();
    const oldEpoch = await epoch(conversation);
    await removeBob();
    expect((await req('PUT', `/general/members/${id.bob}`)).statusCode).toBe(200);
    const currentEpoch = await epoch(conversation);
    expect(currentEpoch).toBeGreaterThan(oldEpoch);
    const stale = await req('POST', `/conversations/${conversation}/messages`,
      { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch: oldEpoch });
    expect(stale.statusCode).toBe(409);
    const current = await req('POST', `/conversations/${conversation}/messages`,
      { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch: currentEpoch });
    expect(current.statusCode, current.body).toBe(200);
    expect(current.json().data.sequence).toBe(1);
  });

  it('refuse les époques invalides sans conversion ni valeur implicite', async () => {
    const conversation = await general();
    for (const expectedMembersEpoch of [-1, 0.5, '0', null, Number.MAX_SAFE_INTEGER + 1]) {
      const response = await req('POST', `/conversations/${conversation}/messages`,
        { clientMessageId: randomUUID(), ciphertext: envelope, expectedMembersEpoch });
      expect(response.statusCode, response.body).toBe(400);
    }
    expect(await counts(conversation)).toEqual({ sequence: 0, messages: 0, polls: 0 });
  });
});
