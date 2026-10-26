/** Real React agenda in Edge; every school/name/event is a loopback synthetic fixture. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5191';
const baseline = process.env.DRIVY_BASELINE_ORIGIN ?? 'http://127.0.0.1:5190';
const capturesOnly = process.argv.includes('--captures-only');
for (const url of [origin, baseline]) assert(['127.0.0.1', 'localhost'].includes(new URL(url).hostname), 'LOOPBACK_ONLY');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'artifacts/agenda-20261026/web');
await mkdir(directory, { recursive: true });
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], regressions = [], failures = [], captures = [];
const html = new Map(await Promise.all([origin, baseline].map(async url => [url, await (await fetch(`${url}/app/test/visual.html`)).text()])));
const settle = page => page.waitForTimeout(450);
async function harness(source = origin, fixture = 'mixed', width = 1440, colorScheme = 'light', extra = '') {
  const parameters = `page=agenda&shell=1&agenda=${fixture}${extra}`;
  const context = await browser.newContext({ viewport: { width, height: 1000 }, colorScheme, locale: 'fr-CH' });
  await context.route('**/*', route => {
    if (new URL(route.request().url()).origin !== source) return route.abort();
    if (route.request().isNavigationRequest()) return route.fulfill({ contentType: 'text/html',
      body: html.get(source).replace('<head>', `<head><script>window.__reviewBoot=${JSON.stringify({ parameters })}</script>`) });
    return route.continue();
  });
  const page = await context.newPage(); page.setDefaultTimeout(8000);
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto(`${source}/app/test/visual.html`);
  await page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
  await page.waitForFunction(() => window.__agendaReview && window.__reads.includes('course-series'));
  await settle(page); await page.evaluate(() => document.fonts.ready);
  return { page, context, errors };
}
const dayRows = page => page.locator('.agenda-day').first().locator('.agenda-lesson .row-title').allTextContents();
const chooseInstructor = async (page, name) => {
  await page.getByLabel('Moniteur', { exact: true }).click();
  await page.getByRole('option', { name, exact: true }).click(); await settle(page);
};
async function scenario(name, run, fixture = 'mixed', extra = '') {
  let h;
  try { h = await harness(origin, fixture, 1440, 'light', extra); await run(h.page); assert.deepEqual(h.errors, []); checks.push(name); }
  catch (error) {
    failures.push({ name, message: error.message });
    if (h) await h.page.screenshot({ path: resolve(directory, `failure-${failures.length}.png`), fullPage: true });
  } finally { await h?.context.close(); }
}
try {
  if (!capturesOnly) {
  // Same fixture demonstrates the original defects, without treating baseline failure as candidate success.
  const before = await harness(baseline);
  try {
    assert.deepEqual(await dayRows(before.page), ['Sensibilisation du matin', 'Premiers secours', 'Éloïse Müller']);
    regressions.push('Avant : 09 h, 14 h, 11 h dans deux listes distinctes.');
    await chooseInstructor(before.page, 'Marie Dupont');
    assert.equal(await before.page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 0);
    regressions.push('Avant : le filtre Marie retire tous ses cours.');
    await chooseInstructor(before.page, 'Tous les moniteurs');
    const readsBefore = await before.page.evaluate(() => window.__reads.filter(path => path === 'course-series').length);
    await before.page.evaluate(() => window.__agendaReview.setCourseTitle('Titre externe synthétique'));
    await before.page.getByRole('button', { name: 'Actualiser', exact: true }).click(); await settle(before.page);
    assert.equal(await before.page.evaluate(() => window.__reads.filter(path => path === 'course-series').length), readsBefore);
    assert.equal(await before.page.getByText('Titre externe synthétique', { exact: true }).count(), 0);
    regressions.push('Avant : Actualiser ne recharge pas les cours ni leur titre modifié.');
  } finally { await before.context.close(); }

  await scenario('Chronologie mixte, compteurs de jour/semaine et ouverture de la bonne série', async page => {
    assert.deepEqual(await dayRows(page), ['Sensibilisation du matin', 'Éloïse Müller', 'Premiers secours']);
    assert.equal(await page.locator('.list-summary').textContent(), '1 leçon · 5 séances collectives cette semaine');
    assert.equal(await page.locator('.agenda-day-count').first().textContent(), '1 leçon · 2 séances collectives');
    const firstCourse = await page.evaluate(() => window.__agendaReview.courseIds[0]);
    await page.getByRole('button', { name: /Sensibilisation du matin.*Ouvrir le cours/ }).first().click();
    await page.getByRole('button', { name: 'Fermer', exact: true }).waitFor();
    assert(await page.evaluate(id => window.__reads.includes(`course-series/${id}`), firstCourse));
    await page.getByRole('button', { name: 'Fermer', exact: true }).click();
    assert.deepEqual(await dayRows(page), ['Sensibilisation du matin', 'Éloïse Müller', 'Premiers secours']);
  });
  await scenario('Moniteur de séance, série à plusieurs moniteurs et compteur filtré', async page => {
    await chooseInstructor(page, 'Marie Dupont');
    assert.deepEqual(await dayRows(page), ['Sensibilisation du matin', 'Éloïse Müller', 'Premiers secours']);
    assert.equal(await page.locator('.list-summary').textContent(), '1 leçon · 3 séances collectives cette semaine');
    await chooseInstructor(page, 'Luc Martin');
    assert.equal(await page.getByRole('button', { name: /Ouvrir le dossier/ }).count(), 0);
    assert.equal(await page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 2);
    assert.equal(await page.locator('.list-summary').textContent(), '2 séances collectives cette semaine');
  });
  await scenario('Actualiser relit chaque source une seule fois, conserve semaine et focus', async page => {
    await page.evaluate(() => { window.__reads.length = 0; window.__agendaReview.setCourseTitle('Titre externe synthétique'); window.__agendaReview.setCourseDelay(600); });
    const button = page.getByRole('button', { name: 'Actualiser', exact: true });
    await button.dblclick();
    await page.getByText('Titre externe synthétique', { exact: true }).first().waitFor();
    const reads = await page.evaluate(() => window.__reads);
    for (const path of ['lessons', 'members', 'learners', 'course-series']) assert.equal(reads.filter(item => item === path).length, 1, path);
    assert.equal(new URL(page.url()).searchParams.get('week'), '2026-09-28');
    assert(await button.evaluate(element => element === document.activeElement));
  });
  await scenario('Panne des cours : lectures conservées, fraîcheur honnête et reprise ciblée', async page => {
    await page.evaluate(() => window.__agendaReview.setCourseFailure(503));
    await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
    await page.getByText('Cours non actualisés', { exact: true }).waitFor();
    assert.equal(await page.getByText(/^À jour à/).count(), 0);
    assert.deepEqual(await dayRows(page), ['Sensibilisation du matin', 'Éloïse Müller', 'Premiers secours']);
    assert.match(await page.locator('.list-summary').textContent(), /lecture partielle/);
    await page.evaluate(() => { window.__agendaReview.setCourseFailure(null); window.__agendaReview.setCourseTitle('Cours rétabli'); });
    await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
    await page.getByText('Cours rétabli', { exact: true }).first().waitFor();
    assert.equal(await page.getByText('Cours non actualisés', { exact: true }).count(), 0);
  });
  await scenario('Refus des cours : purge du cache refusé et leçons préservées', async page => {
    await page.evaluate(() => window.__agendaReview.setCourseFailure(403));
    await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
    await page.getByText('Cours non actualisés', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 0);
    assert.equal(await page.getByRole('button', { name: /Ouvrir le dossier/ }).count(), 1);
    assert.equal(await page.getByText(/^À jour à/).count(), 0);
  });
  await scenario('Erreur initiale des cours ne devient pas un agenda vide', async page => {
    await page.getByText('Cours non actualisés', { exact: true }).waitFor();
    assert.equal(await page.getByRole('heading', { name: 'Aucun rendez-vous cette semaine' }).count(), 0);
    assert.match(await page.locator('.list-summary').textContent(), /lecture partielle/);
  }, 'course-only', '&fail=course-series');
  await scenario('Jour uniquement collectif : aucun faux zéro leçon', async page => {
    assert.equal(await page.locator('.list-summary').textContent(), '5 séances collectives cette semaine');
    assert.equal(await page.getByRole('heading', { name: /Aucun/ }).count(), 0);
  }, 'course-only');
  await scenario('Vide confirmé de toutes les sources', async page => {
    await page.getByRole('heading', { name: 'Aucun rendez-vous cette semaine', exact: true }).waitFor();
    assert.equal(await page.locator('.list-summary').textContent(), '0 rendez-vous cette semaine');
    assert.equal(await page.getByText(/^À jour à/).count(), 1);
  }, 'empty');
  await scenario('Limite de 200 séries : couverture non exhaustive annoncée', async page => {
    await page.getByText('Cours potentiellement incomplets', { exact: true }).waitFor();
    assert.equal(await page.getByText(/^À jour à/).count(), 0);
    assert.match(await page.locator('.list-summary').textContent(), /lecture partielle/);
  }, 'cap');
  await scenario('Réponse retardée après changement de semaine ignorée', async page => {
    await page.evaluate(() => window.__agendaReview.setCourseDelay(900));
    await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
    await page.waitForTimeout(180);
    await page.getByRole('button', { name: 'Semaine suivante', exact: true }).click();
    assert.equal(await page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 0);
    await page.getByRole('heading', { name: 'Aucun rendez-vous cette semaine', exact: true }).waitFor();
    assert.equal(new URL(page.url()).searchParams.get('week'), '2026-10-05');
    assert.equal(await page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 0);
  });
  await scenario('Recherche : périmètre explicite, focus préservé, retour du dossier et choix de date', async page => {
    const search = page.getByLabel('Rechercher un élève parmi les leçons', { exact: true });
    await search.fill('eloise');
    assert.equal(await page.getByRole('button', { name: /Ouvrir le cours/ }).count(), 0);
    assert.match(await page.locator('.list-summary').textContent(), /recherche parmi les leçons/);
    await page.getByRole('button', { name: 'Actualiser', exact: true }).click(); await search.focus(); await settle(page);
    assert(await search.evaluate(element => element === document.activeElement)); assert.equal(await search.inputValue(), 'eloise');
    await page.getByRole('button', { name: /Ouvrir le dossier/ }).click();
    await page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Retour à l’agenda', exact: true }).click();
    await search.waitFor(); assert.equal(await search.inputValue(), 'eloise');
    await page.getByLabel('Aller à une date', { exact: true }).fill('2026-11-25');
    await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
    await page.waitForFunction(() => document.activeElement?.classList.contains('agenda-period-label'));
    assert.equal(new URL(page.url()).searchParams.get('week'), '2026-11-23');
  });
  }
  for (const [source, phase] of [[baseline, 'before'], [origin, 'after']]) {
    for (const [width, color] of [[1440, 'light'], [1440, 'dark'], [390, 'light'], [390, 'dark']]) {
      const h = await harness(source, 'mixed', width, color);
      try {
        const path = resolve(directory, `${phase}-${width}-${color}.png`);
        await h.page.screenshot({ path, fullPage: true }); captures.push(path);
        assert(await h.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Overflow ${phase} ${width}`);
        assert.deepEqual(h.errors, []);
        checks.push(`Rendu ${phase} ${width}px ${color} : aucune erreur JS ni débordement horizontal`);
      } finally { await h.context.close(); }
    }
  }
} catch (error) { failures.push({ name: 'Harness ou comparaison avant/après', message: error.message }); }
finally {
  await writeFile(resolve(directory, capturesOnly ? 'captures-results.json' : 'results.json'), JSON.stringify({ checkedAt: new Date().toISOString(), browser: browser.version(),
    scope: 'Edge, vrais composants React, données et transport synthétiques en mémoire. Aucune API/PostgreSQL, VoiceOver ou mesure de performance réelle qualifiée.',
    checks, regressions, failures, captures }, null, 2));
  await browser.close(); console.log(JSON.stringify({ passed: checks.length, regressions, failures, captures: captures.length }, null, 2));
  if (failures.length) process.exitCode = 1;
}
