import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium, type Page } from '../../infra/dev/browser.js';
import { createServer } from '../../apps/web/node_modules/vite/dist/node/index.js';
import react from '../../apps/web/node_modules/@vitejs/plugin-react/dist/index.js';
import tailwind from '../../apps/web/node_modules/@tailwindcss/vite/dist/index.mjs';

// Contrôle navigateur synthétique du reste du lot D : #437 (création confirmée par reçu), #442 (déplacement de leçon), #443 (relecture en panne),
// #444 (examens après transition) et règles d'annulation structurées (#424). Vrais composants et hooks, API simulée.
// `ONLY=rules,exams,lesson,reread,create` limite les blocs joués.
const output = resolve('artifacts/lot-d-completions');
const only = process.env.ONLY?.split(',');
const wanted = (name: string) => !only || only.includes(name);
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
const ok = (body: unknown, status = 200) => ({ status, body });

async function open(surface: string, extra = ''): Promise<Page> {
  const page = await browser.newPage({ viewport: { width: 1000, height: 1100 } });
  page.on('pageerror', error => { throw error; });
  await page.goto(`${origin}/artifacts/lot-d-completions/index.html?surface=${surface}${extra}`);
  await page.waitForFunction(() => Boolean((window as any).fixture));
  return page;
}
const fx = <T>(page: Page, expression: string) => ev<T>(page, `window.fixture.${expression}`);

try {
  // #424 : la règle structurée est lue, conservée tant que le texte ne change pas, et exige une décision quand il change.
  if (wanted('rules')) {
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

    // Règle sans délai : conservation exacte et retrait explicite sont deux décisions distinctes.
    for (const [base, expected] of [['nofee', { cancellationHours: null, lateAction: 'NO_FEE' }], ['contact-null', { cancellationHours: null, lateAction: 'CONTACT' }]] as const) {
      const keep = await open('rules', `&base=${base}`);
      await keep.getByLabel('Conditions d’annulation').waitFor();
      assert.deepEqual((await ev<any>(keep, 'window.rules.payload()')).cancellationRules, undefined, `${base} : rien n’est envoyé sans décision`);
      await keep.getByLabel('Conditions d’annulation').fill('Annulation 48 h avant.');
      assert.equal(await ev(keep, 'window.rules.valid()'), false, `${base} : le changement de texte exige une décision`);
      await keep.getByRole('button', { name: 'Conserver ce délai' }).click();
      assert.equal(await ev(keep, 'window.rules.valid()'), true);
      assert.deepEqual((await ev<any>(keep, 'window.rules.payload()')).cancellationRules, expected, `${base} : « Conserver » renvoie la règle exacte, pas un retrait`);
      // L'école publie entre-temps une règle plus récente : la conservation suit la règle actuelle de l'école.
      await ev(keep, `window.rules.rebase({ procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 48 h avant.', sourceUrls: [], cancellationRules: { cancellationHours: 12, lateAction: 'CONTACT' } })`); await keep.waitForTimeout(200);
      assert.deepEqual((await ev<any>(keep, 'window.rules.payload()')).cancellationRules, { cancellationHours: 12, lateAction: 'CONTACT' }, `${base} : la conservation suit la règle de l’école après relecture`);
      await keep.close();

      const remove = await open('rules', `&base=${base}`);
      await remove.getByLabel('Conditions d’annulation').fill('Annulation 48 h avant.');
      await remove.getByRole('button', { name: 'Retirer le délai' }).click();
      assert.equal((await ev<any>(remove, 'window.rules.payload()')).cancellationRules, null, `${base} : « Retirer » envoie un retrait explicite`);
      await ev(remove, `window.rules.rebase({ procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 48 h avant.', sourceUrls: [], cancellationRules: { cancellationHours: 12, lateAction: 'CONTACT' } })`); await remove.waitForTimeout(200);
      assert.equal((await ev<any>(remove, 'window.rules.payload()')).cancellationRules, null, `${base} : le retrait décidé survit à la relecture`);
      await remove.close();
    }
    const edit = await open('rules');
    await edit.getByLabel('Conditions d’annulation').fill('Annulation 72 h avant.');
    await edit.getByLabel(/Délai d’annulation/).fill('72');
    await ev(edit, `window.rules.rebase({ procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 72 h avant.', sourceUrls: [], cancellationRules: { cancellationHours: 6, lateAction: 'NO_FEE' } })`); await edit.waitForTimeout(200);
    assert.deepEqual((await ev<any>(edit, 'window.rules.payload()')).cancellationRules, { cancellationHours: 72, lateAction: 'CONTACT' }, 'le délai modifié par la personne survit à la relecture');
    await edit.close();
    checks.push('#424 : règle sans délai (NO_FEE, CONTACT) conservée à l’identique ou retirée explicitement ; les deux décisions et une retouche survivent à la relecture de l’école');
  }

  // #444 : après clôture, les examens à venir restent visibles et corrigeables ; la création reste fermée.
  if (wanted('exams')) {
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
    await page.close();

    // La formation devient inactive alors que le dialogue de création est déjà ouvert : plus de création, les gestes existants restent.
    const open2 = await open('exams', '&status=ACTIVE');
    await open2.getByRole('button', { name: /Examen théorique/ }).click();
    await open2.getByRole('heading', { name: /Prévoir/ }).waitFor();
    await ev(open2, 'window.setTrainingStatus("COMPLETED")');
    await open2.getByRole('dialog').waitFor({ state: 'detached' });
    assert.equal(await open2.getByRole('button', { name: 'Prévoir l’examen' }).count(), 0, 'aucun bouton de création après la clôture');
    assert.equal(await open2.getByRole('button', { name: /Examen théorique/ }).count(), 0);
    assert.equal(await fx<number>(open2, 'writes().length'), 0, 'rien n’a été envoyé');
    await open2.getByRole('button', { name: 'Modifier', exact: true }).click();
    await open2.getByRole('dialog').getByText('Modifier la date').waitFor();
    await open2.close();
    checks.push('#444 : formation terminée, badge « 1 examen à venir », Modifier et Reporter ouverts, création fermée ; formation active : création rouverte, pas de badge ; clôture pendant le dialogue de création : dialogue retiré, aucune écriture, gestes sur l’existant conservés');
  }

  // #442 (hook) : relecture d'un déplacement en conflit, base et version avancées ensemble, saisie réconciliée.
  if (wanted('lesson')) {
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
    checks.push('#442 (hook monté) : relecture V1→V2 puis V3 ; la base avance avec la version, le champ de l’école seul est adopté, ma saisie est gardée, l’accord est à redonner');
    await page.close();
  }

  // #442 (trajet réel) : déplacement refusé (VERSION_CONFLICT), lecture plus récente, reprise de la saisie, remontage du formulaire, nouvelle commande.
  if (wanted('lessonflow')) {
    for (const scenario of [
      { name: 'modification disjointe', school: { version: 2, bufferMinutesSnapshot: 15 }, lieu: 'Parc', buffer: '15', conflictText: null as RegExp | null },
      { name: 'conflit sur le même champ', school: { version: 2, meetingPoint: 'Marché', bufferMinutesSnapshot: 15 }, lieu: 'Parc', buffer: '15', conflictText: /lieu/ },
    ]) {
      const page = await open('lessonflow');
      await page.getByRole('button', { name: /^Modifier/ }).first().click();
      await page.locator('#lesson-place').fill('Parc');
      await page.locator('#lesson-move-reason').fill('Demande de l’élève');
      await page.getByRole('checkbox', { name: /accord/ }).click();
      await page.getByRole('button', { name: /^Continuer/ }).click();
      await page.getByRole('button', { name: 'Confirmer le changement' }).waitFor();
      await fx(page, `answer({ status: 409, body: { code: 'VERSION_CONFLICT' } })`);
      await fx(page, `serverLesson(${JSON.stringify(scenario.school)})`);
      await page.getByRole('button', { name: 'Confirmer le changement' }).click();
      await page.waitForFunction(() => (window as any).fixture.writes().length === 1);
      const first = (await fx<any[]>(page, 'writes()'))[0];
      assert.equal(first.ifMatch, '"1"', 'première commande : If-Match de la version lue');
      await page.getByRole('button', { name: 'Reprendre la saisie' }).waitFor();
      const detailBuffer = await page.getByText(/Temps de battement/).locator('xpath=..').innerText();
      await page.getByRole('button', { name: 'Reprendre la saisie' }).click();
      await page.locator('#lesson-place').waitFor();
      assert.equal(await page.locator('#lesson-place').inputValue(), scenario.lieu, `${scenario.name} : ma saisie du lieu est gardée à la reprise`);
      // Le détail et le remontage lisent encore la version V1 du cache : c'est « Relire la version actuelle » qui amène V2.
      await page.getByRole('button', { name: 'Relire la version actuelle' }).click();
      await page.waitForFunction(expected => (document.getElementById('lesson-buffer') as HTMLInputElement | null)?.value === expected, scenario.buffer);
      assert.equal(await page.locator('#lesson-move-reason').inputValue(), 'Demande de l’élève', `${scenario.name} : le motif est gardé`);
      assert.equal(await page.locator('#lesson-buffer').inputValue(), scenario.buffer, `${scenario.name} : le battement changé par l’école seule n’est pas pris pour ma retouche (détail avant reprise : ${detailBuffer.replace(/\s+/g, ' ')})`);
      assert.equal(await page.getByRole('checkbox', { name: /accord/ }).getAttribute('aria-checked'), 'false', `${scenario.name} : l’accord est à redonner`);
      const alertText = await page.getByRole('alert').allInnerTexts();
      if (scenario.conflictText) assert.match(alertText.join(' | '), scenario.conflictText, `${scenario.name} : la divergence réelle est montrée avant confirmation`);
      else assert.doesNotMatch(alertText.join(' | '), /l’école a aussi changé/, `${scenario.name} : aucune divergence inventée`);
      await page.screenshot({ path: `${output}/lesson-${scenario.name.replace(/\s+/g, '-')}.png`, fullPage: true });
      await fx(page, `answer({ status: 200, body: window.fixture.envelope({}) })`);
      await page.getByRole('checkbox', { name: /accord/ }).click();
      await page.getByRole('button', { name: /^Continuer/ }).click();
      await page.getByRole('button', { name: 'Confirmer le changement' }).waitFor();
      await page.getByRole('button', { name: 'Confirmer le changement' }).click();
      await page.waitForFunction(() => (window as any).fixture.writes().length === 2);
      const second = (await fx<any[]>(page, 'writes()'))[1];
      assert.equal(second.ifMatch, '"2"', `${scenario.name} : If-Match de la version relue`);
      assert.notEqual(second.body.operationId ?? second.operationId, first.body.operationId ?? first.operationId);
      assert.equal(second.body.meetingPoint, 'Parc', `${scenario.name} : la saisie part dans la commande`);
      checks.push(`#442 (trajet réel, ${scenario.name}) : refus, reprise après lecture V2, base V1 gardée ; champs conservés correctement, divergences ${scenario.conflictText ? 'signalées' : 'absentes'}, seconde commande If-Match 2 avec un autre operationId`);
      await page.close();
    }
  }

  // #442 : reprise quand la leçon remontée est déjà en V2 (la base V1 voyage avec l'intention) ; base inconnue traitée explicitement.
  if (wanted('lessonresume')) {
    const read = async (extra: string) => {
      const page = await open('lessonresume', extra);
      await page.locator('#lesson').waitFor();
      const text = await page.locator('#lesson').innerText();
      await page.close();
      return text;
    };
    const disjoint = await read('');
    assert.match(disjoint, /version:2 lieu:Parc tampon:15 motif:Demande accord:false relu:true/, disjoint);
    assert.doesNotMatch(disjoint, /l’école a aussi changé/, `modification disjointe : aucune divergence inventée (${disjoint})`);
    const common = await read('&v2=conflict');
    assert.match(common, /version:2 lieu:Parc tampon:15 .*accord:false relu:true/, common);
    assert.match(common, /probleme:.*(lieu|Lieu)/i, `conflit commun : la divergence est montrée (${common})`);
    const unknown = await read('&base=unknown&v2=conflict');
    assert.match(unknown, /lieu:Parc/, unknown);
    assert.match(unknown, /probleme:.+/, `base inconnue : écarts signalés (${unknown})`);
    console.log(JSON.stringify({ disjoint, common, unknown }));
    checks.push('#442 (reprise remontée en V2) : saisie V1 + école V2 ; disjoint = fusion sans divergence, accord à redonner ; même champ = divergence montrée ; base inconnue = écarts signalés, saisie intacte');
  }

  // #443 : CourseWorkspace réel, relecture en panne (503) puis reprise ; un retrait (401/403/404) n'est pas gardé comme une panne.
  if (wanted('reread')) {
    const draftReread = async (statusAfterFailure: number | null) => {
      const page = await open('course', '&course=draft');
      await page.getByLabel('Titre').waitFor();
      await page.getByLabel('Titre').fill('Mon titre');
      await fx(page, `serverSeries(window.fixture.draftId, { version: 2, location: 'Salle B' })`);
      await fx(page, `answer({ status: 409, body: { code: 'VERSION_CONFLICT' } })`);
      await page.getByRole('button', { name: 'Enregistrer le brouillon' }).click();
      await page.getByRole('button', { name: 'Relire, garder ma saisie' }).waitFor();
      assert.equal((await fx<any[]>(page, 'writes()'))[0].ifMatch, '"1"');
      await fx(page, `failCourseReads(${statusAfterFailure ?? 503})`);
      await page.getByRole('button', { name: 'Relire, garder ma saisie' }).click();
      return page;
    };
    // 503 : le formulaire et la cible restent, la lecture est réessayable.
    {
      const page = await draftReread(503);
      await page.getByText('Lecture du cours').waitFor();
      await page.getByText('datent d’une lecture précédente').waitFor();
      assert.equal(await page.getByLabel('Titre').inputValue(), 'Mon titre', 'la saisie survit à la panne');
      assert.equal(await ev<string>(page, 'window.flow.courseId()'), await ev<string>(page, 'window.fixture.draftId'), 'la cible reste le même cours');
      await fx(page, 'failCourseReads(null)');
      await page.getByRole('button', { name: 'Réessayer' }).click();
      await page.getByText('Lecture du cours').waitFor({ state: 'detached' });
      assert.equal(await page.getByLabel('Titre').inputValue(), 'Mon titre', 'ma saisie survit à la reprise');
      await page.waitForFunction(() => (document.querySelector('input[id*="location"]') as HTMLInputElement | null)?.value === 'Salle B', null, { timeout: 5000 }).catch(() => {});
      assert.equal(await page.getByLabel(/^Lieu/).inputValue(), 'Salle B', 'le champ changé par l’école seule est adopté');
      await fx(page, `answer({ status: 200, body: window.fixture.envelope(window.fixture.makeSeries(window.fixture.draftId, 'DRAFT', { version: 3, title: 'Mon titre', location: 'Salle B' })) })`);
      await page.getByRole('button', { name: 'Enregistrer le brouillon' }).click();
      await page.waitForFunction(() => (window as any).fixture.writes().length === 2);
      const write = (await fx<any[]>(page, 'writes()'))[1];
      assert.equal(write.ifMatch, '"2"', 'réconciliation avant écriture : If-Match de la version relue');
      assert.equal(write.body.title, 'Mon titre');
      assert.equal(write.body.location, 'Salle B');
      checks.push('#443 (CourseWorkspace réel, brouillon) : refus de version, relecture en 503, saisie et cible gardées, reprise avec V2, champ de l’école adopté, écriture If-Match 2');
      await page.close();
    }
    // Replanification d'un cours publié.
    {
      const page = await open('course', '&course=published');
      await page.getByRole('button', { name: /Gérer/ }).click();
      await page.getByRole('menuitem', { name: 'Modifier les dates' }).click();
      await page.getByRole('button', { name: /Modifier la séance 1/ }).click();
      await page.getByLabel('Date').fill('2031-05-05');
      await page.getByRole('button', { name: /Retour/ }).first().click();
      await page.getByRole('button', { name: /^Relire/ }).click();
      await fx(page, `serverSeries(window.fixture.publishedId, { version: 2, capacity: 12, remainingSeats: 12 })`);
      await fx(page, `answer({ status: 409, body: { code: 'VERSION_CONFLICT' } })`);
      await page.getByRole('button', { name: 'Enregistrer les dates' }).click();
      await page.getByRole('button', { name: 'Relire, garder mes dates' }).waitFor();
      assert.equal((await fx<any[]>(page, 'writes()'))[0].ifMatch, '"1"');
      await fx(page, 'failCourseReads(503)');
      await page.getByRole('button', { name: 'Relire, garder mes dates' }).click();
      await page.getByText('Lecture du cours').waitFor();
      assert.ok(await page.getByRole('heading', { name: 'Modifier les dates' }).isVisible(), 'la replanification reste ouverte pendant la panne');
      assert.match(await page.locator('.course-sessions').innerText(), /5 mai|05\.05|mai/i, 'la date saisie est conservée');
      await fx(page, 'failCourseReads(null)');
      await page.getByRole('button', { name: 'Réessayer' }).click();
      await page.getByText('Lecture du cours').waitFor({ state: 'detached' });
      assert.ok(await page.getByRole('heading', { name: 'Modifier les dates' }).isVisible(), 'la cible reste ouverte après la reprise');
      assert.equal(await page.getByText('Modifié ailleurs').count(), 0, 'dates de l’école inchangées : pas de conflit');
      await fx(page, `answer({ status: 200, body: window.fixture.envelope(window.fixture.makeSeries(window.fixture.publishedId, 'PUBLISHED', { version: 3 })) })`);
      await page.getByRole('button', { name: /^Relire/ }).click();
      await page.getByRole('button', { name: 'Enregistrer les dates' }).click();
      await page.waitForFunction(() => (window as any).fixture.writes().length === 2);
      assert.equal((await fx<any[]>(page, 'writes()'))[1].ifMatch, '"2"', 'réconciliation avant écriture : If-Match de la version relue');
      checks.push('#443 (CourseWorkspace réel, replanification) : refus de version, relecture en 503, dates saisies et fenêtre gardées, reprise avec V2, écriture If-Match 2');
      await page.close();
    }
    // Retrait d'accès : pas une panne temporaire, rien n'est gardé à l'écran.
    for (const status of [401, 403, 404]) {
      const page = await draftReread(status);
      await page.getByRole('button', { name: 'Réessayer' }).waitFor();
      assert.equal(await page.getByLabel('Titre').count(), 0, `${status} : le formulaire n’est pas gardé`);
      assert.equal(await page.getByText('datent d’une lecture précédente').count(), 0, `${status} : pas de données présentées comme anciennes`);
      await page.close();
    }
    checks.push('#443 (CourseWorkspace réel) : un retrait 401, 403 ou 404 remplace l’écran, aucune donnée gardée comme une panne temporaire');
  }

  // #437 : création dont la réponse se perd, confirmée plus tard par le reçu ; le formulaire se rattache et ne peut plus créer de doublon.
  if (wanted('create')) {
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
    checks.push('#437 (CourseEditor) : réponse perdue, reçu confirmé : rattaché à l’identifiant de la série créée, formulaire verrouillé, une seule écriture');
    await page.close();
  }
  if (wanted('createflow')) {
    const fill = async (page: Page) => {
      await page.getByLabel('Titre').fill('Cours synthétique');
      await page.getByLabel('Places').fill('8');
      await page.getByRole('button', { name: /Modifier la séance 1/ }).click();
      await page.getByLabel('Date').fill('2031-05-05');
      await page.getByLabel('Début').fill('09:00');
      await page.getByLabel('Fin').fill('11:00');
      await page.getByRole('button', { name: /Retour/ }).first().click();
    };
    // Reçu AP72 puis lecture de la série créée en échec : « Réessayer » relit le même identifiant, sans second POST.
    {
      const page = await open('course');
      await fill(page);
      await fx(page, `serverSeries(window.fixture.createdId, window.fixture.makeSeries(window.fixture.createdId, 'DRAFT', { title: 'Cours synthétique' }))`);
      await page.getByRole('button', { name: 'Enregistrer le brouillon' }).first().click();
      await page.waitForFunction(() => (window as any).fixture.writes().length === 1);
      await fx(page, 'failCourseReads(503)');
      await ev(page, `window.fixture.receipt({ operationId: window.fixture.writes()[0].body.operationId, commandType: 'CREATE_COURSE_SERIES', resourceType: 'CourseSeries', resourceId: window.fixture.createdId, committedAt: '2030-01-01T10:00:00Z', resourceVersion: 1 })`);
      const result = await ev<any>(page, 'window.fixture.verify()');
      assert.equal(result.status, 'confirmed', JSON.stringify(result));
      await page.getByText('Lecture du cours').waitFor();
      assert.equal(await ev<string>(page, 'window.flow.courseId()'), await ev<string>(page, 'window.fixture.createdId'), 'le workspace est passé sur la série créée');
      assert.equal(await page.getByLabel('Titre').count(), 0, 'pas de formulaire de création déverrouillé pendant la panne');
      await fx(page, 'failCourseReads(null)');
      await page.getByRole('button', { name: 'Réessayer' }).click();
      await page.getByLabel('Titre').waitFor();
      assert.equal(await page.getByLabel('Titre').inputValue(), 'Cours synthétique');
      assert.equal(await fx<number>(page, 'writes().length'), 1, 'aucun second POST');
      const gets = (await fx<string[]>(page, 'reads()')).filter(item => item.endsWith(`course-series/50000000-0000-4000-8000-0000000000c1`));
      assert.ok(gets.length >= 2, `la relecture porte sur le même identifiant (${gets.length} GET)`);
      checks.push('#437 (CourseWorkspace réel) : reçu confirmé, lecture de la série créée en 503, « Réessayer » relit le même identifiant, une seule écriture');
      await page.close();
    }
    // Réponse directe : créer puis publier. Le rattachement ne doit ni interrompre ni masquer la publication.
    {
      const page = await open('course');
      await fill(page);
      await fx(page, `serverSeries(window.fixture.createdId, window.fixture.makeSeries(window.fixture.createdId, 'DRAFT', { title: 'Cours synthétique' }))`);
      await fx(page, `answer({ status: 201, body: window.fixture.envelope(window.fixture.makeSeries(window.fixture.createdId, 'DRAFT', { title: 'Cours synthétique' })) })`);
      await fx(page, `answer({ status: 200, body: window.fixture.envelope(window.fixture.makeSeries(window.fixture.createdId, 'PUBLISHED', { version: 2, title: 'Cours synthétique' })) })`);
      await page.getByRole('button', { name: /Relire et publier/ }).click();
      await page.getByRole('button', { name: 'Publier le cours' }).click();
      await page.waitForTimeout(1500);
      const sequence = (await fx<any[]>(page, 'writes()')).map(write => `${write.method} ${write.path}`);
      const shown = await ev<string[]>(page, 'window.flow.shown()');
      const visible = await page.locator('main').innerText();
      console.log(JSON.stringify({ blocK: 'createflow-direct', sequence, shown, changed: await ev(page, 'window.flow.changed'), notice: /enregistré|publié/.exec(visible)?.[0] ?? null }));
      assert.deepEqual(sequence, ['POST course-series', `POST course-series/50000000-0000-4000-8000-0000000000c1/publish`], 'créer puis publier : deux écritures, dans l’ordre');
      assert.equal(shown.at(-1), '50000000-0000-4000-8000-0000000000c1', 'le workspace reste sur la série créée');
      assert.match(visible, /publié/, 'la suite (publication) n’est ni interrompue ni masquée');
      checks.push(`#437 (réponse directe, créer puis publier) : écritures ${sequence.join(' → ')} ; navigations ${shown.length}`);
      await page.close();
    }
  }
  console.log(JSON.stringify({ status: 'RÉUSSI', checks }, null, 2));
} finally {
  await browser.close();
  await server.close();
}
