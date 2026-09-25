import { afterEach, describe, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { createSchoolGateway, type SchoolGateway, type SchoolRequest } from '../server/upstream.js';
import { matchSchoolRoute, schoolRoutes } from '../server/school-routes.js';

const config = {origin:'https://drivy.example',apiBaseURL:'https://drivy.example/refonte',issuer:'https://identity.example/realm',
  clientId:'drivy-web',clientSecret:randomBytes(32).toString('hex'),development:false,host:'127.0.0.1',port:3002};
const secret = () => randomBytes(32).toString('base64url');
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); });
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-09-25T08:00:00.000Z' });

async function harness(schoolGateway: SchoolGateway) {
  const now = Date.now();
  const tokens: Tokens = { accessToken: secret(), refreshToken: secret(), expiresAt: now + 300_000,
    principal: { subject: randomUUID(), displayName: 'Test local', email: 'test@example.test', emailVerified: true } };
  const identity: IdentityProvider = {
    begin: vi.fn(async () => ({ transaction: { state: secret(), nonce: secret(), verifier: secret(), expiresAt: now + 300_000 }, url: 'https://identity.example/auth' })),
    complete: vi.fn(async () => tokens), refresh: vi.fn(async () => tokens), revoke: vi.fn(async () => {}),
  };
  const store = new SessionStore();
  const app = await buildWebApp({ config, identity, store, schoolGateway, gateway: vi.fn(async () => ({ status: 200, body: {} })) });
  apps.push(app);
  let cookie = ''; let csrf = '';
  const cookieFrom = (set: unknown) => (Array.isArray(set) ? set[0] : set)?.toString().split(';')[0] ?? '';
  cookie = cookieFrom((await app.inject({ url: '/app/bff/session' })).headers['set-cookie']);
  csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
  const login = async (returnTo?: string) => {
    const started = await app.inject({ method: 'POST', url: '/app/bff/login', payload: returnTo ? { returnTo } : {}, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf } });
    if (started.statusCode !== 200) return started;
    const state = store.get(cookie.split('=')[1])!.login!.state;
    const callback = await app.inject({ url: `/app/bff/callback?code=one&state=${state}`, headers: { cookie } });
    cookie = cookieFrom(callback.headers['set-cookie']);
    csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
    return callback;
  };
  const write = (method: 'POST' | 'PATCH' | 'PUT', url: string, payload: Record<string, unknown>, headers: Record<string, string> = {}) =>
    app.inject({ method, url, payload, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf, ...headers } });
  return { app, store, tokens, login, write, get: (url: string) => app.inject({ url, headers: { cookie } }),
    cookie: () => cookie, csrf: () => csrf };
}

const school = randomUUID();

describe('Liste blanche des routes de gestion', () => {
  test('ne relaie que les couples méthode + chemin déclarés', () => {
    expect(matchSchoolRoute('GET', `/schools/${school}`, '')?.path).toBe(`/v1/schools/${school}`);
    expect(matchSchoolRoute('PATCH', `/schools/${school}/members/${school}`, '')?.route.ifMatch).toBe(true);
    expect(matchSchoolRoute('GET', `/schools/${school}/offerings`, '?limit=100&cursor=abc_-1')?.query).toBe('?limit=100&cursor=abc_-1');
    for (const [method, path, search] of [
      ['GET', `/schools/${school}/learners`, ''],
      ['DELETE', `/schools/${school}`, ''],
      ['PATCH', `/schools/${school}/offerings`, ''],
      ['POST', `/schools/${school}/lessons`, ''],
      ['GET', `/schools/not-a-uuid`, ''],
      ['GET', `/schools/${school}/../me`, ''],
      ['GET', `/schools/${school}/%2e%2e/me`, ''],
      ['GET', `/schools/${school}//setup`, ''],
      ['GET', `/schools/${school}/operations/1`, ''],
      ['GET', `/schools/${school}/offerings`, '?q=secret'],
      ['GET', `/schools/${school}/offerings`, '?limit=1&limit=2'],
      ['GET', `/schools/${school}/offerings`, '?limit=500'],
      ['GET', `/schools/${school}/setup`, '?limit=5'],
    ] as const) expect(matchSchoolRoute(method, path, search), `${method} ${path}${search}`).toBeUndefined();
    // Every declared write carries a body limit; reads never do.
    for (const route of schoolRoutes) expect(route.method === 'GET' ? route.bodyLimit === undefined : (route.bodyLimit ?? 0) > 0).toBe(true);
  });

  test('un chemin hors liste ne consomme jamais le jeton de la session', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway); await h.login();
    for (const url of [`/app/bff/schools/${school}/learners`, `/app/bff/schools/${school}/trainings`, `/app/bff/schools/x/setup`,
      `/app/bff/schools/${school}/offerings?q=1`, `/app/bff/schools/${school}/captures`]) {
      expect((await h.get(url)).statusCode, url).toBe(404);
    }
    expect((await h.app.inject({ method: 'DELETE', url: `/app/bff/schools/${school}`, headers: { cookie: h.cookie() } })).statusCode).toBe(404);
    expect(gateway).not.toHaveBeenCalled();
  });

  test('une lecture exige la session et renvoie l’ETag de la version, sans cache', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({ id: school, version: 4 }), etag: '"4"' }));
    const h = await harness(gateway);
    expect((await h.get(`/app/bff/schools/${school}`)).statusCode).toBe(401);
    await h.login();
    const response = await h.get(`/app/bff/schools/${school}/offerings?limit=100`);
    expect(response.statusCode).toBe(200);
    expect(response.headers.etag).toBe('"4"');
    expect(response.headers['cache-control']).toBe('no-store');
    expect(gateway).toHaveBeenCalledWith({ method: 'GET', path: `/v1/schools/${school}/offerings`, query: '?limit=100' }, h.tokens.accessToken);
    expect(response.body).not.toContain(h.tokens.accessToken);
  });
});

describe('Écritures de gestion', () => {
  const operationId = randomUUID();
  const body = { operationId, name: 'École synthétique', timeZone: 'Europe/Zurich', contactEmail: 'ecole@example.test', impactConfirmed: true };

  test.each([
    ['sans jeton CSRF', { 'x-csrf-token': '' }],
    ['jeton CSRF étranger', { 'x-csrf-token': 'x'.repeat(43) }],
    ['origine étrangère', { origin: 'https://evil.example' }],
  ])('refuse une écriture %s avant tout appel amont', async (_label, headers) => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway); await h.login();
    const response = await h.write('PATCH', `/app/bff/schools/${school}`, body, { 'idempotency-key': operationId, 'if-match': '"3"', ...headers });
    expect(response.statusCode).toBe(403);
    expect(gateway).not.toHaveBeenCalled();
  });

  test('refuse un corps non JSON même avec le bon jeton CSRF', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway); await h.login();
    const response = await h.app.inject({ method: 'POST', url: `/app/bff/schools/${school}/offerings`, payload: 'operationId=1',
      headers: { cookie: h.cookie(), origin: config.origin, 'x-csrf-token': h.csrf(), 'content-type': 'application/x-www-form-urlencoded', 'idempotency-key': operationId } });
    expect([403, 415]).toContain(response.statusCode);
    expect(gateway).not.toHaveBeenCalled();
  });

  test('transmet Idempotency-Key et If-Match à l’identique puis renvoie l’ETag confirmé', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({ id: school, version: 4 }), etag: '"4"' }));
    const h = await harness(gateway); await h.login();
    const response = await h.write('PATCH', `/app/bff/schools/${school}`, body, { 'idempotency-key': operationId, 'if-match': '"3"' });
    expect(response.statusCode).toBe(200);
    expect(response.headers.etag).toBe('"4"');
    expect(gateway).toHaveBeenCalledTimes(1);
    const [sent, token] = gateway.mock.calls[0]!;
    expect(sent).toEqual({ method: 'PATCH', path: `/v1/schools/${school}`, query: '', body, idempotencyKey: operationId, ifMatch: '"3"' } satisfies SchoolRequest);
    expect(token).toBe(h.tokens.accessToken);
  });

  test('une création sans If-Match reste sans version ; une clé différente de operationId est refusée', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 201, body: envelope({ version: 1 }), etag: '"1"' }));
    const h = await harness(gateway); await h.login();
    const offer = { operationId, offeringKey: 'b-standard' };
    expect((await h.write('POST', `/app/bff/schools/${school}/offerings`, offer, { 'idempotency-key': randomUUID() })).statusCode).toBe(400);
    expect((await h.write('POST', `/app/bff/schools/${school}/offerings`, offer)).statusCode).toBe(400);
    expect((await h.write('POST', `/app/bff/schools/${school}/offerings`, offer, { 'idempotency-key': operationId, 'if-match': '"1"' })).statusCode).toBe(400);
    expect(gateway).not.toHaveBeenCalled();
    const created = await h.write('POST', `/app/bff/schools/${school}/offerings`, offer, { 'idempotency-key': operationId.toUpperCase() });
    expect(created.statusCode).toBe(201);
    expect(gateway.mock.calls[0]![0].ifMatch).toBeUndefined();
    expect(gateway.mock.calls[0]![0].idempotencyKey).toBe(operationId.toUpperCase());
  });

  test('If-Match est exigé et strict sur les commandes versionnées', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway); await h.login();
    const url = `/app/bff/schools/${school}/invitations/${randomUUID()}/revoke`;
    const revoke = { operationId, reason: 'Adresse erronée' };
    expect((await h.write('POST', url, revoke, { 'idempotency-key': operationId })).statusCode).toBe(428);
    for (const version of ['3', 'W/"3"', '"0"', '"3", "4"', '*']) {
      expect((await h.write('POST', url, revoke, { 'idempotency-key': operationId, 'if-match': version })).statusCode, version).toBe(400);
    }
    expect(gateway).not.toHaveBeenCalled();
  });

  test('un corps au-delà de la limite de la route est refusé', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway); await h.login();
    const response = await h.write('POST', `/app/bff/schools/${school}/invitations`, { operationId, email: `${'a'.repeat(3000)}@example.test`, roles: ['LEARNER'] },
      { 'idempotency-key': operationId });
    expect(response.statusCode).toBe(413);
    expect(gateway).not.toHaveBeenCalled();
  });

  test('un refus métier garde son code sans refléter le détail amont', async () => {
    const leaked = secret();
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 412, body: { code: 'VERSION_CONFLICT', title: leaked, detail: leaked } }));
    const h = await harness(gateway); await h.login();
    const response = await h.write('PATCH', `/app/bff/schools/${school}`, body, { 'idempotency-key': operationId, 'if-match': '"3"' });
    expect(response.statusCode).toBe(412);
    expect(response.json().code).toBe('VERSION_CONFLICT');
    expect(response.body).not.toContain(leaked);
    expect(response.headers.etag).toBeUndefined();
  });

  test('REAUTH_REQUIRED conserve la session ; un autre 401 amont la détruit', async () => {
    let status = { status: 401, body: { code: 'REAUTH_REQUIRED' } };
    const gateway = vi.fn<SchoolGateway>(async () => status);
    const h = await harness(gateway); await h.login();
    const url = `/app/bff/schools/${school}/members/${randomUUID()}`;
    const member = { operationId, roles: ['ADMIN'], grants: [], reason: 'Réorganisation' };
    const first = await h.write('PATCH', url, member, { 'idempotency-key': operationId, 'if-match': '"2"' });
    expect(first.statusCode).toBe(401); expect(first.json().code).toBe('REAUTH_REQUIRED');
    expect((await h.get('/app/bff/session')).json().authenticated).toBe(true);
    status = { status: 401, body: { code: 'UNAUTHORIZED' } };
    expect((await h.write('PATCH', url, member, { 'idempotency-key': operationId, 'if-match': '"2"' })).json().code).toBe('SESSION_EXPIRED');
    expect((await h.get('/app/bff/session')).json().authenticated).toBe(false);
  });

  test('une réponse amont perdue devient 503 : le navigateur garde la même demande', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => { throw new Error('connexion interrompue après commit'); });
    const h = await harness(gateway); await h.login();
    const response = await h.write('PATCH', `/app/bff/schools/${school}`, body, { 'idempotency-key': operationId, 'if-match': '"3"' });
    expect(response.statusCode).toBe(503);
    expect(response.json().code).toBe('SERVICE_UNAVAILABLE');
  });
});

describe('Retour vers la gestion après connexion', () => {
  test('accepte seulement une page de gestion de la même origine', async () => {
    const h = await harness(vi.fn<SchoolGateway>());
    for (const returnTo of ['https://evil.example/app/gestion', '//evil.example', '/app/bff/logout', '/app/gestion/../bff']) {
      expect((await h.login(returnTo)).statusCode, returnTo).toBe(400);
    }
    const callback = await h.login(`/app/gestion/${school}/offres`);
    expect(callback.headers.location).toBe(`/app/gestion/${school}/offres`);
  });
});

test('échange HTTP réel : méthode, Bearer, Idempotency-Key, If-Match et ETag, sans cookie ni redirection', async () => {
  const api = Fastify({ logger: false });
  const access = secret(); const operationId = randomUUID(); let seen = false;
  api.patch('/refonte/v1/schools/:schoolId/members/:memberId', async (request, reply) => {
    expect(request.headers.authorization).toBe(`Bearer ${access}`);
    expect(request.headers['idempotency-key']).toBe(operationId);
    expect(request.headers['if-match']).toBe('"7"');
    expect(request.headers.cookie).toBeUndefined();
    expect((request.body as { operationId: string }).operationId).toBe(operationId);
    seen = true;
    return reply.code(200).header('ETag', '"8"').send(envelope({ version: 8 }));
  });
  api.get('/refonte/v1/schools/:schoolId/setup', async (_request, reply) => reply.header('ETag', 'W/"weak"').send(envelope({})));
  api.get('/refonte/v1/schools/:schoolId/readiness', async (_request, reply) => reply.redirect('/refonte/v1/me'));
  try {
    const origin = await api.listen({ host: '127.0.0.1', port: 0 });
    const gateway = createSchoolGateway(origin + '/refonte');
    const member = randomUUID();
    const result = await gateway({ method: 'PATCH', path: `/v1/schools/${school}/members/${member}`, query: '',
      body: { operationId, roles: ['ADMIN'], grants: [], reason: 'Test' }, idempotencyKey: operationId, ifMatch: '"7"' }, access);
    expect(result).toMatchObject({ status: 200, etag: '"8"' }); expect(seen).toBe(true);
    expect((await gateway({ method: 'GET', path: `/v1/schools/${school}/setup`, query: '' }, access)).etag).toBeUndefined();
    await expect(gateway({ method: 'GET', path: `/v1/schools/${school}/readiness`, query: '' }, access)).rejects.toThrow();
    await expect(gateway({ method: 'GET', path: `/v1/schools/${school}/learners`, query: '' }, access)).rejects.toThrow();
    await expect(gateway({ method: 'GET', path: '/v1/me', query: '' }, access)).rejects.toThrow();
    await expect(gateway({ method: 'POST', path: `/v1/schools/${school}/offerings`, query: '', body: {} }, access)).rejects.toThrow();
  } finally { await api.close(); }
});
