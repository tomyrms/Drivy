/** W29: brief local comparison of synthetic fixtures, not production Web Vitals or acceptance tests. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const { chromium } = await import(process.env.DRIVY_PLAYWRIGHT_MODULE ?? '../../infra/dev/node_modules/playwright-core/index.mjs');
const targets = [
  { name: 'before', origin: process.env.DRIVY_PERF_BEFORE ?? 'http://127.0.0.1:5186', revision: process.env.DRIVY_PERF_BEFORE_REVISION ?? null },
  { name: 'after', origin: process.env.DRIVY_PERF_AFTER ?? 'http://127.0.0.1:5187', revision: process.env.DRIVY_PERF_AFTER_REVISION ?? null },
];
for (const target of targets) assert(['localhost', '127.0.0.1'].includes(new URL(target.origin).hostname), 'Loopback synthetic fixtures only');
const directory = resolve(process.env.DRIVY_PERF_DIRECTORY ?? 'docs/implementation/proofs/epic-280');
const passes = Math.min(3, Math.max(1, Number(process.env.DRIVY_PERF_PASSES ?? 3)));
const widths = [1440, 390];
const parameters = 'page=agenda&agenda=mixed&shell=1';
const channel = process.env.DRIVY_BROWSER_CHANNEL ?? 'msedge';
await mkdir(directory, { recursive: true });
for (const target of targets) {
  const response = await fetch(`${target.origin}/app/test/visual.html`);
  assert(response.ok, `${target.name}: fixture HTML unavailable`);
  target.html = await response.text();
  const fixture = await (await fetch(`${target.origin}/app/test/visual.tsx`)).text();
  assert(fixture.includes('__reviewBoot'), `${target.name}: review boot hook missing`);
  assert(/setTimeout\(resolve,[\s\S]{0,100}\b120\)/.test(fixture), `${target.name}: expected 120ms fixture latency not found`);
}

function instrument() {
  const measurement = { phases: {}, shifts: [], paints: [], errors: [] };
  window.__perf280 = measurement;
  const visible = node => !!node?.getClientRects().length && !node.closest('[hidden], [inert]');
  const loaded = () => !document.querySelector('main[aria-busy="true"]')
    && ![...document.querySelectorAll('main .loading, main .skeleton, main .row-skeleton')].some(visible);
  const rows = () => [...document.querySelectorAll('main table tbody tr')].filter(visible);
  const ready = kind => kind === 'agenda'
    ? loaded() && [...document.querySelectorAll('main .agenda-lesson')].some(visible)
    : kind === 'learners' ? /\/eleves$/.test(location.pathname) && loaded() && rows().length === 2
      : rows().length === 1 && rows()[0].textContent.includes('Éloïse Müller');
  function measure(name, kind, startedAt) {
    let completed = false, scheduled = false;
    const observer = new MutationObserver(check);
    const timer = setTimeout(() => { observer.disconnect(); measurement.errors.push(`${name}: useful render timeout`); }, 15000);
    function check() {
      if (completed || scheduled || !ready(kind)) return;
      scheduled = true;
      requestAnimationFrame(() => requestAnimationFrame(() => {
        scheduled = false;
        if (completed || !ready(kind)) return;
        completed = true; observer.disconnect(); clearTimeout(timer);
        const completedAt = performance.now();
        measurement.phases[name] = { startedAt, completedAt, durationMs: completedAt - startedAt };
      }));
    }
    observer.observe(document, { childList: true, subtree: true, attributes: true });
    check();
  }
  try {
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) measurement.shifts.push({ startTime: entry.startTime, value: entry.value, hadRecentInput: entry.hadRecentInput });
    }).observe({ type: 'layout-shift', buffered: true });
    new PerformanceObserver(list => {
      for (const entry of list.getEntries()) measurement.paints.push({ name: entry.name, startTime: entry.startTime });
    }).observe({ type: 'paint', buffered: true });
  } catch (error) { measurement.errors.push(error.message); }
  document.addEventListener('click', event => {
    if (event.target.closest?.('.console-nav a[href*="/eleves"]') && !measurement.phases.navigation) measure('navigation', 'learners', performance.now());
  }, true);
  document.addEventListener('input', event => {
    if (/\/eleves$/.test(location.pathname) && event.target.value === 'Éloïse' && !measurement.phases.search) measure('search', 'search', performance.now());
  }, true);
  measure('initial', 'agenda', 0);
}

function cls(shifts, end = Infinity) {
  let maximum = 0, score = 0, first = 0, previous = 0;
  for (const shift of shifts.filter(item => !item.hadRecentInput && item.startTime <= end)) {
    if (shift.startTime - previous > 1000 || shift.startTime - first > 5000) { first = shift.startTime; score = 0; }
    score += shift.value; maximum = Math.max(maximum, score); previous = shift.startTime;
  }
  return maximum;
}
const browser = await chromium.launch({ channel, headless: true });
const results = [];
try {
  for (let pass = 1; pass <= passes; pass++) for (const width of widths) {
    const order = pass % 2 ? targets : [...targets].reverse();
    for (const target of order) {
      const context = await browser.newContext({ viewport: { width, height: 900 }, locale: 'fr-CH', timezoneId: 'Europe/Zurich', colorScheme: 'light', reducedMotion: 'reduce' });
      await context.addInitScript(instrument);
      await context.route('**/*', route => {
        const request = route.request();
        if (new URL(request.url()).origin !== target.origin) return route.abort();
        if (request.isNavigationRequest()) return route.fulfill({ contentType: 'text/html', body: target.html.replace('<head>', `<head><script>window.__reviewBoot=${JSON.stringify({ parameters })}</script>`) });
        return route.continue();
      });
      const page = await context.newPage(); page.setDefaultTimeout(15000);
      const errors = []; page.on('pageerror', error => errors.push(error.message));
      const result = { version: target.name, origin: target.origin, pass, width, height: 900, errors };
      try {
        await page.goto(`${target.origin}/app/test/visual.html?${parameters}`);
        await page.waitForFunction(() => !!window.__perf280.phases.initial);
        await page.evaluate(() => document.fonts.ready);
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        const initial = await page.evaluate(() => {
          const first = [...document.querySelectorAll('main .agenda-lesson')].find(node => node.getClientRects().length);
          const rect = first?.getBoundingClientRect();
          const snapshot = window.__reviewSnapshot?.();
          return {
            initialEnd: performance.now(),
            firstLesson: rect ? { top: rect.top, bottom: rect.bottom, intersectsViewport: rect.bottom > 0 && rect.top < innerHeight } : null,
            fixture: snapshot ? { learners: snapshot.db.learners, lessons: snapshot.db.lessons, courses: snapshot.db['course-series'] ?? null } : null,
          };
        });
        result.fixtureSha256 = createHash('sha256').update(JSON.stringify(initial.fixture)).digest('hex');
        result.firstLesson = initial.firstLesson;
        const menu = page.getByRole('button', { name: 'Menu', exact: true });
        if (await menu.isVisible()) await menu.click();
        await page.locator('.console-nav a').filter({ hasText: /^Élèves$/ }).first().click();
        await page.waitForFunction(() => !!window.__perf280.phases.navigation);
        await page.getByRole('searchbox', { name: 'Rechercher un élève', exact: true }).fill('Éloïse');
        await page.waitForFunction(() => !!window.__perf280.phases.search);
        const measured = await page.evaluate(() => window.__perf280);
        result.phases = measured.phases;
        result.firstContentfulPaintMs = measured.paints.find(paint => paint.name === 'first-contentful-paint')?.startTime ?? null;
        result.initialCls = cls(measured.shifts, initial.initialEnd);
        result.journeyCls = cls(measured.shifts);
        result.layoutShifts = measured.shifts;
        errors.push(...measured.errors);
        result.completed = true;
      } catch (error) { result.completed = false; result.error = error.message; }
      finally { await context.close(); }
      results.push(result);
      console.log(JSON.stringify({ version: result.version, pass, width, completed: result.completed, phases: result.phases, initialCls: result.initialCls, error: result.error }));
    }
  }
} finally { await browser.close(); }
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const summary = widths.flatMap(width => targets.map(target => {
  const matching = results.filter(result => result.width === width && result.version === target.name && result.completed);
  return { version: target.name, width, count: matching.length,
    initialMedianMs: median(matching.map(result => result.phases.initial.durationMs)),
    navigationMedianMs: median(matching.map(result => result.phases.navigation.durationMs)),
    searchMedianMs: median(matching.map(result => result.phases.search.durationMs)),
    initialClsMedian: median(matching.map(result => result.initialCls)),
    journeyClsMedian: median(matching.map(result => result.journeyCls)),
  };
}));
const report = {
  kind: 'W29 brief local synthetic comparison; development modules and emulated viewport; not production or physical mobile qualification',
  recordedAt: new Date().toISOString(), browser: browser.version(), channel, headless: true,
  provenance: targets.map(({ name, origin, revision }) => ({ name, origin, revision })),
  environment: { platform: process.platform, node: process.version, fixtureLatencyMs: 120, assetLatency: 'loopback, unthrottled', cpu: 'unthrottled', freshBrowserContextEachPass: true, reducedMotion: 'reduce', locale: 'fr-CH', timezone: 'Europe/Zurich', theme: 'light', parameters, passes, alternatingOrder: true },
  definitions: { initial: 'Navigation start to loaded agenda item, with visible main loading indicators absent, then two animation frames.', navigation: 'Captured click on Élèves navigation link to two loaded learner rows, then two animation frames; opening mobile menu excluded.', search: 'Captured input event for complete term Éloïse to exactly one matching learner row, then two animation frames; automated typing duration excluded.', cls: 'Maximum layout-shift session window, 1s gap / 5s span, excluding hadRecentInput; initial ends after useful agenda + font readiness + two frames; journey ends after search.' },
  summary, results,
};
await writeFile(resolve(directory, 'performance-comparison.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ summary, distinctFixtureHashes: [...new Set(results.filter(result => result.fixtureSha256).map(result => result.fixtureSha256))] }));
if (results.some(result => !result.completed || result.errors.length)) process.exitCode = 1;
