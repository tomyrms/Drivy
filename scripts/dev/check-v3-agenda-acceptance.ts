/** Real authenticated browser -> BFF -> API -> PostgreSQL agenda acceptance. */
import { resolve } from 'node:path';
import type { Browser } from '../../infra/dev/browser.js';
type Context = Awaited<ReturnType<Browser['newContext']>>;
type Page = Awaited<ReturnType<Context['newPage']>>;
export async function verifyV3Agenda(options: {
  page: Page; schoolPath: string; bff: string; civilDay: string; instructorId: string; instructorName: string;
  artifactDirectory: string; assert: (value: unknown, label: string) => void; setStage: (value: string) => void;
}) {
  const { page, schoolPath, bff, civilDay, instructorId, instructorName, artifactDirectory, assert, setStage } = options;
  setStage('V3 : accès direct à une semaine avec BFF/API/PostgreSQL réels');
  await page.getByLabel('Moniteur', { exact: true }).click();
  await page.getByRole('option', { name: instructorName, exact: true }).click();
  await page.getByRole('searchbox', { name: 'Élève', exact: true }).fill('Élève');
  const date = page.getByLabel('Aller à une date', { exact: true });
  const originalMonday = await date.inputValue();
  await date.fill('2027-02-17');
  const selected = page.waitForResponse(response => response.url().startsWith(`${bff}/lessons?`) && new URL(response.url()).searchParams.get('from') === '2027-02-14T23:00:00.000Z');
  await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
  const response = await selected;
  await page.waitForFunction(() => document.activeElement?.classList.contains('agenda-period-label'));
  assert(await page.evaluate(() => document.activeElement?.classList.contains('agenda-period-label')), 'V3 agenda : le focus clavier rejoint la semaine affichée après confirmation');
  const params = new URL(response.url()).searchParams;
  assert(response.status() === 200 && params.get('to') === '2027-02-21T23:00:00.000Z' && params.get('instructorMembershipId') === instructorId,
    'V3 agenda : date directe convertie en semaine Europe/Zurich, filtre moniteur conservé dans la vraie requête API');
  await page.getByText('Aucun rendez-vous cette semaine', { exact: true }).waitFor();
  assert(await page.getByRole('searchbox', { name: 'Élève', exact: true }).inputValue() === 'Élève',
    'V3 agenda : la recherche élève reste intacte après le saut de date');
  await page.goBack();
  await page.waitForFunction(value => document.querySelector<HTMLInputElement>('input[type=date]')?.value === value, originalMonday);
  await page.locator('.agenda-lesson').waitFor();
  assert(new URL(page.url()).searchParams.get('instructor') === instructorId,
    'V3 agenda : le retour navigateur restaure la semaine et sa vraie leçon sans perdre le moniteur');
  await date.fill('2027-02-17');
  await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
  await page.waitForFunction(() => new URL(location.href).searchParams.get('week') === '2027-02-15');
  await date.fill('2026-10-25');
  const dst = page.waitForResponse(result => result.url().startsWith(`${bff}/lessons?`) && new URL(result.url()).searchParams.get('from') === '2026-10-18T22:00:00.000Z');
  await date.press('Enter');
  const dstResponse = await dst;
  assert(dstResponse.status() === 200 && new URL(dstResponse.url()).searchParams.get('to') === '2026-10-25T23:00:00.000Z',
    'V3 agenda : la semaine du changement d’heure contient bien 169 heures dans la requête réelle');

  setStage('V3 : erreur injectée sur la lecture agenda puis reprise réelle');
  let failed = false;
  const pattern = `${bff}/lessons?*`;
  await page.route(pattern, async route => {
    if (!failed) { failed = true; await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ code: 'SERVICE_UNAVAILABLE' }) }); }
    else await route.continue();
  });
  try {
    await date.fill('2027-03-17');
    await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
    await page.getByRole('button', { name: 'Réessayer', exact: true }).waitFor();
    const retry = page.waitForResponse(result => result.url().startsWith(`${bff}/lessons?`));
    await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
    assert((await retry).status() === 200 && new URL(page.url()).searchParams.get('week') === '2027-03-15',
      'V3 agenda : panne visible et reprise sur la semaine demandée vers les vrais services');
  } finally { await page.unroute(pattern); }
  await date.fill(civilDay);
  await page.getByRole('button', { name: 'Afficher la semaine', exact: true }).click();
  await page.locator('.agenda-lesson').waitFor();
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 1100 });
    await page.screenshot({ path: resolve(artifactDirectory, `v3-agenda-real-${width}.png`), fullPage: true });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      `V3 agenda : vraie leçon et commandes utilisables sans débordement à ${width}px`);
  }
  await page.reload(); await page.locator('.agenda-lesson').waitFor();
  assert(new URL(page.url()).searchParams.get('instructor') === instructorId,
    'V3 agenda : rechargement du build conserve la semaine, le moniteur et la leçon durable');
}
