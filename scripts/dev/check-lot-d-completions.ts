import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Contrôle navigateur synthétique du reste du lot D : #437 (création confirmée par reçu), #442 (déplacement de leçon), #444 (examens après
// transition) et règles d'annulation structurées (#424). Vrais composants et hooks, API simulée.
const output = resolve('artifacts/lot-d-completions');
await mkdir(output, { recursive: true });
await writeFile(`${output}/index.html`, '<html lang="fr"><meta charset="utf-8"><div id="root"></div><script type="module" src="/scripts/dev/lot-d-completions-fixture.tsx"></script></html>');
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
const ev = <T>(page: Page, expression: string) => page.evaluate(expression) as Promise<T>;

async function open(surface: string): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 1100 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/lot-d-completions/index.html?surface=${surface}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}

try {
  // #424 : la règle structurée est lue, conservée tant que le texte ne change pas, et exige une décision quand il change.
  {
    const page = await open('rules');
    await page.getByLabel(/Délai d’annulation/).waitFor();
    assert.equal(await page.getByLabel(/Délai d’annulation/).inputValue(), '24', 'le délai structuré lu est affiché');
    assert.deepEqual(await ev(page, 'window.rules.payload()'), { procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 24 h avant.', sourceUrls: [] }, 'sans choix, la règle n’est pas envoyée (l’école la conserve)');
    assert.equal(await ev(page, 'window.rules.changed()'), false);
    await page.getByLabel('Conditions d’annulation').fill('Annulation 48 h avant.');
    assert.equal(await ev(page, 'window.rules.valid()'), false, 'le texte change : décision requise avant envoi');
    await page.getByText('Le texte d’annulation change : conservez le délai, modifiez-le ou retirez-le.').waitFor();
    await page.getByRole('button', { name: 'Conserver ce délai' }).click();
    assert.equal(await ev(page, 'window.rules.valid()'), true);
    assert.deepEqual((await ev<any>(page, 'window.rules.payload()')).cancellationRules, { cancellationHours: 24, lateAction: 'CONTACT' }, 'décision explicite : règle conservée envoyée');
    await page.getByLabel('Conditions d’annulation').fill('Annulation 72 h avant.');
    await page.getByLabel(/Délai d’annulation/).fill('72');
    assert.deepEqual((await ev<any>(page, 'window.rules.payload()')).cancellationRules, { cancellationHours: 72, lateAction: 'CONTACT' }, 'délai modifié');
    await page.getByLabel(/Délai d’annulation/).fill('');
    assert.equal((await ev<any>(page, 'window.rules.payload()')).cancellationRules, null, 'délai retiré = null explicite');
    await page.getByLabel(/Délai d’annulation/).fill('abc');
    assert.equal(await ev(page, 'window.rules.valid()'), false, 'heures invalides refusées');
    await page.screenshot({ path: `${output}/rules.png`, fullPage: true });
    checks.push('#424 : délai lu, non envoyé sans choix, décision exigée au changement de texte, conservé / modifié / retiré (null) explicitement, heures invalides refusées');
    await page.close();
  }

  // #444 : après clôture, les examens à venir restent visibles et corrigeables ; la création reste fermée.
  {
    const page = await open('exams');
    await page.getByText('1 examen à venir').waitFor();
    await page.getByRole('button', { name: 'Modifier', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Reporter', exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Examen théorique/ }).count(), 0, 'aucune création d’examen pour une formation terminée');
    await page.screenshot({ path: `${output}/exams-completed.png`, fullPage: true });
    await page.getByRole('button', { name: 'Modifier', exact: true }).click();
    await page.getByRole('dialog').waitFor();
    await page.getByRole('button', { name: 'Annuler', exact: true }).click();
    await ev(page, 'window.setTrainingStatus("ACTIVE")');
    await page.getByRole('button', { name: /Examen théorique/ }).waitFor();
    assert.equal(await page.getByText('1 examen à venir').count(), 0, 'formation active : pas de badge');
    checks.push('#444 : formation terminée, badge « 1 examen à venir », Modifier et Reporter ouverts, création fermée ; formation active : création rouverte, pas de badge');
    await page.close();
  }

  // #442 : relecture d'un déplacement en conflit, base et version avancées ensemble, saisie réconciliée.
  {
    const page = await open('lesson');
    await page.locator('#lesson').waitFor();
    assert.match(await page.locator('#lesson').innerText(), /version:1 lieu:Gare/);
    await ev(page, 'window.lesson.change("meetingPoint", "Parc")');
    await ev(page, 'window.lesson.change("reason", "Demande de l’élève")');
    await ev(page, 'window.fixture.serverLesson({ version: 2, bufferMinutesSnapshot: 15 })');
    await ev(page, 'window.lesson.rereadVersion()');
    await page.waitForFunction(() => /relu:true/.test(document.getElementById('lesson')!.innerText));
    const first = await page.locator('#lesson').innerText();
    assert.match(first, /version:2/, 'la base avance à la version relue');
    assert.match(first, /lieu:Parc/, 'ma saisie est conservée');
    assert.match(first, /tampon:15/, 'le champ que seule l’école a changé est adopté');
    assert.match(first, /motif:Demande de l’élève/);
    assert.match(first, /accord:false/, 'l’accord est à reconfirmer');
    await ev(page, 'window.fixture.serverLesson({ version: 3, meetingPoint: "Marché", bufferMinutesSnapshot: 15 })');
    await ev(page, 'window.lesson.rereadVersion()');
    await page.waitForFunction(() => /version:3/.test(document.getElementById('lesson')!.innerText));
    assert.match(await page.locator('#lesson').innerText(), /lieu:Parc/, 'même champ des deux côtés : la saisie reste, en conflit signalé, à confirmer de nouveau');
    checks.push('#442 : relecture V1→V2 puis V3 ; la base avance avec la version, le champ de l’école seul est adopté, ma saisie est gardée, l’accord est à redonner');
    await page.close();
  }

  // #437 : création dont la réponse se perd, confirmée plus tard par le reçu ; le formulaire se rattache et ne peut plus créer de doublon.
  {
    const page = await open('create');
    await page.getByLabel('Titre').fill('Cours synthétique');
    await page.getByLabel('Places').fill('8');
    await page.getByRole('button', { name: /Modifier la séance 1/ }).click();
    await page.getByLabel('Date').fill('2031-05-05');
    await page.getByLabel('Début').fill('09:00');
    await page.getByLabel('Fin').fill('11:00');
    await page.getByRole('button', { name: /Retour/ }).first().click();
    await page.getByRole('button', { name: 'Enregistrer le brouillon' }).first().click();
    await page.waitForFunction(() => (window as any).fixture.writes().length === 1);
    await ev(page, `window.fixture.receipt({ operationId: window.fixture.writes()[0].body.operationId, commandType: 'CREATE_COURSE_SERIES', resourceType: 'CourseSeries', resourceId: window.fixture.createdId, committedAt: '2030-01-01T10:00:00Z', resourceVersion: 1 })`);
    const result = await ev<any>(page, 'window.fixture.verify()');
    assert.equal(result.status, 'confirmed', JSON.stringify(result));
    await page.waitForFunction(() => document.getElementById('attached')!.innerText.includes('50000000-0000-4000-8000-0000000000c1'));
    const enabled = await page.getByRole('button', { name: 'Enregistrer le brouillon' }).first().isEnabled().catch(() => false);
    assert.equal(enabled, false, 'le formulaire de création est verrouillé après rattachement');
    await page.getByRole('button', { name: 'Enregistrer le brouillon' }).first().click({ force: true, timeout: 1000 }).catch(() => {});
    await page.waitForTimeout(300);
    assert.equal(await ev<number>(page, 'window.fixture.writes().length'), 1, 'aucune seconde création');
    checks.push('#437 : réponse perdue, reçu confirmé : rattaché à l’identifiant de la série créée, formulaire verrouillé, une seule écriture');
    await page.close();
  }
  console.log(JSON.stringify({ status: 'RÉUSSI', checks }, null, 2));
} finally {
  await browser.close();
  await server.close();
}
