import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Contrôle navigateur synthétique du lot D : #422 (horaires) et reprise #430 des horaires. Vrais composants, API simulée.
const output = resolve('artifacts/lot-d-audit');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/lot-d-audit-fixture.tsx"></script></html>');
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
const fx = <T>(page: Page, expression: string) => page.evaluate(`(${expression})(window.fixture)`) as Promise<T>;

async function openEditor(): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 1000 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/lot-d-audit/index.html`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  await page.getByRole('button', { name: /Modifier/ }).first().click();
  await page.locator('#rule-start').waitFor();
  return page;
}
const time = (page: Page, id: string, value: string) => page.locator(id).fill(value);
const submitEdit = async (page: Page) => {
  await page.getByRole('button', { name: 'Relire', exact: true }).click();
  await page.getByRole('button', { name: 'Enregistrer l’horaire' }).click();
};

try {
  // #422-1 : conflit sur Début, puis retouche de Fin et de « Valable dès le » pendant l'alerte ; les deux choix gardent la dernière retouche.
  for (const choice of ['Garder ma saisie', 'Prendre la version de l’école'] as const) {
    const page = await openEditor();
    await time(page, '#rule-start', '09:00');
    await fx(page, 'f => f.externalChange({ localStart: "10:00" })');
    await page.getByText('Modifié ailleurs').waitFor();
    await time(page, '#rule-end', '18:30');
    await page.locator('#rule-from').fill('2020-02-01');
    await page.getByRole('button', { name: choice, exact: true }).click();
    await page.getByText('Modifié ailleurs').waitFor({ state: 'detached' });
    assert.equal(await page.locator('#rule-end').inputValue(), '18:30', `${choice}: Fin conservée`);
    assert.equal(await page.locator('#rule-from').inputValue(), '2020-02-01', `${choice}: date conservée`);
    assert.equal(await page.locator('#rule-start').inputValue(), choice === 'Garder ma saisie' ? '09:00' : '10:00', `${choice}: Début`);
    await fx(page, 'f => f.outcome("ok")');
    await submitEdit(page);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    const writes = await fx<any[]>(page, 'f => f.writes()');
    assert.equal(writes.at(-1).ifMatch, '"2"');
    assert.equal(writes.at(-1).body.localEnd, '18:30');
    assert.equal(writes.at(-1).body.localStart, choice === 'Garder ma saisie' ? '09:00' : '10:00');
    await fx(page, 'f => f.release()');
    await page.close();
    await fx; // no-op, garde l'ordre lisible
    // L'état serveur est rechargé pour l'itération suivante.
    checks.push(`#422 horaires (${choice}) : champ non conflictuel retouché après l'alerte conservé, If-Match v2, un seul envoi`);
  }
  // #422-2 et #430 : refus reçu après départ (le serveur est passé en v2 entre-temps), retour, reprise : la base éditée est conservée.
  async function refusedAfterLeaving(otherChange: Record<string, string>) {
    const page = await openEditor();
    await time(page, '#rule-start', '09:00');
    await submitEdit(page);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    await fx(page, 'f => f.hide()');
    await page.locator('#elsewhere').waitFor();
    await page.evaluate(`window.fixture.serverChange(${JSON.stringify(otherChange)})`);
    await fx(page, 'f => f.release()');
    await page.waitForTimeout(300);
    await fx(page, 'f => f.show()');
    await page.getByRole('button', { name: 'Reprendre la saisie' }).waitFor();
    return page;
  }
  {
    const page = await refusedAfterLeaving({ localEnd: '18:00' });
    // Isolation : une autre école ne voit ni le refus ni la saisie ; la nôtre les retrouve.
    await fx(page, 'f => f.otherSchool()');
    await page.waitForTimeout(300);
    assert.equal(await page.getByRole('button', { name: 'Reprendre la saisie' }).count(), 0);
    await fx(page, 'f => f.ownSchool()');
    await page.getByRole('button', { name: 'Reprendre la saisie' }).waitFor();
    await page.getByRole('button', { name: 'Reprendre la saisie' }).click();
    await page.locator('#rule-start').waitFor();
    assert.equal(await page.locator('#rule-start').inputValue(), '09:00');
    assert.equal(await page.locator('#rule-end').inputValue(), '18:00', 'la fin d’autrui est adoptée, pas écrasée');
    assert.equal(await page.getByText('Modifié ailleurs').count(), 0);
    await fx(page, 'f => f.outcome("ok")');
    await submitEdit(page);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    const writes = await fx<any[]>(page, 'f => f.writes()');
    assert.equal(writes.length, 2);
    assert.equal(writes[1].ifMatch, '"2"');
    assert.equal(writes[1].body.localStart, '09:00');
    assert.equal(writes[1].body.localEnd, '18:00');
    await page.close();
    checks.push('#422/#430 horaires : refus reçu page quittée, isolation école, reprise ; v1 09:00–17:00 + autrui v2 fin 18:00 → envoi 09:00–18:00 sous If-Match v2');
  }
  for (const choice of ['Garder ma saisie', 'Prendre la version de l’école'] as const) {
    const page = await refusedAfterLeaving({ localStart: '10:00' });
    await page.getByRole('button', { name: 'Reprendre la saisie' }).click();
    await page.getByText('Modifié ailleurs').waitFor();
    await page.getByRole('button', { name: choice, exact: true }).click();
    assert.equal(await page.locator('#rule-start').inputValue(), choice === 'Garder ma saisie' ? '09:00' : '10:00');
    if (choice !== 'Garder ma saisie') {
      // La version de l'école adoptée est identique à la base : rien à enregistrer, aucun envoi, aucun écrasement.
      assert.equal(await page.getByRole('button', { name: 'Relire', exact: true }).isDisabled(), true);
      assert.equal((await fx<any[]>(page, 'f => f.writes()')).length, 1);
      await page.close();
      checks.push(`#422/#430 horaires : même champ après reprise, « ${choice} » adopte la v2 sans nouvel envoi`);
      continue;
    }
    await fx(page, 'f => f.outcome("ok")');
    await submitEdit(page);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    const writes = await fx<any[]>(page, 'f => f.writes()');
    assert.equal(writes[1].ifMatch, '"2"');
    assert.equal(writes[1].body.localStart, choice === 'Garder ma saisie' ? '09:00' : '10:00');
    await page.close();
    checks.push(`#422/#430 horaires : même champ après reprise, choix explicite « ${choice} », If-Match v2`);
  }
  // #430 : succès tardif page quittée → ni refus ni reprise à proposer.
  {
    const page = await openEditor();
    await time(page, '#rule-start', '09:00');
    await fx(page, 'f => f.outcome("ok")');
    await submitEdit(page);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    await fx(page, 'f => f.hide()');
    await page.locator('#elsewhere').waitFor();
    await fx(page, 'f => f.release()');
    await page.waitForTimeout(300);
    await fx(page, 'f => f.show()');
    await page.getByRole('heading', { name: 'Disponibilités' }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Reprendre la saisie' }).count(), 0);
    checks.push('#430 horaires : succès tardif page quittée, aucun refus ni reprise affichés');
    await page.close();
  }
  await writeFile(`${output}/results.json`, JSON.stringify({ synthetic: true, engine: browser.version(), checks }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks }));
} finally { await browser.close(); await server.close(); }
