import { afterEach, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { createNotificationGateway, type NotificationGateway } from '../server/upstream.js';
import { saveNotificationPreferences } from '../client/notification-preferences-model.js';

const config = {origin:'https://drivy.example',apiBaseURL:'https://drivy.example/refonte',issuer:'https://identity.example/realm',
  clientId:'drivy-web',clientSecret:randomBytes(32).toString('hex'),development:false,host:'127.0.0.1',port:3002};
const secret = () => randomBytes(32).toString('base64url');
const apps: { close(): Promise<unknown> }[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); });
const prefs = {courseOffers:true,courseReminders:false,courseChanges:true,courseStaffAlerts:true};
const messagingPrefs = {...prefs,messagingPrivate:false,messagingGeneral:true,messagingMentions:true};

async function harness(notificationGateway: NotificationGateway) {
  const now = Date.now();
  const tokens: Tokens = { accessToken: secret(), refreshToken: secret(), expiresAt: now + 300_000,
    principal: { subject: randomUUID(), displayName: 'Test', email: 't@example.test', emailVerified: true } };
  const identity: IdentityProvider = {
    begin: vi.fn(async () => ({ transaction: { state: secret(), nonce: secret(), verifier: secret(), expiresAt: now + 300_000 }, url: 'https://identity.example/auth' })),
    complete: vi.fn(async () => tokens), password: vi.fn(async () => tokens), refresh: vi.fn(async () => tokens), revoke: vi.fn(async () => {}),
  };
  const store = new SessionStore();
  const app = await buildWebApp({ config, identity, store, notificationGateway, gateway: vi.fn(async () => ({ status: 200, body: {} })) });
  apps.push(app);
  const cookieFrom = (set: unknown) => (Array.isArray(set) ? set[0] : set)?.toString().split(';')[0] ?? '';
  let csrf = (await app.inject({ url: '/app/bff/session' })).json().csrfToken;
  const started = await app.inject({ method: 'POST', url: '/app/bff/login', payload: {}, headers: { origin: config.origin, 'x-csrf-token': csrf } });
  let cookie = cookieFrom(started.headers['set-cookie']);
  const state = store.get(cookie.split('=')[1])!.login!.state;
  cookie = cookieFrom((await app.inject({ url: `/app/bff/callback?code=one&state=${state}`, headers: { cookie } })).headers['set-cookie']);
  csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
  const put = (payload: unknown, headers: Record<string, string> = {}) => app.inject({ method: 'PUT', url: '/app/bff/me/notification-preferences',
    payload: payload as object, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf, 'content-type': 'application/json', ...headers } });
  return { app, tokens, cookie, put };
}

test('GET et PUT relaient la version et le corps, et exigent If-Match et CSRF', async () => {
  const gateway = vi.fn<NotificationGateway>(async request => request.method === 'GET'
    ? { status: 200, body: { data: { version: 3, ...prefs } }, etag: '"3"' }
    : { status: 200, body: { data: { version: 4, ...(request.body as object) } }, etag: '"4"' });
  const h = await harness(gateway);
  const read = await h.app.inject({ url: '/app/bff/me/notification-preferences', headers: { cookie: h.cookie } });
  expect(read.statusCode).toBe(200); expect(read.headers.etag).toBe('"3"');
  expect(gateway).toHaveBeenLastCalledWith({ method: 'GET' }, h.tokens.accessToken);
  expect((await h.put(prefs)).statusCode).toBe(428);
  expect((await h.put(prefs, { 'if-match': 'W/"3"' })).statusCode).toBe(400);
  expect((await h.put({ ...prefs, extra: true }, { 'if-match': '"3"' })).statusCode).toBe(400);
  expect((await h.put(prefs, { 'if-match': '"3"', 'x-csrf-token': 'nope' })).statusCode).toBe(403);
  expect((await h.put({ ...prefs, pad: 'x'.repeat(1_100) }, { 'if-match': '"3"' })).statusCode).toBe(413);
  const saved = await h.put(prefs, { 'if-match': '"3"' });
  expect(saved.statusCode).toBe(200); expect(saved.headers.etag).toBe('"4"');
  expect(gateway).toHaveBeenLastCalledWith({ method: 'PUT', body: prefs, ifMatch: '"3"' }, h.tokens.accessToken);
  expect(gateway).toHaveBeenCalledTimes(2);
  // Push devices belong to the app: not relayed.
  expect((await h.app.inject({ method: 'PUT', url: '/app/bff/me/push-devices', payload: {}, headers: { cookie: h.cookie } })).statusCode).toBe(404);
});

test('les catégories de messagerie sont relayées telles quelles, sans clé inconnue (#74)', async () => {
  const gateway = vi.fn<NotificationGateway>(async request => request.method === 'GET'
    ? { status: 200, body: { data: { version: 3, ...messagingPrefs } }, etag: '"3"' }
    : { status: 200, body: { data: { version: 4, ...(request.body as object) } }, etag: '"4"' });
  const h = await harness(gateway);
  const saved = await h.put(messagingPrefs, { 'if-match': '"3"' });
  expect(saved.statusCode).toBe(200);
  expect(gateway).toHaveBeenLastCalledWith({ method: 'PUT', body: messagingPrefs, ifMatch: '"3"' }, h.tokens.accessToken);
  expect((await h.put({ ...messagingPrefs, messagingEverything: true }, { 'if-match': '"3"' })).statusCode).toBe(400);
  expect((await h.put({ ...messagingPrefs, messagingGeneral: 'oui' }, { 'if-match': '"3"' })).statusCode).toBe(400);
  expect(gateway).toHaveBeenCalledTimes(1);
});

test('un conflit de version API reste un 412', async () => {
  const h = await harness(async () => ({ status: 412, body: { code: 'VERSION_CONFLICT' } }));
  const response = await h.put(prefs, { 'if-match': '"2"' });
  expect(response.statusCode).toBe(412); expect(response.json().code).toBe('VERSION_CONFLICT');
});

test('la passerelle nâ€™envoie que ce chemin, avec Bearer et If-Match', async () => {
  const api = Fastify({ logger: false }); const access = secret(); let seen: Record<string, unknown> = {};
  api.put('/refonte/v1/me/notification-preferences', async (request, reply) => {
    seen = { auth: request.headers.authorization, ifMatch: request.headers['if-match'], body: request.body, cookie: request.headers.cookie };
    return reply.header('ETag', '"5"').send({ data: { version: 5, ...prefs } });
  });
  apps.push(api);
  const origin = await api.listen({ host: '127.0.0.1', port: 0 });
  const result = await createNotificationGateway(origin + '/refonte')({ method: 'PUT', body: prefs, ifMatch: '"4"' }, access);
  expect(result).toMatchObject({ status: 200, etag: '"5"' });
  expect(seen).toEqual({ auth: `Bearer ${access}`, ifMatch: '"4"', body: prefs, cookie: undefined });
  await expect(createNotificationGateway(origin)({ method: 'PUT', body: prefs, ifMatch: '*' }, access)).rejects.toThrow();
});

test('le client envoie If-Match et signale un conflit', async () => {
  const send = vi.fn(async () => new Response(JSON.stringify({ code: 'VERSION_CONFLICT' }), { status: 412 }));
  expect(await saveNotificationPreferences(messagingPrefs, 7, 'csrf', send as unknown as typeof fetch)).toEqual({ ok: false, conflict: true, kind: 'conflict' });
  const init = (send.mock.calls[0] as unknown as [string, RequestInit])[1];
  expect((init.headers as Record<string, string>)['If-Match']).toBe('"7"');
  expect(init.method).toBe('PUT');
});
