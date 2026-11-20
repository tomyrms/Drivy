import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { addDays, periodIndexOf, periodStart, zurichDay } from '../src/platform-commercial-model.js';
import { billingEnvelope, billingRunEnvelope, invoiceEnvelope, invoicePageEnvelope, issuerSettingsEnvelope } from '../src/platform-billing-contract.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, prepareSchool, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T05 (#457) sur PostgreSQL réelle : émetteur versionné, brouillon puis émission figée, numérotation sans trou, avoir total et nouvelle
 * génération, annulation d'un brouillon, envoi enregistré, activation, préparation planifiée et rattrapage, isolement d'un échec,
 * concurrence, garde-fous et RLS. Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic).
 * Jeu d'essai synthétique ; aucun montant, IBAN ni identité réels (IBAN : exemple publié de la norme).
 * Jeton de recette : `Bearer <sujet>` ; `demo-*` viennent du jeu d'essai de l'API, `op-a` et `op-b` sont des opérateurs de plateforme.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const A = 'op-a', B = 'op-b';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};

const billingTables = 'drivy.platform_billing_issuer, drivy.platform_billing_activation, drivy.platform_invoice, drivy.platform_invoice_counter';
beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-billing-synthetic-secret-32-characters' });
});
beforeEach(async () => {
  await pool.query(`TRUNCATE ${billingTables}, drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation, drivy.platform_audit_event,
    drivy.platform_operator_invitation, drivy.platform_offer, drivy.platform_offer_assignment, drivy.platform_module_adjustment,
    drivy.platform_commercial_terms, drivy.platform_trial_change, drivy.platform_paid_start, drivy.platform_commercial_request CASCADE`);
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
  await prepareSchool(pool);
});
afterAll(async () => { await app?.close(); await pool?.end(); });

type Method = 'GET' | 'POST' | 'PATCH';
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
function expectProblem(response: Reply, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  expect(response.json()).toMatchObject({ status, code });
}
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);
const journal = async (action: string) => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE action=$1 ORDER BY occurred_at,id`, [action])).rows;
const ownerError = async (sql: string, params: unknown[] = []) => { try { await pool.query(sql, params); return undefined; } catch (error) { return error as Error & { code?: string }; } };

const today = () => zurichDay(new Date());
const year = () => today().slice(0, 4);
const complete = { initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
const address = { billingStreet: 'Rue des Lilas 2', billingPostalCode: '1200', billingCity: 'Genève', billingCountry: 'CH' };
const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid' };
const issuerFields = {
  legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'CH', email: 'facturation@example.invalid',
  iban: 'CH93 0076 2011 6238 5295 7', taxMode: 'NONE', vatNumber: null, taxRateBp: null, pricesIncludeTax: null, taxNote: 'TVA non applicable',
};

async function schoolClient(withAddress = true) {
  const created = await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, ...(withAddress ? address : {}), schoolId: id.schoolA } });
  expect(created.statusCode, created.body).toBe(201);
  return created.json().data.id as string;
}
async function commercial(clientId: string, path: string, body: Record<string, unknown> = {}) {
  const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/commercial`)).json().data.version as number;
  const response = await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial${path}`, { body: { operationId: randomUUID(), ...body }, version });
  expect(response.statusCode, response.body).toBeLessThan(300);
  return response.json().data;
}
/** Fiche facturable : offre en vigueur, conditions complètes, début payant confirmé (aujourd'hui par défaut). */
async function billableClient({ startsOn = today(), terms = complete, withAddress = true }: { startsOn?: string; terms?: Record<string, unknown>; withAddress?: boolean } = {}) {
  const clientId = await schoolClient(withAddress);
  const offer = await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: `Complète ${randomUUID().slice(0, 8)}`, modules: ['MESSAGING'] } });
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
/** Commande de facturation sous la version courante de la fiche (ou celle donnée). */
async function bill(clientId: string, path: string, body: Record<string, unknown> = {}, version?: number, as = A) {
  const expected = version ?? (await billing(clientId, as)).version;
  return call(as, 'POST', `/v1/platform/clients/${clientId}${path}`, { body: { operationId: randomUUID(), ...body }, version: expected });
}
async function prepared(clientId: string, body: Record<string, unknown>) {
  const response = await bill(clientId, '/invoices', body);
  expect(response.statusCode, response.body).toBe(201);
  expect(invoiceEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
async function issued(clientId: string, invoiceId: string) {
  const response = await bill(clientId, `/invoices/${invoiceId}/issue`, { confirm: true });
  expect(response.statusCode, response.body).toBe(200);
  return response.json().data;
}
const invoices = async (clientId: string) => (await pool.query(`SELECT kind, status, number, generation, period_start::text AS period_start, net_total, total, origin
  FROM drivy.platform_invoice WHERE client_id=$1 ORDER BY number NULLS LAST, prepared_at`, [clientId])).rows;
/** Recule toute la vie commerciale d'une fiche de `days` jours, déclencheurs suspendus (seule façon de simuler un passé dans une base qui le refuse). */
async function backdate(clientId: string, days: number) {
  const tables = ['platform_paid_start', 'platform_commercial_terms', 'platform_billing_activation', 'platform_offer_assignment'];
  const db = await pool.connect();
  try {
    await db.query('BEGIN');
    for (const table of tables) await db.query(`ALTER TABLE drivy.${table} DISABLE TRIGGER USER`);
    await db.query('UPDATE drivy.platform_paid_start SET starts_on=starts_on-$2::int WHERE client_id=$1', [clientId, days]);
    await db.query('UPDATE drivy.platform_commercial_terms SET effective_from=effective_from-$2::int WHERE client_id=$1', [clientId, days]);
    await db.query('UPDATE drivy.platform_billing_activation SET starts_on=starts_on-$2::int WHERE client_id=$1', [clientId, days]);
    for (const table of tables) await db.query(`ALTER TABLE drivy.${table} ENABLE TRIGGER USER`);
    await db.query('COMMIT');
  } catch (error) { await db.query('ROLLBACK'); throw error; } finally { db.release(); }
}
const runAt = async (day = today()) => (await pool.query<{ result: any }>('SELECT drivy.platform_billing_run_at($1::date) AS result', [day])).rows[0]!.result;

describe('accès', () => {
  it('seul un opérateur actif lit ou commande la facturation ; une école n’y accède jamais', async () => {
    const clientId = await schoolClient();
    for (const url of ['/v1/platform/invoices', '/v1/platform/billing/issuer', `/v1/platform/clients/${clientId}/billing`]) {
      expectProblem(await call('demo-admin', 'GET', url), 403, 'PLATFORM_OPERATOR_REQUIRED');
      expect((await call(null, 'GET', url)).statusCode).toBe(401);
    }
    expectProblem(await call('demo-admin', 'POST', '/v1/platform/billing/run', { body: { operationId: randomUUID() } }), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expectProblem(await call('demo-admin', 'POST', `/v1/platform/clients/${clientId}/invoices`, { body: { operationId: randomUUID(), kind: 'INITIAL' }, version: 1 }), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expectProblem(await call(A, 'GET', `/v1/platform/clients/${randomUUID()}/billing`), 404, 'NOT_FOUND');
    expectProblem(await call(A, 'GET', `/v1/platform/invoices/${randomUUID()}`), 404, 'NOT_FOUND');
  });
});

describe('émetteur', () => {
  it('chaque version redonne tout et ne réécrit jamais la précédente ; version périmée, rejeu, TVA incomplète ; journal sans IBAN ni adresse', async () => {
    const empty = (await call(A, 'GET', '/v1/platform/billing/issuer')).json().data;
    expect(empty).toEqual({ current: null, versions: [], version: 1 });
    const first = await setIssuer();
    expect(first.statusCode, first.body).toBe(201);
    expect(issuerSettingsEnvelope.safeParse(first.json()).success, first.body).toBe(true);
    expect(first.json().data.current).toMatchObject({ sequence: 1, iban: 'CH9300762011623852957', taxMode: 'NONE' });
    expectProblem(await call(A, 'POST', '/v1/platform/billing/issuer', { body: { operationId: randomUUID(), ...issuerFields }, version: 1 }), 412, 'VERSION_CONFLICT');
    expect((await setIssuer({ ...issuerFields, taxMode: 'VAT' })).statusCode).toBe(400);
    const vat = await setIssuer({ ...issuerFields, taxMode: 'VAT', vatNumber: 'CHE-123.456.789 TVA', taxRateBp: 810, pricesIncludeTax: false, taxNote: null });
    expect(vat.statusCode, vat.body).toBe(201);
    expect(vat.json().data.versions.map((item: { sequence: number }) => item.sequence)).toEqual([2, 1]);
    expect(await count('platform_billing_issuer')).toBe(2);
    const entries = await journal('SET_BILLING_ISSUER');
    expect(entries).toHaveLength(2);
    expect(entries[0].changes).toMatchObject({ hasIban: true, hasEmail: true });
    expect(JSON.stringify(entries)).not.toMatch(/CH93|facturation@example/);
    expect((await ownerError('UPDATE drivy.platform_billing_issuer SET city=$1', ['Ailleurs']))?.message).toMatch(/platform_issuer_fixed/);
  });
});

describe('brouillon, émission et numérotation', () => {
  it('un brouillon est calculé par la base ; l’émission exige émetteur et destinataire, puis fige numéro, échéance et montants', async () => {
    const clientId = await billableClient({ withAddress: false });
    const view = await billing(clientId);
    expect(view).toMatchObject({ billable: true, issuerReady: false, paidStartsOn: today(), initial: { net: 40_000, state: 'DUE' } });
    expect(view.periods[0]).toMatchObject({ startsOn: today(), net: 9_900, state: 'DUE' });
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    expect(draft).toMatchObject({ status: 'DRAFT', kind: 'INITIAL', origin: 'MANUAL', number: null, total: null, netTotal: 40_000, generation: 1 });
    expect(draft.lines).toEqual([expect.objectContaining({ code: 'INITIAL', label: 'Montant initial', amount: 50_000, discount: 10_000, net: 40_000 })]);
    expectProblem(await bill(clientId, '/invoices', { kind: 'INITIAL' }), 409, 'INVOICE_EXISTS');
    expectProblem(await bill(clientId, `/invoices/${draft.id}/issue`, { confirm: true }), 409, 'BILLING_ISSUER_MISSING');
    expect((await setIssuer()).statusCode).toBe(201);
    expectProblem(await bill(clientId, `/invoices/${draft.id}/issue`, { confirm: true }), 409, 'INVOICE_RECIPIENT_INCOMPLETE');
    const client = (await call(A, 'GET', `/v1/platform/clients/${clientId}`)).json().data;
    const patched = await call(A, 'PATCH', `/v1/platform/clients/${clientId}`, { body: { operationId: randomUUID(), ...address }, version: client.version });
    expect(patched.statusCode, patched.body).toBe(200);
    expect((await bill(clientId, `/invoices/${draft.id}/issue`, {})).statusCode).toBe(400);
    const invoice = await issued(clientId, draft.id);
    expect(invoice).toMatchObject({
      status: 'ISSUED', number: `F-${year()}-00001`, issuedOn: today(), dueOn: addDays(today(), 30), paymentTermDays: 30, total: 40_000, balance: 40_000,
      tax: { mode: 'NONE', amount: 0 }, issuer: { legalName: 'Drivy Exemple Sàrl', iban: 'CH9300762011623852957' },
      recipient: { name: 'Auto-école des Lilas', street: 'Rue des Lilas 2', city: 'Genève' }, issuedByName: 'Camille Exemple',
    });
    const period = await issued(clientId, (await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).id);
    expect(period).toMatchObject({ number: `F-${year()}-00002`, period: { index: 0, startsOn: today() }, total: 9_900 });
    expect(period.lines[0].label).toMatch(/^Abonnement du \d{2}\.\d{2}\.\d{4} au \d{2}\.\d{2}\.\d{4}$/);
    const after = await billing(clientId);
    expect(after).toMatchObject({ issuerReady: true, outstanding: 49_900, overdue: 0, initial: { state: 'ISSUED', number: `F-${year()}-00001` } });
    expect(after.periods[0]).toMatchObject({ state: 'ISSUED', number: `F-${year()}-00002`, balance: 9_900 });
    const issues = await journal('ISSUE_INVOICE');
    expect(issues.map(entry => entry.changes.number)).toEqual([`F-${year()}-00001`, `F-${year()}-00002`]);
  });

  it('TVA hors taxe : taxe arrondie au centime ajoutée au total ; la version de l’émetteur en vigueur est figée dans la facture', async () => {
    await setIssuer({ ...issuerFields, taxMode: 'VAT', vatNumber: 'CHE-123.456.789 TVA', taxRateBp: 810, pricesIncludeTax: false, taxNote: null });
    const clientId = await billableClient();
    const invoice = await issued(clientId, (await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).id);
    expect(invoice).toMatchObject({ netTotal: 9_900, tax: { mode: 'VAT', rateBp: 810, pricesIncludeTax: false, amount: 802 }, total: 10_702, issuer: { vatNumber: 'CHE-123.456.789 TVA' } });
    await setIssuer({ ...issuerFields, legalName: 'Drivy Renommée Sàrl' });
    const reread = (await call(A, 'GET', `/v1/platform/invoices/${invoice.id}`)).json().data;
    expect(reread).toMatchObject({ total: 10_702, issuer: { legalName: 'Drivy Exemple Sàrl' } });
  });

  it('période : invalide, future au-delà de la suivante, ou après résiliation ; la suivante se prépare d’avance', async () => {
    await setIssuer();
    const clientId = await billableClient();
    expectProblem(await bill(clientId, '/invoices', { kind: 'PERIOD', periodStart: addDays(today(), 1) }), 409, 'INVOICE_PERIOD_INVALID');
    expectProblem(await bill(clientId, '/invoices', { kind: 'PERIOD', periodStart: periodStart(today(), 2) }), 409, 'INVOICE_PERIOD_FUTURE');
    expect((await bill(clientId, '/invoices', { kind: 'PERIOD' })).statusCode).toBe(400);
    const next = await prepared(clientId, { kind: 'PERIOD', periodStart: periodStart(today(), 1) });
    expect(next).toMatchObject({ status: 'DRAFT', period: { index: 1 } });
  });

  it('un brouillon s’annule avec un motif, puis se prépare à nouveau ; une facture émise ne s’annule pas', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    expect((await bill(clientId, `/invoices/${draft.id}/cancel`, { reason: 'x' })).statusCode).toBe(400);
    const cancelled = await bill(clientId, `/invoices/${draft.id}/cancel`, { reason: 'Saisie à reprendre' });
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(cancelled.json().data).toMatchObject({ status: 'CANCELLED', reason: 'Saisie à reprendre', cancelledByName: 'Camille Exemple' });
    const again = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    expect(again.number).toBe(`F-${year()}-00001`);
    expectProblem(await bill(clientId, `/invoices/${again.id}/cancel`, { reason: 'Trop tard' }), 409, 'INVOICE_NOT_DRAFT');
    expect(JSON.stringify(await journal('CANCEL_INVOICE_DRAFT'))).not.toMatch(/Saisie à reprendre/);
  });

  it('une facture d’une autre fiche n’est jamais commandée par celle-ci', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    const other = await schoolClient();
    expectProblem(await bill(other, `/invoices/${draft.id}/issue`, { confirm: true }), 404, 'NOT_FOUND');
  });

  it('des conditions changées entre la préparation et l’émission refusent l’émission', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const next = await prepared(clientId, { kind: 'PERIOD', periodStart: periodStart(today(), 1) });
    await commercial(clientId, '/terms', { ...complete, monthlyAmount: 12_000 });
    expectProblem(await bill(clientId, `/invoices/${next.id}/issue`, { confirm: true }), 409, 'INVOICE_TERMS_CHANGED');
  });

  it('un début payant déjà facturé ne s’annule plus', async () => {
    await setIssuer();
    const clientId = await billableClient({ startsOn: addDays(today(), 3) });
    await prepared(clientId, { kind: 'INITIAL' });
    const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/commercial`)).json().data.version;
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial/paid-start/cancel`, { body: { operationId: randomUUID(), reason: 'Report demandé' }, version }), 409, 'PAID_START_INVOICED');
  });
});

describe('avoir et nouvelle génération', () => {
  it('un avoir total solde la facture, une seule fois ; la période redevient due et se refacture en génération 2', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const invoice = await issued(clientId, (await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).id);
    expect((await bill(clientId, `/invoices/${invoice.id}/credit`, { reason: 'Montant erroné' })).statusCode).toBe(400);
    const credit = await bill(clientId, `/invoices/${invoice.id}/credit`, { reason: 'Montant erroné', confirm: true });
    expect(credit.statusCode, credit.body).toBe(201);
    expect(credit.json().data).toMatchObject({
      kind: 'CREDIT_NOTE', status: 'ISSUED', number: `AV-${year()}-00001`, total: 9_900, balance: null,
      creditsInvoice: { id: invoice.id, number: invoice.number }, lines: [expect.objectContaining({ code: 'CREDIT' })],
    });
    expectProblem(await bill(clientId, `/invoices/${invoice.id}/credit`, { reason: 'Encore', confirm: true }), 409, 'INVOICE_CREDITED');
    expectProblem(await bill(clientId, `/invoices/${credit.json().data.id}/credit`, { reason: 'Avoir d’avoir', confirm: true }), 409, 'INVOICE_NOT_CREDITABLE');
    const original = (await call(A, 'GET', `/v1/platform/invoices/${invoice.id}`)).json().data;
    expect(original).toMatchObject({ balance: 0, overdue: false, creditNote: { number: `AV-${year()}-00001`, total: 9_900 } });
    expect((await billing(clientId)).periods[0].state).toBe('DUE');
    const second = await issued(clientId, (await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).id);
    expect(second).toMatchObject({ generation: 2, number: `F-${year()}-00002` });
    expect((await billing(clientId)).periods[0]).toMatchObject({ state: 'ISSUED', number: `F-${year()}-00002` });
    expect(JSON.stringify(await journal('ISSUE_CREDIT_NOTE'))).not.toMatch(/Montant erroné/);
  });
});

describe('envoi', () => {
  it('l’envoi s’enregistre une fois, daté entre l’émission et aujourd’hui ; un brouillon ne s’envoie pas', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    expectProblem(await bill(clientId, `/invoices/${draft.id}/sent`, { sentOn: today() }), 409, 'INVOICE_NOT_ISSUED');
    await issued(clientId, draft.id);
    expectProblem(await bill(clientId, `/invoices/${draft.id}/sent`, { sentOn: addDays(today(), 1) }), 409, 'INVOICE_SENT_DATE');
    const sent = await bill(clientId, `/invoices/${draft.id}/sent`, { sentOn: today() });
    expect(sent.statusCode, sent.body).toBe(200);
    expect(sent.json().data).toMatchObject({ sendStatus: 'SENT', sentOn: today(), sentRecordedByName: 'Camille Exemple' });
    expectProblem(await bill(clientId, `/invoices/${draft.id}/sent`, { sentOn: today() }), 409, 'INVOICE_ALREADY_SENT');
  });
});

describe('liste des factures', () => {
  it('filtre par fiche, état, genre et envoi ; pagine ; respecte le contrat', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const initial = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    await prepared(clientId, { kind: 'PERIOD', periodStart: today() });
    const all = await call(A, 'GET', `/v1/platform/invoices?clientId=${clientId}`);
    expect(all.statusCode, all.body).toBe(200);
    expect(invoicePageEnvelope.safeParse(all.json()).success, all.body).toBe(true);
    expect(all.json().data).toMatchObject({ total: 2, limit: 50, offset: 0 });
    expect((await call(A, 'GET', '/v1/platform/invoices?status=ISSUED')).json().data.items.map((item: { id: string }) => item.id)).toEqual([initial.id]);
    expect((await call(A, 'GET', '/v1/platform/invoices?kind=PERIOD&status=DRAFT')).json().data.total).toBe(1);
    expect((await call(A, 'GET', '/v1/platform/invoices?sendStatus=SENT')).json().data.total).toBe(0);
    expect((await call(A, 'GET', '/v1/platform/invoices?overdue=true')).json().data.total).toBe(0);
    const page = (await call(A, 'GET', '/v1/platform/invoices?limit=1&offset=1')).json().data;
    expect(page).toMatchObject({ total: 2, limit: 1, offset: 1 });
    expect(page.items).toHaveLength(1);
    expect((await call(A, 'GET', '/v1/platform/invoices?limit=101')).statusCode).toBe(400);
  });
});

describe('activation et préparation planifiée', () => {
  it('seule une fiche facturable s’active, aujourd’hui ou plus tard, une fois ; l’arrêt exige un motif', async () => {
    const pilot = await schoolClient();
    expectProblem(await bill(pilot, '/billing/activation', { startsOn: today(), confirm: true }), 409, 'BILLING_NOT_READY');
    const clientId = await billableClient();
    expectProblem(await bill(clientId, '/billing/activation', { startsOn: addDays(today(), -1), confirm: true }), 409, 'EFFECTIVE_DATE_PAST');
    expect((await bill(clientId, '/billing/activation', { startsOn: today() })).statusCode).toBe(400);
    const activated = await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    expect(activated.statusCode, activated.body).toBe(201);
    expect(activated.json().data.activation).toMatchObject({ status: 'ACTIVE', startsOn: today(), activatedByName: 'Camille Exemple' });
    expectProblem(await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true }), 409, 'BILLING_ACTIVE');
    const stopped = await bill(clientId, '/billing/activation/stop', { reason: 'Facturation manuelle' });
    expect(stopped.statusCode, stopped.body).toBe(200);
    expect(stopped.json().data).toMatchObject({ activation: null, activations: [expect.objectContaining({ status: 'STOPPED', stopReason: 'Facturation manuelle' })] });
    expect(JSON.stringify(await journal('STOP_BILLING'))).not.toMatch(/Facturation manuelle/);
  });

  it('le passage prépare et émet ce qui est dû, rien deux fois ; sans activation il ne fait rien', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const idle = await call(A, 'POST', '/v1/platform/billing/run', { body: { operationId: randomUUID() } });
    expect(idle.statusCode, idle.body).toBe(200);
    expect(billingRunEnvelope.safeParse(idle.json()).success, idle.body).toBe(true);
    expect(idle.json().data).toMatchObject({ skipped: false, clients: 0, prepared: 0, issued: 0 });
    await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    const run = (await call(A, 'POST', '/v1/platform/billing/run', { body: { operationId: randomUUID() } })).json().data;
    expect(run).toMatchObject({ clients: 1, prepared: 2, issued: 2, waiting: 0, failed: 0 });
    expect(await invoices(clientId)).toEqual([
      expect.objectContaining({ kind: 'INITIAL', status: 'ISSUED', number: `F-${year()}-00001`, origin: 'SCHEDULED', net_total: 40_000 }),
      expect.objectContaining({ kind: 'PERIOD', status: 'ISSUED', number: `F-${year()}-00002`, origin: 'SCHEDULED', period_start: today(), net_total: 9_900 }),
    ]);
    expect((await runAt()).prepared).toBe(0);
    expect(await count('platform_invoice')).toBe(2);
    const system = (await journal('ISSUE_INVOICE')).filter(entry => entry.actor_kind === 'SYSTEM');
    expect(system).toHaveLength(2);
    expect(system[0].actor_name).toBe('Facturation planifiée');
  });

  it('sans émetteur, les brouillons attendent ; le passage suivant les émet sans les préparer à nouveau ; un brouillon d’opérateur n’est jamais touché', async () => {
    const clientId = await billableClient();
    const manual = await prepared(clientId, { kind: 'INITIAL' });
    await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    expect(await runAt()).toMatchObject({ prepared: 1, issued: 0, waiting: 2, failed: 0 });
    await setIssuer();
    expect(await runAt()).toMatchObject({ prepared: 0, issued: 1, waiting: 1 });
    expect((await call(A, 'GET', `/v1/platform/invoices/${manual.id}`)).json().data.status).toBe('DRAFT');
  });

  it('rattrapage : un passage manqué reprend chaque période due avec les montants de l’échéancier, au plus 24 documents par passage, numéros sans trou', async () => {
    await setIssuer();
    const clientId = await billableClient({ terms: { ...complete, recurringDiscount: 900, recurringDiscountMonths: 2 } });
    await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    await backdate(clientId, 30 * 26);
    const anchor = (await billing(clientId)).paidStartsOn as string;
    const due = periodIndexOf(anchor, today()) + 1;
    expect(due).toBeGreaterThan(24);
    const first = await runAt();
    expect(first).toMatchObject({ issued: 24, failed: 0 });
    const second = await runAt();
    expect(second.issued).toBe(due + 1 - 24);
    expect((await runAt()).issued).toBe(0);
    const rows = await invoices(clientId);
    expect(rows).toHaveLength(due + 1);
    expect(rows.map(row => row.number)).toEqual(rows.map((_, index) => `F-${year()}-${String(index + 1).padStart(5, '0')}`));
    const view = await billing(clientId);
    const byStart = new Map(rows.filter(row => row.kind === 'PERIOD').map(row => [row.period_start, row.net_total]));
    for (const period of view.periods.filter((item: { startsOn: string }) => item.startsOn <= today())) {
      expect(byStart.get(period.startsOn), period.startsOn).toBe(period.net);
      expect(period.state).toBe('ISSUED');
    }
    expect(byStart.get(anchor)).toBe(9_000);
    expect(byStart.get(periodStart(anchor, 2))).toBe(9_900);
  });

  it('un brouillon planifié dont les conditions ont changé est annulé puis préparé à nouveau', async () => {
    const clientId = await billableClient();
    await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    expect((await runAt()).waiting).toBe(2);
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('ALTER TABLE drivy.platform_commercial_terms DISABLE TRIGGER USER');
      await db.query('UPDATE drivy.platform_commercial_terms SET monthly_amount=12000 WHERE client_id=$1', [clientId]);
      await db.query('ALTER TABLE drivy.platform_commercial_terms ENABLE TRIGGER USER'); await db.query('COMMIT');
    } finally { db.release(); }
    await setIssuer();
    expect(await runAt()).toMatchObject({ prepared: 1, issued: 2 });
    expect(await count('platform_invoice', `status='CANCELLED' AND reason='Conditions modifiées avant émission'`)).toBe(1);
    expect((await journal('CANCEL_INVOICE_DRAFT')).map(entry => entry.changes.reason)).toEqual(['TERMS_CHANGED']);
  });

  it('un passage concurrent est sauté, jamais doublé', async () => {
    await setIssuer();
    const clientId = await billableClient();
    await bill(clientId, '/billing/activation', { startsOn: today(), confirm: true });
    const holder = await pool.connect();
    try {
      await holder.query('BEGIN');
      await holder.query("SELECT pg_advisory_xact_lock(hashtextextended('platform-billing-run',0))");
      expect(await runAt()).toEqual({ skipped: true });
      await holder.query('COMMIT');
    } finally { holder.release(); }
    expect((await runAt()).issued).toBe(2);
  });
});

describe('concurrence', () => {
  it('deux émissions du même brouillon : une seule réussit, un seul numéro est pris', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    const version = (await billing(clientId)).version;
    const replies = await Promise.all([A, B].map(as => bill(clientId, `/invoices/${draft.id}/issue`, { confirm: true }, version, as)));
    expect(replies.map(reply => reply.statusCode).sort()).toEqual([200, 412]);
    expect((await pool.query('SELECT last FROM drivy.platform_invoice_counter WHERE series=$1', ['F'])).rows[0].last).toBe(1);
  });

  it('deux préparations de la même période : une seule facture vivante', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const version = (await billing(clientId)).version;
    const replies = await Promise.all([A, B].map(as => bill(clientId, '/invoices', { kind: 'PERIOD', periodStart: today() }, version, as)));
    expect(replies.map(reply => reply.statusCode).sort()).toEqual([201, 412]);
    expect(await count('platform_invoice', `client_id='${clientId}'`)).toBe(1);
  });

  it('rejeu à l’identique : même reçu ; même clé, autre contenu : refus', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const version = (await billing(clientId)).version;
    const body = { operationId: randomUUID(), kind: 'INITIAL' };
    const first = await call(A, 'POST', `/v1/platform/clients/${clientId}/invoices`, { body, version });
    expect(first.statusCode, first.body).toBe(201);
    const replay = await call(A, 'POST', `/v1/platform/clients/${clientId}/invoices`, { body, version });
    expect(replay.statusCode).toBe(201);
    expect(replay.json().data.id).toBe(first.json().data.id);
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${clientId}/invoices`, { body: { ...body, kind: 'PERIOD', periodStart: today() }, version }), 409, 'IDEMPOTENCY_MISMATCH');
    expect(await count('platform_invoice')).toBe(1);
  });
});

describe('garde-fous de la base', () => {
  it('une facture émise ne change plus, rien ne s’efface ; aucune activation datée du passé', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const invoice = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    expect((await ownerError('UPDATE drivy.platform_invoice SET total=1 WHERE id=$1', [invoice.id]))?.message).toMatch(/platform_invoice_issued_fixed/);
    expect((await ownerError('UPDATE drivy.platform_invoice SET number=$2 WHERE id=$1', [invoice.id, 'F-1999-00001']))?.message).toMatch(/platform_invoice_issued_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_invoice'))?.message).toMatch(/platform_invoice_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_billing_issuer'))?.message).toMatch(/platform_issuer_fixed/);
    expect((await ownerError(`INSERT INTO drivy.platform_billing_activation(id,client_id,starts_on,activated_by) VALUES(gen_random_uuid(),$1,drivy.zurich_today()-1,
      (SELECT id FROM drivy.platform_operator LIMIT 1))`, [clientId]))?.message).toMatch(/platform_activation_backdated/);
  });

  it('les tables de facturation sont sous RLS forcée ; drivy_app sans opérateur ne lit rien ; le service ne fait que passer', async () => {
    await setIssuer();
    const clientId = await billableClient();
    await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    const rows = (await pool.query<{ relname: string; forced: boolean }>(`SELECT relname, relforcerowsecurity AS forced FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname IN ('platform_billing_issuer','platform_billing_activation','platform_invoice','platform_invoice_counter')`)).rows;
    expect(rows).toHaveLength(4);
    expect(rows.every(row => row.forced)).toBe(true);
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      expect((await db.query('SELECT count(*)::int AS n FROM drivy.platform_invoice')).rows[0].n).toBe(0);
      await db.query('ROLLBACK');
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_billing_worker');
      expect((await db.query('SELECT drivy.platform_billing_run() AS result')).rows[0].result).toMatchObject({ skipped: false, clients: 0 });
      await expect(db.query('SELECT count(*) FROM drivy.platform_invoice')).rejects.toThrow(/permission denied/);
      await db.query('ROLLBACK');
    } finally { db.release(); }
  });
});
