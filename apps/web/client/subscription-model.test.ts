import { describe, expect, test } from 'vitest';
import {
  availableActions, invoiceFileName, requestBodyOf, requestStatusLabel, requestSteps, schoolSubscriptionSchema, settlementLabel, subscriptionAttention,
  type SchoolSubscription, type SubscriptionInvoice, type SubscriptionRequest,
} from './subscription-model.js';

/** R01-T08 (#460) : ce que l'écran dit d'une demande et d'une facture. Écrit sans être exécuté (règle du porteur). Données synthétiques. */
const today = '2026-11-22';
const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const base: SchoolSubscription = {
  hasClient: true, today, contact: { name: 'Drivy Exemple', email: 'contact@example.invalid' }, lifecycle: 'PAID', state: 'OFFER_ACTIVE', restriction: null, trial: null,
  paidStartsOn: '2026-11-01', terminationOn: null, nextPeriodStart: '2026-12-01', nextDueOn: null, offer: null, scheduledOffer: null, modules: [], terms: null, scheduledTerms: null,
  debt: null, invoices: [], payments: [], requests: [], availableOffers: [], notices: [], dunning: null, version: 1,
};
const request = (patch: Partial<SubscriptionRequest> = {}): SubscriptionRequest => ({
  id: uuid(1), kind: 'TERMINATION', status: 'RECEIVED', source: 'SCHOOL', requestedOn: '2026-11-20', requestedOfferId: null, requestedOfferName: null, requestedModules: [],
  desiredOn: '2026-12-31', details: null, response: null, effectiveOn: null, decidedAt: null, version: 1, createdAt: '2026-11-20T09:00:00.000Z', revisions: [], ...patch,
});
const invoice = (patch: Partial<SubscriptionInvoice> = {}): SubscriptionInvoice => ({
  id: uuid(2), kind: 'PERIOD', number: '2026-0001', periodStart: '2026-11-01', periodEnd: '2026-11-30', issuedOn: '2026-11-01', dueOn: '2026-12-01', taxAmount: 0, total: 9_900,
  creditsInvoiceNumber: null, settlement: { state: 'UNPAID', allocated: 0, credited: 0, balance: 9_900, overdue: false }, hasDocument: true, ...patch,
});
const draft = { kind: 'OFFER_CHANGE' as const, offerId: null, modules: [] as string[], desiredOn: '', details: '' };

describe('fixture', () => {
  test('respecte le contrat lu par l’écran', () => {
    expect(schoolSubscriptionSchema.safeParse({ ...base, invoices: [invoice()], requests: [request()] }).success).toBe(true);
  });
});

describe('suivi d’une demande', () => {
  test('une résiliation envoyée reste en attente, sans fin effective confirmée', () => {
    expect(requestStatusLabel(request())).toBe('En attente de confirmation');
    expect(requestStatusLabel(request({ status: 'IN_PROGRESS' }))).toBe('En attente de confirmation');
    expect(requestSteps(request(), today).map(step => [step.key, step.state, step.detail])).toEqual([
      ['received', 'done', expect.any(String)], ['decision', 'current', 'En attente'], ['effect', 'upcoming', 'Non confirmée'],
    ]);
  });

  test('demande, décision et fin effective restent trois faits distincts', () => {
    const confirmed = request({ status: 'ACCEPTED', effectiveOn: '2026-12-31', decidedAt: '2026-11-21T10:00:00.000Z', version: 2 });
    expect(requestStatusLabel(confirmed)).toBe('Confirmée');
    expect(requestSteps(confirmed, today).map(step => step.state)).toEqual(['done', 'done', 'upcoming']);
    expect(requestSteps(confirmed, '2026-12-31').map(step => step.state)).toEqual(['done', 'done', 'done']);
  });

  test('une demande refusée, retirée ou reprise n’annonce aucune fin', () => {
    for (const status of ['REFUSED', 'WITHDRAWN', 'REVOKED'] as const) {
      const steps = requestSteps(request({ status, decidedAt: '2026-11-21T10:00:00.000Z' }), today);
      expect(steps.map(step => step.key)).toEqual(['received', 'decision']);
      expect(steps[1]!.state).toBe('stopped');
    }
  });

  test('une régularisation n’a pas d’étape d’effet', () => {
    expect(requestSteps(request({ kind: 'REGULARIZATION', desiredOn: null }), today).map(step => step.key)).toEqual(['received', 'decision']);
    expect(requestStatusLabel(request({ kind: 'REGULARIZATION' }))).toBe('Reçue');
  });
});

describe('actions possibles', () => {
  test('une demande ouverte bloque seulement son type', () => {
    expect(availableActions({ ...base, requests: [request({ kind: 'OFFER_CHANGE' })] })).toEqual({ offerChange: false, termination: true, regularization: true });
  });

  test('une résiliation confirmée garde la seule régularisation', () => {
    expect(availableActions({ ...base, terminationOn: '2026-12-31' })).toEqual({ offerChange: false, termination: false, regularization: true });
    expect(availableActions({ ...base, lifecycle: 'TERMINATED', terminationOn: today })).toEqual({ offerChange: false, termination: false, regularization: true });
  });

  test('sans fiche, rien ne se demande', () => {
    expect(availableActions({ ...base, hasClient: false })).toEqual({ offerChange: false, termination: false, regularization: false });
  });
});

describe('fait le plus urgent', () => {
  const debt = { outstanding: 9_900, overdueAmount: 9_900, overdueCount: 1, oldestOverdueDueOn: '2026-11-01', unallocated: 0 };

  test('rien d’inhabituel, rien à dire', () => { expect(subscriptionAttention(base)).toBeNull(); expect(subscriptionAttention({ ...base, hasClient: false })).toBeNull(); });
  test('le retard propose la régularisation', () => { expect(subscriptionAttention({ ...base, debt })).toMatchObject({ tone: 'danger', title: 'Une facture en retard', regularize: true }); });
  test('la résiliation à venir n’est pas présentée comme terminée', () => {
    expect(subscriptionAttention({ ...base, terminationOn: '2026-12-31' })).toMatchObject({ tone: 'default', title: 'Résiliation confirmée', regularize: false });
  });
  test('la résiliation effective passe avant le retard', () => {
    expect(subscriptionAttention({ ...base, lifecycle: 'TERMINATED', terminationOn: today, debt })).toMatchObject({ title: 'Abonnement résilié', regularize: true });
  });
  test('l’essai terminé reste un état distinct', () => {
    expect(subscriptionAttention({ ...base, lifecycle: 'TRIAL_EXPIRED', trial: { startsAt: '2026-10-01T00:00:00.000Z', endsAt: '2026-11-01T00:00:00.000Z' } }))
      .toMatchObject({ title: 'Essai terminé', regularize: true });
  });
});

/** R01-T09 (#461) : suspension et avertissement vus par l'école. Écrit sans être exécuté (règle du porteur). Données synthétiques. */
describe('suspension', () => {
  const restriction = { reason: 'SUSPENDED' as const, closes: ['WRITE_NEW'], causes: ['PAYMENT' as const] };
  const unpaid = { suspended: true, causes: ['PAYMENT' as const], since: '2026-11-20', invoiceNumber: '2026-0001', dueOn: '2026-08-01', balance: 4_900, suspensionOn: null };

  test('le contrat accepte une suspension et des avis sans demande d’origine', () => {
    expect(schoolSubscriptionSchema.safeParse({ ...base, restriction, dunning: unpaid,
      notices: [{ id: uuid(3), requestId: null, event: 'SUSPENDED', createdAt: '2026-11-20T08:00:00.000Z' }] }).success).toBe(true);
  });
  test('un impayé nomme la facture, son échéance et le reste dû, puis rassure sur l’historique', () => {
    const attention = subscriptionAttention({ ...base, restriction, dunning: unpaid });
    expect(attention).toMatchObject({ tone: 'danger', title: 'Abonnement suspendu', regularize: true });
    expect(attention?.detail).toMatch(/^Facture 2026-0001 échue le .+, reste .+\. L’historique reste consultable\.$/);
  });
  test('une autre décision ne parle pas d’argent', () => {
    expect(subscriptionAttention({ ...base, restriction: { ...restriction, causes: ['MANUAL'] },
      dunning: { ...unpaid, causes: ['MANUAL'], invoiceNumber: null, dueOn: null, balance: null } }))
      .toMatchObject({ title: 'Abonnement suspendu', detail: 'Décision de Drivy. L’historique reste consultable.' });
  });
  test('la restriction seule suffit si le dossier de relance manque', () => {
    expect(subscriptionAttention({ ...base, restriction })).toMatchObject({ title: 'Abonnement suspendu', detail: 'Facture impayée. L’historique reste consultable.' });
  });
  test('la résiliation passe avant la suspension, la suspension avant l’essai terminé', () => {
    expect(subscriptionAttention({ ...base, lifecycle: 'TERMINATED', terminationOn: today, restriction, dunning: unpaid })).toMatchObject({ title: 'Abonnement résilié' });
    expect(subscriptionAttention({ ...base, lifecycle: 'TRIAL_EXPIRED', restriction, dunning: unpaid })).toMatchObject({ title: 'Abonnement suspendu' });
  });
  test('un avertissement remis annonce la date, sans dire que l’école est suspendue', () => {
    const attention = subscriptionAttention({ ...base, dunning: { ...unpaid, suspended: false, causes: [], since: null, suspensionOn: '2026-12-05' } });
    expect(attention?.title).toMatch(/^Suspension prévue le /);
    expect(attention?.title).not.toBe('Abonnement suspendu');
  });
});

describe('corps de la demande', () => {
  test('signale la première zone à corriger', () => {
    expect(requestBodyOf(draft, today)).toMatchObject({ problem: { field: 'choice' } });
    expect(requestBodyOf({ ...draft, kind: 'TERMINATION' }, today)).toMatchObject({ problem: { field: 'desiredOn' } });
    expect(requestBodyOf({ ...draft, kind: 'TERMINATION', desiredOn: '2026-11-21' }, today)).toMatchObject({ problem: { field: 'desiredOn' } });
    expect(requestBodyOf({ ...draft, kind: 'TERMINATION', desiredOn: '2028-01-01' }, today)).toMatchObject({ problem: { field: 'desiredOn' } });
    expect(requestBodyOf({ ...draft, kind: 'REGULARIZATION' }, today)).toMatchObject({ problem: { field: 'details' } });
    expect(requestBodyOf({ ...draft, kind: 'REGULARIZATION', details: ' a ' }, today)).toMatchObject({ problem: { field: 'details' } });
    expect(requestBodyOf({ ...draft, kind: 'REGULARIZATION', details: 'x'.repeat(1001) }, today)).toMatchObject({ problem: { field: 'details' } });
  });

  test('n’envoie que les champs du type de demande', () => {
    expect(requestBodyOf({ ...draft, modules: ['MESSAGING', 'MESSAGING'], desiredOn: today, details: '  Ajouter la messagerie ' }, today))
      .toEqual({ body: { kind: 'OFFER_CHANGE', modules: ['MESSAGING'], desiredOn: today, details: 'Ajouter la messagerie' } });
    expect(requestBodyOf({ kind: 'TERMINATION', offerId: uuid(3), modules: ['MESSAGING'], desiredOn: '2026-12-31', details: '' }, today))
      .toEqual({ body: { kind: 'TERMINATION', desiredOn: '2026-12-31' } });
    expect(requestBodyOf({ kind: 'REGULARIZATION', offerId: uuid(3), modules: ['MESSAGING'], desiredOn: '2020-01-01', details: 'Reprendre le paiement' }, today))
      .toEqual({ body: { kind: 'REGULARIZATION', details: 'Reprendre le paiement' } });
  });
});

describe('factures', () => {
  test('le libellé suit le règlement relu par l’API', () => {
    expect(settlementLabel(invoice())).toEqual({ label: 'À payer', tone: 'attention' });
    expect(settlementLabel(invoice({ settlement: { state: 'PARTIAL', allocated: 1_000, credited: 0, balance: 8_900, overdue: false } })).label).toBe('Partiellement payée');
    expect(settlementLabel(invoice({ settlement: { state: 'PARTIAL', allocated: 1_000, credited: 0, balance: 8_900, overdue: true } }))).toEqual({ label: 'En retard', tone: 'danger' });
    expect(settlementLabel(invoice({ settlement: { state: 'PAID', allocated: 9_900, credited: 0, balance: 0, overdue: false } })).label).toBe('Payée');
    expect(settlementLabel(invoice({ settlement: { state: 'CREDITED', allocated: 0, credited: 9_900, balance: 0, overdue: false } })).label).toBe('Créditée');
    expect(settlementLabel(invoice({ kind: 'CREDIT_NOTE', settlement: null })).label).toBe('Avoir');
  });

  test('le nom du fichier distingue facture et avoir', () => {
    expect(invoiceFileName({ kind: 'PERIOD', number: '2026-0001' })).toBe('facture-2026-0001.pdf');
    expect(invoiceFileName({ kind: 'CREDIT_NOTE', number: '2026-0002' })).toBe('avoir-2026-0002.pdf');
  });
});
