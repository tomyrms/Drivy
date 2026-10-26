/** Browser evidence for #119. Loopback only; four boolean preferences and synthetic account identifiers. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../infra/dev/node_modules/playwright-core/index.mjs';

const origin = process.env.DRIVY_REVIEW_ORIGIN ?? 'http://127.0.0.1:5194';
assert(['localhost', '127.0.0.1'].includes(new URL(origin).hostname));
const directory = resolve('docs/implementation/proofs/reactivite-web-20261026');
await mkdir(directory, { recursive: true });
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const results = [];
try {
  for (const colorScheme of ['light', 'dark']) for (const width of [1440, 390]) {
    const context = await browser.newContext({ viewport: { width, height: 1000 }, colorScheme, locale: 'fr-CH' });
    let preferences = { version: 1, courseOffers: true, courseReminders: true, courseChanges: true, courseStaffAlerts: true };
    let hold = false, release, loseResponse = false, puts = 0;
    const headers = { 'content-type': 'application/json' };
    await context.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (url.origin !== origin) return route.abort();
      if (!url.pathname.startsWith('/app/bff/')) return route.continue();
      let body;
      if (url.pathname.endsWith('/session')) body = { authenticated: true, csrfToken: 'synthetic-only', invitationPending: false };
      else if (url.pathname.endsWith('/me')) body = { data: { personId: '00000000-0000-4000-8000-000000000001', displayName: 'Compte synthétique', version: 1, memberships: [] } };
      else if (url.pathname.endsWith('/notification-preferences')) {
        if (request.method() === 'PUT') {
          puts++;
          const expected = Number(request.headers()['if-match'].replaceAll('"', ''));
          if (hold) { hold = false; await new Promise(done => { release = done; }); }
          if (expected !== preferences.version) return route.fulfill({ status: 412, headers, body: JSON.stringify({ code: 'VERSION_CONFLICT' }) });
          preferences = { ...request.postDataJSON(), version: preferences.version + 1 };
          if (loseResponse) { loseResponse = false; return route.fulfill({ status: 503, headers, body: JSON.stringify({ code: 'API_UNAVAILABLE' }) }); }
        }
        body = { data: preferences };
      } else return route.fulfill({ status: 404, headers, body: '{}' });
      return route.fulfill({ status: 200, headers, body: JSON.stringify(body) });
    });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${origin}/app/preferences`);
    const offers = page.getByRole('checkbox', { name: /Places et nouvelles sessions/ });
    const reminders = page.getByRole('checkbox', { name: /Rappels de cours/ });
    await offers.waitFor();
    hold = true;
    await offers.uncheck();
    await page.waitForFunction(() => document.querySelector('input[type="checkbox"]')?.checked === false);
    await reminders.uncheck(); await offers.check();
    assert.equal(await reminders.isEnabled(), true);
    assert.equal(await reminders.isChecked(), false);
    assert.equal(await offers.isChecked(), true);
    // The first PUT is still held: the local changes above are independent of its response.
    while (!release) await page.waitForTimeout(10);
    assert.equal(puts, 1); release();
    await page.getByRole('status').filter({ hasText: 'Préférences synchronisées.' }).waitFor();
    assert.equal(preferences.courseOffers, true); assert.equal(preferences.courseReminders, false); assert.equal(puts, 2);
    await page.screenshot({ path: resolve(directory, `preferences-${width}-${colorScheme}.png`), fullPage: true });
    loseResponse = true;
    await page.getByRole('checkbox', { name: /Changements de cours/ }).uncheck();
    await page.getByRole('alert').filter({ hasText: 'Modification non confirmée' }).waitFor();
    const beforeVerify = puts;
    await page.getByRole('button', { name: 'Vérifier', exact: true }).click();
    await page.getByRole('status').filter({ hasText: 'Préférences synchronisées.' }).waitFor();
    assert.equal(puts, beforeVerify); assert.equal(preferences.courseChanges, false);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    assert.deepEqual(errors, []);
    results.push({ width, colorScheme, immediateChoices: true, latestChoicePreserved: true, lostResponseVerifiedWithoutReplay: true, horizontalOverflow: false });
    await context.close();
  }
  await writeFile(resolve(directory, 'browser-results.json'), JSON.stringify({ synthetic: true, checks: results }, null, 2));
  process.stdout.write(JSON.stringify({ checks: results.length, failed: 0 }) + '\n');
} finally { await browser.close(); }
