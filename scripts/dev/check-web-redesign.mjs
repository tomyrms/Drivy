/** Edge checks of real React components. BFF and reload state are synthetic fixtures. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5173';
if (!['127.0.0.1', 'localhost'].includes(new URL(origin).hostname)) throw new Error('LOOPBACK_REVIEW_REQUIRED');
const directory = resolve(process.env.DRIVY_REVIEW_DIRECTORY ?? 'artifacts/web-redesign-20261013/after');
const captureWidths = process.env.DRIVY_CAPTURE_WIDTHS?.split(',').map(value => Number(value.trim())) ?? [320, 390, 768, 1024, 1440];
assert(captureWidths.length > 0 && captureWidths.every(width => Number.isInteger(width) && width >= 240 && width <= 3840), 'DRIVY_CAPTURE_WIDTHS must contain integer widths between 240 and 3840.');
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
async function scenario(label, parameters, run, options = {}) {
  if (checkFilter && !checkFilter.test(label)) return;
  stage = label; const h = await harness(parameters, options);
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
      await h.page.waitForFunction(() => document.activeElement?.id === 'school-phone');
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
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 01 02');
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click(); await settle(h.page);
      await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).waitFor();
      await h.reload(); await h.page.getByText('+41 21 555 01 02', { exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
      assert.equal(await h.page.getByLabel(/Téléphone/).inputValue(), '+41 21 555 01 02');
    });
    await scenario('Coordonnées : lecture initiale, modification explicite et fermeture sans écriture', 'page=config&shell=1', async h => {
      assert.equal(await h.page.locator('#school-phone').count(), 0);
      const edit = h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }); await edit.click();
      await h.page.locator('#school-phone').waitFor();
      await h.page.getByRole('button', { name: 'Terminer', exact: true }).click();
      await edit.waitFor(); assert.equal(await h.page.getByRole('dialog').count(), 0);
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
    await scenario('Refus enregistrement : erreur, saisie conservée, aucun faux succès', 'page=config&shell=1&state=mutation-error', async h => {
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 01 03');
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click(); await settle(h.page);
      assert.equal(await h.page.getByLabel(/Téléphone/).inputValue(), '+41 21 555 01 03'); assert(await h.page.getByRole('alert').count() > 0);
      assert.equal(await h.page.getByText('Les coordonnées de l’école sont enregistrées.', { exact: true }).count(), 0);
    });
    await scenario('Validation formulaire : erreur près du champ, focus et absence d’envoi invalide', 'page=config&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
      const email = h.page.getByLabel('E-mail de l’école', { exact: true });
      await email.fill('adresse-invalide'); await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.id === 'school-email');
      assert.equal(await email.getAttribute('aria-invalid'), 'true');
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
    await scenario('Conflit coordonnées : relecture version serveur, saisie conservée et nouvel envoi confirmé', 'page=config&shell=1&state=conflict-once', async h => {
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
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
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
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
      await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click();
      await h.page.getByLabel(/Téléphone/).fill('+41 21 555 09 09');
      await h.page.getByRole('link', { name: 'Retour à la gestion', exact: true }).click();
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
      await h.page.getByRole('link', { name: 'Retour à la gestion', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
      assert.equal(await h.page.getByRole('dialog').count(), 0);
      await h.page.goBack(); await toggle.waitFor(); await toggle.uncheck();
      await h.page.getByRole('link', { name: 'Retour à la gestion', exact: true }).click();
      const dialog = h.page.getByRole('dialog', { name: 'Quitter sans enregistrer ?' }); await dialog.waitFor();
      await dialog.getByRole('button', { name: 'Retour', exact: true }).click();
      assert(new URL(h.page.url()).pathname.endsWith('/signalements')); assert.equal(await toggle.isChecked(), false);
      await h.page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
      await h.page.getByText('Enregistré', { exact: true }).waitFor();
      await h.page.getByRole('link', { name: 'Retour à la gestion', exact: true }).click();
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
      await h.page.waitForFunction(() => document.activeElement?.getAttribute('aria-haspopup') === 'listbox');
      const category = h.page.getByLabel('Catégorie de test', { exact: true }); assert(await category.evaluate(input => input === document.activeElement && input.getAttribute('aria-invalid') === 'true'));
      await category.click(); await h.page.getByRole('option', { name: 'Permis B', exact: true }).click(); await h.page.getByRole('button', { name: 'Vérifier la saisie', exact: true }).click();
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
      await h.page.waitForFunction(() => document.activeElement?.querySelector('.person-name')?.textContent === 'Zoé Girard');
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
    await scenario('Tri et filtre élèves : en-tête au clavier, page réinitialisée et profil choisi dans le menu', 'page=learners&shell=1&stress=1&volume=1', async h => {
      const pagination = h.page.getByRole('navigation', { name: 'Pagination des élèves', exact: true });
      await pagination.getByRole('button', { name: 'Suivant', exact: true }).click();
      const sort = h.page.getByRole('button', { name: 'Élève, trier par nom décroissant', exact: true }); await sort.focus(); await sort.press('Enter');
      assert.equal(await h.page.locator('.record-table th[aria-sort]').getAttribute('aria-sort'), 'descending');
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 25); assert(await pagination.getByRole('button', { name: 'Précédent', exact: true }).isDisabled());
      assert.equal(await h.page.locator('.record-link .person-name').first().innerText(), 'Zoé Girard');
      await h.page.getByLabel('Profil', { exact: true }).click(); await h.page.getByRole('option', { name: 'À compléter', exact: true }).click();
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 1); assert.match(await h.page.locator('.record-link').innerText(), /Éloïse/);
      await h.page.getByLabel('Profil', { exact: true }).click(); await h.page.getByRole('option', { name: 'Tous les profils', exact: true }).click();
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 25);
    });
    await scenario('Équipe : tri, filtre inactif et contexte conservé après ouverture du membre', 'page=team&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Luc Martin', exact: true }).waitFor();
      await h.page.locator('.record-table tbody tr').filter({ has: h.page.getByRole('link', { name: 'Luc Martin', exact: true }) }).getByText('Vous', { exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Membre, trier par nom décroissant', exact: true }).click();
      assert.equal(await h.page.locator('.record-table th[aria-sort]').getAttribute('aria-sort'), 'descending');
      await h.page.getByRole('group', { name: 'Accès', exact: true }).getByRole('button', { name: /Inactifs/ }).click();
      const member = h.page.getByRole('link', { name: 'Paul Suspendu', exact: true }); assert.equal(await h.page.locator('.record-table tbody tr').count(), 1);
      await member.click(); await h.page.getByRole('heading', { name: 'Paul Suspendu', exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Tous les membres', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.querySelector('.person-name')?.textContent === 'Paul Suspendu');
      assert.equal(await h.page.locator('.record-table tbody tr').count(), 1); assert.equal(await h.page.locator('.record-table th[aria-sort]').getAttribute('aria-sort'), 'descending');
    });
    await scenario('Agenda : semaine, moniteur et recherche conservés au retour du dossier', 'page=agenda&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Semaine suivante', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Aucune leçon cette semaine', exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Semaine précédente', exact: true }).click();
      await h.page.getByLabel('Moniteur', { exact: true }).click(); await h.page.getByRole('combobox', { name: 'Rechercher : Moniteur', exact: true }).fill('Marie');
      await h.page.getByRole('option', { name: 'Marie Dupont', exact: true }).click();
      await h.page.getByLabel('Élève', { exact: true }).fill('eloise');
      const previous = h.page.url(); assert.equal(new URL(previous).searchParams.get('week'), '2026-09-28'); assert(new URL(previous).searchParams.has('instructor')); assert(!previous.includes('eloise'));
      await h.page.locator('.agenda-lesson').first().click(); await h.page.getByRole('heading', { name: 'Éloïse Müller', exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Retour à l’agenda', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor(); assert.equal(h.page.url(), previous);
      assert.equal(await h.page.getByLabel('Élève', { exact: true }).inputValue(), 'eloise');
      await h.page.getByLabel('Moniteur', { exact: true }).filter({ hasText: 'Marie Dupont' }).waitFor();
      await h.page.locator('.agenda-lesson').first().waitFor();
      assert.equal(await h.page.locator('.agenda-lesson').count(), 2);
      await h.page.getByRole('link', { name: 'Disponibilités', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Disponibilités', exact: true }).waitFor();
      const home = h.page.getByRole('link', { name: 'Planning', exact: true });
      assert.equal(new URL(await home.getAttribute('href'), origin).href, previous);
      await home.click(); await h.page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
      assert.equal(h.page.url(), previous); assert.equal(await h.page.getByLabel('Élève', { exact: true }).inputValue(), 'eloise');
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
    await scenario('Formations : Permis B depuis la liste, rubriques adressables, précédent et suivant', 'page=formations&shell=1', async h => {
      await h.page.getByRole('link', { name: 'Permis B', exact: true }).click();
      await h.page.getByRole('heading', { name: 'Permis B', level: 1 }).waitFor();
      const tabs = h.page.getByRole('navigation', { name: 'Rubriques du permis B', exact: true });
      await tabs.getByRole('link', { name: 'Tarifs', exact: true }).click(); await h.page.getByRole('heading', { name: 'Tarifs', exact: true }).waitFor();
      assert.equal(new URL(h.page.url()).searchParams.get('view'), 'tarifs');
      await h.page.goBack(); await h.page.getByRole('heading', { name: 'Général', exact: true }).waitFor();
      await h.page.goForward(); await h.page.getByRole('heading', { name: 'Tarifs', exact: true }).waitFor();
      await h.reload(); await h.page.getByRole('heading', { name: 'Tarifs', exact: true }).waitFor();
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
    await scenario('Formations : compétences modifiées sur place, saisie conservée entre rubriques, une seule commande', 'page=formation&view=competences&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Modifier les compétences', exact: true }).click();
      await h.page.getByRole('button', { name: 'Ajouter une compétence', exact: true }).click();
      const added = h.page.locator('.competency-row').nth(2);
      await h.page.getByRole('button', { name: 'Enregistrer les compétences', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.getAttribute('aria-invalid') === 'true');
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
      await added.getByRole('textbox').first().fill('Conduite de nuit'); await added.locator('textarea').fill('Adapter sa conduite.');
      const up = h.page.getByRole('button', { name: 'Monter Conduite de nuit', exact: true }); await up.focus(); await h.page.keyboard.press('Enter');
      assert.equal(await h.page.evaluate(() => document.activeElement?.getAttribute('aria-label')), 'Monter Conduite de nuit');
      const tabs = h.page.getByRole('navigation', { name: 'Rubriques du permis B', exact: true });
      await tabs.getByRole('link', { name: 'Tarifs', exact: true }).click(); await tabs.getByRole('link', { name: /Compétences.*modification en cours/ }).click();
      assert.equal(await h.page.locator('.competency-row').nth(1).getByRole('textbox').first().inputValue(), 'Conduite de nuit');
      assert.equal(await h.page.evaluate(() => Object.keys(localStorage).every(key => key === 'drivy.web.theme')), true);
      await h.page.getByRole('button', { name: 'Enregistrer les compétences', exact: true }).click();
      await h.page.getByText('Les compétences sont enregistrées pour les nouvelles inscriptions.', { exact: true }).waitFor();
      const writes = await h.page.evaluate(() => window.__log.filter(line => line.startsWith('POST')));
      assert.equal(writes.length, 1); assert.match(writes[0], /^POST formations\/programmes /);
      await h.page.getByText('Conduite de nuit', { exact: true }).waitFor();
    });
    await scenario('Formations : tarif ajouté depuis la fiche, prix absent refusé puis zéro accepté', 'page=formation&view=tarifs&shell=1', async h => {
      await h.page.getByRole('button', { name: 'Ajouter un tarif', exact: true }).click();
      await h.page.getByLabel('Nom du tarif', { exact: true }).fill('Leçon d’essai offerte');
      await h.page.getByRole('button', { name: 'Ajouter le tarif', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.getAttribute('aria-invalid') === 'true');
      assert.equal(await h.page.getByLabel('Prix (CHF)', { exact: true }).getAttribute('aria-invalid'), 'true');
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
      await h.page.getByLabel('Prix (CHF)', { exact: true }).fill('0');
      await h.page.getByRole('button', { name: 'Ajouter le tarif', exact: true }).click();
      await h.page.getByText('Le tarif est ajouté.', { exact: true }).waitFor();
      const write = await h.page.evaluate(() => window.__log.find(line => line.startsWith('POST formations/tariffs')));
      assert.match(write, /"priceCents":0/); assert.match(write, /"categoryCode":"B"/);
      assert.equal(await h.page.evaluate(() => window.__log.some(line => line.includes('setup-draft'))), false);
    });
    await scenario('Formations : conflit explicite sans perte de saisie', 'page=formation&view=tarifs&shell=1&state=conflict', async h => {
      await h.page.getByRole('button', { name: /^Modifier / }).first().click();
      await h.page.getByLabel('Prix (CHF)', { exact: true }).fill('111');
      await h.page.getByRole('button', { name: 'Enregistrer le tarif', exact: true }).click();
      await h.page.getByText(/Ce tarif a été modifié entre-temps/).first().waitFor();
      assert.equal(await h.page.getByLabel('Prix (CHF)', { exact: true }).inputValue(), '111');
      await h.page.getByRole('button', { name: 'Recharger la fiche', exact: true }).click();
      await h.page.getByText('Ce tarif a changé pendant votre modification', { exact: true }).waitFor();
      await h.page.getByRole('button', { name: 'Enregistrer le tarif', exact: true }).click();
      await h.page.getByText(/Le tarif est enregistré/).waitFor();
    });
    await scenario('Formations : ancienne adresse d’une version précédente retrouvée dans l’historique', 'page=legacy&shell=1', async h => {
      await h.page.getByText('Version précédente', { exact: true }).first().waitFor();
      const url = new URL(h.page.url());
      assert.equal(url.pathname.endsWith('/formations'), true); assert.equal(url.searchParams.get('view'), 'historique');
    });
    await scenario('Formations : ancienne adresse d’un contenu actuel ouvre sa rubrique', 'page=legacy-current&shell=1', async h => {
      await h.page.getByRole('heading', { name: 'Compétences', exact: true }).waitFor();
      assert.equal(new URL(h.page.url()).searchParams.get('view'), 'competences');
    });
    await scenario('Formations : un permis déjà préparé n’est pas recréé par l’assistant', 'page=formation-new&shell=1', async h => {
      await h.page.getByLabel('Permis', { exact: true }).click();
      await h.page.getByRole('combobox', { name: 'Rechercher : Permis', exact: true }).fill('B');
      await h.page.getByRole('option', { name: 'Permis B · déjà préparé', exact: true }).click();
      await h.page.getByRole('link', { name: 'Ouvrir sa fiche', exact: true }).waitFor();
      assert.equal(await h.page.getByRole('button', { name: 'Continuer', exact: true }).isDisabled(), true);
    });
    await scenario('Choix simple : clavier, option désactivée, Échap, Tab et restitution du focus', 'page=choices', async h => {
      const trigger = h.page.getByLabel('Permis de test', { exact: true }), count = h.page.getByLabel('Nombre de changements', { exact: true });
      assert(await trigger.evaluate(element => element.tagName === 'BUTTON'));
      await trigger.focus(); await trigger.press('Enter'); await h.page.getByRole('option', { name: 'Permis A', exact: true }).waitFor();
      assert.equal(await h.page.getByRole('option', { name: 'Permis B', exact: true }).getAttribute('aria-disabled'), 'true');
      await h.page.keyboard.press('End'); await h.page.keyboard.press('Enter');
      await h.page.getByRole('listbox').waitFor({ state: 'hidden' }); assert.equal(await count.innerText(), '1'); assert.match(await trigger.innerText(), /Permis BE/);
      await trigger.press('Space'); await h.page.getByRole('listbox').waitFor(); await h.page.keyboard.press('Home'); await h.page.keyboard.press('Escape');
      await h.page.getByRole('listbox').waitFor({ state: 'hidden' }); assert(await trigger.evaluate(element => element === document.activeElement)); assert.equal(await count.innerText(), '1');
      await trigger.press('ArrowDown'); await h.page.getByRole('listbox').waitFor(); await h.page.keyboard.press('Tab');
      await h.page.getByRole('listbox').waitFor({ state: 'hidden' }); assert.equal(await count.innerText(), '1');
    });
    await scenario('Choix recherché : filtrer sans modifier, aucun résultat et sélection explicite', 'page=choices', async h => {
      const trigger = h.page.getByLabel('Personne de test', { exact: true }), count = h.page.getByLabel('Nombre de changements', { exact: true });
      await trigger.click(); const search = h.page.getByRole('combobox', { name: 'Rechercher : Personne de test', exact: true });
      await search.fill('introuvable'); await h.page.getByText('Aucun résultat', { exact: true }).waitFor(); assert.equal(await count.innerText(), '0');
      await search.fill('eloise'); await h.page.getByRole('option', { name: 'Éloïse Müller', exact: true }).waitFor(); assert.equal(await count.innerText(), '0');
      await search.press('ArrowDown'); await search.press('Enter'); await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert.equal(await count.innerText(), '1'); assert.match(await trigger.innerText(), /Éloïse Müller/); assert(await trigger.evaluate(element => element === document.activeElement));
      await trigger.click(); await search.fill('Bruno'); await search.press('Escape'); await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert.equal(await count.innerText(), '1'); assert.match(await trigger.innerText(), /Éloïse Müller/);
    });
    await scenario('Choix tactiles : cibles de 44 px et sélection par toucher dans le vrai menu', 'page=choices', async h => {
      assert(await h.page.evaluate(() => matchMedia('(pointer: coarse)').matches));
      assert(await h.page.locator('.choice-trigger,.segment-option > span').evaluateAll(elements => elements.filter(element => element.getClientRects().length > 0).every(element => element.getBoundingClientRect().height >= 44)));
      await h.page.getByLabel('Permis de test', { exact: true }).tap();
      await h.page.getByRole('option', { name: 'Permis BE', exact: true }).tap();
      await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert.equal(await h.page.getByLabel('Nombre de changements', { exact: true }).innerText(), '1');
      assert.match(await h.page.getByLabel('Permis de test', { exact: true }).innerText(), /Permis BE/);
    }, { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    await scenario('Choix vides : valeur métier vide, aucune option, choix retiré et désactivation', 'page=choices', async h => {
      const filter = h.page.getByLabel('Filtre de test', { exact: true }), count = h.page.getByLabel('Nombre de changements', { exact: true });
      await filter.click(); await h.page.getByRole('option', { name: 'Tous les permis', exact: true }).click();
      await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert.equal(await count.innerText(), '1'); assert.match(await filter.innerText(), /Tous les permis/);
      await h.page.getByLabel('Liste sans choix', { exact: true }).click(); await h.page.getByText('Aucun choix disponible', { exact: true }).waitFor();
      assert.equal(await h.page.getByRole('option').count(), 0); await h.page.keyboard.press('Escape'); assert.equal(await count.innerText(), '1');
      assert.equal(await h.page.getByLabel('Choix indisponible', { exact: true }).isEnabled(), false);
      await h.page.getByRole('button', { name: 'Retirer l’option sélectionnée', exact: true }).click();
      assert.match(await h.page.getByLabel('Choix retiré', { exact: true }).innerText(), /Choisir/); assert.equal(await count.innerText(), '1');
    });
    for (const label of ['Choix du groupe', 'Recherche du groupe']) await scenario(`Choix et fieldset : ${label} se ferme si le groupe est désactivé pendant l’ouverture`, 'page=choices', async h => {
      await h.page.getByRole('button', { name: 'Désactiver le groupe dans deux secondes', exact: true }).click();
      const trigger = h.page.getByLabel(label, { exact: true }); await trigger.click(); await h.page.getByRole('listbox').waitFor();
      await h.page.getByText('Groupe désactivé', { exact: true }).waitFor(); await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert.equal(await trigger.isEnabled(), false); assert.equal(await h.page.getByLabel('Nombre de changements', { exact: true }).innerText(), '0');
      await h.page.getByRole('button', { name: 'Réactiver le groupe', exact: true }).click(); await trigger.click();
      await h.page.getByRole('option', { name: label === 'Choix du groupe' ? 'Permis BE' : 'Bruno Blanc', exact: true }).click();
      assert.equal(await h.page.getByLabel('Nombre de changements', { exact: true }).innerText(), '1');
    });
    for (const width of [1440, 390]) for (const label of ['Permis du dialogue', 'Personne du dialogue']) await scenario(`Choix et dialogue ${width}px : ${label} reste dans le plan modal et Échap ferme une couche à la fois`, 'page=choices', async h => {
      await h.page.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
      const opener = h.page.getByRole('button', { name: 'Ouvrir le dialogue de test', exact: true }); await opener.click();
      const dialog = h.page.getByRole('dialog', { name: 'Dialogue de choix local', exact: true }), trigger = dialog.getByLabel(label, { exact: true });
      await trigger.click(); await dialog.getByRole('listbox').waitFor(); await settle(h.page);
      const option = dialog.getByRole('option', { name: label === 'Permis du dialogue' ? 'Permis BE' : 'Bruno Blanc', exact: true });
      assert(await option.evaluate(element => { const rect = element.getBoundingClientRect(); const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2); return element === hit || element.contains(hit); }), 'L’option du menu doit recevoir le clic au-dessus du dialogue');
      await h.page.keyboard.press('Escape'); await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
      assert(await dialog.isVisible()); assert(await trigger.evaluate(element => element === document.activeElement));
      await h.page.keyboard.press('Escape'); await dialog.waitFor({ state: 'hidden' }); assert(await opener.evaluate(element => element === document.activeElement));
    });
    await scenario('Choix invalide : vrai déclencheur focalisé et erreur associée, segment au clavier', 'page=choices', async h => {
      await h.page.getByRole('button', { name: 'Vérifier le choix', exact: true }).click();
      await h.page.waitForFunction(() => document.activeElement?.id === 'choice-required');
      const required = h.page.getByLabel('Choix obligatoire', { exact: true });
      assert(await required.evaluate(element => element.tagName === 'BUTTON' && element.getAttribute('aria-invalid') === 'true' && element.getAttribute('aria-describedby').split(' ').some(id => document.getElementById(id)?.textContent === 'Choisissez un permis.')));
      await required.press('Enter'); await h.page.getByRole('option', { name: 'Permis A', exact: true }).click();
      await h.page.getByRole('button', { name: 'Vérifier le choix', exact: true }).click(); await h.page.getByText('Choix local valide.', { exact: true }).waitFor();
      const segments = h.page.getByRole('group', { name: 'Permis segmenté', exact: true });
      await segments.getByRole('radio', { name: 'Permis A', exact: true }).focus(); await h.page.keyboard.press('ArrowRight');
      assert(await segments.getByRole('radio', { name: 'Permis BE', exact: true }).isChecked());
      assert(await segments.getByRole('radio', { name: 'Permis B', exact: true }).isDisabled());
      assert.equal(await h.page.evaluate(() => window.__log.length), 0);
    });
  }
  if (!process.argv.includes('--checks-only')) {
    const pages = process.env.DRIVY_CAPTURE_TARGETS?.split(',') ?? ['learners', 'learner-detail', 'config', 'config-form', 'agenda', 'trips', 'privacy', 'preferences', 'team', 'team-detail', 'availability', 'absences', 'themes', 'formations', 'formation', 'formation-competences', 'formation-competences-form', 'formation-rules', 'formation-tariffs', 'formation-tariff-form', 'formation-history', 'formation-new', 'uncategorized', 'conditions', 'overview', 'profile', 'invitations', 'invitations-team', 'signin', 'account', 'invitation', 'opening', 'operator', 'setup-identity', 'setup-privacy', 'setup-profile', 'setup-formations', 'setup-pricing', 'setup-review', 'controls', 'choices', 'choice-menu', 'choice-search', 'choice-dialog'];
    for (const theme of ['light', 'dark']) for (const target of pages) {
      stage = `capture ${target} ${theme}`;
      const widths = [...new Set(captureWidths)];
      const parameters = target.startsWith('setup-') ? `page=overview&status=draft&step=${target.slice(6).toUpperCase()}&setup=ready`
        : target.startsWith('formation-') && target !== 'formation-new' ? `page=formation&view=${{ 'formation-competences': 'competences', 'formation-competences-form': 'competences', 'formation-rules': 'deroulement', 'formation-tariffs': 'tarifs', 'formation-tariff-form': 'tarifs', 'formation-history': 'historique' }[target]}`
        : target === 'config-form' ? 'page=config'
        : target.startsWith('choice-') ? 'page=choices'
        : target === 'learner-detail' ? 'page=learners'
        : target === 'team-detail' ? 'page=team'
        : target === 'invitations-team' ? 'page=invitations&audience=team' : `page=${target}`;
      const h = await harness(`${parameters}&shell=1&stress=1`, { colorScheme: theme });
      try {
        await h.open();
        if (target === 'setup-review') { await h.page.getByRole('button', { name: 'Vérifier la préparation', exact: true }).click(); await settle(h.page); }
        if (target === 'formation-competences-form') { await h.page.getByRole('button', { name: 'Modifier les compétences', exact: true }).click(); await settle(h.page); }
        if (target === 'formation-tariff-form') { await h.page.getByRole('button', { name: 'Ajouter un tarif', exact: true }).click(); await settle(h.page); }
        if (target === 'config-form') { await h.page.getByRole('button', { name: 'Modifier les coordonnées', exact: true }).click(); await settle(h.page); }
        if (target === 'learner-detail') { await h.page.getByRole('link', { name: /Éloïse/ }).first().click(); await settle(h.page); }
        if (target === 'team-detail') { await h.page.getByRole('link', { name: /Marie-Christine/ }).first().click(); await settle(h.page); }
        if (target === 'learner-detail' || target === 'team-detail') assert.equal(await h.page.getByRole('heading', { level: 1 }).count(), 1);
        for (const width of widths) {
          await h.page.setViewportSize({ width, height: width <= 390 ? 844 : 1000 }); await settle(h.page);
          if (target.startsWith('choice-')) {
            if (target === 'choice-dialog') await h.page.getByRole('button', { name: 'Ouvrir le dialogue de test', exact: true }).click();
            await h.page.getByLabel(target === 'choice-menu' ? 'Permis de test' : target === 'choice-search' ? 'Personne de test' : 'Permis du dialogue', { exact: true }).click();
            await h.page.getByRole('listbox').waitFor(); await settle(h.page);
            assert(await h.page.locator('.choice-popup').evaluate(element => { const r = element.getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth; }), 'Le menu ouvert reste dans la largeur du viewport');
          }
          const file = `${target}-${width}-${theme}-synthetic.png`; await h.page.screenshot({ path: resolve(directory, file), fullPage: true });
          const overflow = !(await noOverflow(h.page)); captures.push({ target, theme, width, file, horizontalOverflow: overflow, pageErrors: h.errors });
          console.log(`JCODE_PROGRESS ${JSON.stringify({ message: `${target} ${width}px ${theme}`, current: captures.length, total: pages.length * 2 * widths.length, unit: 'captures' })}`);
          if (overflow || h.errors.length) failures.push({ scenario: `${target} ${width}px ${theme}`, error: overflow ? 'Horizontal document overflow' : 'JavaScript error' });
          if (process.argv.includes('--axe') && width !== 1024) {
            await h.page.addScriptTag({ path: resolve('.local/a11y/node_modules/axe-core/axe.min.js') });
            const audit = await auditAccessibility(h.page);
            accessibility.push({ target, theme, width, ...audit });
            if (audit.violations.length) failures.push({ scenario: `axe ${target} ${width}px ${theme}`, error: audit.violations.map(item => item.id).join(', ') });
            if (target === 'formation-competences-form' && width === 1440 && audit.incomplete.length) {
              await h.page.getByRole('button', { name: 'Ajouter une compétence', exact: true }).focus();
              for (let index = 0; index < 6; index++) await h.page.keyboard.press('Tab');
              const focusedAudit = await auditAccessibility(h.page);
              accessibility.push({ target, theme, width, state: 'after-keyboard-scroll', ...focusedAudit });
              const file = `formation-competences-form-${width}-${theme}-keyboard-synthetic.png`;
              await h.page.screenshot({ path: resolve(directory, file) });
              supplemental.push({ target, theme, width, file, state: 'after-keyboard-scroll' });
              // Incomplete results remain in the report for manual review; they are not violations.
              if (focusedAudit.violations.length) failures.push({ scenario: `axe après défilement ${target} ${width}px ${theme}`, error: focusedAudit.violations.map(item => item.id).join(', ') });
            }
          }
          if (target.startsWith('choice-')) {
            await h.page.keyboard.press('Escape'); await h.page.getByRole('listbox').waitFor({ state: 'hidden' });
            if (target === 'choice-dialog') { await h.page.keyboard.press('Escape'); await h.page.getByRole('dialog').waitFor({ state: 'hidden' }); }
          }
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
