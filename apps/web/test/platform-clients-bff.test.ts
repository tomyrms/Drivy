import { afterEach, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { allowedPlatformRequest, type PlatformGateway, type PlatformRequest } from '../server/platform-routes.js';
import { createPlatformGateway } from '../server/upstream.js';

// R01-T02 : écoles clientes et codes d'ouverture, côté relais web. Aucune donnée réelle : tout est synthétique.
const config = { origin: 'https://drivy.example.invalid', apiBaseURL: 'https://drivy.example.invalid/refonte', issuer: 'https://identity.example.invalid/realm',
  clientId: 'drivy-web', clientSecret: randomBytes(32).toString('hex'), development: false, host: '127.0.0.1', port: 3002 };
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); vi.unstubAllGlobals(); });
const secret = () => randomBytes(32).toString('base64url');
const iso = (offsetDays = 0) => new Date(Date.now() + offsetDays * 86_400_000).toISOString();
const openingPattern = /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;
const key = randomUUID();

const setup = { step: 'IDENTITY', stepsDone: 2, stepsTotal: 6, completedAt: null, savedAt: null };
const facts = (extra: Record<string, unknown> = {}) => ({ name: 'École synthétique', status: 'DRAFT', contactEmail: 'contact@example.invalid', contactPhone: null, setup, ...extra });
const commercial = { state: 'NOT_CONFIGURED', offer: null, scheduledOffer: null, entitlementVersion: 1, dueDates: [] };
const summary = (extra: Record<string, unknown> = {}) => ({ id: randomUUID(), displayName: 'Auto-école synthétique', preparation: 'AWAITING_SCHOOL', schoolId: null, school: null,
  contactName: null, contactEmail: null, latestCode: null, commercial, version: 1, createdAt: iso(), updatedAt: iso(), ...extra });
const detail = (extra: Record<string, unknown> = {}) => ({ ...summary(), contactPhone: null, billing: { street: null, postalCode: null, city: null, country: null },
  internalNotes: null, link: null, codes: [], ...extra });
const codeRow = (extra: Record<string, unknown> = {}) => ({ id: randomUUID(), state: 'AVAILABLE', clientId: randomUUID(), clientName: 'Auto-école synthétique', createdAt: iso(), expiresAt: iso(7),
  usedAt: null, revokedAt: null, issuedByName: 'Opérateur synthétique', school: null, ...extra });

async function harness(platformGateway: PlatformGateway) {
  const now = Date.now(), store = new SessionStore(); let subject = 'synthetic-operator-account';
  const tokens = (): Tokens => ({ accessToken: secret(), expiresAt: now + 300_000, principal: { subject, displayName: 'Opérateur synthétique', email: 'o@example.invalid', emailVerified: true } });
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
  return { app, post, login, store, get: (path: string) => app.inject({ url: `/app/bff/${path}`, headers: { cookie } }),
    current: () => store.get(cookie.split('=')[1])!, changeSubject: (value: string) => { subject = value; } };
}

test('liste fermée : lectures des fiches, des codes et des écoles non rattachées, requêtes bornées', () => {
  const ok = (request: PlatformRequest) => allowedPlatformRequest(request);
  const id = randomUUID();
  for (const path of ['/v1/platform/clients', '/v1/platform/clients?limit=100', '/v1/platform/clients?limit=25&q=lilas&preparation=IN_PREPARATION&cursor=abc_DEF-123',
    `/v1/platform/clients/${id}`, '/v1/platform/unattached-schools', '/v1/platform/unattached-schools?q=%C3%A9cole&limit=50', '/v1/platform/school-codes',
    `/v1/platform/school-codes?clientId=${id}&state=AVAILABLE&limit=100&cursor=abc`]) expect(ok({ method: 'GET', path }), path).toBe(true);
  for (const path of ['/v1/platform/clients?limit=0', '/v1/platform/clients?limit=101', '/v1/platform/clients?limit=1&limit=2', '/v1/platform/clients?other=1',
    '/v1/platform/clients?preparation=PAID', '/v1/platform/clients?cursor=a%20b', `/v1/platform/clients/${id}?x=1`, '/v1/platform/clients/not-a-uuid',
    `/v1/platform/clients/${id}/codes`, '/v1/platform/clients?q=' + 'a'.repeat(101), '/v1/platform/clients?q=a%00b', '/v1/platform/clients?constructor=1',
    '/v1/platform/unattached-schools?limit=51', '/v1/platform/unattached-schools?cursor=abc', '/v1/platform/school-codes?state=ALL', '/v1/platform/school-codes?clientId=1',
    '/v1/platform/school-codes?preparation=ACTIVE', `/v1/platform/school-codes/${id}`, '/v1/platform/schools', '/v1/platform/clients/../me'])
    expect(ok({ method: 'GET', path }), path).toBe(false);
  expect(ok({ method: 'GET', path: '/v1/platform/clients', body: {} })).toBe(false);
  expect(ok({ method: 'GET', path: `/v1/platform/clients/${id}`, ifMatch: '"1"' })).toBe(false);

  // Créations : clé obligatoire, pas de version.
  for (const path of ['/v1/platform/clients', '/v1/platform/school-codes', `/v1/platform/school-codes/${id}/revoke`]) {
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key }), path).toBe(true);
    expect(ok({ method: 'POST', path, body: {} }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: 'x' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"1"' }), path).toBe(false);
    expect(ok({ method: 'POST', path: `${path}?x=1`, body: {}, idempotencyKey: key }), path).toBe(false);
  }
  // Rattachement et modification : clé et version obligatoires.
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}/attach-school`, body: {}, idempotencyKey: key, ifMatch: '"2"' })).toBe(true);
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}/attach-school`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}/attach-school`, body: {}, idempotencyKey: key, ifMatch: 'W/"2"' })).toBe(false);
  expect(ok({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: {}, idempotencyKey: key, ifMatch: '"2"' })).toBe(true);
  expect(ok({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: {}, ifMatch: '"2"' })).toBe(false);
  expect(ok({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: {}, idempotencyKey: key, ifMatch: '"0"' })).toBe(false);
  for (const path of ['/v1/platform/clients', '/v1/platform/me', '/v1/platform/operators', '/v1/platform/invitations', `/v1/platform/clients/${id}/attach-school`, `/v1/platform/school-codes/${id}`])
    expect(ok({ method: 'PATCH', path, body: {}, idempotencyKey: key, ifMatch: '"2"' }), path).toBe(false);
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}/delete`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: `/v1/platform/school-codes/${id}`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: `/v1/platform/clients/${id}/link-school`, body: {}, idempotencyKey: key })).toBe(false);
});

test('la passerelle envoie une modification en PATCH avec clé, version et corps, et refuse une route hors liste sans requête', async () => {
  const fetchMock = vi.fn(async () => new Response(JSON.stringify({ data: {} }), { status: 200, headers: { 'content-type': 'application/json' } }));
  vi.stubGlobal('fetch', fetchMock);
  const gateway = createPlatformGateway('https://drivy.example.invalid/refonte');
  const id = randomUUID();
  await expect(gateway({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: {}, idempotencyKey: key }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  await expect(gateway({ method: 'PATCH', path: '/v1/platform/operators', body: {}, idempotencyKey: key, ifMatch: '"1"' }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  await expect(gateway({ method: 'GET', path: '/v1/platform/clients?limit=500' }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  expect(fetchMock).not.toHaveBeenCalled();
  await gateway({ method: 'PATCH', path: `/v1/platform/clients/${id}`, body: { operationId: key, contactName: 'Camille' }, idempotencyKey: key, ifMatch: '"4"' }, 'synthetic-token');
  const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe(`https://drivy.example.invalid/refonte/v1/platform/clients/${id}`);
  expect(init.method).toBe('PATCH'); expect(init.redirect).toBe('error'); expect(init.body).toBe(JSON.stringify({ operationId: key, contactName: 'Camille' }));
  expect(init.headers).toMatchObject({ Authorization: 'Bearer synthetic-token', 'Idempotency-Key': key, 'If-Match': '"4"', 'Content-Type': 'application/json' });
  await gateway({ method: 'GET', path: '/v1/platform/clients?limit=25&q=lilas' }, 'synthetic-token');
  const [, read] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
  expect(read.method).toBe('GET'); expect(read.body).toBeUndefined(); expect(read.headers).not.toHaveProperty('Content-Type');
});

test('anonyme, origine étrangère ou jeton CSRF faux : aucun appel à l’API pour les écoles clientes', async () => {
  const api = vi.fn<PlatformGateway>(async () => ({ status: 200, body: { data: {} } })), h = await harness(api);
  const id = randomUUID();
  for (const path of ['platform/clients', `platform/clients/${id}`, 'platform/unattached-schools', 'platform/school-codes', 'platform/school-codes/pending'])
    expect((await h.get(path)).statusCode, path).toBe(401);
  for (const [path, body] of [['platform/clients', { operationId: randomUUID() }], [`platform/clients/${id}/update`, { operationId: randomUUID(), version: 1, contactName: 'x' }],
    [`platform/clients/${id}/attach-school`, { operationId: randomUUID(), version: 1, schoolId: id }], ['platform/school-codes', { operationId: randomUUID() }],
    ['platform/school-codes/clear', {}], [`platform/school-codes/${id}/revoke`, { operationId: randomUUID() }]] as const)
    expect((await h.post(path, body)).statusCode, path).toBe(401);
  await h.login();
  for (const [path, body] of [['platform/clients', { operationId: randomUUID() }], ['platform/school-codes', { operationId: randomUUID() }],
    [`platform/school-codes/${id}/revoke`, { operationId: randomUUID() }], [`platform/clients/${id}/update`, { operationId: randomUUID(), version: 1, contactName: 'x' }]] as const) {
    expect((await h.post(path, body, { origin: 'https://foreign.example.invalid' })).statusCode, path).toBe(403);
    expect((await h.post(path, body, { 'x-csrf-token': 'wrong' })).statusCode, path).toBe(403);
  }
  expect(api).not.toHaveBeenCalled();
});

test('lectures : requête reconstruite champ par champ, champs inconnus retirés, forme inattendue refusée', async () => {
  const calls: PlatformRequest[] = [], client = summary({ preparation: 'IN_PREPARATION', school: facts() }), opened = detail({ id: client.id, codes: [codeRow({ state: 'USED' })] });
  const h = await harness(async command => {
    calls.push(structuredClone(command));
    if (command.path.startsWith('/v1/platform/clients?') || command.path === '/v1/platform/clients') return { status: 200, body: { data: { items: [{ ...client, internalNotes: 'jamais relayé', passwordHash: 'x' }], total: 135, nextCursor: 'AbC_-1' }, requestId: 'r' } };
    if (command.path.startsWith('/v1/platform/clients/')) return { status: 200, body: { data: opened } };
    if (command.path.startsWith('/v1/platform/school-codes')) return { status: 200, body: { data: { items: [codeRow()], total: 1, nextCursor: null } } };
    return { status: 200, body: { data: { items: [{ id: randomUUID(), name: 'École pilote', status: 'ACTIVE', contactEmail: 'pilote@example.invalid', contactPhone: null, setup }] } } };
  });
  await h.login();
  const list = await h.get('platform/clients?q=%20lilas%20&preparation=IN_PREPARATION&limit=100&cursor=AbC_-1');
  expect(list.statusCode).toBe(200); expect(list.json().data.total).toBe(135); expect(list.json().data.nextCursor).toBe('AbC_-1');
  expect(list.body.includes('jamais relayé')).toBe(false); expect(list.body.includes('passwordHash')).toBe(false); expect(list.body.includes('requestId')).toBe(false);
  expect(calls.at(-1)?.path).toBe('/v1/platform/clients?limit=100&cursor=AbC_-1&q=lilas&preparation=IN_PREPARATION');
  await h.get('platform/clients'); expect(calls.at(-1)?.path).toBe('/v1/platform/clients');
  await h.get('platform/clients?q=%20%20'); expect(calls.at(-1)?.path).toBe('/v1/platform/clients');
  for (const bad of ['limit=0', 'limit=101', 'limit=a', 'cursor=a%20b', 'preparation=PAID', 'other=1', 'limit=1&limit=2', 'q=' + 'a'.repeat(101)]) {
    const before = calls.length; expect((await h.get(`platform/clients?${bad}`)).statusCode, bad).toBe(400); expect(calls).toHaveLength(before);
  }
  const one = await h.get(`platform/clients/${client.id.toUpperCase()}`);
  expect(one.statusCode).toBe(200); expect(one.json().data.codes[0].state).toBe('USED'); expect(calls.at(-1)?.path).toBe(`/v1/platform/clients/${client.id}`);
  expect((await h.get('platform/clients/not-a-uuid')).statusCode).toBe(400); expect((await h.get(`platform/clients/${client.id}?x=1`)).statusCode).toBe(400);
  const codes = await h.get(`platform/school-codes?clientId=${client.id.toUpperCase()}&state=AVAILABLE&limit=10`);
  expect(codes.statusCode).toBe(200); expect(calls.at(-1)?.path).toBe(`/v1/platform/school-codes?limit=10&clientId=${client.id}&state=AVAILABLE`);
  expect(codes.body).not.toMatch(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
  for (const bad of ['state=ALL', 'clientId=1', 'preparation=ACTIVE', 'limit=500']) expect((await h.get(`platform/school-codes?${bad}`)).statusCode, bad).toBe(400);
  const unattached = await h.get('platform/unattached-schools?q=pilote&limit=20');
  expect(unattached.statusCode).toBe(200); expect(unattached.json().data.items[0].name).toBe('École pilote'); expect(calls.at(-1)?.path).toBe('/v1/platform/unattached-schools?limit=20&q=pilote');
  expect((await h.get('platform/unattached-schools?limit=51')).statusCode).toBe(400);
  const broken = await harness(async () => ({ status: 200, body: { data: { items: [{ id: 'x' }], total: 1, nextCursor: null } } })); await broken.login();
  const response = await broken.get('platform/clients'); expect(response.statusCode).toBe(503); expect(response.json().code).toBe('INVALID_RESPONSE');
  const refused = await harness(async () => ({ status: 403, body: { code: 'PLATFORM_OPERATOR_REQUIRED', title: 'texte interne' } })); await refused.login();
  const denied = await refused.get('platform/clients'); expect(denied.statusCode).toBe(403); expect(denied.json().code).toBe('PLATFORM_OPERATOR_REQUIRED'); expect(denied.body.includes('texte interne')).toBe(false);
});

test('fiche : création, modification versionnée et rattachement passent la clé et la version, avec des champs bornés', async () => {
  const writes: PlatformRequest[] = [], id = randomUUID(), schoolId = randomUUID();
  const h = await harness(async command => { writes.push(structuredClone(command)); return { status: command.method === 'POST' && command.path === '/v1/platform/clients' ? 201 : 200, body: { data: detail({ id }) } }; });
  await h.login();
  const operationId = randomUUID();
  const created = await h.post('platform/clients', { operationId, displayName: ' Auto-école des Lilas ', contactEmail: ' Camille@Example.INVALID ', internalNotes: null, schoolId: schoolId.toUpperCase() });
  expect(created.statusCode).toBe(201);
  expect(writes[0]).toEqual({ method: 'POST', path: '/v1/platform/clients', idempotencyKey: operationId,
    body: { operationId, displayName: 'Auto-école des Lilas', contactEmail: 'camille@example.invalid', internalNotes: null, schoolId } });
  const updated = await h.post(`platform/clients/${id.toUpperCase()}/update`, { operationId, version: 3, contactName: 'Camille', billingCity: null });
  expect(updated.statusCode).toBe(200);
  expect(writes[1]).toEqual({ method: 'PATCH', path: `/v1/platform/clients/${id}`, idempotencyKey: operationId, ifMatch: '"3"', body: { operationId, contactName: 'Camille', billingCity: null } });
  const attached = await h.post(`platform/clients/${id}/attach-school`, { operationId, version: 4, schoolId: schoolId.toUpperCase() });
  expect(attached.statusCode).toBe(200);
  expect(writes[2]).toEqual({ method: 'POST', path: `/v1/platform/clients/${id}/attach-school`, idempotencyKey: operationId, ifMatch: '"4"', body: { operationId, schoolId } });
  // Des notes de 4 000 caractères accentués dépassent la limite de 2 Kio du relais : la fiche a sa propre limite.
  const notes = 'é'.repeat(4000);
  const long = await h.post(`platform/clients/${id}/update`, { operationId, version: 5, internalNotes: notes });
  expect(long.statusCode).toBe(200); expect((writes[3]!.body as { internalNotes: string }).internalNotes).toBe(notes);
  const longCreate = await h.post('platform/clients', { operationId: randomUUID(), displayName: 'Lilas', internalNotes: notes });
  expect(longCreate.statusCode).toBe(201);
  const before = writes.length;
  for (const bad of [{ operationId, version: 3 }, { operationId, version: 0, contactName: 'x' }, { operationId, version: 3, contactName: '' }, { operationId, version: 3, contactEmail: 'pas-une-adresse' },
    { operationId, version: 3, contactName: 'x'.repeat(201) }, { operationId, version: 3, internalNotes: 'x'.repeat(4001) }, { operationId, version: 3, status: 'ACTIVE' },
    { operationId, version: 3, offer: 'PREMIUM' }, { version: 3, contactName: 'x' }, { operationId, contactName: 'x' }, { operationId, version: 3, contactName: 'x', schoolId }])
    expect((await h.post(`platform/clients/${id}/update`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const bad of [{ operationId, displayName: '' }, { operationId, schoolId: 'x' }, { operationId, version: 1 }, { displayName: 'x' }, { operationId, commercialState: 'PAID' }])
    expect((await h.post('platform/clients', bad)).statusCode, JSON.stringify(bad)).toBe(400);
  for (const bad of [{ operationId, version: 1 }, { operationId, schoolId }, { operationId, version: 1, schoolId: 'x' }, { operationId, version: 1, schoolId, name: 'x' }])
    expect((await h.post(`platform/clients/${id}/attach-school`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  expect((await h.post('platform/clients/pas-un-uuid/update', { operationId, version: 1, contactName: 'x' })).statusCode).toBe(400);
  expect(writes).toHaveLength(before);
});

test('fiche : un conflit de version, une école déjà rattachée ou une fiche inconnue sont relayés tels quels', async () => {
  let outcome: { status: number; body: unknown } = { status: 412, body: { code: 'VERSION_CONFLICT' } };
  const h = await harness(async () => outcome); await h.login();
  const id = randomUUID(), operationId = randomUUID();
  for (const [status, code] of [[412, 'VERSION_CONFLICT'], [409, 'CLIENT_SCHOOL_LINKED'], [409, 'CLIENT_SCHOOL_ALREADY_LINKED'], [404, 'NOT_FOUND'], [409, 'IDEMPOTENCY_MISMATCH']] as const) {
    outcome = { status, body: { code } };
    const response = await h.post(`platform/clients/${id}/attach-school`, { operationId, version: 1, schoolId: randomUUID() });
    expect(response.statusCode).toBe(status); expect(response.json().code).toBe(code);
  }
});

test('code : tiré dans le relais, au format de saisie, rendu avec son lien, jamais relu ni journalisé', async () => {
  const writes: PlatformRequest[] = [], clientId = randomUUID();
  const h = await harness(async command => {
    if (command.method === 'POST') { writes.push(structuredClone(command)); return { status: 201, body: { data: { codeId: randomUUID(), client: detail({ id: clientId }) } } }; }
    return { status: 200, body: { data: { items: [codeRow({ clientId })], total: 1, nextCursor: null } } };
  });
  await h.login();
  const operationId = randomUUID();
  const first = await h.post('platform/school-codes', { operationId, displayName: ' Auto-école des Lilas ', validityDays: 14 });
  expect(first.statusCode).toBe(201);
  const code = first.json().code as string; expect(code).toMatch(openingPattern);
  expect(first.json().link).toBe(`https://drivy.example.invalid/app/ouvrir#token=${code}`);
  expect(first.json().data.client.id).toBe(clientId);
  expect(writes[0]).toEqual({ method: 'POST', path: '/v1/platform/school-codes', idempotencyKey: operationId, body: { operationId, code, displayName: 'Auto-école des Lilas', validityDays: 14 } });
  // Le code ne se relit nulle part : ni la liste, ni l'état en attente.
  expect((await h.get('platform/school-codes')).body.includes(code)).toBe(false);
  const pending = await h.get('platform/school-codes/pending');
  expect(pending.json()).toEqual({ pending: { operationId, displayName: 'Auto-école des Lilas', validityDays: 14 } }); expect(pending.body.includes(code)).toBe(false);
  // Reprise : même opération, même contenu, même code ; l'API rejoue son reçu.
  const again = await h.post('platform/school-codes', { operationId, displayName: 'Auto-école des Lilas', validityDays: 14 });
  expect(again.statusCode).toBe(201); expect(again.json().code).toBe(code); expect(writes[1]!.body).toEqual(writes[0]!.body);
  // Un autre contenu sous la même opération, ou une autre opération avant l'accusé : refus sans appel.
  expect((await h.post('platform/school-codes', { operationId, displayName: 'Autre libellé', validityDays: 14 })).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await h.post('platform/school-codes', { operationId, displayName: 'Auto-école des Lilas' })).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await h.post('platform/school-codes', { operationId: randomUUID(), clientId })).json().code).toBe('PLATFORM_CODE_IN_PROGRESS');
  expect(writes).toHaveLength(2);
  expect((await h.post('platform/school-codes/clear', {})).json()).toEqual({ ok: true });
  expect(h.current().platformCode).toBeUndefined(); expect((await h.get('platform/school-codes/pending')).json()).toEqual({ pending: null });
  const next = await h.post('platform/school-codes', { operationId: randomUUID(), clientId: clientId.toUpperCase() });
  expect(next.statusCode).toBe(201); expect(next.json().code).toMatch(openingPattern); expect(next.json().code).not.toBe(code);
  expect(writes[2]!.body).toMatchObject({ clientId }); expect(writes[2]!.body).not.toHaveProperty('displayName');
});

test('code : données invalides refusées avant tout appel, le relais impose le code et la forme', async () => {
  const api = vi.fn<PlatformGateway>(async () => ({ status: 201, body: {} })), h = await harness(api); await h.login();
  const operationId = randomUUID(), clientId = randomUUID();
  for (const bad of [{}, { operationId: 'x' }, { operationId, validityDays: 0 }, { operationId, validityDays: 31 }, { operationId, validityDays: 1.5 }, { operationId, clientId: 'x' },
    { operationId, displayName: '' }, { operationId, displayName: 'x'.repeat(151) }, { operationId, clientId, displayName: 'Libellé' }, { operationId, code: 'ABCD-EFGH' },
    { operationId, token: 'ABCD-EFGH' }, { operationId, email: 'a@example.invalid' }])
    expect((await h.post('platform/school-codes', bad)).statusCode, JSON.stringify(bad)).toBe(400);
  expect((await h.post('platform/school-codes/not-a-uuid/revoke', { operationId })).statusCode).toBe(400);
  expect((await h.post(`platform/school-codes/${clientId}/revoke`, {})).statusCode).toBe(400);
  expect((await h.post(`platform/school-codes/${clientId}/revoke`, { operationId, version: 1 })).statusCode).toBe(400);
  expect(api).not.toHaveBeenCalled(); expect(h.current().platformCode).toBeUndefined();
});

test('code : réponse perdue ou panne gardent le même code ; un refus définitif libère et tire un autre code', async () => {
  const sent: string[] = []; let step = 0;
  const h = await harness(async command => {
    sent.push((command.body as { code: string }).code); step += 1;
    if (step === 1) throw new Error('synthetic_network_loss');
    if (step === 2) return { status: 503, body: { code: 'SERVICE_UNAVAILABLE' } };
    if (step === 3) return { status: 409, body: { code: 'CLIENT_CODE_PENDING' } };
    if (step === 4) return { status: 409, body: { code: 'OPENING_CODE_TAKEN' } };
    return { status: 201, body: { data: { codeId: randomUUID(), client: detail() } } };
  });
  await h.login();
  const operationId = randomUUID(), clientId = randomUUID(), body = { operationId, clientId };
  expect((await h.post('platform/school-codes', body)).statusCode).toBe(503);
  expect((await h.post('platform/school-codes', body)).statusCode).toBe(503);
  expect(sent[1]).toBe(sent[0]); expect(h.current().platformCode?.code).toBe(sent[0]);
  expect((await h.post('platform/school-codes', body)).json().code).toBe('CLIENT_CODE_PENDING');
  expect(sent[2]).toBe(sent[0]); expect(h.current().platformCode).toBeUndefined();
  expect((await h.post('platform/school-codes', { operationId: randomUUID(), clientId })).json().code).toBe('OPENING_CODE_TAKEN');
  expect(h.current().platformCode).toBeUndefined();
  const last = await h.post('platform/school-codes', { operationId: randomUUID(), clientId });
  expect(last.statusCode).toBe(201); expect(sent).toHaveLength(5); expect(new Set(sent).size).toBe(3);
});

test('code : une réponse du service hors contrat est une erreur, et le code reste gardé pour la reprise', async () => {
  const h = await harness(async () => ({ status: 201, body: { data: { codeId: 'pas-un-uuid' } } })); await h.login();
  const response = await h.post('platform/school-codes', { operationId: randomUUID() });
  expect(response.statusCode).toBe(503); expect(response.json().code).toBe('INVALID_RESPONSE'); expect(response.body).not.toMatch(/[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}/);
  expect(h.current().platformCode?.code).toMatch(openingPattern);
});

test('code : un accès retiré, un autre compte ou un retrait de soi-même n’héritent pas du code gardé', async () => {
  let denied = false;
  const h = await harness(async command => {
    if (denied) return { status: 403, body: { code: 'PLATFORM_OPERATOR_REQUIRED' } };
    return command.method === 'POST' ? { status: 201, body: { data: { codeId: randomUUID(), client: detail() } } } : { status: 200, body: { data: { items: [], total: 0, nextCursor: null } } };
  });
  await h.login();
  await h.post('platform/school-codes', { operationId: randomUUID() }); expect(h.current().platformCode).toBeDefined();
  await h.login(); expect(h.current().platformCode).toBeDefined();
  h.changeSubject('another-account'); await h.login();
  expect(h.current().platformCode).toBeUndefined(); expect((await h.get('platform/school-codes/pending')).json()).toEqual({ pending: null });
  h.changeSubject('synthetic-operator-account'); await h.login();
  await h.post('platform/school-codes', { operationId: randomUUID() }); expect(h.current().platformCode).toBeDefined();
  denied = true;
  const response = await h.get('platform/clients'); expect(response.statusCode).toBe(403); expect(response.json().code).toBe('PLATFORM_OPERATOR_REQUIRED');
  expect(h.current().platformCode).toBeUndefined();
});

test('révocation d’un code : clé transmise sans version, refus relayés', async () => {
  const id = randomUUID(), writes: PlatformRequest[] = []; let outcome: { status: number; body: unknown } = { status: 200, body: { data: codeRow({ id, state: 'REVOKED', revokedAt: iso() }) } };
  const h = await harness(async command => { writes.push(structuredClone(command)); return outcome; }); await h.login();
  const operationId = randomUUID();
  const done = await h.post(`platform/school-codes/${id.toUpperCase()}/revoke`, { operationId });
  expect(done.statusCode).toBe(200); expect(done.json().data.state).toBe('REVOKED');
  expect(writes[0]).toEqual({ method: 'POST', path: `/v1/platform/school-codes/${id}/revoke`, idempotencyKey: operationId, body: { operationId } });
  for (const [status, code] of [[409, 'OPENING_LINK_USED'], [409, 'OPENING_LINK_REVOKED'], [404, 'NOT_FOUND']] as const) {
    outcome = { status, body: { code } };
    const response = await h.post(`platform/school-codes/${id}/revoke`, { operationId: randomUUID() });
    expect(response.statusCode).toBe(status); expect(response.json().code).toBe(code);
  }
});
