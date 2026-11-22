import { z } from 'zod';
import { iso } from './entitlements-model.js';

/**
 * Règlements manuels (R01-T06, #458). Modèle pur : bornes des saisies et projections. Les soldes, l'état de règlement et la dette se calculent
 * dans la base (`drivy.platform_invoice_settlement`, `drivy.platform_client_debt`, migration 20261118) et ne sont jamais recalculés ici :
 * l'équipe, l'espace école et la suspension lisent le même calcul.
 *
 * Montants : entiers en centimes de CHF. Jours : `AAAA-MM-JJ`, jours civils Europe/Zurich.
 */

export const paymentMethods = ['BANK_TRANSFER', 'CASH', 'OTHER'] as const;
export type PaymentMethod = (typeof paymentMethods)[number];
export const paymentStatuses = ['RECORDED', 'VOIDED'] as const;
export const paymentVoidCauses = ['VOIDED', 'CORRECTED'] as const;
export const allocationStatuses = ['ACTIVE', 'RELEASED'] as const;
export const allocationReleaseCauses = ['MANUAL', 'PAYMENT_VOIDED', 'PAYMENT_CORRECTED'] as const;
export const regularizationKinds = ['REFUND_RECORDED', 'OTHER'] as const;
export const regularizationStatuses = ['ACTIVE', 'CANCELLED'] as const;
/** État de règlement d'une facture émise : réglée, partiellement réglée, à régler, annulée par un avoir. */
export const settlementStates = ['PAID', 'PARTIAL', 'UNPAID', 'CREDITED'] as const;
export type SettlementState = (typeof settlementStates)[number];
/** Plus grand montant d'un règlement : 1 000 000 CHF. */
export const paymentAmountMax = 100_000_000;
/** Affectations données à la saisie, au plus. */
export const paymentAllocationsMax = 50;

// --- Saisies ----------------------------------------------------------------------------------------------------------------

const operationId = z.uuid();
const day = z.iso.date();
const reason = z.string().trim().min(3).max(500);
const amount = z.number().int().min(1).max(paymentAmountMax);
/** Devise saisie telle quelle : une autre que CHF est refusée par la base (`PAYMENT_CURRENCY`), jamais convertie. */
const currency = z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/);
const reference = z.string().trim().max(140).nullable().transform(value => (value === '' ? null : value));
const note = z.string().trim().max(500).nullable().transform(value => (value === '' ? null : value))
  .refine(value => value === null || value.length >= 3, { message: 'Trois caractères au moins.' });
const allocationItem = z.object({ invoiceId: z.uuid(), amount }).strict();
const distinctInvoices = (items: readonly { invoiceId: string }[]) => new Set(items.map(item => item.invoiceId)).size === items.length;

/**
 * Saisie d'un règlement : les affectations sont données (`allocations`), ou réparties d'office de l'échéance la plus ancienne à la plus récente
 * (`spread`), ou absentes (tout reste non affecté). Un doublon probable n'est enregistré qu'avec `confirmDuplicate`.
 */
export const paymentBody = z.object({
  operationId, amount, currency, receivedOn: day, method: z.enum(paymentMethods), reference, note,
  allocations: z.array(allocationItem).max(paymentAllocationsMax), spread: z.boolean(), confirmDuplicate: z.boolean(),
}).strict()
  .refine(body => !(body.spread && body.allocations.length > 0), { path: ['spread'], message: 'Répartition d’office ou affectations données, pas les deux.' })
  .refine(body => distinctInvoices(body.allocations), { path: ['allocations'], message: 'Une facture au plus une fois.' })
  .refine(body => body.allocations.reduce((sum, item) => sum + item.amount, 0) <= body.amount,
    { path: ['allocations'], message: 'Les affectations dépassent le montant du règlement.' });
export type PaymentBody = z.infer<typeof paymentBody>;
export const allocateBody = z.object({ operationId, invoiceId: z.uuid(), amount }).strict();
export const releaseBody = z.object({ operationId, reason }).strict();
export const voidBody = z.object({ operationId, reason, confirm: z.literal(true) }).strict();
/** Correction : le règlement complet tel qu'il aurait dû être saisi, et le motif. L'original reste, annulé. */
export const correctBody = z.object({ operationId, amount, currency, receivedOn: day, method: z.enum(paymentMethods), reference, note, reason }).strict();
export const regularizeBody = z.object({ operationId, amount, kind: z.enum(regularizationKinds), reason }).strict();
export const regularizationCancelBody = z.object({ operationId, reason }).strict();

// --- Lignes de la base (to_jsonb : jours en `AAAA-MM-JJ`, instants en ISO) -------------------------------------------------------

export interface SettlementRow { allocated: number; credited: number; balance: number; state: SettlementState; overdue: boolean }
export interface DebtRow { outstanding: number; overdueAmount: number; overdueCount: number; oldestOverdueDueOn: string | null; unallocated: number }
/** Affectation active vue depuis la facture. */
export interface InvoiceAllocationRow {
  id: string; payment_id: string; amount: number; received_on: string; method: PaymentMethod; created_at: string; created_by_name: string | null;
}
export interface AllocationRow {
  id: string; invoice_id: string; invoice_number: string | null; amount: number; status: (typeof allocationStatuses)[number];
  created_at: string; created_by_name: string | null; released_at: string | null; released_by_name: string | null;
  release_cause: (typeof allocationReleaseCauses)[number] | null; release_reason: string | null;
}
export interface RegularizationRow {
  id: string; amount: number; kind: (typeof regularizationKinds)[number]; reason: string; status: (typeof regularizationStatuses)[number];
  created_at: string; created_by_name: string | null; cancelled_at: string | null; cancelled_by_name: string | null; cancel_reason: string | null;
}
export interface PaymentRow {
  id: string; client_id: string; amount: number; currency: 'CHF'; received_on: string; method: PaymentMethod; reference: string | null; note: string | null;
  status: (typeof paymentStatuses)[number]; corrects_payment_id: string | null; recorded_at: string; voided_at: string | null;
  void_cause: (typeof paymentVoidCauses)[number] | null; void_reason: string | null; version: number;
  // Ajouts de la lecture.
  recorded_by_name: string | null; voided_by_name: string | null; corrected_by_id: string | null; available: number;
  allocations: AllocationRow[]; regularizations: RegularizationRow[];
}

// --- Vues -------------------------------------------------------------------------------------------------------------------

export const settlementView = (row: SettlementRow | null) => row
  ? { state: row.state, allocated: row.allocated, credited: row.credited, balance: row.balance, overdue: row.overdue } : null;
export type SettlementView = NonNullable<ReturnType<typeof settlementView>>;

export const invoiceAllocationView = (row: InvoiceAllocationRow) => ({
  id: row.id, paymentId: row.payment_id, amount: row.amount, receivedOn: row.received_on, method: row.method,
  createdAt: iso(row.created_at)!, createdByName: row.created_by_name,
});

export const debtView = (row: DebtRow) => ({
  outstanding: row.outstanding, overdueAmount: row.overdueAmount, overdueCount: row.overdueCount, oldestOverdueDueOn: row.oldestOverdueDueOn,
  unallocated: row.unallocated,
});
export type DebtView = ReturnType<typeof debtView>;

export function paymentView(row: PaymentRow) {
  const allocations = row.allocations.map(item => ({
    id: item.id, invoiceId: item.invoice_id, invoiceNumber: item.invoice_number, amount: item.amount, status: item.status,
    createdAt: iso(item.created_at)!, createdByName: item.created_by_name, releasedAt: iso(item.released_at), releasedByName: item.released_by_name,
    releaseCause: item.release_cause, releaseReason: item.release_reason,
  }));
  const regularizations = row.regularizations.map(item => ({
    id: item.id, amount: item.amount, kind: item.kind, reason: item.reason, status: item.status, createdAt: iso(item.created_at)!,
    createdByName: item.created_by_name, cancelledAt: iso(item.cancelled_at), cancelledByName: item.cancelled_by_name, cancelReason: item.cancel_reason,
  }));
  const allocated = allocations.filter(item => item.status === 'ACTIVE').reduce((sum, item) => sum + item.amount, 0);
  const regularized = regularizations.filter(item => item.status === 'ACTIVE').reduce((sum, item) => sum + item.amount, 0);
  return {
    id: row.id, clientId: row.client_id, amount: row.amount, currency: row.currency, receivedOn: row.received_on, method: row.method,
    reference: row.reference, note: row.note, status: row.status,
    // `available` est relu en base (`platform_payment_available`) ; `allocated` et `regularized` en sont le détail.
    allocated, regularized, available: row.available,
    correctsPaymentId: row.corrects_payment_id, correctedByPaymentId: row.corrected_by_id,
    recordedAt: iso(row.recorded_at)!, recordedByName: row.recorded_by_name,
    voidedAt: iso(row.voided_at), voidedByName: row.voided_by_name, voidCause: row.void_cause, voidReason: row.void_reason,
    allocations, regularizations, version: row.version,
  };
}
export type PaymentView = ReturnType<typeof paymentView>;
