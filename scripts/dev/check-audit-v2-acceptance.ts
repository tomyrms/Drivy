/** Audit acceptance additions using the real Keycloak/BFF/API/PostgreSQL recipe. No password recovery. */
import { z } from 'zod';
import type { Browser } from '../../infra/dev/browser.js';
type BrowserContext = Awaited<ReturnType<Browser['newContext']>>;
type Page = Awaited<ReturnType<BrowserContext['newPage']>>;

export async function verifyAuditV2(options: {
  page: Page; context: BrowserContext; origin: string; keycloakOrigin: string; schoolId: string;
  operatorPassword: string; consumerPassword: string;
  assert: (value: unknown, label: string) => void; setStage: (value: string) => void;
}) {
  const { page, context, origin, keycloakOrigin, schoolId, operatorPassword, consumerPassword, assert, setStage } = options;
  const me = async () => {
    const response = await context.request.get(`${origin}/app/bff/me`);
    if (!response.ok()) throw new Error('AUDIT_IDENTITY_UNAVAILABLE');
    return z.object({ data: z.object({ personId: z.uuid() }) }).parse(await response.json()).data.personId;
  };
  const originalPerson = await me();
  const sessionCookie = async () => (await context.cookies(origin)).find(cookie => cookie.name === 'drivy-dev-session')?.value;
  async function stepUp(username: string, password: string, rejected: boolean) {
    setStage(`audit V2 step-up : démarrer la transaction (${rejected ? 'autre compte' : 'même compte'})`);
    const originalCookie = await sessionCookie();
    if (!originalCookie) throw new Error('AUDIT_SESSION_COOKIE_REQUIRED');
    const session = await context.request.get(`${origin}/app/bff/session`);
    const { csrfToken } = z.object({ csrfToken: z.string() }).parse(await session.json());
    const begin = await context.request.post(`${origin}/app/bff/login`, {
      headers: { Origin: origin, 'X-CSRF-Token': csrfToken },
      data: { reauthenticate: true, returnTo: `/app/gestion/${schoolId}/equipe` },
    });
    if (!begin.ok()) throw new Error('AUDIT_STEP_UP_START_FAILED');
    const { url } = z.object({ url: z.url() }).parse(await begin.json());
    // Only the provider's cookies are removed to exercise its ordinary account-choice form.
    // The original BFF session and its transaction cookie stay untouched.
    for (const cookie of await context.cookies()) if (cookie.domain === new URL(keycloakOrigin).hostname && cookie.path.startsWith('/realms/')) {
      await context.clearCookies({ name: cookie.name, domain: cookie.domain, path: cookie.path });
    }
    setStage('audit V2 step-up : ouvrir le fournisseur');
    await page.goto(url);
    setStage('audit V2 step-up : renseigner le compte');
    await page.locator('input[name="username"]').fill(username);
    setStage('audit V2 step-up : renseigner le secret éphémère');
    await page.locator('input[name="password"]').fill(password);
    setStage('audit V2 step-up : soumettre le formulaire fournisseur');
    await page.locator('input[type="submit"],button[type="submit"]').first().click();
    setStage('audit V2 step-up : attendre le retour BFF');
    await page.waitForURL(value => value.origin === origin && (rejected ? value.searchParams.get('auth') === 'failed' : value.pathname.endsWith('/equipe')));
    const samePerson = await me() === originalPerson;
    assert(samePerson && (rejected ? await sessionCookie() === originalCookie : await sessionCookie() !== originalCookie),
      rejected ? 'Step-up réel : le compte différent est refusé et le compte initial reste connecté'
        : 'Step-up réel : le même compte est accepté avec rotation de session');
  }
  setStage('audit V2 : step-up avec un autre compte réel');
  await stepUp('operateur-recette', operatorPassword, true);
  setStage('audit V2 : step-up avec le compte initial réel');
  await stepUp('responsable-recette', consumerPassword, false);

  setStage('audit V2 : erreur GPS puis lecture réelle après reprise');
  const response = await context.request.get(`${origin}/app/bff/schools/${schoolId}/learners`);
  if (!response.ok()) throw new Error('AUDIT_LEARNERS_UNAVAILABLE');
  const learner = z.object({ data: z.object({ items: z.array(z.object({ id: z.uuid(), displayName: z.string() })) }) }).parse(await response.json()).data.items[0];
  if (!learner) throw new Error('AUDIT_LEARNER_REQUIRED');
  const endpoint = `${origin}/app/bff/schools/${schoolId}/recording-choices`;
  let reads = 0;
  await page.route(endpoint, async route => {
    reads++;
    if (reads === 1) await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ code: 'SERVICE_UNAVAILABLE' }) });
    else await route.continue();
  });
  try {
    await page.goto(`${origin}/app/gestion/${schoolId}/eleves?selection=${learner.id}`);
    await page.getByRole('heading', { name: learner.displayName, exact: true }).waitFor();
    await page.getByText('Accord GPS indisponible', { exact: true }).waitFor();
    const retry = page.waitForResponse(result => result.url() === endpoint);
    await page.getByRole('button', { name: 'Réessayer', exact: true }).click();
    const realResponse = await retry;
    await page.getByText(/^Accord GPS :/).waitFor();
    assert(realResponse.status() === 200 && reads === 2 && await page.getByText('Accord GPS indisponible', { exact: true }).count() === 0,
      'Accord GPS : panne injectée visible puis reprise vers le vrai BFF/API/PostgreSQL');
  } finally { await page.unroute(endpoint); }
}
