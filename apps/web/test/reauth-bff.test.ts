import { randomUUID } from 'node:crypto';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { buildWebApp } from '../server/app.js';
import { IdentityUnavailable, InvalidCredentials, recentAuthentication, type IdentityProvider } from '../server/oidc.js';
import { SessionStore, type Tokens } from '../server/session.js';
import { RateLimiter } from '../server/rate-limit.js';
import { identityConfirmationMessage } from '../client/identity-confirmation-model.js';
import { RequestFailure } from '../client/protocol.js';

const now = 1_792_238_400_000;
const config = { origin: 'https://drivy.example.test', apiBaseURL: 'https://api.example.test', issuer: 'https://identity.example.test',
  clientId: 'drivy-web', clientSecret: randomUUID(), development: false, host: '127.0.0.1', port: 3002 };
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); });

async function harness(limit = 30) {
  const store = new SessionStore(() => now), session = store.create();
  const original: Tokens = { accessToken: randomUUID(), refreshToken: randomUUID(), expiresAt: now + 300_000,
    principal: { subject: randomUUID(), displayName: 'Compte synthétique', email: 'compte@example.test', emailVerified: true } };
  session.tokens = original;
  const fresh: Tokens = { ...original, accessToken: randomUUID(), refreshToken: randomUUID(),
    principal: { ...original.principal, authenticatedAt: now / 1000 } };
  const identity: IdentityProvider = { begin: vi.fn(), complete: vi.fn(), password: vi.fn(async () => fresh),
    refresh: vi.fn(async () => original), revoke: vi.fn(async () => {}) };
  const app = await buildWebApp({ config, store, identity, now: () => now, entryLimiter: new RateLimiter(limit, 60_000, () => now) });
  apps.push(app);
  const headers = { cookie: `__Host-drivy-session=${session.id}`, origin: config.origin, 'x-csrf-token': session.csrf };
  const body = { email: 'compte@example.test', password: randomUUID() };
  const post = () => app.inject({ method: 'POST', url: '/app/bff/reauthenticate', headers, payload: body });
  return { app, store, session, original, fresh, identity, headers, body, post };
}

describe('Confirmation d’identité dans Drivy', () => {
  test('session indique la preuve manquante sans exposer sujet, jetons ou auth_time', async () => {
    const h = await harness();
    const state = await h.app.inject({ url: '/app/bff/session', headers: h.headers });
    expect(state.json()).toMatchObject({ authenticated: true, reauthenticationRequired: true });
    for (const secret of [h.original.accessToken, h.original.refreshToken!, h.original.principal.subject, 'authenticatedAt']) expect(state.body).not.toContain(secret);
  });
  test('même compte et preuve signée fraîche : rotation, intention conservée, aucune mutation GPS', async () => {
    const h = await harness();
    h.session.opening = { token: 'K7Q4-MX2P', operationId: randomUUID() };
    const opening = h.session.opening;
    const response = await h.post();
    expect(response.statusCode).toBe(200); expect(response.json()).toEqual({ ok: true });
    const set = response.headers['set-cookie'];
    const cookie = (Array.isArray(set) ? set[0] : set)!.split(';')[0]!;
    const next = h.store.get(cookie.split('=')[1])!;
    expect(h.store.isCurrent(h.session)).toBe(false);
    expect(next.tokens).toEqual(h.fresh); expect(next.opening).toBe(opening); expect(next.csrf).not.toBe(h.headers['x-csrf-token']);
    const status = await h.app.inject({ url: '/app/bff/session', headers: { cookie } });
    expect(status.json().reauthenticationRequired).toBe(false);
    expect(h.identity.revoke).not.toHaveBeenCalled();
    expect(response.body).not.toContain(h.body.password);
  });
  test.each([new InvalidCredentials(), new IdentityUnavailable()])('échec fournisseur conserve le compte et les intentions', async error => {
    const h = await harness(); vi.mocked(h.identity.password).mockRejectedValue(error);
    const response = await h.post();
    expect(response.statusCode).toBe(error instanceof InvalidCredentials ? 401 : 503);
    expect(h.session.tokens).toBe(h.original); expect(h.store.isCurrent(h.session)).toBe(true);
    expect(response.headers['set-cookie']).toBeUndefined(); expect(h.session.reauthenticating).toBeUndefined();
  });
  test('un autre compte est refusé avant rotation et son nouveau jeton est révoqué', async () => {
    const h = await harness(), other = { ...h.fresh, principal: { ...h.fresh.principal, subject: randomUUID() } };
    vi.mocked(h.identity.password).mockResolvedValue(other);
    const response = await h.post();
    expect(response.statusCode).toBe(409); expect(response.json().code).toBe('REAUTH_ACCOUNT_MISMATCH');
    expect(h.session.tokens).toBe(h.original); expect(h.store.isCurrent(h.session)).toBe(true);
    expect(h.identity.revoke).toHaveBeenCalledWith(other);
  });
  test.each([undefined, now / 1000 - 301, now / 1000 + 6, -1, now / 1000 + 0.5])('preuve absente ou invalide (%s) ne devient jamais une confirmation', async authenticatedAt => {
    const h = await harness();
    const principal = { ...h.original.principal, ...(authenticatedAt === undefined ? {} : { authenticatedAt }) };
    const candidate = { ...h.fresh, principal }; vi.mocked(h.identity.password).mockResolvedValue(candidate);
    const response = await h.post();
    expect(response.statusCode).toBe(503); expect(response.json().code).toBe('REAUTH_PROOF_UNAVAILABLE');
    expect(h.session.tokens).toBe(h.original); expect(h.store.isCurrent(h.session)).toBe(true);
    expect(h.identity.revoke).toHaveBeenCalledWith(candidate);
  });
  test('CSRF, session authentifiée et limite de tentatives sont imposés au serveur', async () => {
    const h = await harness(1);
    for (const headers of [{ ...h.headers, origin: 'https://other.example.test' }, { ...h.headers, 'x-csrf-token': 'wrong' }]) {
      expect((await h.app.inject({ method: 'POST', url: '/app/bff/reauthenticate', headers, payload: h.body })).statusCode).toBe(403);
    }
    expect((await h.app.inject({ method: 'POST', url: '/app/bff/reauthenticate', payload: h.body })).statusCode).toBe(401);
    expect(h.identity.password).not.toHaveBeenCalled();
    vi.mocked(h.identity.password).mockRejectedValue(new InvalidCredentials());
    expect((await h.post()).statusCode).toBe(401); expect((await h.post()).statusCode).toBe(429);
    expect(h.identity.password).toHaveBeenCalledTimes(1);
  });
  test('une déconnexion pendant la vérification ne ressuscite pas la session', async () => {
    const h = await harness(); let resolve!: (value: Tokens) => void;
    vi.mocked(h.identity.password).mockImplementation(() => new Promise(done => { resolve = done; }));
    const pending = h.post(); await vi.waitFor(() => expect(h.identity.password).toHaveBeenCalled());
    const concurrent = await h.post(); expect(concurrent.statusCode).toBe(409); expect(concurrent.json().code).toBe('REAUTH_IN_PROGRESS');
    h.store.destroy(h.session); resolve(h.fresh);
    expect((await pending).statusCode).toBe(401); expect(h.store.size).toBe(0); expect(h.identity.revoke).toHaveBeenCalledWith(h.fresh);
  });
  test('la fraîcheur utilise auth_time, jamais expiration du jeton ni son renouvellement', () => {
    const principal = { subject: 'synthetic', displayName: 'Compte', emailVerified: false };
    expect(recentAuthentication(principal, now, 300)).toBe(false);
    expect(recentAuthentication({ ...principal, authenticatedAt: now / 1000 - 300 }, now, 300)).toBe(true);
    expect(recentAuthentication({ ...principal, authenticatedAt: now / 1000 - 301 }, now, 300)).toBe(false);
  });
  test('le formulaire indique les refus sans reprendre les détails de transport', () => {
    expect(identityConfirmationMessage(new RequestFailure('REAUTH_ACCOUNT_MISMATCH', 409))).toContain('compte déjà connecté');
    expect(identityConfirmationMessage(new RequestFailure('INVALID_CREDENTIALS', 401))).toBe('E-mail ou mot de passe incorrect.');
    expect(identityConfirmationMessage(new Error('private provider detail'))).not.toContain('private');
  });
});
