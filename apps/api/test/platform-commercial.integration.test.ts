import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { Pool } from 'pg';
import { buildApp } from '../src/app.js';
import type { Identity } from '../src/auth.js';
import { ApiError } from '../src/errors.js';
import { addDays, nextPeriodStart, zurichDay } from '../src/platform-commercial-model.js';
import { commercialDetailEnvelope } from '../src/platform-commercial-contract.js';
import { fixtureIds as id, seedFixtures } from '../scripts/fixtures.js';
import { freshDatabase, issuer, prepareSchool, seedPlatformOperator } from './support/harness.js';

/**
 * R01-T04 (#456) sur PostgreSQL réelle : conditions par version, essai (début, prolongation, fin anticipée, expiration), début payant,
 * demandes de l'école et décisions, résiliation, fermeture de l'usage nouveau relue au serveur, concurrence et garde-fous de la base.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Jeu d'essai synthétique ; aucun montant ni identité réels.
 * Jeton de recette : `Bearer <sujet>` ; `demo-*` viennent du jeu d'essai de l'API, `op-a` et `op-b` sont des opérateurs de plateforme.
 */
let pool: Pool, app: ReturnType<typeof buildApp>;
const A = 'op-a', B = 'op-b';
const verifyToken = async (header: string | undefined): Promise<Identity> => {
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'AUTHENTICATION_REQUIRED', 'Connexion requise.');
  return { issuer, subject: header.slice(7) };
};

beforeAll(async () => {
  pool = await freshDatabase();
  app = buildApp({ pool, verifyToken, cursorSecret: 'platform-commercial-synthetic-secret-32-chars' });
});
beforeEach(async () => {
  await pool.query(`TRUNCATE drivy.person, drivy.school, drivy.platform_operator, drivy.platform_operation, drivy.platform_audit_event,
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
const school = (subject: string, method: Method, target: string, options: Options = {}) => call(subject, method, `/v1/schools/${id.schoolA}${target}`, options);
function expectProblem(response: Reply, status: number, code: string) {
  expect(response.statusCode, response.body).toBe(status);
  expect(response.json()).toMatchObject({ status, code });
}
const count = async (table: string, where = 'true') => Number((await pool.query<{ n: string }>(`SELECT count(*) AS n FROM drivy.${table} WHERE ${where}`)).rows[0]!.n);
const journal = async (action: string) => (await pool.query(`SELECT * FROM drivy.platform_audit_event WHERE action=$1 ORDER BY occurred_at,id`, [action])).rows;
const ownerError = async (sql: string, params: unknown[] = []) => { try { await pool.query(sql, params); return undefined; } catch (error) { return error as Error & { code?: string }; } };

const today = () => zurichDay(new Date());
const inDays = (days: number) => new Date(Date.now() + days * 86_400_000).toISOString();
const complete = { initialAmount: 50_000, initialDiscount: 10_000, monthlyAmount: 9_900, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
const fiche = { displayName: 'Auto-école des Lilas', contactName: 'Marie Exemple', contactEmail: 'marie@example.invalid' };

async function schoolClient() {
  const created = await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), ...fiche, schoolId: id.schoolA } });
  expect(created.statusCode, created.body).toBe(201);
  return created.json().data.id as string;
}
async function dossier(clientId: string, as = A) {
  const response = await call(as, 'GET', `/v1/platform/clients/${clientId}/commercial`);
  expect(response.statusCode, response.body).toBe(200);
  expect(commercialDetailEnvelope.safeParse(response.json()).success, response.body).toBe(true);
  return response.json().data;
}
/** Commande commerciale sous la version courante du dossier (ou celle donnée). */
async function command(clientId: string, path: string, body: Record<string, unknown> = {}, version?: number, as = A) {
  const expected = version ?? (await dossier(clientId, as)).version;
  return call(as, 'POST', `/v1/platform/clients/${clientId}/commercial${path}`, { body: { operationId: randomUUID(), ...body }, version: expected });
}
async function offerInForce(clientId: string) {
  const offer = await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: `Complète ${randomUUID().slice(0, 8)}`, modules: ['MESSAGING', 'COLLECTIVE_COURSES'] } });
  expect(offer.statusCode, offer.body).toBe(201);
  const rights = (await call(A, 'GET', `/v1/platform/clients/${clientId}/entitlements`)).json().data;
  const assigned = await call(A, 'POST', `/v1/platform/clients/${clientId}/assignments`, { body: { operationId: randomUUID(), offerId: offer.json().data.id }, version: rights.version });
  expect(assigned.statusCode, assigned.body).toBe(201);
  return offer.json().data.id as string;
}
const newCourseType = () => school('demo-admin', 'POST', '/course-types', { body: { operationId: randomUUID(), title: `Type ${randomUUID()}`, description: '' } });
const schoolRights = async () => { const response = await school('demo-alice', 'GET', '/entitlements'); expect(response.statusCode, response.body).toBe(200); return response.json().data; };

describe('accès', () => {
  it('seul un opérateur actif lit ou modifie le dossier commercial ; une école n’y accède jamais', async () => {
    const clientId = await schoolClient();
    expectProblem(await call('demo-admin', 'GET', `/v1/platform/clients/${clientId}/commercial`), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expect((await call(null, 'GET', `/v1/platform/clients/${clientId}/commercial`)).statusCode).toBe(401);
    expectProblem(await call('demo-admin', 'POST', `/v1/platform/clients/${clientId}/commercial/terms`, { body: { operationId: randomUUID(), ...complete }, version: 1 }), 403, 'PLATFORM_OPERATOR_REQUIRED');
    expectProblem(await call(A, 'GET', `/v1/platform/clients/${randomUUID()}/commercial`), 404, 'NOT_FOUND');
    expect(await count('platform_commercial_terms')).toBe(0);
  });
});

describe('école pilote et conditions', () => {
  it('une école sans essai ni début payant reste NONE, sans restriction ni montant', async () => {
    const clientId = await schoolClient();
    const detail = await dossier(clientId);
    expect(detail).toMatchObject({ lifecycle: 'NONE', restriction: null, trial: null, paidStart: null, billable: false, terms: { status: 'NONE', missing: ['OFFER', 'TERMS'] } });
    expect(detail.schedule).toEqual({ initial: null, periods: [] });
    expect(await schoolRights()).toMatchObject({ lifecycle: 'NONE', restriction: null, trialEndsAt: null, paidStartsOn: null, terminationOn: null });
    expect((await newCourseType()).statusCode).toBe(201);
  });

  it('une version incomplète est montrée à compléter ; une nouvelle version ne réécrit jamais l’ancienne ; rejeu et version périmée', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    const first = await command(clientId, '/terms', { ...complete, paymentTermDays: null, suspensionBilling: null });
    expect(first.statusCode, first.body).toBe(201);
    expect(first.json().data.terms).toMatchObject({ status: 'INCOMPLETE', missing: ['PAYMENT_TERM', 'SUSPENSION_BILLING'] });
    const version = first.json().data.version as number;
    const operationId = randomUUID();
    const body = { operationId, ...complete };
    const second = await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial/terms`, { body, version });
    expect(second.statusCode, second.body).toBe(201);
    const replay = await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial/terms`, { body, version });
    expect(replay.statusCode).toBe(201);
    expect(replay.json().data.version).toBe(second.json().data.version);
    expectProblem(await call(A, 'POST', `/v1/platform/clients/${clientId}/commercial/terms`, { body: { ...body, monthlyAmount: 1 }, version }), 409, 'IDEMPOTENCY_MISMATCH');
    expectProblem(await command(clientId, '/terms', complete, version), 412, 'VERSION_CONFLICT');
    expect(await count('platform_commercial_terms')).toBe(2);
    const detail = second.json().data;
    expect(detail.terms.status).toBe('COMPLETE');
    expect(detail.terms.versions.map((item: { sequence: number; phase: string }) => [item.sequence, item.phase])).toEqual([[2, 'IN_FORCE'], [1, 'SUPERSEDED']]);
    const entries = await journal('SET_COMMERCIAL_TERMS');
    expect(entries).toHaveLength(2);
    expect(entries[1].changes).toMatchObject({ sequence: 2, monthlyAmount: 9_900, complete: true });
  });

  it('refuse une date passée, et sans début payant accepte une date à venir quelconque', async () => {
    const clientId = await schoolClient();
    expectProblem(await command(clientId, '/terms', { ...complete, effectiveFrom: addDays(today(), -1) }), 409, 'EFFECTIVE_DATE_PAST');
    const later = await command(clientId, '/terms', { ...complete, effectiveFrom: addDays(today(), 9) });
    expect(later.statusCode, later.body).toBe(201);
    expect(later.json().data.terms).toMatchObject({ inForce: null, scheduled: { sequence: 1, effectiveFrom: addDays(today(), 9) } });
  });
});

describe('essai', () => {
  it('début, fin anticipée : l’usage nouveau se ferme avec la marche à suivre, la lecture reste ; aucun montant n’apparaît', async () => {
    const clientId = await schoolClient();
    const started = await command(clientId, '/trial/start', { endsAt: inDays(30) });
    expect(started.statusCode, started.body).toBe(201);
    expect(started.json().data).toMatchObject({ lifecycle: 'TRIAL', trial: { phase: 'RUNNING' } });
    expect((await schoolRights()).trialEndsAt).toBe(started.json().data.trial.endsAt);
    expectProblem(await command(clientId, '/trial/start', { endsAt: inDays(40) }), 409, 'TRIAL_EXISTS');

    const ended = await command(clientId, '/trial/end', { reason: 'Demande de l’école' });
    expect(ended.statusCode, ended.body).toBe(201);
    expect(ended.json().data).toMatchObject({ lifecycle: 'TRIAL_EXPIRED', restriction: { reason: 'TRIAL_EXPIRED', closes: ['WRITE_NEW'] }, billable: false });
    expect(ended.json().data.schedule).toEqual({ initial: null, periods: [] });
    const rights = await schoolRights();
    expect(rights).toMatchObject({ lifecycle: 'TRIAL_EXPIRED', restriction: { reason: 'TRIAL_EXPIRED', closes: ['WRITE_NEW'] } });
    expect(rights.modules.every((item: { entitled: boolean }) => !item.entitled)).toBe(true);
    const refused = await newCourseType();
    expectProblem(refused, 403, 'MODULE_NOT_ENTITLED');
    expect(refused.json().title).toMatch(/essai/i);
    expect(refused.body).not.toMatch(/CHF|\d{3,}/);
    expect((await school('demo-admin', 'GET', '/course-catalogue')).statusCode).toBe(200);
    expect(await count('platform_paid_start')).toBe(0);
    // Le journal garde l'action, jamais le motif.
    const entries = await journal('END_TRIAL_EARLY');
    expect(JSON.stringify(entries[0].changes)).not.toMatch(/Demande/);
  });

  it('une prolongation rétablit l’usage ; elle doit aller au-delà de la fin actuelle', async () => {
    const clientId = await schoolClient();
    await command(clientId, '/trial/start', { endsAt: inDays(5) });
    await command(clientId, '/trial/end', { reason: 'Pause' });
    expectProblem(await command(clientId, '/trial/extend', { endsAt: inDays(-1), reason: 'Rentrée décalée' }), 409, 'TRIAL_EXTEND_INVALID');
    const extended = await command(clientId, '/trial/extend', { endsAt: inDays(20), reason: 'Rentrée décalée' });
    expect(extended.statusCode, extended.body).toBe(201);
    expect(extended.json().data).toMatchObject({ lifecycle: 'TRIAL', restriction: null });
    expect(extended.json().data.trialChanges.map((item: { kind: string }) => item.kind)).toEqual(['EXTEND', 'END_EARLY', 'START']);
    expect((await newCourseType()).statusCode).toBe(201);
  });

  it('refuse une fin passée et un essai démarré sans fin explicite', async () => {
    const clientId = await schoolClient();
    expectProblem(await command(clientId, '/trial/start', { endsAt: inDays(-1) }), 409, 'TRIAL_END_PAST');
    expect((await command(clientId, '/trial/start', {})).statusCode).toBe(400);
    expect(await count('platform_trial_change')).toBe(0);
  });
});

describe('début payant', () => {
  it('exige une offre, des conditions complètes à sa date et une confirmation explicite', async () => {
    const clientId = await schoolClient();
    expectProblem(await command(clientId, '/paid-start', { startsOn: today(), confirm: true }), 409, 'TERMS_INCOMPLETE');
    await command(clientId, '/terms', complete);
    expectProblem(await command(clientId, '/paid-start', { startsOn: today(), confirm: true }), 409, 'TERMS_INCOMPLETE');
    await offerInForce(clientId);
    expect((await command(clientId, '/paid-start', { startsOn: today() })).statusCode).toBe(400);
    expectProblem(await command(clientId, '/paid-start', { startsOn: addDays(today(), -1), confirm: true }), 409, 'EFFECTIVE_DATE_PAST');
    const paid = await command(clientId, '/paid-start', { startsOn: today(), confirm: true });
    expect(paid.statusCode, paid.body).toBe(201);
    const detail = paid.json().data;
    expect(detail).toMatchObject({ lifecycle: 'PAID', billable: true, paidStart: { startsOn: today(), started: true, termsSequence: 1 } });
    expect(detail.schedule.initial).toMatchObject({ dueOn: today(), amount: 50_000, discount: 10_000, net: 40_000 });
    expect(detail.schedule.periods[0]).toMatchObject({ startsOn: today(), amount: 9_900, net: 9_900 });
    expect(detail.nextPeriodStart).toBe(nextPeriodStart(today(), today()));
    expectProblem(await command(clientId, '/paid-start', { startsOn: addDays(today(), 3), confirm: true }), 409, 'PAID_START_EXISTS');
    expectProblem(await command(clientId, '/paid-start/cancel', { reason: 'Erreur de date' }), 409, 'PAID_START_STARTED');
    expectProblem(await command(clientId, '/trial/start', { endsAt: inDays(10) }), 409, 'TRIAL_CLOSED');
    // La fiche résume le cycle et ses échéances, sans montant.
    const fiche = (await call(A, 'GET', `/v1/platform/clients/${clientId}`)).json().data;
    expect(fiche.commercial).toMatchObject({ lifecycle: 'PAID', paidStartsOn: today(), billingReady: true });
    expect(JSON.stringify(fiche.commercial)).not.toMatch(/9900|50000/);
  });

  it('après le début payant : nouvelle version au prochain début de période, complète, et une autre date demande un motif', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    await command(clientId, '/terms', complete);
    await command(clientId, '/paid-start', { startsOn: today(), confirm: true });
    expectProblem(await command(clientId, '/terms', { ...complete, monthlyAmount: null }), 409, 'TERMS_INCOMPLETE');
    const odd = addDays(today(), 3);
    expectProblem(await command(clientId, '/terms', { ...complete, monthlyAmount: 12_900, effectiveFrom: odd }), 409, 'TERMS_EXCEPTION_REASON_REQUIRED');
    const next = await command(clientId, '/terms', { ...complete, monthlyAmount: 12_900 });
    expect(next.statusCode, next.body).toBe(201);
    expect(next.json().data.terms.scheduled).toMatchObject({ sequence: 2, effectiveFrom: nextPeriodStart(today(), today()) });
    expect(next.json().data.schedule.periods.slice(0, 2).map((item: { amount: number }) => item.amount)).toEqual([9_900, 12_900]);
    const exception = await command(clientId, '/terms', { ...complete, monthlyAmount: 11_900, effectiveFrom: odd, exceptionReason: 'Geste commercial' });
    expect(exception.statusCode, exception.body).toBe(201);
    expect(JSON.stringify((await journal('SET_COMMERCIAL_TERMS')).map(item => item.changes))).not.toMatch(/Geste/);
  });

  it('un début payant à venir s’annule, l’historique le garde', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    await command(clientId, '/terms', complete);
    await command(clientId, '/paid-start', { startsOn: addDays(today(), 5), confirm: true });
    const cancelled = await command(clientId, '/paid-start/cancel', { reason: 'Report demandé' });
    expect(cancelled.statusCode, cancelled.body).toBe(200);
    expect(cancelled.json().data).toMatchObject({ paidStart: null, lifecycle: 'NONE', billable: false });
    expect(cancelled.json().data.paidStarts).toEqual([expect.objectContaining({ status: 'CANCELLED', cancelReason: 'Report demandé' })]);
    expect(await count('platform_paid_start')).toBe(1);
  });

  it('deux confirmations simultanées sous la même version : une seule passe', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    await command(clientId, '/terms', complete);
    const version = (await dossier(clientId)).version;
    const replies = await Promise.all([A, B].map(as => command(clientId, '/paid-start', { startsOn: addDays(today(), 2), confirm: true }, version, as)));
    expect(replies.map(reply => reply.statusCode).sort()).toEqual([201, 412]);
    expect(await count('platform_paid_start', "status='ACTIVE'")).toBe(1);
  });

  it('deux nouvelles versions simultanées : un seul numéro, jamais de doublon', async () => {
    const clientId = await schoolClient();
    const version = (await dossier(clientId)).version;
    const replies = await Promise.all([A, B].map(as => command(clientId, '/terms', complete, version, as)));
    expect(replies.map(reply => reply.statusCode).sort()).toEqual([201, 412]);
    expect(await count('platform_commercial_terms')).toBe(1);
  });
});

describe('demandes et résiliation', () => {
  it('un changement d’offre accepté devient l’attribution en vigueur ; une décision est définitive', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    const wanted = await call(A, 'POST', '/v1/platform/offers', { body: { operationId: randomUUID(), name: `Messagerie ${randomUUID().slice(0, 8)}`, modules: ['MESSAGING'] } });
    const offerId = wanted.json().data.id as string;
    expectProblem(await command(clientId, '/requests', { kind: 'OFFER_CHANGE', requestedOn: addDays(today(), 1), requestedOfferId: offerId }), 409, 'REQUEST_DATE_FUTURE');
    const recorded = await command(clientId, '/requests', { kind: 'OFFER_CHANGE', requestedOn: today(), requestedOfferId: offerId, details: 'Par téléphone' });
    expect(recorded.statusCode, recorded.body).toBe(201);
    const request = recorded.json().data.requests[0];
    expect(request).toMatchObject({ kind: 'OFFER_CHANGE', status: 'RECEIVED', requestedOfferName: wanted.json().data.name });
    const decide = (body: Record<string, unknown>, as = A) => command(clientId, `/requests/${request.id}/decision`, body, undefined, as);
    expect((await decide({ status: 'IN_PROGRESS' })).statusCode).toBe(200);
    const accepted = await decide({ status: 'ACCEPTED', effectiveOn: today() });
    expect(accepted.statusCode, accepted.body).toBe(200);
    expect(accepted.json().data.offer).toMatchObject({ offerId, modules: ['MESSAGING'] });
    expect(accepted.json().data.requests[0]).toMatchObject({ status: 'ACCEPTED', decidedByName: 'Camille Exemple' });
    expect(accepted.json().data.requests[0].assignmentId).toEqual(expect.any(String));
    expectProblem(await decide({ status: 'REFUSED', response: 'Trop tard.' }), 409, 'REQUEST_CLOSED');
    expectProblem(await newCourseType(), 403, 'MODULE_NOT_ENTITLED');
    // Une demande d'une autre fiche n'existe pas ici.
    const other = (await call(A, 'POST', '/v1/platform/clients', { body: { operationId: randomUUID(), displayName: 'Autre école' } })).json().data.id as string;
    expectProblem(await command(other, `/requests/${request.id}/decision`, { status: 'WITHDRAWN' }), 404, 'NOT_FOUND');
  });

  it('une résiliation acceptée ferme l’usage nouveau à sa date, définitivement ; la lecture reste', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    await command(clientId, '/terms', complete);
    await command(clientId, '/paid-start', { startsOn: today(), confirm: true });
    const recorded = await command(clientId, '/requests', { kind: 'TERMINATION', requestedOn: today() });
    const requestId = recorded.json().data.requests[0].id as string;
    expectProblem(await command(clientId, `/requests/${requestId}/decision`, { status: 'ACCEPTED', effectiveOn: addDays(today(), -1) }), 409, 'EFFECTIVE_DATE_PAST');
    const accepted = await command(clientId, `/requests/${requestId}/decision`, { status: 'ACCEPTED', effectiveOn: today() });
    expect(accepted.statusCode, accepted.body).toBe(200);
    expect(accepted.json().data).toMatchObject({ lifecycle: 'TERMINATED', restriction: { reason: 'TERMINATED' }, billable: false, termination: { effectiveOn: today() } });
    expect(await schoolRights()).toMatchObject({ lifecycle: 'TERMINATED', terminationOn: today() });
    const refused = await newCourseType();
    expectProblem(refused, 403, 'MODULE_NOT_ENTITLED');
    expect(refused.json().title).toMatch(/résilié/i);
    expect((await school('demo-admin', 'GET', '/course-catalogue')).statusCode).toBe(200);
    expectProblem(await command(clientId, '/terms', complete), 409, 'CLIENT_TERMINATED');
    const again = await command(clientId, '/requests', { kind: 'TERMINATION', requestedOn: today() });
    expectProblem(await command(clientId, `/requests/${again.json().data.requests[0].id}/decision`, { status: 'ACCEPTED', effectiveOn: today() }), 409, 'CLIENT_TERMINATED');
  });

  it('un refus porte sa réponse ; le journal ne garde jamais le texte libre', async () => {
    const clientId = await schoolClient();
    const recorded = await command(clientId, '/requests', { kind: 'TERMINATION', requestedOn: today(), details: 'Fermeture de l’agence' });
    const requestId = recorded.json().data.requests[0].id as string;
    expect((await command(clientId, `/requests/${requestId}/decision`, { status: 'REFUSED' })).statusCode).toBe(400);
    const refused = await command(clientId, `/requests/${requestId}/decision`, { status: 'REFUSED', response: 'Contrat annuel en cours.' });
    expect(refused.json().data.requests[0]).toMatchObject({ status: 'REFUSED', response: 'Contrat annuel en cours.' });
    const entries = [...await journal('RECORD_COMMERCIAL_REQUEST'), ...await journal('DECIDE_COMMERCIAL_REQUEST')];
    expect(JSON.stringify(entries.map(item => item.changes))).not.toMatch(/agence|annuel/);
  });
});

describe('garde-fous de la base', () => {
  it('rien ne se réécrit ni ne s’efface ; aucune date passée même en écriture directe', async () => {
    const clientId = await schoolClient();
    await offerInForce(clientId);
    await command(clientId, '/terms', complete);
    await command(clientId, '/trial/start', { endsAt: inDays(10) });
    await command(clientId, '/paid-start', { startsOn: addDays(today(), 3), confirm: true });
    await command(clientId, '/requests', { kind: 'TERMINATION', requestedOn: today() });
    expect((await ownerError('UPDATE drivy.platform_commercial_terms SET monthly_amount=1'))?.message).toMatch(/platform_terms_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_commercial_terms'))?.message).toMatch(/platform_terms_fixed/);
    expect((await ownerError('UPDATE drivy.platform_trial_change SET ends_at=now()'))?.message).toMatch(/platform_trial_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_paid_start'))?.message).toMatch(/platform_paid_start_fixed/);
    expect((await ownerError("UPDATE drivy.platform_paid_start SET starts_on=starts_on+1"))?.message).toMatch(/platform_paid_start_fixed/);
    expect((await ownerError('DELETE FROM drivy.platform_commercial_request'))?.message).toMatch(/platform_request_fixed/);
    expect((await ownerError(`INSERT INTO drivy.platform_commercial_terms(client_id,sequence,initial_amount,monthly_amount,payment_term_days,suspension_billing,effective_from)
      VALUES($1,9,0,0,0,'CONTINUE',drivy.zurich_today()-1)`, [clientId]))?.message).toMatch(/platform_terms_backdated/);
  });

  it('les quatre tables commerciales sont sous RLS forcée', async () => {
    const rows = (await pool.query<{ relname: string; forced: boolean }>(`SELECT relname, relforcerowsecurity AS forced FROM pg_class
      WHERE relnamespace='drivy'::regnamespace AND relname IN ('platform_commercial_terms','platform_trial_change','platform_paid_start','platform_commercial_request')`)).rows;
    expect(rows).toHaveLength(4);
    expect(rows.every(row => row.forced)).toBe(true);
  });
});
