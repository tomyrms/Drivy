/** Real agenda React UI in Edge. Transport is the existing synthetic fixture, not API acceptance. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';
const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5189';
assert(['127.0.0.1', 'localhost'].includes(new URL(origin).hostname));
const before = process.argv.includes('--before');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? `artifacts/v3-20261018/agenda-${before ? 'before' : 'after'}`);
await mkdir(directory, { recursive: true });
const html = await (await fetch(`${origin}/app/test/visual.html`)).text();
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], failures = [], measurements = [];
try {
  for (const [width, colorScheme] of [[1440, 'light'], [390, 'light'], [390, 'dark']]) {
    const context = await browser.newContext({ viewport: { width, height: 1000 }, locale: 'fr-CH', colorScheme });
    await context.route('**/*', route => {
      if (new URL(route.request().url()).origin !== origin) return route.abort();
      if (route.request().isNavigationRequest()) return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', '<head><script>window.__reviewBoot={parameters:"page=agenda&shell=1"}</script>') });
      return route.continue();
    });
    const page = await context.newPage(); page.setDefaultTimeout(6000);
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    const key = `${width}-${colorScheme}`;
    const week = () => new URL(page.url()).searchParams.get('week');
    const expectWeek = async value => { await page.waitForFunction(value => new URL(location.href).searchParams.get('week') === value, value); assert.equal(week(), value); };
    try {
      await page.goto(`${origin}/app/test/visual.html`);
      await page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
      await page.getByRole('button', { name: /Ouvrir le dossier/ }).first().waitFor();
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path: resolve(directory, `agenda-${key}.png`), fullPage: true });
      if (before) {
        for (let i = 0; i < 8; i++) await page.getByRole('button', { name: 'Semaine suivante', exact: true }).click();
        await expectWeek('2026-11-23');
        measurements.push({ key, task: '28 septembre vers semaine du 23 novembre 2026', buttonActivations: 8 });
        checks.push(`${key}: huit semaines nécessitent huit activations`);
      } else {
        const date = page.getByLabel('Aller à une date', { exact: true });
        assert.equal(await date.count(), 1, 'A distant week must be reachable directly through a labelled date field');
        await date.fill('2026-11-25');
        assert.equal(week(), '2026-09-28', 'Editing a date must not prematurely navigate');
        await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
        await expectWeek('2026-11-23');
        await page.waitForFunction(() => document.activeElement?.classList.contains('agenda-period-label'));
        measurements.push({ key, task: '28 septembre vers semaine du 23 novembre 2026', dateSelections: 1, buttonActivations: 1 });
        checks.push(`${key}: date directe, lundi normalisé, focus sur semaine`);
        await page.goBack(); await expectWeek('2026-09-28');
        await page.waitForFunction(() => document.querySelector('input[type=date]')?.value === '2026-09-28');
        await date.fill('');
        await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
        assert.equal(week(), '2026-09-28', 'Empty date must not navigate');
        checks.push(`${key}: retour navigateur et date vide préservent la semaine`);
        await date.fill('2026-10-25'); await date.press('Enter'); await expectWeek('2026-10-19');
        checks.push(`${key}: saisie clavier pendant changement heure Europe/Zurich`);
        await page.getByRole('button', { name: 'Semaine suivante', exact: true }).click(); await expectWeek('2026-10-26');
        await page.getByRole('button', { name: 'Semaine précédente', exact: true }).click(); await expectWeek('2026-10-19');
        await page.reload(); await expectWeek('2026-10-19');
        await page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
        checks.push(`${key}: flèches et rechargement restent cohérents`);
        await page.getByLabel('Aller à une date', { exact: true }).fill('2026-09-30');
        await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click(); await expectWeek('2026-09-28');
        await page.getByRole('button', { name: /Ouvrir le dossier/ }).first().click();
        await page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
        await page.goBack(); await expectWeek('2026-09-28');
        await page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
        checks.push(`${key}: dossier élève et retour conservent la semaine`);
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        assert.deepEqual(errors, []);
      }
    } catch (error) {
      failures.push({ key, message: error.message });
      await page.screenshot({ path: resolve(directory, `failed-${key}.png`), fullPage: true });
    } finally { await context.close(); }
  }
} finally {
  await writeFile(resolve(directory, 'results.json'), JSON.stringify({ scope: 'Edge real React, synthetic transport. Date-selection actions are not measured time savings.', checks, failures, measurements }, null, 2));
  await browser.close();
  console.log(JSON.stringify({ checks, failures, measurements }, null, 2));
  if (failures.length) process.exitCode = 1;
}
