import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { Pool } from 'pg';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { processPushBatch, type PushSender } from '../src/course-push.js';
import { freshDatabase, harness, id, type Call } from './support/harness.js';

/**
 * #120/#74 : révocation d'un appareil push sans jeton d'accès. Vraie PostgreSQL, routes réelles, données synthétiques.
 * Le secret n'est rendu qu'à l'enregistrement ; la base n'en garde que l'empreinte. L'envoi APNs est remplacé par un
 * collecteur local : aucune livraison réelle n'est revendiquée.
 */
let pool: Pool, worker: Pool, call: Call, app: Awaited<ReturnType<typeof harness>>['app'];
const lines: string[] = [];
beforeEach(async () => {
  lines.length = 0;
  pool = await freshDatabase();
  ({ call, app } = await harness(pool, { logger: { level: 'info', stream: { write: (line: string) => { lines.push(line); } } } }));
  worker = new Pool({ connectionString: process.env.TEST_DATABASE_URL, options: '-c role=drivy_harness_migrator' });
});
afterEach(async () => { await app?.close(); await worker?.end(); await pool?.end(); });

const newToken = () => randomUUID().replace(/-/g, '').repeat(2);
async function register(subject: string, token = newToken()) {
  const response = await call('PUT', '/v1/me/push-devices', { token, environment: 'SANDBOX' } as never, null, subject);
  expect(response.statusCode, response.body).toBe(200);
  const body = response.json() as { data: { registered: boolean; revocationSecret: string } };
  return { token, secret: body.data.revocationSecret, body };
}
const anonymous = (token: string, revocationSecret: string) => app.inject({ method: 'POST', url: '/v1/push-devices/revoke',
  headers: { 'content-type': 'application/json' }, payload: { token, revocationSecret } });
const revokedAt = async (token: string) => (await pool.query<{ revoked_at: Date | null }>(
  'SELECT revoked_at FROM drivy.push_device WHERE token=$1', [token])).rows[0]?.revoked_at ?? null;
const digestOf = async (token: string) => (await pool.query<{ revocation_digest: Buffer }>(
  'SELECT revocation_digest FROM drivy.push_device WHERE token=$1', [token])).rows[0]?.revocation_digest;

/** Validateur du contrat d'extension apps/api/contracts, chargé une fois par test concerné. */
async function contractSchema(name: string) {
  const document = JSON.parse(await readFile(new URL('../contracts/push-device-revocation.json', import.meta.url), 'utf8')) as
    { $id: string; $defs: Record<string, object> };
  const ajv = new Ajv2020({ strict: false, allErrors: true });
  ajv.addSchema(document);
  const validate = ajv.getSchema(`${document.$id}#/$defs/${name}`);
  expect(validate, name).toBeDefined();
  return validate!;
}

describe('secret de révocation propre à l’appareil', () => {
  it('rendu une seule fois, seule son empreinte est en base, un nouvel enregistrement la remplace', async () => {
    const registration = await register('demo-alice');
    expect(registration.secret).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(registration.body.data).toEqual({ registered: true, revocationSecret: registration.secret });
    // Le contrôle contractuel est fait par le schéma du contrat, pas par une forme devinée.
    const validateRegistration = await contractSchema('PushDeviceRegistration');
    expect(validateRegistration(registration.body), JSON.stringify(validateRegistration.errors)).toBe(true);

    const digest = await digestOf(registration.token);
    expect(digest).toHaveLength(32);
    expect(digest!.equals(createHash('sha256').update(registration.secret).digest())).toBe(true);
    const row = (await pool.query<{ row: string }>('SELECT to_jsonb(d)::text AS row FROM drivy.push_device d WHERE token=$1',
      [registration.token])).rows[0]!.row;
    expect(row).not.toContain(registration.secret);

    // Un nouvel enregistrement du même jeton émet un autre secret et n'en garde que la nouvelle empreinte.
    const renewed = await register('demo-alice', registration.token);
    expect(renewed.secret).not.toBe(registration.secret);
    const renewedDigest = await digestOf(registration.token);
    expect(renewedDigest!.equals(createHash('sha256').update(renewed.secret).digest())).toBe(true);
    expect(renewedDigest!.equals(digest!)).toBe(false);

    // Le rôle applicatif ne peut pas relire l'empreinte.
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_app');
      await db.query("SELECT set_config('app.person_id',$1,true)", [id.alice]);
      await expect(db.query('SELECT revocation_digest FROM drivy.push_device')).rejects.toMatchObject({ code: '42501' });
    } finally { await db.query('ROLLBACK'); db.release(); }
  });
});

describe('route anonyme de révocation', () => {
  it('bon secret : la ligne est révoquée et ce jeton ne reçoit plus aucune alerte', async () => {
    const registration = await register('demo-alice');
    const response = await anonymous(registration.token, registration.secret);
    expect(response.statusCode, response.body).toBe(200);
    expect(response.json().data).toEqual({ revoked: true });
    const validateRevoked = await contractSchema('PushDeviceAnonymousRevocation');
    expect(validateRevoked(response.json()), JSON.stringify(validateRevoked.errors)).toBe(true);
    expect(await revokedAt(registration.token)).not.toBeNull();

    // Une alerte mise en file après la révocation n'est plus adressée à ce jeton.
    await pool.query(`INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body)
      VALUES($1,$2,'CHANGE','revocation:anonymous','Titre synthétique','')`, [id.alice, id.schoolA]);
    const delivered: string[] = [];
    const sender: PushSender = { send: async token => { delivered.push(token); return 'SENT'; }, close() {} };
    await processPushBatch(worker, sender);
    expect(delivered).not.toContain(registration.token);
    expect((await pool.query("SELECT status,failure_code FROM drivy.push_notification WHERE dedupe_key='revocation:anonymous'")).rows[0])
      .toMatchObject({ status: 'SKIPPED', failure_code: 'NO_DEVICE' });
  });

  it('mauvais secret, jeton inconnu ou secret d’un autre jeton : même réponse, rien n’est révoqué', async () => {
    const alice = await register('demo-alice');
    const bob = await register('demo-bob');
    const responses = await Promise.all([
      anonymous(alice.token, 'A'.repeat(43)),
      anonymous(newToken(), alice.secret),
      anonymous(alice.token, bob.secret),
    ]);
    for (const response of responses) {
      expect(response.statusCode, response.body).toBe(200);
      expect(response.json().data).toEqual({ revoked: true });
    }
    expect(await revokedAt(alice.token)).toBeNull();
    expect(await revokedAt(bob.token)).toBeNull();
  });

  it('le secret d’avant une reprise par un autre compte ne révoque plus rien', async () => {
    const first = await register('demo-alice');
    const second = await register('demo-bob', first.token);
    expect(second.secret).not.toBe(first.secret);
    expect((await anonymous(first.token, first.secret)).statusCode).toBe(200);
    expect(await revokedAt(first.token)).toBeNull();
    expect((await anonymous(first.token, second.secret)).statusCode).toBe(200);
    expect(await revokedAt(first.token)).not.toBeNull();
  });
});

describe('limitation de fréquence de la route anonyme', () => {
  it('par jeton : la onzième tentative refusée est un 429', async () => {
    const token = newToken();
    for (let attempt = 0; attempt < 10; attempt++) {
      expect((await anonymous(token, `wrong-${attempt}`)).statusCode).toBe(200);
    }
    const limited = await anonymous(token, 'wrong-again');
    expect(limited.statusCode).toBe(429);
    expect(limited.json()).toMatchObject({ code: 'PUSH_REVOCATION_ATTEMPTS', status: 429 });
  });

  it('par IP : la trente-et-unième tentative refusée est un 429, même avec des jetons distincts', async () => {
    for (let attempt = 0; attempt < 30; attempt++) {
      expect((await anonymous(newToken(), `wrong-${attempt}`)).statusCode).toBe(200);
    }
    const limited = await anonymous(newToken(), 'wrong-again');
    expect(limited.statusCode).toBe(429);
    expect(limited.json()).toMatchObject({ code: 'PUSH_REVOCATION_ATTEMPTS', status: 429 });
  });
});

describe('journaux et route authentifiée', () => {
  it('aucun jeton ni secret dans les journaux capturés', async () => {
    const registration = await register('demo-alice');
    await anonymous(registration.token, registration.secret);
    await anonymous(registration.token, 'A'.repeat(43));
    const output = lines.join('\n');
    expect(output).not.toContain(registration.token);
    expect(output).not.toContain(registration.secret);
  });

  it('la route authentifiée existante révoque toujours son propre appareil et le réenregistrement le réactive', async () => {
    const registration = await register('demo-alice');
    expect((await call('POST', '/v1/me/push-devices/revoke', { token: registration.token }, null, 'demo-alice')).json().data)
      .toEqual({ revoked: true });
    expect(await revokedAt(registration.token)).not.toBeNull();
    // Un autre compte ne révoque pas cet appareil : la route reste bornée au propriétaire.
    const bob = await register('demo-bob');
    expect((await call('POST', '/v1/me/push-devices/revoke', { token: bob.token }, null, 'demo-alice')).statusCode).toBe(200);
    expect(await revokedAt(bob.token)).toBeNull();
    // Un nouvel enregistrement efface la révocation et émet un nouveau secret.
    const renewed = await register('demo-alice', registration.token);
    expect(await revokedAt(registration.token)).toBeNull();
    expect(renewed.secret).not.toBe(registration.secret);
  });
});
