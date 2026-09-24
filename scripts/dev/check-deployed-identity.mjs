/** Contrôle séparé et explicite de l'environnement HTTPS avec un compte sonde sans lien métier.
 * Usage : node scripts/dev/check-deployed-identity.mjs
 * Préparation opérateur : infra/dev/.state/deployed-probe.json, jamais les identifiants de luc.
 * { "username":"probe-oidc-...", "password":"...", "subject":"UUID Keycloak" }
 * Le mot de passe du compte sonde doit être non temporaire ; aucun mot de passe n'est changé ici.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const origin = 'https://drivy.shulker.ch';
const issuer = `${origin}/identity/realms/drivy`;
const clientId = 'drivy-apple';
const callbackURI = 'ch.drivy.qualification:/oauth/callback';
let stage = 'Lecture du compte sonde privé';
function demand(value) { if (!value) throw new Error('Contrôle refusé'); }
async function request(url, init = {}) {
  demand(new URL(url).origin === origin);
  return fetch(url, { ...init, redirect: 'manual', signal: AbortSignal.timeout(15_000) });
}
async function main() {
  const account = JSON.parse(await readFile(new URL('../../infra/dev/.state/deployed-probe.json', import.meta.url), 'utf8'));
  demand(/^probe-oidc-[a-z0-9-]{8,40}$/.test(account.username ?? '') && typeof account.password === 'string' && account.password.length >= 32 &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(account.subject ?? ''));
  const verifier = randomBytes(32).toString('base64url'), nonce = randomBytes(32).toString('base64url'), state = randomBytes(32).toString('base64url');
  let browser, context, timeout;
  let deliver = () => {};
  const callback = new Promise(resolve => { deliver = resolve; });
  try {
    stage = 'Découverte HTTPS du fournisseur';
    const discoveryResponse = await request(`${issuer}/.well-known/openid-configuration`);
    demand(discoveryResponse.ok);
    const discovery = await discoveryResponse.json();
    demand(discovery.issuer === issuer && discovery.authorization_endpoint === `${issuer}/protocol/openid-connect/auth` &&
      discovery.token_endpoint === `${issuer}/protocol/openid-connect/token` && discovery.jwks_uri === `${issuer}/protocol/openid-connect/certs`);
    stage = 'Obligation de PKCE S256 imposée par le fournisseur HTTPS';
    const withoutChallenge = new URL(discovery.authorization_endpoint);
    withoutChallenge.search = new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: callbackURI,
      scope: 'openid profile', state, nonce }).toString();
    const rejectedAuthorization = async url => {
      const response = await request(url);
      const location = response.headers.get('location');
      const returned = location ? new URL(location) : null;
      return response.status === 400 || (response.status === 302 && returned?.href.split('?')[0] === callbackURI &&
        returned.searchParams.get('error') === 'invalid_request' && !returned.searchParams.has('code'));
    };
    demand(await rejectedAuthorization(withoutChallenge));
    const plainChallenge = new URL(withoutChallenge);
    plainChallenge.searchParams.set('code_challenge', verifier);
    plainChallenge.searchParams.set('code_challenge_method', 'plain');
    demand(await rejectedAuthorization(plainChallenge));
    stage = 'Connexion réelle du compte sonde dans un navigateur isolé';
    browser = await chromium.launch({ channel: 'msedge', headless: true });
    context = await browser.newContext();
    await context.route('**/*', async route => {
      try {
        const target = new URL(route.request().url());
        if (target.origin !== origin) return route.abort();
        if (route.request().method() === 'POST' && target.pathname.includes('/identity/realms/drivy/login-actions/')) {
          const response = await route.fetch({ maxRedirects: 0, timeout: 15_000 });
          const location = response.headers().location;
          if (response.status() === 302 && location?.startsWith(`${callbackURI}?`)) {
            await route.abort('aborted'); await response.dispose(); deliver(location); return;
          }
          return route.fulfill({ response });
        }
        return route.continue();
      } catch { deliver(null); await route.abort().catch(() => {}); }
    });
    const page = await context.newPage();
    const auth = new URL(discovery.authorization_endpoint);
    auth.search = new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: callbackURI, scope: 'openid profile',
      state, nonce, code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256', prompt: 'login' }).toString();
    await page.goto(auth.href, { waitUntil: 'domcontentloaded' });
    await page.locator('input[name="username"]').fill(account.username);
    await page.locator('input[name="password"]').fill(account.password);
    await page.locator('input[type="submit"],button[type="submit"]').first().click({ noWaitAfter: true });
    const location = await Promise.race([callback, new Promise(resolve => { timeout = setTimeout(() => resolve(null), 15_000); })]);
    demand(typeof location === 'string');
    await page.goto('about:blank');
    const returned = new URL(location);
    demand(returned.href.split('?')[0] === callbackURI && returned.searchParams.get('state') === state && returned.searchParams.get('iss') === issuer && returned.searchParams.has('code'));
    stage = 'Échange du code et vérification des signatures, audiences, subject et nonce';
    const exchange = await request(discovery.token_endpoint, { method: 'POST', body: new URLSearchParams({ grant_type: 'authorization_code',
      client_id: clientId, code: returned.searchParams.get('code'), code_verifier: verifier, redirect_uri: callbackURI }) });
    demand(exchange.ok);
    const tokens = await exchange.json();
    const jwks = createRemoteJWKSet(new URL(discovery.jwks_uri));
    const access = await jwtVerify(tokens.access_token, jwks, { issuer, audience: 'drivy-api', algorithms: ['RS256'], requiredClaims: ['sub', 'iat', 'exp'] });
    const identity = await jwtVerify(tokens.id_token, jwks, { issuer, audience: clientId, algorithms: ['RS256'], requiredClaims: ['sub', 'iat', 'exp'] });
    demand(access.payload.sub === account.subject && identity.payload.sub === account.subject && identity.payload.nonce === nonce);
    stage = 'API HTTPS : identité sonde reconnue mais sans aucun droit scolaire';
    const me = await request(`${origin}/refonte/v1/me`, { headers: { Authorization: `Bearer ${tokens.access_token}` } });
    const problem = await me.json();
    demand(me.status === 403 && problem.code === 'IDENTITY_NOT_LINKED');
    const idDenied = await request(`${origin}/refonte/v1/me`, { headers: { Authorization: `Bearer ${tokens.id_token}` } });
    demand(idDenied.status === 401);
    stage = 'Rotation du refresh token standard du compte sonde';
    const refresh = await request(discovery.token_endpoint, { method: 'POST', body: new URLSearchParams({ grant_type: 'refresh_token', client_id: clientId, refresh_token: tokens.refresh_token }) });
    demand(refresh.ok);
    const renewed = await refresh.json();
    const verifiedRenewed = await jwtVerify(renewed.access_token, jwks, { issuer, audience: 'drivy-api', algorithms: ['RS256'], requiredClaims: ['sub', 'iat', 'exp'] });
    demand(verifiedRenewed.payload.sub === account.subject);
    const renewedMe = await request(`${origin}/refonte/v1/me`, { headers: { Authorization: `Bearer ${renewed.access_token}` } });
    demand(renewedMe.status === 403 && (await renewedMe.json()).code === 'IDENTITY_NOT_LINKED');
    const replay = await request(discovery.token_endpoint, { method: 'POST', body: new URLSearchParams({ grant_type: 'refresh_token', client_id: clientId, refresh_token: tokens.refresh_token }) });
    demand(replay.status === 400);
    await writeFile(new URL('../../infra/dev/.state/deployed-check-result.json', import.meta.url), JSON.stringify({ checkedAt: new Date().toISOString(),
      issuer, browser: browser.version(), result: 'PASSED',
      checks: { discoveryStatus: discoveryResponse.status, missingPKCERejected: true, plainPKCERejected: true, tokenExchangeStatus: exchange.status,
        signaturesIssuerAudienceSubjectNonceVerified: true, meStatus: me.status, meCode: problem.code, idTokenStatus: idDenied.status,
        refreshStatus: refresh.status, renewedMeStatus: renewedMe.status, refreshReplayStatus: replay.status },
      scope: 'OIDC HTTPS navigateur/PKCE, rotation et API sans lien métier ; compte luc et client iOS non utilisés.' }, null, 2) + '\n', { mode: 0o600 });
    console.log('Contrôle sonde réussi : HTTPS, navigateur, PKCE, jetons et refus API attendu sans lien métier. Aucun mot de passe modifié.');
  } finally { if (timeout) clearTimeout(timeout); await context?.close(); await browser?.close(); }
}
main().catch(() => { console.error(`Contrôle sonde interrompu : ${stage}. Aucun jeton, formulaire ou mot de passe affiché.`); process.exitCode = 1; });
