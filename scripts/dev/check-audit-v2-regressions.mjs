/** V2 regression checks: real React components, synthetic transport, loopback only. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5188';
assert(['127.0.0.1', 'localhost'].includes(new URL(origin).hostname));
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'artifacts/audit-v2-20261018/regressions');
await mkdir(directory, { recursive: true });
const response = await fetch(`${origin}/app/test/visual.html`);
assert(response.ok);
const html = await response.text();
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], failures = [];
async function scenario(name, width, run) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, locale: 'fr-CH' });
  await context.route('**/*', route => {
    if (new URL(route.request().url()).origin !== origin) return route.abort();
    if (route.request().isNavigationRequest()) return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', '<head><script>window.__reviewBoot={parameters:"page=learners&shell=1"}</script>') });
    return route.continue();
  });
  const page = await context.newPage(); page.setDefaultTimeout(6000);
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(`${origin}/app/test/visual.html?page=learners&shell=1`);
    await page.getByRole('link', { name: 'Éloïse Müller', exact: true }).waitFor();
    await run(page);
    assert.deepEqual(errors, []);
    checks.push(name);
  } catch (error) {
    failures.push({ name, error: error.message, stack: error.stack });
    await page.screenshot({ path: resolve(directory, `${name}-failed.png`), fullPage: true });
  } finally { await context.close(); }
}
async function interceptConsent(page, status, delayed = false) {
  await page.evaluate(({ status, delayed }) => {
    const original = window.fetch;
    window.__auditGps = { status, requests: 0, release: null };
    window.fetch = async (input, init) => {
      const url = new URL(String(input));
      if (!url.pathname.endsWith('/recording-choices')) return original(input, init);
      const state = window.__auditGps; state.requests++;
      if (delayed && state.requests === 1) await new Promise(resolve => { state.release = resolve; });
      const body = state.status === 200 ? { data: { items: [] }, requestId: 'audit-v2', serverTime: new Date().toISOString() }
        : { code: state.status === 401 ? 'SESSION_EXPIRED' : state.status === 403 ? 'ACCESS_DENIED' : 'SERVICE_UNAVAILABLE' };
      return { status: state.status, ok: state.status === 200, url: url.href, headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
    };
  }, { status, delayed });
  await page.getByRole('link', { name: 'Éloïse Müller', exact: true }).click();
  await page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
  await page.waitForFunction(() => window.__auditGps.requests > 0);
}
try {
  for (const width of [1440, 390]) await scenario(`gps-read-error-retry-${width}`, width, async page => {
    await interceptConsent(page, 503);
    await page.getByText('Accord GPS indisponible', { exact: true }).waitFor();
    assert.equal(await page.getByText('Accord GPS : Pas encore donné', { exact: true }).count(), 0, 'A failed read must not invent a consent status');
    await page.screenshot({ path: resolve(directory, `gps-error-${width}.png`), fullPage: true });
    await page.evaluate(() => { window.__auditGps.status = 200; });
    const retry = page.getByRole('button', { name: 'Réessayer', exact: true });
    await retry.focus(); await retry.press('Enter');
    await page.getByText('Accord GPS : Pas encore donné', { exact: true }).waitFor();
    assert.equal(await page.getByText('Accord GPS indisponible', { exact: true }).count(), 0);
    assert.equal(await page.evaluate(() => window.__auditGps.requests), 2);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  });
  await scenario('gps-session-expired', 1440, async page => {
    await interceptConsent(page, 401);
    await page.getByText('Accord GPS indisponible', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Se reconnecter', exact: true }).waitFor();
    assert.equal(await page.getByText('Accord GPS : Pas encore donné', { exact: true }).count(), 0);
  });
  await scenario('gps-permission-refusal-stays-hidden', 1440, async page => {
    await interceptConsent(page, 403);
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    assert.equal(await page.getByText(/Accord GPS/).count(), 0, 'A permission refusal must not reveal the GPS status');
  });
  await scenario('gps-loading-is-not-a-consent', 390, async page => {
    await interceptConsent(page, 200, true);
    await page.getByText('Lecture de l’accord GPS…', { exact: true }).waitFor();
    assert.equal(await page.getByText('Accord GPS : Pas encore donné', { exact: true }).count(), 0);
    await page.evaluate(() => window.__auditGps.release());
    await page.getByText('Accord GPS : Pas encore donné', { exact: true }).waitFor();
  });
} finally {
  await writeFile(resolve(directory, 'results.json'), JSON.stringify({ scope: 'Edge real components, synthetic BFF only', browser: browser.version(), checks, failures }, null, 2));
  await browser.close();
  console.log(JSON.stringify({ checks, failures, directory }, null, 2));
  if (failures.length) process.exitCode = 1;
}
