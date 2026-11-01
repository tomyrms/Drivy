// #77, qualification : le partage de la clé d'un signalement aux appareils des administrateurs, côté serveur.
// PostgreSQL synthétique réel, migrations sous propriétaire non privilégié. Aucun contenu en clair : le serveur ne voit
// que des enveloppes opaques, jamais la clé de session ni le texte signalé.
import { randomUUID } from 'node:crypto';
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
const issuer = 'https://messaging-report-keys.test.invalid';
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
const req = (subject: string, method: Method, target: string, device: string, payload?: object) => app.inject({ method, url: target,
  headers: { authorization: `Bearer ${subject}`, 'x-drivy-expected-person-id': subjects[subject]!, 'x-drivy-expected-access-epoch': '1',
    'x-drivy-device-id': device }, ...(payload ? { payload } : {}) });
const deviceKeys = (person: string, device: string) => ({ user_id: user(person), device_id: device,
  algorithms: ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
  keys: { [`curve25519:${device}`]: `c${device}`, [`ed25519:${device}`]: `e${device}` }, signatures: {} });
const oneTime = (name: string) => ({ [`signed_curve25519:${name}`]: { key: `k${name}`, signatures: {} } });

async function register(subject: string, device: string) {
  const person = subjects[subject]!;
  const response = await req(subject, 'POST', `${crypto}/keys/upload`, device,
    { device_keys: deviceKeys(person, device), one_time_keys: oneTime(`${device}A`) });
  expect(response.statusCode, response.body).toBe(200);
}
/** Ce que le client envoie à un appareil d'administrateur : une enveloppe Olm opaque, jamais la clé de session. */
const keyShare = (marker: string) => ({ algorithm: 'm.olm.v1.curve25519-aes-sha2', sender_key: 'sender', ciphertext: { cadmin: { type: 0, body: marker } } });
const share = (subject: string, device: string, target: string, targetDevice: string, marker: string, txn = randomUUID().slice(0, 12)) =>
  req(subject, 'PUT', `${crypto}/sendToDevice/m.room.encrypted/${txn}`, device,
    { messages: { [user(target)]: { [targetDevice]: keyShare(marker) } } });
const queued = async () => (await pool.query<{ recipient: string; device: string; sender: string }>(
  `SELECT recipient_person_id AS recipient,recipient_device_id AS device,sender_person_id AS sender FROM drivy.messaging_to_device ORDER BY id`)).rows;

beforeAll(async () => { const database = await freshDatabase(); await database.end(); });
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); });
afterAll(async () => { await app.close(); await pool.end(); });

describe('signalements, clé partagée aux appareils des administrateurs', () => {
  it('le signalant réclame une clé à usage unique de l’administrateur puis lui livre la clé de session, que lui seul reçoit', async () => {
    await register('demo-admin', 'ADMINDEVICE1');
    await register('demo-instructor', 'INSTRDEVICE1');
    await register('demo-alice', 'ALICEDEVICE1');

    // Un membre quelconque joint l'appareil de l'administrateur : requête de clés, puis clé à usage unique.
    const query = await req('demo-instructor', 'POST', `${crypto}/keys/query`, 'INSTRDEVICE1', { device_keys: { [user(id.admin)]: [] } });
    expect(query.statusCode, query.body).toBe(200);
    expect(Object.keys(query.json().data.device_keys[user(id.admin)])).toEqual(['ADMINDEVICE1']);
    const claim = await req('demo-instructor', 'POST', `${crypto}/keys/claim`, 'INSTRDEVICE1',
      { one_time_keys: { [user(id.admin)]: { ADMINDEVICE1: 'signed_curve25519' } } });
    expect(claim.statusCode, claim.body).toBe(200);
    expect(Object.keys(claim.json().data.one_time_keys[user(id.admin)].ADMINDEVICE1)).toEqual(['signed_curve25519:ADMINDEVICE1A']);
    // Une clé à usage unique ne sert qu'une fois : la même demande ne la redonne pas.
    const again = await req('demo-instructor', 'POST', `${crypto}/keys/claim`, 'INSTRDEVICE1',
      { one_time_keys: { [user(id.admin)]: { ADMINDEVICE1: 'signed_curve25519' } } });
    expect(again.json().data.one_time_keys).toEqual({});

    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, 'ADMINDEVICE1', 'CLE-DU-SIGNALEMENT')).statusCode).toBe(200);
    expect(await queued()).toEqual([{ recipient: id.admin, device: 'ADMINDEVICE1', sender: id.instructor }]);

    // L'appareil de l'administrateur reçoit exactement ce message, avec le signalant comme expéditeur.
    const sync = await req('demo-admin', 'GET', `${crypto}/sync`, 'ADMINDEVICE1');
    expect(sync.statusCode, sync.body).toBe(200);
    const events = sync.json().data.to_device.events as { type: string; sender: string; content: { ciphertext: { cadmin: { body: string } } } }[];
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ type: 'm.room.encrypted', sender: user(id.instructor) });
    expect(events[0]!.content.ciphertext.cadmin.body).toBe('CLE-DU-SIGNALEMENT');

    // Personne d'autre ne la reçoit : ni l'élève, ni le signalant, ni un autre appareil de l'administrateur.
    for (const [subject, device] of [['demo-alice', 'ALICEDEVICE1'], ['demo-instructor', 'INSTRDEVICE1']] as const) {
      const other = await req(subject, 'GET', `${crypto}/sync`, device);
      expect(other.statusCode, subject).toBe(200);
      expect(other.json().data.to_device.events, subject).toEqual([]);
    }
    await register('demo-admin', 'ADMINDEVICE2');
    const second = await req('demo-admin', 'GET', `${crypto}/sync`, 'ADMINDEVICE2');
    expect(second.json().data.to_device.events).toEqual([]);

    // Le passage du jeton de synchronisation acquitte la livraison : la clé n'est plus conservée côté serveur.
    const next = sync.json().data.next_batch as string;
    const acknowledged = await req('demo-admin', 'GET', `${crypto}/sync?since=${encodeURIComponent(next)}`, 'ADMINDEVICE1');
    expect(acknowledged.json().data.to_device.events).toEqual([]);
    expect(await queued()).toEqual([]);
  });

  it('la file d’un appareil d’administrateur n’est lisible que par lui, même si un autre compte réutilise son identifiant d’appareil', async () => {
    await register('demo-admin', 'ADMINDEVICE1');
    await register('demo-instructor', 'INSTRDEVICE1');
    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, 'ADMINDEVICE1', 'SECRET-ADMIN')).statusCode).toBe(200);
    // Un appareil est celui d'une personne : Alice qui réutilise cet identifiant obtient sa propre file, jamais celle de l'administrateur.
    const reused = await req('demo-alice', 'GET', `${crypto}/sync`, 'ADMINDEVICE1');
    expect(reused.statusCode, reused.body).toBe(200);
    expect(reused.json().data.to_device.events).toEqual([]);
    expect(reused.body).not.toContain('SECRET-ADMIN');
    // La file de l'administrateur est intacte et lui seul la lit.
    expect(await queued()).toEqual([{ recipient: id.admin, device: 'ADMINDEVICE1', sender: id.instructor }]);
    const own = await req('demo-admin', 'GET', `${crypto}/sync`, 'ADMINDEVICE1');
    expect(own.json().data.to_device.events).toHaveLength(1);
  });

  it('un administrateur sans appareil : il est listé comme destinataire, mais rien n’est à réclamer ni à mettre en file', async () => {
    await register('demo-instructor', 'INSTRDEVICE1');
    const recipients = await req('demo-instructor', 'GET', `${crypto}/report-recipients`, 'INSTRDEVICE1');
    expect(recipients.json().data).toEqual({ recipients: [{ personId: id.admin }] });
    const query = await req('demo-instructor', 'POST', `${crypto}/keys/query`, 'INSTRDEVICE1', { device_keys: { [user(id.admin)]: [] } });
    expect(query.statusCode, query.body).toBe(200);
    expect(query.json().data.device_keys[user(id.admin)] ?? {}).toEqual({});
    const claim = await req('demo-instructor', 'POST', `${crypto}/keys/claim`, 'INSTRDEVICE1',
      { one_time_keys: { [user(id.admin)]: { ADMINDEVICE1: 'signed_curve25519' } } });
    expect(claim.statusCode, claim.body).toBe(200);
    expect(claim.json().data.one_time_keys).toEqual({});
    // Envoi à « tous les appareils » d'un administrateur qui n'en a aucun : accepté, mais personne ne reçoit rien.
    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, '*', 'SANS-APPAREIL')).statusCode).toBe(200);
    expect(await queued()).toEqual([]);
  });

  it('un appareil d’administrateur révoqué n’est plus joignable et sa file disparaît', async () => {
    await register('demo-admin', 'ADMINDEVICE1');
    await register('demo-instructor', 'INSTRDEVICE1');
    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, 'ADMINDEVICE1', 'AVANT-REVOCATION')).statusCode).toBe(200);
    expect(await queued()).toHaveLength(1);

    const revoked = await req('demo-admin', 'DELETE', `${crypto}/devices/ADMINDEVICE1`, 'ADMINDEVICE2');
    expect(revoked.statusCode, revoked.body).toBe(200);
    expect(await queued()).toEqual([]);
    const query = await req('demo-instructor', 'POST', `${crypto}/keys/query`, 'INSTRDEVICE1', { device_keys: { [user(id.admin)]: [] } });
    expect(query.json().data.device_keys[user(id.admin)] ?? {}).toEqual({});
    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, 'ADMINDEVICE1', 'APRES-REVOCATION')).statusCode).toBe(200);
    expect(await queued()).toEqual([]);
    expect((await req('demo-admin', 'GET', `${crypto}/sync`, 'ADMINDEVICE1')).statusCode).toBe(403);
  });

  it('un administrateur retiré de l’école n’est plus destinataire : ni liste, ni clés, ni file', async () => {
    await register('demo-admin', 'ADMINDEVICE1');
    await register('demo-instructor', 'INSTRDEVICE1');
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1", [id.adminMember]);
    const recipients = await req('demo-instructor', 'GET', `${crypto}/report-recipients`, 'INSTRDEVICE1');
    expect(recipients.json().data).toEqual({ recipients: [] });
    const query = await req('demo-instructor', 'POST', `${crypto}/keys/query`, 'INSTRDEVICE1', { device_keys: { [user(id.admin)]: [] } });
    expect(query.json().data.device_keys[user(id.admin)] ?? {}).toEqual({});
    expect((await share('demo-instructor', 'INSTRDEVICE1', id.admin, 'ADMINDEVICE1', 'RETIRE')).statusCode).toBe(200);
    expect(await queued()).toEqual([]);
  });

  it('un administrateur d’une autre école n’est pas destinataire : ni listé, ni joignable, ni servi', async () => {
    // Le moniteur administre l'école B, pas l'école A. Bob n'a aucun lien avec lui : ses clés restent hors de portée.
    await register('demo-instructor', 'INSTRDEVICE1');
    await register('demo-bob', 'BOBDEVICE001');
    const recipients = await req('demo-bob', 'GET', `${crypto}/report-recipients`, 'BOBDEVICE001');
    expect((recipients.json().data.recipients as { personId: string }[]).map(r => r.personId)).toEqual([id.admin]);
    const query = await req('demo-bob', 'POST', `${crypto}/keys/query`, 'BOBDEVICE001', { device_keys: { [user(id.instructor)]: [] } });
    expect(query.json().data.device_keys[user(id.instructor)] ?? {}).toEqual({});
    expect((await share('demo-bob', 'BOBDEVICE001', id.instructor, 'INSTRDEVICE1', 'PAS-UN-ADMIN')).statusCode).toBe(200);
    expect(await queued()).toEqual([]);
  });
});
