import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { zurichDay } from '../src/platform-commercial-model.js';
import { dashboardEnvelope } from '../src/platform-dashboard-contract.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, prepareSchool, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T10 (#462) sur PostgreSQL réelle : droits relus au serveur, période bornée, zéro réel distinct d'une condition manquante, revenu mensuel
 * contractuel avec remise, totaux égaux à la somme des lignes, prochaines actions.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Jeu d'essai synthétique ; IBAN : exemple publié de la norme.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const A = 'op-a';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};
const call = (subject: string, method: 'GET' | 'POST', url: string, body?: Record<string, unknown>, version?: number) => app.inject({
  method, url, headers: {
    authorization: `Bearer ${subject}`,
    ...(body?.operationId ? { 'idempotency-key': String(body.operationId) } : {}),
    ...(version ? { 'if-match': `"${version}"` } : {}),
  },
  ...(body ? { payload: body } : {}),
} as never) as unknown as Promise<{ statusCode: number; body: string; json: () => any }>;

const today = () => zurichDay(new Date());
const read = async (from = today(), to = today()) => {
  const response = await call(A, 'GET', `/v1/platform/dashboard?from=${from}&to=${to}`);
  expect(response.statusCode, response.body).toBe(200);
  expect(dashboardEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
};
const terms = { initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900, recurringDiscount: 900, recurringDiscountMonths: null, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
const issuerFields = {
  legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'CH', email: 'facturation@example.invalid',
  iban: 'CH93 0076 2011 6238 5295 7', taxMode: 'NONE', vatNumber: null, taxRateBp: null, pricesIncludeTax: null, taxNote: 'TVA non applicable',
};
async function commercial(clientId: string, path: string, body: Record<string, unknown>) {
  const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/commercial`)).json().data.version as number;
  const response = await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial${path}`, { operationId: randomUUID(), ...body }, version);
  expect(response.statusCode, response.body).toBeLessThan(300);
}
async function paidClient(conditions: Record<string, unknown> = terms) {
  const created = await call(A, 'POST', '/v1/platform/clients', { operationId: randomUUID(), displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple',
    contactEmail: 'marie@example.invalid', billingStreet: 'Rue des Lilas 2', billingPostalCode: '1200', billingCity: 'Genève', billingCountry: 'CH', schoolId: id.schoolA });
  expect(created.statusCode, created.body).toBe(201);
  const clientId = created.json().data.id as string;
  const offer = await call(A, 'POST', '/v1/platform/offers', { operationId: randomUUID(), name: `Complète ${randomUUID().slice(0, 8)}`, modules: ['MESSAGING'] });
  expect(offer.statusCode, offer.body).toBe(201);
  const rights = (await call(A, 'GET', `/v1/platform/clients/${clientId}/entitlements`)).json().data;
  const assigned = await call(A, 'POST', `/v1/platform/clients/${clientId}/assignments`, { operationId: randomUUID(), offerId: offer.json().data.id }, rights.version);
  expect(assigned.statusCode, assigned.body).toBe(201);
  await commercial(clientId, '/terms', conditions);
  await commercial(clientId, '/paid-start', { startsOn: today(), confirm: true });
  return clientId;
}
async function bill(clientId: string, path: string, body: Record<string, unknown>) {
  const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/billing`)).json().data.version as number;
  return call(A, 'POST', `/v1/platform/clients/${clientId}${path}`, { operationId: randomUUID(), ...body }, version);
}

beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-dashboard-synthetic-secret-32-characters' });
});
beforeEach(async () => {
  await pool.query(`TRUNCATE drivy.platform_billing_issuer, drivy.platform_billing_activation, drivy.platform_invoice, drivy.platform_invoice_counter, drivy.platform_payment,
    drivy.platform_payment_allocation, drivy.platform_payment_regularization, drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation,
    drivy.platform_audit_event, drivy.platform_operator_invitation, drivy.platform_offer, drivy.platform_offer_assignment, drivy.platform_module_adjustment,
    drivy.platform_commercial_terms, drivy.platform_trial_change, drivy.platform_paid_start, drivy.platform_commercial_request, drivy.platform_termination_decision,
    drivy.platform_commercial_notice, drivy.platform_dunning_policy, drivy.platform_dunning_exception, drivy.platform_dunning_step, drivy.platform_commercial_suspension,
    drivy.platform_commercial_alert CASCADE`);
  await pool.query('INSERT INTO drivy.platform_dunning_policy DEFAULT VALUES ON CONFLICT (singleton) DO NOTHING');
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await prepareSchool(pool);
});
afterAll(async () => { await app?.close(); await pool?.end(); });

describe('tableau de bord commercial', () => {
  it('refuse une personne qui n’est pas opérateur et une période invalide', async () => {
    const refused = await call('demo-instructor', 'GET', `/v1/platform/dashboard?from=${today()}&to=${today()}`);
    expect(refused.statusCode, refused.body).toBe(403);
    expect((await call(A, 'GET', '/v1/platform/dashboard?from=2026-02-01&to=2026-01-01')).statusCode).toBe(400);
    expect((await call(A, 'GET', '/v1/platform/dashboard?from=2024-01-01&to=2026-01-01')).statusCode).toBe(400);
    expect((await call(A, 'GET', `/v1/platform/dashboard?from=${today()}`)).statusCode).toBe(400);
  });

  it('rend de vrais zéros sans aucune école', async () => {
    const data = await read();
    expect(data.clients).toEqual([]);
    expect(data.totals).toMatchObject({ clients: 0, invoiced: 0, collected: 0, outstanding: 0, monthly: 0, monthlyMissing: 0 });
  });

  it('calcule le revenu mensuel avec sa remise, hors montant initial', async () => {
    const clientId = await paidClient();
    const data = await read();
    expect(data.totals).toMatchObject({ monthly: 9_000, monthlyClients: 1, invoiced: 0 });
    expect(data.clients.find((item: any) => item.id === clientId)).toMatchObject({ situation: 'ACTIVE', monthly: 9_000, monthlyState: 'DEFINED' });
  });

  it('distingue une mensualité manquante d’un zéro et l’annonce comme action', async () => {
    const clientId = await paidClient();
    // Les routes et la base refusent ce cas après un début payant : on simule une donnée ancienne pour vérifier que l'écran ne la présente pas comme un zéro.
    const db = await pool.connect();
    try {
      await db.query('BEGIN');
      await db.query("SET LOCAL session_replication_role='replica'");
      await db.query('UPDATE drivy.platform_commercial_terms SET monthly_amount=NULL,recurring_discount=0 WHERE client_id=$1', [clientId]);
      await db.query('COMMIT');
    } finally { db.release(); }
    const data = await read();
    const row = data.clients.find((item: any) => item.id === clientId);
    expect(row).toMatchObject({ monthly: null, monthlyState: 'MISSING' });
    expect(data.totals.monthlyMissing).toBe(1);
    expect(row.actions.map((action: any) => action.kind)).toContain('TERMS_MISSING');
  });

  it('garde des totaux égaux à la somme des lignes', async () => {
    const version = (await call(A, 'GET', '/v1/platform/billing/issuer')).json().data.version as number;
    expect((await call(A, 'POST', '/v1/platform/billing/issuer', { operationId: randomUUID(), ...issuerFields }, version)).statusCode).toBeLessThan(300);
    const clientId = await paidClient();
    const draft = await bill(clientId, '/invoices', { kind: 'INITIAL' });
    expect(draft.statusCode, draft.body).toBe(201);
    const invoiceId = draft.json().data.invoices.find((item: any) => item.status === 'DRAFT').id as string;
    expect((await bill(clientId, `/invoices/${invoiceId}/issue`, { confirm: true })).statusCode).toBe(200);
    const payment = await bill(clientId, '/payments', { amount: 10_000, currency: 'CHF', receivedOn: today(), method: 'BANK_TRANSFER', reference: null, note: null,
      allocations: [{ invoiceId, amount: 10_000 }], spread: false, confirmDuplicate: false });
    expect(payment.statusCode, payment.body).toBe(201);
    const data = await read();
    for (const key of ['invoiced', 'collected', 'outstanding', 'overdue'] as const) {
      expect(data.totals[key], key).toBe(data.clients.reduce((sum: number, item: any) => sum + item[key], 0));
    }
    expect(data.totals).toMatchObject({ invoiced: 40_000, collected: 10_000, outstanding: 30_000 });
    // Hors période, le flux disparaît ; la dette du jour reste.
    const past = await read('2020-01-01', '2020-12-31');
    expect(past.totals).toMatchObject({ invoiced: 0, collected: 0, outstanding: 30_000 });
  });
});
