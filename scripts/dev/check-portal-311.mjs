/** Small synthetic pre-delivery smoke; the full R24 matrix runs after the user's review.
 * Usage: DRIVY_PLAYWRIGHT_MODULE=<optional module path> node check-portal-311.mjs <preview URL> <output directory>
 * Atrium's CDP captures are tiled in narrow panes on this host; this captures the real browser viewport.
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { chromium } = await import(process.env.DRIVY_PLAYWRIGHT_MODULE ? pathToFileURL(process.env.DRIVY_PLAYWRIGHT_MODULE).href : 'playwright');
const [base = 'http://127.0.0.1:5188/preview-311.html', output = '.local/portal-311-smoke'] = process.argv.slice(2);
await mkdir(output, { recursive: true });
const browser = await chromium.launch();
const results = [];
try {
  for (const [width, theme] of [[390, 'dark'], [1440, 'light']]) {
    const session = await browser.newContext({ viewport: { width, height: 960 }, locale: 'fr-CH', timezoneId: 'Europe/Zurich' });
    await session.addInitScript(value => localStorage.setItem('drivy.web.theme', value), theme);
    const page = await session.newPage();
    const failures = [];
    page.on('pageerror', error => failures.push(error.message));
    page.on('console', message => { if (message.type() === 'error') failures.push(message.text()); });
    for (const destination of ['agenda', 'eleves', 'equipe', 'formations', 'prestations', 'confidentialite', 'champs-profil', 'configuration', 'preferences']) {
      await page.goto(`${base}?page=${destination}`, { waitUntil: 'networkidle' });
      await page.getByRole('heading').first().waitFor();
      await page.evaluate(() => document.fonts.ready);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
      assert(overflow <= 1, `${destination} overflows at ${width}: ${overflow}`);
      await page.screenshot({ path: resolve(output, `${destination}-${width}-${theme}.png`) });
      results.push({ destination, width, theme, overflow, errors: [...failures] });
      assert.deepEqual(failures, [], `${destination}: browser errors`);
    }
    await page.goto(`${base}?page=configuration`, { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: 'Rechercher un réglage' }).click();
    await page.getByRole('textbox', { name: 'Rechercher dans les paramètres' }).fill('Téléphone');
    await page.getByRole('link', { name: /Téléphone de l’école/ }).click();
    await page.waitForFunction(() => document.activeElement?.id === 'school-phone');
    await page.screenshot({ path: resolve(output, `search-focus-${width}-${theme}.png`) });
    results.push({ destination: 'search-school-phone', width, theme, focus: 'school-phone' });
    await session.close();
  }
  await writeFile(resolve(output, 'smoke.json'), JSON.stringify({ synthetic: true, results }, null, 2));
  console.log(JSON.stringify({ checks: results.length, result: 'PASS', output: resolve(output) }));
} finally { await browser.close(); }
