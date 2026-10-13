/** Edge checks of real React components. BFF and reload state are synthetic fixtures. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5173';
if (!['127.0.0.1', 'localhost'].includes(new URL(origin).hostname)) throw new Error('LOOPBACK_REVIEW_REQUIRED');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'artifacts/web-redesign-20261013/after');
await mkdir(directory, { recursive: true });
const response = await fetch(`${origin}/app/test/visual.html`);
assert(response.ok, 'Vite must be running locally.');
const html = await response.text();
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], captures = [], failures = [], accessibility = [], supplemental = [];
const scope = 'Edge et vrais composants React ; BFF et rechargement synthétiques en mémoire du test. Aucun OIDC/PostgreSQL/lecteur d’écran physique qualifié.';
const checkFilter = process.env.DRIVY_REVIEW_CHECK_FILTER ? new RegExp(process.env.DRIVY_REVIEW_CHECK_FILTER, 'iu') : null;
let stage = 'initialisation';
async function harness(parameters, options = {}) {
  const boot = { parameters };
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, colorScheme: 'light', locale: 'fr-CH', ...options });
  await context.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin !== origin) return route.abort();
    if (request.isNavigationRequest() && url.pathname.startsWith('/app/')) {
      const script = `<script>window.__reviewBoot=${JSON.stringify(boot).replaceAll('<', '\\u003c')}</script>`;
      return route.fulfill({ contentType: 'text/html', body: html.replace('<head>', `<head>${script}`) });
    }
    return route.continue();
  });
  const page = await context.newPage(); page.setDefaultTimeout(8000);
  const errors = []; page.on('pageerror', error => errors.push(error.name));
  const ready = async () => { await page.locator('h1').first().waitFor(); await page.waitForTimeout(850); await page.evaluate(() => document.fonts.ready); };
  const open = async (url = `${origin}/app/test/visual.html?${parameters}`) => { await page.goto(url); await ready(); };
  const reload = async () => { boot.snapshot = await page.evaluate(() => window.__reviewSnapshot()); await page.reload(); await ready(); };
  return { context, page, boot, errors, open, reload };
}
const settle = page => page.waitForTimeout(550);
const noOverflow = page => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
const auditAccessibility = page => page.evaluate(async () => {
  const result = await window.axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] }, resultTypes: ['violations', 'incomplete'] });
  const summarize = rows => rows.map(row => ({ id: row.id, impact: row.impact, help: row.help, helpUrl: row.helpUrl, nodes: row.nodes.map(node => {
    const element = typeof node.target[0] === 'string' ? document.querySelector(node.target[0]) : null;
    const rect = element?.getBoundingClientRect(), styles = [];
    for (let current = element; current; current = current.parentElement) styles.push({ tag: current.tagName, className: current.className, background: getComputedStyle(current).backgroundColor, color: getComputedStyle(current).color });
    const unobscured = rect && [.1, .5, .9].every(x => [.1, .5, .9].every(y => { const hit = document.elementFromPoint(rect.left + rect.width * x, rect.top + rect.height * y); return hit === element || element.contains(hit); }));
    return { target: node.target, html: node.html, summary: node.failureSummary, rect: rect?.toJSON(), unobscuredAtNinePoints: unobscured, styles };
  }) }));
  return { violations: summarize(result.violations), incomplete: summarize(result.incomplete) };
});
async function scenario(label, parameters, run) {
  if (checkFilter && !checkFilter.test(label)) return;
  stage = label; const h = await harness(parameters);
  try { await h.open(); await run(h); assert.equal(h.errors.length, 0); checks.push(label); }
  catch (error) { failures.push({ scenario: label, error: String(error.message).slice(0, 2400) }); }
  finally { await h.context.close(); }
}
try {
  if (!process.argv.includes('--captures-only')) {
    await scenario('Thèmes : changement immédiat, rechargement, choix manuel et suivi système', 'page=preferences&shell=1', async h => {
      await h.page.getByRole('radio', { name: 'Sombre', exact: true }).check();
      assert.equal(await h.page.locator('html').getAttribute('data-theme'), 'dark');
      assert.equal(await h.page.evaluate(() => localStorage.getItem('drivy.web.theme')), 'dark');
      await h.reload(); assert.equal(await h.page.locator('html').getAttribute('data-theme'), 'dark');
      await h.page.emulateMedia({ colorScheme: 'light' }); assert.equal(await h.page.locator('html').getAttribute('data-theme'), 'dark');
      await h.page.getByRole('radio', { name: 'Système', exact: true }).check();
      await h.page.emulateMedia({ colorScheme: 'dark' }); await h.page.waitForFunction(() => document.documentElement.dataset.theme === 'dark');
      await h.page.emulateMedia({ colorScheme: 'light' }); await h.page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
      await h.page.getByRole('radio', { name: 'Sombre', exact: true }).check();
      await h.page.route('**/test/visual.tsx*', route => route.abort());
      await h.page.goto(`${origin}/app/preferences`);
      assert.equal(await h.page.locator('h1').count(), 0, 'Le module React est bloqué pour isoler le thème initial');
      assert.equal(await h.page.locator('html').getAttribute('data-theme'), 'dark');
    });
    await scenario('Recherche réglages : résultat profond, clavier, Échap et retour du focus', 'page=learners&shell=1', async h => {
      const trigger = h.page.getByRole('button', { name: 'Rechercher un réglage', exact: true }); await trigger.click();
      const input = h.page.getByLabel('Rechercher dans les paramètres', { exact: true }); await input.fill('téléphone');
      await h.page.getByRole('dialog').getByRole('link').first().waitFor(); await input.press('Tab');
      assert(await h.page.getByRole('dialog').evaluate(dialog => dialog.contains(document.activeElement)));
      await h.page.keyboard.press('Escape'); await h.page.getByRole('dialog').waitFor({ state: 'hidden' });
      assert(await trigger.evaluate(button => button === document.activeElement));
      await trigger.click(); await input.fill('téléphone'); await h.page.getByRole('dialog').getByRole('link').first().click(); await settle(h.page);
      assert(new URL(h.page.url()).pathname.endsWith('/configuration'));
      await trigger.click(); await input.fill('conservation'); await h.page.getByRole('dialog').getByRole('link').first().click();
      await h.page.waitForFunction(() => document.activeElement?.id === 'privacy-retention');
      await trigger.click(); await input.fill('conservation'); await h.page.getByRole('dialog').getByRole('link').first().click();
      await h.page.waitForFunction(() => document.activeElement?.id === 'privacy-retention');
    });
    await scenario('Élève : recherche, fiche, trajet et retour à la liste filtrée', 'page=learners&shell=1&stress=1', async h => {
      await h.page.getByLabel('Rechercher un élève', { exact: true }).fill('Éloïse'); assert.equal(await h.page.locator('.record-table tbody tr').count(), 1);
      await h.page.getByRole('link', { name: /Éloïse/ }).first().click(); await h.page.getByRole('button', { name: 'Voir les trajets', exact: true }).click(); await settle(h.page);
      assert(new URL(h.page.url()).pathname.endsWith('/trajets')); await h.page.goBack(); await settle(h.page);
      await h.page.getByRole('button', { name: 'Tous les élèves', exact: true }).click();
      assert.equal(await h.page.getByLabel('Rechercher un élève', { exact: true }).inputValue(), 'Éloïse'); assert.equal(await h.page.locator('.record-table tbody tr').count(), 1);
    });
    await scenario('Recherche sans résultat : état explicite et réinitialisation utile', 'page=learners&shell=1&stress=1', async h => {
      await h.page.getByLabel('Rechercher un élève', { exact: true }).fill('aucune-correspondance');
      await h.page.getByRole('heading', { name: 'Aucun élève trouvé', exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Réinitialiser les filtres', exact: true }).click();
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 20);
    });
    await scenario('Menu compte au clavier : ouverture, choix du thème et Échap rend le focus', 'page=learners&shell=1', async h => {
      const trigger = h.page.getByRole('button', { name: 'Luc Martin', exact: true });
      await trigger.focus(); await h.page.keyboard.press('Enter');
      await h.page.getByRole('link', { name: 'Préférences personnelles', exact: true }).waitFor();
      const dark = h.page.getByRole('radio', { name: 'Sombre', exact: true }); await dark.focus(); await h.page.keyboard.press('Space');
      assert.equal(await h.page.locator('html').getAttribute('data-theme'), 'dark');
      await h.page.keyboard.press('Escape'); await h.page.getByRole('link', { name: 'Préférences personnelles', exact: true }).waitFor({ state: 'hidden' });
      assert(await trigger.evaluate(element => element === document.activeElement));
    });
    await scenario('Profil incomplet : correction, écriture confirmée et disparition du signal', 'page=learners&shell=1', async h => {
      await h.page.getByRole('link', { name: /Éloïse/ }).first().click(); await h.page.getByLabel('Date de naissance', { exact: true }).fill('2000-02-12');
      await h.page.locator('.profile-completion').getByRole('button', { name: 'Enregistrer le profil', exact: true }).click(); await h.page.locator('.profile-completion').waitFor({ state: 'detached' });
      assert.equal(await h.page.getByText('Profil à compléter', { exact: true }).count(), 0); await h.reload(); assert.equal(await h.page.getByText('Profil à compléter', { exact: true }).count(), 0);
    });
    await scenario('Coordonnées : modification puis rechargement de l’URL et du résultat confirmé', 'page=config&shell=1', async h => {
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 01 02');
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click(); await settle(h.page);
      await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).waitFor();
      await h.reload(); assert.equal(await h.page.getByLabel(/Téléphone/).inputValue(), '+41 21 555 01 02');
    });
    await scenario('Refus enregistrement : erreur, saisie conservée, aucun faux succès', 'page=config&shell=1&state=mutation-error', async h => {
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 01 03');
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click(); await settle(h.page);
      assert.equal(await h.page.getByLabel(/Téléphone/).inputValue(), '+41 21 555 01 03'); assert(await h.page.getByRole('alert').count() > 0);
      assert.equal(await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).count(), 0);
    });
    await scenario('Validation formulaire : erreur près du champ, focus et absence d’envoi invalide', 'page=config&shell=1', async h => {
      const email = h.page.getByLabel('E-mail de l’école', { exact: true });
      await email.fill('adresse-invalide'); await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.id === 'school-email');
      assert.equal(await email.getAttribute('aria-invalid'), 'true');
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
    await scenario('Conflit coordonnées : relecture version serveur, saisie conservée et nouvel envoi confirmé', 'page=config&shell=1&state=conflict-once', async h => {
      const phone = h.page.getByLabel(/Téléphone/);
      await phone.fill('+41 21 555 01 04'); await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.getByRole('button', { name: 'Recharger les informations', exact: true }).click(); await settle(h.page);
      assert.equal(await phone.inputValue(), '+41 21 555 01 04');
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).waitFor();
      assert.equal(await h.page.evaluate(() => window.__reviewSnapshot().school.version), 3);
      assert.equal(await h.page.getByText('Modifications non enregistrées', { exact: true }).count(), 0);
    });
    await scenario('Valeur confirmée avant relecture : ancienne valeur modifiée et Annuler rétablit la valeur durable', 'page=config&shell=1&state=slow-school-after-save', async h => {
      const phone = h.page.getByLabel(/Téléphone/), save = h.page.getByRole('button', { name: 'Enregistrer', exact: true });
      const oldValue = await phone.inputValue(), savedValue = '+41 21 555 01 05';
      await phone.fill(savedValue); await save.click();
      await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).waitFor();
      await h.page.waitForFunction(() => window.__schoolReadWaiting === true);
      assert.equal(await save.isEnabled(), false);
      await phone.fill(oldValue); assert.equal(await save.isEnabled(), true);
      await h.page.getByText('Modifications non enregistrées', { exact: true }).waitFor();
      await phone.fill('+41 21 555 01 06'); await h.page.getByRole('button', { name: 'Annuler', exact: true }).click();
      assert.equal(await phone.inputValue(), savedValue); assert.equal(await save.isEnabled(), false);
      await h.page.evaluate(() => window.__releaseSchoolRead());
      await h.page.waitForFunction(() => window.__schoolReadWaiting === false); await settle(h.page);
      assert.equal(await phone.inputValue(), savedValue); assert.equal(await save.isEnabled(), false);
    });
    await scenario('Saisie non enregistrée : navigation annulée puis acceptée, historique arrière et avant intact', 'page=learners&shell=1', async h => {
      await h.page.getByRole('link', { name: 'Paramètres de l’école', exact: true }).click(); await settle(h.page);
      const configUrl = h.page.url();
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 09 09');
      await h.page.getByRole('link', { name: 'Planning', exact: true }).click();
      const dialog = h.page.getByRole('dialog', { name: 'Quitter sans enregistrer ?' });
      await dialog.waitFor(); await dialog.getByRole('button', { name: 'Retour', exact: true }).click();
      assert.equal(h.page.url(), configUrl);
      assert.equal(await h.page.getByLabel(/Téléphone/).inputValue(), '+41 21 555 09 09');
      await h.page.goBack(); await dialog.waitFor();
      await dialog.getByRole('button', { name: 'Retour', exact: true }).click(); await settle(h.page);
      assert.equal(h.page.url(), configUrl);
      await h.page.goBack(); await dialog.waitFor();
      await dialog.getByRole('button', { name: 'Quitter la page', exact: true }).click(); await settle(h.page);
      assert(new URL(h.page.url()).pathname.endsWith('/eleves'));
      await h.page.goForward(); await settle(h.page); assert.equal(h.page.url(), configUrl);
    });
    await scenario('Signalements : retour à la valeur initiale et sauvegarde libèrent la sortie ; vraie saisie reste protégée', 'page=themes&shell=1', async h => {
      const toggle = h.page.getByRole('switch', { name: 'Maîtrise du véhicule', exact: true });
      await toggle.uncheck(); await toggle.check();
      await h.page.getByRole('link', { name: 'Planning', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
      assert.equal(await h.page.getByRole('dialog').count(), 0);
      await h.page.goBack(); await toggle.waitFor(); await toggle.uncheck();
      await h.page.getByRole('link', { name: 'Planning', exact: true }).click();
      const dialog = h.page.getByRole('dialog', { name: 'Quitter sans enregistrer ?' }); await dialog.waitFor();
      await dialog.getByRole('button', { name: 'Retour', exact: true }).click();
      assert(new URL(h.page.url()).pathname.endsWith('/signalements')); assert.equal(await toggle.isChecked(), false);
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.getByText('Enregistré', { exact: true }).waitFor();
      await h.page.getByRole('link', { name: 'Planning', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
      assert.equal(await h.page.getByRole('dialog').count(), 0);
    });
    for (const role of ['learner', 'instructor']) await scenario(`Accès direct console refusé au rôle ${role}`, `page=learners&shell=1&role=${role}`, async h => {
      assert.equal(await h.page.getByLabel('Rechercher un élève', { exact: true }).count(), 0); assert.match(await h.page.locator('body').innerText(), /administration|administrateur|réservé/i);
    });
    for (const state of ['empty', 'error', 'slow']) await scenario(`État ${state} lisible sans erreur JavaScript`, `page=${state === 'slow' ? 'agenda' : 'learners'}&shell=1&state=${state}`, async h => {
      if (state === 'slow') { assert(await h.page.getByRole('status').count() > 0); await h.page.getByRole('button', { name: /Éloïse/ }).first().waitFor(); }
      else { const text = await h.page.locator('body').innerText(); assert.match(text, state === 'empty' ? /aucun élève/i : /réessayer|indisponible|recharger/i); }
    });
    await scenario('Contrôles natifs : case mixte, clavier, contrôles désactivés et erreurs associées', 'page=controls', async h => {
      const aggregate = h.page.getByRole('checkbox', { name: 'Sélectionner tous les jours', exact: true });
      assert(await aggregate.evaluate(input => input.type === 'checkbox' && input.indeterminate && !input.checked));
      assert(await aggregate.evaluate(input => input.closest('label').getBoundingClientRect().height >= 40));
      await aggregate.focus(); await h.page.keyboard.press('Space');
      assert(await aggregate.isChecked()); assert.equal(await aggregate.evaluate(input => input.indeterminate), false);
      await h.page.getByRole('status').filter({ hasText: '2 jours sélectionnés' }).waitFor();
      await h.page.keyboard.press('Space');
      await h.page.getByRole('status').filter({ hasText: '0 jours sélectionnés' }).waitFor();
      await h.page.getByRole('checkbox', { name: 'Lundi', exact: true }).check();
      assert(await aggregate.evaluate(input => input.indeterminate));
      for (const name of ['Case désactivée non cochée', 'Case désactivée cochée', 'Case désactivée mixte']) assert(await h.page.getByRole('checkbox', { name, exact: true }).isDisabled());
      await h.page.getByRole('checkbox', { name: 'Mardi', exact: true }).focus(); await h.page.keyboard.press('Tab');
      assert(await h.page.getByRole('checkbox', { name: 'J’ai relu les choix de démonstration.', exact: true }).evaluate(input => input === document.activeElement));
      const light = h.page.getByRole('radio', { name: 'Clair', exact: true }); await light.check(); await light.focus(); await h.page.keyboard.press('ArrowRight');
      assert(await h.page.getByRole('radio', { name: 'Sombre', exact: true }).isChecked());
      const email = h.page.getByLabel('E-mail de test', { exact: true }); await email.fill('invalide'); await email.press('Enter');
      await h.page.waitForFunction(() => document.activeElement?.getAttribute('type') === 'email' && document.activeElement?.getAttribute('aria-invalid') === 'true');
      assert(await email.evaluate(input => input === document.activeElement && input.getAttribute('aria-invalid') === 'true' && !!document.getElementById(input.getAttribute('aria-describedby'))?.textContent));
      await email.fill('controle@example.test'); await email.press('Enter');
      await h.page.waitForFunction(() => document.activeElement?.tagName === 'SELECT');
      const category = h.page.getByLabel('Catégorie de test', { exact: true }); assert(await category.evaluate(input => input === document.activeElement && input.getAttribute('aria-invalid') === 'true'));
      await category.selectOption('B'); await h.page.getByRole('button', { name: 'Vérifier la saisie', exact: true }).click();
      await h.page.getByText('Saisie de test valide.', { exact: true }).waitFor();
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
    await scenario('Pagination élèves : page deux, liens natifs, retour au contexte et homonymes', 'page=learners&shell=1&stress=1&volume=1', async h => {
      const rows = h.page.locator('.record-table tbody tr'); assert.equal(await rows.count(), 25);
      const pagination = h.page.getByRole('navigation', { name: 'Pagination des élèves', exact: true });
      await pagination.getByRole('button', { name: 'Suivant', exact: true }).click(); assert.equal(await rows.count(), 11);
      const zoe = h.page.getByRole('link', { name: 'Zoé Girard', exact: true });
      const href = await zoe.getAttribute('href'); assert.match(href, /[?&]selection=[\da-f-]{36}/);
      const [popup] = await Promise.all([h.context.waitForEvent('page'), zoe.click({ modifiers: ['Control'] })]);
      await popup.waitForLoadState('domcontentloaded'); assert.equal(popup.url(), new URL(href, origin).href);
      // Edge's native background-tab first request can escape context.route. Preserve and verify
      // its genuine destination, then reload the same URL to install the synthetic BFF fixture.
      if (!(await popup.evaluate(() => !!window.__reviewBoot))) await popup.reload();
      await popup.getByRole('heading', { name: 'Zoé Girard', exact: true }).waitFor({ timeout: 8000 });
      await popup.close();
      assert.equal(await rows.count(), 11); assert.equal(new URL(h.page.url()).searchParams.has('selection'), false);
      await zoe.click(); await h.page.getByRole('heading', { name: 'Zoé Girard', exact: true }).waitFor();
      assert.equal(await h.page.locator('.record-table').isVisible(), false);
      await h.page.getByRole('button', { name: 'Tous les élèves', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.textContent === 'Zoé Girard');
      assert.equal(await rows.count(), 11); assert(await zoe.evaluate(link => link === document.activeElement));
      await zoe.click(); await h.page.goBack(); await settle(h.page); assert.equal(await rows.count(), 11);
      const search = h.page.getByLabel('Rechercher un élève', { exact: true }); await search.fill('Camille Rochat');
      assert.equal(await rows.count(), 2); assert.match(await h.page.locator('.record-table').innerText(), /camille\.1@example\.test/); assert.match(await h.page.locator('.record-table').innerText(), /camille\.2@example\.test/);
      await search.fill('camille.2@example.test'); assert.equal(await rows.count(), 1); assert.equal(h.page.url().includes('camille'), false);
      await h.page.getByRole('button', { name: 'Réinitialiser les filtres', exact: true }).click(); assert.equal(await rows.count(), 25);
    });
    await scenario('Dossier direct : élève absent de la liste malgré une panne de l’annuaire', 'page=learners&shell=1&selection=outside&state=directory-error', async h => {
      await h.page.getByRole('heading', { name: 'Diane Horizon', exact: true }).waitFor();
      assert.match(await h.page.locator('.detail-panel').innerText(), /diane@example\.test/);
      const selected = new URL(h.page.url()).searchParams.get('selection');
      assert(await h.page.evaluate(id => window.__reads.includes(`learners/${id}`), selected));
    });
    await scenario('Dossier direct inexistant : réponse 404 distincte d’une panne', 'page=learners&shell=1&selection=missing', async h => {
      await h.page.getByText('Cette information n’est pas disponible avec vos accès actuels.', { exact: true }).waitFor();
      assert.equal(await h.page.getByRole('heading', { name: 'Diane Horizon', exact: true }).count(), 0);
      const selected = new URL(h.page.url()).searchParams.get('selection');
      assert(await h.page.evaluate(id => window.__reads.includes(`learners/${id}`), selected));
    });
    await scenario('Annuaire élèves : panne secondaire du référentiel sans disparition des dossiers', 'page=learners&shell=1&fail=curricula', async h => {
      await h.page.getByRole('link', { name: 'Éloïse Müller', exact: true }).waitFor();
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 2);
      await h.page.getByRole('link', { name: 'Éloïse Müller', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
      assert.match(await h.page.locator('main').innerText(), /indisponible|impossible|non consultable|non disponibles/i);
    });
    await scenario('Catalogue : recherche par compétence, conservation au retour et validation par Entrée', 'page=curricula&shell=1', async h => {
      const search = h.page.getByLabel('Rechercher un référentiel', { exact: true });
      await search.fill('equilibre'); assert.equal(await h.page.locator('.data-table tbody tr').count(), 1);
      await h.page.getByRole('button', { name: 'Catégorie A', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Catégorie A · révision 1', exact: true }).waitFor();
      await h.page.goBack(); await settle(h.page); assert.equal(await search.inputValue(), 'equilibre');
      await h.page.getByRole('button', { name: 'Effacer la recherche', exact: true }).click(); assert.equal(await h.page.locator('.data-table tbody tr').count(), 2);
      await h.page.getByRole('button', { name: 'Nouveau référentiel', exact: true }).click();
      await h.page.getByLabel('Catégorie', { exact: true }).fill('BE'); await h.page.getByLabel('Catégorie', { exact: true }).press('Enter');
      await h.page.waitForFunction(() => document.activeElement?.getAttribute('aria-invalid') === 'true');
      const label = h.page.getByLabel('Libellé', { exact: true });
      assert(await label.evaluate(input => input === document.activeElement && input.getAttribute('aria-invalid') === 'true'));
      assert.equal(await h.page.evaluate(() => window.__log.length), 0); assert.equal(await h.page.getByRole('dialog').count(), 0);
    });
    await scenario('Catalogue : conditions valides ouvrent la relecture par Entrée sans écriture anticipée', 'page=terms&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Nouvelles conditions', exact: true }).click();
      await h.page.getByLabel('Libellé', { exact: true }).fill('Conditions synthétiques de recette');
      await h.page.getByLabel('Texte des conditions', { exact: true }).fill('Texte local utilisé pour vérifier la relecture avant confirmation.');
      await h.page.getByLabel('Valables dès le', { exact: true }).fill('2026-10-13');
      await h.page.getByLabel('Libellé', { exact: true }).press('Enter');
      await h.page.getByRole('dialog').waitFor(); assert.equal(await h.page.evaluate(() => window.__log.length), 0);
      assert.equal(await h.page.getByRole('dialog').getByRole('checkbox').isChecked(), false);
    });
    await scenario('Catalogue : la barre d’enregistrement ne masque aucun champ parcouru au clavier', 'page=curricula&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Nouveau référentiel', exact: true }).click();
      for (const viewport of [{ width: 1440, height: 1000 }, { width: 1280, height: 720 }, { width: 720, height: 500 }]) {
        await h.page.setViewportSize(viewport); await h.page.getByLabel('Catégorie', { exact: true }).focus();
        for (let index = 0; index < 7; index++) {
          assert(await h.page.evaluate(() => {
            const active = document.activeElement, rect = active.getBoundingClientRect(), bar = document.querySelector('.editor-save-bar').getBoundingClientRect();
            return rect.top >= 0 && rect.bottom <= innerHeight && !(rect.left < bar.right && rect.right > bar.left && rect.top < bar.bottom && rect.bottom > bar.top);
          }), `Champ focalisé visible à ${viewport.width}×${viewport.height}`);
          await h.page.keyboard.press('Tab');
        }
      }
    });
  }
  if (!process.argv.includes('--checks-only')) {
    const pages = process.env.DRIVY_CAPTURE_TARGETS?.split(',') ?? ['learners', 'learner-detail', 'config', 'agenda', 'trips', 'privacy', 'preferences', 'team', 'team-detail', 'availability', 'absences', 'themes', 'formations', 'curricula', 'curriculum-form', 'procedures', 'offerings', 'products', 'terms', 'overview', 'profile', 'invitations', 'invitations-team', 'signin', 'account', 'invitation', 'opening', 'operator', 'setup-identity', 'setup-privacy', 'setup-profile', 'setup-formations', 'setup-pricing', 'setup-review', 'controls'];
    for (const theme of ['light', 'dark']) for (const target of pages) {
      stage = `capture ${target} ${theme}`;
      const widths = [1440, 1024, 390];
      const parameters = target.startsWith('setup-') ? `page=overview&status=draft&step=${target.slice(6).toUpperCase()}&setup=ready`
        : target === 'curriculum-form' ? 'page=curricula'
        : target === 'learner-detail' ? 'page=learners'
        : target === 'team-detail' ? 'page=team'
        : target === 'invitations-team' ? 'page=invitations&audience=team' : `page=${target}`;
      const h = await harness(`${parameters}&shell=1&stress=1`, { colorScheme: theme });
      try {
        await h.open();
        if (target === 'setup-review') { await h.page.getByRole('button', { name: 'Vérifier la préparation', exact: true }).click(); await settle(h.page); }
        if (target === 'curriculum-form') { await h.page.getByRole('button', { name: 'Nouveau référentiel', exact: true }).click(); await settle(h.page); }
        if (target === 'learner-detail') { await h.page.getByRole('link', { name: /Éloïse/ }).first().click(); await settle(h.page); }
        if (target === 'team-detail') { await h.page.getByRole('link', { name: /Marie-Christine/ }).first().click(); await settle(h.page); }
        if (target === 'learner-detail' || target === 'team-detail') assert.equal(await h.page.getByRole('heading', { level: 1 }).count(), 1);
        for (const width of widths) {
          await h.page.setViewportSize({ width, height: width === 390 ? 844 : 1000 }); await settle(h.page);
          const file = `${target}-${width}-${theme}-synthetic.png`; await h.page.screenshot({ path: resolve(directory, file), fullPage: true });
          const overflow = !(await noOverflow(h.page)); captures.push({ target, theme, width, file, horizontalOverflow: overflow, pageErrors: h.errors });
          if (overflow || h.errors.length) failures.push({ scenario: `${target} ${width}px ${theme}`, error: overflow ? 'Horizontal document overflow' : 'JavaScript error' });
          if (process.argv.includes('--axe') && width !== 1024) {
            await h.page.addScriptTag({ path: resolve('.local/a11y/node_modules/axe-core/axe.min.js') });
            const audit = await auditAccessibility(h.page);
            accessibility.push({ target, theme, width, ...audit });
            if (audit.violations.length) failures.push({ scenario: `axe ${target} ${width}px ${theme}`, error: audit.violations.map(item => item.id).join(', ') });
            if (target === 'curriculum-form' && width === 1440 && audit.incomplete.length) {
              await h.page.getByLabel('Catégorie', { exact: true }).focus();
              for (let index = 0; index < 6; index++) await h.page.keyboard.press('Tab');
              const focusedAudit = await auditAccessibility(h.page);
              accessibility.push({ target, theme, width, state: 'after-keyboard-scroll', ...focusedAudit });
              const file = `curriculum-form-${width}-${theme}-keyboard-synthetic.png`;
              await h.page.screenshot({ path: resolve(directory, file) });
              supplemental.push({ target, theme, width, file, state: 'after-keyboard-scroll' });
              // Incomplete results remain in the report for manual review; they are not violations.
              if (focusedAudit.violations.length) failures.push({ scenario: `axe après défilement ${target} ${width}px ${theme}`, error: focusedAudit.violations.map(item => item.id).join(', ') });
            }
          }
        }
        if (target === 'config') {
          await h.page.setViewportSize({ width: 1440, height: 1000 }); await settle(h.page);
          await h.page.screenshot({ path: resolve(directory, `config-form-1440-${theme}-synthetic.png`), fullPage: true });
        }
      } finally { await h.context.close(); }
    }
    const h = await harness('page=learners&shell=1&stress=1', { viewport: { width: 720, height: 500 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
    try {
      await h.open(); assert(await noOverflow(h.page)); await h.page.screenshot({ path: resolve(directory, 'learners-200-percent-reflow-synthetic.png'), fullPage: true });
      checks.push('Reflow 720 CSS px à échelle 2 et réduction des animations (équivalent géométrique du zoom desktop 200 %)');
    } finally { await h.context.close(); }
    if (pages.includes('controls')) {
      const h = await harness('page=controls', { forcedColors: 'active' });
      try {
        await h.open();
        const styles = await h.page.evaluate(() => ({ active: matchMedia('(forced-colors: active)').matches,
          checkboxes: [...document.querySelectorAll('.check-control input')].map(input => getComputedStyle(input).appearance),
          radios: [...document.querySelectorAll('.theme-option input')].map(input => getComputedStyle(input).appearance),
          svg: [...document.querySelectorAll('.check-control svg')].map(svg => getComputedStyle(svg).display) }));
        assert(styles.active && styles.checkboxes.every(value => value === 'auto') && styles.radios.every(value => value === 'auto') && styles.svg.every(value => value === 'none'));
        const file = 'controls-1440-forced-colors-synthetic.png'; await h.page.screenshot({ path: resolve(directory, file), fullPage: true });
        supplemental.push({ target: 'controls', width: 1440, file, state: 'forced-colors', styles });
        checks.push('Couleurs forcées émulées : cases et radios natifs, SVG des cases masqués');
      } finally { await h.context.close(); }
    }
  }
} catch (error) { failures.push({ scenario: stage, error: String(error.message).split('\n')[0] }); }
finally {
  await writeFile(resolve(directory, process.argv.includes('--checks-only') ? checkFilter ? 'interaction-filtered-results.json' : 'interaction-results.json' : process.env.DRIVY_CAPTURE_TARGETS ? `targeted-${process.env.DRIVY_CAPTURE_TARGETS.replaceAll(',', '-')}-results.json` : 'review-results.json'), JSON.stringify({ scope, nativeTabFixture: 'Destination Ctrl-clic vérifiée avant rechargement du même URL pour installer le BFF synthétique dans le nouvel onglet Edge.', checkFilter: checkFilter?.source ?? null, browser: browser.version(), checks, captures, supplemental, accessibility, failures }, null, 2));
  await browser.close(); console.log(JSON.stringify({ passed: checks.length, captures: captures.length, failures, directory }));
  if (failures.length) process.exitCode = 1;
}
