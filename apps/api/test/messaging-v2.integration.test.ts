// Écrit, NON exécuté : PostgreSQL de test à qualifier en #84.
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
const issuer = 'https://messaging-v2.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const app = Fastify();
app.setErrorHandler((error, _request, reply) => reply.status(error instanceof ApiError ? error.status : 400)
  .send({ code: error instanceof ApiError ? error.code : 'INVALID_REQUEST' }));
registerMessaging(app, { pool, verifyToken: async authorization => {
  if (!authorization?.startsWith('Bearer demo-')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: authorization.slice(7) };
}, mode: 'test-synthetic' });
const path = `/v1/schools/${id.schoolA}/messaging`;
const newcomer = '20000000-0000-4000-8000-0000000000aa';
async function addNewcomer() {
  await pool.query("INSERT INTO drivy.person(id,display_name) VALUES($1,'Arrivée Exemple')", [newcomer]);
  await pool.query('INSERT INTO drivy.identity_link(issuer,subject,person_id) VALUES($1,$2,$3)', [issuer, 'demo-newcomer', newcomer]);
  await pool.query("INSERT INTO drivy.membership(id,school_id,person_id,roles) VALUES('30000000-0000-4000-8000-0000000000aa',$1,$2,ARRAY['LEARNER'])", [id.schoolA, newcomer]);
}
const subjects: Record<string, string> = { 'demo-admin': id.admin, 'demo-instructor': id.instructor,
  'demo-alice': id.alice, 'demo-bob': id.bob, 'demo-other-instructor': id.otherInstructor, 'demo-newcomer': newcomer };
type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';
const req = (subject: string, method: Method, target: string, payload?: object) => app.inject({ method, url: target,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1' },
  ...(payload ? { payload } : {}) });
const ciphertext = (payload = 'AAAA') => ({ scheme: 'synthetic', keyId: 'fixture', payload });
async function send(subject: string, conversationId: string, extra: object = {}) {
  const response = await req(subject, 'POST', `${path}/conversations/${conversationId}/messages`,
    { clientMessageId: randomUUID(), ciphertext: ciphertext(), ...extra });
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
const endAssignment = () => pool.query('UPDATE drivy.instructor_assignment SET valid_until=now() WHERE id=$1', [id.assignment]);
const restoreAssignment = () => pool.query('UPDATE drivy.instructor_assignment SET valid_until=NULL WHERE id=$1', [id.assignment]);

beforeAll(async () => { await migrate(pool); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('messagerie v2, fin du lien et époque des membres', () => {
  it('garde la lecture jusqu’à la coupure, refuse l’écriture et compte départs et retours', async () => {
    const conversationId = await openPrivate();
    await send('demo-instructor', conversationId);
    const members = await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/members`);
    expect(members.json().data).toEqual({ members: [{ personId: id.instructor }, { personId: id.alice }].sort((a, b) => a.personId.localeCompare(b.personId)), membersEpoch: 0 });
    await endAssignment();
    const page = await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/messages`);
    expect(page.statusCode, page.body).toBe(200);
    expect(page.json().data.items).toHaveLength(1);
    expect(page.json().data.access).toEqual({ canWrite: false, readableUntilSequence: 1, isGroupAdmin: false });
    const denied = await req('demo-alice', 'POST', `${path}/conversations/${conversationId}/messages`, { clientMessageId: randomUUID(), ciphertext: ciphertext() });
    expect(denied.statusCode).toBe(403);
    expect((await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/members`)).json().data.membersEpoch).toBe(2);
    await restoreAssignment();
    await send('demo-instructor', conversationId);
    expect((await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/members`)).json().data.membersEpoch).toBe(4);
    // Le retour ne rouvre pas les messages de la coupure : la nouvelle plage commence après la dernière séquence.
    const after = (await req('demo-alice', 'GET', `${path}/conversations/${conversationId}/messages`)).json().data.items as { sequence: number }[];
    expect(after.map(item => item.sequence).sort()).toEqual([1, 2]);
    const listed = (await req('demo-alice', 'GET', `${path}/conversations`)).json().data.items[0];
    expect(listed.membersEpoch).toBe(4);
  });
  it('n’offre plus de contact ADMIN dédié à l’élève', async () => {
    await pool.query(`INSERT INTO drivy.messaging_admin_contact(school_id,learner_person_id,admin_person_id,assigned_by_membership_id)
      VALUES($1,$2,$3,$4)`, [id.schoolA, id.alice, id.admin, id.adminMember]);
    expect((await req('demo-alice', 'GET', `${path}/contacts`)).json().data.contacts.map((c: { personId: string }) => c.personId)).toEqual([id.instructor]);
    expect((await req('demo-admin', 'PUT', `${path}/private/${id.alice}`)).statusCode).toBe(403);
  });
});

describe('messagerie v2, général', () => {
  it('annuaire : nom, photo seulement si visible, administrateurs par défaut', async () => {
    const members = (await req('demo-alice', 'GET', `${path}/general/members?limit=100`)).json().data.members as
      { personId: string; displayName: string; photoVersion: number | null; isGroupAdmin: boolean }[];
    const admin = members.find(m => m.personId === id.admin)!;
    expect(admin.isGroupAdmin).toBe(true);
    expect(members.filter(m => m.isGroupAdmin)).toHaveLength(1);
    for (const member of members) expect(Object.keys(member).sort()).toEqual(['displayName', 'hasPhoto', 'isGroupAdmin', 'personId', 'photoVersion']);
  });
  it('nomme et retire un administrateur, refuse le dernier, audite', async () => {
    await openGeneral();
    expect((await req('demo-instructor', 'PUT', `${path}/general/admins/${id.alice}`)).statusCode).toBe(403);
    expect((await req('demo-admin', 'PUT', `${path}/general/admins/${id.instructor}`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'PUT', `${path}/general/admins/${id.instructor}`)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'DELETE', `${path}/general/admins/${id.admin}`)).statusCode).toBe(200);
    expect((await req('demo-instructor', 'DELETE', `${path}/general/admins/${id.instructor}`)).statusCode).toBe(409);
    const audit = await pool.query('SELECT action FROM drivy.messaging_general_audit WHERE school_id=$1 ORDER BY id', [id.schoolA]);
    expect(audit.rows.map(row => row.action)).toEqual(['ADMIN_GRANTED', 'ADMIN_REVOKED']);
  });
  it('retire un membre : lecture seule jusqu’à la coupure, plus d’entrée par PUT /general', async () => {
    const general = await openGeneral();
    await send('demo-bob', general);
    expect((await req('demo-admin', 'DELETE', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'DELETE', `${path}/general/members/${id.admin}`)).statusCode).toBe(403);
    expect((await req('demo-bob', 'PUT', `${path}/general`)).statusCode).toBe(403);
    expect((await req('demo-bob', 'POST', `${path}/conversations/${general}/messages`, { clientMessageId: randomUUID(), ciphertext: ciphertext() })).statusCode).toBe(403);
    await send('demo-admin', general);
    const bobView = (await req('demo-bob', 'GET', `${path}/conversations/${general}/messages`)).json().data.items as unknown[];
    expect(bobView).toHaveLength(1);
    const members = (await req('demo-admin', 'GET', `${path}/conversations/${general}/members`)).json().data;
    expect(members.members.map((m: { personId: string }) => m.personId)).not.toContain(id.bob);
    expect(members.membersEpoch).toBeGreaterThanOrEqual(1);
    expect((await req('demo-admin', 'GET', `${path}/general/members?limit=100`)).json().data.members.map((m: { personId: string }) => m.personId)).not.toContain(id.bob);
  });
});

describe('messagerie v2, arrivée et réintégration (comme WhatsApp)', () => {
  it('un nouveau membre ne voit ni messages, ni réactions, ni votes, ni lectures antérieurs', async () => {
    const general = await openGeneral();
    const before = await send('demo-alice', general, { poll: { optionCount: 2, multiple: false } });
    expect((await req('demo-bob', 'PUT', `${path}/conversations/${general}/messages/${before.id}/reactions/${encodeURIComponent('👍')}`)).statusCode).toBe(200);
    expect((await req('demo-bob', 'PUT', `${path}/conversations/${general}/messages/${before.id}/poll/votes`, { optionIndexes: [0] })).statusCode).toBe(200);
    expect((await req('demo-bob', 'PUT', `${path}/conversations/${general}/read-state`, { lastReadSequence: 1 })).statusCode).toBe(200);
    await addNewcomer();
    const page = (await req('demo-newcomer', 'GET', `${path}/conversations/${general}/messages`)).json().data;
    expect(page.items).toEqual([]);
    expect(page.readStates).toEqual([]);
    expect((await req('demo-newcomer', 'PUT', `${path}/conversations/${general}/messages/${before.id}/reactions/${encodeURIComponent('👍')}`)).statusCode).toBe(404);
    // La RLS borne aussi la lecture directe des réactions, sondages et votes à la plage lisible.
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.school_id',$1,true),set_config('app.person_id',$2,true)", [id.schoolA, newcomer]);
      for (const table of ['messaging_reaction', 'messaging_poll', 'messaging_poll_vote'])
        expect((await db.query(`SELECT 1 FROM drivy.${table} WHERE message_id=$1`, [before.id])).rowCount, table).toBe(0);
    } finally { await db.query('ROLLBACK'); db.release(); }
    const after = await send('demo-alice', general);
    expect((await req('demo-newcomer', 'GET', `${path}/conversations/${general}/messages`)).json().data.items.map((m: { id: string }) => m.id)).toEqual([after.id]);
  });
  it('nouveau moniteur attribué : historique privé antérieur invisible', async () => {
    const conversationId = await openPrivate();
    await send('demo-instructor', conversationId);
    await endAssignment();
    await pool.query(`INSERT INTO drivy.instructor_assignment(id,school_id,training_id,instructor_membership_id,valid_from)
      VALUES('70000000-0000-4000-8000-0000000000aa',$1,$2,$3,now()-interval '1 minute')`, [id.schoolA, id.aliceTraining, id.otherInstructorMember]);
    const opened = await req('demo-other-instructor', 'PUT', `${path}/private/${id.alice}`);
    expect(opened.statusCode, opened.body).toBe(200);
    expect((await req('demo-other-instructor', 'GET', `${path}/conversations/${opened.json().data.conversationId}/messages`)).json().data.items).toEqual([]);
  });
  it('réintègre un membre retiré : rien de l’intervalle, époque +1, audit', async () => {
    const general = await openGeneral();
    await send('demo-bob', general);
    expect((await req('demo-admin', 'DELETE', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    const gap = await send('demo-admin', general);
    const epoch = (await req('demo-admin', 'GET', `${path}/conversations/${general}/members`)).json().data.membersEpoch as number;
    expect((await req('demo-alice', 'PUT', `${path}/general/members/${id.bob}`)).statusCode).toBe(403);
    expect((await req('demo-admin', 'PUT', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'PUT', `${path}/general/members/${id.bob}`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'GET', `${path}/conversations/${general}/members`)).json().data.membersEpoch).toBe(epoch + 1);
    const back = await send('demo-bob', general);
    const seen = (await req('demo-bob', 'GET', `${path}/conversations/${general}/messages`)).json().data.items.map((m: { id: string }) => m.id);
    expect(seen).not.toContain(gap.id);
    expect(seen).toContain(back.id);
    const audit = await pool.query('SELECT action FROM drivy.messaging_general_audit WHERE school_id=$1 ORDER BY id', [id.schoolA]);
    expect(audit.rows.map(row => row.action)).toEqual(['MEMBER_REMOVED', 'MEMBER_REINSTATED']);
  });
});

describe('messagerie v2, messages', () => {
  it('supprime pour moi ou pour tout le monde avec tombstone', async () => {
    const general = await openGeneral();
    const mine = await send('demo-bob', general);
    const other = await send('demo-alice', general);
    expect((await req('demo-bob', 'DELETE', `${path}/conversations/${general}/messages/${other.id}?scope=everyone`)).statusCode).toBe(403);
    expect((await req('demo-bob', 'DELETE', `${path}/conversations/${general}/messages/${other.id}?scope=me`)).statusCode).toBe(200);
    expect((await req('demo-bob', 'DELETE', `${path}/conversations/${general}/messages/${other.id}?scope=me`)).statusCode).toBe(200);
    expect((await req('demo-bob', 'DELETE', `${path}/conversations/${general}/messages/${mine.id}?scope=everyone`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'DELETE', `${path}/conversations/${general}/messages/${other.id}?scope=everyone`)).statusCode).toBe(200);
    const bob = (await req('demo-bob', 'GET', `${path}/conversations/${general}/messages`)).json().data.items;
    expect(bob.map((m: { id: string }) => m.id)).toEqual([mine.id]);
    expect(bob[0]).toMatchObject({ deletedForEveryone: true, ciphertext: null, pinned: false, reactions: [] });
    const stored = await pool.query('SELECT envelope FROM drivy.messaging_message WHERE id=$1', [mine.id]);
    expect(stored.rows[0].envelope).toBeNull();
  });
  it('réactions, réponses citées, épinglage et lectures visibles', async () => {
    const conversationId = await openPrivate();
    const first = await send('demo-instructor', conversationId);
    const reply = await send('demo-alice', conversationId, { replyToMessageId: first.id });
    expect((await req('demo-alice', 'POST', `${path}/conversations/${conversationId}/messages`,
      { clientMessageId: randomUUID(), ciphertext: ciphertext(), replyToMessageId: randomUUID() })).statusCode).toBe(404);
    const reaction = `${path}/conversations/${conversationId}/messages/${first.id}/reactions/${encodeURIComponent('👍')}`;
    expect((await req('demo-alice', 'PUT', reaction)).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', reaction)).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/messages/${first.id}/reactions/x`)).statusCode).toBe(400);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/messages/${first.id}/pin`)).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', `${path}/conversations/${conversationId}/read-state`, { lastReadSequence: 2 })).statusCode).toBe(200);
    const page = (await req('demo-instructor', 'GET', `${path}/conversations/${conversationId}/messages`)).json().data;
    const byId = new Map(page.items.map((m: { id: string }) => [m.id, m]));
    expect(byId.get(first.id)).toMatchObject({ pinned: true, reactions: [{ emoji: '👍', personIds: [id.alice] }] });
    expect(byId.get(reply.id)).toMatchObject({ replyToMessageId: first.id });
    expect(page.readStates).toEqual([{ personId: id.alice, lastReadSequence: 2 }]);
    await endAssignment();
    expect((await req('demo-alice', 'DELETE', reaction)).statusCode).toBe(403);
  });
  it('sondages : unique, multiple, vote modifiable et retirable, clôture par le créateur', async () => {
    const general = await openGeneral();
    const poll = await send('demo-instructor', general, { poll: { optionCount: 3, multiple: false } });
    const votes = `${path}/conversations/${general}/messages/${poll.id}/poll/votes`;
    expect((await req('demo-alice', 'PUT', votes, { optionIndexes: [0, 1] })).statusCode).toBe(400);
    expect((await req('demo-alice', 'PUT', votes, { optionIndexes: [3] })).statusCode).toBe(400);
    expect((await req('demo-alice', 'PUT', votes, { optionIndexes: [0] })).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', votes, { optionIndexes: [2] })).statusCode).toBe(200);
    expect((await req('demo-bob', 'PUT', votes, { optionIndexes: [2] })).statusCode).toBe(200);
    expect((await req('demo-bob', 'PUT', votes, { optionIndexes: [] })).statusCode).toBe(200);
    expect((await req('demo-alice', 'POST', `${path}/conversations/${general}/messages/${poll.id}/poll/close`)).statusCode).toBe(403);
    expect((await req('demo-instructor', 'POST', `${path}/conversations/${general}/messages/${poll.id}/poll/close`)).statusCode).toBe(200);
    expect((await req('demo-alice', 'PUT', votes, { optionIndexes: [1] })).statusCode).toBe(409);
    const item = (await req('demo-bob', 'GET', `${path}/conversations/${general}/messages`)).json().data.items
      .find((m: { id: string }) => m.id === poll.id);
    expect(item.poll).toEqual({ optionCount: 3, multiple: false, closed: true, creatorId: id.instructor,
      votes: [{ optionIndex: 2, personIds: [id.alice] }] });
    const multi = await send('demo-alice', general, { poll: { optionCount: 2, multiple: true } });
    expect((await req('demo-bob', 'PUT', `${path}/conversations/${general}/messages/${multi.id}/poll/votes`, { optionIndexes: [0, 1] })).statusCode).toBe(200);
  });
});

describe('messagerie v2, signalements', () => {
  it('idempotent par clientReportId, limité à la plage lisible, réservé aux administrateurs de l’école', async () => {
    const conversationId = await openPrivate();
    const message = await send('demo-instructor', conversationId);
    const body = { clientReportId: randomUUID(), conversationId, items: [{ messageId: message.id, ciphertext: ciphertext('BBBB') }] };
    const first = await req('demo-alice', 'POST', `${path}/reports`, body);
    expect(first.statusCode, first.body).toBe(200);
    expect((await req('demo-alice', 'POST', `${path}/reports`, body)).json().data.reportId).toBe(first.json().data.reportId);
    expect((await req('demo-alice', 'POST', `${path}/reports`, { ...body, items: [{ messageId: message.id, ciphertext: ciphertext('CCCC') }] })).statusCode).toBe(409);
    expect((await req('demo-bob', 'POST', `${path}/reports`, { ...body, clientReportId: randomUUID() })).statusCode).toBe(404);
    expect((await req('demo-alice', 'GET', `${path}/reports`)).statusCode).toBe(403);
    const inbox = (await req('demo-admin', 'GET', `${path}/reports`)).json().data.reports;
    expect(inbox).toHaveLength(1);
    expect(inbox[0].items).toEqual([{ messageId: message.id, ciphertext: ciphertext('BBBB') }]);
    // Preuve conservée après suppression pour tout le monde.
    expect((await req('demo-instructor', 'DELETE', `${path}/conversations/${conversationId}/messages/${message.id}?scope=everyone`)).statusCode).toBe(200);
    expect((await req('demo-admin', 'GET', `${path}/reports`)).json().data.reports[0].items).toEqual([{ messageId: message.id, ciphertext: ciphertext('BBBB') }]);
  });
});
