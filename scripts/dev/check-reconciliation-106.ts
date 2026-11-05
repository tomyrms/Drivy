import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

const output = resolve('artifacts/reconciliation-restes-106');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/reconciliation-106-fixture.tsx"></script></html>');
const server = await createServer({ configFile: false, root: resolve('.'), plugins: [react(), tailwind()],
  resolve: { alias: { '@': resolve('apps/web/client'), react: resolve('apps/web/node_modules/react'), 'react-dom': resolve('apps/web/node_modules/react-dom') } },
  server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' });
await server.listen();
const address = server.httpServer!.address();
assert(address && typeof address !== 'string');
const origin = `http://127.0.0.1:${address.port}`;
const browser = await chromium.launch({ headless: true, args: ['--disable-gpu'] });
const checks: string[] = [];
const results: Record<string, unknown> = {};

async function pageFor(mode: string): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/reconciliation-restes-106/index.html?mode=${mode}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}

try {
  const setup = await pageFor('setup');
  await setup.locator('input[name="identity.name"]').waitFor({ timeout: 15000 });
  await setup.locator('input[name="identity.name"]').fill('  École Espace  ');
  await setup.evaluate(() => (window as any).fixture.hold());
  await setup.evaluate(() => (window as any).fixture.saveSameStep());
  await setup.waitForFunction(() => (window as any).fixture.waiting(), undefined, { timeout: 10000 });
  await setup.locator('input[name="identity.contactEmail"]').fill('local@example.invalid');
  // Laisse le rendu et l'effet track suivre la saisie avant la réponse différée.
  await setup.evaluate(() => new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
  await setup.evaluate(() => (window as any).fixture.release());
  await setup.waitForFunction(() => document.querySelector<HTMLInputElement>('input[name="identity.name"]')?.value === 'École Espace', undefined, { timeout: 10000 });
  assert.equal(await setup.locator('input[name="identity.contactEmail"]').inputValue(), 'local@example.invalid');
  const first = await setup.evaluate(() => (window as any).fixture.writes());
  assert.equal(first.length, 1);
  assert.equal(first[0].content.identity.name, '  École Espace  ');
  assert.equal(first[0].content.identity.contactEmail, '');

  await setup.evaluate(() => (window as any).fixture.saveSameStep());
  await setup.waitForFunction(() => (window as any).fixture.writes().length === 2, undefined, { timeout: 10000 });
  const second = await setup.evaluate(() => (window as any).fixture.writes());
  assert.equal(second[1].content.identity.name, 'École Espace');
  assert.equal(second[1].content.identity.contactEmail, 'local@example.invalid');

  await setup.locator('input[name="identity.contactEmail"]').fill('troisieme@example.invalid');
  await setup.evaluate(() => (window as any).fixture.saveSameStep());
  await setup.waitForFunction(() => (window as any).fixture.writes().length === 3, undefined, { timeout: 10000 });
  const third = await setup.evaluate(() => (window as any).fixture.writes());
  assert.equal(third[2].content.identity.name, 'École Espace');
  assert.equal(third[2].content.identity.contactEmail, 'troisieme@example.invalid');
  assert.equal(await setup.locator('input[name="identity.name"]').inputValue(), 'École Espace');
  results.setup = { writes: third.length, first, second, third };
  checks.push('C1: normalisation serveur visible, saisie track conservée, deuxième et troisième corps fusionnés');
  await setup.close();

  const conflict = await pageFor('setup');
  await conflict.locator('input[name="identity.name"]').waitFor({ timeout: 15000 });
  await conflict.locator('input[name="identity.name"]').fill('Envoyé');
  await conflict.evaluate(() => {
    (window as any).fixture.conflictResponse();
    (window as any).fixture.failRead();
    (window as any).fixture.hold();
    (window as any).fixture.saveSameStep();
  });
  await conflict.waitForFunction(() => (window as any).fixture.waiting(), undefined, { timeout: 10000 });
  await conflict.locator('input[name="identity.name"]').fill('Local');
  await conflict.evaluate(() => (window as any).fixture.saveSameStep());
  await conflict.evaluate(() => (window as any).fixture.release());
  await conflict.waitForFunction(() => (window as any).fixture.phase() === 'conflict', undefined, { timeout: 10000 });
  await conflict.waitForFunction(() => (window as any).fixture.failedReads() > 0, undefined, { timeout: 10000 });
  const durableConflict = await conflict.evaluate(() => ({
    writes: (window as any).fixture.writes().length,
    document: (window as any).fixture.document(),
    content: (window as any).fixture.content(),
    phase: (window as any).fixture.phase(),
  }));
  assert.equal(durableConflict.writes, 1);
  assert.equal(durableConflict.document.version, 2);
  assert.equal(durableConflict.document.content.identity.name, 'Serveur Normalisé');
  assert.equal(durableConflict.content.identity.name, 'Local');
  assert.equal(durableConflict.phase, 'conflict');

  const readsBefore = await conflict.evaluate(() => (window as any).fixture.draftReads());
  await conflict.evaluate(() => { (window as any).fixture.retryRead(); (window as any).fixture.reload(); });
  await conflict.waitForFunction((before: number) => (window as any).fixture.draftReads() > before, readsBefore, { timeout: 5000 });
  await conflict.waitForFunction(() => (window as any).fixture.phase() === 'conflict', undefined, { timeout: 5000 });
  const afterRead = await conflict.evaluate(() => ({
    document: (window as any).fixture.document(),
    content: (window as any).fixture.content(),
    phase: (window as any).fixture.phase(),
  }));
  assert.equal(afterRead.document.version, 2);
  assert.equal(afterRead.content.identity.name, 'Local');
  results.conflict = { durableConflict, afterRead };
  checks.push('C2: première confirmation durable transmise, GET en échec sans perte, relecture explicite sans écraser le local');
  await conflict.close();

  const trackConflict = await pageFor('setup');
  await trackConflict.locator('input[name="identity.name"]').waitFor({ timeout: 15000 });
  await trackConflict.locator('input[name="identity.name"]').fill('Avant');
  await trackConflict.evaluate(() => { (window as any).fixture.conflictResponse(); (window as any).fixture.hold(); (window as any).fixture.saveSameStep(); });
  await trackConflict.waitForFunction(() => (window as any).fixture.waiting(), undefined, { timeout: 10000 });
  await trackConflict.locator('input[name="identity.name"]').fill('Local');
  await trackConflict.evaluate(() => new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
  await trackConflict.evaluate(() => (window as any).fixture.release());
  await trackConflict.waitForFunction(() => (window as any).fixture.phase() === 'conflict', undefined, { timeout: 10000 });
  const trackOnly = await trackConflict.evaluate(() => ({
    writes: (window as any).fixture.writes().length,
    document: (window as any).fixture.document(),
    content: (window as any).fixture.content(),
    phase: (window as any).fixture.phase(),
    conflicts: (window as any).fixture.saveConflicts(),
  }));
  assert.equal(trackOnly.writes, 1);
  assert.equal(trackOnly.document.content.identity.name, 'Serveur Normalisé');
  assert.equal(trackOnly.content.identity.name, 'Local');
  assert.equal(trackOnly.phase, 'conflict');
  assert.deepEqual(trackOnly.conflicts, ['content.identity.name']);
  results.trackOnly = trackOnly;
  checks.push('R1: conflit d’une saisie track sans second enqueue signalé par l’état existant, local et confirmation conservés');
  await trackConflict.close();

  const draft = await pageFor('draft');
  await draft.locator('#batch-conflict').click();
  await draft.waitForFunction(() => (window as any).fixture.state().conflicts.includes('email'), undefined, { timeout: 5000 });
  await draft.waitForFunction(() => (window as any).fixture.state().guards === 1, undefined, { timeout: 5000 });
  const conflicted = await draft.evaluate(() => (window as any).fixture.state());
  assert.equal(conflicted.draft.email, 'local@example.invalid');
  assert.equal(conflicted.edited, true);
  assert.equal(conflicted.guards, 1);
  await draft.locator('#refresh').click();
  await draft.evaluate(() => new Promise<void>(done => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
  await draft.waitForFunction(() => (window as any).fixture.state().guards === 1, undefined, { timeout: 5000 });
  const refreshed = await draft.evaluate(() => (window as any).fixture.state());
  assert.equal(refreshed.draft.email, 'local@example.invalid');
  assert.deepEqual(refreshed.conflicts, ['email']);
  assert.equal(refreshed.guards, 1);
  await draft.locator('#resolve').click();
  await draft.waitForFunction(() => (window as any).fixture.state().conflicts.length === 0, undefined, { timeout: 5000 });
  await draft.waitForFunction(() => (window as any).fixture.state().guards === 0, undefined, { timeout: 5000 });
  const resolved = await draft.evaluate(() => (window as any).fixture.state());
  assert.equal(resolved.edited, false);
  assert.equal(resolved.guards, 0);
  await draft.locator('#edit-email').click();
  await draft.waitForFunction(() => (window as any).fixture.state().draft.email === 'autre@example.invalid', undefined, { timeout: 5000 });
  const afterResolutionEdit = await draft.evaluate(() => (window as any).fixture.state());
  assert.deepEqual(afterResolutionEdit.conflicts, []);
  results.draft = { conflicted, refreshed, resolved, afterResolutionEdit };
  checks.push('C3/R2: conflit atomique avec la valeur, survit au refresh, résolution puis édition sans résurrection');
  await draft.close();

  const adoption = await pageFor('draft');
  await adoption.locator('#adopt-edit').click();
  await adoption.waitForFunction(() => (window as any).fixture.state().draft.name === 'Ecole', undefined, { timeout: 5000 });
  const adopted = await adoption.evaluate(() => (window as any).fixture.state());
  assert.deepEqual(adopted.conflicts, []);
  await adoption.locator('#refresh').click();
  await adoption.locator('#edit-name').click();
  await adoption.waitForFunction(() => (window as any).fixture.state().draft.name === 'Autre école', undefined, { timeout: 5000 });
  const afterAdoptionEdit = await adoption.evaluate(() => (window as any).fixture.state());
  assert.deepEqual(afterAdoptionEdit.conflicts, []);
  results.adoption = { adopted, afterAdoptionEdit };
  checks.push('R2: adoption normale puis édition et refresh ne fabriquent aucun conflit');
  await adoption.close();

  await writeFile(`${output}/results.json`, JSON.stringify({ synthetic: true, engine: { name: 'Chromium', version: browser.version() }, checks, results }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks, results }, null, 2));
} finally {
  await browser.close();
  await server.close();
}
