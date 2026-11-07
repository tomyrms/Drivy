import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Contrôle navigateur synthétique du lot D : #434 (cours annulé), #430 (participants) et #422 (éditeur de cours). Vrais composants, API simulée.
const output = resolve('artifacts/lot-d-courses');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/lot-d-courses-fixture.tsx"></script></html>');
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

async function open(surface: 'sheet' | 'editor' | 'lanes'): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 1100 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/lot-d-courses/index.html?surface=${surface}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}
const openParticipants = async (page: Page, tab: string) => {
  await page.getByRole('button', { name: 'Participants', exact: true }).click();
  await page.getByRole('tab', { name: tab, exact: true }).click();
};

try {
  // #434 : cours annulé. La feuille s'ouvre ; les faits existants se corrigent ; les nouveaux actes restent fermés.
  {
    const page = await open('sheet');
    await openParticipants(page, 'Règlements');
    await page.getByText('Ana Annulée').first().waitFor();
    assert.equal(await page.getByRole('button', { name: /Consigner un règlement/ }).count(), 0, 'aucun nouveau règlement pour une inscription annulée');
    await page.getByRole('button', { name: /Annuler la saisie de/ }).waitFor();
    await page.getByRole('tab', { name: 'Validation', exact: true }).click();
    assert.equal(await page.getByRole('button', { name: /Valider le cours pour/ }).count(), 0, 'aucune nouvelle validation');
    await page.getByRole('button', { name: 'Retirer la validation de Ana Annulée' }).waitFor();
    await page.getByRole('tab', { name: 'Appel', exact: true }).click();
    await page.getByText('Ana Annulée').first().waitFor();
    assert.equal(await page.getByText('Cara Sans Marque').count(), 0, 'une inscription annulée sans marque ne figure pas à l’appel');
    await page.screenshot({ path: `${output}/cancelled-attendance.png`, fullPage: true });
    checks.push('#434 : cours annulé, feuille ouverte ; règlement annulable et validation retirable, ni règlement ni validation nouveaux, appel limité aux marques existantes');
    await page.close();
  }

  // #430 : refus reçu après départ de la feuille, retour, reprise ; isolation d'école ; succès tardif.
  async function refusedAfterLeaving(): Promise<Page> {
    const page = await open('sheet');
    await openParticipants(page, 'Règlements');
    await page.getByRole('button', { name: /Annuler la saisie de/ }).click();
    await page.getByRole('dialog').getByRole('textbox').fill('Erreur de saisie');
    await page.getByRole('dialog').getByRole('button', { name: 'Annuler la saisie', exact: true }).click();
    await page.waitForFunction(() => (window as any).fixture.waiting());
    await fx(page, 'f => f.hide()');
    await page.locator('#elsewhere').waitFor();
    await fx(page, 'f => f.release()');
    await page.waitForTimeout(300);
    await fx(page, 'f => f.show()');
    return page;
  }
  {
    const page = await refusedAfterLeaving();
    await openParticipants(page, 'Règlements');
    await page.getByRole('button', { name: 'Reprendre la saisie' }).waitFor();
    await fx(page, 'f => f.otherSchool()');
    await page.waitForTimeout(300);
    assert.equal(await page.getByRole('button', { name: 'Reprendre la saisie' }).count(), 0, 'isolation école');
    await fx(page, 'f => f.ownSchool()');
    await page.waitForTimeout(300);
    if (await page.getByRole('button', { name: 'Reprendre la saisie' }).count() === 0) await openParticipants(page, 'Règlements');
    await page.getByRole('button', { name: 'Reprendre la saisie' }).click();
    await page.getByRole('dialog').getByRole('textbox').waitFor();
    assert.equal(await page.getByRole('dialog').getByRole('textbox').inputValue(), 'Erreur de saisie');
    await page.screenshot({ path: `${output}/participants-resumed.png`, fullPage: true });
    checks.push('#430 participants : refus reçu feuille quittée, retrouvé au retour ; absent dans une autre école ; reprise avec le motif saisi');
    await page.close();
  }
  {
    const page = await open('sheet');
    await fx(page, 'f => f.mode("ok")');
    await openParticipants(page, 'Règlements');
    await page.getByRole('button', { name: /Annuler la saisie de/ }).click();
    await page.getByRole('dialog').getByRole('textbox').fill('Erreur de saisie');
    await page.getByRole('dialog').getByRole('button', { name: 'Annuler la saisie', exact: true }).click();
    await page.waitForFunction(() => (window as any).fixture.waiting());
    await fx(page, 'f => f.hide()');
    await page.locator('#elsewhere').waitFor();
    await fx(page, 'f => f.release()');
    await page.waitForTimeout(300);
    await fx(page, 'f => f.show()');
    await openParticipants(page, 'Règlements');
    await page.getByText('Ana Annulée').first().waitFor();
    assert.equal(await page.getByRole('button', { name: 'Reprendre la saisie' }).count(), 0, 'succès tardif : aucun refus');
    checks.push('#430 participants : succès tardif feuille quittée, aucun refus ni reprise');
    await page.close();
  }
  // #422 cours : conflit sur le titre, places retouchées avant l'alerte ; formulaire verrouillé pendant l'alerte, les deux choix gardent les places, If-Match de la version vue.
  for (const choice of ['Garder ma saisie', 'Prendre la version de l’école'] as const) {
    const page = await open('editor');
    await page.locator('#course-title').waitFor();
    await page.locator('#course-title').fill('Mon titre');
    await page.locator('#course-capacity').fill('12');
    await fx(page, 'f => f.serverChange({ title: "Titre de l’école" })');
    await page.getByText('Modifié ailleurs').waitFor();
    assert.equal(await page.locator('#course-capacity').isDisabled(), true, 'formulaire verrouillé pendant l’alerte : aucune retouche perdue possible');
    await page.getByRole('button', { name: choice, exact: true }).click();
    await page.getByText('Modifié ailleurs').waitFor({ state: 'detached' });
    assert.equal(await page.locator('#course-capacity').inputValue(), '12', `${choice}: places conservées`);
    assert.equal(await page.locator('#course-title').inputValue(), choice === 'Garder ma saisie' ? 'Mon titre' : 'Titre de l’école');
    await fx(page, 'f => f.mode("ok")');
    await page.getByRole('button', { name: 'Enregistrer le brouillon', exact: true }).click();
    await page.waitForFunction(() => (window as any).fixture.waiting());
    const writes = await fx<any[]>(page, 'f => f.writes()');
    assert.equal(writes.length, 1, 'un seul envoi');
    assert.equal(writes[0].ifMatch, '"2"');
    assert.equal(writes[0].body.capacity, 12);
    assert.equal(writes[0].body.title, choice === 'Garder ma saisie' ? 'Mon titre' : 'Titre de l’école');
    await fx(page, 'f => f.release()');
    checks.push(`#422 cours (${choice}) : formulaire verrouillé pendant l'alerte, places conservées, If-Match v2, un seul envoi`);
    await page.close();
  }
  // #422 cours : champs distincts → fusion sans alerte, If-Match v2.
  {
    const page = await open('editor');
    await page.locator('#course-title').waitFor();
    await page.locator('#course-title').fill('Mon titre');
    await fx(page, 'f => f.serverChange({ location: "Salle B" })');
    await page.waitForFunction(() => (document.querySelector('#course-location') as HTMLInputElement | null)?.value === 'Salle B');
    assert.equal(await page.getByText('Modifié ailleurs').count(), 0);
    assert.equal(await page.locator('#course-title').inputValue(), 'Mon titre');
    await fx(page, 'f => f.mode("ok")');
    await page.getByRole('button', { name: 'Enregistrer le brouillon', exact: true }).click();
    await page.waitForFunction(() => (window as any).fixture.waiting());
    const writes = await fx<any[]>(page, 'f => f.writes()');
    assert.equal(writes[0].ifMatch, '"2"');
    assert.equal(writes[0].body.location, 'Salle B');
    assert.equal(writes[0].body.title, 'Mon titre');
    await fx(page, 'f => f.release()');
    checks.push('#422 cours : champs distincts fusionnés sans alerte, If-Match v2, ni perte ni écrasement');
    await page.close();
  }
  // #430 familles tarifs / conditions / programmes : vrais hooks de commandes, refus reçu après démontage, retrouvé au remontage, isolé par école, succès tardif sans refus.
  for (const family of ['tariff', 'terms', 'programme'] as const) {
    const column = { tariff: 'tarifs', terms: 'conditions', programme: 'programmes' }[family];
    const text = async (page: Page) => (await page.locator('#lanes').innerText());
    const page = await open('lanes');
    await page.locator('#lanes').waitFor();
    await page.evaluate(`window.lanes.${family}()`);
    await page.waitForFunction(() => (window as any).fixture.waiting());
    await fx(page, 'f => f.hide()');
    await page.locator('#elsewhere').waitFor();
    await fx(page, 'f => f.release()');
    await page.waitForTimeout(300);
    await fx(page, 'f => f.show()');
    await page.locator('#lanes').waitFor();
    assert.match(await text(page), new RegExp(`${column}:1`), `${family}: refus retrouvé au remontage`);
    for (const other of ['tarifs', 'conditions', 'programmes'].filter(item => item !== column)) assert.match(await text(page), new RegExp(`${other}:0`), `${family}: autres familles intactes`);
    await fx(page, 'f => f.otherSchool()');
    await page.waitForTimeout(200);
    assert.match(await text(page), new RegExp(`${column}:0`), `${family}: invisible dans une autre école`);
    await fx(page, 'f => f.ownSchool()');
    await page.waitForTimeout(200);
    assert.match(await text(page), new RegExp(`${column}:1`), `${family}: retrouvé dans l’école d’origine`);
    // Succès tardif : aucun refus.
    const late = await open('lanes');
    await fx(late, 'f => f.mode("ok")');
    await late.evaluate(`window.lanes.${family}()`);
    await late.waitForFunction(() => (window as any).fixture.waiting());
    await fx(late, 'f => f.hide()');
    await late.locator('#elsewhere').waitFor();
    await fx(late, 'f => f.release()');
    await late.waitForTimeout(300);
    await fx(late, 'f => f.show()');
    await late.locator('#lanes').waitFor();
    assert.match(await text(late), new RegExp(`${column}:0`), `${family}: succès tardif sans refus`);
    checks.push(`#430 ${family === 'tariff' ? 'tarifs' : family === 'terms' ? 'conditions' : 'programmes'} : refus reçu page quittée retrouvé au remontage, isolé par école ; succès tardif sans refus`);
    await late.close();
    await page.close();
  }
  await writeFile(`${output}/results.json`, JSON.stringify({ synthetic: true, engine: browser.version(), checks }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks }));
} finally { await browser.close(); await server.close(); }
