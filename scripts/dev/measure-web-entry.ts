/** Measures built public web entrypoints on a real BFF. Anonymous identity/API are explicit stubs. */
import assert from 'node:assert/strict';
import { gzipSync } from 'node:zlib';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { chromium, type Browser } from '../../infra/dev/browser.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import type { IdentityProvider } from '../../apps/web/server/oidc.js';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const runs = 5;
const routes = ['/app/', '/app/invitation', '/app/ouvrir', '/app/preferences', '/app/gestion/00000000-0000-4000-8000-000000000000/apercu'];
const identity: IdentityProvider = {
  async begin() { throw new Error('ANONYMOUS_MEASUREMENT_ONLY'); },
  async complete() { throw new Error('ANONYMOUS_MEASUREMENT_ONLY'); },
  async refresh() { throw new Error('ANONYMOUS_MEASUREMENT_ONLY'); },
  async revoke() {},
};
const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)]!;
async function measure(browser: Browser, origin: string, route: string) {
  const context = await browser.newContext({ locale: 'fr-CH' });
  const page = await context.newPage();
  const samples = [];
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    for (const cache of ['cold-context', 'warm-reload']) {
      const assets: { path: string; rawBytes: number; estimatedGzipBytes: number }[] = [];
      const pending: Promise<void>[] = [];
      const listener = (response: import('../../infra/dev/node_modules/playwright-core/index.js').Response) => {
        if (response.request().resourceType() !== 'script') return;
        pending.push((async () => {
          assert.equal(response.status(), 200);
          const body = await response.body();
          assets.push({ path: new URL(response.url()).pathname, rawBytes: body.length, estimatedGzipBytes: gzipSync(body).length });
        })());
      };
      page.on('response', listener);
      const started = performance.now();
      if (cache === 'cold-context') await page.goto(`${origin}${route}`, { waitUntil: 'domcontentloaded' });
      else await page.reload({ waitUntil: 'domcontentloaded' });
      await page.locator('h1').first().waitFor();
      const headingVisibleMs = performance.now() - started;
      await page.waitForLoadState('networkidle');
      await Promise.all(pending); page.off('response', listener);
      assert(assets.length > 0); assert.deepEqual(errors, []);
      samples.push({ cache, headingVisibleMs, assets, rawBytes: assets.reduce((sum, a) => sum + a.rawBytes, 0), estimatedGzipBytes: assets.reduce((sum, a) => sum + a.estimatedGzipBytes, 0) });
    }
    return samples;
  } finally { await context.close(); }
}
async function main() {
  const app = await buildWebApp({
    config: { origin: 'http://127.0.0.1:0', apiBaseURL: 'http://127.0.0.1:9', issuer: 'http://127.0.0.1:9', clientId: 'measure', clientSecret: 'synthetic-measurement-only', development: true, host: '127.0.0.1', port: 0 },
    identity,
    gateway: async () => ({ status: 503, body: { code: 'ANONYMOUS_MEASUREMENT_ONLY' } }),
    staticRoot: resolve(root, 'apps/web/dist/client'),
  });
  let browser: Browser | undefined;
  try {
    const origin = await app.listen({ host: '127.0.0.1', port: 0 });
    browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
    const results = [];
    for (const route of routes) {
      const samples = [];
      for (let run = 0; run < runs; run++) samples.push(...await measure(browser, origin, route));
      results.push({ route, samples, medians: ['cold-context', 'warm-reload'].map(cache => {
        const values = samples.filter(s => s.cache === cache);
        return { cache, headingVisibleMs: median(values.map(s => s.headingVisibleMs)), rawBytes: median(values.map(s => s.rawBytes)), estimatedGzipBytes: median(values.map(s => s.estimatedGzipBytes)), chunks: median(values.map(s => s.assets.length)) };
      }) });
      console.log(`MEASURED ${route}`);
    }
    const output = resolve(process.env.OUTPUT ?? 'artifacts/v3-20261018/web-entry.json');
    await mkdir(dirname(output), { recursive: true });
    await writeFile(output, JSON.stringify({ node: process.version, browser: browser.version(), scope: 'Built client + real BFF, anonymous identity stub. Gzip sizes estimated from resource bodies, not transferred bytes. Local timings only.', runs, results }, null, 2));
    if (process.argv.includes('--require-split')) {
      assert(results[0]!.medians[0]!.rawBytes < results[4]!.medians[0]!.rawBytes, 'Account entry must not load the entire management console');
      assert(results[3]!.medians[0]!.rawBytes < results[0]!.medians[0]!.rawBytes, 'Preferences must not load all account flows');
    }
    console.log(`SAVED ${output}`);
  } finally { await browser?.close(); await app.close(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
