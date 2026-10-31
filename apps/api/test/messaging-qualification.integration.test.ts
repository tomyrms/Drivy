import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import type { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import { createTokenVerifier } from '../src/auth.js';
import { readConfig } from '../src/config.js';
import { freshDatabase, issuer, id } from './support/harness.js';
import { seedFixtures } from '../scripts/fixtures.js';

const env = { NODE_ENV: 'production', DATABASE_URL: 'postgresql://localhost/drivy_test', OIDC_ISSUER: issuer,
  OIDC_AUDIENCE: 'drivy-api', OIDC_JWKS_URL: `${issuer}/jwks`, CURSOR_SECRET: 'synthetic-secret-at-least-32-characters' };
describe('configuration qualification fermée', () => {
  it('désactive par défaut et normalise les écoles explicites', () => {
    expect(readConfig(env)).toMatchObject({ MESSAGING_MODE: 'disabled', MESSAGING_QUALIFICATION_SCHOOL_IDS: [] });
    expect(readConfig({ ...env, MESSAGING_MODE: 'qualification', MESSAGING_QUALIFICATION_SCHOOL_IDS: ` ${id.schoolA},${id.schoolA} ` }))
      .toMatchObject({ MESSAGING_MODE: 'qualification', MESSAGING_QUALIFICATION_SCHOOL_IDS: [id.schoolA] });
  });
  it.each([
    { MESSAGING_MODE: 'test-synthetic' }, { MESSAGING_MODE: 'enabled' },
    { MESSAGING_MODE: 'qualification' }, { MESSAGING_MODE: 'qualification', MESSAGING_QUALIFICATION_SCHOOL_IDS: '*' },
    { MESSAGING_MODE: 'qualification', MESSAGING_QUALIFICATION_SCHOOL_IDS: `${id.schoolA},` },
    { MESSAGING_QUALIFICATION_SCHOOL_IDS: 'invalid' }
  ])('refuse configuration ouverte ou ambiguë %j', input => expect(() => readConfig({ ...env, ...input })).toThrow());
});

let pool: Pool;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let app: ReturnType<typeof buildApp>;
let connects = 0;
const token = (subject = 'demo-admin', audience = 'drivy-api', expiration: string | number = '5m') => new SignJWT({})
  .setProtectedHeader({ alg: 'RS256', kid: 'qualification' }).setIssuer(issuer).setAudience(audience)
  .setSubject(subject).setIssuedAt().setExpirationTime(expiration).sign(keys.privateKey);
const path = (school = id.schoolA) => `/v1/schools/${school}/messaging`;
async function request(route: string, options: { school?: string; actor?: string; epoch?: string; authorization?: string; method?: 'GET' | 'PUT' | 'POST'; payload?: object } = {}) {
  return app.inject({ method: options.method ?? 'GET', url: path(options.school as typeof id.schoolA | undefined) + route,
    ...(options.payload ? { payload: options.payload } : {}),
    headers: { authorization: options.authorization ?? `Bearer ${await token()}`, 'x-drivy-expected-person-id': options.actor ?? id.admin,
      'x-drivy-expected-access-epoch': options.epoch ?? '1', 'x-drivy-device-id': 'QUALIFICATIONDEVICE' } });
}
beforeAll(async () => {
  pool = await freshDatabase();
  keys = await generateKeyPair('RS256');
  const publicKey = await exportJWK(keys.publicKey);
  const verifyToken = createTokenVerifier({ OIDC_ISSUER: issuer, OIDC_AUDIENCE: 'drivy-api', OIDC_JWKS_URL: `${issuer}/jwks` },
    createLocalJWKSet({ keys: [{ ...publicKey, kid: 'qualification', alg: 'RS256' }] }));
  vi.stubEnv('NODE_ENV', 'production');
  const countedPool = { connect: async () => { connects++; return pool.connect(); } } as unknown as Pool;
  app = buildApp({ pool: countedPool, verifyToken, cursorSecret: env.CURSOR_SECRET,
    ...{ messaging: { mode: 'qualification' as const, schoolIds: [id.schoolA] } } });
});
beforeEach(async () => { await pool.query('TRUNCATE drivy.person,drivy.school CASCADE'); await seedFixtures(pool, issuer); connects = 0; });
afterAll(async () => { await app?.close(); await pool?.end(); vi.unstubAllEnvs(); });
describe('composition réelle de qualification avec JWT signés et PostgreSQL', () => {
  it('ouvre messages et relais seulement dans école autorisée sous NODE_ENV production', async () => {
    const messages = await request('/conversations');
    expect(messages.statusCode, messages.body).toBe(200);
    const crypto = await request('/crypto/devices');
    expect(crypto.statusCode, crypto.body).toBe(200);
    expect(messages.headers['cache-control']).toBe('no-store');
    const general = await request('/general', { method: 'PUT' });
    expect(general.statusCode, general.body).toBe(200);
    const conversation = general.json().data.conversationId;
    const members = await request(`/conversations/${conversation}/members`);
    const sent = await request(`/conversations/${conversation}/messages`, { method: 'POST', payload: {
      clientMessageId: randomUUID(), expectedMembersEpoch: members.json().data.membersEpoch,
      ciphertext: { scheme: 'synthetic', keyId: 'qualification-fixture', payload: 'AAAA' }
    } });
    expect(sent.statusCode, sent.body).toBe(200);
    expect((await pool.query('SELECT id FROM drivy.messaging_message WHERE id=$1', [sent.json().data.id])).rowCount).toBe(1);
  });
  it('refuse école hors liste avant connexion base pour messages et clés', async () => {
    for (const route of ['/conversations', '/crypto/devices']) {
      const result = await request(route, { school: id.schoolB });
      expect(result.statusCode, result.body).toBe(503);
      expect(result.json().code).toBe('MESSAGING_NOT_ENABLED');
    }
    expect(connects).toBe(0);
  });
  it('#77 : signalements, statut et destinataires restent fermés hors liste, ouverts dans l’école listée', async () => {
    const report = randomUUID();
    const status = { method: 'PUT' as const, payload: { status: 'HANDLED', expectedStatus: 'OPEN' } };
    for (const [route, options] of [['/reports', {}], [`/reports/${report}/status`, status], ['/crypto/report-recipients', {}]] as const) {
      const closed = await request(route, { ...options, school: id.schoolB });
      expect(closed.statusCode, route).toBe(503);
      expect(closed.json().code, route).toBe('MESSAGING_NOT_ENABLED');
    }
    expect(connects).toBe(0);
    expect((await request('/reports')).statusCode).toBe(200);
    expect((await request('/crypto/report-recipients')).json().data.recipients).toEqual([{ personId: id.admin }]);
    expect((await request(`/reports/${report}/status`, status)).statusCode).toBe(404);
  });
  it('vérifie réellement signature, audience, expiration et absence de token', async () => {
    const valid = await token();
    const parts = valid.split('.'); parts[1] = Buffer.from('{"sub":"demo-admin"}').toString('base64url');
    for (const authorization of ['', 'Bearer synthetic-admin', `Bearer ${parts.join('.')}`, `Bearer ${await token('demo-admin', 'wrong')}`, `Bearer ${await token('demo-admin', 'drivy-api', 1)}`]) {
      for (const route of ['/conversations', '/crypto/devices']) expect((await request(route, { authorization })).statusCode).toBe(401);
    }
    expect(connects).toBe(0);
  });
  it('ne fait confiance ni à acteur ni à epoch fournis par client', async () => {
    for (const route of ['/conversations', '/crypto/devices']) {
      expect((await request(route, { actor: id.alice })).statusCode).toBe(403);
      expect((await request(route, { epoch: '99' })).statusCode).toBe(403);
      expect((await request(route, { authorization: `Bearer ${await token('unknown-person')}` })).statusCode).toBe(403);
    }
  });
  it('relit révocation appartenance en base pour messages et relais', async () => {
    expect((await request('/conversations')).statusCode).toBe(200);
    await pool.query("UPDATE drivy.membership SET status='REVOKED' WHERE id=$1", [id.adminMember]);
    for (const route of ['/conversations', '/crypto/devices']) expect((await request(route)).statusCode).toBe(403);
  });
});
