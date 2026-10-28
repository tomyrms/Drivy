/** Targeted EPIC #280 smoke: real React/Edge, local synthetic BFF and persisted pageshow event.
 * Does not qualify real browser bfcache, OIDC, PostgreSQL, or the full #309/#84 campaign. */
import assert from 'node:assert/strict';

const { chromium } = await import(process.env.DRIVY_PLAYWRIGHT_MODULE ?? '../../infra/dev/node_modules/playwright-core/index.mjs');
const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5187';
assert(['127.0.0.1', 'localhost'].includes(new URL(origin).hostname), 'LOOPBACK_REVIEW_REQUIRED');
const browser = await chromium.launch({ channel: process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge', headless: true });
const checks = [], failures = [];

async function scenario(name, parameters, run) {
  if (process.env.DRIVY_ACCESS_CHECK_FILTER && !new RegExp(process.env.DRIVY_ACCESS_CHECK_FILTER).test(name)) return;
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'fr-CH' });
  await context.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
  const page = await context.newPage(); page.setDefaultTimeout(6500);
  const errors = []; page.on('pageerror', error => errors.push(error.name));
  try {
    await page.goto(`${origin}/app/test/visual.html?${parameters}`);
    await page.waitForFunction(() => typeof window.__reviewSnapshot === 'function');
    await run(page);
    assert.deepEqual(errors, [], 'No React runtime exception');
    checks.push(name);
  } catch (error) { failures.push({ name, error: String(error.message).slice(0, 1600), visibleDialog: (await page.getByRole('dialog').allTextContents()).join(' ').slice(0, 1200) }); }
  finally { await context.close(); }
}

async function editSchool(page) {
  await page.getByRole('button', { name: 'Modifier', exact: true }).click();
  await page.getByLabel('Nom de l’école').fill('Brouillon synthétique conservé');
}

async function gateResume(page, response = 'same') {
  await page.evaluate(response => {
    const original = window.fetch;
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    window.__releaseAccessSmoke = release;
    window.fetch = async (input, init) => {
      const path = new URL(String(input), location.href).pathname;
      if (path.endsWith('/bff/session')) await gate;
      const reply = await original(input, init);
      if (!path.endsWith('/bff/me')) return reply;
      if (response === 'unavailable') return { ...reply, ok: false, status: 503, json: async () => ({ code: 'SERVICE_UNAVAILABLE' }) };
      const body = await reply.json();
      if (response === 'denied') body.data.memberships = body.data.memberships.map(member => ({ ...member, roles: ['INSTRUCTOR'] }));
      if (response === 'changed') body.data.personId = '11111111-1111-4111-8111-999999999999';
      return { ...reply, json: async () => body };
    };
    window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
  }, response);
  await page.getByText('Vérification de vos accès…', { exact: true }).waitFor();
  assert.equal(await page.locator('.console-content').getAttribute('hidden'), '');
  assert.equal(await page.locator('.console-content').getAttribute('inert'), '');
  assert.equal(await page.getByRole('dialog').count(), 0, 'Portaled dialogs must be hidden during revalidation');
  assert.equal(await page.locator('.choice-positioner:visible').count(), 0, 'Portaled choices must be hidden during revalidation');
}
const releaseResume = page => page.evaluate(() => window.__releaseAccessSmoke());

try {
  await scenario('Same access preserves draft and search; portals hidden while checking', 'page=config&shell=1', async page => {
    await editSchool(page);
    await page.getByRole('button', { name: 'Rechercher un réglage' }).click();
    await page.getByLabel('Rechercher dans les paramètres').fill('Téléphone');
    await gateResume(page);
    assert.equal(await page.locator('#school-name').inputValue(), 'Brouillon synthétique conservé');
    await releaseResume(page);
    await page.getByRole('dialog', { name: 'Rechercher un réglage' }).waitFor();
    assert.equal(await page.getByLabel('Rechercher dans les paramètres').inputValue(), 'Téléphone');
    await page.keyboard.press('Escape');
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    assert.equal(await page.getByLabel('Nom de l’école').inputValue(), 'Brouillon synthétique conservé');
    assert.equal(await page.getByRole('button', { name: 'Enregistrer', exact: true }).isEnabled(), true);
  });

  await scenario('Unavailable rights keep the school hidden and permit retry', 'page=config&shell=1', async page => {
    await editSchool(page);
    await gateResume(page, 'unavailable');
    await releaseResume(page);
    await page.getByText('Vos accès doivent être vérifiés', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Réessayer', exact: true }).isEnabled(), true);
    assert.equal(await page.locator('.console-content').getAttribute('hidden'), '');
    assert.equal(await page.locator('#school-name').inputValue(), 'Brouillon synthétique conservé');
  });

  await scenario('Revoked administrative access removes the old school surface', 'page=config&shell=1', async page => {
    await editSchool(page);
    await gateResume(page, 'denied');
    await releaseResume(page);
    await page.locator('.access-resume-gate').waitFor({ state: 'hidden' });
    assert.equal(await page.locator('#school-name').count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Rechercher un réglage' }).count(), 0);
    assert.equal(await page.locator('.console-nav').count(), 0);
    await page.getByRole('heading', { name: 'Gestion réservée à l’administration' }).waitFor();
  });

  await scenario('Changed account does not retain another person’s draft', 'page=config&shell=1', async page => {
    await editSchool(page);
    await gateResume(page, 'changed');
    await releaseResume(page);
    await page.getByRole('button', { name: 'Modifier', exact: true }).waitFor();
    assert.equal(await page.locator('#school-name').count(), 0);
    await page.getByRole('button', { name: 'Modifier', exact: true }).click();
    assert.equal(await page.getByLabel('Nom de l’école').inputValue(), 'École Synthétique');
  });

  await scenario('Sending command keeps busy guard after access revalidation', 'page=team&shell=1', async page => {
    await page.getByRole('link', { name: 'Marie Dupont', exact: true }).click();
    await page.getByRole('button', { name: 'Retirer l’accès…', exact: true }).click();
    const dialog = page.getByRole('dialog', { name: 'Retirer l’accès', exact: true });
    await dialog.getByLabel('Motif du retrait').fill('Contrôle synthétique des protections');
    await dialog.getByRole('checkbox').check();
    await page.evaluate(() => {
      const original = window.fetch;
      // The local visual fixture models completed identity verification with this flag.
      // This smoke qualifies busy UI only; BFF identity verification has separate essential tests.
      window.__reauthed = true;
      window.__busySmoke = { count: 0, release: null };
      const pending = new Promise(resolve => { window.__busySmoke.release = resolve; });
      window.fetch = async (input, init) => {
        if (new URL(String(input), location.href).pathname.endsWith('/deactivate') && init?.method === 'POST') {
          window.__busySmoke.count++;
          await pending;
        }
        return original(input, init);
      };
    });
    await dialog.getByRole('button', { name: 'Retirer l’accès', exact: true }).click();
    await page.waitForFunction(() => window.__busySmoke.count === 1);
    await gateResume(page);
    await releaseResume(page);
    await dialog.waitFor();
    assert.equal(await dialog.getByRole('button', { name: 'Retour', exact: true }).isEnabled(), false);
    assert.equal(await dialog.locator('button[type="button"]').last().isEnabled(), false);
    await page.keyboard.press('Escape');
    assert.equal(await dialog.isVisible(), true, 'Busy dialog must reject Escape');
    assert.equal(await page.evaluate(() => window.__busySmoke.count), 1);
    await page.evaluate(() => window.__busySmoke.release());
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    await page.locator('#main').getByText('Marie Dupont n’a plus accès à l’école.', { exact: true }).waitFor();
  });

  await scenario('Select keyboard navigation stays inside the dialog and returns focus', 'page=choices', async page => {
    const trigger = page.getByRole('button', { name: 'Ouvrir le dialogue de test' });
    await trigger.click();
    const dialog = page.getByRole('dialog', { name: 'Dialogue de choix local' });
    await dialog.waitFor();
    const select = dialog.getByRole('combobox', { name: 'Permis du dialogue' });
    await select.focus(); await page.keyboard.press('ArrowDown');
    await page.getByRole('listbox').waitFor();
    await page.keyboard.press('End'); await page.keyboard.press('Enter');
    await page.getByRole('listbox').waitFor({ state: 'hidden' });
    assert.match(await select.innerText(), /BE/);
    for (let index = 0; index < 8; index++) {
      await page.keyboard.press('Tab');
      await page.waitForFunction(() => !!document.activeElement?.closest('[role="dialog"]'));
    }
    await page.keyboard.press('Escape');
    await dialog.waitFor({ state: 'hidden' });
    await page.waitForFunction(element => element === document.activeElement, await trigger.elementHandle());
  });
} finally { await browser.close(); }

console.log(JSON.stringify({ scope: 'Local synthetic BFF; actual React in Edge; synthetic pageshow.persisted. No full acceptance campaign.', checks, failures }, null, 2));
if (failures.length) process.exitCode = 1;
