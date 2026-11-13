/**
 * Console des opérateurs, de bout en bout sur la chaîne réelle : navigateur → BFF → API → PostgreSQL avec RLS.
 * Appelée par la recette d'ouverture d'école une fois l'opérateur mis en service par la voie officielle. Comptes et adresses synthétiques,
 * aucun code d'invitation ni identifiant dans un artefact : seuls des contrôles nommés rejoignent le résultat.
 */
import type { Pool } from 'pg';
import type { Browser, Page } from '../../infra/dev/browser.js';

export async function verifyPlatformTeam(options: {
  browser: Browser; origin: string; keycloakOrigin: string; administration: Pool; operatorPage: Page;
  colleague: { email: string; password: string }; invitee: { email: string; password: string };
  signIn: (page: Page, email: string, password: string) => Promise<void>;
  assert: (value: unknown, label: string) => void; setStage: (value: string) => void;
}): Promise<void> {
  const { browser, origin, keycloakOrigin, administration, operatorPage, colleague, invitee, signIn, assert, setStage } = options;
  const step = (detail: string) => setStage(`console des opérateurs · ${detail}`);
  const count = async (sql: string, params: unknown[] = []) => (await administration.query(sql, params)).rows[0].n as number;
  const opened: Array<{ close(): Promise<void> }> = [];
  /** Un navigateur propre par compte, limité aux deux origines de la recette. */
  async function signedIn(email: string, password: string, path: string) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, locale: 'fr-CH' });
    opened.push(context); context.setDefaultTimeout(20_000);
    await context.route('**/*', route => [origin, keycloakOrigin].includes(new URL(route.request().url()).origin) ? route.continue() : route.abort());
    const page = await context.newPage();
    await page.goto(`${origin}${path}`); await signIn(page, email, password);
    return { context, page };
  }
  /** Émet une invitation depuis la console et rend le code montré une seule fois. */
  async function invite(page: Page, email: string) {
    await page.getByRole('tab', { name: 'Invitations', exact: true }).click();
    await page.getByLabel('Adresse e-mail de l’invité', { exact: true }).fill(email);
    await page.getByRole('button', { name: 'Inviter', exact: true }).click();
    await page.getByText('Code à transmettre', { exact: true }).waitFor();
    const code = await page.getByLabel('Code d’accès', { exact: true }).inputValue();
    await page.getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
    await page.getByText('Code à transmettre', { exact: true }).waitFor({ state: 'hidden' });
    return code;
  }
  /** Aucune table de la plateforme ne retient un code, ni en clair ni dans un reçu ou une ligne de journal. */
  async function storedAnywhere(code: string) {
    let found = 0;
    for (const table of ['platform_operator_invitation', 'platform_audit_event', 'platform_operation'])
      found += await count(`SELECT count(*)::int AS n FROM drivy.${table} x WHERE x::text LIKE '%'||$1::text||'%'`, [code]);
    return found;
  }
  try {
    step('équipe lue en base après la mise en service');
    await operatorPage.goto(`${origin}/app/plateforme`);
    await operatorPage.getByRole('heading', { name: 'Plateforme', level: 1, exact: true }).waitFor();
    await operatorPage.getByText('Opérateur Synthétique').first().waitFor();
    assert(await operatorPage.getByText('Vous', { exact: true }).count() === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE'") === 1,
      'La console montre l’équipe lue en base, avec « Vous » sur le compte mis en service');

    step('retrait du dernier opérateur');
    await operatorPage.getByRole('button', { name: 'Me retirer de l’équipe', exact: true }).click();
    const dialog = operatorPage.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Retirer', exact: true }).click();
    await dialog.getByText('Le dernier opérateur actif ne peut pas être retiré.').waitFor();
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE'") === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='REVOKE_PLATFORM_OPERATOR' AND result='REFUSED' AND reason_code='LAST_PLATFORM_OPERATOR'") >= 1,
      'Le dernier opérateur actif ne peut pas se retirer et le refus est au journal');
    await dialog.getByRole('button', { name: 'Garder l’accès', exact: true }).click();

    step('invitation du collègue');
    const colleagueCode = await invite(operatorPage, colleague.email);
    assert(/^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/.test(colleagueCode)
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator_invitation WHERE status='AVAILABLE' AND invitee_email=$1", [colleague.email]) === 1,
      'Une invitation émise depuis la console porte un code au bon format et reste disponible en base');
    assert(await storedAnywhere(colleagueCode) === 0, 'Le code d’invitation n’est écrit ni dans l’invitation, ni dans le journal, ni dans les reçus');
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='CREATE_PLATFORM_INVITATION' AND result='SUCCESS'") === 1,
      'La création d’une invitation laisse une ligne au journal commercial');

    step('compte sans accès avant acceptation');
    const first = await signedIn(colleague.email, colleague.password, '/app/plateforme');
    await first.page.getByRole('alert').getByText('Accès refusé').waitFor();
    assert(await first.page.getByRole('tab', { name: 'Équipe', exact: true }).count() === 0
      && (await first.context.request.get(`${origin}/app/bff/platform/operators`)).status() === 403
      && (await first.context.request.get(`${origin}/app/bff/operator/school-opening-links`)).status() === 403,
      'Un compte vérifié qui n’a pas accepté de code ne lit ni l’équipe ni les liens d’ouverture');

    // Les liens de la console sont des Button Base UI rendus en <a> : Base UI leur donne role="button", donc on les trouve par leur texte.
    step('acceptation du code par un second compte · page de saisie');
    await first.page.getByText('Saisir un code d’accès', { exact: true }).click();
    await first.page.getByRole('heading', { name: 'Rejoindre la plateforme', level: 1, exact: true }).waitFor();
    step('acceptation du code par un second compte · lecture des droits');
    await first.page.getByLabel('Code d’accès', { exact: true }).fill(colleagueCode);
    await first.page.getByRole('button', { name: 'Voir les droits', exact: true }).click();
    await first.page.getByText('Droits accordés', { exact: true }).waitFor();
    await first.page.getByText('Jamais accordé', { exact: true }).waitFor();
    step('acceptation du code par un second compte · aucun accès avant confirmation');
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE'") === 1,
      'Lire les droits d’un code ne donne aucun accès avant l’acceptation');
    step('acceptation du code par un second compte · confirmation');
    await first.page.getByRole('button', { name: 'Accepter et rejoindre', exact: true }).click();
    await first.page.getByText('Vous faites partie de l’équipe', { exact: true }).waitFor();
    step('acceptation du code par un second compte · état en base');
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE' AND added_via='INVITATION' AND contact_email=$1", [colleague.email]) === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator_invitation WHERE status='USED' AND invitee_email=$1", [colleague.email]) === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='ACCEPT_PLATFORM_INVITATION' AND result='SUCCESS'") === 1,
      'L’acceptation crée un seul opérateur, ferme l’invitation et s’écrit au journal');
    step('acceptation du code par un second compte · ouverture de la console');
    await first.page.getByText('Ouvrir la console', { exact: true }).click();
    await first.page.getByRole('heading', { name: 'Plateforme', level: 1, exact: true }).waitFor();
    await first.page.getByText('Vous', { exact: true }).first().waitFor();

    step('invitation créée par le collègue');
    const orphanCode = await invite(first.page, invitee.email);
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator_invitation i JOIN drivy.platform_operator o ON o.id=i.created_by WHERE i.status='AVAILABLE' AND i.invitee_email=$1 AND o.contact_email=$2",
      [invitee.email, colleague.email]) === 1, 'Le collègue, devenu opérateur, peut inviter à son tour');

    step('retrait du collègue par l’opérateur');
    await operatorPage.goto(`${origin}/app/plateforme`);
    await operatorPage.getByRole('button', { name: /^Retirer / }).first().waitFor();
    await operatorPage.getByRole('button', { name: /^Retirer / }).first().click();
    await operatorPage.getByRole('dialog').getByRole('button', { name: 'Retirer', exact: true }).click();
    await operatorPage.getByRole('dialog').waitFor({ state: 'hidden' });
    await operatorPage.getByText('Retiré', { exact: true }).first().waitFor();
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='REVOKED' AND contact_email=$1", [colleague.email]) === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE'") === 1,
      'Le retrait révoque le collègue et laisse l’opérateur mis en service seul actif');
    await first.page.reload();
    await first.page.getByRole('alert').getByText('Accès refusé').waitFor();
    assert((await first.context.request.get(`${origin}/app/bff/platform/operators`)).status() === 403
      && (await first.context.request.get(`${origin}/app/bff/operator/school-opening-links`)).status() === 403,
      'Un opérateur retiré perd l’accès à la console et à l’ouverture d’école dès le retrait');

    step('invitation pendante du collègue retiré');
    await operatorPage.getByRole('tab', { name: 'Invitations', exact: true }).click();
    await operatorPage.getByText('Révoquée', { exact: true }).first().waitFor();
    assert(await count("SELECT count(*)::int AS n FROM drivy.platform_operator_invitation WHERE status='REVOKED' AND invitee_email=$1", [invitee.email]) === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='REVOKE_PLATFORM_OPERATOR' AND result='SUCCESS' AND (changes->>'revokedInvitations')::int=1") === 1,
      'Le retrait révoque dans la même opération les invitations pendantes du collègue et en journalise le nombre');
    step('code émis par un opérateur retiré');
    const second = await signedIn(invitee.email, invitee.password, '/app/plateforme/rejoindre');
    await second.page.getByLabel('Code d’accès', { exact: true }).fill(orphanCode);
    await second.page.getByRole('button', { name: 'Voir les droits', exact: true }).click();
    await second.page.getByText('Cette invitation a été révoquée.', { exact: false }).first().waitFor();
    assert(await second.page.getByRole('button', { name: 'Accepter et rejoindre', exact: true }).count() === 0
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE status='ACTIVE'") === 1
      && await count("SELECT count(*)::int AS n FROM drivy.platform_operator WHERE contact_email=$1", [invitee.email]) === 0,
      'Le code émis par un opérateur retiré est refusé et n’ouvre aucune entrée dans l’équipe');
  } finally {
    for (const context of opened) await context.close().catch(() => undefined);
  }
}
