/** V4 acceptance through the real authenticated web/BFF/API/PostgreSQL path.
 * Only the directory outage is injected. Recovery must reach the real services.
 */
import { resolve } from 'node:path';
import type { Browser } from '../../infra/dev/browser.js';
type Context = Awaited<ReturnType<Browser['newContext']>>;
type Page = Awaited<ReturnType<Context['newPage']>>;
export async function verifyV4Web(options: {
  page: Page; schoolPath: string; bff: string; artifactDirectory: string;
  assert: (value: unknown, label: string) => void; setStage: (value: string) => void;
}) {
  const { page, bff, artifactDirectory, assert, setStage } = options;
  const agendaURL = page.url();
  setStage('V4 : recherche agenda conservée pendant une panne partielle');
  await page.getByRole('searchbox', { name: 'Élève', exact: true }).fill('Élève');
  await page.locator('.agenda-lesson').first().click();
  await page.getByRole('button', { name: 'Retour à l’agenda', exact: true }).waitFor();
  let unavailable = true;
  const directoryPath = `${new URL(bff).pathname}/learners`;
  const directoryRoute = (url: URL) => url.pathname === directoryPath;
  await page.route(directoryRoute, async route => {
    if (unavailable) await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ code: 'SERVICE_UNAVAILABLE' }) });
    else await route.continue();
  });
  try {
    const outage = page.waitForResponse(response => new URL(response.url()).pathname === directoryPath && response.status() === 503);
    await page.getByRole('button', { name: 'Retour à l’agenda', exact: true }).click();
    await outage;
    await page.getByRole('button', { name: 'Réessayer', exact: true }).waitFor();
    assert(await page.getByRole('searchbox', { name: 'Élève', exact: true }).inputValue() === 'Élève',
      'V4 agenda : la recherche conservée n’est pas effacée lors de la panne du répertoire');
    setStage('V4 : leçons masquées à tort après panne du répertoire');
    await page.locator('.list-summary').waitFor();
    await page.screenshot({ path: resolve(artifactDirectory, 'v4-agenda-directory-outage.png'), fullPage: true });
    await page.locator('.agenda-lesson').first().waitFor();
    assert(await page.locator('.agenda-lesson').count() > 0,
      'V4 agenda : la lecture réussie des leçons reste visible malgré le répertoire indisponible et la recherche conservée');
    assert(await page.getByText(/recherche.*(suspendue|indisponible|reprendra)/i).count() > 0,
      'V4 agenda : la suspension temporaire de la recherche est explicitement expliquée');
    assert(await page.getByRole('heading', { name: 'Aucune leçon trouvée', exact: true }).count() === 0,
      'V4 agenda : une panne de répertoire ne devient pas un faux résultat vide');
    for (const width of [320, 390, 768, 1024, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.screenshot({ path: resolve(artifactDirectory, `v4-agenda-partial-${width}.png`), fullPage: true });
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
        `V4 agenda : état partiel connecté sans débordement à ${width}px`);
    }
    unavailable = false;
    const recovered = page.waitForResponse(response => new URL(response.url()).pathname === directoryPath && response.status() === 200);
    await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
    await recovered;
    await page.locator('.agenda-lesson').filter({ hasText: 'Élève Première leçon' }).waitFor();
    assert(await page.getByRole('searchbox', { name: 'Élève', exact: true }).inputValue() === 'Élève',
      'V4 agenda : la reprise réelle du répertoire réapplique la recherche sans perdre la saisie');
  } finally { await page.unroute(directoryRoute); }

  setStage('V4 : critères du vide filtré et réinitialisation des élèves');
  await page.locator('.agenda-lesson').first().click();
  await page.getByRole('button', { name: 'Tous les élèves', exact: true }).click();
  const search = page.getByRole('searchbox', { name: 'Rechercher un élève', exact: true });
  await search.fill('V4-introuvable');
  await page.getByLabel('Profil', { exact: true }).click();
  await page.getByRole('option', { name: 'À compléter', exact: true }).click();
  await page.getByRole('heading', { name: 'Aucun élève trouvé', exact: true }).waitFor();
  const empty = page.locator('.empty-state');
  assert((await empty.innerText()).includes('V4-introuvable') && /compléter/i.test(await empty.innerText()),
    'V4 élèves : le résultat vide nomme la recherche et le filtre de profil réellement actifs');
  for (const width of [320, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.screenshot({ path: resolve(artifactDirectory, `v4-learners-empty-${width}.png`), fullPage: true });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      `V4 élèves : critères de recherche vides lisibles sans débordement à ${width}px`);
  }
  await page.getByRole('button', { name: 'Réinitialiser les filtres', exact: true }).click();
  await page.getByRole('link', { name: /Élève Première leçon/ }).first().waitFor();
  assert(await search.inputValue() === '', 'V4 élèves : Réinitialiser restaure le dossier réel et efface les critères');
  await page.goto(agendaURL);
  await page.getByRole('heading', { name: 'Agenda', exact: true }).waitFor();
}
