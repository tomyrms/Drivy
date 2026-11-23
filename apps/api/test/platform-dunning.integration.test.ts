import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { addDays, zurichDay } from '../src/platform-commercial-model.js';
import { billingEnvelope } from '../src/platform-billing-contract.js';
import { commercialAlertsEnvelope, dunningPolicyEnvelope, dunningRunEnvelope, dunningViewEnvelope } from '../src/platform-dunning-contract.js';
import { schoolSubscriptionEnvelope } from '../src/school-subscription-contract.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, lessonBody, prepareCommercial, prepareSchool, seedPlatformOperator, type Call } from './support/harness.js';

/**
 * R01-T09 (#461) sur PostgreSQL réelle : politique désactivée par défaut et versionnée, rappels idempotents qui rattrapent un retard sans
 * doublon, âge de la dette gardé malgré un paiement partiel, avertissement daté avant toute suspension automatique, remise en échec qui exige
 * un opérateur, suspension distincte de l'archivage, causes PAYMENT et MANUAL levées chacune pour elle-même, exceptions motivées, pause de
 * facturation selon le contrat, blocage au serveur des engagements nouveaux, alertes de la console, fin de mois, février et fuseau de Zurich.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Aucun abonnement réel ni suspension réelle n'est activé.
 * Jeu d'essai synthétique ; aucun montant, IBAN ni identité réels (IBAN : exemple publié de la norme).
 * Jeton de recette : `Bearer <sujet>` ; `demo-*` viennent du jeu d'essai de l'API, `op-a` et `op-b` sont des opérateurs de plateforme.
 * Les passages planifiés sont simulés par `platform_dunning_run_at(jour)` ; les échéances passées sont posées déclencheurs suspendus.
 */
let pool: Pool, app: ReturnType<typeof buildApp>, context: Awaited<ReturnType<typeof prepareSchool>>;
const A = 'op-a', B = 'op-b';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};

const billingTables = 'drivy.platform_billing_issuer, drivy.platform_billing_activation, drivy.platform_invoice, drivy.platform_invoice_counter, '
  + 'drivy.platform_payment, drivy.platform_payment_allocation, drivy.platform_payment_regularization';
const dunningTables = ['platform_dunning_policy', 'platform_dunning_exception', 'platform_dunning_step', 'platform_commercial_suspension', 'platform_commercial_alert'];
beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-dunning-synthetic-secret-32-characters' });
});
beforeEach(async () => {
  await pool.query(`TRUNCATE ${billingTables}, drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation, drivy.platform_audit_event,
    drivy.platform_operator_invitation, drivy.platform_offer, drivy.platform_offer_assignment, drivy.platform_module_adjustment,
    drivy.platform_commercial_terms, drivy.platform_trial_change, drivy.platform_paid_start, drivy.platform_commercial_request,
    drivy.platform_termination_decision, drivy.platform_commercial_notice, ${dunningTables.map(table => `drivy.${table}`).join(', ')} CASCADE`);
  // La migration pose la politique désactivée ; la vider avec les opérateurs exige de la remettre telle quelle.
  await pool.query('INSERT INTO drivy.platform_dunning_policy DEFAULT VALUES ON CONFLICT (singleton) DO NOTHING');
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
  context = await prepareSchool(pool);
});
afterAll(async () => { await app?.close(); await pool?.end(); });

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH';
interface Options { body?: Record<string, unknown>; version?: number | null }
interface Reply { statusCode: number; body: string; json: () => any }
const call = (subject: string | null, method: Method, url: string, options: Options = {}) => app.inject({
  method, url, headers: {
    ...(subject ? { authorization: `Bearer ${subject}` } : {}),
    ...(options.body?.operationId ? { 'idempotency-key': String(options.body.operationId) } : {}),
    ...(options.version ? { 'if-match': `"${options.version}"` } : {}),
  },
  ...(options.body ? { payload: options.body } : {}),
}) as unknown as Promise<Reply>;
/** Même forme que l'appel du harnais, pour réutiliser ses préparations d'agenda : route relative à l'école A, moniteur par défaut. */
const schoolCall: Call = (method, route, body, version, subject = 'demo-instructor', headers = {}) => app.inject({
  method, url: route.startsWith('/v1/') ? route : `/v1/schools/${id.schoolA}${route}`,
  headers: {
    authorization: `Bearer ${subject}`,
    ...(body ? { 'idempotency-key': String(body.operationId) } : {}),
    ...(version ? { 'if-match': `"${version}"` } : {}),
    ...headers,
  },
  ...(body ? { payload: body } : {}),
}) as never;
function expectProblem(response: Reply, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  expect(response.json()).toMatchObject({ status, code });
}
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);
const journal = async (action: string) => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE action=$1 ORDER BY occurred_at,id`, [action])).rows;
const succeeded = async (action: string) => (await journal(action)).filter(entry => entry.result === 'SUCCESS');
const ownerError = async (sql: string, params: unknown[] = []) => {
  try { await pool.query(sql, params); return undefined; } catch (error) { return error as Error & { code?: string }; }
};
const today = () => zurichDay(new Date());

// --- Fiche, conditions, factures et règlements (mêmes chemins que la recette de facturation) ------------------------------------------------
const complete = { initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
const address = { billingStreet: 'Rue des Lilas 2', billingPostalCode: '1200', billingCity: 'Genève', billingCountry: 'CH' };
const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid' };
const issuerFields = {
  legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'CH', email: 'facturation@example.invalid',
  iban: 'CH93 0076 2011 6238 5295 7', taxMode: 'NONE', vatNumber: null, taxRateBp: null, pricesIncludeTax: null, taxNote: 'TVA non applicable',
};
async function schoolClient(withAddress = true, schoolId: string = id.schoolA) {
  const created = await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, ...(withAddress ? address : {}), schoolId } });
  expect(created.statusCode, created.body).toBe(201);
  return created.json().data.id as string;
}
async function commercial(clientId: string, path: string, body: Record<string, unknown> = {}) {
  const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/commercial`)).json().data.version as number;
  const response = await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial${path}`, { body: { operationId: randomUUID(), ...body }, version });
  expect(response.statusCode, response.body).toBeLessThan(300);
  return response.json().data;
}
/** Fiche payante dès aujourd'hui, avec la messagerie et les cours collectifs : la suspension doit fermer des modules réellement accordés. */
async function billableClient({ startsOn = today(), terms = complete, withAddress = true, schoolId = id.schoolA }:
  { startsOn?: string; terms?: Record<string, unknown>; withAddress?: boolean; schoolId?: string } = {}) {
  const clientId = await schoolClient(withAddress, schoolId);
  const offer = await call(A, 'POST', '/v1/platform/offers', {
    body: { operationId: randomUUID(), name: `Complète ${randomUUID().slice(0, 8)}`, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] },
  });
  expect(offer.statusCode, offer.body).toBe(201);
  const rights = (await call(A, 'GET', `/v1/platform/clients/${clientId}/entitlements`)).json().data;
  const assigned = await call(A, 'POST', `/v1/platform/clients/${clientId}/assignments`, { body: { operationId: randomUUID(), offerId: offer.json().data.id }, version: rights.version });
  expect(assigned.statusCode, assigned.body).toBe(201);
  await commercial(clientId, '/terms', terms);
  await commercial(clientId, '/paid-start', { startsOn, confirm: true });
  return clientId;
}
async function setIssuer(fields: Record<string, unknown> = issuerFields, as = A) {
  const version = (await call(as, 'GET', '/v1/platform/billing/issuer')).json().data.version as number;
  return call(as, 'POST', '/v1/platform/billing/issuer', { body: { operationId: randomUUID(), ...fields }, version });
}
async function billing(clientId: string, as = A) {
  const response = await call(as, 'GET', `/v1/platform/clients/${clientId}/billing`);
  expect(response.statusCode, response.body).toBe(200);
  expect(billingEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
async function bill(clientId: string, path: string, body: Record<string, unknown> = {}, version?: number, as = A) {
  const expected = version ?? (await billing(clientId, as)).version;
  return call(as, 'POST', `/v1/platform/clients/${clientId}${path}`, { body: { operationId: randomUUID(), ...body }, version: expected });
}
const invoiceIn = (response: Reply, pick: (invoice: any) => boolean) => {
  expect(billingEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  const found = (response.json().data.invoices as any[]).find(pick);
  expect(found, response.body).toBeDefined();
  return found;
};
async function prepared(clientId: string, body: Record<string, unknown>) {
  const response = await bill(clientId, '/invoices', body);
  expect(response.statusCode, response.body).toBe(201);
  return invoiceIn(response, invoice => invoice.status === 'DRAFT' && invoice.kind === body.kind
    && (body.periodStart ? invoice.period?.startsOn === body.periodStart : true));
}
async function issued(clientId: string, invoiceId: string) {
  const response = await bill(clientId, `/invoices/${invoiceId}/issue`, { confirm: true });
  expect(response.statusCode, response.body).toBe(200);
  return invoiceIn(response, invoice => invoice.id === invoiceId);
}
const invoices = async (clientId: string) => (await pool.query(`SELECT kind, status, number, generation, period_start::text AS period_start, net_total, total, origin
  FROM drivy.platform_invoice WHERE client_id=$1 ORDER BY number NULLS LAST, prepared_at`, [clientId])).rows;
const paymentInput = (patch: Record<string, unknown> = {}) => ({
  amount: 10_000, currency: 'CHF', receivedOn: today(), method: 'BANK_TRANSFER', reference: null, note: null, allocations: [], spread: false, confirmDuplicate: false, ...patch,
});
async function paid(clientId: string, patch: Record<string, unknown> = {}, as = A) {
  const response = await bill(clientId, '/payments', paymentInput(patch), undefined, as);
  expect(response.statusCode, response.body).toBe(201);
  expect(billingEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
/** Échéance posée dans le passé ou l'avenir, déclencheurs suspendus : seule façon de simuler une dette ancienne dans une base qui fige l'émis. */
async function setDue(invoiceId: string, dueOn: string) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    await db.query('ALTER TABLE drivy.platform_invoice DISABLE TRIGGER USER');
    await db.query('UPDATE drivy.platform_invoice SET due_on=$2::date, issued_on=least(issued_on, $2::date - 30) WHERE id=$1', [invoiceId, dueOn]);
    await db.query('ALTER TABLE drivy.platform_invoice ENABLE TRIGGER USER');
    await db.query('COMMIT');
  } catch (error) { await db.query('ROLLBACK'); throw error; } finally { db.release(); }
}
/** Montant initial émis (40 000 centimes) dont l'échéance est `dueOn`. */
async function overdueClient(dueOn: string, { terms = complete, schoolId = id.schoolA }: { terms?: Record<string, unknown>; schoolId?: string } = {}) {
  if (await count('platform_billing_issuer') === 0) expect((await setIssuer()).statusCode).toBe(201);
  const clientId = await billableClient({ terms, schoolId });
  const invoice = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
  await setDue(invoice.id, dueOn);
  return { clientId, invoiceId: invoice.id as string, number: invoice.number as string, dueOn };
}

// --- Relances : politique, passages, état recalculé ------------------------------------------------------------------------------------------
const policyDefaults = { remindersEnabled: false, autoSuspend: false, reminderDays: [3, 15, 30], suspensionMonths: 2, warningDays: 14, trialAlertDays: 7 };
async function policy(as = A) {
  const response = await call(as, 'GET', '/v1/platform/dunning/policy');
  expect(response.statusCode, response.body).toBe(200);
  expect(dunningPolicyEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
const updatePolicy = (body: Record<string, unknown>, version: number, as = A) =>
  call(as, 'POST', '/v1/platform/dunning/policy', { body: { operationId: randomUUID(), ...policyDefaults, ...body }, version });
async function setPolicy(patch: Record<string, unknown>) {
  const response = await updatePolicy(patch, (await policy()).version);
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data;
}
const enforce = () => setPolicy({ remindersEnabled: true, autoSuspend: true });
async function runAt(day: string) {
  const result = (await pool.query<{ result: any }>('SELECT drivy.platform_dunning_run_at($1::date) AS result', [day])).rows[0]!.result;
  if (!result.skipped) expect(result.failed, JSON.stringify(result)).toBe(0);
  return result;
}
const stateAt = async (clientId: string, day: string) =>
  (await pool.query<{ state: any }>('SELECT drivy.platform_dunning_state($1::uuid,$2::date) AS state', [clientId, day])).rows[0]!.state;
const monthsAfter = async (day: string, months: number) =>
  (await pool.query<{ day: string }>('SELECT drivy.platform_dunning_months_after($1::date,$2::integer)::text AS day', [day, months])).rows[0]!.day;
const paused = async (clientId: string, day = today()) =>
  (await pool.query<{ paused: boolean }>('SELECT drivy.platform_period_paused($1::uuid,$2::date) AS paused', [clientId, day])).rows[0]!.paused;

// --- Dossier d'une fiche (console) ------------------------------------------------------------------------------------------------------------
async function dunning(clientId: string) {
  const response = await call(A, 'GET', `/v1/platform/clients/${clientId}/dunning`);
  expect(response.statusCode, response.body).toBe(200);
  expect(dunningViewEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
async function dun(clientId: string, path: string, body: Record<string, unknown>, version?: number) {
  const expected = version ?? (await dunning(clientId)).version as number;
  return call(A, 'POST', `/v1/platform/clients/${clientId}/dunning${path}`, { body: { operationId: randomUUID(), ...body }, version: expected });
}
const viewOf = (response: Reply) => {
  expect(dunningViewEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
};
const suspend = (clientId: string, cause: 'PAYMENT' | 'MANUAL', reason = 'Décision de recette') => dun(clientId, '/suspensions', { cause, reason });
async function suspended(clientId: string, cause: 'PAYMENT' | 'MANUAL') {
  const response = await suspend(clientId, cause);
  expect(response.statusCode, response.body).toBe(201);
  const found = (viewOf(response).suspensions as any[]).find(item => item.cause === cause && item.status === 'ACTIVE');
  expect(found, response.body).toBeDefined();
  return found.id as string;
}
const lift = (clientId: string, suspensionId: string, reason = 'Levée de recette') => dun(clientId, `/suspensions/${suspensionId}/lift`, { reason });
const grant = (clientId: string, body: Record<string, unknown>) => dun(clientId, '/exceptions', { reason: 'Accord de recette', ...body });

// --- Lectures directes ------------------------------------------------------------------------------------------------------------------------
const alertsOf = async (clientId: string) => (await pool.query(`SELECT kind, status, resolved_cause, on_date::text AS on_date, dedupe_key
  FROM drivy.platform_commercial_alert WHERE client_id=$1 ORDER BY kind, opened_at, id`, [clientId])).rows;
const kindsOf = async (clientId: string) => (await alertsOf(clientId)).filter(alert => alert.status === 'OPEN').map(alert => alert.kind as string).sort();
const stepsOf = async (clientId: string, cycle = 0) => (await pool.query<{ step: string }>(`SELECT cycle || ':' || kind || ':' || offset_days || ':' || status AS step
  FROM drivy.platform_dunning_step WHERE client_id=$1 AND cycle=$2 ORDER BY kind, offset_days`, [clientId, cycle])).rows.map(row => row.step);
const warningOf = async (clientId: string, cycle = 0) => (await pool.query(`SELECT id, suspension_on::text AS suspension_on, recipient_count, notice_id
  FROM drivy.platform_dunning_step WHERE client_id=$1 AND cycle=$2 AND kind='WARNING'`, [clientId, cycle])).rows[0];
const suspensionsOf = async (clientId: string) => (await pool.query(`SELECT id, cause, origin, status, starts_on::text AS starts_on, lifted_on::text AS lifted_on,
  lift_cause, months FROM drivy.platform_commercial_suspension WHERE client_id=$1 ORDER BY started_at, id`, [clientId])).rows;
const noticesOf = async (clientId: string, event: string) => Number((await pool.query<{ n: string }>(
  'SELECT count(*) AS n FROM drivy.platform_commercial_notice WHERE client_id=$1 AND event=$2', [clientId, event])).rows[0]!.n);
const pushCount = async (noticeId: string) => Number((await pool.query<{ n: string }>(
  'SELECT count(*) AS n FROM drivy.push_notification WHERE commercial_notice_id=$1', [noticeId])).rows[0]!.n);
/** Échec d'envoi constaté par le service de notifications : l'avertissement n'est alors remis à personne. */
const failWarning = (stepId: string) => pool.query(`UPDATE drivy.push_notification SET status='FAILED'
  WHERE commercial_notice_id=(SELECT notice_id FROM drivy.platform_dunning_step WHERE id=$1)`, [stepId]);

// --- Côté école -------------------------------------------------------------------------------------------------------------------------------
async function subscription() {
  const response = await call('demo-admin', 'GET', `/v1/schools/${id.schoolA}/subscription`);
  expect(response.statusCode, response.body).toBe(200);
  expect(schoolSubscriptionEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response;
}
/** Droits relus par un membre quelconque (ici une élève) : c'est ce que l'iPhone et la web affichent. */
async function schoolRights() {
  const response = await call('demo-alice', 'GET', `/v1/schools/${id.schoolA}/entitlements`);
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data;
}
const newCourseType = () => call('demo-admin', 'POST', `/v1/schools/${id.schoolA}/course-types`,
  { body: { operationId: randomUUID(), title: `Type ${randomUUID().slice(0, 8)}`, description: '' } });

describe('politique', () => {
  it('désactivée par défaut, versionnée, bornée et journalisée', async () => {
    expect(await policy()).toMatchObject({ ...policyDefaults, version: 1, updatedByName: null });
    expectProblem(await updatePolicy({ autoSuspend: true }, 1), 400, 'INVALID_REQUEST');
    expectProblem(await updatePolicy({ reminderDays: [15, 3] }, 1), 400, 'INVALID_REQUEST');
    const updated = await updatePolicy({ remindersEnabled: true, reminderDays: [5, 20], warningDays: 10 }, 1);
    expect(updated.statusCode, updated.body).toBe(200);
    expect(dunningPolicyEnvelope.safeParse(updated.json()).success, updated.body).toBe(true);
    expect(updated.json().data).toMatchObject({
      remindersEnabled: true, autoSuspend: false, reminderDays: [5, 20], warningDays: 10, version: 2, updatedByName: 'Camille Exemple',
    });
    expectProblem(await updatePolicy({ remindersEnabled: false }, 1, B), 412, 'VERSION_CONFLICT');
    expect((await policy(B)).version).toBe(2);
    expect(await succeeded('UPDATE_DUNNING_POLICY')).toHaveLength(1);
  });
});

describe('accès', () => {
  it('seul un opérateur lit et commande les relances ; une école n’y accède jamais', async () => {
    const clientId = await schoolClient();
    for (const url of ['/v1/platform/dunning/policy', '/v1/platform/commercial-alerts', `/v1/platform/clients/${clientId}/dunning`])
      expectProblem(await call('demo-admin', 'GET', url), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expectProblem(await call('demo-admin', 'POST', '/v1/platform/dunning/run', { body: { operationId: randomUUID() } }), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expectProblem(await call(null, 'GET', '/v1/platform/dunning/policy'), 401, 'AUTHENTICATION_REQUIRED');
    expectProblem(await call(A, 'GET', `/v1/platform/clients/${randomUUID()}/dunning`), 404, 'NOT_FOUND');
    expect(await succeeded('RUN_DUNNING')).toHaveLength(0);
  });
});

describe('dates', () => {
  it('un mois plus tard reste dans le mois suivant : fin de mois, février et année bissextile', async () => {
    expect(await monthsAfter('2026-01-31', 1)).toBe('2026-02-28');
    expect(await monthsAfter('2026-08-31', 1)).toBe('2026-09-30');
    expect(await monthsAfter('2026-12-31', 2)).toBe('2027-02-28');
    expect(await monthsAfter('2027-12-31', 2)).toBe('2028-02-29');
    const { clientId, invoiceId } = await overdueClient('2025-12-31');
    expect(await stateAt(clientId, '2026-03-01')).toMatchObject({
      overdue: true, dueOn: '2025-12-31', months: 2, baseOn: '2026-02-28', warningOn: '2026-03-01', suspensionOn: '2026-03-15', suspensionDue: false,
    });
    await setDue(invoiceId, '2027-12-31');
    expect(await stateAt(clientId, '2028-01-15')).toMatchObject({ baseOn: '2028-02-29', warningOn: '2028-02-15', suspensionOn: '2028-02-29', suspensionDue: false });
    // Sans avertissement remis, la suspension ne tombe jamais moins de quatorze jours après l'annonce : le 29 février ne suffit plus.
    expect(await stateAt(clientId, '2028-02-29')).toMatchObject({ warningOn: '2028-02-29', suspensionOn: '2028-03-14', suspensionDue: false });
    await enforce();
    expect(await runAt('2028-02-15')).toMatchObject({ skipped: false, warnings: 1, suspended: 0 });
    expect((await warningOf(clientId))?.suspension_on).toBe('2028-02-29');
    expect(await stateAt(clientId, '2028-02-29')).toMatchObject({ suspensionOn: '2028-02-29', suspensionDue: true });
  });

  it('le jour est celui de Zurich : fin d’essai annoncée sept jours avant, constatée le lendemain', async () => {
    expect(zurichDay(new Date('2026-11-23T23:30:00.000Z'))).toBe('2026-11-24');
    expect(zurichDay(new Date('2026-06-30T22:30:00.000Z'))).toBe('2026-07-01');
    expect((await pool.query<{ day: string }>('SELECT drivy.zurich_today()::text AS day')).rows[0]!.day).toBe(today());
    const clientId = await schoolClient();
    // 23 h 30 UTC est déjà le lendemain à Zurich, en hiver comme en été : c'est ce jour-là le dernier de l'essai.
    const lastUtcDay = addDays(today(), 20), end = addDays(lastUtcDay, 1);
    await commercial(clientId, '/trial/start', { endsAt: `${lastUtcDay}T23:30:00.000Z` });
    await runAt(addDays(end, -8));
    expect(await kindsOf(clientId)).toEqual([]);
    await runAt(addDays(end, -7));
    expect(await kindsOf(clientId)).toEqual(['TRIAL_ENDING']);
    await runAt(end);
    expect(await kindsOf(clientId)).toEqual(['TRIAL_ENDING']);
    await runAt(addDays(end, 1));
    expect(await alertsOf(clientId)).toEqual([
      expect.objectContaining({ kind: 'TRIAL_ENDED', status: 'OPEN', on_date: end }),
      expect.objectContaining({ kind: 'TRIAL_ENDING', status: 'RESOLVED', resolved_cause: 'OBSOLETE', on_date: end }),
    ]);
  });
});

describe('relances', () => {
  it('un paiement partiel ne remet pas l’âge de la dette à zéro ; le solde ferme l’alerte', async () => {
    const T = today(), due = addDays(T, -40);
    const { clientId, invoiceId } = await overdueClient(due);
    await paid(clientId, { amount: 10_000, allocations: [{ invoiceId, amount: 10_000 }] });
    expect(await stateAt(clientId, T)).toMatchObject({ overdue: true, invoiceId, dueOn: due, daysLate: 40, balance: 30_000, baseOn: await monthsAfter(due, 2) });
    await runAt(T);
    expect(await kindsOf(clientId)).toEqual(['NEW_OVERDUE']);
    await paid(clientId, { amount: 30_000, allocations: [{ invoiceId, amount: 30_000 }] });
    await runAt(T);
    expect(await alertsOf(clientId)).toEqual([expect.objectContaining({ kind: 'NEW_OVERDUE', status: 'RESOLVED', resolved_cause: 'OBSOLETE' })]);
    expect(await stateAt(clientId, T)).toMatchObject({ overdue: false, daysLate: 0 });
  });

  it('un rappel par palier, jamais deux, même relancé ou concurrent ; un retard rattrapé saute les paliers dépassés', async () => {
    await setPolicy({ remindersEnabled: true });
    const T = today();
    const { clientId } = await overdueClient(addDays(T, -20));
    expect(await runAt(T)).toMatchObject({ skipped: false, reminders: 1, warnings: 0, suspended: 0 });
    expect(await stepsOf(clientId)).toEqual(['0:REMINDER:3:SKIPPED', '0:REMINDER:15:RECORDED']);
    const recorded = (await pool.query(`SELECT recipient_count, notice_id FROM drivy.platform_dunning_step WHERE client_id=$1 AND status='RECORDED'`, [clientId])).rows[0];
    expect(recorded.recipient_count).toBeGreaterThan(0);
    expect(await pushCount(recorded.notice_id)).toBe(recorded.recipient_count);
    expect(await runAt(T)).toMatchObject({ reminders: 0 });
    const both = await Promise.all([runAt(addDays(T, 10)), runAt(addDays(T, 10))]);
    expect(both.reduce((sum, result) => sum + (result.reminders ?? 0), 0)).toBe(1);
    expect(await stepsOf(clientId)).toEqual(['0:REMINDER:3:SKIPPED', '0:REMINDER:15:RECORDED', '0:REMINDER:30:RECORDED']);
    expect(await succeeded('SEND_PAYMENT_REMINDER')).toHaveLength(2);
    expect(await noticesOf(clientId, 'PAYMENT_REMINDER')).toBe(2);
  });

  it('rappels seuls : aucune suspension sans la suspension automatique, aucune date annoncée à l’école', async () => {
    await setPolicy({ remindersEnabled: true });
    const T = today();
    const { clientId } = await overdueClient(addDays(T, -70));
    expect(await runAt(T)).toMatchObject({ reminders: 1, warnings: 0, suspended: 0 });
    expect(await runAt(addDays(T, 30))).toMatchObject({ warnings: 0, suspended: 0 });
    expect(await count('platform_dunning_step', `kind='WARNING'`)).toBe(0);
    expect(await count('platform_commercial_suspension')).toBe(0);
    expect((await subscription()).json().data.dunning).toMatchObject({ suspended: false, suspensionOn: null });
    expect((await stateAt(clientId, T)).suspensionOn).not.toBeNull();
  });
});

describe('suspension', () => {
  it('avertissement daté, suspension à la date annoncée, levée par le règlement dans la même transaction', async () => {
    await enforce();
    const T = today(), due = addDays(T, -70);
    const { clientId, invoiceId, number } = await overdueClient(due);
    expect((await newCourseType()).statusCode).toBe(201);
    expect(await runAt(T)).toMatchObject({ reminders: 1, warnings: 1, suspended: 0 });
    expect((await warningOf(clientId))?.suspension_on).toBe(addDays(T, 14));
    expect(await kindsOf(clientId)).toEqual(['NEW_OVERDUE', 'SUSPENSION_UPCOMING']);
    expect((await subscription()).json().data.dunning).toMatchObject({ suspended: false, invoiceNumber: number, dueOn: due, suspensionOn: addDays(T, 14) });
    expect(await runAt(addDays(T, 13))).toMatchObject({ reminders: 0, warnings: 0, suspended: 0 });
    const read = await call('demo-admin', 'POST', `/v1/schools/${id.schoolA}/subscription/notices/read`, { body: { operationId: randomUUID() } });
    expect(read.statusCode, read.body).toBe(200);
    expect((await stateAt(clientId, addDays(T, 14))).warningDelivery).toBe('READ');
    expect(await runAt(addDays(T, 14))).toMatchObject({ suspended: 1 });
    expect(await suspensionsOf(clientId)).toEqual([
      expect.objectContaining({ cause: 'PAYMENT', origin: 'AUTOMATIC', status: 'ACTIVE', starts_on: addDays(T, 14), months: 2 }),
    ]);
    expect((await schoolRights()).restriction).toEqual({ reason: 'SUSPENDED', closes: ['WRITE_NEW'], causes: ['PAYMENT'] });
    const refused = await newCourseType();
    expectProblem(refused, 403, 'MODULE_NOT_ENTITLED');
    expect(refused.json().title).toMatch(/suspendu/);
    expect((await subscription()).json().data.dunning).toMatchObject({ suspended: true, causes: ['PAYMENT'], since: addDays(T, 14), suspensionOn: null });
    await paid(clientId, { amount: 40_000, allocations: [{ invoiceId, amount: 40_000 }] });
    expect(await suspensionsOf(clientId)).toEqual([expect.objectContaining({ status: 'LIFTED', lift_cause: 'PAYMENT_CONFIRMED', lifted_on: addDays(T, 14) })]);
    expect(await noticesOf(clientId, 'REACTIVATED')).toBe(1);
    expect((await schoolRights()).restriction).toBeNull();
    expect((await subscription()).json().data.dunning).toBeNull();
    for (const action of ['SEND_SUSPENSION_WARNING', 'SUSPEND_SCHOOL', 'LIFT_SCHOOL_SUSPENSION'])
      expect((await succeeded(action)).filter(entry => entry.actor_kind === 'SYSTEM'), action).toHaveLength(1);
  });

  it('une remise en échec ne suspend pas : alerte, confirmation motivée par un opérateur, puis suspension', async () => {
    await enforce();
    const T = today();
    const { clientId } = await overdueClient(addDays(T, -70));
    await runAt(T);
    const warning = (await warningOf(clientId))!;
    await failWarning(warning.id);
    expect(await runAt(addDays(T, 14))).toMatchObject({ suspended: 0 });
    expect(await kindsOf(clientId)).toEqual(['DELIVERY_FAILED', 'NEW_OVERDUE']);
    expect((await stateAt(clientId, T)).warningDelivery).toBe('FAILED');
    const before = (await dunning(clientId)).version as number;
    const confirmed = await dun(clientId, `/steps/${warning.id}/confirm`, { reason: 'Remise confirmée par téléphone' }, before);
    expect(confirmed.statusCode, confirmed.body).toBe(200);
    expect((viewOf(confirmed).steps as any[]).find(step => step.id === warning.id)).toMatchObject({ delivery: 'CONFIRMED', confirmedByName: 'Camille Exemple' });
    expect(await alertsOf(clientId)).toContainEqual(expect.objectContaining({ kind: 'DELIVERY_FAILED', status: 'RESOLVED', resolved_cause: 'OBSOLETE' }));
    expectProblem(await dun(clientId, `/steps/${warning.id}/confirm`, { reason: 'Deuxième confirmation' }, before), 412, 'VERSION_CONFLICT');
    expectProblem(await dun(clientId, `/steps/${warning.id}/confirm`, { reason: 'Deuxième confirmation' }), 409, 'DUNNING_STEP_CLOSED');
    expect(await runAt(addDays(T, 14))).toMatchObject({ suspended: 1 });
  });

  it('deux causes distinctes : régler l’impayé ne lève jamais la suspension décidée pour une autre cause', async () => {
    const T = today();
    const { clientId, invoiceId } = await overdueClient(addDays(T, -70));
    const payment = await suspended(clientId, 'PAYMENT');
    const manual = await suspended(clientId, 'MANUAL');
    expectProblem(await suspend(clientId, 'MANUAL'), 409, 'SUSPENSION_ACTIVE');
    expect((await schoolRights()).restriction).toMatchObject({ reason: 'SUSPENDED', causes: ['MANUAL', 'PAYMENT'] });
    expectProblem(await lift(clientId, payment), 409, 'SUSPENSION_DEBT_REMAINING');
    await paid(clientId, { amount: 40_000, allocations: [{ invoiceId, amount: 40_000 }] });
    expect(await suspensionsOf(clientId)).toEqual([
      expect.objectContaining({ id: payment, status: 'LIFTED', lift_cause: 'PAYMENT_CONFIRMED' }),
      expect.objectContaining({ id: manual, status: 'ACTIVE' }),
    ]);
    expect(await noticesOf(clientId, 'REACTIVATED')).toBe(0);
    expect((await schoolRights()).restriction).toMatchObject({ reason: 'SUSPENDED', causes: ['MANUAL'] });
    const lifted = await lift(clientId, manual);
    expect(lifted.statusCode, lifted.body).toBe(200);
    expect(viewOf(lifted).suspensions).toContainEqual(expect.objectContaining({ id: manual, status: 'LIFTED', liftCause: 'OPERATOR', liftedByName: 'Camille Exemple' }));
    expect(await noticesOf(clientId, 'REACTIVATED')).toBe(1);
    expect((await schoolRights()).restriction).toBeNull();
    expectProblem(await lift(clientId, manual), 409, 'SUSPENSION_LIFTED');
    expectProblem(await lift(clientId, randomUUID()), 404, 'NOT_FOUND');
    const entries = await succeeded('SUSPEND_SCHOOL');
    expect(entries).toHaveLength(2);
    expect(JSON.stringify(entries)).not.toContain('Décision de recette');
  });

  it('exception motivée : autre délai ou arrêt, une seule active, révocable, jamais une levée de dette', async () => {
    await enforce();
    const T = today(), due = addDays(T, -70);
    const { clientId } = await overdueClient(due);
    const delayed = await grant(clientId, { kind: 'DELAY', suspensionMonths: 4, endsOn: addDays(T, 60) });
    expect(delayed.statusCode, delayed.body).toBe(201);
    expect(viewOf(delayed).state).toMatchObject({ months: 4, baseOn: await monthsAfter(due, 4) });
    expectProblem(await grant(clientId, { kind: 'HOLD', endsOn: addDays(T, 10) }), 409, 'DUNNING_EXCEPTION_ACTIVE');
    expectProblem(await grant(clientId, { kind: 'DELAY', endsOn: addDays(T, 10) }), 400, 'INVALID_REQUEST');
    expectProblem(await grant(clientId, { kind: 'HOLD', endsOn: addDays(T, -1) }), 409, 'DUNNING_EXCEPTION_DATE');
    expect(await runAt(T)).toMatchObject({ reminders: 1, warnings: 0, suspended: 0 });
    expect(await stepsOf(clientId)).toEqual(['0:REMINDER:3:SKIPPED', '0:REMINDER:15:SKIPPED', '0:REMINDER:30:RECORDED']);
    expectProblem(await suspend(clientId, 'PAYMENT'), 409, 'SUSPENSION_NO_DEBT');
    const exceptionId = viewOf(delayed).exceptions[0].id as string;
    const revoked = await dun(clientId, `/exceptions/${exceptionId}/revoke`, { reason: 'Accord retiré' });
    expect(revoked.statusCode, revoked.body).toBe(200);
    expectProblem(await dun(clientId, `/exceptions/${exceptionId}/revoke`, { reason: 'Accord retiré' }), 409, 'DUNNING_EXCEPTION_CLOSED');
    const payment = await suspended(clientId, 'PAYMENT');
    const held = await grant(clientId, { kind: 'HOLD', endsOn: addDays(T, 10) });
    expect(held.statusCode, held.body).toBe(201);
    // Sous une exception active, la suspension pour impayé peut être levée ; la dette, elle, reste due.
    const lifted = await lift(clientId, payment);
    expect(lifted.statusCode, lifted.body).toBe(200);
    expect(viewOf(lifted).state).toMatchObject({ overdue: true, hold: true, cycle: 1 });
    expectProblem(await suspend(clientId, 'PAYMENT'), 409, 'SUSPENSION_HOLD');
    expect(await runAt(addDays(T, 5))).toMatchObject({ reminders: 0, warnings: 0, suspended: 0 });
    // L'arrêt échu, un nouveau cycle commence : nouveaux rappels et nouvel avertissement, jamais une suspension sans lui.
    expect(await runAt(addDays(T, 11))).toMatchObject({ reminders: 1, warnings: 1, suspended: 0 });
    expect(await stepsOf(clientId, 1)).toEqual(['1:REMINDER:3:SKIPPED', '1:REMINDER:15:SKIPPED', '1:REMINDER:30:RECORDED', '1:WARNING:0:RECORDED']);
    expect((await warningOf(clientId, 1))?.suspension_on).toBe(addDays(T, 25));
    expect(((await dunning(clientId)).exceptions as any[]).map(item => item.status)).toEqual(['EXPIRED', 'REVOKED']);
  });

  it('suspendre n’archive pas, et une école archivée n’est ni suspendue ni avertie', async () => {
    const T = today();
    const { clientId } = await overdueClient(addDays(T, -70));
    const manual = await suspended(clientId, 'MANUAL');
    expect((await pool.query('SELECT status FROM drivy.school WHERE id=$1', [id.schoolA])).rows[0].status).toBe('ACTIVE');
    expect((await lift(clientId, manual)).statusCode).toBe(200);
    await pool.query(`UPDATE drivy.school SET status='ARCHIVED' WHERE id=$1`, [id.schoolA]);
    expectProblem(await suspend(clientId, 'MANUAL'), 409, 'SCHOOL_ARCHIVED');
    expectProblem(await suspend(clientId, 'PAYMENT'), 409, 'SCHOOL_ARCHIVED');
    // Palier unique au-delà du retard : seul l'avertissement et la suspension sont en jeu ici.
    await setPolicy({ remindersEnabled: true, autoSuspend: true, reminderDays: [80] });
    expect(await runAt(T)).toMatchObject({ reminders: 0, warnings: 0, suspended: 0 });
    expect(await count('platform_dunning_step')).toBe(0);
  });

  it('pause de facturation selon le contrat : aucune période préparée pendant la suspension, l’émis intact', async () => {
    expect((await setIssuer()).statusCode).toBe(201);
    const clientId = await billableClient({ terms: { ...complete, suspensionBilling: 'PAUSE' } });
    await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    expect(await paused(clientId)).toBe(false);
    const manual = await suspended(clientId, 'MANUAL');
    expect(await paused(clientId)).toBe(true);
    const before = await invoices(clientId);
    expectProblem(await bill(clientId, '/invoices', { kind: 'PERIOD', periodStart: today() }), 409, 'INVOICE_PERIOD_PAUSED');
    expect(await invoices(clientId)).toEqual(before);
    expect((await lift(clientId, manual)).statusCode).toBe(200);
    expect(await paused(clientId)).toBe(false);
    expect(await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).toMatchObject({ status: 'DRAFT', kind: 'PERIOD' });
    // Un contrat qui continue la facturation n'est jamais mis en pause par une suspension.
    const other = await billableClient({ schoolId: id.schoolB });
    await suspended(other, 'MANUAL');
    expect(await paused(other)).toBe(false);
  });

  it('suspendue, l’école ne prend aucun engagement nouveau mais consulte et termine ce qui est pris', async () => {
    const setup = await prepareCommercial(schoolCall);
    const clientId = await billableClient();
    const first = await schoolCall('POST', '/lessons', lessonBody(setup, context.policy, 1));
    expect(first.statusCode, first.body).toBe(201);
    const lesson = first.json().data;
    const manual = await suspended(clientId, 'MANUAL');
    const refused = await schoolCall('POST', '/lessons', lessonBody(setup, context.policy, 2));
    expect(refused.statusCode, refused.body).toBe(403);
    expect(refused.json()).toMatchObject({ code: 'MODULE_NOT_ENTITLED' });
    expect(refused.json().title).toMatch(/suspendu/);
    expect((await schoolCall('GET', `/lessons/${lesson.id}`)).statusCode).toBe(200);
    const cancelled = await schoolCall('POST', `/lessons/${lesson.id}/cancel`, { operationId: randomUUID(), reasonCode: 'OTHER', comment: 'Recette' }, lesson.version, 'demo-admin');
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(cancelled.json().data.status).toBe('CANCELLED');
    expect((await lift(clientId, manual)).statusCode).toBe(200);
    const after = await schoolCall('POST', '/lessons', lessonBody(setup, context.policy, 3));
    expect(after.statusCode, after.body).toBe(201);
  });
});

describe('console et école', () => {
  it('alertes : lues par un opérateur, prises en compte une fois, jamais rouvertes par un passage', async () => {
    const due = addDays(today(), -40);
    const { clientId, number } = await overdueClient(due);
    await runAt(today());
    const listed = await call(A, 'GET', '/v1/platform/commercial-alerts');
    expect(listed.statusCode, listed.body).toBe(200);
    expect(commercialAlertsEnvelope.safeParse(listed.json()).success, listed.body).toBe(true);
    const [alert] = listed.json().data.items;
    expect(alert).toMatchObject({ clientId, clientName: fiche.displayName, kind: 'NEW_OVERDUE', invoiceNumber: number, onDate: due });
    const acknowledged = await call(A, 'POST', `/v1/platform/commercial-alerts/${alert.id}/acknowledge`, { body: { operationId: randomUUID() } });
    expect(acknowledged.statusCode, acknowledged.body).toBe(200);
    expect(acknowledged.json().data.items).toEqual([]);
    expect(await alertsOf(clientId)).toEqual([expect.objectContaining({ kind: 'NEW_OVERDUE', status: 'RESOLVED', resolved_cause: 'OPERATOR' })]);
    expectProblem(await call(A, 'POST', `/v1/platform/commercial-alerts/${alert.id}/acknowledge`, { body: { operationId: randomUUID() } }), 409, 'ALERT_CLOSED');
    await runAt(today());
    expect(await kindsOf(clientId)).toEqual([]);
    const run = await call(A, 'POST', '/v1/platform/dunning/run', { body: { operationId: randomUUID() } });
    expect(run.statusCode, run.body).toBe(200);
    expect(dunningRunEnvelope.safeParse(run.json()).success, run.body).toBe(true);
    expect(run.json().data).toMatchObject({ skipped: false, failed: 0 });
    expect(await succeeded('RUN_DUNNING')).toHaveLength(1);
    expect(await succeeded('ACKNOWLEDGE_COMMERCIAL_ALERT')).toHaveLength(1);
  });

  it('l’école voit la facture, l’échéance et le reste dû, sans motif, auteur ni exception', async () => {
    const T = today(), due = addDays(T, -20);
    const { clientId, invoiceId, number } = await overdueClient(due);
    expect((await subscription()).json().data.dunning).toEqual({
      suspended: false, causes: [], since: null, invoiceNumber: number, dueOn: due, balance: 40_000, suspensionOn: null,
    });
    const held = await grant(clientId, { kind: 'HOLD', endsOn: addDays(T, 30), reason: 'Motif confidentiel de recette' });
    expect(held.statusCode, held.body).toBe(201);
    expect((await subscription()).body).not.toMatch(/confidentiel|"HOLD"|exceptionId/);
    const exceptionId = viewOf(held).exceptions[0].id as string;
    expect((await dun(clientId, `/exceptions/${exceptionId}/revoke`, { reason: 'Fin de recette' })).statusCode).toBe(200);
    await enforce();
    await runAt(T);
    expect((await subscription()).json().data.notices).toContainEqual(expect.objectContaining({ event: 'PAYMENT_REMINDER', requestId: null }));
    await paid(clientId, { amount: 40_000, allocations: [{ invoiceId, amount: 40_000 }] });
    expect((await subscription()).json().data.dunning).toBeNull();
  });
});

describe('garde-fous', () => {
  it('tables fermées à l’application et au service, suspension figée, politique cohérente', async () => {
    const security = (await pool.query(`SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname::text = ANY($1::text[]) ORDER BY relname`, [dunningTables])).rows;
    expect(security).toHaveLength(dunningTables.length);
    for (const row of security) expect(row, row.relname).toMatchObject({ relrowsecurity: true, relforcerowsecurity: true });
    for (const table of dunningTables) {
      const db = await pool.connect();
      try {
        await db.query('BEGIN');
        await db.query('SET LOCAL ROLE drivy_app');
        await expect(db.query(`SELECT * FROM drivy.${table}`), table).rejects.toThrow(/permission denied/);
      } finally { await db.query('ROLLBACK'); db.release(); }
    }
    const clientId = await schoolClient();
    const manual = await suspended(clientId, 'MANUAL');
    expect((await ownerError('DELETE FROM drivy.platform_commercial_suspension WHERE id=$1', [manual]))?.message).toMatch(/platform_suspension_fixed/);
    expect((await ownerError(`UPDATE drivy.platform_commercial_suspension SET reason='Motif réécrit' WHERE id=$1`, [manual]))?.message).toMatch(/platform_suspension_fixed/);
    expect((await ownerError('UPDATE drivy.platform_dunning_policy SET auto_suspend=true, reminders_enabled=false'))?.code).toBe('23514');
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query('SET LOCAL ROLE drivy_billing_worker');
      expect((await db.query<{ result: any }>('SELECT drivy.platform_dunning_run() AS result')).rows[0]!.result).toMatchObject({ skipped: false, failed: 0 });
      await expect(db.query('SELECT * FROM drivy.platform_commercial_suspension')).rejects.toThrow(/permission denied/);
    } finally { await db.query('ROLLBACK'); db.release(); }
  });
});
