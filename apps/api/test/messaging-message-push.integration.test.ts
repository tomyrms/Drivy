// #74 : alertes des nouveaux messages privés et du général, et préférences de messagerie, de bout en bout sur PostgreSQL synthétique
// (routes messagerie + préférences + worker push). Le transport est un collecteur local, jamais APNs.
// Ne jamais pointer vers une base de production.
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerNotificationPreferences } from '../src/notification-preferences.js';
import { processPushBatch, type PushSender } from '../src/course-push.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-message-push.test.invalid';
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
const queued = (category?: string) => pool.query<{ person_id: string; category: string; status: string; failure_code: string | null; title: string; body: string;
  valid_until: Date | null; message_id: string }>(
  `SELECT person_id,category,status,failure_code,title,body,valid_until,message_id FROM drivy.push_notification
   WHERE category LIKE 'MESSAGE_%' AND ($1::text IS NULL OR category=$1) ORDER BY category,person_id,created_at`, [category ?? null]);
const run = async () => { const out: Sent[] = []; await processPushBatch(worker, collector(out)); return out; };

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await worker.end(); await pool.end(); });

describe('alerte de message privé (#74)', () => {
  it('prévient le destinataire, jamais l’auteur, avec une charge générique et une seule fois', async () => {
    const conversationId = await openPrivate();
    for (const person of [id.instructor, id.alice]) await device(person);
    const message = await send('demo-instructor', conversationId);
    const rows = (await queued()).rows;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ person_id: id.alice, category: 'MESSAGE_PRIVATE', status: 'PENDING', title: 'Nouveau message', body: '', message_id: message.id });
    const lifetime = rows[0]!.valid_until!.getTime() - Date.now();
    expect(lifetime).toBeGreaterThan(5 * 60_000);
    expect(lifetime).toBeLessThanOrEqual(15 * 60_000);

    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.token).toBe(token(id.alice));
    expect(out[0]!.payload).toEqual({ aps: { alert: { title: 'Nouveau message' }, sound: 'default', 'thread-id': `messaging:${id.schoolA}:${conversationId}` },
      kind: 'MESSAGING', category: 'MESSAGING_PRIVATE', schoolId: id.schoolA, conversationId, messageId: message.id, sequence: message.sequence });
    const serialized = JSON.stringify(out[0]!.payload);
    for (const forbidden of ['Alex', 'Moniteur', 'Alice', 'Exemple', 'AAAA', 'ciphertext']) expect(serialized).not.toContain(forbidden);
    expect(await run()).toEqual([]);
    expect((await queued()).rows[0]!.status).toBe('SENT');
  });

  it('ne met rien en file sans appareil enregistré ni lorsque la catégorie est refusée', async () => {
    const conversationId = await openPrivate();
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toEqual([]);
    await device(id.alice);
    await setPreferences(id.alice, { private: false });
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toEqual([]);
    await setPreferences(id.alice, { private: true });
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toHaveLength(1);
  });

  it.each([
    ['préférence refusée avant l’envoi', 'PREFERENCE_DISABLED', async () => setPreferences(id.alice, { private: false })],
    ['conversation en sourdine', 'SILENCED', async (conversationId: string) => { await pool.query(
      `INSERT INTO drivy.messaging_read_state(school_id,conversation_id,person_id,muted_until) VALUES($1,$2,$3,now()+interval '1 hour')`, [id.schoolA, conversationId, id.alice]); }],
    ['attribution terminée', 'RECIPIENT_INELIGIBLE', async () => { await pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]); }],
    ['message déjà lu ailleurs', 'EVENT_OBSOLETE', async (conversationId: string) => { await pool.query(
      `INSERT INTO drivy.messaging_read_state(school_id,conversation_id,person_id,last_read_sequence) VALUES($1,$2,$3,1)`, [id.schoolA, conversationId, id.alice]); }],
    ['message supprimé pour tout le monde', 'EVENT_OBSOLETE', async () => { await pool.query(
      'UPDATE drivy.messaging_message SET deleted_at=now(),envelope=NULL,deleted_by_person_id=sender_person_id'); }],
    ['appareil retiré', 'NO_DEVICE', async () => { await pool.query('UPDATE drivy.push_device SET revoked_at=now() WHERE person_id=$1', [id.alice]); }],
    ['compte désactivé dans l’école', 'RECIPIENT_INELIGIBLE', async () => { await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE person_id=$1", [id.alice]); }]
  ])('relit juste avant l’envoi : %s', async (_label, code, change) => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toHaveLength(1);
    await change(conversationId);
    expect(await run()).toEqual([]);
    expect((await queued()).rows[0]).toMatchObject({ status: 'SKIPPED', failure_code: code });
  });

  it('périme une alerte trop ancienne au lieu de la rejouer après une reprise du service', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    await pool.query("UPDATE drivy.push_notification SET valid_until=now()-interval '1 second' WHERE category='MESSAGE_PRIVATE'");
    expect(await run()).toEqual([]);
    expect((await queued()).rows[0]!.status).toBe('EXPIRED');
  });
});

describe('alerte du général, mentions et sondages (#74)', () => {
  it('ne prévient personne par défaut pour le général, puis seulement ceux qui l’ont activé', async () => {
    const conversationId = await openGeneral();
    for (const person of [id.admin, id.alice, id.bob]) await device(person);
    await send('demo-admin', conversationId);
    expect((await queued()).rows).toEqual([]);
    await setPreferences(id.bob, { general: true });
    const message = await send('demo-admin', conversationId);
    const rows = (await queued()).rows;
    expect(rows.map(row => [row.person_id, row.category])).toEqual([[id.bob, 'MESSAGE_GENERAL']]);
    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.payload).toMatchObject({ kind: 'MESSAGING', category: 'MESSAGING_GENERAL', conversationId, messageId: message.id,
      aps: { alert: { title: 'Nouveau message' } } });
    expect(JSON.stringify(out[0]!.payload)).not.toContain('Camille');
  });

  it('une mention n’ajoute pas d’alerte du général et une mention refusée ne retombe pas sur le général', async () => {
    const conversationId = await openGeneral();
    for (const person of [id.alice, id.bob]) await device(person);
    await setPreferences(id.alice, { general: true });
    await setPreferences(id.bob, { general: true, mentions: false });
    await send('demo-admin', conversationId, { mentionPersonIds: [id.alice, id.bob] });
    const rows = (await queued()).rows;
    expect(rows.map(row => [row.person_id, row.category]).sort()).toEqual([[id.alice, 'MESSAGE_MENTION'], [id.bob, 'MESSAGE_MENTION']].sort());
    const out = await run();
    expect(out.map(item => [item.token, (item.payload as { category: string }).category])).toEqual([[token(id.alice), 'MESSAGING_MENTION']]);
    expect((await queued('MESSAGE_GENERAL')).rows).toEqual([]);
    expect((await queued('MESSAGE_MENTION')).rows.find(row => row.person_id === id.bob)).toMatchObject({ status: 'SKIPPED', failure_code: 'PREFERENCE_DISABLED' });
  });

  it('un sondage suit la catégorie de sa conversation ; ni vote ni clôture n’alertent', async () => {
    const general = await openGeneral();
    await device(id.bob);
    await setPreferences(id.bob, { general: true });
    const poll = await send('demo-admin', general, { poll: { optionCount: 3, multiple: false } });
    expect((await queued()).rows.map(row => [row.person_id, row.category, row.message_id])).toEqual([[id.bob, 'MESSAGE_GENERAL', poll.id]]);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${general}/messages/${poll.id}/poll/votes`, { optionIndexes: [1] })).statusCode).toBe(200);
    expect((await req('demo-admin', 'POST', `${path}/conversations/${general}/messages/${poll.id}/poll/close`)).statusCode).toBe(200);
    expect((await queued()).rows).toHaveLength(1);
    expect(await run()).toHaveLength(1);
  });

  it('retrait du général, adhésion perdue ou lien coupé : plus d’alerte', async () => {
    const conversationId = await openGeneral();
    await device(id.bob);
    await setPreferences(id.bob, { general: true });
    await send('demo-admin', conversationId);
    expect((await queued()).rows).toHaveLength(1);
    expect((await req('demo-admin', 'DELETE', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    expect(await run()).toEqual([]);
    expect((await queued()).rows[0]).toMatchObject({ status: 'SKIPPED', failure_code: 'RECIPIENT_INELIGIBLE' });
    await send('demo-admin', conversationId);
    expect((await queued()).rows).toHaveLength(1);
  });
});

describe('préférences de messagerie dans l’objet versionné (#74)', () => {
  const get = (subject: string) => req(subject, 'GET', '/v1/me/notification-preferences');
  const put = (subject: string, body: object, version: number) => req(subject, 'PUT', '/v1/me/notification-preferences', body, { 'if-match': `"${version}"` });
  const course = { courseOffers: true, courseReminders: true, courseChanges: true, courseStaffAlerts: true };

  it('sans ligne : privés et mentions actifs, général désactivé, version 1', async () => {
    const read = await get('demo-alice');
    expect(read.statusCode, read.body).toBe(200);
    expect(read.json().data).toEqual({ version: 1, ...course, messagingPrivate: true, messagingGeneral: false, messagingMentions: true });
    expect(read.headers.etag).toBe('"1"');
  });

  it('enregistre les trois catégories avec les cours, versionne et refuse une version périmée', async () => {
    const saved = await put('demo-alice', { ...course, messagingPrivate: false, messagingGeneral: true, messagingMentions: false }, 1);
    expect(saved.statusCode, saved.body).toBe(200);
    expect(saved.json().data).toEqual({ version: 2, ...course, messagingPrivate: false, messagingGeneral: true, messagingMentions: false });
    expect((await put('demo-alice', { ...course, messagingPrivate: true }, 1)).statusCode).toBe(412);
    expect((await get('demo-alice')).json().data).toMatchObject({ version: 2, messagingPrivate: false, messagingGeneral: true, messagingMentions: false });
    const row = (await pool.query('SELECT messaging_private,messaging_general,messaging_mentions FROM drivy.notification_preference WHERE person_id=$1', [id.alice])).rows;
    expect(row).toEqual([{ messaging_private: false, messaging_general: true, messaging_mentions: false }]);
  });

  it('un ancien client qui n’envoie que les cours ne réinitialise pas les choix de messagerie', async () => {
    expect((await put('demo-alice', { ...course, messagingPrivate: false, messagingMentions: false }, 1)).statusCode).toBe(200);
    const legacy = await put('demo-alice', { ...course, courseReminders: false }, 2);
    expect(legacy.statusCode, legacy.body).toBe(200);
    expect(legacy.json().data).toEqual({ version: 3, ...course, courseReminders: false, messagingPrivate: false, messagingGeneral: false, messagingMentions: false });
  });

  it('refuse une clé inconnue, un type invalide et ne touche jamais les choix d’un tiers', async () => {
    expect((await put('demo-alice', { ...course, messagingPrivate: 'oui' }, 1)).statusCode).toBe(400);
    expect((await put('demo-alice', { ...course, messagingEverything: true }, 1)).statusCode).toBe(400);
    expect((await put('demo-alice', { ...course, messagingPrivate: false }, 1)).statusCode).toBe(200);
    expect((await get('demo-bob')).json().data).toMatchObject({ version: 1, messagingPrivate: true });
  });

  it('une préférence enregistrée par l’API gouverne les alertes suivantes', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    expect((await put('demo-alice', { ...course, messagingPrivate: false }, 1)).statusCode).toBe(200);
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toEqual([]);
    expect((await put('demo-alice', { ...course, messagingPrivate: true }, 2)).statusCode).toBe(200);
    await send('demo-instructor', conversationId);
    expect((await queued()).rows).toHaveLength(1);
  });
});
