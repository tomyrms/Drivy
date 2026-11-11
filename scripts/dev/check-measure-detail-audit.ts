import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Contrôle navigateur synthétique de #432 (portée du détail F06) et #433 (corrections avec valeur nulle). Aucune donnée réelle.
const output = resolve('artifacts/measure-detail-audit');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/measure-detail-audit-fixture.tsx"></script></html>');
const server = await createServer({ configFile: false, root: resolve('.'), plugins: [react(), tailwind()],
  resolve: { alias: { '@': resolve('apps/web/client'), react: resolve('apps/web/node_modules/react'), 'react-dom': resolve('apps/web/node_modules/react-dom') } },
  server: { host: '127.0.0.1', port: 0 }, logLevel: 'error' });
await server.listen();
const address = server.httpServer!.address();
assert(address && typeof address !== 'string');
const origin = `http://127.0.0.1:${address.port}`;
const channel = process.env.DRIVY_BROWSER_CHANNEL;
const browser = await chromium.launch({ headless: true, args: ['--disable-gpu'], ...(channel ? { channel } : {}) });
const checks: string[] = [];

async function pageFor(mode: string): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/measure-detail-audit/index.html?mode=${mode}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}

try {
  // #433 : valeur 0, mais deux corrections de paiements plus anciens → les lignes sont lues et affichées, dans la partie qui en contient.
  const corrections = await pageFor('corrections');
  await corrections.getByText('Affichées : 2 sur 2', { exact: false }).waitFor();
  assert.equal(await corrections.getByRole('tab', { name: 'Corrections postérieures' }).getAttribute('aria-selected'), 'true');
  assert.equal(await corrections.locator('.pilotage-lines li').count(), 2);
  assert.deepEqual(await corrections.evaluate(() => (window as any).fixture.reads()), ['b']);
  await corrections.screenshot({ path: `${output}/corrections.png`, fullPage: true });
  checks.push('#433 : F06 à 0 avec lineCount=2 ouvre la partie « Corrections postérieures » et montre 2 lignes');
  await corrections.close();

  // #432 : une page de la partie A est en retard quand on passe à la partie B ; elle ne doit rien ajouter à B.
  const scope = await pageFor('scope');
  await scope.getByText('Affichées : 1 sur 2', { exact: false }).waitFor();
  await scope.getByRole('button', { name: 'Afficher la suite' }).click();
  await scope.waitForFunction(() => (window as any).fixture.waiting());
  await scope.getByRole('tab', { name: 'Corrections postérieures' }).click();
  await scope.getByText('Affichées : 1 sur 1', { exact: false }).waitFor();
  await scope.evaluate(() => (window as any).fixture.release());
  await scope.waitForTimeout(300);
  assert.equal(await scope.locator('.pilotage-lines li').count(), 1);
  assert.equal(await scope.getByText('Affichées : 1 sur 1', { exact: false }).count(), 1);
  assert.equal(await scope.getByRole('button', { name: 'Afficher la suite' }).count(), 0);
  await scope.screenshot({ path: `${output}/scope.png`, fullPage: true });
  checks.push('#432 : une page tardive de la partie A ne modifie ni les lignes ni le curseur de la partie B');
  await scope.close();

  await writeFile(`${output}/results.json`, JSON.stringify({ synthetic: true, engine: browser.version(), checks }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks }));
} finally { await browser.close(); await server.close(); }
