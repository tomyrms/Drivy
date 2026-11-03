// #74 : regroupement anti-rafale des alertes de messagerie, de bout en bout sur PostgreSQL réelle (routes messagerie +
// worker push). Le transport est un collecteur local, jamais APNs. Ne jamais pointer vers une base de production.
// Les durées sont simulées en déplaçant `sent_at`/`available_at` en base : aucun sommeil long.
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerNotificationPreferences } from '../src/notification-preferences.js';
import { processPushBatch, type PushSender } from '../src/course-push.js';
import { MESSAGING_PUSH_QUIET_WINDOW_SECONDS } from '../src/messaging-notifications.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-push-coalescing.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const worker = new Pool({ connectionString: url, options: '-c role=drivy_harness_migrator' });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
const verifyToken = async (authorization: string | undefined) => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
};
registerMessaging(app, { pool, verifyToken, mode: 'test-synthetic' });
registerNotificationPreferences(app, { pool, verifyToken });
const path = `/v1/schools/${id.schoolA}/messaging`;
const subjects: Record<string, string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor, 'demo-alice': id.alice, 'demo-bob': id.bob };
const req = (subject: string, method: 'GET' | 'POST' | 'PUT' | 'DELETE', target: string, payload?: object, headers: Record<string, string> = {}) =>
  app.inject({ method, url: target, headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!,
    'x-drivy-expected-access-epoch': '1', ...headers }, ...(payload ? { payload } : {}) });
async function send(subject: string, conversationId: string, extra: object = {}) {
  const members = await req(subject, 'GET', `${path}/conversations/${conversationId}/members`);
  const response = await req(subject, 'POST', `${path}/conversations/${conversationId}/messages`, { clientMessageId: randomUUID(),
    ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AAAA' }, expectedMembersEpoch: members.json().data.membersEpoch, ...extra });
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data as { id: string; sequence: number };
}
async function openGeneral() {
  let conversationId = '';
  for (const subject of ['demo-admin', 'demo-alice', 'demo-bob'])
    conversationId = (await req(subject, 'PUT', `${path}/general`)).json().data.conversationId;
  return conversationId;
}
async function openPrivate() {
  const opened = await req('demo-instructor', 'PUT', `${path}/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
type Sent = { token: string; payload: Record<string, unknown> };
function collector(out: Sent[]): PushSender { return { async send(token, _env, payload) { out.push({ token, payload: payload as Record<string, unknown> }); return 'SENT'; }, close() {} }; }
const token = (person: string) => person.replace(/-/g, '').padEnd(64, 'a').slice(0, 64);
async function device(person: string) {
  await pool.query("INSERT INTO drivy.push_device(person_id,platform,environment,token) VALUES($1,'IOS','SANDBOX',$2)", [person, token(person)]);
}
async function setPreferences(person: string, values: { private?: boolean; general?: boolean; mentions?: boolean }) {
  await pool.query(`INSERT INTO drivy.notification_preference(person_id,messaging_private,messaging_general,messaging_mentions) VALUES($1,$2,$3,$4)
    ON CONFLICT(person_id) DO UPDATE SET messaging_private=$2,messaging_general=$3,messaging_mentions=$4`,
    [person, values.private ?? true, values.general ?? false, values.mentions ?? true]);
}
interface QueuedRow {
  id: string; person_id: string; category: string; status: string; failure_code: string | null; attempts: number;
  message_id: string; message_sequence: string; available_at: Date; sent_at: Date | null; valid_until: Date | null;
}
const queued = async () => (await pool.query<QueuedRow>(
  `SELECT id,person_id,category,status,failure_code,attempts,message_id,message_sequence,available_at,sent_at,valid_until
   FROM drivy.push_notification WHERE category LIKE 'MESSAGE_%' ORDER BY message_sequence,id`)).rows;
const run = async () => { const out: Sent[] = []; await processPushBatch(worker, collector(out)); return out; };
/** Simule l'écoulement de la fenêtre de calme sans attendre : l'envoi précédent vieillit, le report devient dû. */
async function elapseQuietWindow() {
  await pool.query("UPDATE drivy.push_notification SET sent_at=sent_at-make_interval(secs=>$1+1) WHERE status='SENT'", [MESSAGING_PUSH_QUIET_WINDOW_SECONDS]);
  await pool.query("UPDATE drivy.push_notification SET available_at=now()-interval '1 second' WHERE status='PENDING'");
}

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await worker.end(); await pool.end(); });

describe('regroupement anti-rafale des alertes de messagerie (#74)', () => {
  it('une rafale de cinq messages privés ne produit qu’une alerte, les autres sont regroupées', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    const messages: { id: string; sequence: number }[] = [];
    for (let index = 0; index < 5; index += 1) messages.push(await send('demo-instructor', conversationId));
    expect(await queued()).toHaveLength(5);

    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.token).toBe(token(id.alice));
    expect(out[0]!.payload).toMatchObject({ kind: 'MESSAGING', category: 'MESSAGING_PRIVATE', conversationId,
      messageId: messages[4]!.id, sequence: messages[4]!.sequence,
      aps: { alert: { title: 'Nouveau message' }, sound: 'default', 'thread-id': `messaging:${id.schoolA}:${conversationId}` } });

    const rows = await queued();
    expect(rows.filter(row => row.status === 'SENT').map(row => row.message_id)).toEqual([messages[4]!.id]);
    expect(rows.filter(row => row.failure_code === 'COALESCED')).toHaveLength(4);
    expect(rows.filter(row => row.failure_code === 'COALESCED').every(row => row.status === 'SKIPPED')).toBe(true);
    expect(await run()).toEqual([]);
  });

  it('une mention autorisée prime : mention et message du général ne font qu’une alerte de mention', async () => {
    const conversationId = await openGeneral();
    await device(id.alice);
    await setPreferences(id.alice, { general: true });
    const mention = await send('demo-admin', conversationId, { mentionPersonIds: [id.alice] });
    const general = await send('demo-admin', conversationId);
    expect((await queued()).map(row => row.category).sort()).toEqual(['MESSAGE_GENERAL', 'MESSAGE_MENTION']);

    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.payload).toMatchObject({ kind: 'MESSAGING', category: 'MESSAGING_MENTION', conversationId, messageId: mention.id });
    const rows = await queued();
    expect(rows.find(row => row.category === 'MESSAGE_MENTION')).toMatchObject({ status: 'SENT', failure_code: null });
    expect(rows.find(row => row.category === 'MESSAGE_GENERAL')).toMatchObject({ status: 'SKIPPED', failure_code: 'COALESCED', message_id: general.id });
  });

  it('deux conversations de la même personne restent deux alertes', async () => {
    const privateConversation = await openPrivate();
    const generalConversation = await openGeneral();
    await device(id.alice);
    await setPreferences(id.alice, { general: true });
    await send('demo-instructor', privateConversation);
    await send('demo-admin', generalConversation);

    const out = await run();
    expect(out).toHaveLength(2);
    expect(out.map(item => (item.payload as { conversationId: string }).conversationId).sort())
      .toEqual([privateConversation, generalConversation].sort());
    expect((await queued()).filter(row => row.status === 'SENT')).toHaveLength(2);
  });

  it('un message moins de 60 s après un envoi est reporté sans consommer de tentative, puis regroupé', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    expect(await run()).toHaveLength(1);
    const sentAt = (await queued()).find(row => row.status === 'SENT')!.sent_at!;

    const second = await send('demo-instructor', conversationId);
    const third = await send('demo-instructor', conversationId);
    expect(await run()).toEqual([]);

    const pending = (await queued()).filter(row => row.status === 'PENDING');
    expect(pending.map(row => row.message_id).sort()).toEqual([second.id, third.id].sort());
    for (const row of pending) {
      expect(row.attempts).toBe(0);
      expect(row.available_at.getTime()).toBe(sentAt.getTime() + MESSAGING_PUSH_QUIET_WINDOW_SECONDS * 1_000);
    }

    await elapseQuietWindow();
    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.payload).toMatchObject({ category: 'MESSAGING_PRIVATE', messageId: third.id });
    const rows = await queued();
    expect(rows.filter(row => row.status === 'SENT')).toHaveLength(2);
    expect(rows.filter(row => row.failure_code === 'COALESCED')).toHaveLength(1);
  });

  it('une alerte expirée pendant le report n’est jamais envoyée', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    expect(await run()).toHaveLength(1);
    await send('demo-instructor', conversationId);
    expect(await run()).toEqual([]);
    await pool.query("UPDATE drivy.push_notification SET valid_until=now()-interval '1 second' WHERE status='PENDING'");

    await elapseQuietWindow();
    expect(await run()).toEqual([]);
    expect((await queued()).filter(row => row.status === 'PENDING')).toEqual([]);
    expect((await queued()).filter(row => row.status === 'EXPIRED')).toHaveLength(1);
  });

  it('une préférence coupée pendant le report n’envoie rien', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    expect(await run()).toHaveLength(1);
    await send('demo-instructor', conversationId);
    await send('demo-instructor', conversationId);
    expect(await run()).toEqual([]);
    await setPreferences(id.alice, { private: false });

    await elapseQuietWindow();
    expect(await run()).toEqual([]);
    const rows = (await queued()).filter(row => row.status !== 'SENT');
    expect(rows).toHaveLength(2);
    expect(rows.every(row => row.status === 'SKIPPED' && row.failure_code === 'PREFERENCE_DISABLED')).toBe(true);
  });

  it('quand aucune alerte du groupe ne passe la revalidation, chacune garde son motif', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    for (let index = 0; index < 3; index += 1) await send('demo-instructor', conversationId);
    await pool.query(`INSERT INTO drivy.messaging_read_state(school_id,conversation_id,person_id,muted_until)
      VALUES($1,$2,$3,now()+interval '1 hour')`, [id.schoolA, conversationId, id.alice]);

    expect(await run()).toEqual([]);
    const rows = await queued();
    expect(rows).toHaveLength(3);
    expect(rows.every(row => row.status === 'SKIPPED' && row.failure_code === 'SILENCED')).toBe(true);
    expect(rows.some(row => row.failure_code === 'COALESCED')).toBe(false);
  });

  it('la charge reste générique et sans contenu', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    await send('demo-instructor', conversationId);
    const out = await run();
    expect(out).toHaveLength(1);
    const serialized = JSON.stringify(out[0]!.payload);
    for (const forbidden of ['Alice', 'Exemple', 'Moniteur', 'AAAA', 'ciphertext']) expect(serialized).not.toContain(forbidden);
    expect(Object.keys(out[0]!.payload).sort())
      .toEqual(['aps', 'category', 'conversationId', 'kind', 'messageId', 'schoolId', 'sequence']);
  });
});
