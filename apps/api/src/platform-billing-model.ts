import { z } from 'zod';
import { iso } from './entitlements-model.js';
import { billingSchedule, periodIndexOf, type CommercialDetail } from './platform-commercial-model.js';
import {
  debtView, invoiceAllocationView, paymentView, settlementStates, settlementView,
  type DebtRow, type InvoiceAllocationRow, type PaymentRow, type SettlementRow,
} from './platform-payments-model.js';
import { paymentModes, referenceTypes } from './platform-invoice-qr.js';

/**
 * Factures initiales et mensuelles, avoirs et échéancier (R01-T05, #457). Modèle pur : bornes des saisies, contrôle d'IBAN, calcul de la taxe
 * (miroir de `drivy.platform_invoice_tax`) et projections. Le contenu d'une facture est calculé et figé dans la base
 * (`drivy.platform_invoice_compute`, migration 20261117) ; ce module ne le recalcule pas, il l'expose.
 *
 * Montants : entiers en centimes de CHF. Jours : `AAAA-MM-JJ`, jours civils Europe/Zurich.
 */

export const invoiceKinds = ['INITIAL', 'PERIOD', 'CREDIT_NOTE'] as const;
export type InvoiceKind = (typeof invoiceKinds)[number];
export const invoiceStatuses = ['DRAFT', 'ISSUED', 'CANCELLED'] as const;
export type InvoiceStatus = (typeof invoiceStatuses)[number];
export const invoiceOrigins = ['MANUAL', 'SCHEDULED'] as const;
export const sendStatuses = ['NOT_SENT', 'SENT'] as const;
export const taxModes = ['NONE', 'VAT'] as const;
export const activationStatuses = ['ACTIVE', 'STOPPED'] as const;
/** Lecture d'une période de l'échéancier : rien, brouillon, émise (solde dû ou nul), créditée. */
export const periodBillingStates = ['NOT_DUE', 'DUE', 'DRAFT', 'ISSUED', 'CREDITED'] as const;
export type PeriodBillingState = (typeof periodBillingStates)[number];
/** Périodes montrées après la période en cours dans l'échéancier de facturation. */
export const billingLookahead = 3;
/** Plus grand nombre de périodes rendues par l'échéancier de facturation (au-delà, la liste des factures fait foi). */
export const billingScheduleMax = 36;
export const invoicePageMax = 100;

// --- Contrôles ------------------------------------------------------------------------------------------------------------------

/** IBAN : forme (la base la relit) et clé de contrôle modulo 97 (ISO 13616). Espaces ignorés, lettres en majuscules. */
export function normalizeIban(value: string): string { return value.replace(/\s+/g, '').toUpperCase(); }
export function ibanValid(value: string): boolean {
  const iban = normalizeIban(value);
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  const moved = iban.slice(4) + iban.slice(0, 4);
  let rest = 0;
  for (const char of moved) {
    const digits = /[A-Z]/.test(char) ? String(char.charCodeAt(0) - 55) : char;
    for (const digit of digits) rest = (rest * 10 + Number(digit)) % 97;
  }
  return rest === 1;
}

/**
 * Taxe d'un montant net, arrondie au centime le plus proche (moitié vers le haut), entiers seulement. Même règle que `drivy.platform_invoice_tax`.
 * Prix hors taxe : taxe = net × taux. Prix taxe comprise : taxe = net − net / (1 + taux).
 */
export function invoiceTax(net: number, mode: (typeof taxModes)[number], rateBp: number | null, pricesIncludeTax: boolean | null): number {
  if (mode !== 'VAT' || rateBp === null) return 0;
  const half = (numerator: bigint, denominator: bigint) => (numerator * 2n + denominator) / (2n * denominator);
  if (pricesIncludeTax) return Number(BigInt(net) - half(BigInt(net) * 10000n, BigInt(10000 + rateBp)));
  return Number(half(BigInt(net) * BigInt(rateBp), 10000n));
}
/** Total d'un document : le net, plus la taxe quand les prix sont hors taxe. */
export const invoiceTotal = (net: number, mode: (typeof taxModes)[number], rateBp: number | null, pricesIncludeTax: boolean | null) =>
  mode === 'VAT' && pricesIncludeTax === false ? net + invoiceTax(net, mode, rateBp, pricesIncludeTax) : net;

// --- Saisies ----------------------------------------------------------------------------------------------------------------

const operationId = z.uuid();
const day = z.iso.date();
const reason = z.string().trim().min(3).max(500);
const text = (max: number) => z.string().trim().min(1).max(max);

/** Paramètres de l'émetteur : chaque version redonne tout ; aucune n'est modifiée. La TVA n'est jamais devinée. */
export const issuerBody = z.object({
  operationId,
  legalName: text(150), street: text(200), buildingNumber: text(16).nullable().default(null), postalCode: text(20), city: text(100),
  country: z.string().trim().toUpperCase().regex(/^[A-Z]{2}$/),
  email: z.email().max(254).transform(value => value.toLowerCase()).nullable(),
  // Compte de la QR-facture : suisse ou liechtensteinois, IBAN ou QR-IBAN. Le titulaire est le créancier du QR.
  iban: z.string().max(42).transform(normalizeIban).refine(value => /^(CH|LI)[0-9]{7}[A-Z0-9]{12}$/.test(value) && ibanValid(value), { message: 'IBAN invalide.' }).nullable(),
  accountHolder: text(70).nullable().default(null),
  taxMode: z.enum(taxModes),
  vatNumber: z.string().trim().regex(/^CHE-[0-9]{3}\.[0-9]{3}\.[0-9]{3} (TVA|MWST|IVA)$/).nullable(),
  taxRateBp: z.number().int().min(1).max(5000).nullable(),
  pricesIncludeTax: z.boolean().nullable(),
  taxNote: z.string().trim().min(3).max(200).nullable(),
}).strict().superRefine((body, context) => {
  const vat = body.vatNumber !== null && body.taxRateBp !== null && body.pricesIncludeTax !== null;
  const none = body.vatNumber === null && body.taxRateBp === null && body.pricesIncludeTax === null;
  if (body.taxMode === 'VAT' ? !vat : !none) {
    context.addIssue({ code: 'custom', path: ['taxMode'], message: 'La TVA exige numéro, taux et sens des prix ; sans TVA, aucun des trois.' });
  }
});
export type IssuerBody = z.infer<typeof issuerBody>;

/** Activation de la préparation planifiée : confirmée, datée d'aujourd'hui ou plus tard. */
export const activationBody = z.object({ operationId, startsOn: day, confirm: z.literal(true) }).strict();
export const activationStopBody = z.object({ operationId, reason }).strict();
/** Préparation d'un brouillon : le montant initial, ou une période désignée par son premier jour. */
export const prepareBody = z.object({ operationId, kind: z.enum(['INITIAL', 'PERIOD']), periodStart: day.optional() }).strict()
  .refine(body => (body.kind === 'PERIOD') === (body.periodStart !== undefined), { path: ['periodStart'], message: 'Une période se désigne par son premier jour.' });
export const issueBody = z.object({ operationId, confirm: z.literal(true) }).strict();
export const cancelBody = z.object({ operationId, reason }).strict();
export const creditBody = z.object({ operationId, reason, confirm: z.literal(true) }).strict();
export const sentBody = z.object({ operationId, sentOn: day }).strict();
export const runBody = z.object({ operationId }).strict();
/** Document PDF (R01-T07). `revision` absente : le plus récent. */
export const documentBody = z.object({ operationId }).strict();
export const documentQuery = z.object({ revision: z.coerce.number().int().min(1).max(20).optional() }).strict();
/** Envoi après aperçu : `resend` doit être explicite dès qu'un envoi a pu partir. */
export const deliveryBody = z.object({ operationId, confirm: z.literal(true), resend: z.boolean() }).strict();
export const deliveryStatuses = ['QUEUED', 'PROCESSING', 'ACCEPTED', 'FAILED', 'UNCERTAIN', 'CANCELLED'] as const;

const queryText = (schema: z.ZodType) => z.preprocess(value => (value === '' ? undefined : value), schema.optional());
export const invoiceListQuery = z.object({
  clientId: queryText(z.uuid()), status: queryText(z.enum(invoiceStatuses)), kind: queryText(z.enum(invoiceKinds)),
  sendStatus: queryText(z.enum(sendStatuses)), from: queryText(day), to: queryText(day), dueBefore: queryText(day),
  overdue: queryText(z.enum(['true'])), settlement: queryText(z.enum(settlementStates)),
  limit: z.coerce.number().int().min(1).max(invoicePageMax).default(50), offset: z.coerce.number().int().min(0).max(100_000).default(0),
}).strict();
export type InvoiceListQuery = z.infer<typeof invoiceListQuery>;

// --- Lignes de la base (to_jsonb : jours en `AAAA-MM-JJ`, instants en ISO) -------------------------------------------------------

export interface InvoiceLine {
  code: 'INITIAL' | 'MONTHLY' | 'CREDIT'; label: string; periodStart: string | null; periodEnd: string | null;
  amount: number; discount: number; net: number; termsSequence: number | null;
}
export interface InvoiceRow {
  id: string; client_id: string; kind: InvoiceKind; generation: number; status: InvoiceStatus; origin: (typeof invoiceOrigins)[number];
  paid_start_id: string; period_index: number | null; period_start: string | null; period_end: string | null; credits_invoice_id: string | null;
  terms_id: string | null; terms_sequence: number | null; currency: 'CHF'; lines: InvoiceLine[]; subtotal: number; discount_total: number; net_total: number;
  number: string | null; issued_on: string | null; due_on: string | null; issued_at: string | null; issuer: Record<string, string | null> | null;
  recipient: Record<string, string | null> | null; payment_term_days: number | null; tax_mode: (typeof taxModes)[number] | null; tax_rate_bp: number | null;
  prices_include_tax: boolean | null; tax_amount: number | null; total: number | null; send_status: (typeof sendStatuses)[number]; sent_on: string | null;
  sent_recorded_at: string | null; prepared_at: string; cancelled_at: string | null; reason: string | null; version: number;
  // Ajouts de la lecture.
  client_name: string | null; school_id: string | null; prepared_by_name: string | null; issued_by_name: string | null; cancelled_by_name: string | null;
  sent_recorded_by_name: string | null; credit_note: { id: string; number: string; total: number; issued_on: string } | null;
  credited_number: string | null;
  documents: InvoiceDocumentRow[]; delivery: InvoiceDeliveryRow | null;
  /** Calcul de la base (`platform_invoice_settlement`) : null pour un brouillon, une annulation ou un avoir. */
  settlement: SettlementRow | null; allocations: InvoiceAllocationRow[];
}
/** Document conservé, sans son contenu. */
export interface InvoiceDocumentRow {
  id: string; revision: number; payment_mode: (typeof paymentModes)[number]; reference_type: (typeof referenceTypes)[number] | null; reference: string | null;
  amount: number; byte_size: number; sha256: string; created_at: string; created_by_name: string | null;
}
/** Dernier envoi, sans son contenu chiffré. */
export interface InvoiceDeliveryRow {
  id: string; status: (typeof deliveryStatuses)[number]; recipient_masked: string; attempts: number; failure_code: string | null; document_id: string;
  resend_of: string | null; requested_at: string; requested_by_name: string | null; accepted_at: string | null; finished_at: string | null;
}
export interface IssuerRow {
  id: string; sequence: number; legal_name: string; street: string; building_number: string | null; postal_code: string; city: string; country: string;
  email: string | null; iban: string | null; account_holder: string | null; tax_mode: (typeof taxModes)[number]; vat_number: string | null; tax_rate_bp: number | null; prices_include_tax: boolean | null;
  tax_note: string | null; created_at: string; created_by_name: string | null;
}
export interface ActivationRow {
  id: string; starts_on: string; status: (typeof activationStatuses)[number]; activated_at: string; activated_by_name: string | null;
  stopped_at: string | null; stopped_by_name: string | null; stop_reason: string | null;
}

// --- Vues -------------------------------------------------------------------------------------------------------------------

/**
 * Solde d'un document, relu du calcul de la base (total moins affectations actives, nul si un avoir l'annule). Un brouillon, une annulation ou
 * un avoir n'ont pas de solde. Échue : émise, solde positif, échéance passée au jour de Zurich.
 */
export function invoiceBalance(row: Pick<InvoiceRow, 'kind' | 'status' | 'settlement'>) {
  if (row.kind === 'CREDIT_NOTE' || row.status !== 'ISSUED' || !row.settlement) return { balance: null, overdue: false };
  return { balance: row.settlement.balance, overdue: row.settlement.overdue };
}

export function invoiceView(row: InvoiceRow) {
  const { balance, overdue } = invoiceBalance(row);
  return {
    id: row.id, clientId: row.client_id, clientName: row.client_name, schoolId: row.school_id, kind: row.kind, generation: row.generation,
    status: row.status, origin: row.origin, number: row.number, currency: row.currency,
    period: row.period_start ? { index: row.period_index!, startsOn: row.period_start, endsOn: row.period_end! } : null,
    termsSequence: row.terms_sequence,
    lines: row.lines.map(line => ({
      code: line.code, label: line.label, periodStart: line.periodStart, periodEnd: line.periodEnd, amount: line.amount, discount: line.discount,
      net: line.net, termsSequence: line.termsSequence,
    })),
    subtotal: row.subtotal, discountTotal: row.discount_total, netTotal: row.net_total,
    tax: row.tax_mode === null ? null : { mode: row.tax_mode, rateBp: row.tax_rate_bp, pricesIncludeTax: row.prices_include_tax, amount: row.tax_amount! },
    total: row.total, issuedOn: row.issued_on, dueOn: row.due_on, paymentTermDays: row.payment_term_days, issuedAt: iso(row.issued_at),
    issuedByName: row.issued_by_name,
    issuer: row.issuer ? {
      legalName: row.issuer.legalName ?? '', street: row.issuer.street ?? '', buildingNumber: row.issuer.buildingNumber ?? null,
      postalCode: row.issuer.postalCode ?? '', city: row.issuer.city ?? '', country: row.issuer.country ?? '', email: row.issuer.email ?? null,
      iban: row.issuer.iban ?? null, accountHolder: row.issuer.accountHolder ?? row.issuer.legalName ?? null, vatNumber: row.issuer.vatNumber ?? null,
      taxNote: row.issuer.taxNote ?? null,
    } : null,
    recipient: row.recipient ? {
      name: row.recipient.name ?? '', contactName: row.recipient.contactName ?? null, street: row.recipient.street ?? '',
      postalCode: row.recipient.postalCode ?? '', city: row.recipient.city ?? '', country: row.recipient.country ?? '',
    } : null,
    sendStatus: row.send_status, sentOn: row.sent_on, sentRecordedAt: iso(row.sent_recorded_at), sentRecordedByName: row.sent_recorded_by_name,
    balance, overdue, settlement: invoiceBalance(row).balance === null ? null : settlementView(row.settlement),
    allocations: row.allocations.map(invoiceAllocationView),
    documents: (row.documents ?? []).map(item => ({
      id: item.id, revision: item.revision, paymentMode: item.payment_mode, referenceType: item.reference_type, reference: item.reference, amount: item.amount,
      byteSize: item.byte_size, sha256: item.sha256, createdAt: iso(item.created_at)!, createdByName: item.created_by_name,
    })),
    delivery: row.delivery ? {
      id: row.delivery.id, status: row.delivery.status, recipientMasked: row.delivery.recipient_masked, attempts: row.delivery.attempts,
      failureCode: row.delivery.failure_code, documentId: row.delivery.document_id, resendOf: row.delivery.resend_of, requestedAt: iso(row.delivery.requested_at)!,
      requestedByName: row.delivery.requested_by_name, acceptedAt: iso(row.delivery.accepted_at), finishedAt: iso(row.delivery.finished_at),
    } : null,
    creditNote: row.credit_note ? { id: row.credit_note.id, number: row.credit_note.number, total: row.credit_note.total, issuedOn: row.credit_note.issued_on } : null,
    creditsInvoice: row.credits_invoice_id ? { id: row.credits_invoice_id, number: row.credited_number } : null,
    reason: row.reason, preparedAt: iso(row.prepared_at)!, preparedByName: row.prepared_by_name, cancelledAt: iso(row.cancelled_at),
    cancelledByName: row.cancelled_by_name, version: row.version,
  };
}
export type InvoiceView = ReturnType<typeof invoiceView>;

export const issuerView = (row: IssuerRow) => ({
  id: row.id, sequence: row.sequence, legalName: row.legal_name, street: row.street, buildingNumber: row.building_number ?? null,
  postalCode: row.postal_code, city: row.city, country: row.country, email: row.email, iban: row.iban, accountHolder: row.account_holder ?? null, taxMode: row.tax_mode, vatNumber: row.vat_number, taxRateBp: row.tax_rate_bp, pricesIncludeTax: row.prices_include_tax,
  taxNote: row.tax_note, createdAt: iso(row.created_at)!, createdByName: row.created_by_name,
});

export const activationView = (row: ActivationRow) => ({
  id: row.id, startsOn: row.starts_on, status: row.status, activatedAt: iso(row.activated_at)!, activatedByName: row.activated_by_name,
  stoppedAt: iso(row.stopped_at), stoppedByName: row.stopped_by_name, stopReason: row.stop_reason,
});

/** État de facturation d'un document dû (initial ou période) d'après ses factures. La dernière génération vivante fait foi. */
export function documentState(invoices: readonly InvoiceView[], kind: 'INITIAL' | 'PERIOD', periodStart: string | null, due: boolean) {
  const own = invoices.filter(item => item.kind === kind && item.status !== 'CANCELLED' && (item.period?.startsOn ?? null) === periodStart)
    .sort((a, b) => b.generation - a.generation);
  const latest = own[0] ?? null;
  const state: PeriodBillingState = !latest ? (due ? 'DUE' : 'NOT_DUE')
    : latest.status === 'DRAFT' ? 'DRAFT' : latest.creditNote ? (due ? 'DUE' : 'CREDITED') : 'ISSUED';
  return { state, invoiceId: latest?.id ?? null, number: latest?.number ?? null, total: latest?.total ?? null, balance: latest?.balance ?? null };
}

/**
 * Facturation d'une fiche vue par l'équipe (solde, retards et reste non affecté relus de `platform_client_debt`) : activation, échéancier depuis la première période (période en cours + `billingLookahead`),
 * chaque période annotée de sa facture, puis les factures. L'échéancier reprend `billingSchedule` (R01-T04) : mêmes montants que la base.
 * Une période est « due » si elle a commencé ; une facture créditée redevient due tant qu'aucune nouvelle génération n'est émise.
 */
export function billingView(args: {
  commercial: CommercialDetail; activation: ActivationRow | null; activations: readonly ActivationRow[]; invoices: readonly InvoiceRow[];
  issuerReady: boolean; version: number; payments: readonly PaymentRow[]; debt: DebtRow;
}) {
  const { commercial, activation } = args; const today = commercial.today;
  const invoices = args.invoices.map(row => invoiceView(row));
  const anchor = commercial.paidStart?.startsOn ?? null;
  const current = anchor ? Math.max(0, periodIndexOf(anchor, today)) : 0;
  const schedule = billingSchedule({
    paidStartsOn: anchor, terminationOn: commercial.termination?.effectiveOn ?? null,
    terms: commercial.terms.versions, today: anchor ?? today,
    count: Math.min(billingScheduleMax, current + 1 + billingLookahead),
  });
  const initial = schedule.initial && schedule.initial.net > 0 && anchor
    ? { ...schedule.initial, ...documentState(invoices, 'INITIAL', null, anchor <= today) } : null;
  const periods = schedule.periods.map(period => ({ ...period, ...documentState(invoices, 'PERIOD', period.startsOn, period.startsOn <= today) }));
  const debt = debtView(args.debt);
  return {
    today, billable: commercial.billable, issuerReady: args.issuerReady,
    activation: activation ? activationView(activation) : null, activations: args.activations.map(activationView),
    paidStartsOn: anchor, terminationOn: commercial.termination?.effectiveOn ?? null,
    initial, periods,
    invoices, outstanding: debt.outstanding, overdue: debt.overdueCount, debt,
    payments: args.payments.map(paymentView),
    version: args.version,
  };
}
export type BillingView = ReturnType<typeof billingView>;
