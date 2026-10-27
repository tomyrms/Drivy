// #101 : alerte de mention réelle de bout en bout sur PostgreSQL synthétique (routes messagerie + worker push).
// Le transport est un collecteur local, jamais APNs. Ne jamais pointer vers une base de production.
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { processPushBatch, type PushSender } from '../src/course-push.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-mention.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const worker = new Pool({ connectionString: url, options: '-c role=drivy_harness_migrator' });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
registerMessaging(app, { pool, verifyToken: async authorization => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
}, mode: 'test-synthetic' });
const path = `/v1/schools/${id.schoolA}/messaging`;
const subjects: Record<string, string> = { 'demo-admin': id.admin, 'demo-alice': id.alice, 'demo-bob': id.bob };
const req = (subject: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', target: string, payload?: object) => app.inject({ method, url: target,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1' },
  ...(payload ? { payload } : {}) });
async function send(subject: string, conversationId: string, mentionPersonIds: string[]) {
  const members = await req(subject, 'GET', `${path}/conversations/${conversationId}/members`);
  const response = await req(subject, 'POST', `${path}/conversations/${conversationId}/messages`, { clientMessageId: randomUUID(),
    ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AAAA' }, expectedMembersEpoch: members.json().data.membersEpoch, mentionPersonIds });
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data as { id: string };
}
type Sent = { token: string; payload: Record<string, unknown> };
function collector(out: Sent[]): PushSender { return { async send(token, _env, payload) { out.push({ token, payload: payload as Record<string, unknown> }); return 'SENT'; }, close() {} }; }
const token = (person: string) => person.replace(/-/g, '').padEnd(64, 'a').slice(0, 64);
async function device(person: string) {
  await pool.query("INSERT INTO drivy.push_device(person_id,platform,environment,token) VALUES($1,'IOS','SANDBOX',$2)", [person, token(person)]);
}
const queued = () => pool.query<{ person_id: string; status: string; failure_code: string | null; title: string; body: string }>(
  "SELECT person_id,status,failure_code,title,body FROM drivy.push_notification WHERE category='MESSAGE_MENTION' ORDER BY person_id");

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await worker.end(); await pool.end(); });

describe('notification de mention (#101)', () => {
  it('alerte uniquement les mentionnés hors auteur, sans contenu ni nom, une seule fois', async () => {
    let conversationId = '';
    for (const subject of ['demo-admin', 'demo-alice', 'demo-bob'])
      conversationId = (await req(subject, 'PUT', `${path}/general`)).json().data.conversationId;
    for (const person of [id.admin, id.alice, id.bob]) await device(person);
    const message = await send('demo-admin', conversationId, [id.alice, id.admin]);
    await send('demo-admin', conversationId, []);
    expect((await queued()).rows.map(r => r.person_id)).toEqual([id.alice]);
    expect((await queued()).rows[0]).toMatchObject({ title: 'Quelqu’un vous a mentionné'.replace('’', "'"), body: '' });
    const out: Sent[] = [];
    await processPushBatch(worker, collector(out));
    expect(out).toHaveLength(1);
    expect(out[0]!.token).toBe(token(id.alice));
    expect(out[0]!.payload).toEqual({ aps: { alert: { title: "Quelqu'un vous a mentionné" }, sound: 'default',
      'thread-id': `messaging:${id.schoolA}:${conversationId}` }, kind: 'MESSAGING', schoolId: id.schoolA,
      conversationId, messageId: message.id, sequence: expect.any(Number), category: 'MESSAGE_MENTION' });
    expect(out[0]!.payload.sequence).toBeGreaterThan(0);
    await processPushBatch(worker, collector(out));
    expect(out).toHaveLength(1);
    expect((await queued()).rows[0]!.status).toBe('SENT');
  });

  it('revalide avant envoi : préférence, sourdine, retrait du général et message supprimé', async () => {
    let conversationId = '';
    for (const subject of ['demo-admin', 'demo-alice', 'demo-bob'])
      conversationId = (await req(subject, 'PUT', `${path}/general`)).json().data.conversationId;
    for (const person of [id.alice, id.bob]) await device(person);
    await send('demo-admin', conversationId, [id.alice, id.bob]);
    await pool.query('INSERT INTO drivy.notification_preference(person_id,messaging_mentions) VALUES($1,false)', [id.alice]);
    expect((await req('demo-admin', 'DELETE', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    const out: Sent[] = [];
    await processPushBatch(worker, collector(out));
    expect(out).toEqual([]);
    const rows = (await queued()).rows;
    expect(Object.fromEntries(rows.map(r => [r.person_id, r.failure_code]))).toEqual({ [id.alice]: 'PREFERENCE_DISABLED', [id.bob]: 'RECIPIENT_INELIGIBLE' });

    await pool.query('UPDATE drivy.notification_preference SET messaging_mentions=true WHERE person_id=$1', [id.alice]);
    await send('demo-admin', conversationId, [id.alice]);
    await pool.query(`INSERT INTO drivy.messaging_read_state(school_id,conversation_id,person_id,muted_until) VALUES($1,$2,$3,now()+interval '1 hour')
      ON CONFLICT(school_id,conversation_id,person_id) DO UPDATE SET muted_until=EXCLUDED.muted_until`, [id.schoolA, conversationId, id.alice]);
    await processPushBatch(worker, collector(out));
    expect(out).toEqual([]);
    expect((await queued()).rows.filter(r => r.person_id === id.alice).map(r => r.failure_code).sort()).toEqual(['PREFERENCE_DISABLED', 'SILENCED']);

    await pool.query('UPDATE drivy.messaging_read_state SET muted_until=NULL WHERE person_id=$1', [id.alice]);
    const deleted = await send('demo-admin', conversationId, [id.alice]);
    await pool.query('UPDATE drivy.messaging_message SET deleted_at=now(),envelope=NULL,deleted_by_person_id=sender_person_id WHERE id=$1', [deleted.id]);
    await processPushBatch(worker, collector(out));
    expect(out).toEqual([]);
  });
});
