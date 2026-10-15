import { randomBytes, randomUUID } from 'node:crypto';
import { afterEach, expect, test, vi } from 'vitest';
import { buildWebApp, normalizeAccessCode } from '../server/app.js';
import type { WebConfig } from '../server/config.js';
import { InvalidCredentials, type IdentityProvider } from '../server/oidc.js';
import { SessionStore, type Tokens } from '../server/session.js';
import type { AnonymousGateway } from '../server/upstream.js';

const config: WebConfig = { origin:'https://drivy.example.test', apiBaseURL:'https://api.example.test', issuer:'https://identity.example.test/realms/drivy',
  clientId:'drivy-web', clientSecret:randomBytes(32).toString('hex'), development:false, host:'127.0.0.1', port:3002 };
const secret = () => randomBytes(32).toString('base64url');
// Valeur générée à l'exécution : aucun secret n'est écrit dans le dépôt.
const chosenSecret = `Aa1!${randomUUID()}`;
const apps: Awaited<ReturnType<typeof buildWebApp>>[] = [];
afterEach(async () => { await Promise.all(apps.splice(0).map(app => app.close())); });

async function harness(anonymous: AnonymousGateway) {
  const tokens: Tokens = { accessToken: secret(), refreshToken: secret(), expiresAt: Date.now() + 300_000,
    principal: { subject: randomUUID(), displayName: 'Camille Recette', email: 'camille@example.test', emailVerified: false } };
  const identity: IdentityProvider = { begin: vi.fn(), complete: vi.fn(), refresh: vi.fn(async () => tokens), revoke: vi.fn(async () => {}),
    password: vi.fn(async (username: string, value: string) => { if (value !== chosenSecret) throw new InvalidCredentials(); return { ...tokens, principal: { ...tokens.principal, email: username } }; }) };
  const store = new SessionStore();
  const app = await buildWebApp({ config, identity, store, anonymousGateway: anonymous, gateway: vi.fn(async () => ({ status: 200, body: { data: { memberships: [] } } })) });
  apps.push(app);
  let cookie = '', csrf = (await app.inject({ url: '/app/bff/session' })).json().csrfToken as string;
  const post = async (url: string, payload: Record<string, unknown>) => {
    const response = await app.inject({ method: 'POST', url, payload, headers: { cookie, origin: config.origin, 'x-csrf-token': csrf } });
    const set = response.headers['set-cookie']; const created = (Array.isArray(set) ? set.find(item => item.includes('session=')) : set)?.split(';')[0] ?? '';
    if (created.includes('=') && !created.endsWith('=')) cookie = created;
    // Une session vient d'être ouverte : la page relit son jeton anti-falsification avant la requête suivante.
    csrf = (await app.inject({ url: '/app/bff/session', headers: { cookie } })).json().csrfToken;
    return response;
  };
  return { app, store, identity, post, session: () => store.get(cookie.split('=')[1]), status: () => app.inject({ url: '/app/bff/session', headers: { cookie } }) };
}

test('un code tapé se normalise ; un jeton de lien reste tel quel', () => {
  expect(normalizeAccessCode(' abcd efgh ')).toBe('ABCD-EFGH');
  expect(normalizeAccessCode('abcd-efgh')).toBe('ABCD-EFGH');
  const token = randomBytes(32).toString('base64url');
  expect(normalizeAccessCode(token)).toBe(token);
});

test('connexion par formulaire : session ouverte ; mauvais mot de passe refusé sans détail', async () => {
  const h = await harness(vi.fn());
  const refused = await h.post('/app/bff/password-login', { email: 'camille@example.test', password: 'faux' });
  expect(refused.statusCode).toBe(401); expect(refused.json().code).toBe('INVALID_CREDENTIALS');
  const accepted = await h.post('/app/bff/password-login', { email: 'camille@example.test', password: chosenSecret });
  expect(accepted.statusCode, accepted.body).toBe(200);
  expect((await h.status()).json()).toMatchObject({ authenticated: true, user: { displayName: 'Camille Recette' } });
  expect(JSON.stringify(accepted.json())).not.toContain(chosenSecret);
});

test('un code d’ouverture est gardé dans la session, puis le compte créé s’y connecte', async () => {
  const anonymous = vi.fn<AnonymousGateway>(async path => path === '/v1/access-codes/preview'
    ? { status: 200, body: { data: { kind: 'SCHOOL_OPENING', expiresAt: '2026-10-22T12:00:00.000Z' } } }
    : { status: 201, body: { data: { kind: 'SCHOOL_OPENING', email: 'camille@example.test' } } });
  const h = await harness(anonymous);
  const preview = await h.post('/app/bff/access-code', { code: 'abcd efgh' });
  expect(preview.statusCode, preview.body).toBe(200); expect(preview.json()).toEqual({ kind: 'SCHOOL_OPENING', expiresAt: '2026-10-22T12:00:00.000Z' });
  expect(anonymous).toHaveBeenLastCalledWith('/v1/access-codes/preview', { code: 'ABCD-EFGH' }, expect.any(String));
  expect(h.session()?.opening?.token).toBe('ABCD-EFGH');
  const created = await h.post('/app/bff/accounts', { code: 'ABCD-EFGH', firstName: 'Camille', lastName: 'Recette', email: 'camille@example.test', password: chosenSecret });
  expect(created.statusCode, created.body).toBe(200); expect(created.json()).toEqual({ kind: 'SCHOOL_OPENING' });
  expect(h.identity.password).toHaveBeenCalledWith('camille@example.test', chosenSecret);
  // L'intention d'ouverture survit à la rotation de session : le formulaire de l'école s'ouvre ensuite.
  expect(h.session()?.tokens).toBeDefined(); expect(h.session()?.opening?.token).toBe('ABCD-EFGH');
});

test('un code d’élève ne garde rien ; les refus de l’API passent tels quels', async () => {
  const anonymous = vi.fn<AnonymousGateway>(async path => path === '/v1/access-codes/preview'
    ? { status: 200, body: { data: { kind: 'LEARNER_INVITATION', schoolName: 'École de recette', roles: ['LEARNER'], expiresAt: '2026-10-22T12:00:00.000Z' } } }
    : { status: 409, body: { code: 'ACCOUNT_EXISTS', title: 'Un compte existe déjà.' } });
  const h = await harness(anonymous);
  const preview = await h.post('/app/bff/access-code', { code: 'WXYZ-2345' });
  expect(preview.json()).toEqual({ kind: 'LEARNER_INVITATION', schoolName: 'École de recette', expiresAt: '2026-10-22T12:00:00.000Z' });
  expect(h.session()).toBeUndefined();
  const refused = await h.post('/app/bff/accounts', { code: 'WXYZ-2345', firstName: 'Camille', lastName: 'Recette', email: 'camille@example.test', password: chosenSecret });
  expect(refused.statusCode).toBe(409); expect(refused.json().code).toBe('ACCOUNT_EXISTS');
  expect(h.identity.password).not.toHaveBeenCalled();
  expect((await h.post('/app/bff/access-code', { code: 'pas un code' })).statusCode).toBe(400);
});
