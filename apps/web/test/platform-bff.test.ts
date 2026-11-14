import { afterEach, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { allowedPlatformRequest, type PlatformGateway, type PlatformRequest } from '../server/platform-routes.js';
import { createPlatformGateway } from '../server/upstream.js';

const config = { origin: 'https://drivy.example.invalid', apiBaseURL: 'https://drivy.example.invalid/refonte', issuer: 'https://identity.example.invalid/realm',
  clientId: 'drivy-web', clientSecret: randomBytes(32).toString('hex'), development: false, host: '127.0.0.1', port: 3002 };
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); vi.unstubAllGlobals(); });
const secret = () => randomBytes(32).toString('base64url');
const iso = (offsetDays = 0) => new Date(Date.now() + offsetDays * 86_400_000).toISOString();
const rights = { level: 'COMMERCIAL', rights: ['MANAGE_PLATFORM_TEAM', 'MANAGE_SCHOOL_OPENINGS', 'MANAGE_OFFERS', 'READ_COMMERCIAL_JOURNAL'], notGranted: ['SCHOOL_RECORDS', 'TRIPS', 'MESSAGES', 'SCHOOL_ROLES'] };
const operator = (extra: Record<string, unknown> = {}) => ({ id: randomUUID(), displayName: 'Opérateur synthétique', maskedEmail: 'o***@example.invalid', level: 'COMMERCIAL',
  status: 'ACTIVE', addedVia: 'BOOTSTRAP', joinedAt: iso(-3), revokedAt: null, version: 1, self: true, ...extra });
const invitation = (extra: Record<string, unknown> = {}) => ({ id: randomUUID(), status: 'AVAILABLE', level: 'COMMERCIAL', maskedEmail: 'i***@example.invalid', createdAt: iso(), expiresAt: iso(7),
  version: 1, usedAt: null, revokedAt: null, createdByName: 'Opérateur synthétique', ...extra });
const preview = (extra: Record<string, unknown> = {}) => ({ status: 'AVAILABLE', maskedEmail: 'i***@example.invalid', expiresAt: iso(7), matchesAccount: true, alreadyMember: false, ...rights, ...extra });
const codePattern = /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/;

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
  return { app, post, login, store, gateway, identity, get: (path: string) => app.inject({ url: `/app/bff/${path}`, headers: { cookie } }),
    current: () => store.get(cookie.split('=')[1])!, changeSubject: (value: string) => { subject = value; } };
}

const key = randomUUID();
test('liste fermée : seules les routes de la plateforme, avec leurs clés et leur version, passent', () => {
  const ok = (request: PlatformRequest) => allowedPlatformRequest(request);
  const id = randomUUID();
  for (const path of ['/v1/platform/me', '/v1/platform/operators', '/v1/platform/invitations', '/v1/platform/journal', `/v1/platform/operations/${id}`,
    '/v1/platform/journal?limit=50', `/v1/platform/journal?limit=20&result=REFUSED&schoolId=${id}&cursor=abc_DEF-123`]) expect(ok({ method: 'GET', path }), path).toBe(true);
  for (const path of ['/v1/platform', '/v1/platform/me?x=1', '/v1/platform/journal?limit=0', '/v1/platform/journal?limit=101', '/v1/platform/journal?limit=1&limit=2',
    '/v1/platform/journal?other=1', '/v1/platform/journal?cursor=a%20b', '/v1/platform/journal?result=ALL', '/v1/platform/journal?schoolId=1', '/v1/platform/operations/..%2Fme',
    '/v1/platform/operations/not-a-uuid', '/v1/platform/../school', '/v1/me', '/v1/operator/school-opening-links', '/v1/platform/operators/x', '/v1/school-openings/preview'])
    expect(ok({ method: 'GET', path }), path).toBe(false);
  expect(ok({ method: 'GET', path: '/v1/platform/me', body: {} })).toBe(false);
  expect(ok({ method: 'GET', path: '/v1/platform/me', idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: '/v1/platform/invitations/preview', body: {} })).toBe(true);
  expect(ok({ method: 'POST', path: '/v1/platform/invitations/preview', body: {}, idempotencyKey: key })).toBe(false);
  for (const path of ['/v1/platform/invitations', '/v1/platform/invitations/accept']) {
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key }), path).toBe(true);
    expect(ok({ method: 'POST', path, body: {} }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: 'x' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"1"' }), path).toBe(false);
  }
  for (const path of [`/v1/platform/invitations/${id}/revoke`, `/v1/platform/operators/${id}/revoke`]) {
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"3"' }), path).toBe(true);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: 'W/"3"' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, idempotencyKey: key, ifMatch: '"0"' }), path).toBe(false);
    expect(ok({ method: 'POST', path, body: {}, ifMatch: '"3"' }), path).toBe(false);
  }
  expect(ok({ method: 'POST', path: `/v1/platform/operators/${id}`, body: {}, idempotencyKey: key })).toBe(false);
  expect(ok({ method: 'POST', path: '/v1/platform/journal', body: {}, idempotencyKey: key })).toBe(false);
});

test('la passerelle refuse une route hors liste sans émettre de requête, et transmet clé, version et jeton', async () => {
  const fetchMock = vi.fn(async () => new Response(JSON.stringify({ data: {} }), { status: 200, headers: { 'content-type': 'application/json' } }));
  vi.stubGlobal('fetch', fetchMock);
  const gateway = createPlatformGateway('https://drivy.example.invalid/refonte');
  await expect(gateway({ method: 'GET', path: '/v1/me' }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  await expect(gateway({ method: 'POST', path: `/v1/platform/operators/${randomUUID()}/revoke`, body: {}, idempotencyKey: key }, 'synthetic-token')).rejects.toThrow('Route API non autorisée.');
  expect(fetchMock).not.toHaveBeenCalled();
  const id = randomUUID();
  const result = await gateway({ method: 'POST', path: `/v1/platform/operators/${id}/revoke`, body: { operationId: key }, idempotencyKey: key, ifMatch: '"4"' }, 'synthetic-token');
  expect(result.status).toBe(200);
  const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe(`https://drivy.example.invalid/refonte/v1/platform/operators/${id}/revoke`);
  expect(init.method).toBe('POST'); expect(init.redirect).toBe('error');
  expect(init.headers).toMatchObject({ Authorization: 'Bearer synthetic-token', 'Idempotency-Key': key, 'If-Match': '"4"', 'Content-Type': 'application/json' });
});

test('anonyme, origine étrangère ou jeton CSRF faux : aucun appel à l’API de la plateforme', async () => {
  const api = vi.fn<PlatformGateway>(async () => ({ status: 200, body: { data: {} } })), h = await harness(api);
  for (const path of ['platform/me', 'platform/operators', 'platform/invitations', 'platform/journal', `platform/operations/${randomUUID()}`, 'platform/join'])
    expect((await h.get(path)).statusCode, path).toBe(401);
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' })).statusCode).toBe(401);
  expect((await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' })).statusCode).toBe(401);
  await h.login();
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' }, { origin: 'https://foreign.example.invalid' })).statusCode).toBe(403);
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' }, { 'x-csrf-token': 'wrong' })).statusCode).toBe(403);
  expect((await h.post(`platform/operators/${randomUUID()}/revoke`, { operationId: randomUUID(), version: 1 }, { 'x-csrf-token': 'wrong' })).statusCode).toBe(403);
  expect((await h.post('platform/join/accept', {}, { 'x-csrf-token': 'wrong' })).statusCode).toBe(403);
  expect(api).not.toHaveBeenCalled();
  expect(h.store.size).toBe(1);
});

test('la connexion peut revenir à la console et à la page d’acceptation, pas ailleurs', async () => {
  const h = await harness(async () => ({ status: 200, body: { data: {} } }));
  expect((await h.login('/app/plateforme')).headers.location).toBe('/app/plateforme');
  expect((await h.login('/app/plateforme/rejoindre')).headers.location).toBe('/app/plateforme/rejoindre');
  expect((await h.post('login', { returnTo: '/app/plateforme/autre' })).statusCode).toBe(400);
  expect((await h.post('login', { returnTo: '/app/plateforme/rejoindre/x' })).statusCode).toBe(400);
});

test('lectures : champs inconnus retirés, requête du journal revalidée et reconstruite, forme inattendue refusée', async () => {
  const mine = operator(), other = operator({ self: false, addedVia: 'INVITATION' }), pending = invitation();
  const calls: PlatformRequest[] = [];
  const h = await harness(async command => {
    calls.push(structuredClone(command));
    if (command.path === '/v1/platform/me') return { status: 200, body: { data: { operator: { ...mine, internalNote: 'hidden' }, ...rights }, requestId: 'r', serverTime: iso() } };
    if (command.path === '/v1/platform/operators') return { status: 200, body: { data: { items: [mine, other] } } };
    if (command.path === '/v1/platform/invitations') return { status: 200, body: { data: { items: [pending] } } };
    if (command.path.startsWith('/v1/platform/journal')) return { status: 200, body: { data: { items: [{ id: randomUUID(), occurredAt: iso(), actorKind: 'OPERATOR', actorName: 'Opérateur synthétique',
      action: 'CREATE_PLATFORM_INVITATION', result: 'SUCCESS', reasonCode: null, schoolId: null, subject: { type: 'PlatformInvitation', id: pending.id }, operationId: randomUUID(), changes: { level: 'COMMERCIAL' } }], nextCursor: 'AbC_-1' } } };
    return { status: 200, body: { data: { operationId: command.path.split('/').at(-1), kind: 'CREATE_PLATFORM_INVITATION', statusCode: 201, result: {} } } };
  });
  await h.login();
  const me = await h.get('platform/me'); expect(me.statusCode).toBe(200);
  expect(me.body.includes('internalNote')).toBe(false); expect(me.body.includes('requestId')).toBe(false); expect(me.json().data.rights).toEqual(rights.rights);
  expect((await h.get('platform/operators')).json().data.items).toHaveLength(2);
  const invitations = await h.get('platform/invitations'); expect(invitations.json().data.items[0].id).toBe(pending.id); expect(invitations.json().pending).toBeUndefined();
  const journal = await h.get(`platform/journal?limit=20&result=REFUSED&cursor=AbC_-1&schoolId=${pending.id.toUpperCase()}`);
  expect(journal.statusCode).toBe(200); expect(journal.json().data.nextCursor).toBe('AbC_-1');
  expect(calls.at(-1)?.path).toBe(`/v1/platform/journal?limit=20&cursor=AbC_-1&schoolId=${pending.id}&result=REFUSED`);
  for (const bad of ['limit=0', 'limit=101', 'limit=a', 'cursor=a%20b', 'result=ALL', 'schoolId=1', 'other=1', 'limit=1&limit=2']) {
    const before = calls.length; expect((await h.get(`platform/journal?${bad}`)).statusCode, bad).toBe(400); expect(calls).toHaveLength(before);
  }
  const operationId = randomUUID(); expect((await h.get(`platform/operations/${operationId}`)).json().data.operationId).toBe(operationId);
  expect((await h.get('platform/operations/not-a-uuid')).statusCode).toBe(400);
  expect((await h.get('platform/me?x=1')).statusCode).toBe(400);
  const broken = await harness(async () => ({ status: 200, body: { data: { items: [{ id: 'x' }] } } })); await broken.login();
  const response = await broken.get('platform/operators'); expect(response.statusCode).toBe(503); expect(response.json().code).toBe('INVALID_RESPONSE');
});

test('un accès refusé par l’API est relayé tel quel et ne laisse rien d’une émission en cours', async () => {
  const refuse = { status: 403, body: { code: 'PLATFORM_OPERATOR_REQUIRED', title: 'texte interne', requestId: 'r' } };
  let denied = false;
  const h = await harness(async command => {
    if (denied) return refuse;
    return command.method === 'POST' ? { status: 201, body: { data: invitation() } } : { status: 200, body: { data: { items: [] } } };
  });
  await h.login();
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' })).statusCode).toBe(201);
  expect(h.current().platformInvite?.code).toMatch(codePattern);
  denied = true;
  const response = await h.get('platform/operators'); expect(response.statusCode).toBe(403); expect(response.json().code).toBe('PLATFORM_OPERATOR_REQUIRED');
  expect(response.body.includes('texte interne')).toBe(false); expect(h.current().platformInvite).toBeUndefined();
});

test('émission : le code naît dans le relais, n’est rendu qu’à la création et jamais relu', async () => {
  const writes: PlatformRequest[] = []; let created = invitation();
  const h = await harness(async command => {
    if (command.method === 'POST') { writes.push(structuredClone(command)); return { status: 201, body: { data: created } }; }
    return { status: 200, body: { data: { items: [created] } } };
  });
  await h.login();
  const operationId = randomUUID(), body = { operationId, email: ' Invite@Example.INVALID ', validityDays: 3 };
  const first = await h.post('platform/invitations', body);
  expect(first.statusCode).toBe(201);
  const code = first.json().code as string; expect(code).toMatch(codePattern); expect(first.json().data.id).toBe(created.id);
  expect(writes[0]).toMatchObject({ path: '/v1/platform/invitations', idempotencyKey: operationId, body: { operationId, code, email: 'invite@example.invalid', validityDays: 3 } });
  const listing = await h.get('platform/invitations');
  expect(listing.body.includes(code)).toBe(false);
  expect(listing.json().pending).toEqual({ operationId, email: 'invite@example.invalid', validityDays: 3 });
  // Reprise : même opération, même contenu, même code ; l'API rejoue son reçu.
  const again = await h.post('platform/invitations', { ...body, email: 'invite@example.invalid' });
  expect(again.statusCode).toBe(201); expect(again.json().code).toBe(code); expect(writes[1]!.body).toEqual(writes[0]!.body);
  // Un autre contenu sous la même opération, ou une autre opération avant l'accusé : refus sans appel.
  expect((await h.post('platform/invitations', { ...body, email: 'autre@example.invalid' })).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await h.post('platform/invitations', { operationId, email: 'invite@example.invalid' })).json().code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'autre@example.invalid' })).json().code).toBe('PLATFORM_INVITE_IN_PROGRESS');
  expect(writes).toHaveLength(2);
  expect((await h.post('platform/invitations/clear', {})).json()).toEqual({ ok: true });
  expect(h.current().platformInvite).toBeUndefined(); expect((await h.get('platform/invitations')).json().pending).toBeUndefined();
  created = invitation();
  const next = await h.post('platform/invitations', { operationId: randomUUID(), email: 'autre@example.invalid' });
  expect(next.statusCode).toBe(201); expect(next.json().code).toMatch(codePattern); expect(next.json().code).not.toBe(code);
});

test('émission : données invalides refusées avant tout appel, code et champs imposés par le relais', async () => {
  const api = vi.fn<PlatformGateway>(async () => ({ status: 201, body: { data: invitation() } })), h = await harness(api); await h.login();
  const operationId = randomUUID();
  for (const bad of [{ operationId, email: 'pas-une-adresse' }, { operationId: 'x', email: 'i@example.invalid' }, { operationId, email: 'i@example.invalid', validityDays: 0 },
    { operationId, email: 'i@example.invalid', validityDays: 15 }, { operationId, email: 'i@example.invalid', validityDays: 1.5 }, { operationId, email: 'i@example.invalid', code: 'ABCDE-FGHJK' },
    { operationId, email: 'i@example.invalid', level: 'COMMERCIAL' }, {}])
    expect((await h.post('platform/invitations', bad)).statusCode, JSON.stringify(bad)).toBe(400);
  expect(api).not.toHaveBeenCalled(); expect(h.current().platformInvite).toBeUndefined();
});

test('émission : réponse perdue ou panne gardent le même code ; un refus définitif libère et tire un autre code', async () => {
  const sent: string[] = []; let step = 0;
  const h = await harness(async command => {
    sent.push((command.body as { code: string }).code); step += 1;
    if (step === 1) throw new Error('synthetic_network_loss');
    if (step === 2) return { status: 503, body: { code: 'SERVICE_UNAVAILABLE' } };
    if (step === 3) return { status: 409, body: { code: 'PLATFORM_INVITATION_PENDING' } };
    if (step === 4) return { status: 409, body: { code: 'PLATFORM_CODE_TAKEN' } };
    return { status: 201, body: { data: invitation() } };
  });
  await h.login();
  const operationId = randomUUID(), body = { operationId, email: 'i@example.invalid' };
  expect((await h.post('platform/invitations', body)).statusCode).toBe(503);
  expect((await h.post('platform/invitations', body)).statusCode).toBe(503);
  expect(sent[1]).toBe(sent[0]); expect(h.current().platformInvite?.code).toBe(sent[0]);
  expect((await h.post('platform/invitations', body)).json().code).toBe('PLATFORM_INVITATION_PENDING');
  expect(sent[2]).toBe(sent[0]); expect(h.current().platformInvite).toBeUndefined();
  expect((await h.post('platform/invitations', { operationId: randomUUID(), email: 'autre@example.invalid' })).json().code).toBe('PLATFORM_CODE_TAKEN');
  expect(h.current().platformInvite).toBeUndefined();
  const last = await h.post('platform/invitations', { operationId: randomUUID(), email: 'autre@example.invalid' });
  expect(last.statusCode).toBe(201); expect(sent).toHaveLength(5); expect(new Set(sent).size).toBe(3);
});

test('révocation : version attendue et clé transmises, conflit et refus relayés, retrait de soi-même efface le code gardé', async () => {
  const targetId = randomUUID(), writes: PlatformRequest[] = []; let outcome: { status: number; body: unknown } = { status: 200, body: { data: operator({ id: targetId, status: 'REVOKED', version: 4, revokedAt: iso(), self: false }) } };
  const h = await harness(async command => { if (command.path.endsWith('/revoke')) { writes.push(structuredClone(command)); return outcome; } return { status: 201, body: { data: invitation() } }; });
  await h.login();
  const operationId = randomUUID();
  const done = await h.post(`platform/operators/${targetId.toUpperCase()}/revoke`, { operationId, version: 3 });
  expect(done.statusCode).toBe(200); expect(done.json().data.status).toBe('REVOKED');
  expect(writes[0]).toEqual({ method: 'POST', path: `/v1/platform/operators/${targetId}/revoke`, body: { operationId }, idempotencyKey: operationId, ifMatch: '"3"' });
  const invitationId = randomUUID(); outcome = { status: 200, body: { data: invitation({ id: invitationId, status: 'REVOKED', version: 2, revokedAt: iso() }) } };
  expect((await h.post(`platform/invitations/${invitationId}/revoke`, { operationId: randomUUID(), version: 1 })).json().data.status).toBe('REVOKED');
  expect(writes[1]).toMatchObject({ path: `/v1/platform/invitations/${invitationId}/revoke`, ifMatch: '"1"' });
  for (const [status, code] of [[412, 'VERSION_CONFLICT'], [409, 'LAST_PLATFORM_OPERATOR'], [409, 'PLATFORM_OPERATOR_REVOKED'], [404, 'NOT_FOUND']] as const) {
    outcome = { status, body: { code } };
    const response = await h.post(`platform/operators/${targetId}/revoke`, { operationId: randomUUID(), version: 3 });
    expect(response.statusCode).toBe(status); expect(response.json().code).toBe(code);
  }
  for (const bad of [{ operationId, version: 0 }, { operationId, version: 1.5 }, { operationId, version: 3_000_000_000 }, { operationId }, { version: 1 }, { operationId, version: 1, ifMatch: '"2"' }])
    expect((await h.post(`platform/operators/${targetId}/revoke`, bad)).statusCode, JSON.stringify(bad)).toBe(400);
  expect((await h.post('platform/operators/pas-un-uuid/revoke', { operationId, version: 1 })).statusCode).toBe(400);
  expect(writes).toHaveLength(6);
  // Un opérateur qui se retire perd aussi le code d'invitation que le relais gardait pour lui.
  await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' }); expect(h.current().platformInvite).toBeDefined();
  outcome = { status: 200, body: { data: operator({ status: 'REVOKED', version: 2, revokedAt: iso(), self: true }) } };
  expect((await h.post(`platform/operators/${randomUUID()}/revoke`, { operationId: randomUUID(), version: 1 })).statusCode).toBe(200);
  expect(h.current().platformInvite).toBeUndefined();
});

test('un autre compte ne reçoit ni le code émis ni l’acceptation en cours du précédent', async () => {
  const h = await harness(async command => command.method === 'POST' && command.path.endsWith('/preview') ? { status: 200, body: { data: preview() } } : { status: 201, body: { data: invitation() } });
  await h.login();
  await h.post('platform/invitations', { operationId: randomUUID(), email: 'i@example.invalid' }); await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' });
  expect(h.current().platformInvite).toBeDefined(); expect(h.current().platformJoin).toBeDefined();
  await h.login();
  expect(h.current().platformInvite).toBeDefined(); expect(h.current().platformJoin).toBeDefined();
  h.changeSubject('another-account'); await h.login();
  expect(h.current().platformInvite).toBeUndefined(); expect(h.current().platformJoin).toBeUndefined();
  expect((await h.get('platform/invitations')).json().pending).toBeUndefined();
  expect((await h.get('platform/join')).json()).toEqual({ pending: false, uncertain: false, accepted: false });
  expect((await h.post('platform/join/accept', {})).json().code).toBe('PLATFORM_JOIN_MISSING');
});

test('acceptation : aperçu des droits, confirmation liée à cet aperçu, puis envoi unique et résultat rendu', async () => {
  const calls: PlatformRequest[] = [], member = operator({ addedVia: 'INVITATION' }), stable = preview();
  const h = await harness(async command => {
    calls.push(structuredClone(command));
    if (command.path.endsWith('/preview')) return { status: 200, body: { data: stable } };
    return { status: 201, body: { data: { operator: member, ...rights }, requestId: 'r' } };
  });
  await h.login('/app/plateforme/rejoindre');
  const shown = await h.post('platform/join/preview', { code: ' abcde fghjk ' });
  expect(shown.statusCode).toBe(200); expect(shown.json().data).toMatchObject({ status: 'AVAILABLE', notGranted: rights.notGranted, rights: rights.rights });
  expect(calls[0]).toMatchObject({ method: 'POST', path: '/v1/platform/invitations/preview', body: { code: 'ABCDE-FGHJK' } });
  expect(calls[0]!.idempotencyKey).toBeUndefined();
  const confirmation = shown.json().confirmation as string; expect(confirmation.length).toBeGreaterThan(20);
  expect((await h.get('platform/join')).json()).toEqual({ pending: true, uncertain: false, accepted: false });
  expect((await h.get('platform/join')).body.includes('ABCDE')).toBe(false);
  // Sans la bonne confirmation, rien n'est envoyé.
  expect((await h.post('platform/join/accept', {})).json().code).toBe('PLATFORM_PREVIEW_CHANGED');
  expect((await h.post('platform/join/accept', { confirmation: 'faux' })).json().code).toBe('PLATFORM_PREVIEW_CHANGED');
  expect(calls).toHaveLength(1);
  const accepted = await h.post('platform/join/accept', { confirmation });
  expect(accepted.statusCode).toBe(201); expect(accepted.json().data.operator.id).toBe(member.id); expect(accepted.body.includes('requestId')).toBe(false);
  expect(calls.map(call => call.path)).toEqual(['/v1/platform/invitations/preview', '/v1/platform/invitations/preview', '/v1/platform/invitations/accept']);
  const send = calls[2]!; expect(send.idempotencyKey).toBe((send.body as { operationId: string }).operationId);
  expect(send.body).toEqual({ operationId: send.idempotencyKey, code: 'ABCDE-FGHJK' });
  expect(h.current().platformJoin?.code).toBeUndefined(); expect(h.current().platformJoin?.confirmation).toBeUndefined();
  expect((await h.get('platform/join')).json()).toEqual({ pending: false, uncertain: false, accepted: true });
  const replay = await h.post('platform/join/accept', {}); expect(replay.statusCode).toBe(200); expect(replay.json().data.operator.id).toBe(member.id); expect(calls).toHaveLength(3);
});

test('acceptation : un code mal formé est refusé avant tout appel ; les droits qui changent entre aperçu et envoi annulent la confirmation', async () => {
  let shown = preview(); const calls: PlatformRequest[] = [];
  const h = await harness(async command => { calls.push(structuredClone(command)); return command.path.endsWith('/preview') ? { status: 200, body: { data: shown } } : { status: 201, body: { data: { operator: operator(), ...rights } } }; });
  await h.login('/app/plateforme/rejoindre');
  for (const bad of ['', 'ABCDE', 'ABCDE-FGHJ0', 'ABCDE-FGHJI', 'ABCDEFGHJKL', 'ABCDE-FGHJK-LMNPQ']) expect((await h.post('platform/join/preview', { code: bad })).statusCode, bad).toBe(400);
  expect((await h.post('platform/join/preview', { code: 'ABCDE-FGHJK', extra: 1 })).statusCode).toBe(400);
  expect(calls).toHaveLength(0);
  const confirmation = (await h.post('platform/join/preview', { code: 'abcdefghjk' })).json().confirmation as string;
  shown = preview({ rights: [...rights.rights, 'MANAGE_PAYMENTS'] });
  expect((await h.post('platform/join/accept', { confirmation })).json().code).toBe('PLATFORM_PREVIEW_CHANGED');
  expect(calls.filter(call => call.path.endsWith('/accept'))).toHaveLength(0);
  expect((await h.post('platform/join/accept', { confirmation })).json().code).toBe('PLATFORM_PREVIEW_CHANGED');
  const fresh = (await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' })).json().confirmation as string;
  expect((await h.post('platform/join/accept', { confirmation: fresh })).statusCode).toBe(201);
});

test('acceptation : une réponse perdue se reprend par la même demande, sans nouvel aperçu ni autre opération', async () => {
  const calls: PlatformRequest[] = []; let lose = true; const member = operator({ addedVia: 'INVITATION' }), stable = preview();
  const h = await harness(async command => {
    calls.push(structuredClone(command));
    if (command.path.endsWith('/preview')) return { status: 200, body: { data: stable } };
    if (lose) { lose = false; throw new Error('synthetic_network_loss'); }
    return { status: 201, body: { data: { operator: member, ...rights } } };
  });
  await h.login('/app/plateforme/rejoindre');
  const confirmation = (await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' })).json().confirmation as string;
  expect((await h.post('platform/join/accept', { confirmation })).statusCode).toBe(503);
  expect(h.current().platformJoin).toMatchObject({ submitted: true, uncertain: true, code: 'ABCDE-FGHJK' });
  expect((await h.get('platform/join')).json()).toEqual({ pending: true, uncertain: true, accepted: false });
  // Un autre code ne remplace pas une demande dont le sort est inconnu.
  expect((await h.post('platform/join/preview', { code: 'ZZZZZ-ZZZZZ' })).json().code).toBe('PLATFORM_JOIN_IN_PROGRESS');
  const retry = await h.post('platform/join/accept', {});
  expect(retry.statusCode).toBe(201); expect(retry.json().data.operator.id).toBe(member.id);
  const sends = calls.filter(call => call.path.endsWith('/accept'));
  expect(sends).toHaveLength(2); expect(sends[1]).toEqual(sends[0]);
  expect(calls.filter(call => call.path.endsWith('/preview'))).toHaveLength(2);
  expect(h.current().platformJoin?.uncertain).toBeUndefined();
});

test('acceptation : un refus définitif abandonne l’état, une adresse non vérifiée ou un excès d’essais laissent corriger', async () => {
  let answer: { status: number; body: unknown } = { status: 409, body: { code: 'PLATFORM_INVITATION_USED' } }; const stable = preview();
  const h = await harness(async command => command.path.endsWith('/preview') ? { status: 200, body: { data: stable } } : answer);
  await h.login('/app/plateforme/rejoindre');
  const accept = async () => (await h.post('platform/join/accept', { confirmation: (await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' })).json().confirmation }));
  const terminal = await accept(); expect(terminal.statusCode).toBe(409); expect(terminal.json().code).toBe('PLATFORM_INVITATION_USED'); expect(h.current().platformJoin).toBeUndefined();
  for (const [status, code] of [[410, 'PLATFORM_INVITATION_EXPIRED'], [404, 'PLATFORM_INVITATION_INVALID']] as const) {
    answer = { status, body: { code } }; expect((await accept()).json().code).toBe(code); expect(h.current().platformJoin).toBeUndefined();
  }
  for (const [status, code] of [[403, 'EMAIL_VERIFICATION_REQUIRED'], [403, 'PLATFORM_INVITATION_EMAIL_MISMATCH'], [429, 'INVITATION_CODE_ATTEMPTS']] as const) {
    answer = { status, body: { code } };
    const response = await accept(); expect(response.statusCode).toBe(status); expect(response.json().code).toBe(code);
    expect(h.current().platformJoin).toMatchObject({ code: 'ABCDE-FGHJK' }); expect(h.current().platformJoin?.submitted).toBeUndefined(); expect(h.current().platformJoin?.uncertain).toBeUndefined();
    expect((await h.get('platform/join')).json()).toEqual({ pending: true, uncertain: false, accepted: false });
  }
});

test('un aperçu refusé ne laisse aucune trace, ni du code ni de la demande', async () => {
  const h = await harness(async () => ({ status: 404, body: { code: 'PLATFORM_INVITATION_INVALID' } })); await h.login('/app/plateforme/rejoindre');
  const response = await h.post('platform/join/preview', { code: 'ABCDE-FGHJK' });
  expect(response.statusCode).toBe(404); expect(response.json().code).toBe('PLATFORM_INVITATION_INVALID'); expect(response.body.includes('ABCDE')).toBe(false);
  expect(h.current().platformJoin).toBeUndefined();
});
