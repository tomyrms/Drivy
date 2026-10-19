/** Audit regressions: real React/command store in Edge, synthetic BFF only. No external network. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5173';
assert(['127.0.0.1', 'localhost'].includes(new URL(origin).hostname), 'Loopback review required');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'artifacts/audit-20261018/regressions');
await mkdir(directory, { recursive: true });
const response = await fetch(`${origin}/app/test/visual.html`);
assert(response.ok, 'Start the local Vite server first');
const html = await response.text();
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], failures = [];
async function scenario(name, parameters, run) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'fr-CH' });
  await context.route('**/*', route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin !== origin) return route.abort();
    if (request.isNavigationRequest()) return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', `<head><script>window.__reviewBoot=${JSON.stringify({ parameters })}</script>`) });
    return route.continue();
  });
  const page = await context.newPage(); page.setDefaultTimeout(8000);
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(`${origin}/app/test/visual.html?${parameters}`);
    await run(page);
    assert.deepEqual(errors, [], 'No uncaught browser errors');
    checks.push(name);
  } catch (error) {
    failures.push({ name, error: String(error.message), stack: error.stack });
    await page.screenshot({ path: resolve(directory, `${name}-failed.png`), fullPage: true });
  } finally { await context.close(); }
}
async function editMember(page) {
  await page.getByRole('link', { name: 'Marie Dupont', exact: true }).click();
  await page.getByRole('heading', { name: 'Marie Dupont', exact: true }).waitFor();
  await page.getByRole('checkbox', { name: 'Administration', exact: true }).check();
  await page.getByLabel('Motif du changement', { exact: true }).fill('Remplacement pendant les vacances');
}
async function submitMember(page) {
  await page.getByRole('button', { name: 'Relire le changement', exact: true }).click();
  await page.getByRole('button', { name: 'Confirmer le changement d’accès', exact: true }).click();
}
try {
  for (const { width, abandon } of [{ width: 1440, abandon: false }, { width: 390, abandon: false }, { width: 1440, abandon: true }]) await scenario(`team-draft-after-retry-conflict-${width}${abandon ? '-abandon' : ''}`, 'page=team&shell=1', async page => {
    await page.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
    await editMember(page);
    await page.locator('summary').filter({ hasText: 'Autorisations particulières' }).click();
    await page.getByRole('checkbox', { name: 'Vérifier les permis', exact: true }).uncheck();
    await page.locator('summary').filter({ hasText: 'Autorisations particulières' }).click();
    await page.evaluate(() => {
      const original = window.fetch;
      const state = window.__audit = { attempts: 0, reloaded: false, versions: [], serverVersion: null };
      window.fetch = async (input, init) => {
        const url = new URL(String(input)), method = init?.method ?? 'GET';
        const reply = (status, body) => ({ status, ok: status < 400, url: url.href, headers: new Headers({ 'content-type': 'application/json' }), json: async () => body });
        if (method === 'PATCH' && /\/members\/[^/]+$/.test(url.pathname)) {
          state.attempts++;
          state.versions.push(new Headers(init.headers).get('if-match'));
          return state.attempts === 1 ? reply(503, { code: 'SERVICE_UNAVAILABLE' }) : reply(412, { code: 'VERSION_CONFLICT' });
        }
        if (/\/operations\/[^/]+$/.test(url.pathname)) return reply(404, { code: 'OPERATION_NOT_FOUND' });
        const result = await original(input, init);
        if (state.attempts >= 2 && method === 'GET' && url.pathname.endsWith('/members')) {
          const body = await result.json();
          const target = body.data.items.find(item => item.displayName === 'Marie Dupont');
          target.version++; target.grants = [...target.grants, 'cash_record'];
          state.serverVersion = target.version;
          state.reloaded = true;
          return reply(200, body);
        }
        return result;
      };
    });
    await submitMember(page);
    await page.getByRole('button', { name: 'Vérifier auprès de l’école', exact: true }).click();
    await page.getByRole('heading', { name: 'Demande introuvable auprès de l’école', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Renvoyer la même demande', exact: true }).click();
    await page.waitForFunction(() => window.__audit.reloaded);
    await page.getByRole('button', { name: 'Retirer l’accès…', exact: true }).waitFor();
    assert(await page.getByRole('checkbox', { name: 'Administration', exact: true }).isChecked(), 'The requested role must survive a rejected retry and newer server version');
    assert.equal(await page.getByLabel('Motif du changement', { exact: true }).inputValue(), 'Remplacement pendant les vacances');
    assert.equal(await page.getByRole('checkbox', { name: 'Vérifier les permis', exact: true, includeHidden: true }).isChecked(), false, 'Keep the explicitly removed permission');
    await page.getByText('Les accès ont changé', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Relire le changement', exact: true }).isEnabled(), false, 'Do not silently rebase permissions onto a newer version');
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Conflict notice must not cause horizontal overflow');
    await page.screenshot({ path: resolve(directory, `team-conflict-${width}.png`), fullPage: true });
    assert.equal(await page.getByRole('button', { name: 'Retirer l’accès…', exact: true }).isEnabled(), false);
    assert.equal(await page.evaluate(() => window.__audit.attempts), 2, 'No automatic extra write after a conflict');
    if (abandon) {
      await page.getByRole('button', { name: 'Tous les membres', exact: true }).click();
      await page.getByRole('button', { name: 'Quitter la page', exact: true }).click();
      await page.getByRole('link', { name: 'Marie Dupont', exact: true }).click();
      assert.equal(await page.getByText('Les accès ont changé', { exact: true }).count(), 0, 'An explicitly abandoned conflict must not return when reopening the same member');
    } else {
      const discard = page.getByRole('button', { name: 'Annuler les modifications', exact: true });
      await discard.focus(); await discard.press('Enter');
    }
    assert.equal(await page.getByRole('checkbox', { name: 'Administration', exact: true }).isChecked(), false);
    await page.locator('summary').filter({ hasText: 'Autorisations particulières' }).click();
    assert(await page.getByRole('checkbox', { name: 'Enregistrer les encaissements', exact: true }).isChecked(), 'Reset must use the new server state');
    assert.equal(await page.getByText('Les accès ont changé', { exact: true }).count(), 0);
    assert.equal(await page.getByRole('checkbox', { name: 'Vérifier les permis', exact: true }).isChecked(), true, 'Reset must restore the server permission');
    await page.getByRole('checkbox', { name: 'Administration', exact: true }).check();
    await page.getByLabel('Motif du changement', { exact: true }).fill('Nouvelle décision après relecture');
    await submitMember(page);
    await page.waitForFunction(() => window.__audit.attempts === 3);
    const state = await page.evaluate(() => window.__audit);
    assert.equal(state.versions[2], `"${state.serverVersion}"`, 'An explicit new decision must use the current server version');
  });
  await scenario('team-retry-success-clears-draft', 'page=team&shell=1', async page => {
    await editMember(page);
    await page.evaluate(() => {
      window.__reauthed = true;
      const original = window.fetch;
      let attempts = 0;
      window.fetch = async (input, init) => {
        const url = new URL(String(input));
        const reply = (status, body) => ({ status, ok: status < 400, url: url.href, headers: new Headers({ 'content-type': 'application/json' }), json: async () => body });
        if (init?.method === 'PATCH' && /\/members\/[^/]+$/.test(url.pathname) && ++attempts === 1) return reply(503, { code: 'SERVICE_UNAVAILABLE' });
        if (/\/operations\/[^/]+$/.test(url.pathname)) return reply(404, { code: 'OPERATION_NOT_FOUND' });
        return original(input, init);
      };
    });
    await submitMember(page);
    await page.getByRole('button', { name: 'Vérifier auprès de l’école', exact: true }).click();
    await page.getByRole('heading', { name: 'Demande introuvable auprès de l’école', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Renvoyer la même demande', exact: true }).click();
    await page.getByText('Résultat confirmé par l’école', { exact: true }).waitFor();
    await page.getByLabel('Motif du changement', { exact: true }).waitFor({ state: 'hidden' });
    assert(await page.getByRole('checkbox', { name: 'Administration', exact: true }).isChecked());
    assert.equal(await page.getByText('Les accès ont changé', { exact: true }).count(), 0, 'Own recovered write is not a concurrent conflict');
  });
  await scenario('team-success-clears-draft', 'page=team&shell=1', async page => {
    await editMember(page);
    await page.evaluate(() => { window.__reauthed = true; });
    await submitMember(page);
    await page.getByText('Les accès de Marie Dupont sont modifiés.', { exact: true }).first().waitFor();
    await page.getByLabel('Motif du changement', { exact: true }).waitFor({ state: 'hidden' });
    assert(await page.getByRole('checkbox', { name: 'Administration', exact: true }).isChecked());
    assert.equal(await page.getByText('Les accès ont changé', { exact: true }).count(), 0);
    await page.getByRole('button', { name: 'Tous les membres', exact: true }).click();
    await page.getByRole('link', { name: 'Luc Martin', exact: true }).click();
    assert.equal(await page.getByLabel('Motif du changement', { exact: true }).count(), 0, 'A different member must not inherit the previous draft');
  });
} finally {
  await writeFile(resolve(directory, 'results.json'), JSON.stringify({ scope: 'Real React and command recovery, synthetic BFF, Edge only', browser: browser.version(), checks, failures }, null, 2));
  await browser.close();
  console.log(JSON.stringify({ checks, failures, directory }, null, 2));
  if (failures.length) process.exitCode = 1;
}
