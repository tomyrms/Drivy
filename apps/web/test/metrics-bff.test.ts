import { afterEach, describe, expect, test, vi } from 'vitest';
import { randomBytes, randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import { buildWebApp } from '../server/app.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { IdentityProvider } from '../server/oidc.js';
import { createMetricsExportGateway, type MetricsExportGateway, type SchoolGateway } from '../server/upstream.js';

/** Pilotage de l'école (#373, T02) : relais des lectures et téléchargement CSV par le BFF, sans jamais stocker ni élargir un droit. */
const config = {origin:'https://drivy.example',apiBaseURL:'https://drivy.example/refonte',issuer:'https://identity.example/realm',
  clientId:'drivy-web',clientSecret:randomBytes(32).toString('hex'),development:false,host:'127.0.0.1',port:3002};
const secret = () => randomBytes(32).toString('base64url');
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); });
const envelope = (data: unknown) => ({ data, requestId: randomUUID(), serverTime: '2026-10-28T17:00:00.000Z' });

async function harness(schoolGateway: SchoolGateway, extra: { metricsExportGateway?: MetricsExportGateway } = {}) {
  const now = Date.now();
  const tokens: Tokens = { accessToken: secret(), refreshToken: secret(), expiresAt: now + 300_000,
    principal: { subject: randomUUID(), displayName: 'Test local', email: 'test@example.test', emailVerified: true } };
  const identity: IdentityProvider = {
    begin: vi.fn(async () => ({ transaction: { state: secret(), nonce: secret(), verifier: secret(), expiresAt: now + 300_000 }, url: 'https://identity.example/auth' })),
    complete: vi.fn(async () => tokens), password: vi.fn(async () => tokens), refresh: vi.fn(async () => tokens), revoke: vi.fn(async () => {}),
  };
  const store = new SessionStore();
  const app = await buildWebApp({ config, identity, store, schoolGateway, ...extra, gateway: vi.fn(async () => ({ status: 200, body: {} })) });
  apps.push(app);
  let cookie = ''; let csrf = '';
  const cookieFrom = (set: unknown) => (Array.isArray(set) ? set[0] : set)?.toString().split(';')[0] ?? '';
  csrf = (await app.inject({ url: '/app/bff/session' })).json().csrfToken;
  const login = async () => {
    const started = await app.inject({ method: 'POST', url: '/app/bff/login', payload: {}, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf } });
    cookie = cookieFrom(started.headers['set-cookie']);
    const state = store.get(cookie.split('=')[1])!.login!.state;
    const callback = await app.inject({ url: `/app/bff/callback?code=one&state=${state}`, headers: { cookie } });
    cookie = cookieFrom(callback.headers['set-cookie']);
    csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
  };
  const write = (method: 'POST', url: string, payload: unknown, headers: Record<string, string> = {}) =>
    app.inject({ method, url, payload: payload as never, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf, ...headers } });
  return { app, tokens, login, write, get: (url: string) => app.inject({ url, headers: { cookie } }), cookie: () => cookie, csrf: () => csrf };
}

const school = randomUUID();
const base = `/app/bff/schools/${school}/metrics`;
const month = 'from=2026-10-01&toExclusive=2026-11-01';

describe('lectures du pilotage', () => {
  test('relaie les lectures avec des dates civiles et refuse tout le reste avant un appel amont', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(gateway);
    expect((await h.get(`${base}?domain=activity&${month}`)).statusCode).toBe(401);
    await h.login();
    const member = randomUUID();
    expect((await h.get(`${base}?domain=finance&${month}&compare=previous-month&breakdown=instructor&scope=school&instructorMembershipId=${member}&categoryCode=B&productKey=b-45`)).statusCode).toBe(200);
    expect((await h.get(`${base}/definitions`)).statusCode).toBe(200);
    expect((await h.get(`${base}/series?${month}&granularity=week&measures=L01,F01`)).statusCode).toBe(200);
    expect((await h.get(`${base}/details?measure=F06&part=a&${month}&limit=25&expectedLineCount=5&expectedAmountCents=57000&bucketFrom=2026-10-05&bucketToExclusive=2026-10-12`)).statusCode).toBe(200);
    const sent = gateway.mock.calls.map(([request]) => request);
    expect(sent[0]).toMatchObject({ method: 'GET', path: `/v1/schools/${school}/metrics` });
    expect(sent[0]!.query).toContain(`instructorMembershipId=${member}`);
    expect(sent[2]).toMatchObject({ path: `/v1/schools/${school}/metrics/series`, query: expect.stringContaining('measures=L01%2CF01') });
    const calls = gateway.mock.calls.length;
    for (const bad of [
      `${base}?domain=autre&${month}`, `${base}?domain=activity&from=2026-10-01T00:00:00Z&toExclusive=2026-11-01`, `${base}?domain=activity&${month}&extra=1`,
      `${base}?domain=activity&${month}&domain=finance`, `${base}?domain=activity&from=2026-1-1&toExclusive=2026-11-01`,
      `${base}/series?${month}&granularity=year&measures=L01`, `${base}/series?${month}&granularity=week&measures=L01,L02,L03,L04,L05,L06`,
      `${base}/details?measure=l01&${month}`, `${base}/details?measure=F06&part=c&${month}`,
      `${base}/definitions?x=1`, `${base}/unknown`,
    ]) expect((await h.get(bad)).statusCode, bad).toBe(404);
    // Une date-heure reste exigée pour les plannings : la règle civile ne vaut que pour le pilotage.
    expect((await h.get(`/app/bff/schools/${school}/lessons?from=2026-10-01&to=2026-11-01`)).statusCode).toBe(404);
    expect((await h.write('POST', base, { operationId: randomUUID(), domain: 'activity' }, { 'idempotency-key': randomUUID() })).statusCode).toBe(404);
    expect(gateway.mock.calls.length).toBe(calls);
  });

  test('un refus de droit de l’API traverse le relais avec son code, sans montant ni cache', async () => {
    const gateway = vi.fn<SchoolGateway>(async () => ({ status: 403, body: { code: 'METRIC_SCOPE_FORBIDDEN', title: 'Texte amont ignoré', amountCents: 57000 } }));
    const h = await harness(gateway); await h.login();
    const response = await h.get(`${base}?domain=finance&${month}`);
    expect(response.statusCode).toBe(403);
    expect(response.json().code).toBe('METRIC_SCOPE_FORBIDDEN');
    expect(response.body).not.toContain('57000');
    expect(response.headers['cache-control']).toBe('no-store');
  });
});

describe('export CSV du pilotage', () => {
  const exportURL = `${base}/exports`;
  const exportBody = { measure: 'F01', from: '2026-10-01', toExclusive: '2026-11-01', expectedLineCount: 5 };

  test('exige session et jeton CSRF, relaie la commande et reconstruit le nom du fichier', async () => {
    const csv = '﻿#complete;true\r\nline_kind;line_id\r\n';
    const exporter = vi.fn<MetricsExportGateway>(async () => ({ status: 200, csv, drift: true }));
    const schools = vi.fn<SchoolGateway>(async () => ({ status: 200, body: envelope({}) }));
    const h = await harness(schools, { metricsExportGateway: exporter });
    expect((await h.app.inject({ method: 'POST', url: exportURL, payload: exportBody, headers: { origin: config.origin, 'content-type': 'application/json' } })).statusCode).toBe(401);
    await h.login();
    expect((await h.write('POST', exportURL, exportBody, { 'x-csrf-token': '' })).statusCode).toBe(403);
    expect((await h.write('POST', exportURL, exportBody, { origin: 'https://evil.example' })).statusCode).toBe(403);
    expect(exporter).not.toHaveBeenCalled();
    const response = await h.write('POST', exportURL, exportBody);
    expect(response.statusCode).toBe(200);
    expect(response.headers['content-type']).toBe('text/csv; charset=utf-8');
    expect(response.headers['content-disposition']).toBe('attachment; filename="drivy-F01-2026-10-01_2026-11-01.csv"');
    expect(response.headers['x-metrics-drift']).toBe('true');
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body).toBe(csv);
    expect(exporter).toHaveBeenCalledWith({ schoolId: school, body: exportBody }, h.tokens.accessToken);
    expect(schools).not.toHaveBeenCalled();
    const part = await h.write('POST', exportURL, { ...exportBody, measure: 'F06', part: 'b' });
    expect(part.headers['content-disposition']).toBe('attachment; filename="drivy-F06b-2026-10-01_2026-11-01.csv"');
  });

  test('refuse une commande mal formée avant tout appel amont et laisse passer le code de refus', async () => {
    const exporter = vi.fn<MetricsExportGateway>(async () => ({ status: 403, body: { code: 'ACCESS_REVOKED' } }));
    const h = await harness(vi.fn<SchoolGateway>(), { metricsExportGateway: exporter }); await h.login();
    for (const payload of [{}, { measure: 'F01' }, { ...exportBody, measure: 'F01\r\nSet-Cookie: x=1' }, { ...exportBody, from: '2026-10' }, { ...exportBody, part: 'c' }, { ...exportBody, note: 'x'.repeat(5_000) }])
      expect((await h.write('POST', exportURL, payload)).statusCode, JSON.stringify(payload).slice(0, 60)).toBe(400);
    const array = await h.app.inject({ method: 'POST', url: exportURL, payload: [exportBody], headers: { cookie: h.cookie(), origin: config.origin, 'x-csrf-token': h.csrf() } });
    expect(array.statusCode).toBe(400);
    expect((await h.write('POST', '/app/bff/schools/not-a-uuid/metrics/exports', exportBody)).statusCode).toBe(404);
    expect(exporter).not.toHaveBeenCalled();
    const refused = await h.write('POST', exportURL, exportBody);
    expect(refused.statusCode).toBe(403);
    expect(refused.json().code).toBe('ACCESS_REVOKED');
    expect(refused.headers['content-type']).not.toContain('text/csv');
    exporter.mockResolvedValueOnce({ status: 413, body: { code: 'EXPORT_TOO_LARGE' } });
    expect((await h.write('POST', exportURL, exportBody)).json().code).toBe('EXPORT_TOO_LARGE');
  });

  test('échange HTTP réel : chemin fixe, Bearer, aucun cookie, refus des redirections et des réponses inattendues', async () => {
    const api = Fastify({ logger: false });
    const access = secret(); let seen: unknown;
    api.post('/refonte/v1/schools/:schoolId/metrics/exports', async (request, reply) => {
      expect(request.headers.authorization).toBe(`Bearer ${access}`);
      expect(request.headers.cookie).toBeUndefined();
      seen = request.body;
      const measure = (request.body as { measure: string }).measure;
      if (measure === 'F02') return reply.redirect('/refonte/v1/me');
      if (measure === 'F03') return reply.type('application/json').send({ data: 1 });
      if (measure === 'F04') return reply.code(403).type('application/problem+json').send({ code: 'ACCESS_REVOKED' });
      return reply.type('text/csv; charset=utf-8').header('x-metrics-drift', 'true').send('﻿#complete;true\r\n');
    });
    try {
      const origin = await api.listen({ host: '127.0.0.1', port: 0 });
      const gateway = createMetricsExportGateway(origin + '/refonte');
      expect(await gateway({ schoolId: school, body: exportBody }, access)).toEqual({ status: 200, csv: '﻿#complete;true\r\n', drift: true });
      expect(seen).toEqual(exportBody);
      expect(await gateway({ schoolId: school, body: { ...exportBody, measure: 'F04' } }, access)).toEqual({ status: 403, body: { code: 'ACCESS_REVOKED' } });
      await expect(gateway({ schoolId: school, body: { ...exportBody, measure: 'F02' } }, access)).rejects.toThrow();
      await expect(gateway({ schoolId: school, body: { ...exportBody, measure: 'F03' } }, access)).rejects.toThrow();
      await expect(gateway({ schoolId: 'x/../me', body: exportBody }, access)).rejects.toThrow();
    } finally { await api.close(); }
  });
});
