/** Short, local-only rendering review. This is not the W31/#84 acceptance campaign. */
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const { chromium } = await import(process.env.DRIVY_PLAYWRIGHT_MODULE ?? '../../infra/dev/node_modules/playwright-core/index.mjs');
const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5187';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname), 'Only a loopback synthetic fixture may be captured');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'docs/implementation/proofs/epic-280');
const prefix = process.env.DRIVY_REVIEW_PREFIX ?? 'after';
const pages = (process.env.DRIVY_REVIEW_PAGES ?? 'overview,agenda,learner-detail,signin,formations,config').split(',');
const widths = (process.env.DRIVY_REVIEW_WIDTHS ?? '390,1440').split(',').map(Number);
const themes = (process.env.DRIVY_REVIEW_THEMES ?? 'light,dark').split(',');
const fixtures = {
  'formation-pricing': 'page=formation&view=tarifs&shell=1',
  'setup-pricing': 'page=overview&status=draft&setup=ready&step=PRICING&shell=1',
  'setup-review': 'page=overview&status=draft&setup=ready&step=REVIEW&shell=1',
  'course': 'page=course&agenda=course-review',
  'course-draft': 'page=course&agenda=course-review&draft=1',
  'agenda-mixed': 'page=agenda&agenda=mixed&shell=1',
  'invitations-team': 'page=invitations&audience=team&shell=1',
};
await mkdir(directory, { recursive: true });
const html = await (await fetch(`${origin}/app/test/visual.html`)).text();
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const results = [];
try {
  for (const theme of themes) for (const width of widths) for (const view of pages) {
    const parameters = fixtures[view] ?? `page=${view === 'learner-detail' ? 'learners' : view}&shell=1`;
    const context = await browser.newContext({ viewport: { width, height: 900 }, locale: 'fr-CH', colorScheme: theme, reducedMotion: 'reduce' });
    await context.route('**/*', route => {
      const request = route.request();
      if (new URL(request.url()).origin !== origin) return route.abort();
      if (request.isNavigationRequest()) return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', `<head><script>window.__reviewBoot=${JSON.stringify({ parameters })}</script>`) });
      return route.continue();
    });
    const page = await context.newPage();
    page.setDefaultTimeout(12000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const name = `${prefix}-${view}-${width}-${theme}`;
    try {
      await page.goto(`${origin}/app/test/visual.html?${parameters}`);
      await page.locator('main h1, main h2').first().waitFor({ state: 'visible' });
      await page.waitForFunction(() => !document.querySelector('main[aria-busy="true"]'));
      if (view === 'learner-detail') {
        await page.getByRole('link', { name: /Éloïse Müller/ }).click();
        await page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
      }
      await page.waitForFunction(() => ![...document.querySelectorAll('main .loading, main .skeleton, main .row-skeleton')].some(node => node.getClientRects().length > 0));
      await page.waitForLoadState('networkidle');
      await page.evaluate(() => document.fonts.ready);
      // Two paints settle responsive layout; no timed wait or synthetic claim of physical-device testing.
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const geometry = await page.evaluate(() => ({ viewport: innerWidth, scroll: document.documentElement.scrollWidth, theme: document.documentElement.dataset.theme, headings: [...document.querySelectorAll('main h1')].map(node => node.textContent) }));
      await page.screenshot({ path: resolve(directory, `${name}.png`), fullPage: true });
      results.push({ name, ...geometry, errors, captured: true });
    } catch (error) { results.push({ name, captured: false, error: error.message, errors }); }
    finally { await context.close(); }
  }
} finally { await browser.close(); }
const manifest = resolve(directory, `${prefix}-rendering.json`);
const previous = await readFile(manifest, 'utf8').then(value => JSON.parse(value).results ?? []).catch(() => []);
const names = new Set(results.map(result => result.name));
await writeFile(manifest, JSON.stringify({ kind: 'synthetic Chromium rendering, not real mobile or acceptance', origin, results: [...previous.filter(result => !names.has(result.name)), ...results] }, null, 2));
console.log(JSON.stringify(results));
if (results.some(result => !result.captured || result.errors.length || result.scroll > result.viewport)) process.exitCode = 1;
