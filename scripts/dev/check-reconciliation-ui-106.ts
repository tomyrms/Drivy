import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

const output = resolve('artifacts/reconciliation-ui-106');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/reconciliation-ui-106-fixture.tsx"></script></html>');
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
  await page.goto(`${origin}/artifacts/reconciliation-ui-106/index.html?mode=${mode}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}


async function send(page: Page, field: string) {
 await page.locator('#school-name').fill('Envoyé');
 await page.getByRole('button', { name: 'Enregistrer', exact: true }).click();
 await page.waitForFunction(() => (window as any).fixture.waiting());
 await page.locator(field).fill(field === '#school-name' ? 'Local' : 'local@example.invalid');
 await page.evaluate(() => (window as any).fixture.release());
}
try {
 const page = await pageFor('normal');
 await send(page, '#school-email');
 await page.waitForFunction(() => document.querySelector<HTMLInputElement>('#school-name')?.value === 'Nom confirmé');
 assert.equal(await page.locator('#school-email').inputValue(), 'local@example.invalid');
 assert.equal(await page.evaluate(() => document.activeElement?.id), 'school-email');
 assert.equal(await page.getByText('Les coordonnées de l’école sont enregistrées.').count(), 0);
 assert.equal(await page.getByText('Modifications à concilier', { exact: true }).count(), 0);
 await page.evaluate(() => (window as any).fixture.refresh());
 await page.locator('#school-phone').fill('123');
 assert.equal(await page.getByText('Modifications à concilier', { exact: true }).count(), 0);
 assert.equal(await page.evaluate(() => (window as any).fixture.writes().length), 1);
 checks.push('Réponse différée: normalisation autre champ, saisie et focus conservés, aucun faux succès ni renvoi');
 await page.close();
 const conflict = await pageFor('conflict');
 await send(conflict, '#school-name');
 await conflict.getByText('Modifications à concilier', { exact: true }).waitFor();
 assert.equal(await conflict.locator('#school-name').inputValue(), 'Local');
 assert.equal(await conflict.evaluate(() => document.activeElement?.id), 'school-name');
 await conflict.evaluate(() => (window as any).fixture.refresh());
 assert.equal(await conflict.getByText('Modifications à concilier', { exact: true }).count(), 1);
 await conflict.screenshot({ path: `${output}/desktop.png`, fullPage: true });
 await conflict.setViewportSize({ width: 390, height: 844 });
 await conflict.screenshot({ path: `${output}/narrow.png`, fullPage: true });
 assert.equal(await conflict.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
 await conflict.getByRole('button', { name: 'Reprendre les coordonnées confirmées' }).focus();
 await conflict.keyboard.press('Enter');
 await conflict.waitForFunction(() => document.querySelector<HTMLInputElement>('#school-name')?.value === 'Nom confirmé');
 await conflict.waitForFunction(() => document.activeElement?.id === 'school-name');
 assert.equal(await conflict.evaluate(() => document.activeElement?.id), 'school-name');
 await conflict.locator('#school-name').fill('Nouvelle édition');
 assert.equal(await conflict.getByText('Modifications à concilier', { exact: true }).count(), 0);
 await conflict.getByRole('button', { name: 'Enregistrer', exact: true }).click();
 await conflict.waitForFunction(() => (window as any).fixture.waiting());
 const writes = await conflict.evaluate(() => (window as any).fixture.writes());
 assert.equal(writes.length, 2);
 assert.equal(writes[1].body.name, 'Nouvelle édition');
 assert.equal(writes[1].headers['if-match'], '"2"');
 assert.ok(writes[1].headers['x-csrf-token']);
 await conflict.evaluate(() => { (window as any).fixture.scope(); (window as any).fixture.release(); });
 await conflict.waitForFunction(() => document.querySelector<HTMLInputElement>('#school-name')?.value === 'Nom confirmé');
 assert.equal(await conflict.getByText('Modifications à concilier', { exact: true }).count(), 0);
 checks.push('Même champ: conflit persistant au refresh, résolution clavier puis édition, If-Match/CSRF, changement de portée pendant envoi');
 await conflict.close();
 const receipt = await pageFor('receipt');
 await receipt.evaluate(() => (window as any).fixture.receipt());
 await send(receipt, '#school-email');
 await receipt.getByText('Une demande attend la vérification de son résultat (voir en haut de la page).').waitFor();
 const verified = await receipt.evaluate(() => (window as any).fixture.verify());
 assert.equal(verified.status, 'confirmed'); assert.equal(verified.body, null);
 await receipt.getByText('Envoi confirmé, coordonnées à relire', { exact: true }).waitFor();
 await receipt.getByRole('button', { name: 'Relire les coordonnées', exact: true }).waitFor();
 assert.equal(await receipt.locator('#school-email').inputValue(), 'local@example.invalid');
 assert.equal(await receipt.locator('#school-name').inputValue(), 'Envoyé');
 assert.equal(await receipt.getByRole('button', { name: 'Enregistrer', exact: true }).isDisabled(), true);
 assert.equal(await receipt.evaluate(() => (window as any).fixture.writes().length), 1);
 await receipt.screenshot({ path: `${output}/receipt.png`, fullPage: true });
 await receipt.evaluate(() => (window as any).fixture.retry());
 await receipt.getByRole('button', { name: 'Relire les coordonnées', exact: true }).click();
 await receipt.waitForFunction(() => document.querySelector<HTMLInputElement>('#school-name')?.value === 'Nom confirmé');
 assert.equal(await receipt.locator('#school-email').inputValue(), 'local@example.invalid');
 assert.equal(await receipt.evaluate(() => (window as any).fixture.writes().length), 1);
 checks.push('Reçu réel body=null, relecture 503 sans corps fabriqué, retry lecture et fusion sans renvoi');
 await receipt.close();
 await writeFile(`${output}/results.json`, JSON.stringify({ synthetic: true, engine: browser.version(), checks }, null, 2));
 console.log(JSON.stringify({ result: 'PASS', checks }));
} finally { await browser.close(); await server.close(); }
