import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { addDays, maxAheadDays, zurichDay } from '../src/platform-commercial-model.js';
import { schoolSubscriptionEnvelope, subscriptionRequestEnvelope } from '../src/school-subscription-contract.js';
import { subscriptionView, type SubscriptionRow } from '../src/school-subscription.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, prepareSchool, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T08 (#460) sur PostgreSQL réelle : espace abonnement de l'école, demandes et résiliation, révision opérateur, documents, avis.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Jeu d'essai synthétique, aucun montant ni identité réels.
 * Jeton de recette : `Bearer <sujet>`. `demo-admin` est responsable de l'école A ; `demo-instructor` est moniteur en A et responsable en B.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const A = 'op-a', B = 'op-b';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};

beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'school-subscription-synthetic-secret-32-chars' });
});
beforeEach(async () => {
  await pool.query(`TRUNCATE drivy.platform_billing_issuer, drivy.platform_billing_activation, drivy.platform_invoice, drivy.platform_invoice_counter,
    drivy.platform_payment, drivy.platform_payment_allocation, drivy.platform_payment_regularization, drivy.person, drivy.school, drivy.platform_operator,
    drivy.platform_operation, drivy.platform_audit_event, drivy.platform_operator_invitation, drivy.platform_offer, drivy.platform_offer_assignment,
    drivy.platform_module_adjustment, drivy.platform_commercial_terms, drivy.platform_trial_change, drivy.platform_paid_start,
    drivy.platform_commercial_request, drivy.platform_termination_decision, drivy.platform_commercial_notice CASCADE`);
  await seedFixtures(pool, issuer);
  await seedPlatformOperator(pool, A, { displayName: 'Camille Exemple' });
  await seedPlatformOperator(pool, B, { displayName: 'Jean Exemple' });
  await prepareSchool(pool);
});
afterAll(async () => { await app?.close(); await pool?.end(); });

type Method = 'GET' | 'POST';
interface Options { body?: Record<string, unknown>; version?: number | null }
interface Reply { statusCode: number; body: string; rawPayload: Buffer; headers: Record<string, unknown>; json: () => any }
const call = (subject: string | null, method: Method, url: string, options: Options = {}) => app.inject({
  method, url, headers: {
    ...(subject ? { authorization: `Bearer ${subject}` } : {}),
    ...(options.body?.operationId ? { 'idempotency-key': String(options.body.operationId) } : {}),
    ...(options.version ? { 'if-match': `"${options.version}"` } : {}),
  },
  ...(options.body ? { payload: options.body } : {}),
}) as unknown as Promise<Reply>;
const school = (subject: string | null, method: Method, target: string, options: Options = {}, schoolId: string = id.schoolA) =>
  call(subject, method, `/v1/schools/${schoolId}${target}`, options);
function expectProblem(response: Reply, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  expect(response.json()).toMatchObject({ status, code });
}
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);

const today = () => zurichDay(new Date());
const complete = { initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
const address = { billingStreet: 'Rue des Lilas 2', billingPostalCode: '1200', billingCity: 'Genève', billingCountry: 'CH' };
const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid' };
const issuerFields = {
  legalName: 'Drivy Exemple Sàrl', street: 'Rue de l’Exemple 1', postalCode: '1000', city: 'Lausanne', country: 'CH', email: 'facturation@example.invalid',
  iban: 'CH93 0076 2011 6238 5295 7', taxMode: 'NONE', vatNumber: null, taxRateBp: null, pricesIncludeTax: null, taxNote: 'TVA non applicable',
};

async function schoolClient(schoolId: string = id.schoolA) {
  const created = await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, ...address, schoolId } });
  expect(created.statusCode, created.body).toBe(201);
  return created.json().data.id as string;
}
const dossierVersion = async (clientId: string, as = A) => (await call(as, 'GET', `/v1/platform/clients/${clientId}/commercial`)).json().data.version as number;
/** Commande commerciale sous la version courante du dossier (ou celle donnée). */
async function command(clientId: string, path: string, body: Record<string, unknown> = {}, version?: number, as = A) {
  const expected = version ?? await dossierVersion(clientId, as);
  return call(as, 'POST', `/v1/platform/clients/${clientId}/commercial${path}`, { body: { operationId: randomUUID(), ...body }, version: expected });
}
async function newOffer(modules: string[]) {
  const offer = await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: `Offre ${randomUUID().slice(0, 8)}`, modules } });
  expect(offer.statusCode, offer.body).toBe(201);
  return offer.json().data as { id: string; name: string };
}
async function offerInForce(clientId: string, modules = ['MESSAGING', 'COLLECTIVE_COURSES']) {
  const offer = await newOffer(modules);
  const rights = (await call(A, 'GET', `/v1/platform/clients/${clientId}/entitlements`)).json().data;
  const assigned = await call(A, 'POST', `/v1/platform/clients/${clientId}/assignments`, { body: { operationId: randomUUID(), offerId: offer.id }, version: rights.version });
  expect(assigned.statusCode, assigned.body).toBe(201);
  return offer;
}
/** Fiche payante : offre en vigueur, conditions complètes, début payant aujourd'hui. */
async function paidClient() {
  const clientId = await schoolClient();
  await offerInForce(clientId);
  expect((await command(clientId, '/terms', complete)).statusCode).toBe(201);
  expect((await command(clientId, '/paid-start', { startsOn: today(), confirm: true })).statusCode).toBe(201);
  return clientId;
}
async function bill(clientId: string, path: string, body: Record<string, unknown> = {}) {
  const version = (await call(A, 'GET', `/v1/platform/clients/${clientId}/billing`)).json().data.version as number;
  return call(A, 'POST', `/v1/platform/clients/${clientId}${path}`, { body: { operationId: randomUUID(), ...body }, version });
}
/** Facture initiale préparée puis, sauf demande contraire, émise par l'opérateur. */
async function initialInvoice(issue = true) {
  const version = (await call(A, 'GET', '/v1/platform/billing/issuer')).json().data.version as number;
  const configured = await call(A, 'POST', '/v1/platform/billing/issuer', { body: { operationId: randomUUID(), ...issuerFields }, version });
  expect(configured.statusCode, configured.body).toBeLessThan(300);
  const clientId = await paidClient();
  const prepared = await bill(clientId, '/invoices', { kind: 'INITIAL' });
  expect(prepared.statusCode, prepared.body).toBe(201);
  const draft = (prepared.json().data.invoices as any[]).find(item => item.status === 'DRAFT');
  if (!issue) return { clientId, invoice: draft };
  const emitted = await bill(clientId, `/invoices/${draft.id}/issue`, { confirm: true });
  expect(emitted.statusCode, emitted.body).toBe(200);
  return { clientId, invoice: (emitted.json().data.invoices as any[]).find(item => item.id === draft.id) };
}
async function storedDocument(clientId: string, invoiceId: string) {
  const content = Buffer.from('%PDF-1.7 document synthétique');
  await pool.query(`INSERT INTO drivy.platform_invoice_document(id,client_id,invoice_id,revision,payment_mode,amount,content,byte_size,sha256,generator,created_by)
    VALUES ($1,$2,$3,1,'NONE',0,$4,$5,$6,'test',(SELECT id FROM drivy.platform_operator ORDER BY id LIMIT 1))`,
  [randomUUID(), clientId, invoiceId, content, content.length, createHash('sha256').update(content).digest('hex')]);
  return content;
}

async function subscription(subject = 'demo-admin', schoolId: string = id.schoolA) {
  const response = await school(subject, 'GET', '/subscription', {}, schoolId);
  expect(response.statusCode, response.body).toBe(200);
  expect(schoolSubscriptionEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
const ask = (body: Record<string, unknown>, subject = 'demo-admin', operationId: string = randomUUID()) =>
  school(subject, 'POST', '/subscription/requests', { body: { operationId, ...body } });
const withdraw = (requestId: string, version: number, operationId: string = randomUUID(), subject = 'demo-admin', schoolId: string = id.schoolA) =>
  school(subject, 'POST', `/subscription/requests/${requestId}/withdraw`, { body: { operationId }, version }, schoolId);
const decide = (clientId: string, requestId: string, body: Record<string, unknown>) => command(clientId, `/requests/${requestId}/decision`, body);
const revise = (clientId: string, requestId: string, body: Record<string, unknown>) => command(clientId, `/requests/${requestId}/revision`, body);
async function sent(body: Record<string, unknown>) {
  const response = await ask(body);
  expect(response.statusCode, response.body).toBe(201);
  expect(subscriptionRequestEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data as { id: string; status: string; version: number };
}
const documentUrl = (invoiceId: string) => `/subscription/invoices/${invoiceId}/document`;

describe('accès', () => {
  it('seul le responsable actif de cette école entre ; élève, moniteur et personne extérieure sont refusés', async () => {
    await schoolClient();
    expect(await subscription()).toMatchObject({ hasClient: true, lifecycle: 'NONE', invoices: [], payments: [], requests: [] });
    expect((await school(null, 'GET', '/subscription')).statusCode).toBe(401);
    expectProblem(await school('demo-alice', 'GET', '/subscription'), 403, 'COMMERCIAL_ACCESS_REQUIRED');
    expectProblem(await school('demo-instructor', 'GET', '/subscription'), 403, 'COMMERCIAL_ACCESS_REQUIRED');
    expectProblem(await school('demo-foreign', 'GET', '/subscription'), 403, 'ACCESS_DENIED');
    expectProblem(await ask({ kind: 'REGULARIZATION', details: 'Question' }, 'demo-alice'), 403, 'SETUP_ACCESS_REQUIRED');
    expectProblem(await ask({ kind: 'REGULARIZATION', details: 'Question' }, 'demo-instructor'), 403, 'SETUP_ACCESS_REQUIRED');
    expect(await count('platform_commercial_request')).toBe(0);
  });

  it('un rôle cumulé ouvre seulement l’école où il est responsable', async () => {
    const clientA = await schoolClient();
    const request = await sent({ kind: 'REGULARIZATION', details: 'Question de solde' });
    const clientB = await schoolClient(id.schoolB);
    const seen = await subscription('demo-instructor', id.schoolB);
    expect(seen).toMatchObject({ hasClient: true, requests: [] });
    expect(clientB).not.toBe(clientA);
    expectProblem(await withdraw(request.id, 1, randomUUID(), 'demo-instructor', id.schoolB), 404, 'NOT_FOUND');
    expect((await subscription()).requests).toHaveLength(1);
  });

  it('une école sans fiche voit un état vide et ne peut rien demander', async () => {
    expect(await subscription()).toMatchObject({ hasClient: false, lifecycle: 'NONE', state: 'NOT_CONFIGURED', invoices: [], version: 0 });
    expectProblem(await ask({ kind: 'REGULARIZATION', details: 'Question' }), 409, 'COMMERCIAL_CLIENT_MISSING');
  });
});

describe('demandes de l’école', () => {
  it('une demande de changement ne touche ni l’offre ni les modules avant décision ; rejeu, conflit de clé et doublon', async () => {
    const clientId = await schoolClient();
    const current = await offerInForce(clientId);
    const wanted = await newOffer(['MESSAGING']);
    const before = await subscription();
    const body = { kind: 'OFFER_CHANGE', offerId: wanted.id, desiredOn: addDays(today(), 10), details: 'Réduire les modules' };
    const operationId = randomUUID();
    const first = await ask(body, 'demo-admin', operationId);
    expect(first.statusCode, first.body).toBe(201);
    expect(first.json().data).toMatchObject({ status: 'RECEIVED', version: 1 });
    const replay = await ask(body, 'demo-admin', operationId);
    expect(replay.statusCode).toBe(201);
    expect(replay.json().data.id).toBe(first.json().data.id);
    expectProblem(await ask({ ...body, details: 'Un autre texte' }, 'demo-admin', operationId), 409, 'IDEMPOTENCY_MISMATCH');
    expectProblem(await ask(body), 409, 'REQUEST_ALREADY_OPEN');
    expect(await count('platform_commercial_request')).toBe(1);
    const after = await subscription();
    expect(after.modules).toEqual(before.modules);
    expect(after.offer.name).toBe(current.name);
    expect(after.requests[0]).toMatchObject({ source: 'SCHOOL', status: 'RECEIVED', requestedOfferName: wanted.name, effectiveOn: null, decidedAt: null });
  });

  it('une demande de modules seuls reste une demande ; l’école ne s’attribue aucun droit', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId, ['MESSAGING']);
    const before = (await subscription()).modules;
    await sent({ kind: 'OFFER_CHANGE', modules: ['COLLECTIVE_COURSES'] });
    const after = await subscription();
    expect(after.modules).toEqual(before);
    expect(after.requests[0]).toMatchObject({ requestedOfferId: null, requestedModules: ['COLLECTIVE_COURSES'] });
    expect(await count('platform_offer_assignment', `client_id='${clientId}'`)).toBe(1);
  });

  it('deux envois simultanés ne créent qu’une seule demande', async () => {
    await schoolClient();
    const body = { kind: 'TERMINATION', desiredOn: addDays(today(), 30) };
    const replies = await Promise.all([ask(body), ask(body)]);
    expect(replies.map(reply => reply.statusCode).sort()).toEqual([201, 409]);
    expect(await count('platform_commercial_request')).toBe(1);
  });

  it('refuse un contenu incohérent, une date passée ou trop éloignée', async () => {
    await schoolClient();
    expect((await ask({ kind: 'OFFER_CHANGE' })).statusCode).toBe(400);
    expect((await ask({ kind: 'TERMINATION' })).statusCode).toBe(400);
    expect((await ask({ kind: 'REGULARIZATION', modules: ['MESSAGING'] })).statusCode).toBe(400);
    expect((await ask({ kind: 'OFFER_CHANGE', modules: ['INCONNU'] })).statusCode).toBe(400);
    expectProblem(await ask({ kind: 'TERMINATION', desiredOn: addDays(today(), -1) }), 409, 'EFFECTIVE_DATE_PAST');
    expectProblem(await ask({ kind: 'TERMINATION', desiredOn: addDays(today(), maxAheadDays + 1) }), 400, 'INVALID_REQUEST');
    expect(await count('platform_commercial_request')).toBe(0);
  });

  it('le retrait suit la version et reste possible jusqu’à la décision', async () => {
    const clientId = await schoolClient();
    const request = await sent({ kind: 'TERMINATION', desiredOn: addDays(today(), 30), details: 'Fermeture' });
    expect((await decide(clientId, request.id, { status: 'IN_PROGRESS' })).statusCode).toBe(200);
    expectProblem(await withdraw(request.id, 1), 412, 'VERSION_CONFLICT');
    const operationId = randomUUID();
    const done = await withdraw(request.id, 2, operationId);
    expect(done.statusCode, done.body).toBe(200);
    expect(done.json().data).toMatchObject({ id: request.id, status: 'WITHDRAWN', version: 3 });
    expect((await withdraw(request.id, 2, operationId)).json().data.version).toBe(3);
    expectProblem(await withdraw(request.id, 3), 409, 'REQUEST_CLOSED');
    expect((await subscription()).terminationOn).toBeNull();
    expect((await ask({ kind: 'TERMINATION', desiredOn: addDays(today(), 30) })).statusCode).toBe(201);
  });
});

describe('résiliation', () => {
  it('reste en attente jusqu’à la confirmation, puis montre la date d’effet sans fermer avant cette date', async () => {
    const clientId = await paidClient();
    const desired = addDays(today(), 40), effective = addDays(today(), 45);
    const request = await sent({ kind: 'TERMINATION', desiredOn: desired });
    const waiting = await subscription();
    expect(waiting).toMatchObject({ lifecycle: 'PAID', terminationOn: null, restriction: null });
    expect(waiting.requests[0]).toMatchObject({ status: 'RECEIVED', desiredOn: desired, effectiveOn: null, decidedAt: null });

    const accepted = await decide(clientId, request.id, { status: 'ACCEPTED', effectiveOn: effective, response: 'Fin confirmée.' });
    expect(accepted.statusCode, accepted.body).toBe(200);
    const confirmed = await subscription();
    expect(confirmed).toMatchObject({ lifecycle: 'PAID', terminationOn: effective, restriction: null });
    expect(confirmed.requests[0]).toMatchObject({ status: 'ACCEPTED', effectiveOn: effective, response: 'Fin confirmée.' });

    expectProblem(await withdraw(request.id, 2), 409, 'REQUEST_CLOSED');
    expectProblem(await ask({ kind: 'TERMINATION', desiredOn: desired }), 409, 'TERMINATION_CONFIRMED');
    expectProblem(await ask({ kind: 'OFFER_CHANGE', modules: ['MESSAGING'] }), 409, 'CLIENT_TERMINATED');
    expect((await ask({ kind: 'REGULARIZATION', details: 'Question de solde' })).statusCode).toBe(201);
  });

  it('après confirmation, changer la date ou reprendre est une nouvelle décision opérateur visible', async () => {
    const clientId = await paidClient();
    const first = addDays(today(), 30), later = addDays(today(), 60);
    const request = await sent({ kind: 'TERMINATION', desiredOn: first });
    await decide(clientId, request.id, { status: 'ACCEPTED', effectiveOn: first });
    expectProblem(await revise(clientId, request.id, { action: 'CHANGE_DATE', effectiveOn: first, response: 'Même date.' }), 409, 'TERMINATION_DATE_UNCHANGED');
    expect((await revise(clientId, request.id, { action: 'CHANGE_DATE', response: 'Sans date.' })).statusCode).toBe(400);

    const moved = await revise(clientId, request.id, { action: 'CHANGE_DATE', effectiveOn: later, response: 'Date repoussée.' });
    expect(moved.statusCode, moved.body).toBe(200);
    const afterMove = await subscription();
    expect(afterMove.terminationOn).toBe(later);
    expect(afterMove.requests[0].revisions).toEqual([expect.objectContaining({ action: 'CHANGE_DATE', previousEffectiveOn: first, newEffectiveOn: later, response: 'Date repoussée.' })]);

    const resumed = await revise(clientId, request.id, { action: 'RESUME', response: 'Service repris.' });
    expect(resumed.statusCode, resumed.body).toBe(200);
    const afterResume = await subscription();
    expect(afterResume).toMatchObject({ lifecycle: 'PAID', terminationOn: null });
    expect(afterResume.requests[0].status).toBe('REVOKED');
    expect(afterResume.requests[0].revisions).toHaveLength(2);
    expect(afterResume.notices.map((item: { event: string }) => item.event)).toEqual(expect.arrayContaining(['ACCEPTED', 'DATE_CHANGED', 'RESUMED']));
    expect(await count('platform_termination_decision')).toBe(2);
    expect((await ask({ kind: 'TERMINATION', desiredOn: first })).statusCode).toBe(201);
  });

  it('une résiliation déjà effective ne se révise plus ; une régularisation acceptée ne rouvre rien', async () => {
    const clientId = await paidClient();
    const request = await sent({ kind: 'TERMINATION', desiredOn: today() });
    await decide(clientId, request.id, { status: 'ACCEPTED', effectiveOn: today() });
    expect(await subscription()).toMatchObject({ lifecycle: 'TERMINATED', terminationOn: today(), restriction: { reason: 'TERMINATED' } });
    expectProblem(await revise(clientId, request.id, { action: 'RESUME', response: 'Reprise tardive.' }), 409, 'TERMINATION_EFFECTIVE');
    expectProblem(await revise(clientId, request.id, { action: 'CHANGE_DATE', effectiveOn: addDays(today(), 5), response: 'Trop tard.' }), 409, 'TERMINATION_EFFECTIVE');
    const regularization = await sent({ kind: 'REGULARIZATION', details: 'Solde à régulariser' });
    const accepted = await decide(clientId, regularization.id, { status: 'ACCEPTED', effectiveOn: today() });
    expect(accepted.statusCode, accepted.body).toBe(200);
    expect(await subscription()).toMatchObject({ lifecycle: 'TERMINATED', restriction: { reason: 'TERMINATED' } });
  });
});

describe('factures et règlements', () => {
  it('un brouillon reste invisible ; montants et soldes sont ceux de la facture et des écritures confirmées', async () => {
    const draft = await initialInvoice(false);
    expect((await subscription()).invoices).toEqual([]);
    const emitted = await bill(draft.clientId, `/invoices/${draft.invoice.id}/issue`, { confirm: true });
    expect(emitted.statusCode, emitted.body).toBe(200);
    const paid = await bill(draft.clientId, '/payments', {
      amount: 10_000, currency: 'CHF', receivedOn: today(), method: 'BANK_TRANSFER', reference: 'REF-SYNTHETIQUE', note: 'Note interne',
      allocations: [{ invoiceId: draft.invoice.id, amount: 10_000 }], spread: false, confirmDuplicate: false,
    });
    expect(paid.statusCode, paid.body).toBeLessThan(300);
    const seen = await subscription();
    expect(seen.invoices).toHaveLength(1);
    expect(seen.invoices[0]).toMatchObject({ id: draft.invoice.id, kind: 'INITIAL', total: 40_000, hasDocument: false,
      settlement: { state: 'PARTIAL', allocated: 10_000, balance: 30_000, overdue: false } });
    expect(seen.payments).toEqual([expect.objectContaining({ amount: 10_000, method: 'BANK_TRANSFER' })]);
    expect(JSON.stringify(seen.payments)).not.toMatch(/REF-SYNTHETIQUE|Note interne/);
    expect(seen.debt).toMatchObject({ outstanding: 30_000, overdueCount: 0 });
    expect(seen.nextDueOn).toBe(seen.invoices[0].dueOn);
    expect(seen.terms).toMatchObject({ initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900 });
  });

  it('sert le document conservé à son école seulement, sans jamais en générer', async () => {
    const { clientId, invoice } = await initialInvoice();
    expectProblem(await school('demo-admin', 'GET', documentUrl(invoice.id)), 409, 'DOCUMENT_UNAVAILABLE');
    expect(await count('platform_invoice_document')).toBe(0);
    const content = await storedDocument(clientId, invoice.id);
    const file = await school('demo-admin', 'GET', documentUrl(invoice.id));
    expect(file.statusCode, file.body).toBe(200);
    expect(file.headers['content-type']).toContain('application/pdf');
    expect(String(file.headers['content-disposition'])).toContain(`facture-${invoice.number}.pdf`);
    expect(file.headers['cache-control']).toBe('no-store');
    expect(file.rawPayload.equals(content)).toBe(true);
    expect((await subscription()).invoices[0].hasDocument).toBe(true);

    expectProblem(await school('demo-alice', 'GET', documentUrl(invoice.id)), 403, 'COMMERCIAL_ACCESS_REQUIRED');
    expectProblem(await school('demo-instructor', 'GET', documentUrl(invoice.id), {}, id.schoolB), 404, 'NOT_FOUND');
    expectProblem(await school('demo-admin', 'GET', documentUrl(randomUUID())), 404, 'NOT_FOUND');
  });

  it('une école archivée garde factures, contact et demande de régularisation, sans se réactiver', async () => {
    const { clientId, invoice } = await initialInvoice();
    const content = await storedDocument(clientId, invoice.id);
    await pool.query("UPDATE drivy.school SET status='ARCHIVED' WHERE id=$1", [id.schoolA]);
    const seen = await subscription();
    expect(seen.invoices).toHaveLength(1);
    expect(seen.contact).toMatchObject({ email: 'facturation@example.invalid' });
    expect((await school('demo-admin', 'GET', documentUrl(invoice.id))).rawPayload.equals(content)).toBe(true);
    expect((await ask({ kind: 'REGULARIZATION', details: 'Reprendre le paiement' })).statusCode).toBe(201);
    const status = (await pool.query<{ status: string }>('SELECT status FROM drivy.school WHERE id=$1', [id.schoolA])).rows[0]!.status;
    expect(status).toBe('ARCHIVED');
    expectProblem(await school('demo-alice', 'GET', '/subscription'), 403, 'COMMERCIAL_ACCESS_REQUIRED');
  });
});

describe('avis', () => {
  it('une entrée par événement, sans doublon à la relecture ; l’opérateur marque lu', async () => {
    const clientId = await schoolClient();
    const request = await sent({ kind: 'REGULARIZATION', details: 'Question de solde' });
    const list = async () => (await call(A, 'GET', '/v1/platform/commercial-notices')).json().data.items as { id: string; clientId: string; kind: string; event: string }[];
    const first = await list();
    expect(first).toEqual([expect.objectContaining({ clientId, requestId: request.id, kind: 'REGULARIZATION', event: 'RECEIVED' })]);
    expect(await list()).toHaveLength(1);
    expectProblem(await call('demo-admin', 'GET', '/v1/platform/commercial-notices'), 403, 'PLATFORM_OPERATOR_REQUIRED');
    const body = { operationId: randomUUID(), ids: first.map(item => item.id) };
    const read = await call(A, 'POST', '/v1/platform/commercial-notices/read', { body });
    expect(read.statusCode, read.body).toBe(200);
    expect(read.json().data.read).toBe(1);
    expect((await call(A, 'POST', '/v1/platform/commercial-notices/read', { body })).statusCode).toBe(200);
    expect(await list()).toEqual([]);
  });

  it('la réponse de Drivy arrive une fois au responsable, avec un texte générique ; lire ne supprime rien', async () => {
    const clientId = await schoolClient();
    const request = await sent({ kind: 'REGULARIZATION', details: 'Solde de 400 francs' });
    expect((await subscription()).notices).toEqual([]);
    expect((await decide(clientId, request.id, { status: 'IN_PROGRESS' })).statusCode).toBe(200);
    expect((await subscription()).notices.map((item: { event: string }) => item.event)).toEqual(['IN_PROGRESS']);
    expect((await subscription()).notices).toHaveLength(1);

    const pushes = (await pool.query<{ person_id: string; title: string; body: string }>("SELECT person_id,title,body FROM drivy.push_notification WHERE category='COMMERCIAL'")).rows;
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toMatchObject({ person_id: id.admin, title: 'Abonnement' });
    expect(pushes[0]!.body).not.toMatch(/\d|CHF|francs/);

    expectProblem(await school('demo-alice', 'POST', '/subscription/notices/read', { body: { operationId: randomUUID() } }), 403, 'SETUP_ACCESS_REQUIRED');
    const read = await school('demo-admin', 'POST', '/subscription/notices/read', { body: { operationId: randomUUID() } });
    expect(read.statusCode, read.body).toBe(200);
    expect(read.json().data).toEqual({ schoolId: id.schoolA, read: 1 });
    expect((await school('demo-admin', 'POST', '/subscription/notices/read', { body: { operationId: randomUUID() } })).json().data.read).toBe(0);
    expect((await subscription()).notices).toEqual([]);
    expect(await count('platform_commercial_notice', "audience='SCHOOL'")).toBe(1);
  });
});

describe('garde-fous', () => {
  it('les nouvelles tables sont sous RLS forcée et une décision de révision ne se réécrit pas', async () => {
    const clientId = await paidClient();
    const request = await sent({ kind: 'TERMINATION', desiredOn: addDays(today(), 30) });
    await decide(clientId, request.id, { status: 'ACCEPTED', effectiveOn: addDays(today(), 30) });
    await revise(clientId, request.id, { action: 'CHANGE_DATE', effectiveOn: addDays(today(), 40), response: 'Date repoussée.' });
    const rows = (await pool.query<{ relname: string; forced: boolean }>(`SELECT relname, relforcerowsecurity AS forced FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname IN ('platform_termination_decision','platform_commercial_notice')`)).rows;
    expect(rows).toHaveLength(2);
    expect(rows.every(row => row.forced)).toBe(true);
    await pool.query("UPDATE drivy.platform_termination_decision SET response='Réécrit'").catch(() => undefined);
    await pool.query('DELETE FROM drivy.platform_termination_decision').catch(() => undefined);
    expect((await pool.query<{ response: string }>('SELECT response FROM drivy.platform_termination_decision')).rows).toEqual([{ response: 'Date repoussée.' }]);
  });

  it('la prochaine période s’arrête à la résiliation ; une facture en retard n’est pas la prochaine échéance', () => {
    const base: SubscriptionRow = { hasClient: true, today: '2026-11-22', contact: null, version: 1, paidStartsOn: '2026-11-01' };
    expect(subscriptionView(base).nextPeriodStart).toBe('2026-12-01');
    expect(subscriptionView({ ...base, terminationOn: '2026-12-01' }).nextPeriodStart).toBeNull();
    const invoice = { id: randomUUID(), kind: 'PERIOD', number: 'F-1', periodStart: null, periodEnd: null, issuedOn: '2026-10-01', taxAmount: 0, total: 100, creditsInvoiceNumber: null, hasDocument: false } as const;
    const settlement = { state: 'UNPAID', allocated: 0, credited: 0, balance: 100 } as const;
    const view = subscriptionView({ ...base, invoices: [
      { ...invoice, dueOn: '2026-11-01', settlement: { ...settlement, overdue: true } },
      { ...invoice, id: randomUUID(), dueOn: '2026-12-10', settlement: { ...settlement, overdue: false } },
      { ...invoice, id: randomUUID(), dueOn: '2026-12-05', settlement: { ...settlement, state: 'PAID', balance: 0, overdue: false } },
    ] });
    expect(view.nextDueOn).toBe('2026-12-10');
  });
});
