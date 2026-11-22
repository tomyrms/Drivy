import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { debtSchema, paymentSchema } from '../src/platform-billing-contract.js';
import { invoiceListQuery } from '../src/platform-billing-model.js';
import {
  allocateBody, correctBody, debtView, paymentBody, paymentView, regularizeBody, releaseBody, settlementView, voidBody, type PaymentRow,
} from '../src/platform-payments-model.js';

/**
 * R01-T06 (#458) : bornes des saisies et projections des règlements. Les soldes sont calculés par la base ; ces tests ne vérifient que la saisie
 * et la vue. Écrit sans être exécuté (règle du porteur : aucun test avant la fin de l'epic). Données synthétiques.
 */
const operationId = randomUUID();
const invoiceA = randomUUID(), invoiceB = randomUUID();
const payment = {
  operationId, amount: 10_000, currency: 'chf', receivedOn: '2027-01-20', method: 'BANK_TRANSFER', reference: '', note: '',
  allocations: [], spread: false, confirmDuplicate: false,
};

describe('saisie d’un règlement', () => {
  it('normalise devise, référence et note vides ; refuse montant nul, négatif, décimal ou démesuré', () => {
    expect(paymentBody.parse(payment)).toMatchObject({ currency: 'CHF', reference: null, note: null });
    for (const amount of [0, -100, 10.5, 100_000_001]) expect(paymentBody.safeParse({ ...payment, amount }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, receivedOn: '20.01.2027' }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, method: 'CARD' }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, note: 'ok' }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, extra: true }).success).toBe(false);
  });
  it('une autre devise passe la saisie : la base la refuse sans la convertir', () => {
    expect(paymentBody.parse({ ...payment, currency: 'eur' }).currency).toBe('EUR');
    expect(paymentBody.safeParse({ ...payment, currency: 'EURO' }).success).toBe(false);
  });
  it('affectations : une facture au plus une fois, somme au plus le montant, jamais avec la répartition d’office', () => {
    expect(paymentBody.safeParse({ ...payment, allocations: [{ invoiceId: invoiceA, amount: 6_000 }, { invoiceId: invoiceB, amount: 4_000 }] }).success).toBe(true);
    expect(paymentBody.safeParse({ ...payment, allocations: [{ invoiceId: invoiceA, amount: 6_000 }, { invoiceId: invoiceB, amount: 4_001 }] }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, allocations: [{ invoiceId: invoiceA, amount: 1 }, { invoiceId: invoiceA, amount: 1 }] }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, spread: true, allocations: [{ invoiceId: invoiceA, amount: 1 }] }).success).toBe(false);
    expect(paymentBody.safeParse({ ...payment, spread: true }).success).toBe(true);
  });
  it('annulation confirmée et motivée ; correction complète et motivée ; régularisation typée', () => {
    expect(voidBody.safeParse({ operationId, reason: 'Saisie en double' }).success).toBe(false);
    expect(voidBody.safeParse({ operationId, reason: 'x', confirm: true }).success).toBe(false);
    expect(voidBody.safeParse({ operationId, reason: 'Saisie en double', confirm: true }).success).toBe(true);
    const { allocations: _a, spread: _s, confirmDuplicate: _c, ...fields } = payment;
    expect(correctBody.safeParse({ ...fields, reason: 'Montant mal lu' }).success).toBe(true);
    expect(correctBody.safeParse({ ...fields }).success).toBe(false);
    expect(regularizeBody.safeParse({ operationId, amount: 500, kind: 'REFUND_RECORDED', reason: 'Virement retour du 25.01' }).success).toBe(true);
    expect(regularizeBody.safeParse({ operationId, amount: 500, kind: 'REFUND', reason: 'Virement retour' }).success).toBe(false);
    expect(releaseBody.safeParse({ operationId, reason: 'Mauvaise facture' }).success).toBe(true);
    expect(allocateBody.safeParse({ operationId, invoiceId: invoiceA, amount: 0 }).success).toBe(false);
  });
  it('la liste des factures filtre l’état de règlement, ignoré s’il est vide', () => {
    expect(invoiceListQuery.parse({ settlement: 'PARTIAL' }).settlement).toBe('PARTIAL');
    expect(invoiceListQuery.parse({ settlement: '' }).settlement).toBeUndefined();
    expect(invoiceListQuery.safeParse({ settlement: 'REFUNDED' }).success).toBe(false);
  });
});

const row = (patch: Partial<PaymentRow> = {}): PaymentRow => ({
  id: randomUUID(), client_id: randomUUID(), amount: 12_000, currency: 'CHF', received_on: '2027-01-20', method: 'BANK_TRANSFER', reference: 'Virement 0042',
  note: null, status: 'RECORDED', corrects_payment_id: null, recorded_at: '2027-01-20T09:00:00.000Z', voided_at: null, void_cause: null, void_reason: null,
  version: 1, recorded_by_name: 'Camille Exemple', voided_by_name: null, corrected_by_id: null, available: 1_600,
  allocations: [
    { id: randomUUID(), invoice_id: invoiceA, invoice_number: 'F-2027-00001', amount: 9_900, status: 'ACTIVE', created_at: '2027-01-20T09:00:00.000Z',
      created_by_name: 'Camille Exemple', released_at: null, released_by_name: null, release_cause: null, release_reason: null },
    { id: randomUUID(), invoice_id: invoiceB, invoice_number: 'F-2027-00002', amount: 2_100, status: 'RELEASED', created_at: '2027-01-20T09:00:00.000Z',
      created_by_name: 'Camille Exemple', released_at: '2027-01-21T09:00:00.000Z', released_by_name: 'Jean Exemple', release_cause: 'MANUAL',
      release_reason: 'Mauvaise facture' },
  ],
  regularizations: [
    { id: randomUUID(), amount: 500, kind: 'REFUND_RECORDED', reason: 'Virement retour', status: 'ACTIVE', created_at: '2027-01-22T09:00:00.000Z',
      created_by_name: 'Jean Exemple', cancelled_at: null, cancelled_by_name: null, cancel_reason: null },
  ],
  ...patch,
});

describe('vue d’un règlement', () => {
  it('détaille affecté et régularisé actifs, reprend le reste relu en base ; respecte le contrat', () => {
    const view = paymentView(row());
    expect(view).toMatchObject({ amount: 12_000, allocated: 9_900, regularized: 500, available: 1_600, reference: 'Virement 0042', recordedByName: 'Camille Exemple' });
    expect(view.allocations.map(item => item.status)).toEqual(['ACTIVE', 'RELEASED']);
    expect(paymentSchema.safeParse(view).success).toBe(true);
  });
  it('un règlement corrigé reste lisible, avec son auteur et le lien vers la correction', () => {
    const correctionId = randomUUID();
    const view = paymentView(row({
      status: 'VOIDED', void_cause: 'CORRECTED', void_reason: 'Montant mal lu', voided_at: '2027-01-23T09:00:00.000Z', voided_by_name: 'Jean Exemple',
      corrected_by_id: correctionId, available: 0, regularizations: [],
      allocations: row().allocations.map(item => ({ ...item, status: 'RELEASED' as const, release_cause: 'PAYMENT_CORRECTED' as const, release_reason: null })),
    }));
    expect(view).toMatchObject({ status: 'VOIDED', voidCause: 'CORRECTED', correctedByPaymentId: correctionId, recordedByName: 'Camille Exemple', allocated: 0 });
    expect(paymentSchema.safeParse(view).success).toBe(true);
  });
  it('état de règlement et dette reprennent la base telle quelle', () => {
    expect(settlementView(null)).toBeNull();
    expect(settlementView({ allocated: 4_000, credited: 0, balance: 5_900, state: 'PARTIAL', overdue: true }))
      .toEqual({ state: 'PARTIAL', allocated: 4_000, credited: 0, balance: 5_900, overdue: true });
    const debt = debtView({ outstanding: 5_900, overdueAmount: 5_900, overdueCount: 1, oldestOverdueDueOn: '2027-02-14', unallocated: 1_600 });
    expect(debtSchema.safeParse(debt).success).toBe(true);
  });
});
