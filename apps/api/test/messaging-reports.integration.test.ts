// #77 : signalements scellés pour les administrateurs, statut de traitement, cadence, destinataires de clés.
// PostgreSQL synthétique réel, migrations sous propriétaire non privilégié (#78/#84).
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerMessagingKeys } from '../src/messaging-keys-routes.js';
import { ApiError } from '../src/errors.js';
import { reportLimits } from '../src/messaging.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-reports.test.invalid';
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
const path = `/v1/schools/${id.schoolA}/messaging`;
const crypto = `${path}/crypto`;
const subjects: Record<string, string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor,
  'demo-alice': id.alice, 'demo-bob': id.bob, 'demo-other-instructor': id.otherInstructor };
const user = (person: string) => `@${person.toLowerCase()}:drivy`;
type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';
const req = (subject: string, method: Method, target: string, payload?: object, device = 'REPORTDEVICE1') => app.inject({ method, url: target,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1',
    'x-drivy-device-id': device }, ...(payload ? { payload } : {}) });
const ciphertext = (payload = 'AAAA') => ({ scheme: 'synthetic', keyId: 'fixture', payload });
const deviceKeys = (person: string, device: string) => ({ user_id: user(person), device_id: device,
  algorithms: ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
  keys: { [`curve25519:${device}`]: `c${device}`, [`ed25519:${device}`]: `e${device}` }, signatures: {} });

async function send(subject: string, conversationId: string) {
  const members = await req(subject, 'GET', `${path}/conversations/${conversationId}/members`);
  expect(members.statusCode, members.body).toBe(200);
  const response = await req(subject, 'POST', `${path}/conversations/${conversationId}/messages`,
    { clientMessageId: randomUUID(), ciphertext: ciphertext(), expectedMembersEpoch: members.json().data.membersEpoch });
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data as { id: string; sequence: number };
}
async function openPrivate() {
  const opened = await req('demo-instructor', 'PUT', `${path}/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
async function openGeneral(subject = 'demo-admin') {
  const opened = await req(subject, 'PUT', `${path}/general`);
  expect(opened.statusCode, opened.body).toBe(200);
  return opened.json().data.conversationId as string;
}
const report = (subject: string, conversationId: string, messageId: string, clientReportId = randomUUID(), payload = 'BBBB') =>
  req(subject, 'POST', `${path}/reports`, { clientReportId, conversationId, items: [{ messageId, ciphertext: ciphertext(payload) }] });
const setStatus = (subject: string, reportId: string, status: string, expectedStatus: string) =>
  req(subject, 'PUT', `${path}/reports/${reportId}/status`, { status, expectedStatus });

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('signalements, boîte des administrateurs', () => {
  it('donne à l’administrateur le contexte minimal et les noms, sans lui ouvrir la conversation privée', async () => {
    const conversationId = await openPrivate();
    const message = await send('demo-instructor', conversationId);
    const created = await report('demo-alice', conversationId, message.id);
    expect(created.statusCode, created.body).toBe(200);
    const listed = await req('demo-admin', 'GET', `${path}/reports`);
    expect(listed.statusCode, listed.body).toBe(200);
    const data = listed.json().data;
    expect(data.openCount).toBe(1);
    expect(data.nextCursor).toBeNull();
    expect(data.reports).toHaveLength(1);
    const [item] = data.reports;
    expect(item).toMatchObject({ id: created.json().data.reportId, conversationId, conversationKind: 'PRIVATE', reporterPersonId: id.alice,
      reporterDisplayName: 'Alice Exemple', status: 'OPEN', history: [] });
    expect(item.items).toEqual([{ messageId: message.id, ciphertext: ciphertext('BBBB'), senderPersonId: id.instructor,
      senderDisplayName: 'Alex Moniteur', sequence: message.sequence, acceptedAt: expect.any(String) }]);
    // Le signalement n’ouvre que les enveloppes choisies : l’administrateur reste étranger à la conversation.
    expect((await req('demo-admin', 'GET', `${path}/conversations/${conversationId}/messages`)).statusCode).toBe(404);
  });

  it('refuse un non-administrateur et une autre école, au serveur', async () => {
    const conversationId = await openPrivate();
    const message = await send('demo-instructor', conversationId);
    const created = await report('demo-alice', conversationId, message.id);
    const reportId = created.json().data.reportId as string;
    for (const subject of ['demo-alice', 'demo-instructor', 'demo-bob']) {
      expect((await req(subject, 'GET', `${path}/reports`)).statusCode, subject).toBe(403);
      expect((await setStatus(subject, reportId, 'HANDLED', 'OPEN')).statusCode, subject).toBe(403);
    }
    // L’instructeur administre l’école B : il ne voit ni n’agit sur les signalements de l’école A.
    const other = `/v1/schools/${id.schoolB}/messaging`;
    const foreignList = await req('demo-instructor', 'GET', `${other}/reports`);
    expect(foreignList.statusCode, foreignList.body).toBe(200);
    expect(foreignList.json().data).toMatchObject({ reports: [], openCount: 0 });
    expect((await req('demo-instructor', 'PUT', `${other}/reports/${reportId}/status`, { status: 'HANDLED', expectedStatus: 'OPEN' })).statusCode).toBe(404);
    expect((await pool.query('SELECT status FROM drivy.messaging_report WHERE id=$1', [reportId])).rows[0].status).toBe('OPEN');
  });

  it('traite un signalement : historique, rejeu sans doublon, statut périmé refusé, filtre et réouverture', async () => {
    const conversationId = await openPrivate();
    const first = await report('demo-alice', conversationId, (await send('demo-instructor', conversationId)).id);
    const reportId = first.json().data.reportId as string;

    const handled = await setStatus('demo-admin', reportId, 'HANDLED', 'OPEN');
    expect(handled.statusCode, handled.body).toBe(200);
    expect(handled.json().data).toMatchObject({ reportId, status: 'HANDLED' });
    expect(handled.json().data.history).toEqual([{ actorPersonId: id.admin, actorDisplayName: 'Camille Administration',
      fromStatus: 'OPEN', toStatus: 'HANDLED', createdAt: expect.any(String) }]);

    // Un renvoi du même changement (réponse perdue) ne crée pas d’événement.
    expect((await setStatus('demo-admin', reportId, 'HANDLED', 'OPEN')).json().data.history).toHaveLength(1);
    // Un autre administrateur qui lisait encore « ouvert » reçoit un conflit explicite.
    const stale = await setStatus('demo-admin', reportId, 'DISMISSED', 'OPEN');
    expect(stale.statusCode).toBe(409);
    expect(stale.json().code).toBe('REPORT_STATUS_CONFLICT');

    const open = (await req('demo-admin', 'GET', `${path}/reports?status=OPEN`)).json().data;
    expect(open).toMatchObject({ reports: [], openCount: 0 });
    const treated = (await req('demo-admin', 'GET', `${path}/reports?status=HANDLED`)).json().data;
    expect(treated.reports.map((row: { id: string }) => row.id)).toEqual([reportId]);

    const reopened = await setStatus('demo-admin', reportId, 'OPEN', 'HANDLED');
    expect(reopened.statusCode, reopened.body).toBe(200);
    expect(reopened.json().data.history.map((event: { toStatus: string }) => event.toStatus)).toEqual(['HANDLED', 'OPEN']);
    expect((await req('demo-admin', 'GET', `${path}/reports`)).json().data.openCount).toBe(1);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_report_status_event')).rows[0].count).toBe(2);

    expect((await setStatus('demo-admin', randomUUID(), 'HANDLED', 'OPEN')).statusCode).toBe(404);
    expect((await setStatus('demo-admin', reportId, 'ARCHIVED', 'OPEN')).statusCode).toBe(400);
  });

  it('refuse un administrateur révoqué entre la lecture et l’action', async () => {
    const conversationId = await openPrivate();
    const created = await report('demo-alice', conversationId, (await send('demo-instructor', conversationId)).id);
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1", [id.adminMember]);
    expect((await req('demo-admin', 'GET', `${path}/reports`)).statusCode).toBe(403);
    expect((await setStatus('demo-admin', created.json().data.reportId, 'HANDLED', 'OPEN')).statusCode).toBe(403);
  });

  it('pagine du plus récent au plus ancien sans perdre de ligne', async () => {
    const conversationId = await openGeneral();
    const ids: string[] = [];
    for (let index = 0; index < 3; index++) {
      const message = await send('demo-admin', conversationId);
      ids.push((await report('demo-alice', conversationId, message.id)).json().data.reportId);
      await pool.query("UPDATE drivy.messaging_report SET created_at=now()-($2::int*interval '10 minutes') WHERE id=$1", [ids[index], 3 - index]);
    }
    const page = (await req('demo-admin', 'GET', `${path}/reports?limit=2`)).json().data;
    expect(page.reports.map((row: { id: string }) => row.id)).toEqual([ids[2], ids[1]]);
    const next = (await req('demo-admin', 'GET', `${path}/reports?limit=2&before=${page.nextCursor}`)).json().data;
    expect(next.reports.map((row: { id: string }) => row.id)).toEqual([ids[0]]);
    expect(next.nextCursor).toBeNull();
  });
});

describe('signalements, cadence', () => {
  it('limite par personne et par conversation avec une erreur explicite, sans bloquer le renvoi identique', async () => {
    const conversationId = await openPrivate();
    const sent: string[] = [];
    for (let index = 0; index <= reportLimits.perConversationPerHour; index++) sent.push((await send('demo-instructor', conversationId)).id);
    const firstClient = randomUUID();
    for (let index = 0; index < reportLimits.perConversationPerHour; index++) {
      const accepted = await report('demo-alice', conversationId, sent[index]!, index === 0 ? firstClient : randomUUID());
      expect(accepted.statusCode, accepted.body).toBe(200);
    }
    const limited = await report('demo-alice', conversationId, sent.at(-1)!);
    expect(limited.statusCode).toBe(429);
    expect(limited.json().code).toBe('REPORT_RATE_LIMITED');
    // Reprise après réponse perdue : reconnue avant le comptage.
    const replay = await report('demo-alice', conversationId, sent[0]!, firstClient);
    expect(replay.statusCode, replay.body).toBe(200);
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.messaging_report')).rows[0].count).toBe(reportLimits.perConversationPerHour);
    // Une autre personne, ou la même dans une autre conversation, n’est pas bloquée par cette limite.
    const other = await report('demo-instructor', conversationId, sent.at(-1)!);
    expect(other.statusCode, other.body).toBe(200);
    const general = await openGeneral();
    const generalMessage = await send('demo-admin', general);
    expect((await report('demo-alice', general, generalMessage.id)).statusCode).toBe(200);
  });

  it('limite aussi sur vingt-quatre heures dans l’école', async () => {
    const conversationId = await openPrivate();
    const message = await send('demo-instructor', conversationId);
    for (let index = 0; index < reportLimits.perSchoolPerDay; index++) {
      await pool.query(`INSERT INTO drivy.messaging_report(id,school_id,conversation_id,reporter_person_id,client_report_id,fingerprint,created_at)
        VALUES($1,$2,$3,$4,$5,$6,now()-interval '2 hours')`,
        [randomUUID(), id.schoolA, conversationId, id.alice, randomUUID(), 'a'.repeat(64)]);
    }
    const limited = await report('demo-alice', conversationId, message.id);
    expect(limited.statusCode).toBe(429);
    expect(limited.json().code).toBe('REPORT_RATE_LIMITED');
    // Les signalements d’une autre personne ne comptent pas.
    expect((await report('demo-instructor', conversationId, message.id)).statusCode).toBe(200);
  });
});

describe('signalements, destinataires de clés', () => {
  it('liste les administrateurs actifs de l’école, identifiants seulement, et suit leur révocation', async () => {
    const asAlice = await req('demo-alice', 'GET', `${crypto}/report-recipients`);
    expect(asAlice.statusCode, asAlice.body).toBe(200);
    expect(asAlice.json().data).toEqual({ recipients: [{ personId: id.admin }] });
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1", [id.adminMember]);
    expect((await req('demo-alice', 'GET', `${crypto}/report-recipients`)).json().data).toEqual({ recipients: [] });
  });

  it('permet à tout membre de joindre les appareils des administrateurs, et à eux seuls', async () => {
    expect((await req('demo-admin', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.admin, 'ADMINDEVICE1') }, 'ADMINDEVICE1')).statusCode).toBe(200);
    expect((await req('demo-instructor', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.instructor, 'INSTRDEVICE1') }, 'INSTRDEVICE1')).statusCode).toBe(200);
    expect((await req('demo-alice', 'POST', `${crypto}/keys/upload`, { device_keys: deviceKeys(id.alice, 'ALICEDEVICE1') }, 'ALICEDEVICE1')).statusCode).toBe(200);
    // Bob n’a aucun lien avec le moniteur : ses clés restent hors de portée, celles de l’administrateur non.
    const query = await req('demo-bob', 'POST', `${crypto}/keys/query`,
      { device_keys: { [user(id.admin)]: [], [user(id.instructor)]: [] } }, 'BOBDEVICE001');
    expect(query.statusCode, query.body).toBe(200);
    const devices = query.json().data.device_keys as Record<string, Record<string, unknown>>;
    expect(Object.keys(devices[user(id.admin)] ?? {})).toEqual(['ADMINDEVICE1']);
    expect(devices[user(id.instructor)]).toBeUndefined();

    const toAdmin = await req('demo-bob', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/report-key-1`,
      { messages: { [user(id.admin)]: { '*': { algorithm: 'm.olm.v1.curve25519-aes-sha2', ciphertext: {} } } } }, 'BOBDEVICE001');
    expect(toAdmin.statusCode, toAdmin.body).toBe(200);
    const toInstructor = await req('demo-bob', 'PUT', `${crypto}/sendToDevice/m.room.encrypted/report-key-2`,
      { messages: { [user(id.instructor)]: { '*': { algorithm: 'm.olm.v1.curve25519-aes-sha2', ciphertext: {} } } } }, 'BOBDEVICE001');
    expect(toInstructor.statusCode, toInstructor.body).toBe(200);
    expect((await pool.query('SELECT recipient_person_id AS recipient FROM drivy.messaging_to_device ORDER BY id')).rows)
      .toEqual([{ recipient: id.admin }]);
    const sync = await req('demo-admin', 'GET', `${crypto}/sync`, undefined, 'ADMINDEVICE1');
    expect(sync.statusCode, sync.body).toBe(200);
    expect(sync.json().data.to_device.events).toHaveLength(1);
  });
});
