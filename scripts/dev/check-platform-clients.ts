/**
 * Écoles clientes de la console des opérateurs, de bout en bout sur la chaîne réelle : navigateur → BFF → API → PostgreSQL avec RLS.
 * Appelée par la recette d'ouverture d'école une fois l'école créée par un code : l'opérateur la retrouve depuis la console, avec son contact
 * et sa progression, sans contenu pédagogique ; il crée ensuite une fiche et un code depuis l'interface, puis le révoque.
 * Comptes et adresses synthétiques, aucun code dans un artefact : seuls des contrôles nommés rejoignent le résultat.
 */
import type { Pool } from 'pg';
import type { Page } from '../../infra/dev/browser.js';

export async function verifyPlatformClients(options: {
  origin: string; administration: Pool; operatorPage: Page; school: { id: string; name: string };
  assert: (value: unknown, label: string) => void; setStage: (value: string) => void;
}): Promise<void> {
  const { origin, administration, operatorPage: page, school, assert, setStage } = options;
  const step = (detail: string) => setStage(`écoles clientes · ${detail}`);
  const count = async (sql: string, params: unknown[] = []) => (await administration.query(sql, params)).rows[0].n as number;
  const search = async (text: string) => {
    await page.getByLabel('Rechercher une école', { exact: true }).fill(text);
    await page.getByRole('button', { name: 'Rechercher', exact: true }).click();
  };
  const openingCode = /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/;

  step('annuaire : l’école ouverte par un code est retrouvée');
  await page.goto(`${origin}/app/plateforme`);
  await page.getByRole('heading', { name: 'Plateforme', level: 1, exact: true }).waitFor();
  assert(await page.getByRole('tab', { name: 'Écoles', exact: true }).getAttribute('aria-selected') === 'true', 'La console s’ouvre sur les écoles clientes');
  await page.getByRole('list', { name: 'Écoles clientes' }).waitFor();
  await search('Recette');
  await page.getByText('1 sur 1 école', { exact: true }).waitFor();
  await page.getByRole('list', { name: 'Écoles clientes' }).getByRole('button').first().click();
  const facts = page.locator('dl.platform-facts');
  await facts.waitFor();
  const factsText = await facts.innerText();
  assert(factsText.includes('Ouverte avec un code') && factsText.includes(school.name) && factsText.includes('Non configurée') && factsText.includes('Aucune'),
    'La fiche montre l’école, son ouverture par un code et l’offre et les échéances seulement réservées');
  assert(!/élève|trajet|message|dossier/i.test(factsText), 'La fiche ne montre aucun contenu pédagogique');

  step('annuaire : liaison unique en base');
  const linked = (await administration.query(
    `SELECT c.id, c.school_id, c.link_source, c.commercial_state, c.opened_via_link_id, c.first_admin_membership_id, c.version, m.school_id AS member_school, m.roles
       FROM drivy.platform_client c LEFT JOIN drivy.membership m ON m.id = c.first_admin_membership_id`)).rows;
  assert(linked.length === 1 && linked[0].school_id === school.id && linked[0].link_source === 'OPENING_CODE' && linked[0].commercial_state === 'NOT_CONFIGURED'
    && linked[0].member_school === school.id && (linked[0].roles as string[]).includes('ADMIN') && linked[0].opened_via_link_id !== null,
    'L’ouverture par le code relie une seule fois l’école, son premier administrateur et le code à une fiche, sans état commercial');
  assert(await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='SCHOOL_OPENED_FROM_CODE' AND result='SUCCESS' AND actor_kind='SYSTEM' AND school_id=$1", [school.id]) === 1,
    'L’ouverture est au journal commercial, rattachée à l’école');
  assert(await count("SELECT count(*)::int AS n FROM drivy.school_opening_link WHERE status='USED' AND client_id=$1", [linked[0].id]) === 1,
    'Le code utilisé est rattaché à la fiche de l’école');

  step('annuaire : le code utilisé se suit depuis la fiche');
  await page.getByRole('heading', { name: 'Codes d’ouverture' }).waitFor();
  await page.getByText('Utilisé', { exact: true }).first().waitFor();
  assert(await page.getByRole('button', { name: 'Créer un code', exact: true }).count() === 0
    && await page.getByRole('button', { name: 'Rattacher une école', exact: true }).count() === 0,
    'Une école déjà ouverte ne reçoit ni nouveau code ni rattachement');
  await page.getByRole('button', { name: 'Écoles', exact: true }).click();

  step('création d’un code depuis l’interface');
  await page.getByRole('list', { name: 'Écoles clientes' }).waitFor();
  const before = await count('SELECT count(*)::int AS n FROM drivy.platform_client');
  await page.getByRole('button', { name: 'Créer un code', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nom de l’école', { exact: true }).fill('Auto-école Courrier · synthétique');
  await dialog.getByRole('button', { name: 'Créer le code', exact: true }).click();
  await dialog.getByText('Code à transmettre').waitFor();
  const code = await dialog.getByLabel('Code d’ouverture', { exact: true }).inputValue();
  const link = await dialog.getByLabel('Lien d’ouverture', { exact: true }).inputValue();
  assert(openingCode.test(code) && new URL(link).pathname === '/app/ouvrir' && new URL(link).hash === `#token=${code}` && !new URL(link).search,
    'Le code créé depuis la console est court et lisible, le lien le porte dans le fragment seulement');
  const created = (await administration.query(
    "SELECT c.id, l.status, l.expires_at > now() AS valid, l.issued_by_operator_id IS NOT NULL AS issued FROM drivy.platform_client c JOIN drivy.school_opening_link l ON l.client_id = c.id WHERE c.display_name = $1",
    ['Auto-école Courrier · synthétique'])).rows;
  assert(await count('SELECT count(*)::int AS n FROM drivy.platform_client') === before + 1 && created.length === 1
    && created[0].status === 'AVAILABLE' && created[0].valid === true && created[0].issued === true,
    'Créer un code crée la fiche et un seul code disponible, rattaché à l’opérateur émetteur, sans créer d’école');
  assert(await count('SELECT count(*)::int AS n FROM drivy.school') === 1, 'Créer un code ne crée aucune école');
  await dialog.getByRole('button', { name: 'J’ai transmis le code', exact: true }).click();
  await dialog.waitFor({ state: 'hidden' });
  assert(!(await page.locator('body').innerText()).includes(code), 'Le code n’est plus à l’écran une fois confié');

  step('aucune table de la plateforme ne retient le code');
  let found = 0;
  for (const table of ['platform_client', 'platform_audit_event', 'platform_operation', 'school_opening_link'])
    found += await count(`SELECT count(*)::int AS n FROM drivy.${table} x WHERE x::text LIKE '%'||$1::text||'%'`, [code]);
  assert(found === 0, 'Le code d’ouverture n’est écrit ni sur la fiche, ni dans le code, ni dans le journal, ni dans les reçus');
  assert(await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='CREATE_SCHOOL_OPENING_CODE' AND result='SUCCESS'") === 1,
    'La création du code est au journal commercial');

  step('révocation depuis la fiche');
  await search('Courrier');
  await page.getByText('1 sur 1 école', { exact: true }).waitFor();
  await page.getByRole('list', { name: 'Écoles clientes' }).getByRole('button').first().click();
  await page.getByRole('heading', { name: 'Codes d’ouverture' }).waitFor();
  await page.getByText('Disponible', { exact: true }).waitFor();
  await page.getByRole('button', { name: /^Révoquer le code créé le/ }).click();
  await page.getByText('Révoqué', { exact: true }).waitFor();
  assert(await count("SELECT count(*)::int AS n FROM drivy.school_opening_link WHERE client_id=$1 AND status='REVOKED'", [created[0].id]) === 1
    && await count("SELECT count(*)::int AS n FROM drivy.platform_audit_event WHERE action='REVOKE_SCHOOL_OPENING_CODE' AND result='SUCCESS'") === 1,
    'La révocation ferme le code en base et s’écrit au journal');
  await page.getByRole('button', { name: 'Créer un code', exact: true }).waitFor();
  assert(await page.getByRole('button', { name: 'Créer un code', exact: true }).count() === 1,
    'Une fiche sans école dont le code est révoqué propose de nouveau « Créer un code »');
  await page.getByRole('button', { name: 'Écoles', exact: true }).click();
  await page.getByRole('list', { name: 'Écoles clientes' }).waitFor();
}
