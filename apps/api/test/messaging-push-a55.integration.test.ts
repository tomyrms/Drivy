// A55 (#74) : matrice de bout en bout des alertes de messagerie, sur PostgreSQL réelle (routes messagerie + préférences +
// appareils + worker push). Le transport est un collecteur local, jamais APNs. Ne jamais pointer vers une base de production.
// Ces tests couvrent les critères de l'issue qui n'avaient aucune preuve automatisée : charge et journaux sans donnée
// sensible pour les trois catégories, coupure d'accès entre la mise en file et l'envoi, jeton d'appareil repris par une
// autre personne, jeton révoqué, et absence de doublon mention + général pour un même message.
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { Pool } from 'pg';
import { freshDatabase } from './support/harness.js';
import { seedFixtures, fixtureIds as id } from '../scripts/fixtures.js';
import { registerMessaging } from '../src/messaging-routes.js';
import { registerNotificationPreferences } from '../src/notification-preferences.js';
import { processPushBatch, type PushSender } from '../src/course-push.js';
import { ApiError } from '../src/errors.js';

const url = process.env.TEST_DATABASE_URL;
if (!url || new URL(url).pathname !== '/drivy_test') throw new Error('TEST_DATABASE_URL vers drivy_test isolée obligatoire.');
const issuer = 'https://messaging-push-a55.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
const worker = new Pool({ connectionString: url, options: '-c role=drivy_harness_migrator' });
/** Le rôle réel du service d'envoi, utilisé seulement pour prouver son absence d'accès au contenu. */
const workerRole = new Pool({ connectionString: url, options: '-c role=drivy_course_worker' });
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
/** Contenu chiffré synthétique : le serveur ne reçoit qu'un base64 opaque, jamais le texte. */
const envelope = (marker: string) => ({ scheme: 'synthetic', keyId: 'fixture', payload: Buffer.from(marker, 'utf8').toString('base64') });
async function send(subject: string, conversationId: string, extra: object = {}) {
  const members = await req(subject, 'GET', `${path}/conversations/${conversationId}/members`);
  const response = await req(subject, 'POST', `${path}/conversations/${conversationId}/messages`, { clientMessageId: randomUUID(),
    ciphertext: envelope('AAAA'), expectedMembersEpoch: members.json().data.membersEpoch, ...extra });
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
function collector(out: Sent[], result: 'SENT' | 'RETRY' | 'INVALID_TOKEN' = 'SENT'): PushSender {
  return { async send(token, _env, payload) { out.push({ token, payload: payload as Record<string, unknown> }); return result; }, close() {} };
}
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
  person_id: string; category: string; status: string; failure_code: string | null; title: string; body: string; message_id: string;
}
const queued = async () => (await pool.query<QueuedRow>(
  `SELECT person_id,category,status,failure_code,title,body,message_id FROM drivy.push_notification
   WHERE category LIKE 'MESSAGE_%' ORDER BY category,person_id,created_at`)).rows;
const run = async (sender?: PushSender) => { const out: Sent[] = []; await processPushBatch(worker, sender ?? collector(out)); return out; };
/** Coupe le lien d'une personne dans une conversation, comme le fait drivy.messaging_sync_links quand un droit tombe. */
async function cutLink(conversationId: string, person: string) {
  const cut = await pool.query<{ cut_sequence: string }>(
    `UPDATE drivy.messaging_member_link SET cut_sequence=(SELECT last_sequence FROM drivy.messaging_conversation WHERE school_id=$1 AND id=$2),
       cut_at=now()
     WHERE school_id=$1 AND conversation_id=$2 AND person_id=$3 AND cut_sequence IS NULL RETURNING cut_sequence`,
    [id.schoolA, conversationId, person]);
  expect(cut.rowCount).toBe(1);
}

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await worker.end(); await workerRole.end(); await pool.end(); });

describe('A55 : charge et journaux sans donnée sensible', () => {
  it('les trois catégories ne transportent que des identifiants techniques', async () => {
    const privateConversation = await openPrivate();
    const generalConversation = await openGeneral();
    for (const person of [id.alice, id.bob]) await device(person);
    await setPreferences(id.alice, { general: true });
    await setPreferences(id.bob, { general: true });

    const privateMessage = await send('demo-instructor', privateConversation, { ciphertext: envelope('CONTENU-PRIVE-INTERDIT') });
    const generalMessage = await send('demo-admin', generalConversation,
      { ciphertext: envelope('CONTENU-GENERAL-INTERDIT'), poll: { optionCount: 3, multiple: false } });
    const mentionMessage = await send('demo-admin', generalConversation,
      { ciphertext: envelope('CONTENU-MENTION-INTERDIT'), mentionPersonIds: [id.bob] });

    const out = await run();
    expect(out.map(item => (item.payload as { category: string }).category).sort())
      .toEqual(['MESSAGING_GENERAL', 'MESSAGING_MENTION', 'MESSAGING_PRIVATE']);
    const byCategory = new Map(out.map(item => [(item.payload as { category: string }).category, item.payload]));
    // Titre générique, corps absent : l'écran verrouillé ne montre rien du message.
    expect(byCategory.get('MESSAGING_PRIVATE')).toMatchObject({ aps: { alert: { title: 'Nouveau message' } },
      conversationId: privateConversation, messageId: privateMessage.id, sequence: privateMessage.sequence });
    // Alice est abonnée au général : les deux messages du général sont regroupés en une alerte, la plus récente.
    expect(byCategory.get('MESSAGING_GENERAL')).toMatchObject({ aps: { alert: { title: 'Nouveau message' } },
      conversationId: generalConversation });
    expect([generalMessage.id, mentionMessage.id]).toContain((byCategory.get('MESSAGING_GENERAL') as { messageId: string }).messageId);
    expect(byCategory.get('MESSAGING_MENTION')).toMatchObject({ aps: { alert: { title: "Quelqu'un vous a mentionné" } },
      conversationId: generalConversation, messageId: mentionMessage.id });

    const serialized = JSON.stringify(out);
    // Contenu chiffré, noms d'auteur, noms d'élève, question de sondage : rien ne doit apparaître dans une charge.
    for (const forbidden of ['CONTENU-PRIVE-INTERDIT', 'CONTENU-GENERAL-INTERDIT', 'CONTENU-MENTION-INTERDIT',
      envelope('CONTENU-PRIVE-INTERDIT').payload, envelope('CONTENU-GENERAL-INTERDIT').payload, envelope('CONTENU-MENTION-INTERDIT').payload,
      'AAAA', 'ciphertext', 'Alice', 'Alex', 'Camille', 'Exemple', 'optionCount', 'question', 'sondage'])
      expect(serialized).not.toContain(forbidden);
    // Aucun corps d'alerte : `aps.alert` se limite au titre.
    for (const item of out) expect(Object.keys((item.payload as { aps: { alert: object } }).aps.alert)).toEqual(['title']);
    // Les lignes en file elles-mêmes ne retiennent aucun contenu : titre générique, corps vide.
    for (const row of await queued()) {
      expect(row.body).toBe('');
      expect(['Nouveau message', "Quelqu'un vous a mentionné"]).toContain(row.title);
    }
    // Alice est abonnée au général : deux messages du général, une seule alerte, l'autre regroupée.
    const aliceGeneral = (await queued()).filter(row => row.person_id === id.alice && row.category === 'MESSAGE_GENERAL');
    expect(aliceGeneral.filter(row => row.status === 'SENT')).toHaveLength(1);
    expect(aliceGeneral.filter(row => row.failure_code === 'COALESCED')).toHaveLength(1);
  });

  it('le rôle du service d’envoi ne peut pas lire les tables de messagerie', async () => {
    // Le service d'envoi lit sa file et les appareils, jamais le contenu : la preuve est structurelle, pas seulement
    // l'absence de journalisation dans le chemin heureux.
    expect((await workerRole.query<{ count: number }>('SELECT count(*)::int AS count FROM drivy.push_notification')).rows[0]!.count).toBeGreaterThanOrEqual(0);
    expect((await workerRole.query<{ count: number }>('SELECT count(*)::int AS count FROM drivy.push_device')).rows[0]!.count).toBeGreaterThanOrEqual(0);
    for (const table of ['drivy.messaging_message', 'drivy.messaging_conversation', 'drivy.messaging_member_link'])
      await expect(workerRole.query(`SELECT count(*) FROM ${table}`)).rejects.toMatchObject({ code: '42501' });
  });

  it('le service d’envoi n’écrit aucune donnée de message dans ses journaux, même après un échec de transport', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId, { ciphertext: envelope('JOURNAL-INTERDIT') });
    const writes: string[] = [];
    const capture = (...args: unknown[]) => { writes.push(args.map(value => String(value)).join(' ')); };
    const consoleSpies = (['log', 'info', 'warn', 'error', 'debug'] as const)
      .map(kind => vi.spyOn(console, kind).mockImplementation(capture));
    const stdout = vi.spyOn(process.stdout, 'write').mockImplementation((chunk: string | Uint8Array) => { writes.push(String(chunk)); return true; });
    const stderr = vi.spyOn(process.stderr, 'write').mockImplementation((chunk: string | Uint8Array) => { writes.push(String(chunk)); return true; });
    try {
      // Un échec de transport est le chemin le plus bavard : rien de sensible ne doit sortir non plus.
      expect(await run(collector([], 'RETRY'))).toEqual([]);
      expect((await queued()).filter(row => row.status === 'PENDING')).toHaveLength(1);
    } finally {
      for (const spy of consoleSpies) spy.mockRestore();
      stdout.mockRestore();
      stderr.mockRestore();
    }
    const journal = writes.join('\n');
    for (const forbidden of ['JOURNAL-INTERDIT', envelope('JOURNAL-INTERDIT').payload, 'Alice', 'Alex', 'Exemple', 'AAAA'])
      expect(journal).not.toContain(forbidden);
  });
});

describe('A55 : retrait d’accès entre la mise en file et l’envoi', () => {
  it('une conversation privée coupée après la mise en file n’expédie rien', async () => {
    const conversationId = await openPrivate();
    await device(id.alice);
    await send('demo-instructor', conversationId);
    expect(await queued()).toHaveLength(1);
    await cutLink(conversationId, id.alice);
    expect(await run()).toEqual([]);
    expect((await queued())[0]).toMatchObject({ status: 'SKIPPED', failure_code: 'RECIPIENT_INELIGIBLE' });
  });

  it('une mention dont le lien est coupé après la mise en file n’expédie rien', async () => {
    const conversationId = await openGeneral();
    await device(id.bob);
    await send('demo-admin', conversationId, { mentionPersonIds: [id.bob] });
    expect((await queued()).map(row => [row.person_id, row.category])).toEqual([[id.bob, 'MESSAGE_MENTION']]);
    await cutLink(conversationId, id.bob);
    expect(await run()).toEqual([]);
    // Les mentions passent aussi par `push_messaging_snapshot` : le lien coupé rend le destinataire inéligible.
    expect((await queued())[0]).toMatchObject({ status: 'SKIPPED', failure_code: 'RECIPIENT_INELIGIBLE' });
  });

  it('une mention ne laisse aucune alerte du général pour le même message', async () => {
    const conversationId = await openGeneral();
    await device(id.alice);
    await setPreferences(id.alice, { general: true });
    const message = await send('demo-admin', conversationId, { mentionPersonIds: [id.alice] });
    const rows = (await pool.query<{ category: string }>(
      "SELECT category FROM drivy.push_notification WHERE message_id=$1 AND person_id=$2 ORDER BY category", [message.id, id.alice])).rows;
    expect(rows.map(row => row.category)).toEqual(['MESSAGE_MENTION']);
    expect(await run()).toHaveLength(1);
  });

  it('une conversation du général en sourdine après la mise en file n’expédie rien', async () => {
    const conversationId = await openGeneral();
    await device(id.bob);
    await setPreferences(id.bob, { general: true });
    await send('demo-admin', conversationId);
    expect(await queued()).toHaveLength(1);
    await pool.query(`INSERT INTO drivy.messaging_read_state(school_id,conversation_id,person_id,muted_until)
      VALUES($1,$2,$3,now()+interval '1 hour')`, [id.schoolA, conversationId, id.bob]);
    expect(await run()).toEqual([]);
    expect((await queued())[0]).toMatchObject({ status: 'SKIPPED', failure_code: 'SILENCED' });
  });
});

describe('A55 : appareil, changement de compte et révocation', () => {
  it('un jeton repris par une autre personne cesse de servir la première', async () => {
    const privateConversation = await openPrivate();
    const generalConversation = await openGeneral();
    await device(id.alice);
    await send('demo-instructor', privateConversation);
    expect(await queued()).toHaveLength(1);

    // Changement de compte sur le même appareil : bob réclame le jeton d'Alice par la route réelle.
    const claimed = await req('demo-bob', 'PUT', '/v1/me/push-devices', { token: token(id.alice), environment: 'SANDBOX' });
    expect(claimed.statusCode, claimed.body).toBe(200);
    expect((await pool.query('SELECT person_id,revoked_at FROM drivy.push_device WHERE token=$1', [token(id.alice)])).rows)
      .toEqual([{ person_id: id.bob, revoked_at: null }]);

    // L'alerte déjà en file pour Alice ne part plus sur ce jeton.
    expect(await run()).toEqual([]);
    expect((await queued())[0]).toMatchObject({ person_id: id.alice, status: 'SKIPPED', failure_code: 'NO_DEVICE' });
    // Et un message suivant n'ouvre plus de file pour elle : elle n'a plus d'appareil.
    await send('demo-instructor', privateConversation);
    expect(await queued()).toHaveLength(1);

    // Le jeton appartient maintenant à bob, qui reçoit ses propres alertes dessus.
    await setPreferences(id.bob, { general: true });
    await send('demo-admin', generalConversation);
    const out = await run();
    expect(out).toHaveLength(1);
    expect(out[0]!.token).toBe(token(id.alice));
    expect(out[0]!.payload).toMatchObject({ kind: 'MESSAGING', category: 'MESSAGING_GENERAL', conversationId: generalConversation });
  });

  it('un jeton enregistré deux fois reste unique et un jeton révoqué n’est plus utilisé', async () => {
    const conversationId = await openPrivate();
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const registered = await req('demo-alice', 'PUT', '/v1/me/push-devices', { token: token(id.alice), environment: 'SANDBOX' });
      expect(registered.statusCode, registered.body).toBe(200);
      expect(registered.json().data).toEqual({ registered: true });
    }
    expect((await pool.query('SELECT count(*)::int AS count FROM drivy.push_device WHERE token=$1', [token(id.alice)])).rows[0]!.count).toBe(1);
    await send('demo-instructor', conversationId);
    const revoked = await req('demo-alice', 'POST', '/v1/me/push-devices/revoke', { token: token(id.alice) });
    expect(revoked.statusCode, revoked.body).toBe(200);
    expect(revoked.json().data).toEqual({ revoked: true });
    expect((await pool.query('SELECT revoked_at FROM drivy.push_device WHERE token=$1', [token(id.alice)])).rows[0]!.revoked_at).not.toBeNull();
    expect(await run()).toEqual([]);
    expect((await queued())[0]).toMatchObject({ status: 'SKIPPED', failure_code: 'NO_DEVICE' });
  });
});
