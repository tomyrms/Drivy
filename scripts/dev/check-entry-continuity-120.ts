import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { buildWebApp } from '../../apps/web/server/app.js';
import type { IdentityProvider } from '../../apps/web/server/oidc.js';

// Real production build, synthetic browser-boundary responses only. No identity service or database.
const output = resolve('artifacts/entry-continuity-120');
const label = process.argv.includes('--red') ? 'red' : 'green';
const checks: string[] = [];
const session = { authenticated: true, csrfToken: 'synthetic-csrf', invitationPending: false,
  user: { displayName: 'Compte synthétique', emailVerified: true } };
const me = { data: { personId: '10000000-0000-4000-8000-000000000001', displayName: 'Compte synthétique', version: 1, memberships: [] } };
function gate() { let release!: () => void; const promise = new Promise<void>(done => { release = done; }); return { promise, release }; }
const unavailable = async (): Promise<never> => { throw new Error('Unexpected identity call'); };
const identity: IdentityProvider = { begin: unavailable, complete: unavailable, password: unavailable, refresh: unavailable, revoke: unavailable };
await mkdir(output, { recursive: true });
const app = await buildWebApp({ config: { origin: 'http://127.0.0.1', apiBaseURL: 'http://127.0.0.1:9', issuer: 'http://127.0.0.1:9',
  clientId: 'synthetic', clientSecret: 'synthetic-unused-client-secret', development: true, host: '127.0.0.1', port: 0 }, identity,
  staticRoot: resolve('apps/web/dist/client') });
const origin = await app.listen({ host: '127.0.0.1', port: 0 });
const browser = await chromium.launch({ channel: 'msedge', headless: true });
async function fixture(options: { unknown?: boolean; failMe?: boolean } = {}) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const firstSession = gate(), firstMe = gate(), nextMe = gate(), code = gate();
  let sessions = 0, reads = 0, submissions = 0;
  await page.route('**/app/bff/**', async route => {
    const path = new URL(route.request().url()).pathname.split('/app/bff/')[1];
    if (path === 'session') { if (++sessions === 1 && options.unknown) await firstSession.promise; return route.fulfill({ json: session }); }
    if (path === 'me') {
      if (++reads === 1) await firstMe.promise;
      else await nextMe.promise;
      if (reads === 1 && options.failMe) return route.fulfill({ status: 503, json: { code: 'API_UNAVAILABLE' } });
      return route.fulfill({ json: me });
    }
    if (path === 'access-code') { submissions++; await code.promise; return route.fulfill({ status: 422, json: { code: 'ACCESS_CODE_INVALID' } }); }
    throw new Error(`Unexpected synthetic route: ${path}`);
  });
  await page.goto(`${origin}/app/`);
  if (options.unknown) await page.getByRole('button', { name: 'J’ai un code', exact: true }).click();
  const input = page.getByRole('textbox', { name: 'Code ou lien reçu' });
  await input.waitFor();
  return { page, input, firstSession, firstMe, nextMe, code, submissions: () => submissions, reads: () => reads };
}
async function remember(page: Page) {
  await page.evaluate(() => {
    const input = document.querySelector<HTMLInputElement>('input[name="code"]')!;
    input.focus(); input.setSelectionRange(2, 5, 'backward');
    (window as unknown as { originalCode: HTMLInputElement }).originalCode = input;
  });
}
async function continuity(page: Page, name: string) {
  const state = await page.evaluate(() => {
    const original = (window as unknown as { originalCode: HTMLInputElement }).originalCode;
    const current = document.querySelector<HTMLInputElement>('input[name="code"]');
    return { same: original === current, focused: document.activeElement === original, value: current?.value,
      selection: [current?.selectionStart, current?.selectionEnd, current?.selectionDirection] };
  });
  await page.screenshot({ path: `${output}/${label}-${name}.png`, fullPage: true, animations: 'disabled' });
  assert.deepEqual(state, { same: true, focused: true, value: 'ABXYCDEFGH', selection: [2, 5, 'backward'] }, name);
  checks.push(name);
}
async function typeInMiddle(page: Page) {
  const input = page.getByRole('textbox', { name: 'Code ou lien reçu' });
  await input.fill('ABCDEFGH');
  await input.evaluate((element: HTMLInputElement) => element.setSelectionRange(2, 2));
  await page.keyboard.insertText('XY');
  await remember(page);
}
try {
  const known = await fixture();
  await typeInMiddle(known.page);
  // The first real network response remains pending for 15 seconds; typing is already usable.
  await known.page.waitForTimeout(15_000);
  await known.page.screenshot({ path: `${output}/${label}-waiting.png`, fullPage: true, animations: 'disabled' });
  known.firstMe.release();
  await known.page.locator('main[aria-busy="false"]').waitFor();
  await continuity(known.page, 'known-session-me-arrives');
  await known.page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await known.page.getByRole('textbox', { name: 'Code ou lien reçu' }).focus();
  await remember(known.page);
  const refreshed = known.page.waitForResponse('**/app/bff/me');
  known.nextMe.release(); await refreshed;
  await known.page.getByRole('button', { name: 'Actualiser', exact: true }).waitFor();
  await known.page.waitForFunction(() => !document.querySelector('.entry-busy')?.textContent);
  await continuity(known.page, 'refresh');
  await known.page.keyboard.press('Tab');
  assert.notEqual(await known.page.locator('input[name="code"]').evaluate(el => el === document.activeElement), true);
  await known.page.keyboard.press('Shift+Tab');
  assert.equal(await known.input.evaluate(el => el === document.activeElement), true);
  checks.push('Tab/Shift-Tab');

  const unknown = await fixture({ unknown: true });
  await typeInMiddle(unknown.page); unknown.firstSession.release();
  await unknown.page.getByRole('heading', { name: 'Vos écoles', exact: true, level: 1 }).waitFor();
  await continuity(unknown.page, 'session-becomes-known');
  unknown.firstMe.release(); await unknown.page.locator('main[aria-busy="false"]').waitFor();
  await continuity(unknown.page, 'unknown-session-me-arrives');

  const submitting = await fixture();
  await submitting.input.fill('ABCDEFGH');
  await submitting.page.getByRole('button', { name: 'Continuer', exact: true }).click();
  await submitting.page.getByRole('button', { name: 'Vérification…', exact: true }).waitFor();
  const handle = await submitting.input.elementHandle();
  submitting.firstMe.release(); await submitting.page.locator('main[aria-busy="false"]').waitFor();
  assert.equal(await handle!.evaluate(el => el.isConnected), true, 'in-flight form is retained');
  assert.equal(await submitting.input.getAttribute('readonly'), '');
  assert.equal(submitting.submissions(), 1);
  submitting.code.release(); await submitting.page.getByRole('button', { name: 'Continuer', exact: true }).waitFor();
  assert.equal(submitting.submissions(), 1); checks.push('one in-flight submission, refusal returns to same form');

  const failure = await fixture({ failMe: true });
  await typeInMiddle(failure.page); failure.firstMe.release();
  await failure.page.getByRole('button', { name: 'Réessayer', exact: true }).waitFor();
  await continuity(failure.page, 'me-error');
  await failure.page.getByRole('button', { name: 'Réessayer', exact: true }).click();
  await failure.input.focus(); await remember(failure.page);
  const recovered = failure.page.waitForResponse('**/app/bff/me');
  failure.nextMe.release(); await recovered;
  await failure.page.waitForFunction(() => !document.querySelector('.entry-busy')?.textContent);
  await continuity(failure.page, 'me-recovered');

  const other = await fixture();
  const appearance = other.page.getByRole('button', { name: 'Choisir l’apparence' });
  await appearance.focus(); other.firstMe.release();
  await other.page.locator('main[aria-busy="false"]').waitFor();
  assert.equal(await appearance.evaluate(el => el === document.activeElement), true); checks.push('response does not steal another action focus');
  await other.page.getByRole('button', { name: 'Annuler', exact: true }).click();
  await other.page.getByText('Votre école n’apparaît pas encore', { exact: true }).waitFor(); checks.push('empty schools');

  const waiting = await fixture();
  const failed = await fixture({ failMe: true }); failed.firstMe.release();
  await failed.page.getByRole('button', { name: 'Réessayer', exact: true }).waitFor();
  for (const width of [320, 390, 1440]) for (const theme of ['light', 'dark'] as const) {
    for (const [state, page] of [['success', known.page], ['error', failed.page], ['empty', other.page], ['waiting', waiting.page]] as const) {
      await page.setViewportSize({ width, height: 900 }); await page.emulateMedia({ colorScheme: theme });
      await page.waitForFunction(theme => document.documentElement.dataset.theme === theme, theme);
      await page.mouse.move(0, 0);
      // Let finite theme transitions settle before judging their colors.
      await page.evaluate(() => Promise.all(document.getAnimations().filter(animation => animation.effect?.getComputedTiming().iterations !== Infinity).map(animation => animation.finished.catch(() => {}))));
      await page.screenshot({ path: `${output}/${state}-${width}-${theme}.png`, fullPage: true, animations: 'disabled' });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `overflow ${state}/${width}/${theme}`);
    }
  }
  // CSS zoom exercises layout at 200%; this is not Safari nor physical mobile keyboard qualification.
  await known.page.setViewportSize({ width: 1440, height: 1000 });
  await known.page.evaluate(() => { document.documentElement.style.zoom = '2'; });
  assert.equal(await known.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, '200% reflow');
  await known.page.screenshot({ path: `${output}/zoom-200.png`, fullPage: true, animations: 'disabled' });
  checks.push('24 viewport/theme/state captures and 200% CSS zoom without overflow');
} catch (error) {
  await writeFile(`${output}/${label}-results.json`, JSON.stringify({ checks, passed: false, error: String(error) }, null, 2));
  throw error;
} finally { await browser.close(); await app.close(); }
await writeFile(`${output}/${label}-results.json`, JSON.stringify({ checks, passed: true, browser: 'Edge headless', productionBuild: true }, null, 2));
console.log(`PASS ${checks.length} checks; synthetic UI only`);
