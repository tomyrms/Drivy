import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { ApiError } from '../src/errors.js';
import { termsEffectiveFrom, termsFieldsMissing, termsMissing } from '../src/platform-commercial.js';
import {
  addDays, billingSchedule, commercialDetailView, daysInMonth, decisionBody, isPeriodStart, nextPeriodStart, paidStartBody, periodIndexOf, periodStart, requestBody,
  requestTransitionAllowed, termsAt, termsBody, termsPhase, trialEndBody, zurichDay, type CommercialRow, type TermsRow,
} from '../src/platform-commercial-model.js';
import { commercialDetailEnvelope } from '../src/platform-commercial-contract.js';

/**
 * R01-T04 (#456) : calendrier commercial, conditions par version, échéancier prévisionnel et projection du dossier.
 * Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Données synthétiques ; aucun montant réel.
 */
const operationId = randomUUID();
const refusal = (run: () => unknown) => { try { run(); } catch (error) { return error as ApiError; } throw new Error('Un refus était attendu.'); };

describe('calendrier mensuel à ancre stable', () => {
  it('les mois courts ramènent au dernier jour, puis le jour d’ancre revient : 31, 30, 29 et année bissextile', () => {
    expect([0, 1, 2, 3, 4].map(index => periodStart('2027-01-31', index))).toEqual(['2027-01-31', '2027-02-28', '2027-03-31', '2027-04-30', '2027-05-31']);
    expect([0, 1, 2].map(index => periodStart('2027-12-30', index))).toEqual(['2027-12-30', '2028-01-30', '2028-02-29']);
    expect([0, 1, 2].map(index => periodStart('2026-12-29', index))).toEqual(['2026-12-29', '2027-01-29', '2027-02-28']);
    expect(periodStart('2028-01-31', 1)).toBe('2028-02-29');
    expect(periodStart('2028-02-29', 12)).toBe('2029-02-28');
    expect(periodStart('2028-02-29', 48)).toBe('2032-02-29');
    expect(daysInMonth(2028, 2)).toBe(29); expect(daysInMonth(2100, 2)).toBe(28); expect(daysInMonth(2000, 2)).toBe(29);
    expect(() => periodStart('2027-01-31', -1)).toThrow(RangeError);
  });

  it('une période couvre sans trou ni chevauchement le jour avant la suivante', () => {
    const anchor = '2027-01-31';
    for (let index = 0; index < 24; index += 1) expect(addDays(periodStart(anchor, index + 1), -1) >= periodStart(anchor, index)).toBe(true);
    expect(periodIndexOf(anchor, '2027-01-30')).toBe(-1);
    expect(periodIndexOf(anchor, '2027-01-31')).toBe(0);
    expect(periodIndexOf(anchor, '2027-02-27')).toBe(0);
    expect(periodIndexOf(anchor, '2027-02-28')).toBe(1);
    expect(periodIndexOf(anchor, '2027-03-30')).toBe(1);
    expect(periodIndexOf(anchor, '2027-03-31')).toBe(2);
    expect(isPeriodStart(anchor, '2027-02-28')).toBe(true);
    expect(isPeriodStart(anchor, '2027-03-28')).toBe(false);
    expect(isPeriodStart(anchor, '2026-12-31')).toBe(false);
  });

  it('le prochain début de période est strictement après le jour donné, l’ancre tant qu’elle n’est pas atteinte', () => {
    expect(nextPeriodStart('2027-01-31', '2026-12-01')).toBe('2027-01-31');
    expect(nextPeriodStart('2027-01-31', '2027-01-31')).toBe('2027-02-28');
    expect(nextPeriodStart('2027-01-31', '2027-02-28')).toBe('2027-03-31');
    expect(nextPeriodStart('2027-12-31', '2027-12-31')).toBe('2028-01-31');
  });

  it('le jour commercial est celui de Zurich, y compris autour de minuit et du changement d’heure', () => {
    expect(zurichDay(new Date('2026-11-30T22:59:59Z'))).toBe('2026-11-30');
    expect(zurichDay(new Date('2026-11-30T23:00:00Z'))).toBe('2026-12-01');
    expect(zurichDay(new Date('2027-06-29T21:59:59Z'))).toBe('2027-06-29');
    expect(zurichDay(new Date('2027-06-29T22:00:00Z'))).toBe('2027-06-30');
    expect(zurichDay(new Date('2027-03-28T00:30:00Z'))).toBe('2027-03-28');
  });
});

describe('saisies commerciales', () => {
  it('une version de conditions est entière, en centimes, et ses remises ne dépassent jamais le montant', () => {
    const complete = { operationId, initialAmount: 50_000, monthlyAmount: 9_900, paymentTermDays: 30, suspensionBilling: 'CONTINUE' };
    expect(termsBody.parse(complete)).toMatchObject({ initialDiscount: 0, recurringDiscount: 0, recurringDiscountMonths: null, initialDueOn: null });
    expect(termsBody.safeParse({ ...complete, initialAmount: null, monthlyAmount: null, paymentTermDays: null, suspensionBilling: null }).success).toBe(true);
    expect(termsBody.safeParse({ ...complete, monthlyAmount: 99.5 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, monthlyAmount: -1 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, initialDiscount: 50_001 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, recurringDiscount: 10_000 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, recurringDiscountMonths: 3 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, recurringDiscount: 1_000, recurringDiscountMonths: 3 }).success).toBe(true);
    expect(termsBody.safeParse({ ...complete, initialAmount: null, initialDiscount: 100 }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, currency: 'EUR' }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, suspensionBilling: 'PRORATA' }).success).toBe(false);
    expect(termsBody.safeParse({ ...complete, exceptionReason: 'ok' }).success).toBe(false);
  });

  it('le payant exige une confirmation et une date explicites ; une décision acceptée porte sa date, un refus sa réponse', () => {
    expect(paidStartBody.safeParse({ operationId, startsOn: '2026-12-01', confirm: true }).success).toBe(true);
    expect(paidStartBody.safeParse({ operationId, startsOn: '2026-12-01' }).success).toBe(false);
    expect(paidStartBody.safeParse({ operationId, startsOn: '2026-12-01', confirm: false }).success).toBe(false);
    expect(paidStartBody.safeParse({ operationId, confirm: true }).success).toBe(false);
    expect(decisionBody.safeParse({ operationId, status: 'ACCEPTED' }).success).toBe(false);
    expect(decisionBody.safeParse({ operationId, status: 'ACCEPTED', effectiveOn: '2026-12-01' }).success).toBe(true);
    expect(decisionBody.safeParse({ operationId, status: 'REFUSED' }).success).toBe(false);
    expect(decisionBody.safeParse({ operationId, status: 'REFUSED', response: 'Hors catalogue.' }).success).toBe(true);
    expect(decisionBody.safeParse({ operationId, status: 'REFUSED', response: 'Non.', effectiveOn: '2026-12-01' }).success).toBe(false);
    expect(decisionBody.safeParse({ operationId, status: 'WITHDRAWN', offerId: randomUUID() }).success).toBe(false);
    expect(decisionBody.safeParse({ operationId, status: 'RECEIVED' }).success).toBe(false);
    expect(requestBody.safeParse({ operationId, kind: 'TERMINATION', requestedOn: '2026-11-20', requestedOfferId: randomUUID() }).success).toBe(false);
    expect(requestBody.safeParse({ operationId, kind: 'OFFER_CHANGE', requestedOn: '2026-11-20', requestedOfferId: randomUUID() }).success).toBe(true);
    expect(trialEndBody.safeParse({ operationId }).success).toBe(false);
  });

  it('une décision est définitive ; « en traitement » ne se répète pas', () => {
    expect(requestTransitionAllowed('RECEIVED', 'IN_PROGRESS')).toBe(true);
    expect(requestTransitionAllowed('RECEIVED', 'ACCEPTED')).toBe(true);
    expect(requestTransitionAllowed('IN_PROGRESS', 'REFUSED')).toBe(true);
    expect(requestTransitionAllowed('IN_PROGRESS', 'IN_PROGRESS')).toBe(false);
    for (const from of ['ACCEPTED', 'REFUSED', 'WITHDRAWN'] as const)
      for (const to of ['IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN'] as const) expect(requestTransitionAllowed(from, to), `${from}->${to}`).toBe(false);
  });
});

describe('date d’effet des conditions', () => {
  const today = '2027-02-10';
  it('avant le début payant : aujourd’hui par défaut, toute date à venir acceptée', () => {
    expect(termsEffectiveFrom({ requested: undefined, exceptionReason: undefined, paidStartsOn: null, today })).toBe(today);
    expect(termsEffectiveFrom({ requested: undefined, exceptionReason: undefined, paidStartsOn: '2027-03-15', today })).toBe(today);
    expect(termsEffectiveFrom({ requested: '2027-02-17', exceptionReason: undefined, paidStartsOn: null, today })).toBe('2027-02-17');
  });
  it('après le début payant : prochain début de période par défaut, aucun prorata ; une autre date exige un motif', () => {
    expect(termsEffectiveFrom({ requested: undefined, exceptionReason: undefined, paidStartsOn: '2027-01-31', today })).toBe('2027-02-28');
    expect(termsEffectiveFrom({ requested: '2027-03-31', exceptionReason: undefined, paidStartsOn: '2027-01-31', today })).toBe('2027-03-31');
    expect(refusal(() => termsEffectiveFrom({ requested: '2027-02-15', exceptionReason: undefined, paidStartsOn: '2027-01-31', today })).code).toBe('TERMS_EXCEPTION_REASON_REQUIRED');
    expect(termsEffectiveFrom({ requested: '2027-02-15', exceptionReason: 'Geste commercial', paidStartsOn: '2027-01-31', today })).toBe('2027-02-15');
  });
  it('jamais dans le passé, jamais au-delà d’une saison', () => {
    expect(refusal(() => termsEffectiveFrom({ requested: '2027-02-09', exceptionReason: undefined, paidStartsOn: null, today })).code).toBe('EFFECTIVE_DATE_PAST');
    expect(refusal(() => termsEffectiveFrom({ requested: addDays(today, 367), exceptionReason: undefined, paidStartsOn: null, today })).code).toBe('INVALID_REQUEST');
  });
  it('ce qui reste à compléter est nommé, offre comprise', () => {
    expect(termsFieldsMissing(null)).toEqual(['TERMS']);
    expect(termsFieldsMissing({ initialAmount: null, monthlyAmount: 100, paymentTermDays: null, suspensionBilling: 'PAUSE' })).toEqual(['INITIAL_AMOUNT', 'PAYMENT_TERM']);
    expect(termsMissing({ offer: null, scheduledOffer: null }, { initialAmount: 0, monthlyAmount: 0, paymentTermDays: 0, suspensionBilling: 'CONTINUE' })).toEqual(['OFFER']);
  });
});

const terms = (sequence: number, effectiveFrom: string, extra: Partial<TermsRow> = {}): TermsRow => ({
  id: randomUUID(), sequence, currency: 'CHF', initialAmount: 50_000, initialDiscount: 10_000, initialDueOn: null, monthlyAmount: 9_900,
  recurringDiscount: 0, recurringDiscountMonths: null, paymentTermDays: 30, suspensionBilling: 'CONTINUE', effectiveFrom, exceptionReason: null,
  createdAt: '2027-01-02T09:00:00.000+00:00', createdByName: 'Camille Exemple', ...extra,
});

describe('versions et échéancier prévisionnel', () => {
  it('la version applicable est la plus récente dont la date est atteinte ; une version remplacée avant d’avoir servi le dit', () => {
    const first = terms(1, '2027-01-10'); const second = terms(2, '2027-03-31'); const third = terms(3, '2027-03-31');
    const all = [first, second, third];
    expect(termsAt(all, '2027-01-09')).toBeNull();
    expect(termsAt(all, '2027-03-30')?.sequence).toBe(1);
    expect(termsAt(all, '2027-03-31')?.sequence).toBe(3);
    expect(termsPhase(all, second, '2027-02-10')).toBe('SUPERSEDED');
    expect(termsPhase(all, third, '2027-02-10')).toBe('SCHEDULED');
    expect(termsPhase(all, first, '2027-02-10')).toBe('IN_FORCE');
    expect(termsPhase(all, first, '2027-04-01')).toBe('ENDED');
  });

  it('sans début payant confirmé, aucun montant : un essai, même expiré, ne crée jamais de dette', () => {
    expect(billingSchedule({ paidStartsOn: null, terminationOn: null, terms: [terms(1, '2027-01-01')], today: '2027-02-10' })).toEqual({ initial: null, periods: [] });
  });

  it('montant initial une seule fois, puis mensualités ; la remise récurrente dure le nombre de périodes prévu', () => {
    const schedule = billingSchedule({
      paidStartsOn: '2027-01-31', terminationOn: null, today: '2027-01-20', count: 4,
      terms: [terms(1, '2027-01-20', { recurringDiscount: 1_900, recurringDiscountMonths: 2 })],
    });
    expect(schedule.initial).toEqual({ dueOn: '2027-01-31', amount: 50_000, discount: 10_000, net: 40_000, termsSequence: 1 });
    expect(schedule.periods.map(item => [item.startsOn, item.endsOn, item.net])).toEqual([
      ['2027-01-31', '2027-02-27', 8_000], ['2027-02-28', '2027-03-30', 8_000], ['2027-03-31', '2027-04-29', 9_900], ['2027-04-30', '2027-05-30', 9_900],
    ]);
  });

  it('une nouvelle version s’applique à partir de sa période, et une résiliation arrête les périodes qui commenceraient à sa date', () => {
    const schedule = billingSchedule({
      paidStartsOn: '2027-01-31', terminationOn: '2027-04-30', today: '2027-02-10',
      terms: [terms(1, '2027-01-20'), terms(2, '2027-03-31', { monthlyAmount: 12_900, recurringDiscount: 900, recurringDiscountMonths: 1 })],
    });
    expect(schedule.periods.map(item => [item.startsOn, item.amount, item.net, item.termsSequence])).toEqual([
      ['2027-01-31', 9_900, 9_900, 1], ['2027-02-28', 9_900, 9_900, 1], ['2027-03-31', 12_900, 12_000, 2],
    ]);
  });

  it('une mensualité à compléter reste visible comme telle, sans montant inventé', () => {
    const schedule = billingSchedule({ paidStartsOn: '2027-01-31', terminationOn: null, today: '2027-01-31', count: 2, terms: [terms(1, '2027-01-20', { monthlyAmount: null })] });
    expect(schedule.periods.map(item => [item.amount, item.net])).toEqual([[null, null], [null, null]]);
  });
});

describe('dossier commercial', () => {
  const core = {
    state: 'OFFER_ACTIVE' as const, lifecycle: 'PAID' as const, restriction: null, trial: null, paidStartsOn: '2027-01-31', terminationOn: null,
    assignment: null, scheduled: null, modules: [], version: 4, nextChangeAt: null,
  };
  const paid = { id: randomUUID(), startsOn: '2027-01-31', status: 'ACTIVE' as const, confirmedAt: '2027-01-20T10:00:00.000+00:00', confirmedByName: 'Camille Exemple',
    cancelledAt: null, cancelledByName: null, cancelReason: null };
  const first = terms(1, '2027-01-20');
  const row = (extra: Partial<CommercialRow> = {}): CommercialRow => ({
    core, today: '2027-02-10', termsInForce: first.id, missing: [],
    milestones: { codeIssuedAt: null, schoolCreatedAt: null, schoolLinkedAt: null, activatedAt: '2027-01-05T08:00:00.000+00:00', trialStartsAt: null, paidStartsOn: '2027-01-31' },
    terms: [first], trialChanges: [], paidStarts: [{ ...paid, termsId: first.id }], requests: [], version: 9, ...extra,
  });
  const now = new Date('2027-02-10T10:00:00Z');
  const meta = { requestId: randomUUID(), serverTime: '2027-02-10T10:00:01.000Z' };

  it('facturable seulement avec un début payant confirmé et des conditions complètes ; le contrat accepte la projection', () => {
    const detail = commercialDetailView(row(), now);
    expect(detail.billable).toBe(true);
    expect(detail.paidStart).toMatchObject({ startsOn: '2027-01-31', started: true, termsSequence: 1 });
    expect(detail.nextPeriodStart).toBe('2027-02-28');
    expect(detail.terms.status).toBe('COMPLETE');
    expect(detail.proposedTrialStart).toBe('2027-01-05T08:00:00.000Z');
    expect(commercialDetailEnvelope.safeParse({ data: detail, ...meta }).success).toBe(true);
    const incomplete = commercialDetailView(row({ missing: ['PAYMENT_TERM'] }), now);
    expect(incomplete.billable).toBe(false);
    expect(incomplete.terms).toMatchObject({ status: 'INCOMPLETE', missing: ['PAYMENT_TERM'] });
  });

  it('une résiliation effective n’est plus facturable et la prochaine période n’est annoncée que si elle la précède', () => {
    const termination = {
      id: randomUUID(), kind: 'TERMINATION' as const, status: 'ACCEPTED' as const, requestedOn: '2027-02-01', requestedOfferId: null, requestedOfferName: null,
      desiredOn: null, details: null, response: null, effectiveOn: '2027-02-28', assignmentId: null, decidedAt: '2027-02-02T09:00:00.000+00:00',
      decidedByName: 'Camille Exemple', version: 2, createdAt: '2027-02-01T09:00:00.000+00:00', createdByName: 'Camille Exemple', updatedAt: '2027-02-02T09:00:00.000+00:00',
    };
    const detail = commercialDetailView(row({ requests: [termination] }), now);
    expect(detail.termination).toEqual({ requestId: termination.id, effectiveOn: '2027-02-28', decidedAt: '2027-02-02T09:00:00.000Z' });
    expect(detail.nextPeriodStart).toBeNull();
    expect(detail.schedule.periods.map(item => item.startsOn)).toEqual(['2027-01-31']);
    const ended = commercialDetailView(row({ core: { ...core, lifecycle: 'TERMINATED', restriction: { reason: 'TERMINATED', closes: ['WRITE_NEW'] } }, requests: [termination] }), now);
    expect(ended.billable).toBe(false);
    expect(ended.restriction).toEqual({ reason: 'TERMINATED', closes: ['WRITE_NEW'] });
    expect(commercialDetailEnvelope.safeParse({ data: ended, ...meta }).success).toBe(true);
  });

  it('un essai se lit par sa dernière modification ; le dossier refuse tout champ en plus', () => {
    const trialChanges = [
      { id: randomUUID(), sequence: 1, kind: 'START' as const, startsAt: '2027-01-05T08:00:00+00:00', endsAt: '2027-02-04T23:00:00+00:00', reason: null, createdAt: '2027-01-05T08:00:00+00:00', createdByName: null },
      { id: randomUUID(), sequence: 2, kind: 'EXTEND' as const, startsAt: '2027-01-05T08:00:00+00:00', endsAt: '2027-02-28T23:00:00+00:00', reason: 'Rentrée décalée', createdAt: '2027-02-01T08:00:00+00:00', createdByName: 'Jean Exemple' },
    ];
    const detail = commercialDetailView(row({ core: { ...core, lifecycle: 'TRIAL', paidStartsOn: null }, paidStarts: [], trialChanges }), now);
    expect(detail.trial).toEqual({ startsAt: '2027-01-05T08:00:00.000Z', endsAt: '2027-02-28T23:00:00.000Z', phase: 'RUNNING' });
    expect(detail.trialChanges.map(item => item.kind)).toEqual(['EXTEND', 'START']);
    expect(detail.billable).toBe(false);
    expect(detail.schedule).toEqual({ initial: null, periods: [] });
    for (const extra of ['invoice', 'token', 'messages', 'learners'])
      expect(commercialDetailEnvelope.safeParse({ data: { ...detail, [extra]: 1 }, ...meta }).success, extra).toBe(false);
  });
});
