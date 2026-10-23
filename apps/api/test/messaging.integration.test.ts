import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { migrate } from '../scripts/migrations.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
registerMessaging(app, { pool, verifyToken: async authorization => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
}, mode: 'test-synthetic' });
const path = `/v1/schools/${id.schoolA}/messaging`;
const subjects: Record<string,string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor,
  'demo-alice': id.alice, 'demo-bob': id.bob, 'demo-other-instructor': id.otherInstructor,
  'demo-foreign': id.foreign };
const req = (subject: string, method: 'GET'|'POST'|'PUT', url: string, payload?: object, expectedPersonId?: string) => app.inject({ method, url,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': expectedPersonId ?? subjects[subject]!,
    'x-drivy-expected-access-epoch': '1' }, ...(payload ? { payload } : {}) });

beforeAll(async () => { await migrate(pool); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('messaging foundation PostgreSQL, synthetic envelopes only', () => {
  it('limits contacts to current assignment, not universal admin or other school', async () => {
    const instructor = await req('demo-instructor', 'GET', `${path}/contacts`);
    expect(instructor.statusCode, instructor.body).toBe(200);
    expect(instructor.json().data.contacts).toEqual([{ personId: id.alice, displayName: 'Alice Exemple' }]);
    expect((await req('demo-admin', 'GET', `${path}/contacts`)).json().data.contacts).toEqual([]);
    await pool.query(`INSERT INTO drivy.messaging_admin_contact(school_id,learner_person_id,admin_person_id,assigned_by_membership_id)
      VALUES($1,$2,$3,$4)`, [id.schoolA, id.alice, id.admin, id.adminMember]);
    expect((await req('demo-admin', 'GET', `${path}/contacts`)).json().data.contacts).toEqual([{ personId: id.alice, displayName: 'Alice Exemple' }]);
    await pool.query('UPDATE drivy.messaging_admin_contact SET revoked_at=now() WHERE school_id=$1 AND learner_person_id=$2', [id.schoolA,id.alice]);
    expect((await req('demo-admin', 'GET', `${path}/contacts`)).json().data.contacts).toEqual([]);
    expect((await req('demo-alice', 'GET', `${path}/contacts`)).json().data.contacts.map((r: { personId: string }) => r.personId)).toEqual([id.instructor]);
    await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
    expect((await req('demo-instructor', 'GET', `${path}/contacts`)).json().data.contacts).toEqual([]);
  });
  it('persists opaque envelopes, pages without duplicates and rejects conflicting retries and revoked access', async () => {
    const opened = await req('demo-instructor', 'PUT', `${path}/private/${id.alice}`);
    expect(opened.statusCode, opened.body).toBe(200);
    const conversationId = opened.json().data.conversationId as string;
    expect((await req('demo-alice', 'PUT', `${path}/private/${id.instructor}`)).json().data.conversationId).toBe(conversationId);
    const listed = (await req('demo-instructor', 'GET', `${path}/conversations`)).json().data.items[0];
    expect(listed).toMatchObject({ peerPersonId: id.alice, title: 'Alice Exemple' });
    const clientMessageId = randomUUID(), body = { clientMessageId, ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' } };
    const first = await req('demo-instructor', 'POST', `${path}/conversations/${conversationId}/messages`, body);
    expect(first.statusCode, first.body).toBe(200);
    const again = await req('demo-instructor', 'POST', `${path}/conversations/${conversationId}/messages`, body);
    expect(again.json().data.id).toBe(first.json().data.id);
    const conflict = await req('demo-instructor', 'POST', `${path}/conversations/${conversationId}/messages`,
      { clientMessageId, ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AQ==' } });
    expect(conflict.statusCode).toBe(409);
    const page = await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/messages?limit=1`);
    expect(page.json().data.items).toHaveLength(1);
    expect(JSON.stringify(page.json())).not.toContain('plaintext');
    expect((await req('demo-other-instructor', 'GET', `${path}/conversations/${conversationId}/messages`)).statusCode).toBe(404);
    await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
    expect((await req('demo-instructor', 'GET', `${path}/conversations/${conversationId}/messages`)).statusCode).toBe(404);
    expect((await req('demo-instructor', 'POST', `${path}/conversations/${conversationId}/messages`,
      { ...body, clientMessageId: randomUUID() })).statusCode).toBe(404);
  });
  it('keeps general school-scoped and does not grant learner-to-learner private chat', async () => {
    const general = await req('demo-admin', 'PUT', `${path}/general`);
    expect(general.statusCode, general.body).toBe(200);
    expect((await req('demo-alice', 'PUT', `${path}/general`)).json().data.conversationId).toBe(general.json().data.conversationId);
    expect((await req('demo-alice', 'PUT', `${path}/private/${id.bob}`)).statusCode).toBe(403);
    expect((await req('demo-foreign', 'GET', `${path}/conversations/${general.json().data.conversationId}/messages`)).statusCode).toBe(403);
    expect((await req('demo-admin', 'POST', `${path}/conversations/${general.json().data.conversationId}/messages`,
      { clientMessageId: randomUUID(), ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' } }, id.alice)).statusCode).toBe(403);
    await pool.query('UPDATE drivy.membership SET access_epoch=access_epoch+1 WHERE id=$1', [id.adminMember]);
    expect((await req('demo-admin', 'GET', `${path}/conversations`)).statusCode).toBe(403);
  });
  it('pages several messages, resumes in ascending order and persists own mute without false receipts', async () => {
    const opened = await req('demo-alice', 'PUT', `${path}/general`);
    const conversationId = opened.json().data.conversationId as string;
    for (let index = 0; index < 3; index++) {
      const posted = await req('demo-admin', 'POST', `${path}/conversations/${conversationId}/messages`,
        { clientMessageId: randomUUID(), ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' },
          mentionPersonIds: index === 0 ? [id.alice] : [] });
      expect(posted.statusCode, posted.body).toBe(200);
    }
    const page1 = (await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/messages?limit=2`)).json().data;
    expect(page1.items.map((item: { sequence: number }) => item.sequence)).toEqual([3, 2]);
    const page2 = (await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/messages?limit=2&cursor=${page1.nextCursor}`)).json().data;
    expect(page2.items.map((item: { sequence: number }) => item.sequence)).toEqual([1]);
    const pulled = (await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/events?afterSequence=1&limit=1`)).json().data;
    expect(pulled.messages.map((item: { sequence: number }) => item.sequence)).toEqual([2]);
    expect(pulled.nextAfterSequence).toBe(2); expect(pulled.hasMore).toBe(true);
    const mutedUntil = '2026-10-24T12:00:00.000Z';
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/read-state`,
      { lastReadSequence: 1, mutedUntil, expectedVersion: 0 })).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/read-state`,
      { lastReadSequence: 2 })).json().data.mutedUntil).toBe(mutedUntil);
    const own = (await req('demo-alice', 'GET', `${path}/conversations`)).json().data.items[0];
    expect(own).toMatchObject({ lastReadSequence: 2, unreadCount: 1, mutedUntil });
    expect(own.readStateVersion).toBe(1);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/read-state`,
      { lastReadSequence: 2, mutedUntil: null, expectedVersion: 0 })).statusCode).toBe(409);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/read-state`,
      { lastReadSequence: 2, mutedUntil: null, expectedVersion: 1 })).statusCode).toBe(200);
    expect((await req('demo-admin', 'GET', `${path}/conversations`)).json().data.items[0].mutedUntil).toBeNull();
  });
  it('keeps assignment direction for a learner who is also instructor', async () => {
    await pool.query("UPDATE drivy.membership SET roles=ARRAY['LEARNER','INSTRUCTOR'] WHERE id=$1", [id.instructorMember]);
    expect((await req('demo-instructor', 'PUT', `${path}/private/${id.alice}`)).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', `${path}/private/${id.instructor}`)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'PUT', `${path}/private/${id.alice.toUpperCase()}`)).statusCode).toBe(200);
  });
  it('rejects a stale epoch after a concurrent membership change commits', async () => {
    const conversationId = (await req('demo-admin', 'PUT', `${path}/general`)).json().data.conversationId as string;
    const updater = await pool.connect();
    try {
      await updater.query('BEGIN');
      await updater.query('UPDATE drivy.membership SET access_epoch=access_epoch+1 WHERE id=$1', [id.adminMember]);
      const pending = req('demo-admin', 'POST', `${path}/conversations/${conversationId}/messages`,
        { clientMessageId: randomUUID(), ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' } });
      await updater.query('COMMIT');
      const response = await pending;
      expect(response.statusCode).toBe(403);
      expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_message WHERE conversation_id=$1', [conversationId])).rows[0].count).toBe(0);
    } finally {
      await updater.query('ROLLBACK');
      updater.release();
    }
  });
  it('serializes two devices retrying one intent without a second sequence', async () => {
    const conversationId = (await req('demo-alice', 'PUT', `${path}/general`)).json().data.conversationId as string;
    const body = { clientMessageId: randomUUID(), ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AA==' } };
    const [a, b] = await Promise.all([
      req('demo-alice', 'POST', `${path}/conversations/${conversationId}/messages`, body),
      req('demo-alice', 'POST', `${path}/conversations/${conversationId}/messages`, body)
    ]);
    expect([a.statusCode, b.statusCode]).toEqual([200, 200]);
    expect(a.json().data.id).toBe(b.json().data.id);
    const rows = (await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/events`)).json().data.messages;
    expect(rows).toHaveLength(1);
    expect(rows[0].sequence).toBe(1);
  });
});
