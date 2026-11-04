import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Dedicated fixture imports the production component, context, store and CSS. No product test hook.
const output = resolve('artifacts/pending-recovery-106');
const mode = process.argv[2] ?? 'all';
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="./fixture.tsx"></script></html>');
await writeFile(`${output}/fixture.tsx`, `
import React from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import { ConsoleContext } from '/apps/web/client/console/context';
import { PortalPendingRequests } from '/apps/web/client/portal/runtime/pending-requests';
import { commandStore } from '/apps/web/client/command-store';
import { createCommand } from '/apps/web/client/command-core';
import '/apps/web/client/portal/portal.css';
const schoolId = '10000000-0000-4000-8000-000000000001';
const otherSchool = '10000000-0000-4000-8000-000000000002';
let school = schoolId, now = Date.parse('2030-01-01T10:00:00Z'), releaseCsrf, csrfStarted = false;
Date.now = () => now;
let posts = 0, reads = 0, receipt = false, missing = false, command;
window.fetch = async (url, init) => {
  if (init?.method === 'POST') posts++; else reads++;
  const data = receipt ? { requestId: '10000000-0000-4000-8000-000000000004', serverTime: '2030-01-01T10:02:00Z', data: { operationId: command.operationId, commandType: 'CREATE_LESSON', resourceType: 'Lesson', resourceId: '10000000-0000-4000-8000-000000000003', resourceVersion: 1, committedAt: '2030-01-01T10:01:00Z' } } : { code: 'API_UNAVAILABLE' };
  const response = new Response(JSON.stringify(data), { status: receipt ? 200 : missing ? 404 : 503, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: String(url) });
  return response;
};
const root = createRoot(document.getElementById('root'));
function render() { flushSync(() => root.render(<ConsoleContext.Provider value={{ schoolId: school, csrf: () => 'synthetic', refreshCsrf: () => { csrfStarted = true; return new Promise(done => releaseCsrf = done); }, reloadSchool: async () => {}, login: () => {} } as any}><main className="p-4 max-w-3xl mx-auto"><div className="mb-4"><button id="independent">Action indépendante</button></div><PortalPendingRequests /></main></ConsoleContext.Provider>)); }
window.fixture = {
  render,
  submit: async () => { command = createCommand({ schoolId: school, kind: 'createLesson', path: 'lessons', resourceVersion: 0, body: { plannedStart: '2030-01-01T10:01:00Z', meetingPoint: 'Lieu synthétique' } }); await commandStore.submit(command, 'synthetic'); },
  expire: () => { now += 120000; },
  finishCsrf: () => releaseCsrf('synthetic'),
  confirm: () => { receipt = true; },
  missing: () => { missing = true; },
  resetClock: () => { now = Date.parse('2030-01-01T10:00:00Z'); receipt = false; missing = false; csrfStarted = false; },
  restore: () => commandStore.submit(command, 'synthetic'),
  clear: () => commandStore.clear(),
  school: () => { school = school === schoolId ? otherSchool : schoolId; commandStore.scopeToAccess(school, 'synthetic-member', 1); render(); },
  state: () => ({ posts, reads, csrfStarted, operationId: command?.operationId, entries: [...commandStore.getSnapshot().entries.values()], metadata: commandStore.getSnapshot().metadata }),
};
render();
`);
const server = await createServer({ configFile: false, root: resolve('.'), plugins: [react(), tailwind()],
  resolve: { alias: { '@': resolve('apps/web/client'), react: resolve('apps/web/node_modules/react'), 'react-dom': resolve('apps/web/node_modules/react-dom') } },
  server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' });
await server.listen();
const address = server.httpServer!.address();
assert(address && typeof address !== 'string');
const origin = `http://127.0.0.1:${address.port}`;
const browser = await chromium.launch({ headless: true, args: ['--disable-gpu'] });
const engine = { name: 'Chromium', version: browser.version() };
const checks: string[] = [];
async function fixture(failure = '') {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.addInitScript((initial) => {
    const state = window as any;
    state.storageFailure = initial;
    for (const [method, kind] of [['getItem', 'read'], ['setItem', 'write'], ['removeItem', 'clear']] as const) {
      const original = (Storage.prototype as any)[method];
      (Storage.prototype as any)[method] = function (...args: unknown[]) {
        if (state.storageFailure === kind) throw new Error('Synthetic storage refusal');
        return original.apply(this, args);
      };
    }
  }, failure);
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/pending-recovery-106/index.html`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}
async function action(page: Page, name: string) { await page.evaluate(name => (window as any).fixture[name](), name); }
async function state(page: Page) { return page.evaluate(() => (window as any).fixture.state()); }
async function text(page: Page) { return page.locator('main').innerText(); }
async function capture(page: Page, name: string) {
  await page.evaluate(async () => {
    await document.fonts.ready;
    // Keyboard focus may have scrolled the page; capture from a stable origin without moving focus.
    window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
    await new Promise<void>(done => requestAnimationFrame(() => done()));
    await Promise.all(document.getAnimations().filter(animation =>
      animation.effect?.getComputedTiming().iterations !== Infinity).map(animation => animation.finished.catch(() => {})));
    await new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done())));
  });
  const separation = await page.evaluate(() => {
    const control = document.querySelector('#independent')!.getBoundingClientRect();
    const notice = document.querySelector('[data-slot=alert]')!.getBoundingClientRect();
    return notice.top - control.bottom;
  });
  assert(separation >= 4, `fixture control and focus ring need their own space: ${separation}`);
  await page.screenshot({ path: `${output}/correction-2-chromium-${name}.png`, fullPage: true });
}
try {
  if (mode !== 'race') {
    for (const [failure, expected] of [['read', /suivi précédent.*pu être relu/i], ['write', /suivi local.*pu être enregistré|suivi local.*pu être mis à jour/i], ['clear', /suivi local.*pu être effacé/i]] as const) {
      const page = await fixture(failure);
      if (failure !== 'read') await action(page, 'submit');
      if (failure === 'clear') await action(page, 'clear');
      await page.getByText(expected).waitFor({ timeout: 5000 });
      assert.match(await text(page), /vérifi/i);
      await page.locator('#independent').focus();
      await action(page, 'render');
      assert.equal(await page.locator('#independent').evaluate(el => el === document.activeElement), true);
      for (const width of [320, 390, 1440]) for (const theme of ['light', 'dark']) for (const zoom of [1, 2]) {
        await page.setViewportSize({ width, height: 900 });
        await page.evaluate(({ theme, zoom }) => { document.documentElement.dataset.theme = theme; document.body.style.zoom = String(zoom); }, { theme, zoom });
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'horizontal overflow');
        assert(await page.locator('[data-slot=alert]').evaluateAll(elements => elements.every(el => el.scrollWidth <= el.clientWidth + 1)), 'alert content fits');
        await capture(page, `${failure}-${width}-${theme}-${zoom}`);
      }
      await page.evaluate(() => { (window as any).storageFailure = ''; });
      await action(page, 'clear');
      assert.doesNotMatch(await text(page), expected);
      assert.equal(await page.locator('[data-slot=alert]').count(), 0, 'saved clear is silent');
      await page.close(); checks.push(failure);
    }
    const focused = await fixture();
    await focused.locator('#independent').focus();
    await focused.evaluate(() => { (window as any).storageFailure = 'write'; });
    await action(focused, 'submit');
    await focused.getByText(/suivi local.*pu être enregistré/i).waitFor();
    assert.equal(await focused.locator('#independent').evaluate(el => document.activeElement === el), true, 'arrival never steals focus');
    await focused.keyboard.press('Tab');
    assert.equal(await focused.getByRole('button', { name: 'Vérifier le résultat' }).evaluate(el => document.activeElement === el), true);
    await focused.keyboard.press('Tab');
    assert.equal(await focused.getByRole('button', { name: 'Renvoyer la même demande' }).evaluate(el => document.activeElement === el), true);
    await focused.keyboard.press('Shift+Tab');
    assert.equal(await focused.getByRole('button', { name: 'Vérifier le résultat' }).evaluate(el => document.activeElement === el), true);
    await capture(focused, 'keyboard-focus');
    await focused.evaluate(() => {
      (window as any).liveMutations = 0;
      const observer = new MutationObserver(records => { (window as any).liveMutations += records.length; });
      document.querySelectorAll('[role=status]').forEach(el => observer.observe(el, { childList: true, subtree: true, characterData: true }));
    });
    await action(focused, 'render'); await action(focused, 'render');
    assert.equal(await focused.evaluate(() => (window as any).liveMutations), 0, 'stable renders do not repeat live content');
    await action(focused, 'confirm');
    await focused.getByRole('button', { name: 'Vérifier le résultat' }).click();
    await focused.getByText('Le résultat de la demande est confirmé.', { exact: true }).waitFor();
    assert.equal((await state(focused)).entries.length, 0);
    assert.match(await text(focused), /suivi local.*pu être enregistré/i, 'failed removal write still visible without entries');
    await capture(focused, 'confirmed-storage-refused');
    await action(focused, 'school');
    assert.doesNotMatch(await text(focused), /résultat de la demande est confirmé/i, 'old school feedback hidden');
    await focused.close();
    const recovered = await fixture('write'); await action(recovered, 'submit');
    await recovered.evaluate(() => { (window as any).storageFailure = ''; });
    await recovered.getByRole('button', { name: 'Vérifier le résultat' }).click();
    await recovered.waitForFunction(() => (window as any).fixture.state().metadata.durability === 'saved');
    assert.doesNotMatch(await text(recovered), /suivi local.*pu être enregistré/i, 'real successful write clears notice');
    const entryMessage = (await state(recovered)).entries[0].message;
    assert.equal(await recovered.getByText(entryMessage, { exact: true }).count(), 1, 'pending already explained by entry is not duplicated');
    await recovered.close(); checks.push('focus arrival, Tab/Shift-Tab, stable live content, failed write after receipt, saved write');
    const page = await fixture();
    assert.equal(await page.locator('[data-slot=alert]').count(), 0, 'normal empty read is silent');
    await action(page, 'submit');
    await page.reload(); await page.waitForFunction(() => Boolean((window as any).fixture));
    assert.equal((await state(page)).entries[0].command, null);
    assert.equal(await page.getByRole('button', { name: 'Renvoyer la même demande' }).count(), 0);
    await page.getByRole('button', { name: 'Arrêter le suivi', exact: true }).click();
    await page.getByRole('dialog').waitFor();
    assert.match(await page.getByRole('dialog').innerText(), /n’annule pas/);
    await page.getByRole('button', { name: 'Continuer le suivi' }).click();
    await action(page, 'school');
    assert.equal(await page.getByRole('button', { name: 'Vérifier le résultat' }).count(), 0);
    await page.close(); checks.push('reload, stop warning, school, empty');
  }
  if (mode !== 'metadata') {
    const page = await fixture(); await action(page, 'submit');
    const before = await state(page);
    await page.getByRole('button', { name: 'Renvoyer la même demande' }).click();
    await page.waitForFunction(() => (window as any).fixture.state().csrfStarted);
    await action(page, 'expire'); // No store notification or React render between button and guarded call.
    await action(page, 'finishCsrf');
    await page.getByText('L’horaire demandé est passé : vérifiez le résultat ou arrêtez le suivi.', { exact: true }).waitFor({ timeout: 5000 });
    const after = await state(page);
    assert.equal(after.posts, before.posts, 'zero resend emission');
    assert.deepEqual(after.entries, before.entries, 'same operation and intention');
    assert.equal(await page.getByRole('button', { name: 'Vérifier le résultat' }).isEnabled(), true);
    assert.equal(await page.getByText('L’horaire demandé est passé : vérifiez le résultat ou arrêtez le suivi.', { exact: true }).count(), 1);
    await capture(page, 'expired');
    await action(page, 'confirm');
    await page.getByRole('button', { name: 'Vérifier le résultat' }).click();
    await page.getByText('Le résultat de la demande est confirmé.', { exact: true }).waitFor();
    assert.equal((await state(page)).entries.length, 0);
    assert.equal((await state(page)).posts, before.posts);
    assert.doesNotMatch(await text(page), /horaire demandé est passé/);
    await action(page, 'resetClock'); await action(page, 'submit');
    assert.doesNotMatch(await text(page), /horaire demandé est passé/, 'new request never inherits local feedback');
    await page.getByRole('button', { name: 'Vérifier le résultat' }).click();
    await page.getByText('Le résultat n’a pas pu être établi. La demande reste suivie : réessayez la vérification.', { exact: true }).waitFor();
    assert.doesNotMatch(await text(page), /L’école est momentanément inaccessible/, 'replacement shows only current message');
    await action(page, 'clear'); await action(page, 'render');
    assert.equal(await page.getByRole('region', { name: 'Demandes en cours' }).count(), 0);
    await action(page, 'restore');
    assert.doesNotMatch(await text(page), /Le résultat n’a pas pu être établi/, 'same operation restored has no old UI feedback');
    await action(page, 'missing');
    await page.getByRole('button', { name: 'Vérifier le résultat' }).click();
    await page.getByRole('button', { name: 'Arrêter le suivi', exact: true }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Arrêter le suivi', exact: true }).click();
    assert.equal((await state(page)).entries.length, 0);
    await action(page, 'resetClock'); await action(page, 'restore');
    assert.doesNotMatch(await text(page), /L’école ne retrouve pas/, 'released operation restored has no old UI feedback');
    await action(page, 'school'); await action(page, 'school');
    assert.doesNotMatch(await text(page), /Suivi arrêté|horaire demandé est passé/);
    await page.close(); checks.push('deadline race, unchanged intention, late receipt');
    checks.push('replacement, confirmation, clear, release, same operation restored, context switch without stale feedback');
  }
  await writeFile(`${output}/${mode}-results.json`, JSON.stringify({ synthetic: true, engine, cssZoom: true, checks }, null, 2));
  console.log(JSON.stringify({ engine, checks, result: 'PASS' }));
} finally { await browser.close(); await server.close(); }
