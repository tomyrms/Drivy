import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool, type PoolClient } from 'pg';
import { isQRReferenceValid, isSCORReferenceValid } from 'swissqrbill/utils';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { deliverOneInvoice, type BillingMailConfig, type BillingTransport } from '../src/billing-mail.js';
import { ApiError } from '../src/errors.js';
import { addDays, periodIndexOf, periodStart, zurichDay } from '../src/platform-commercial-model.js';
import { billingEnvelope, billingRunEnvelope, invoiceEnvelope, invoicePageEnvelope, issuerSettingsEnvelope } from '../src/platform-billing-contract.js';
import { billingCountry, qrText } from '../src/platform-invoice-qr.js';
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
/** Configuration synthétique : aucune connexion n'est ouverte, chaque test injecte son transport. */
const billingMail: BillingMailConfig = { encryptionKey: 'b2'.repeat(32), host: '127.0.0.1', port: 1025, secure: false, requireTLS: false, from: 'factures@example.invalid' };
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};

const billingTables = 'drivy.platform_billing_issuer, drivy.platform_billing_activation, drivy.platform_invoice, drivy.platform_invoice_counter, '
  + 'drivy.platform_payment, drivy.platform_payment_allocation, drivy.platform_payment_regularization';
beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-billing-synthetic-secret-32-characters', billingMail });
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

/** Une fiche par école (`school_id` unique) : une seconde fiche dans le même test prend l'école B. */
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
/** Fiche facturable : offre en vigueur, conditions complètes, début payant confirmé (aujourd'hui par défaut). */
async function billableClient({ startsOn = today(), terms = complete, withAddress = true, schoolId = id.schoolA }:
  { startsOn?: string; terms?: Record<string, unknown>; withAddress?: boolean; schoolId?: string } = {}) {
  const clientId = await schoolClient(withAddress, schoolId);
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
// Une commande de facturation rend la facturation relue de la fiche (`billingEnvelope`), jamais le seul document : on l'y retrouve.
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
    expect(invoiceIn(cancelled, invoice => invoice.id === draft.id)).toMatchObject({ status: 'CANCELLED', reason: 'Saisie à reprendre', cancelledByName: 'Camille Exemple' });
    const again = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
    expect(again.number).toBe(`F-${year()}-00001`);
    expectProblem(await bill(clientId, `/invoices/${again.id}/cancel`, { reason: 'Trop tard' }), 409, 'INVOICE_NOT_DRAFT');
    expect(JSON.stringify(await journal('CANCEL_INVOICE_DRAFT'))).not.toMatch(/Saisie à reprendre/);
  });

  it('une facture d’une autre fiche n’est jamais commandée par celle-ci', async () => {
    await setIssuer();
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    const other = await schoolClient(true, id.schoolB);
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
    const note = invoiceIn(credit, item => item.kind === 'CREDIT_NOTE' && item.creditsInvoice?.id === invoice.id);
    expect(note).toMatchObject({
      kind: 'CREDIT_NOTE', status: 'ISSUED', number: `AV-${year()}-00001`, total: 9_900, balance: null,
      creditsInvoice: { id: invoice.id, number: invoice.number }, lines: [expect.objectContaining({ code: 'CREDIT' })],
    });
    expectProblem(await bill(clientId, `/invoices/${invoice.id}/credit`, { reason: 'Encore', confirm: true }), 409, 'INVOICE_CREDITED');
    expectProblem(await bill(clientId, `/invoices/${note.id}/credit`, { reason: 'Avoir d’avoir', confirm: true }), 409, 'INVOICE_NOT_CREDITABLE');
    const read = await call(A, 'GET', `/v1/platform/invoices/${invoice.id}`);
    expect(invoiceEnvelope.safeParse(read.json()).success, read.body).toBe(true);
    const original = read.json().data;
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
    expect(invoiceIn(sent, invoice => invoice.id === draft.id)).toMatchObject({ sendStatus: 'SENT', sentOn: today(), sentRecordedByName: 'Camille Exemple' });
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
    const pilot = await schoolClient(true, id.schoolB);
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
    expect(replay.json().data.invoices.map((item: { id: string }) => item.id)).toEqual(first.json().data.invoices.map((item: { id: string }) => item.id));
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

// --- Règlements (R01-T06, #458). Écrit sans être exécuté. Références et notes synthétiques. ---------------------------------------
const paymentInput = (patch: Record<string, unknown> = {}) => ({
  amount: 10_000, currency: 'CHF', receivedOn: today(), method: 'BANK_TRANSFER', reference: null, note: null, allocations: [], spread: false, confirmDuplicate: false, ...patch,
});
async function paid(clientId: string, patch: Record<string, unknown> = {}, as = A) {
  const response = await bill(clientId, '/payments', paymentInput(patch), undefined, as);
  expect(response.statusCode, response.body).toBe(201);
  expect(billingEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
const settledAt = async (invoiceId: string, day = today()) =>
  (await pool.query('SELECT drivy.platform_invoice_settlement($1,$2::date) AS s', [invoiceId, day])).rows[0].s;
const debtAt = async (clientId: string, day = today()) =>
  (await pool.query('SELECT drivy.platform_client_debt($1,$2::date) AS d', [clientId, day])).rows[0].d;
const invoiceOf = (view: any, invoiceId: string) => view.invoices.find((item: { id: string }) => item.id === invoiceId);
const paymentOf = (view: any, paymentId: string) => view.payments.find((item: { id: string }) => item.id === paymentId);
const paymentBy = (view: any, amount: number) => view.payments.find((item: { amount: number; status: string }) => item.amount === amount && item.status === 'RECORDED');
const correction = (patch: Record<string, unknown> = {}) => ({
  amount: 45_000, currency: 'CHF', receivedOn: today(), method: 'BANK_TRANSFER', reference: null, note: null, reason: 'Montant mal lu', ...patch,
});
/** Deux factures émises : montant initial (40 000) puis première période (9 900), à 30 jours. `setIssuer()` est appelé une fois avant. */
async function invoicedClient(schoolId: string = id.schoolA) {
  const clientId = await billableClient({ schoolId });
  const initial = await issued(clientId, (await prepared(clientId, { kind: 'INITIAL' })).id);
  const period = await issued(clientId, (await prepared(clientId, { kind: 'PERIOD', periodStart: today() })).id);
  return { clientId, initial, period };
}

describe('règlements : soldes', () => {
  it('partiel, total puis trop-perçu : soldes exacts, plus aucun retard, filtre de la liste sur le même calcul', async () => {
    await setIssuer();
    const { clientId, initial, period } = await invoicedClient();
    const first = await paid(clientId, { amount: 10_000, allocations: [{ invoiceId: initial.id, amount: 10_000 }] });
    expect(invoiceOf(first, initial.id).settlement).toMatchObject({ allocated: 10_000, balance: 30_000, state: 'PARTIAL', overdue: false });
    expect(first.debt).toMatchObject({ outstanding: 39_900, overdueAmount: 0, overdueCount: 0, unallocated: 0 });
    const second = await paid(clientId, { amount: 40_000, spread: true });
    expect(paymentBy(second, 40_000)).toMatchObject({ allocated: 39_900, available: 100 });
    expect(invoiceOf(second, initial.id).settlement).toMatchObject({ balance: 0, state: 'PAID' });
    expect(invoiceOf(second, period.id).settlement).toMatchObject({ balance: 0, state: 'PAID' });
    expect(second.debt).toMatchObject({ outstanding: 0, overdueAmount: 0, overdueCount: 0, oldestOverdueDueOn: null, unallocated: 100 });
    expect(await debtAt(clientId, addDays(today(), 60))).toMatchObject({ outstanding: 0, overdueCount: 0 });
    expect((await settledAt(period.id, addDays(today(), 60))).overdue).toBe(false);
    const list = await call(A, 'GET', `/v1/platform/invoices?settlement=PAID&clientId=${clientId}`);
    expect(invoicePageEnvelope.safeParse(list.json()).success, list.body).toBe(true);
    expect(list.json().data.total).toBe(2);
    expect((await call(A, 'GET', `/v1/platform/invoices?settlement=UNPAID&clientId=${clientId}`)).json().data.total).toBe(0);
  });

  it('le retard porte sur le seul reste dû, à partir du lendemain de l’échéance', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    await paid(clientId, { amount: 15_000, allocations: [{ invoiceId: initial.id, amount: 15_000 }] });
    expect((await settledAt(initial.id, addDays(today(), 30))).overdue).toBe(false);
    expect(await debtAt(clientId, addDays(today(), 30))).toMatchObject({ overdueAmount: 0, overdueCount: 0 });
    expect(await settledAt(initial.id, addDays(today(), 31))).toMatchObject({ balance: 25_000, state: 'PARTIAL', overdue: true });
    expect(await debtAt(clientId, addDays(today(), 31))).toMatchObject({
      outstanding: 34_900, overdueAmount: 34_900, overdueCount: 2, oldestOverdueDueOn: addDays(today(), 30),
    });
  });

  it('un envoi enregistré ne règle jamais une facture', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const sent = await bill(clientId, `/invoices/${initial.id}/sent`, { sentOn: today() });
    expect(sent.statusCode, sent.body).toBe(200);
    expect(invoiceOf(sent.json().data, initial.id)).toMatchObject({ sendStatus: 'SENT', balance: 40_000, settlement: { state: 'UNPAID', allocated: 0 }, allocations: [] });
    expect(await count('platform_payment')).toBe(0);
    expect(await count('platform_payment_allocation')).toBe(0);
  });
});

describe('règlements : affectations refusées', () => {
  it('ni une autre école, ni au-delà du reste ou du solde, ni un brouillon ; un refus n’écrit rien', async () => {
    await setIssuer();
    const { clientId, initial, period } = await invoicedClient();
    const other = await invoicedClient(id.schoolB);
    expectProblem(await bill(clientId, '/payments', paymentInput({ amount: 1_000, allocations: [{ invoiceId: other.initial.id, amount: 1_000 }] })), 409, 'PAYMENT_OTHER_CLIENT');
    expect(await count('platform_payment')).toBe(0);
    const small = paymentBy(await paid(clientId, { amount: 5_000 }), 5_000);
    const allocate = (paymentId: string, invoiceId: string, amount: number) => bill(clientId, `/payments/${paymentId}/allocations`, { invoiceId, amount });
    expectProblem(await allocate(small.id, other.initial.id, 1_000), 409, 'PAYMENT_OTHER_CLIENT');
    expectProblem(await allocate(small.id, initial.id, 5_001), 409, 'PAYMENT_EXCEEDS_AVAILABLE');
    const large = paymentBy(await paid(clientId, { amount: 20_000 }), 20_000);
    expectProblem(await allocate(large.id, period.id, 9_901), 409, 'PAYMENT_EXCEEDS_BALANCE');
    const draft = await prepared(clientId, { kind: 'PERIOD', periodStart: periodStart(today(), 1) });
    expectProblem(await allocate(large.id, draft.id, 1_000), 409, 'PAYMENT_INVOICE_INVALID');
    expect(await count('platform_payment_allocation')).toBe(0);
    const foreign = paymentBy(await paid(other.clientId, { amount: 3_000 }), 3_000);
    expectProblem(await allocate(foreign.id, initial.id, 1_000), 404, 'NOT_FOUND');
    expectProblem(await bill(clientId, '/payments', paymentInput({ currency: 'EUR' })), 409, 'PAYMENT_CURRENCY');
    expectProblem(await bill(clientId, '/payments', paymentInput({ receivedOn: addDays(today(), 1) })), 409, 'PAYMENT_DATE_FUTURE');
  });
});

describe('règlements : doublons et concurrence', () => {
  it('rejeu sans doublon ; deux opérateurs : un seul passe ; doublon probable confirmé explicitement', async () => {
    await setIssuer();
    const { clientId } = await invoicedClient();
    const url = `/v1/platform/clients/${clientId}/payments`;
    const body = { operationId: randomUUID(), ...paymentInput({ amount: 12_000, reference: 'VIR-778899' }) };
    const version = (await billing(clientId)).version;
    const first = await call(A, 'POST', url, { body, version });
    const replay = await call(A, 'POST', url, { body, version });
    expect([first.statusCode, replay.statusCode]).toEqual([201, 201]);
    expect(replay.json().data.payments.map((item: { id: string }) => item.id)).toEqual(first.json().data.payments.map((item: { id: string }) => item.id));
    expect(await count('platform_payment')).toBe(1);

    const current = (await billing(clientId)).version;
    const raced = await Promise.all([A, B].map(as => call(as, 'POST', url, { body: { operationId: randomUUID(), ...paymentInput({ amount: 7_000 }) }, version: current })));
    expect(raced.map(item => item.statusCode).sort()).toEqual([201, 412]);
    expect(await count('platform_payment', 'amount=7000')).toBe(1);

    expectProblem(await bill(clientId, '/payments', paymentInput({ amount: 12_000, receivedOn: addDays(today(), -10), reference: 'vir-778899' })), 409, 'PAYMENT_POSSIBLE_DUPLICATE');
    expectProblem(await bill(clientId, '/payments', paymentInput({ amount: 12_000, receivedOn: addDays(today(), -3) })), 409, 'PAYMENT_POSSIBLE_DUPLICATE');
    expect(await count('platform_payment', 'amount=12000')).toBe(1);
    await paid(clientId, { amount: 12_000, receivedOn: addDays(today(), -3), confirmDuplicate: true });
    expect(await count('platform_payment', 'amount=12000')).toBe(2);
    expect((await journal('RECORD_PAYMENT')).some(entry => entry.changes?.duplicateConfirmed === true)).toBe(true);
    await paid(clientId, { amount: 12_000, receivedOn: addDays(today(), -10), reference: 'VIR-AUTRE' });
    expect(await count('platform_payment', 'amount=12000')).toBe(3);
  });
});

describe('règlements : correction, libération, annulation, régularisation', () => {
  it('une correction recalcule solde et retard sans effacer l’auteur ni l’original', async () => {
    await setIssuer();
    const { clientId } = await invoicedClient();
    const original = paymentBy(await paid(clientId, { amount: 49_900, spread: true }), 49_900);
    expect(original.allocated).toBe(49_900);
    const corrected = await bill(clientId, `/payments/${original.id}/correct`, correction(), undefined, B);
    expect(corrected.statusCode, corrected.body).toBe(201);
    expect(billingEnvelope.safeParse(corrected.json()).success, corrected.body).toBe(true);
    const after = corrected.json().data;
    const kept = paymentOf(after, original.id);
    const replacement = after.payments.find((item: { correctsPaymentId: string | null }) => item.correctsPaymentId === original.id);
    expect(kept).toMatchObject({
      status: 'VOIDED', voidCause: 'CORRECTED', voidReason: 'Montant mal lu', amount: 49_900, allocated: 0, available: 0,
      recordedByName: 'Camille Exemple', voidedByName: 'Jean Exemple', correctedByPaymentId: replacement.id,
    });
    expect(kept.allocations).toHaveLength(2);
    expect(kept.allocations.every((item: any) => item.status === 'RELEASED' && item.releaseCause === 'PAYMENT_CORRECTED' && item.createdByName === 'Camille Exemple')).toBe(true);
    expect(replacement).toMatchObject({ status: 'RECORDED', amount: 45_000, allocated: 45_000, available: 0, recordedByName: 'Jean Exemple' });
    expect(after.debt).toMatchObject({ outstanding: 4_900, overdueAmount: 0, unallocated: 0 });
    // L'ordre de reprise entre deux affectations du même instant n'est pas garanti : seul le reste dû est vérifié.
    expect(await debtAt(clientId, addDays(today(), 31))).toMatchObject({ outstanding: 4_900, overdueAmount: 4_900, overdueCount: 1 });
    expectProblem(await bill(clientId, `/payments/${original.id}/correct`, correction({ amount: 44_000 })), 409, 'PAYMENT_VOIDED');
    expectProblem(await bill(clientId, `/payments/${replacement.id}/correct`, correction()), 409, 'PAYMENT_UNCHANGED');
    const entries = await journal('CORRECT_PAYMENT');
    expect(entries.find(entry => entry.changes?.after)?.changes).toMatchObject({ before: { amount: 49_900 }, after: { amount: 45_000 } });
    expect(JSON.stringify(entries)).not.toMatch(/Montant mal lu/);
  });

  it('libérer puis créditer ; un avoir ne crée ni remboursement ni régularisation ; annuler laisse le règlement lisible', async () => {
    await setIssuer();
    const { clientId, period } = await invoicedClient();
    const view = await paid(clientId, { amount: 9_900, allocations: [{ invoiceId: period.id, amount: 9_900 }] });
    const payment = paymentBy(view, 9_900), allocation = payment.allocations[0];
    expect(invoiceOf(view, period.id).settlement.state).toBe('PAID');
    expectProblem(await bill(clientId, `/invoices/${period.id}/credit`, { reason: 'Période erronée', confirm: true }), 409, 'INVOICE_PAID');
    const releaseUrl = `/payments/${payment.id}/allocations/${allocation.id}/release`;
    expect((await bill(clientId, releaseUrl, { reason: 'x' })).statusCode).toBe(400);
    const released = await bill(clientId, releaseUrl, { reason: 'Mauvaise facture' });
    expect(released.statusCode, released.body).toBe(200);
    expect(invoiceOf(released.json().data, period.id).settlement).toMatchObject({ state: 'UNPAID', balance: 9_900 });
    expect(paymentOf(released.json().data, payment.id).allocations[0]).toMatchObject({ status: 'RELEASED', releaseCause: 'MANUAL', releaseReason: 'Mauvaise facture' });
    expectProblem(await bill(clientId, releaseUrl, { reason: 'Mauvaise facture' }), 409, 'ALLOCATION_RELEASED');
    const credited = await bill(clientId, `/invoices/${period.id}/credit`, { reason: 'Période erronée', confirm: true });
    expect(credited.statusCode, credited.body).toBe(201);
    expect(invoiceOf(credited.json().data, period.id).settlement).toMatchObject({ state: 'CREDITED', balance: 0 });
    expectProblem(await bill(clientId, `/payments/${payment.id}/allocations`, { invoiceId: period.id, amount: 100 }), 409, 'INVOICE_CREDITED');
    expect(paymentOf(credited.json().data, payment.id)).toMatchObject({ available: 9_900, regularized: 0, regularizations: [] });
    expect(await count('platform_payment_regularization')).toBe(0);
    expect((await bill(clientId, `/payments/${payment.id}/void`, { reason: 'Saisie en double' })).statusCode).toBe(400);
    const voided = await bill(clientId, `/payments/${payment.id}/void`, { reason: 'Saisie en double', confirm: true });
    expect(voided.statusCode, voided.body).toBe(200);
    expect(paymentOf(voided.json().data, payment.id)).toMatchObject({ status: 'VOIDED', voidCause: 'VOIDED', available: 0, recordedByName: 'Camille Exemple' });
    expect(voided.json().data.debt.unallocated).toBe(0);
  });

  it('une régularisation est explicite, bornée au reste, et s’annule sans rien effacer', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const view = await paid(clientId, { amount: 45_000, allocations: [{ invoiceId: initial.id, amount: 40_000 }] });
    const payment = paymentBy(view, 45_000);
    expect(view.debt.unallocated).toBe(5_000);
    const url = `/payments/${payment.id}/regularizations`;
    expectProblem(await bill(clientId, url, { amount: 5_001, kind: 'REFUND_RECORDED', reason: 'Virement retour effectué' }), 409, 'PAYMENT_EXCEEDS_AVAILABLE');
    const done = await bill(clientId, url, { amount: 5_000, kind: 'REFUND_RECORDED', reason: 'Virement retour effectué' });
    expect(done.statusCode, done.body).toBe(201);
    const regularized = paymentOf(done.json().data, payment.id);
    expect(regularized).toMatchObject({ available: 0, regularized: 5_000 });
    expect(done.json().data.debt.unallocated).toBe(0);
    expectProblem(await bill(clientId, `/payments/${payment.id}/void`, { reason: 'Saisie en double', confirm: true }), 409, 'PAYMENT_REGULARIZED');
    const cancelUrl = `${url}/${regularized.regularizations[0].id}/cancel`;
    const cancelled = await bill(clientId, cancelUrl, { reason: 'Virement rejeté' });
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(paymentOf(cancelled.json().data, payment.id)).toMatchObject({ available: 5_000, regularized: 0 });
    expect(paymentOf(cancelled.json().data, payment.id).regularizations[0]).toMatchObject({ status: 'CANCELLED', reason: 'Virement retour effectué', cancelReason: 'Virement rejeté' });
    expectProblem(await bill(clientId, cancelUrl, { reason: 'Virement rejeté' }), 409, 'REGULARIZATION_CANCELLED');
    expect(JSON.stringify([...await journal('REGULARIZE_PAYMENT'), ...await journal('CANCEL_REGULARIZATION')])).not.toMatch(/Virement/);
  });
});

describe('règlements : journal et garde-fous', () => {
  it('le journal ne reçoit ni référence ni note ; rien ne se réécrit ni ne s’efface ; RLS forcée', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const view = await paid(clientId, { amount: 6_000, reference: 'VIR-778899', note: 'Reçu au guichet', allocations: [{ invoiceId: initial.id, amount: 5_000 }] });
    const payment = paymentBy(view, 6_000);
    expect(payment).toMatchObject({ reference: 'VIR-778899', note: 'Reçu au guichet' });
    expect(JSON.stringify(await journal('RECORD_PAYMENT'))).not.toMatch(/778899|guichet/);
    const done = await bill(clientId, `/payments/${payment.id}/regularizations`, { amount: 1_000, kind: 'OTHER', reason: 'Écart de caisse' });
    expect(done.statusCode, done.body).toBe(201);
    expect((await ownerError('UPDATE drivy.platform_payment SET amount=1 WHERE id=$1', [payment.id]))?.message).toMatch(/platform_payment_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_payment WHERE id=$1', [payment.id]))?.message).toMatch(/platform_payment_fixed/);
    expect((await ownerError('UPDATE drivy.platform_payment_allocation SET amount=1 WHERE payment_id=$1', [payment.id]))?.message).toMatch(/platform_allocation_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_payment_allocation WHERE payment_id=$1', [payment.id]))?.message).toMatch(/platform_allocation_fixed/);
    expect((await ownerError('UPDATE drivy.platform_payment_regularization SET amount=1 WHERE payment_id=$1', [payment.id]))?.message).toMatch(/platform_regularization_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_payment_regularization WHERE payment_id=$1', [payment.id]))?.message).toMatch(/platform_regularization_fixed/);
    const rows = (await pool.query<{ forced: boolean }>(`SELECT relforcerowsecurity AS forced FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname IN ('platform_payment','platform_payment_allocation','platform_payment_regularization')`)).rows;
    expect(rows).toHaveLength(3);
    expect(rows.every(row => row.forced)).toBe(true);
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      for (const table of ['platform_payment', 'platform_payment_allocation', 'platform_payment_regularization']) {
        expect((await db.query(`SELECT count(*)::int AS n FROM drivy.${table}`)).rows[0].n).toBe(0);
      }
      await db.query('ROLLBACK');
    } finally { db.release(); }
  });
});

// --- Documents PDF et envoi (R01-T07, #459). Écrit sans être exécuté. Aucun SMTP : transport injecté. Adresses et comptes synthétiques. -----
const invoicePath = (clientId: string, invoiceId: string) => `/v1/platform/clients/${clientId}/invoices/${invoiceId}`;
const download = (clientId: string, invoiceId: string, revision?: number, subject: string | null = A) => app.inject({
  method: 'GET', url: `${invoicePath(clientId, invoiceId)}/document${revision ? `?revision=${revision}` : ''}`,
  headers: subject ? { authorization: `Bearer ${subject}` } : {},
});
async function generated(clientId: string, invoiceId: string, status = 201) {
  const response = await bill(clientId, `/invoices/${invoiceId}/document`);
  expect(response.statusCode, response.body).toBe(status);
  return invoiceIn(response, invoice => invoice.id === invoiceId);
}
const preview = (clientId: string, invoiceId: string) => call(A, 'GET', `${invoicePath(clientId, invoiceId)}/delivery/preview`);
const send = (clientId: string, invoiceId: string, resend = false) => bill(clientId, `/invoices/${invoiceId}/delivery`, { confirm: true, resend });
async function queued(clientId: string, invoiceId: string, resend = false) {
  const response = await send(clientId, invoiceId, resend);
  expect(response.statusCode, response.body).toBe(201);
  return invoiceIn(response, invoice => invoice.id === invoiceId).delivery;
}
const deliveryRow = async (deliveryId: string) => (await pool.query(`SELECT status, attempts, failure_code, payload, lease_id, accepted_at, finished_at
  FROM drivy.platform_invoice_delivery WHERE id=$1`, [deliveryId])).rows[0];
/** Transport de recette : retient chaque message présenté, puis répond ce que le test demande. */
function smtp(outcome: () => { rejected?: unknown[] } = () => ({ rejected: [] })) {
  const messages: Record<string, any>[] = [];
  const factory = (): BillingTransport => ({
    verify: async () => true,
    sendMail: async message => { messages.push(message); return outcome(); },
    close: () => undefined,
  });
  return { messages, factory };
}
const smtpError = (fields: Record<string, unknown>) => smtp(() => { throw Object.assign(new Error('Erreur SMTP de recette'), fields); });
async function asMailer<T>(work: (db: PoolClient) => Promise<T>) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_billing_mailer');
    const result = await work(db);
    await db.query('COMMIT');
    return result;
  } catch (error) { await db.query('ROLLBACK'); throw error; } finally { db.release(); }
}
async function roleError(role: string, sql: string) {
  const db = await pool.connect();
  try {
    await db.query('BEGIN'); await db.query(`SET LOCAL ROLE ${role}`); await db.query(sql);
    return undefined;
  } catch (error) { return error as Error & { code?: string }; } finally { await db.query('ROLLBACK'); db.release(); }
}

describe('documents PDF', () => {
  it('rendu une fois depuis l’instantané : mêmes octets, même après un changement de l’émetteur', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const first = await generated(clientId, initial.id);
    expect(first.documents).toHaveLength(1);
    const document = first.documents[0];
    expect(document).toMatchObject({ revision: 1, paymentMode: 'QR', referenceType: 'SCOR', amount: 40_000, createdByName: 'Camille Exemple' });
    expect(isSCORReferenceValid(document.reference)).toBe(true);
    const file = await download(clientId, initial.id);
    expect(file.statusCode).toBe(200);
    expect(file.headers).toMatchObject({
      'content-type': 'application/pdf', 'content-disposition': `attachment; filename="facture-${initial.number}.pdf"`,
      'cache-control': 'no-store', 'x-content-type-options': 'nosniff',
    });
    expect(file.rawPayload.subarray(0, 5).toString()).toBe('%PDF-');
    expect(createHash('sha256').update(file.rawPayload).digest('hex')).toBe(document.sha256);
    expect(file.rawPayload.byteLength).toBe(document.byteSize);

    expect((await setIssuer({ ...issuerFields, legalName: 'Drivy Renommée Sàrl' })).statusCode).toBe(201);
    const again = await generated(clientId, initial.id, 200);
    expect(again.documents.map((item: { id: string }) => item.id)).toEqual([document.id]);
    expect((await download(clientId, initial.id)).rawPayload.equals(file.rawPayload)).toBe(true);
    expect((await download(clientId, initial.id, 1)).rawPayload.equals(file.rawPayload)).toBe(true);
    expect((await download(clientId, initial.id, 9)).statusCode).toBe(404);
    expect(await count('platform_invoice_document')).toBe(1);
    expect(JSON.stringify(await journal('GENERATE_INVOICE_DOCUMENT'))).not.toMatch(/CH9300762011623852957|marie@|Rue des Lilas/);
  });

  it('un QR-IBAN donne une référence QRR ; un brouillon n’a pas de document', async () => {
    await setIssuer({ ...issuerFields, iban: 'CH44 3199 9123 0008 8901 2' });
    const { clientId, initial } = await invoicedClient();
    const document = (await generated(clientId, initial.id)).documents[0];
    expect(document).toMatchObject({ paymentMode: 'QR', referenceType: 'QRR', amount: 40_000 });
    expect(isQRReferenceValid(document.reference)).toBe(true);
    const draft = await prepared(clientId, { kind: 'PERIOD', periodStart: periodStart(today(), 1) });
    expectProblem(await bill(clientId, `/invoices/${draft.id}/document`), 409, 'INVOICE_NOT_ISSUED');
    expect((await download(clientId, draft.id)).statusCode).toBe(404);
  });

  it('une autre école, un visiteur ou un compte d’école n’obtiennent ni le PDF ni l’aperçu', async () => {
    await setIssuer();
    const a = await invoicedClient();
    const b = await invoicedClient(id.schoolB);
    await generated(a.clientId, a.initial.id);
    expect((await download(b.clientId, a.initial.id)).statusCode).toBe(404);
    expectProblem(await preview(b.clientId, a.initial.id), 404, 'NOT_FOUND');
    expectProblem(await bill(b.clientId, `/invoices/${a.initial.id}/document`), 404, 'NOT_FOUND');
    expectProblem(await send(b.clientId, a.initial.id), 404, 'NOT_FOUND');
    expect((await download(a.clientId, a.initial.id, undefined, null)).statusCode).toBe(401);
    expect((await download(a.clientId, a.initial.id, undefined, 'demo-admin')).statusCode).toBe(403);
    expectProblem(await call('demo-admin', 'GET', `${invoicePath(a.clientId, a.initial.id)}/delivery/preview`), 403, 'PLATFORM_OPERATOR_REQUIRED');
  });

  it('l’émission refuse un compte ou une adresse non conformes, sans consommer de numéro', async () => {
    expect((await setIssuer({ ...issuerFields, iban: null })).statusCode).toBe(201);
    const clientId = await billableClient();
    const draft = await prepared(clientId, { kind: 'INITIAL' });
    const issue = () => bill(clientId, `/invoices/${draft.id}/issue`, { confirm: true });
    expectProblem(await issue(), 409, 'INVOICE_PAYMENT_ACCOUNT');
    expect((await setIssuer({ ...issuerFields, postalCode: 'CH-1000' })).statusCode).toBe(201);
    expectProblem(await issue(), 409, 'INVOICE_ISSUER_ADDRESS');
    expect((await setIssuer()).statusCode).toBe(201);
    await pool.query(`UPDATE drivy.platform_client SET billing_postal_code='CH-1200' WHERE id=$1`, [clientId]);
    expectProblem(await issue(), 409, 'INVOICE_RECIPIENT_ADDRESS');
    expect(await count('platform_invoice', `status='ISSUED'`)).toBe(0);
    await pool.query(`UPDATE drivy.platform_client SET billing_postal_code='1200' WHERE id=$1`, [clientId]);
    expect(await issued(clientId, draft.id)).toMatchObject({ number: `F-${year()}-00001` });
  });

  it('un avoir ne porte aucun ordre de paiement ; le document d’origine reste téléchargeable', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    await generated(clientId, initial.id);
    const original = (await download(clientId, initial.id)).rawPayload;
    const credit = await bill(clientId, `/invoices/${initial.id}/credit`, { reason: 'Montant erroné', confirm: true });
    expect(credit.statusCode, credit.body).toBe(201);
    const note = invoiceIn(credit, invoice => invoice.kind === 'CREDIT_NOTE' && invoice.creditsInvoice?.id === initial.id);
    expect((await generated(clientId, note.id)).documents[0]).toMatchObject({ paymentMode: 'NONE', referenceType: null, reference: null, amount: 0 });
    const after = await generated(clientId, initial.id);
    expect(after.documents.map((item: { revision: number; paymentMode: string }) => [item.revision, item.paymentMode])).toEqual([[2, 'NONE'], [1, 'QR']]);
    expect((await download(clientId, initial.id, 1)).rawPayload.equals(original)).toBe(true);
    expectProblem(await send(clientId, initial.id), 409, 'INVOICE_DELIVERY_CREDITED');
    await queued(clientId, note.id);
    const transport = smtp();
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    expect(transport.messages[0]!.attachments[0].filename).toBe(`avoir-${note.number}.pdf`);
    expect(transport.messages[0]!.text).toMatch(/aucun paiement/);
  });

  it('après un règlement partiel, aucun QR au montant total n’est créé ni envoyé ; le reste dû reste exact', async () => {
    await setIssuer();
    const { clientId, initial, period } = await invoicedClient();
    await generated(clientId, initial.id);
    await paid(clientId, { amount: 15_000, allocations: [{ invoiceId: initial.id, amount: 15_000 }] });
    expectProblem(await send(clientId, initial.id), 409, 'INVOICE_DELIVERY_SETTLED');
    expect(await count('platform_invoice_delivery')).toBe(0);
    expect(invoiceOf(await billing(clientId), initial.id)).toMatchObject({ balance: 25_000, documents: [expect.objectContaining({ paymentMode: 'QR', amount: 40_000 })] });
    await paid(clientId, { amount: 1_000, allocations: [{ invoiceId: period.id, amount: 1_000 }] });
    const late = await generated(clientId, period.id);
    expect(late).toMatchObject({ balance: 8_900, documents: [expect.objectContaining({ paymentMode: 'NONE', amount: 0, reference: null })] });
  });
});

describe('envoi des factures', () => {
  it('aperçu, file, acceptation, renvoi explicite : une acceptation ne règle rien', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const seen = (await preview(clientId, initial.id)).json().data;
    expect(seen).toMatchObject({
      to: 'marie@example.invalid', subject: `Facture ${initial.number}`, fileName: `facture-${initial.number}.pdf`, paymentMode: 'QR', amount: 40_000,
      resend: false, ready: true, problems: [],
    });
    expect((await bill(clientId, `/invoices/${initial.id}/delivery`, { resend: false })).statusCode).toBe(400);
    const delivery = await queued(clientId, initial.id);
    expect(delivery).toMatchObject({ status: 'QUEUED', recipientMasked: 'ma***@example.invalid', attempts: 0, resendOf: null });
    const stored = await deliveryRow(delivery.id);
    expect(stored.payload.toString('latin1')).not.toMatch(/marie|%PDF/);
    expectProblem(await send(clientId, initial.id), 409, 'INVOICE_DELIVERY_ACTIVE');
    const busy = (await preview(clientId, initial.id)).json().data;
    expect(busy.ready).toBe(false);
    expect(busy.problems.map((item: { code: string }) => item.code)).toContain('INVOICE_DELIVERY_ACTIVE');

    const transport = smtp();
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(false);
    expect(transport.messages).toHaveLength(1);
    const message = transport.messages[0]!;
    expect(message).toMatchObject({ from: billingMail.from, to: 'marie@example.invalid', subject: `Facture ${initial.number}`, messageId: `<drivy-invoice-${delivery.id}@example.invalid>` });
    expect(message.attachments[0]).toMatchObject({ filename: `facture-${initial.number}.pdf`, contentType: 'application/pdf' });
    expect(message.attachments[0].content.equals((await download(clientId, initial.id)).rawPayload)).toBe(true);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'ACCEPTED', attempts: 1, failure_code: null, payload: null, lease_id: null });

    const after = invoiceOf(await billing(clientId), initial.id);
    expect(after).toMatchObject({ sendStatus: 'SENT', sentOn: today(), dueOn: initial.dueOn, balance: 40_000, settlement: { state: 'UNPAID', allocated: 0 }, allocations: [] });
    expect(after.delivery).toMatchObject({ status: 'ACCEPTED' });
    expect(await count('platform_payment')).toBe(0);

    expect((await preview(clientId, initial.id)).json().data.resend).toBe(true);
    expectProblem(await send(clientId, initial.id), 409, 'INVOICE_DELIVERY_RESEND_REQUIRED');
    const resent = await queued(clientId, initial.id, true);
    expect(resent.resendOf).toBe(delivery.id);
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    expect(transport.messages).toHaveLength(2);
    expect(transport.messages[1]!.messageId).not.toBe(message.messageId);
    expect(await count('platform_invoice_document')).toBe(1);

    const trail = JSON.stringify([...await journal('QUEUE_INVOICE_DELIVERY'), ...await journal('INVOICE_DELIVERY_ACCEPTED')]);
    expect(trail).not.toMatch(/marie|CH9300762011623852957|Veuillez trouver|Rue des Lilas/);
  });

  it('un rejeu ne crée pas de second envoi ; deux opérateurs en même temps : un seul passe', async () => {
    await setIssuer();
    const { clientId, initial, period } = await invoicedClient();
    const version = (await billing(clientId)).version;
    const body = { operationId: randomUUID(), confirm: true, resend: false };
    const url = `${invoicePath(clientId, initial.id)}/delivery`;
    const first = await call(A, 'POST', url, { body, version });
    const replay = await call(A, 'POST', url, { body, version });
    expect([first.statusCode, replay.statusCode]).toEqual([201, 201]);
    expect(await count('platform_invoice_delivery', `invoice_id='${initial.id}'`)).toBe(1);

    const current = (await billing(clientId)).version;
    const raced = await Promise.all([A, B].map(as => call(as, 'POST', `${invoicePath(clientId, period.id)}/delivery`, {
      body: { operationId: randomUUID(), confirm: true, resend: false }, version: current,
    })));
    expect(raced.map(item => item.statusCode).sort()).toEqual([201, 409]);
    expect(await count('platform_invoice_delivery', `invoice_id='${period.id}'`)).toBe(1);
    expect(await count('platform_invoice_document', `invoice_id='${period.id}'`)).toBe(1);
  });

  it('un refus SMTP ne change ni paiement ni échéance ; l’envoi peut être refait', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const delivery = await queued(clientId, initial.id);
    const transport = smtpError({ responseCode: 550 });
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'FAILED', failure_code: 'SMTP_REJECTED', payload: null });
    expect(invoiceOf(await billing(clientId), initial.id)).toMatchObject({
      sendStatus: 'NOT_SENT', sentOn: null, dueOn: initial.dueOn, balance: 40_000, settlement: { state: 'UNPAID', allocated: 0 },
    });
    expect(await count('platform_payment')).toBe(0);
    expect((await queued(clientId, initial.id)).resendOf).toBe(delivery.id);
  });

  it('un refus temporaire est repris avec délai, puis abandonné après cinq tentatives', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const delivery = await queued(clientId, initial.id);
    const transport = smtpError({ responseCode: 451 });
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    const waiting = await deliveryRow(delivery.id);
    expect(waiting).toMatchObject({ status: 'QUEUED', attempts: 1, failure_code: 'SMTP_TEMPORARY', lease_id: null });
    expect(waiting.payload).not.toBeNull();
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(false);
    for (let attempt = 2; attempt <= 5; attempt += 1) {
      await pool.query('UPDATE drivy.platform_invoice_delivery SET available_at=now() WHERE id=$1', [delivery.id]);
      expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    }
    expect(transport.messages).toHaveLength(5);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'FAILED', attempts: 5, failure_code: 'RETRY_EXHAUSTED', payload: null });
  });

  it('une connexion impossible est reprise sans rien présenter ; un contenu indéchiffrable échoue sans envoi', async () => {
    await setIssuer();
    const { clientId, initial, period } = await invoicedClient();
    const unreachable = await queued(clientId, initial.id);
    let presented = 0;
    expect(await deliverOneInvoice(pool, billingMail, () => ({
      verify: async () => { throw new Error('Connexion de recette impossible'); },
      sendMail: async () => { presented += 1; return { rejected: [] }; },
      close: () => undefined,
    }))).toBe(true);
    expect(presented).toBe(0);
    expect(await deliveryRow(unreachable.id)).toMatchObject({ status: 'QUEUED', failure_code: 'SMTP_UNREACHABLE' });
    await pool.query(`UPDATE drivy.platform_invoice_delivery SET available_at=now()+interval '1 hour' WHERE id=$1`, [unreachable.id]);

    const unreadable = await queued(clientId, period.id);
    const transport = smtp();
    expect(await deliverOneInvoice(pool, { ...billingMail, encryptionKey: 'c3'.repeat(32) }, transport.factory)).toBe(true);
    expect(transport.messages).toHaveLength(0);
    expect(await deliveryRow(unreadable.id)).toMatchObject({ status: 'FAILED', failure_code: 'PAYLOAD_INVALID', payload: null });
  });

  it('une issue inconnue n’est jamais rejouée seule et exige un renvoi explicite', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const delivery = await queued(clientId, initial.id);
    const transport = smtpError({ code: 'ESOCKET' });
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(true);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'UNCERTAIN', failure_code: 'SMTP_UNCERTAIN', payload: null });
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(false);
    expect(transport.messages).toHaveLength(1);
    expect(invoiceOf(await billing(clientId), initial.id).sendStatus).toBe('NOT_SENT');
    expect((await preview(clientId, initial.id)).json().data.resend).toBe(true);
    expectProblem(await send(clientId, initial.id), 409, 'INVOICE_DELIVERY_RESEND_REQUIRED');
    expect((await queued(clientId, initial.id, true)).resendOf).toBe(delivery.id);
  });

  it('un bail expiré donne une issue inconnue ; l’écriture tardive de l’ancien service est ignorée', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const delivery = await queued(clientId, initial.id);
    const job = await asMailer(async db => (await db.query('SELECT * FROM drivy.platform_invoice_delivery_claim()')).rows[0]);
    expect(job.job_id).toBe(delivery.id);
    await pool.query(`UPDATE drivy.platform_invoice_delivery SET lease_until=now()-interval '1 second' WHERE id=$1`, [delivery.id]);
    const transport = smtp();
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(false);
    expect(transport.messages).toHaveLength(0);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'UNCERTAIN', failure_code: 'LEASE_EXPIRED', payload: null, lease_id: null });
    const late = await asMailer(db => db.query('SELECT drivy.platform_invoice_delivery_settle($1,$2,$3,$4) AS result', [job.job_id, job.job_lease, 'ACCEPTED', null]));
    expect(late.rows[0].result).toBe('STALE');
    expect(invoiceOf(await billing(clientId), initial.id).sendStatus).toBe('NOT_SENT');
  });

  it('un règlement saisi avant la prise en charge annule l’envoi du QR', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const delivery = await queued(clientId, initial.id);
    await paid(clientId, { amount: 5_000, allocations: [{ invoiceId: initial.id, amount: 5_000 }] });
    const transport = smtp();
    expect(await deliverOneInvoice(pool, billingMail, transport.factory)).toBe(false);
    expect(transport.messages).toHaveLength(0);
    expect(await deliveryRow(delivery.id)).toMatchObject({ status: 'CANCELLED', failure_code: 'SETTLEMENT_CHANGED', payload: null });
    expect(invoiceOf(await billing(clientId), initial.id)).toMatchObject({ sendStatus: 'NOT_SENT', balance: 35_000 });
  });

  it('sans configuration ou sans contact, l’aperçu le dit et rien n’entre en file', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const plain = buildApp({ pool, verifyToken, cursorSecret: 'platform-billing-synthetic-secret-32-characters' });
    try {
      const authorization = `Bearer ${A}`;
      const seen = await plain.inject({ method: 'GET', url: `${invoicePath(clientId, initial.id)}/delivery/preview`, headers: { authorization } });
      expect(seen.json().data.ready).toBe(false);
      expect(seen.json().data.problems.map((item: { code: string }) => item.code)).toContain('BILLING_MAIL_NOT_CONFIGURED');
      const operationId = randomUUID();
      const refused = await plain.inject({
        method: 'POST', url: `${invoicePath(clientId, initial.id)}/delivery`,
        headers: { authorization, 'idempotency-key': operationId, 'if-match': `"${(await billing(clientId)).version}"` },
        payload: { operationId, confirm: true, resend: false },
      });
      expect(refused.statusCode, refused.body).toBe(409);
      expect(refused.json().code).toBe('BILLING_MAIL_NOT_CONFIGURED');
    } finally { await plain.close(); }
    await pool.query('UPDATE drivy.platform_client SET contact_email=NULL WHERE id=$1', [clientId]);
    const missing = (await preview(clientId, initial.id)).json().data;
    expect(missing).toMatchObject({ to: null, ready: false });
    expect(missing.problems.map((item: { code: string }) => item.code)).toContain('BILLING_CONTACT_MISSING');
    expectProblem(await send(clientId, initial.id), 409, 'BILLING_CONTACT_MISSING');
    expect(await count('platform_invoice_delivery')).toBe(0);
  });
});

describe('documents et envois : garde-fous', () => {
  it('un document ne se réécrit pas ; RLS forcée ; contenu chiffré illisible par l’application ; le service d’envoi n’a aucun droit de table', async () => {
    await setIssuer();
    const { clientId, initial } = await invoicedClient();
    const document = (await generated(clientId, initial.id)).documents[0];
    await queued(clientId, initial.id);
    expect((await ownerError('UPDATE drivy.platform_invoice_document SET generator=$2 WHERE id=$1', [document.id, 'autre']))?.message).toMatch(/platform_invoice_document_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_invoice_document WHERE id=$1', [document.id]))?.message).toMatch(/platform_invoice_document_fixed/);
    const rows = (await pool.query<{ forced: boolean }>(`SELECT relforcerowsecurity AS forced FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname IN ('platform_invoice_document','platform_invoice_delivery')`)).rows;
    expect(rows).toHaveLength(2);
    expect(rows.every(row => row.forced)).toBe(true);
    const db = await pool.connect();
    try {
      await db.query('BEGIN'); await db.query('SET LOCAL ROLE drivy_app');
      expect((await db.query('SELECT count(*)::int AS n FROM drivy.platform_invoice_document')).rows[0].n).toBe(0);
      expect((await db.query('SELECT count(id)::int AS n FROM drivy.platform_invoice_delivery')).rows[0].n).toBe(0);
      await db.query('ROLLBACK');
    } finally { db.release(); }
    expect((await roleError('drivy_app', 'SELECT payload FROM drivy.platform_invoice_delivery'))?.code).toBe('42501');
    expect((await roleError('drivy_app', 'SELECT lease_id FROM drivy.platform_invoice_delivery'))?.code).toBe('42501');
    expect((await roleError('drivy_app', 'SELECT * FROM drivy.platform_invoice_delivery_claim()'))?.code).toBe('42501');
    expect((await roleError('drivy_billing_mailer', 'SELECT id FROM drivy.platform_invoice_delivery'))?.code).toBe('42501');
    expect((await roleError('drivy_billing_mailer', 'SELECT id FROM drivy.platform_invoice_document'))?.code).toBe('42501');
  });

  it('les contrôles de la base et de l’API lisent pays et texte de la même façon', async () => {
    for (const value of ['CH', 'ch', ' Suisse ', 'Liechtenstein', 'france', 'Österreich', 'Narnia', '']) {
      const row = (await pool.query<{ value: string | null }>('SELECT drivy.platform_billing_country($1) AS value', [value])).rows[0]!;
      expect(row.value, value).toBe(billingCountry(value));
    }
    for (const value of ['Rue de l’Exemple  1', '  Genève ', 'A – B — C', '“Lilas”']) {
      const row = (await pool.query<{ value: string }>('SELECT drivy.platform_qr_text($1) AS value', [value])).rows[0]!;
      expect(row.value, value).toBe(qrText(value));
    }
  });
});
