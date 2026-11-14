import { afterEach, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { allowedPlatformRequest, type PlatformGateway, type PlatformRequest } from '../server/platform-routes.js';
import { createPlatformGateway } from '../server/upstream.js';

// R01-T03 : offres, catalogue de modules et droits d'une école cliente, côté relais web. Aucune donnée réelle : tout est synthétique.
// Écrits sans être exécutés (règle du porteur : aucun test avant la fin de l'epic).
const config = { origin: 'https://drivy.example.invalid', apiBaseURL: 'https://drivy.example.invalid/refonte', issuer: 'https://identity.example.invalid/realm',
  clientId: 'drivy-web', clientSecret: randomBytes(32).toString('hex'), development: false, host: '127.0.0.1', port: 3002 };
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); vi.unstubAllGlobals(); });
const secret = () => randomBytes(32).toString('base64url');
const iso = (offsetDays = 0) => new Date(Date.now() + offsetDays * 86_400_000).toISOString();
const key = randomUUID();
const moduleCodes = ['MESSAGING', 'COLLECTIVE_COURSES'];

const offer =(extra: Record<string, unknown> = {}) => ({ id: randomUUID(), name: 'Offre complète', modules: moduleCodes, status: 'ACTIVE', version: 1, createdAt: iso(), updatedAt: iso(),
  archivedAt: null, schoolsInForce: 0, ...extra });
const entitlements = (extra: Record<string, unknown> = {}) => ({ state: 'NOT_CONFIGURED', offer: null, scheduledOffer: null,
  modules: moduleCodes.map(code => ({ code, inOffer: false, entitled: true, adjustment: null })), assignments: [], adjustments: [], version: 1, nextChangeAt: null, ...extra });
const consequences = (extra: Record<string, unknown> = {}) => ({ offer: { id: randomUUID(), name: 'Messagerie seule', modules: ['MESSAGING'] }, effectiveAt: null, immediate: true,
  replacesScheduled: null, endingAdjustments: [], modules: [{ code: 'MESSAGING', before: true, after: true, kind: 'KEEPS', existing: null },
    { code: 'COLLECTIVE_COURSES', before: true, after: false, kind: 'LOSES', existing: { publishedSeries: 2, activeEnrollments: 1, upcomingSessions: 0 } }], version: 1, ...extra });

async function harness(platformGateway: PlatformGateway) {
  const now = Date.now(), store = new SessionStore();
  const tokens = (): Tokens => ({ accessToken: secret(), expiresAt: now + 300_000, principal: { subject: 'synthetic-operator-account', displayName: 'Opérateur synthétique', email: 'o@example.invalid', emailVerified: true } });
  const identity: IdentityProvider = { begin: vi.fn(async () => ({ transaction: { state: secret(), nonce: secret(), verifier: secret(), expiresAt: now + 300_000 }, url: 'https://identity.example.invalid/auth' })),
    complete: vi.fn(async () => tokens()), password: vi.fn(async () => tokens()), refresh: vi.fn(async () => tokens()), revoke: vi.fn(async () => {}) };
  const gateway = vi.fn(async () => ({ status: 403, body: { code: 'IDENTITY_NOT_LINKED' } }));
  const app = await buildWebApp({ config, identity, store, platformGateway, gateway }); apps.push(app);
  let cookie = '', csrf = (await app.inject({ url: '/app/bff/session' })).json().csrfToken as string;
  const cookieFrom = (value: unknown) => (Array.isArray(value) ? value[0] : value)?.toString().split(';')[0] ?? '';
  const post = async (path: string, body: unknown, extra: Record<string, string> = {}) => {
    const response = await app.inject({ method: 'POST', url: `/app/bff/${path}`, payload: body as never, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf, ...extra } });
    if (response.headers['set-cookie']) { cookie = cookieFrom(response.headers['set-cookie']); csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken; }
    return response;
  };
  const login = async (returnTo = '/app/plateforme') => {
    const start = await post('login', { returnTo }); expect(start.statusCode).toBe(200);
    const state = store.get(cookie.split('=')[1])!.login!.state;
    const response = await app.inject({ url: `/app/bff/callback?code=synthetic&state=${state}`, headers: { cookie } });
    cookie = cookieFrom(response.headers['set-cookie']); csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
    return response;
  };
  return { app, post, login, get: (path: string) => app.inject({ url: `/app/bff/${path}`, headers: { cookie } }) };
}

test('liste fermée : catalogue, offres, droits d’une école et aperçu, requêtes bornées', () => {
  const ok = (request: PlatformRequest) => allowedPlatformRequest(request);
  const id = randomUUID(), other = randomUUID();
  const at = '2026-12-01T10:00:00.000Z';
  for (const path of ['/v1/platform/modules', '/v1/platform/offers', '/v1/platform/offers?status=ACTIVE', '/v1/platform/offers?status=ARCHIVED', `/v1/platform/clients/${id}/entitlements`,
    `/v1/platform/clients/${id}/assignment-preview?offerId=${other}`, `/v1/platform/clients/${id}/assignment-preview?offerId=${other}&effectiveAt=${encodeURIComponent(at)}`])
    expect(ok({ method: 'GET', path }), path).toBe(true);
  for (const path of ['/v1/platform/modules?x=1', '/v1/platform/offers?status=DELETED', '/v1/platform/offers?status=ACTIVE&status=ARCHIVED', '/v1/platform/offers?other=1',
    `/v1/platform/offers/${id}`, `/v1/platform/clients/${id}/entitlements?x=1`, `/v1/platform/clients/${id}/assignment-preview`,
    `/v1/platform/clients/${id}/assignment-preview?effectiveAt=${encodeURIComponent(at)}`, `/v1/platform/clients/${id}/assignment-preview?offerId=pas-un-uuid`,
    `/v1/platform/clients/${id}/assignment-preview?offerId=${other}&effectiveAt=demain`, `/v1/platform/clients/${id}/assignment-preview?offerId=${other}&effectiveAt=2026-12-01`,
    `/v1/platform/clients/${id}/assignment-preview?offerId=${other}&offerId=${id}`, `/v1/platform/clients/${id}/assignment-preview?offerId=${other}&x=1`,
    `/v1/platform/clients/${id}/assignments`, `/v1/platform/clients/${id}/adjustments`, '/v1/platform/entitlements', `/v1/platform/schools/${id}/entitlements`,
    `/v1/platform/clients/not-a-uuid/entitlements`])
    expect(ok({ method: 'GET', path }), path).toBe(false);
  expect(ok({ method: 'GET', path: '/v1/platform/offers', body: {} })).toBe(false);
  expect(ok({ method: 'GET', path: `/v1/platform/clients/${id}/entitlements`, ifMatch: '"1"' })).toBe(false);
  expect(ok({ method: 'GET', path: '/v1/platform/modules', idempotencyKey: key })).toBe(false);

  // Création d'une offre : clé obligatoire, pas de version.
  expect(ok({ method: 'POST', path: '/v1/platform/offers', body: {}, idempotencyKey: key })).toBe(true);
  expect(ok({ method: 'POST', path: '/v1/platform/offers', body: {} })).toBe(false);
  expect(ok({ method: 'POST', path: '/v1/platform/offers', body: {}, idempotencyKey: key, ifMatch: '"1"' })).toBe(false);
  expect(ok({ method: 'POST', path: '/v1/platform/offers?x=1', body: {}, idempotencyKey: key })).toBe(false);
  // Modification, archivage, attribution, annulation, ajustement, levée : clé et version obligatoires.
  const versioned = [`/v1/platform/offers/${id}/archive`, `/v1/platform/offers/${id}/restore`, `/v1/platform/clients/${id}/assignments`,
    `/v1/platform/clients/${id}/assignments/${other}/cancel`, `/v1/platform/clients/${id}/adjustments`, `/v1/platform/clients/${id}/adjustments/${other}/lift`];
  for (const path of versioned) {
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"2"' }), path).toBe(true);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, ifMatch: '"2"' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: 'x', ifMatch: '"2"' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: 'W/"2"' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"0"' }), path).toBe(false);
    expect(ok({ method: 'POST', path: `${path}?x=1`, body: {}, idempotencyKey: key, ifMatch: '"2"' }), path).toBe(false);
  }
  expect(ok({ method: 'PATCH', path: `/v1/platform/offers/${id}`, body: {}, idempotencyKey: key, ifMatch: '"2"' })).toBe(true);
  expect(ok({ method: 'PATCH', path: `/v1/platform/offers/${id}`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'PATCH', path: `/v1/platform/offers/${id}`, body: {}, ifMatch: '"2"' })).toBe(false);
  // Rien d'autre n'existe : pas de suppression d'offre, pas de modification directe d'une attribution ou du catalogue.
  for (const path of ['/v1/platform/modules', '/v1/platform/offers', `/v1/platform/clients/${id}/assignments`, `/v1/platform/clients/${id}/entitlements`, `/v1/platform/clients/${id}/adjustments`])
    expect(ok({ method: 'PATCH', path, body: {}, idempotencyKey: key, ifMatch: '"2"' }), path).toBe(false);
  for (const path of ['/v1/platform/modules', `/v1/platform/offers/${id}`, `/v1/platform/offers/${id}/delete`, `/v1/platform/clients/${id}/entitlements`,
    `/v1/platform/clients/${id}/assignments/${other}`, `/v1/platform/clients/${id}/assignments/${other}/restore`, `/v1/platform/clients/${id}/adjustments/${other}`,
    `/v1/platform/clients/${id}/adjustments/${other}/delete`, `/v1/platform/clients/${id}/assignment-preview`])
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"2"' }), path).toBe(false);
});

test('la passerelle envoie la modification d’une offre en PATCH avec clé, version et corps, et l’aperçu en GET borné', async () => {
  const fetchMock = vi.fn(async () => new Response(JSON.stringify({ data: {} }), { status: 200, headers: { 'content-type': 'application/json' } }));
  vi.stubGlobal('fetch', fetchMock);
  const gateway = createPlatformGateway('https://drivy.example.invalid/refonte');
  const id = randomUUID(), clientId = randomUUID();
  await expect(gateway({ method: 'PATCH', path: `/v1/platform/offers/${id}`, body: {}, idempotencyKey: key }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  await expect(gateway({ method: 'GET', path: `/v1/platform/clients/${clientId}/assignment-preview` }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  await expect(gateway({ method: 'POST', path: `/v1/platform/offers/${id}`, body: {}, idempotencyKey: key, ifMatch: '"1"' }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  expect(fetchMock).not.toHaveBeenCalled();
  await gateway({ method: 'PATCH', path: `/v1/platform/offers/${id}`, body: { operationId: key, name: 'Offre renommée' }, idempotencyKey: key, ifMatch: '"4"' }, 'synthetic-token');
  const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe(`https://drivy.example.invalid/refonte/v1/platform/offers/${id}`);
  expect(init.method).toBe('PATCH'); expect(init.redirect).toBe('error'); expect(init.body).toBe(JSON.stringify({ operationId: key, name: 'Offre renommée' }));
  expect(init.headers).toMatchObject({ Authorization: 'Bearer synthetic-token', 'Idempotency-Key': key, 'If-Match': '"4"', 'Content-Type': 'application/json' });
  await gateway({ method: 'GET', path: `/v1/platform/clients/${clientId}/assignment-preview?offerId=${id}` }, 'synthetic-token');
  const [previewUrl, read] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
  expect(previewUrl).toBe(`https://drivy.example.invalid/refonte/v1/platform/clients/${clientId}/assignment-preview?offerId=${id}`);
  expect(read.method).toBe('GET'); expect(read.body).toBeUndefined();
});

test('anonyme, origine étrangère ou jeton CSRF faux : aucun appel à l’API pour les offres et les droits', async () => {
  const api = vi.fn<PlatformGateway>(async () => ({ status: 200, body: { data: {} } })), h = await harness(api);
  const id = randomUUID(), other = randomUUID();
  for (const path of ['platform/modules', 'platform/offers', `platform/clients/${id}/entitlements`, `platform/clients/${id}/assignment-preview?offerId=${other}`])
    expect((await h.get(path)).statusCode, path).toBe(401);
  const writes: [string, unknown][] = [['platform/offers', { operationId: randomUUID(), name: 'Offre', modules: ['MESSAGING'] }],
    [`platform/offers/${id}/update`, { operationId: randomUUID(), version: 1, name: 'Offre' }], [`platform/offers/${id}/archive`, { operationId: randomUUID(), version: 1 }],
    [`platform/offers/${id}/restore`, { operationId: randomUUID(), version: 1 }], [`platform/clients/${id}/assignments`, { operationId: randomUUID(), version: 1, offerId: other }],
    [`platform/clients/${id}/assignments/${other}/cancel`, { operationId: randomUUID(), version: 1 }],
    [`platform/clients/${id}/adjustments`, { operationId: randomUUID(), version: 1, moduleCode: 'MESSAGING', effect: 'REVOKE', reason: 'Demande de l’école' }],
    [`platform/clients/${id}/adjustments/${other}/lift`, { operationId: randomUUID(), version: 1, reason: 'Retour à la normale' }]];
  for (const [path, body] of writes) expect((await h.post(path, body)).statusCode, path).toBe(401);
  await h.login();
  for (const [path, body] of writes) {
    expect((await h.post(path, body, { origin: 'https://foreign.example.invalid' })).statusCode, path).toBe(403);
    expect((await h.post(path, body, { 'x-csrf-token': 'wrong' })).statusCode, path).toBe(403);
  }
  expect(api).not.toHaveBeenCalled();
});

test('lectures : requête reconstruite champ par champ, champs inconnus retirés, forme inattendue refusée', async () => {
  const calls: PlatformRequest[] = [], clientId = randomUUID(), offerId = randomUUID();
  const h = await harness(async command => {
    calls.push(structuredClone(command));
    if (command.path === '/v1/platform/modules') return { status: 200, body: { data: { items: [{ code: 'MESSAGING', sortOrder: 1, internal: 'jamais relayé' }, { code: 'COLLECTIVE_COURSES', sortOrder: 2 }] } } };
    if (command.path.startsWith('/v1/platform/offers')) return { status: 200, body: { data: { items: [{ ...offer({ id: offerId }), passwordHash: 'x', internalNotes: 'jamais relayé' }] } } };
    if (command.path.includes('/entitlements')) return { status: 200, body: { data: { ...entitlements({ version: 3 }), tarif: 'jamais relayé' }, requestId: 'r' } };
    return { status: 200, body: { data: consequences({ version: 3 }) } };
  });
  await h.login();
  const modules = await h.get('platform/modules');
  expect(modules.statusCode).toBe(200); expect(modules.json().data.items).toHaveLength(2); expect(modules.body.includes('jamais relayé')).toBe(false);
  expect(calls.at(-1)).toEqual({ method: 'GET', path: '/v1/platform/modules' });

  const all = await h.get('platform/offers');
  expect(all.statusCode).toBe(200); expect(all.json().data.items[0].id).toBe(offerId); expect(all.body.includes('jamais relayé')).toBe(false); expect(all.body.includes('passwordHash')).toBe(false);
  expect(calls.at(-1)).toEqual({ method: 'GET', path: '/v1/platform/offers' });
  await h.get('platform/offers?status=ARCHIVED'); expect(calls.at(-1)?.path).toBe('/v1/platform/offers?status=ARCHIVED');
  for (const bad of ['status=DELETED', 'other=1', 'status=ACTIVE&status=ARCHIVED', 'limit=10']) {
    const before = calls.length; expect((await h.get(`platform/offers?${bad}`)).statusCode, bad).toBe(400); expect(calls).toHaveLength(before);
  }

  const rights = await h.get(`platform/clients/${clientId.toUpperCase()}/entitlements`);
  expect(rights.statusCode).toBe(200); expect(rights.json().data.version).toBe(3); expect(rights.body.includes('jamais relayé')).toBe(false); expect(rights.body.includes('requestId')).toBe(false);
  expect(calls.at(-1)).toEqual({ method: 'GET', path: `/v1/platform/clients/${clientId}/entitlements` });
  for (const bad of [`platform/clients/${clientId}/entitlements?x=1`, 'platform/clients/not-a-uuid/entitlements']) {
    const before = calls.length; expect((await h.get(bad)).statusCode, bad).toBe(400); expect(calls).toHaveLength(before);
  }

  const at = '2026-12-01T10:00:00.000Z';
  const shown = await h.get(`platform/clients/${clientId.toUpperCase()}/assignment-preview?offerId=${offerId.toUpperCase()}&effectiveAt=${at}`);
  expect(shown.statusCode).toBe(200); expect(shown.json().data.modules[1].existing).toEqual({ publishedSeries: 2, activeEnrollments: 1, upcomingSessions: 0 });
  expect(calls.at(-1)).toEqual({ method: 'GET', path: `/v1/platform/clients/${clientId}/assignment-preview?offerId=${offerId}&effectiveAt=${encodeURIComponent(at)}` });
  await h.get(`platform/clients/${clientId}/assignment-preview?offerId=${offerId}`);
  expect(calls.at(-1)?.path).toBe(`/v1/platform/clients/${clientId}/assignment-preview?offerId=${offerId}`);
  for (const bad of ['', `?effectiveAt=${at}`, '?offerId=pas-un-uuid', `?offerId=${offerId}&effectiveAt=demain`, `?offerId=${offerId}&effectiveAt=2026-12-01`, `?offerId=${offerId}&x=1`,
    `?offerId=${offerId}&offerId=${clientId}`]) {
    const before = calls.length; expect((await h.get(`platform/clients/${clientId}/assignment-preview${bad}`)).statusCode, bad).toBe(400); expect(calls).toHaveLength(before);
  }

  const broken = await harness(async () => ({ status: 200, body: { data: { items: [{ id: 'x' }] } } })); await broken.login();
  for (const path of ['platform/offers', 'platform/modules']) {
    const response = await broken.get(path); expect(response.statusCode, path).toBe(503); expect(response.json().code).toBe('INVALID_RESPONSE');
  }
  const invalidRights = await harness(async () => ({ status: 200, body: { data: { ...entitlements(), version: 0 } } })); await invalidRights.login();
  const refused = await invalidRights.get(`platform/clients/${clientId}/entitlements`); expect(refused.statusCode).toBe(503); expect(refused.json().code).toBe('INVALID_RESPONSE');
});

test('offres : création, modification versionnée, archivage et rétablissement passent la clé et la version, avec des champs bornés', async () => {
  const writes: PlatformRequest[] = [], id = randomUUID();
  const h = await harness(async command => { writes.push(structuredClone(command)); return { status: command.method === 'POST' && command.path === '/v1/platform/offers' ? 201 : 200, body: { data: offer({ id }) } }; });
  await h.login();
  const operationId = randomUUID();
  const created = await h.post('platform/offers', { operationId, name: ' Offre complète ', modules: ['MESSAGING'] });
  expect(created.statusCode).toBe(201); expect(created.json().data.id).toBe(id);
  expect(writes[0]).toEqual({ method: 'POST', path: '/v1/platform/offers', idempotencyKey: operationId, body: { operationId, name: 'Offre complète', modules: ['MESSAGING'] } });
  const renamed = await h.post(`platform/offers/${id.toUpperCase()}/update`, { operationId, version: 3, name: 'Offre renommée' });
  expect(renamed.statusCode).toBe(200);
  expect(writes[1]).toEqual({ method: 'PATCH', path: `/v1/platform/offers/${id}`, idempotencyKey: operationId, ifMatch: '"3"', body: { operationId, name: 'Offre renommée' } });
  await h.post(`platform/offers/${id}/update`, { operationId, version: 4, modules: moduleCodes });
  expect(writes[2]).toEqual({ method: 'PATCH', path: `/v1/platform/offers/${id}`, idempotencyKey: operationId, ifMatch: '"4"', body: { operationId, modules: moduleCodes } });
  for (const change of ['archive', 'restore'] as const) {
    const done = await h.post(`platform/offers/${id.toUpperCase()}/${change}`, { operationId, version: 5 });
    expect(done.statusCode, change).toBe(200);
    expect(writes.at(-1), change).toEqual({ method: 'POST', path: `/v1/platform/offers/${id}/${change}`, idempotencyKey: operationId, ifMatch: '"5"', body: { operationId } });
  }

  const before = writes.length;
  const tooMany = Array.from({ length: 21 }, (_, index) => `MODULE_${String(index).padStart(2, '0')}`);
  for (const bad of [{ operationId }, { operationId, name: '', modules: [] }, { operationId, name: '   ', modules: [] }, { operationId, name: 'x'.repeat(101), modules: [] },
    { operationId, name: 'x', modules: ['messagerie'] }, { operationId, name: 'x', modules: ['MESSAGING', 'MESSAGING'] }, { operationId, name: 'x', modules: 'MESSAGING' }, { operationId, name: 'x', modules: tooMany },
    { operationId, name: 'x', modules: [], status: 'ARCHIVED' }, { operationId, name: 'x', modules: [], price: 100 }, { operationId, name: 'x', modules: [], trialDays: 14 },
    { name: 'x', modules: [] }, { operationId, version: 1, name: 'x', modules: [] }, { operationId: 'pas-un-uuid', name: 'x', modules: [] }])
    expect((await h.post('platform/offers', bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const bad of [{ operationId, version: 1 }, { operationId, version: 0, name: 'x' }, { operationId, name: 'x' }, { version: 1, name: 'x' }, { operationId, version: 1, name: '' },
    { operationId, version: 1, name: 'x', status: 'ARCHIVED' }, { operationId, version: 1, name: 'x', amountCents: 100 }, { operationId, version: 1, modules: ['MESSAGING', 'MESSAGING'] },
    { operationId, version: 2_147_483_648, name: 'x' }])
    expect((await h.post(`platform/offers/${id}/update`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const change of ['archive', 'restore']) {
    for (const bad of [{ operationId }, { version: 1 }, {}, { operationId, version: 1, reason: 'x' }, { operationId, version: 0 }])
      expect((await h.post(`platform/offers/${id}/${change}`, bad)).statusCode, `${change} ${JSON.stringify(bad)}`).toBe(400);
  }
  expect((await h.post('platform/offers/pas-un-uuid/update', { operationId, version: 1, name: 'x' })).statusCode).toBe(400);
  expect((await h.post('platform/offers/pas-un-uuid/archive', { operationId, version: 1 })).statusCode).toBe(400);
  // Aucune route ne supprime une offre (la liste fermée ci-dessus le verrouille) : l'historique des attributions garde toujours son offre.
  expect(writes).toHaveLength(before);
});

test('droits d’une école : attribution, annulation, ajustement et levée passent la clé et la version lue', async () => {
  const writes: PlatformRequest[] = [], clientId = randomUUID(), offerId = randomUUID(), assignmentId = randomUUID(), adjustmentId = randomUUID();
  const h = await harness(async command => { writes.push(structuredClone(command)); return { status: 200, body: { data: entitlements({ version: 9 }) } }; });
  await h.login();
  const operationId = randomUUID(), at = '2026-12-01T10:00:00.000Z';

  const scheduled = await h.post(`platform/clients/${clientId.toUpperCase()}/assignments`, { operationId, version: 2, offerId: offerId.toUpperCase(), effectiveAt: at });
  expect(scheduled.statusCode).toBe(200); expect(scheduled.json().data.version).toBe(9);
  expect(writes[0]).toEqual({ method: 'POST', path: `/v1/platform/clients/${clientId}/assignments`, idempotencyKey: operationId, ifMatch: '"2"', body: { operationId, offerId, effectiveAt: at } });
  await h.post(`platform/clients/${clientId}/assignments`, { operationId, version: 2, offerId });
  expect(writes[1]).toEqual({ method: 'POST', path: `/v1/platform/clients/${clientId}/assignments`, idempotencyKey: operationId, ifMatch: '"2"', body: { operationId, offerId } });
  await h.post(`platform/clients/${clientId}/assignments`, { operationId, version: 2, offerId, effectiveAt: null });
  expect(writes[2]!.body).toEqual({ operationId, offerId, effectiveAt: null });

  const cancelled = await h.post(`platform/clients/${clientId}/assignments/${assignmentId.toUpperCase()}/cancel`, { operationId, version: 5 });
  expect(cancelled.statusCode).toBe(200);
  expect(writes[3]).toEqual({ method: 'POST', path: `/v1/platform/clients/${clientId}/assignments/${assignmentId}/cancel`, idempotencyKey: operationId, ifMatch: '"5"', body: { operationId } });

  const adjusted = await h.post(`platform/clients/${clientId}/adjustments`, { operationId, version: 6, moduleCode: 'COLLECTIVE_COURSES', effect: 'REVOKE', reason: '  Demande de l’école  ' });
  expect(adjusted.statusCode).toBe(200);
  expect(writes[4]).toEqual({ method: 'POST', path: `/v1/platform/clients/${clientId}/adjustments`, idempotencyKey: operationId, ifMatch: '"6"',
    body: { operationId, moduleCode: 'COLLECTIVE_COURSES', effect: 'REVOKE', reason: 'Demande de l’école' } });

  const lifted = await h.post(`platform/clients/${clientId}/adjustments/${adjustmentId.toUpperCase()}/lift`, { operationId, version: 7, reason: 'Retour à la normale' });
  expect(lifted.statusCode).toBe(200);
  expect(writes[5]).toEqual({ method: 'POST', path: `/v1/platform/clients/${clientId}/adjustments/${adjustmentId}/lift`, idempotencyKey: operationId, ifMatch: '"7"',
    body: { operationId, reason: 'Retour à la normale' } });

  const before = writes.length;
  for (const bad of [{ operationId, version: 1 }, { operationId, offerId }, { version: 1, offerId }, { operationId, version: 0, offerId }, { operationId, version: 1, offerId: 'pas-un-uuid' },
    { operationId, version: 1, offerId, effectiveAt: 'demain' }, { operationId, version: 1, offerId, effectiveAt: '2026-12-01' }, { operationId, version: 1, offerId, schoolId: clientId },
    { operationId, version: 1, offerId, amountCents: 100 }, { operationId, version: 1, offerId, state: 'PAID' }])
    expect((await h.post(`platform/clients/${clientId}/assignments`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const bad of [{ operationId }, { version: 1 }, { operationId, version: 1, reason: 'x' }, { operationId, version: 0 }])
    expect((await h.post(`platform/clients/${clientId}/assignments/${assignmentId}/cancel`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  const adjust = { operationId, version: 1, moduleCode: 'MESSAGING', effect: 'GRANT', reason: 'Essai accordé à la demande' };
  for (const bad of [{ ...adjust, effect: 'DELETE' }, { ...adjust, effect: 'grant' }, { ...adjust, reason: 'ab' }, { ...adjust, reason: '   ' }, { ...adjust, reason: 'x'.repeat(501) },
    { ...adjust, moduleCode: 'messagerie' }, { ...adjust, version: 0 }, { ...adjust, operationId: 'x' }, { ...adjust, price: 1 }, { operationId, version: 1, moduleCode: 'MESSAGING', effect: 'GRANT' },
    { operationId, version: 1, effect: 'GRANT', reason: 'Motif lisible' }, { operationId, version: 1, moduleCode: 'MESSAGING', reason: 'Motif lisible' }])
    expect((await h.post(`platform/clients/${clientId}/adjustments`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const bad of [{ operationId, version: 1 }, { operationId, reason: 'Motif lisible' }, { version: 1, reason: 'Motif lisible' }, { operationId, version: 1, reason: 'ab' },
    { operationId, version: 1, reason: 'x'.repeat(501) }, { operationId, version: 1, reason: 'Motif lisible', effect: 'GRANT' }])
    expect((await h.post(`platform/clients/${clientId}/adjustments/${adjustmentId}/lift`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const path of ['platform/clients/pas-un-uuid/assignments', `platform/clients/${clientId}/assignments/pas-un-uuid/cancel`, 'platform/clients/pas-un-uuid/adjustments',
    `platform/clients/${clientId}/adjustments/pas-un-uuid/lift`])
    expect((await h.post(path, { operationId, version: 1, offerId, moduleCode: 'MESSAGING', effect: 'GRANT', reason: 'Motif lisible' })).statusCode, path).toBe(400);
  expect(writes).toHaveLength(before);
});

test('les refus métier et les conflits de version des offres et des droits sont relayés tels quels, sans le texte amont', async () => {
  let outcome: { status: number; body: unknown } = { status: 412, body: { code: 'VERSION_CONFLICT' } };
  const h = await harness(async () => outcome); await h.login();
  const clientId = randomUUID(), offerId = randomUUID(), operationId = randomUUID();
  const refusals = [[412, 'VERSION_CONFLICT'], [409, 'OFFER_ARCHIVED'], [409, 'OFFER_NOT_ARCHIVED'], [409, 'EFFECTIVE_DATE_PAST'], [409, 'ASSIGNMENT_NOT_PENDING'],
    [409, 'ADJUSTMENT_REQUIRES_OFFER'], [409, 'ADJUSTMENT_ACTIVE'], [409, 'ADJUSTMENT_NO_EFFECT'], [409, 'ADJUSTMENT_NOT_ACTIVE'], [404, 'MODULE_UNKNOWN'], [404, 'NOT_FOUND'],
    [409, 'IDEMPOTENCY_MISMATCH']] as const;
  for (const [status, code] of refusals) {
    outcome = { status, body: { code, title: 'texte interne' } };
    const assigned = await h.post(`platform/clients/${clientId}/assignments`, { operationId, version: 1, offerId });
    expect(assigned.statusCode, code).toBe(status); expect(assigned.json().code).toBe(code); expect(assigned.body.includes('texte interne')).toBe(false);
    const archived = await h.post(`platform/offers/${offerId}/archive`, { operationId, version: 1 });
    expect(archived.statusCode, code).toBe(status); expect(archived.json().code).toBe(code);
  }
  // Un compte qui n'est plus opérateur n'obtient plus rien, ni lecture ni écriture.
  outcome = { status: 403, body: { code: 'PLATFORM_OPERATOR_REQUIRED' } };
  for (const response of [await h.get('platform/offers'), await h.get(`platform/clients/${clientId}/entitlements`), await h.post(`platform/offers/${offerId}/restore`, { operationId, version: 1 })]) {
    expect(response.statusCode).toBe(403); expect(response.json().code).toBe('PLATFORM_OPERATOR_REQUIRED');
  }
});
