import { z } from 'zod';
import {
  activationStatuses, deliveryStatuses, invoiceKinds, invoiceOrigins, invoiceStatuses, periodBillingStates, sendStatuses, taxModes,
} from './platform-billing-model.js';
import {
  allocationReleaseCauses, allocationStatuses, paymentMethods, paymentStatuses, paymentVoidCauses, regularizationKinds, regularizationStatuses,
  settlementStates,
} from './platform-payments-model.js';
import { paymentModes, referenceTypes } from './platform-invoice-qr.js';

/**
 * Extension exécutable du dépôt (R01-T05, #457 ; R01-T06, #458) : factures, avoirs, émetteur, activation, préparation planifiée et règlements manuels.
 * L'OpenAPI canonique 3.11.0 reste immuable. Ces schémas décrivent exactement ce que `src/platform-billing.ts` renvoie ;
 * `contracts/platform-billing.json` en est la projection. Montants en centimes de CHF ; jours en Europe/Zurich.
 */
const timestamp = z.iso.datetime();
const day = z.iso.date();
const cents = z.number().int().min(0);
const nullableText = z.string().nullable();

export const issuerSchema = z.object({
  id: z.uuid(), sequence: z.number().int().min(1), legalName: z.string(), street: z.string(), buildingNumber: nullableText, postalCode: z.string(), city: z.string(),
  country: z.string().regex(/^[A-Z]{2}$/), email: nullableText, iban: nullableText, accountHolder: nullableText, taxMode: z.enum(taxModes), vatNumber: nullableText,
  taxRateBp: z.number().int().min(1).max(5000).nullable(), pricesIncludeTax: z.boolean().nullable(), taxNote: nullableText,
  createdAt: timestamp, createdByName: nullableText,
}).strict();
/** `version` sert d'If-Match : 1 tant qu'aucun paramètre n'existe, puis le prochain numéro de version. */
export const issuerSettingsSchema = z.object({
  current: issuerSchema.nullable(), versions: z.array(issuerSchema).max(50), version: z.number().int().min(1),
}).strict();

const invoiceLineSchema = z.object({
  code: z.enum(['INITIAL', 'MONTHLY', 'CREDIT']), label: z.string(), periodStart: day.nullable(), periodEnd: day.nullable(),
  amount: cents, discount: cents, net: cents, termsSequence: z.number().int().min(1).nullable(),
}).strict();
/**
 * Facture ou avoir. Les zones figées (numéro, émetteur, destinataire, taxe, total, dates) sont nulles tant que le document est un brouillon.
 * `balance` et `overdue` viennent de `settlement`, calculé par la base : total moins les affectations actives, zéro après un avoir.
 * Null pour un brouillon, une annulation ou un avoir. Un téléchargement, un QR ou une déclaration de l'école ne changent jamais ce solde.
 */
export const settlementSchema = z.object({
  state: z.enum(settlementStates), allocated: cents, credited: cents, balance: cents, overdue: z.boolean(),
}).strict();
export const invoiceAllocationSchema = z.object({
  id: z.uuid(), paymentId: z.uuid(), amount: cents, receivedOn: day, method: z.enum(paymentMethods), createdAt: timestamp, createdByName: nullableText,
}).strict();
/** Document PDF conservé (R01-T07). Son contenu ne passe que par le téléchargement authentifié. */
export const invoiceDocumentSchema = z.object({
  id: z.uuid(), revision: z.number().int().min(1).max(20), paymentMode: z.enum(paymentModes), referenceType: z.enum(referenceTypes).nullable(),
  reference: nullableText, amount: cents, byteSize: z.number().int().min(1), sha256: z.string().regex(/^[0-9a-f]{64}$/), createdAt: timestamp, createdByName: nullableText,
}).strict();
/** Dernier envoi. `ACCEPTED` : accepté par le serveur SMTP, ni livraison ni lecture prouvées. `UNCERTAIN` : issue inconnue, jamais rejoué seul. */
export const invoiceDeliverySchema = z.object({
  id: z.uuid(), status: z.enum(deliveryStatuses), recipientMasked: z.string(), attempts: z.number().int().min(0).max(5), failureCode: nullableText,
  documentId: z.uuid(), resendOf: z.uuid().nullable(), requestedAt: timestamp, requestedByName: nullableText, acceptedAt: timestamp.nullable(), finishedAt: timestamp.nullable(),
}).strict();
export const deliveryPreviewSchema = z.object({
  to: nullableText, subject: z.string(), text: z.string(), fileName: z.string(), paymentMode: z.enum(paymentModes), amount: cents, resend: z.boolean(), ready: z.boolean(),
  problems: z.array(z.object({ code: z.string(), message: z.string() }).strict()).max(10),
}).strict();
export const invoiceSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), clientName: nullableText, schoolId: z.uuid().nullable(), kind: z.enum(invoiceKinds),
  generation: z.number().int().min(1), status: z.enum(invoiceStatuses), origin: z.enum(invoiceOrigins), number: nullableText, currency: z.literal('CHF'),
  period: z.object({ index: z.number().int().min(0), startsOn: day, endsOn: day }).strict().nullable(),
  termsSequence: z.number().int().min(1).nullable(), lines: z.array(invoiceLineSchema).min(1).max(10),
  subtotal: cents, discountTotal: cents, netTotal: cents,
  tax: z.object({ mode: z.enum(taxModes), rateBp: z.number().int().nullable(), pricesIncludeTax: z.boolean().nullable(), amount: cents }).strict().nullable(),
  total: cents.nullable(), issuedOn: day.nullable(), dueOn: day.nullable(), paymentTermDays: z.number().int().min(0).nullable(), issuedAt: timestamp.nullable(),
  issuedByName: nullableText,
  issuer: z.object({
    legalName: z.string(), street: z.string(), buildingNumber: nullableText, postalCode: z.string(), city: z.string(), country: z.string(), email: nullableText,
    iban: nullableText, accountHolder: nullableText, vatNumber: nullableText, taxNote: nullableText,
  }).strict().nullable(),
  recipient: z.object({
    name: z.string(), contactName: nullableText, street: z.string(), postalCode: z.string(), city: z.string(), country: z.string(),
  }).strict().nullable(),
  sendStatus: z.enum(sendStatuses), sentOn: day.nullable(), sentRecordedAt: timestamp.nullable(), sentRecordedByName: nullableText,
  balance: cents.nullable(), overdue: z.boolean(), settlement: settlementSchema.nullable(), allocations: z.array(invoiceAllocationSchema).max(200),
  documents: z.array(invoiceDocumentSchema).max(20), delivery: invoiceDeliverySchema.nullable(),
  creditNote: z.object({ id: z.uuid(), number: z.string(), total: cents, issuedOn: day }).strict().nullable(),
  creditsInvoice: z.object({ id: z.uuid(), number: nullableText }).strict().nullable(),
  reason: nullableText, preparedAt: timestamp, preparedByName: nullableText, cancelledAt: timestamp.nullable(), cancelledByName: nullableText,
  version: z.number().int().min(1),
}).strict();

/**
 * Règlement saisi à la main. `available` (relu en base) = montant moins affectations actives moins régularisations actives.
 * Un règlement annulé ou corrigé reste lisible avec son auteur ; `correctsPaymentId` et `correctedByPaymentId` relient original et correction.
 */
export const paymentSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), amount: cents, currency: z.literal('CHF'), receivedOn: day, method: z.enum(paymentMethods),
  reference: nullableText, note: nullableText, status: z.enum(paymentStatuses), allocated: cents, regularized: cents, available: cents,
  correctsPaymentId: z.uuid().nullable(), correctedByPaymentId: z.uuid().nullable(), recordedAt: timestamp, recordedByName: nullableText,
  voidedAt: timestamp.nullable(), voidedByName: nullableText, voidCause: z.enum(paymentVoidCauses).nullable(), voidReason: nullableText,
  allocations: z.array(z.object({
    id: z.uuid(), invoiceId: z.uuid(), invoiceNumber: nullableText, amount: cents, status: z.enum(allocationStatuses), createdAt: timestamp,
    createdByName: nullableText, releasedAt: timestamp.nullable(), releasedByName: nullableText, releaseCause: z.enum(allocationReleaseCauses).nullable(),
    releaseReason: nullableText,
  }).strict()),
  regularizations: z.array(z.object({
    id: z.uuid(), amount: cents, kind: z.enum(regularizationKinds), reason: z.string(), status: z.enum(regularizationStatuses), createdAt: timestamp,
    createdByName: nullableText, cancelledAt: timestamp.nullable(), cancelledByName: nullableText, cancelReason: nullableText,
  }).strict()),
  version: z.number().int().min(1),
}).strict();
/** Dette d'une école, même calcul (`platform_client_debt`) pour l'équipe, l'espace école et la suspension. */
export const debtSchema = z.object({
  outstanding: cents, overdueAmount: cents, overdueCount: z.number().int().min(0), oldestOverdueDueOn: day.nullable(), unallocated: cents,
}).strict();

export const activationSchema = z.object({
  id: z.uuid(), startsOn: day, status: z.enum(activationStatuses), activatedAt: timestamp, activatedByName: nullableText,
  stoppedAt: timestamp.nullable(), stoppedByName: nullableText, stopReason: nullableText,
}).strict();
const documentStateFields = {
  state: z.enum(periodBillingStates), invoiceId: z.uuid().nullable(), number: nullableText, total: cents.nullable(), balance: cents.nullable(),
};
/**
 * Facturation d'une fiche. `version` sert d'If-Match aux commandes de facturation. `periods` part de la première période et va jusqu'à
 * la période en cours plus trois (au plus 36) ; chaque période porte l'état de sa facture.
 */
export const billingSchema = z.object({
  today: day, billable: z.boolean(), issuerReady: z.boolean(), activation: activationSchema.nullable(), activations: z.array(activationSchema).max(20),
  paidStartsOn: day.nullable(), terminationOn: day.nullable(),
  initial: z.object({ dueOn: day, amount: cents, discount: cents, net: cents, termsSequence: z.number().int().min(1), ...documentStateFields }).strict().nullable(),
  periods: z.array(z.object({
    index: z.number().int().min(0), startsOn: day, endsOn: day, amount: cents.nullable(), discount: cents, net: cents.nullable(),
    termsSequence: z.number().int().min(1).nullable(), ...documentStateFields,
  }).strict()).max(36),
  invoices: z.array(invoiceSchema).max(200), outstanding: cents, overdue: z.number().int().min(0), debt: debtSchema,
  payments: z.array(paymentSchema).max(200), version: z.number().int().min(1),
}).strict();
export const invoicePageSchema = z.object({
  items: z.array(invoiceSchema).max(100), total: z.number().int().min(0), limit: z.number().int().min(1), offset: z.number().int().min(0), today: day,
}).strict();
export const billingRunSchema = z.union([
  z.object({ skipped: z.literal(true) }).strict(),
  z.object({
    skipped: z.literal(false), today: day, clients: z.number().int().min(0), prepared: z.number().int().min(0), issued: z.number().int().min(0),
    waiting: z.number().int().min(0), failed: z.number().int().min(0),
  }).strict(),
]);

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const issuerSettingsEnvelope = envelope(issuerSettingsSchema);
export const invoiceEnvelope = envelope(invoiceSchema);
export const invoicePageEnvelope = envelope(invoicePageSchema);
export const billingEnvelope = envelope(billingSchema);
export const billingRunEnvelope = envelope(billingRunSchema);
export const deliveryPreviewEnvelope = envelope(deliveryPreviewSchema);
