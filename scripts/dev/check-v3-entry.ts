/** Built client and real anonymous BFF. Failed chunk is deliberate fault injection, not a production outage. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '../../infra/dev/browser.js';
import { buildWebApp } from '../../apps/web/server/app.js';
const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = resolve(root, 'artifacts/v3-20261018/entry-recovery');
await mkdir(directory, { recursive: true });
const identity = { async begin() { throw Error('ANONYMOUS_ONLY'); }, async complete() { throw Error('ANONYMOUS_ONLY'); }, async refresh() { throw Error('ANONYMOUS_ONLY'); }, async revoke() {} };
const config = { origin: 'http://127.0.0.1:0', apiBaseURL: 'http://127.0.0.1:9', issuer: 'http://127.0.0.1:9', clientId: 'measure', clientSecret: 'synthetic-measurement-only', development: true, host: '127.0.0.1', port: 0 };
const app = await buildWebApp({ config, identity, staticRoot: resolve(root, 'apps/web/dist/client') });
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks: string[] = [];
try {
  const origin = await app.listen({ host: '127.0.0.1', port: 0 });
  config.origin = origin;
  for (const [name, path, chunk, exchange] of [
    ['preferences', '/app/preferences', 'preferences-', ''],
    ['console', '/app/gestion/00000000-0000-4000-8000-000000000000/agenda', 'Console-', ''],
    ['invitation', '/app/invitation', 'App-', '/app/bff/invitation'],
    ['opening', '/app/ouvrir', 'school-opening-', '/app/bff/opening'],
  ]) {
    const context = await browser.newContext({ viewport: { width: 390, height: 900 }, locale: 'fr-CH' });
    const page = await context.newPage(); page.setDefaultTimeout(10_000);
    let release: (() => void) | undefined, attempts = 0, exchanged = false, exchangeStatus = 0, navigations = 0;
    const token = 'A'.repeat(43);
    page.on('request', request => {
      assert(!request.url().includes(token));
      if (request.isNavigationRequest()) navigations++;
      if (exchange && new URL(request.url()).pathname === exchange && request.method() === 'POST') exchanged = request.postDataJSON()?.token === token;
    });
    page.on('response', response => { if (exchange && new URL(response.url()).pathname === exchange && response.request().method() === 'POST') exchangeStatus = response.status(); });
    await page.route('**/assets/*.js', async route => {
      if (new URL(route.request().url()).pathname.split('/').at(-1)?.startsWith(chunk!)) {
        attempts++;
        if (attempts === 1) { await new Promise<void>(done => { release = done; }); await route.abort(); return; }
      }
      await route.continue();
    });
    try {
      await page.goto(`${origin}${path}${exchange ? `#token=${token}` : ''}`, { waitUntil: 'domcontentloaded' });
      await page.getByRole('status').filter({ hasText: 'Chargement de Drivy…' }).waitFor();
      await page.waitForFunction(() => location.hash === '');
      while (!release) await page.waitForTimeout(10);
      release();
      await page.getByRole('heading', { name: 'Chargement impossible', exact: true }).waitFor();
      assert.equal(await page.evaluate(() => document.activeElement?.tagName), 'H1');
      assert.equal(navigations, 1, 'No automatic reload loop');
      await page.screenshot({ path: resolve(directory, `${name}-failure.png`), fullPage: true });
      const retry = page.getByRole('button', { name: 'Réessayer', exact: true });
      await retry.focus();
      await Promise.all([page.waitForNavigation({ waitUntil: 'domcontentloaded' }), retry.press('Enter')]);
      await page.waitForFunction(() => !!document.querySelector('h1') && document.querySelector('h1')?.textContent !== 'Chargement impossible');
      await page.waitForLoadState('networkidle');
      assert.equal(navigations, 2); assert.equal(attempts, 2);
      assert.equal(new URL(page.url()).hash, '');
      if (exchange) { assert(exchanged, 'The original bearer link must reach the BFF after explicit retry'); assert.equal(exchangeStatus, 200, 'The real BFF must accept and retain the resumed link'); }
      const stored = await page.evaluate(() => JSON.stringify([Object.entries(localStorage), Object.entries(sessionStorage)]));
      assert(!stored.includes(token));
      checks.push(`${name}: loading, error focus, no reload loop, keyboard retry, real page restored${exchange ? ', bearer link preserved only in memory/fragment and exchanged to BFF' : ''}`);
    } finally { release?.(); await context.close(); }
  }
} finally {
  await writeFile(resolve(directory, 'results.json'), JSON.stringify({ scope: 'Built client and real anonymous BFF. Module network fault injected. No real identity provider in this script.', checks }, null, 2));
  await browser.close(); await app.close();
}
console.log(`${checks.length} entry recovery scenarios passed`);
