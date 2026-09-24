/** Recette HTTPS avec un compte sonde éphémère sans lien métier, jamais le compte luc.
 * Préparer infra/dev/.state/deployed-web-probe.json puis supprimer le compte côté IdP.
 * Aucun jeton, cookie, mot de passe ou écran de connexion n'est enregistré.
 */
import { readFile, writeFile } from 'node:fs/promises';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = 'https://drivy.shulker.ch';
let stage = 'lecture de la sonde privée';
const checks = [];
function demand(value, label) { if (!value) throw new Error(label); checks.push(label); }
async function main() {
  await writeFile(new URL('../../infra/dev/.state/deployed-web-check-result.json', import.meta.url), JSON.stringify({
    checkedAt: new Date().toISOString(), result: 'RUNNING', scope: 'Preuve précédente invalidée avant le contrôle.'
  }) + '\n', { mode: 0o600 });
  const probe = JSON.parse(await readFile(new URL('../../infra/dev/.state/deployed-web-probe.json', import.meta.url), 'utf8'));
  if (!/^probe-web-[a-f0-9]{16}$/.test(probe.username ?? '') || (probe.password?.length ?? 0) < 32) throw new Error('Sonde invalide');
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    stage = 'accueil web HTTPS';
    const home = await page.goto(`${origin}/app`, { waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Se connecter', exact: true }).waitFor();
    demand(home.status() === 200 && home.headers()['content-security-policy']?.includes("default-src 'none'") &&
      home.headers()['content-security-policy']?.includes("script-src 'self'"), 'Accueil HTTPS et CSP');
    const initialResponse = await context.request.get(`${origin}/app/bff/session`);
    const initial = await initialResponse.json();
    demand(initialResponse.headers()['cache-control'] === 'no-store' && !initial.authenticated, 'Session anonyme sans cache');
    const before = (await context.cookies(origin)).find(item => item.name === '__Host-drivy-session');
    demand(before?.secure && before.httpOnly && before.sameSite === 'Lax' && before.path === '/' && before.domain === 'drivy.shulker.ch', 'Cookie sécurisé limité à cet hôte');
    stage = 'connexion par le bouton et formulaire IdP';
    await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
    await page.waitForURL(url => url.pathname.includes('/protocol/openid-connect/auth'));
    const auth = new URL(page.url());
    demand(auth.searchParams.get('client_id') === 'drivy-web' && auth.searchParams.get('code_challenge_method') === 'S256' &&
      auth.searchParams.get('redirect_uri') === `${origin}/app/bff/callback`, 'Client web et callback exact sous PKCE S256');
    await page.locator('input[name="username"]').fill(probe.username);
    await page.locator('input[name="password"]').fill(probe.password);
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    await page.waitForURL(`${origin}/app`);
    await page.getByRole('heading', { name: 'Bienvenue dans Drivy' }).waitFor();
    await page.getByRole('heading', { name: 'Votre école n’apparaît pas encore' }).waitFor();
    demand(true, 'Connexion OIDC réelle et absence de droit scolaire inventé');
    const sessionResponse = await context.request.get(`${origin}/app/bff/session`);
    const session = await sessionResponse.json();
    const after = (await context.cookies(origin)).find(item => item.name === '__Host-drivy-session');
    demand(session.authenticated && after.value !== before.value && session.csrfToken !== initial.csrfToken, 'Rotation de session et du CSRF après authentification');
    demand(!Object.keys(session).some(key => /token/i.test(key) && key !== 'csrfToken') &&
      await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'Aucun jeton OAuth ni stockage de données dans le navigateur');
    stage = 'accès BFF/API et déconnexion';
    const me = await context.request.get(`${origin}/app/bff/me`);
    demand(me.status() === 403 && (await me.json()).code === 'IDENTITY_NOT_LINKED', 'API PostgreSQL : identité reconnue, aucun lien métier');
    const forged = await context.request.post(`${origin}/app/bff/logout`, { headers: { Origin: 'https://foreign.example', 'X-CSRF-Token': session.csrfToken }, data: {} });
    demand(forged.status() === 403, 'Origine étrangère refusée malgré le CSRF correct');
    const stale = await context.request.post(`${origin}/app/bff/logout`, { headers: { Origin: origin, 'X-CSRF-Token': initial.csrfToken }, data: {} });
    demand(stale.status() === 403, 'Ancien CSRF refusé après rotation');
    const logout = await context.request.post(`${origin}/app/bff/logout`, { headers: { Origin: origin, 'X-CSRF-Token': session.csrfToken }, data: {} });
    demand(logout.status() === 200 && (await context.request.get(`${origin}/app/bff/me`)).status() === 401, 'Déconnexion locale et accès privé refusé');
    await writeFile(new URL('../../infra/dev/.state/deployed-web-check-result.json', import.meta.url), JSON.stringify({
      checkedAt: new Date().toISOString(), origin, browser: browser.version(), result: 'PASSED', passed: checks.length, checks,
      scope: 'Portail HTTPS, OIDC confidentiel, BFF et API sans lien métier. Aucun compte utilisateur existant ni email utilisé.'
    }, null, 2) + '\n', { mode: 0o600 });
    console.log(`${checks.length} contrôles HTTPS du portail réussis ; sonde à supprimer côté identité.`);
  } finally { await browser.close(); }
}
main().catch(() => { console.error(`Contrôle web HTTPS interrompu : ${stage}. Aucun secret journalisé.`); process.exitCode = 1; });
