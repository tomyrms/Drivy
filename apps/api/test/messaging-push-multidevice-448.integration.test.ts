// #448 chemin messagerie : état d'envoi par destination, sur PostgreSQL réelle (routes messagerie + worker push).
// Le transport est un expéditeur scripté, jamais APNs. Ne jamais pointer vers une base de production.
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
const issuer = 'https://messaging-push-multidevice.test.invalid';
const pool = new Pool({ connectionString: url, max: 8 });
let worker = new Pool({ connectionString: url, options: '-c role=drivy_harness_migrator' });
const restart = async () => { await worker.end(); worker = new Pool({ connectionString: url, options: '-c role=drivy_harness_migrator' }); };
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
const req = (subject: string, method: 'GET' | 'POST' | 'PUT', target: string, payload?: object) =>
  app.inject({ method, url: target, headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!,
    'x-drivy-expected-access-epoch': '1' }, ...(payload ? { payload } : {}) });
async function sendPrivate() {
  const opened = await req('demo-instructor', 'PUT', `${path}/private/${id.alice}`);
  expect(opened.statusCode, opened.body).toBe(200);
  const conversationId = opened.json().data.conversationId as string;
  const members = await req('demo-instructor', 'GET', `${path}/conversations/${conversationId}/members`);
  const response = await req('demo-instructor', 'POST', `${path}/conversations/${conversationId}/messages`, { clientMessageId: randomUUID(),
    ciphertext: { scheme: 'synthetic', keyId: 'fixture', payload: 'AAAA' }, expectedMembersEpoch: members.json().data.membersEpoch });
  expect(response.statusCode, response.body).toBe(200);
}
const tokenA = 'a'.repeat(64), tokenB = 'b'.repeat(64);
const devices = () => pool.query("INSERT INTO drivy.push_device(person_id,platform,environment,token) VALUES($1,'IOS','SANDBOX',$2),($1,'IOS','SANDBOX',$3)", [id.alice, tokenA, tokenB]);
type Plan = Record<string, ('SENT' | 'INVALID_TOKEN' | 'RETRY')[]>;
function scripted(plan: Plan) {
  const calls: string[] = [];
  const sender: PushSender = { async send(device) {
    calls.push(device);
    const results = plan[device] ?? ['SENT'];
    return results[Math.min(calls.filter((call) => call === device).length - 1, results.length - 1)]!;
  }, close() {} };
  return { sender, calls };
}
const notification = async () => (await pool.query<{ id: string; status: string; attempts: number; failure_code: string | null }>(
  "SELECT id,status,attempts,failure_code FROM drivy.push_notification WHERE category LIKE 'MESSAGE_%' AND person_id=$1", [id.alice])).rows;
const deliveries = async (notificationId: string) => Object.fromEntries((await pool.query<{ token: string; status: string; attempts: number; failure_code: string | null }>(
  'SELECT p.token,d.status,d.attempts,d.failure_code FROM drivy.push_delivery d JOIN drivy.push_device p ON p.id=d.device_id WHERE d.notification_id=$1', [notificationId])).rows.map((row) => [row.token, row]));
const due = () => pool.query("UPDATE drivy.push_notification SET available_at=now()-interval '1 second' WHERE status='PENDING'");

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); await devices(); });
afterAll(async () => { await app.close(); await worker.end(); await pool.end(); });

describe('#448 messagerie : état par destination', () => {
  it('A acceptée, B en échec transitoire : B seule est reprise après redémarrage, la notification se clôt', async () => {
    await sendPrivate();
    const first = scripted({ [tokenA]: ['SENT'], [tokenB]: ['RETRY'] });
    await processPushBatch(worker, first.sender);
    let [row] = await notification();
    expect(row).toMatchObject({ status: 'PENDING', attempts: 1 });
    expect(await deliveries(row!.id)).toMatchObject({ [tokenA]: { status: 'SENT' }, [tokenB]: { status: 'PENDING', failure_code: 'APNS_RETRY' } });
    await restart(); await due();
    const second = scripted({});
    await processPushBatch(worker, second.sender);
    expect(second.calls).toEqual([tokenB]);
    [row] = await notification();
    expect(row).toMatchObject({ status: 'SENT' });
    expect(await deliveries(row!.id)).toMatchObject({ [tokenA]: { status: 'SENT', attempts: 1 }, [tokenB]: { status: 'SENT', attempts: 2 } });
  });
  it('un jeton définitivement invalide ne bloque pas l’autre appareil et ne boucle pas', async () => {
    await sendPrivate();
    await processPushBatch(worker, scripted({ [tokenA]: ['SENT'], [tokenB]: ['INVALID_TOKEN'] }).sender);
    const [row] = await notification();
    expect(row).toMatchObject({ status: 'SENT' });
    expect(await deliveries(row!.id)).toMatchObject({ [tokenB]: { status: 'REJECTED', failure_code: 'INVALID_TOKEN' } });
    await due();
    const again = scripted({});
    await processPushBatch(worker, again.sender);
    expect(again.calls).toEqual([]);
  });
  it('reprise épuisée sur B : EXPIRED, A jamais renvoyée', async () => {
    await sendPrivate();
    const run = scripted({ [tokenA]: ['SENT'], [tokenB]: ['RETRY'] });
    for (let pass = 1; pass <= 5; pass += 1) { await processPushBatch(worker, run.sender); await due(); }
    const [row] = await notification();
    expect(row).toMatchObject({ status: 'SENT', attempts: 5 });
    expect(await deliveries(row!.id)).toMatchObject({ [tokenB]: { status: 'EXPIRED', failure_code: 'RETRY_EXHAUSTED' } });
    expect(run.calls.filter((call) => call === tokenA)).toHaveLength(1);
    expect(run.calls.filter((call) => call === tokenB)).toHaveLength(5);
  });
  it('préférence retirée entre deux passages : la destination restante est close sans envoi', async () => {
    await sendPrivate();
    await processPushBatch(worker, scripted({ [tokenA]: ['SENT'], [tokenB]: ['RETRY'] }).sender);
    await pool.query('INSERT INTO drivy.notification_preference(person_id,messaging_private) VALUES($1,false) ON CONFLICT(person_id) DO UPDATE SET messaging_private=false', [id.alice]);
    await due();
    const run = scripted({});
    await processPushBatch(worker, run.sender);
    expect(run.calls).toEqual([]);
    const [row] = await notification();
    expect(row!.status).toBe('SKIPPED');
    expect(await deliveries(row!.id)).toMatchObject({ [tokenA]: { status: 'SENT' }, [tokenB]: { status: 'REVOKED' } });
  });
});
