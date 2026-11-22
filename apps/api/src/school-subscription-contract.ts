import { z } from 'zod';
import { commercialLifecycles, commercialStates, moduleCodes } from './entitlements-model.js';
import { debtSchema, settlementSchema } from './platform-billing-contract.js';
import { invoiceKinds } from './platform-billing-model.js';
import { commercialRestrictionSchema } from './platform-commercial-contract.js';
import { noticeEvents, requestKinds, requestSources, requestStatuses, revisionActions } from './platform-commercial-model.js';
import { paymentMethods } from './platform-payments-model.js';

/**
 * Espace abonnement de l'école (R01-T08, #460). Extension du dépôt : l'OpenAPI canonique 3.11.0 reste immuable et
 * `contracts/school-subscription.json` est la projection de ces schémas. Montants en centimes de CHF, jours à Zurich.
 * Ni note interne, ni nom d'opérateur, ni brouillon ou facture annulée ne figurent dans cette vue.
 */
const timestamp = z.iso.datetime();
const day = z.iso.date();
const cents = z.number().int().min(0);
const nullableText = z.string().nullable();

const termsSchema = z.object({
  currency: z.literal('CHF'), initialAmount: cents.nullable(), initialDiscount: cents, initialDueOn: day.nullable(), monthlyAmount: cents.nullable(),
  recurringDiscount: cents, recurringDiscountMonths: z.number().int().min(1).nullable(), paymentTermDays: z.number().int().min(0).nullable(), effectiveFrom: day,
}).strict();
const offerSchema = z.object({ name: z.string(), effectiveAt: timestamp }).strict();
export const subscriptionInvoiceSchema = z.object({
  id: z.uuid(), kind: z.enum(invoiceKinds), number: z.string(), periodStart: day.nullable(), periodEnd: day.nullable(), issuedOn: day, dueOn: day.nullable(),
  taxAmount: cents, total: cents, creditsInvoiceNumber: nullableText, settlement: settlementSchema.nullable(), hasDocument: z.boolean(),
}).strict();
export const subscriptionPaymentSchema = z.object({ id: z.uuid(), amount: cents, receivedOn: day, method: z.enum(paymentMethods) }).strict();
export const subscriptionRevisionSchema = z.object({
  action: z.enum(revisionActions), previousEffectiveOn: day, newEffectiveOn: day.nullable(), response: z.string(), decidedAt: timestamp,
}).strict();
export const subscriptionRequestSchema = z.object({
  id: z.uuid(), kind: z.enum(requestKinds), status: z.enum(requestStatuses), source: z.enum(requestSources), requestedOn: day, requestedOfferId: z.uuid().nullable(),
  requestedOfferName: nullableText, requestedModules: z.array(z.string()), desiredOn: day.nullable(), details: nullableText, response: nullableText,
  effectiveOn: day.nullable(), decidedAt: timestamp.nullable(), version: z.number().int().min(1), createdAt: timestamp, revisions: z.array(subscriptionRevisionSchema),
}).strict();

/** `hasClient: false` : l'école n'a pas de fiche commerciale ; les listes sont vides et aucun montant n'est inventé. */
export const schoolSubscriptionSchema = z.object({
  hasClient: z.boolean(), today: day, contact: z.object({ name: z.string(), email: nullableText }).strict().nullable(),
  lifecycle: z.enum(commercialLifecycles), state: z.enum(commercialStates), restriction: commercialRestrictionSchema.nullable(),
  trial: z.object({ startsAt: timestamp, endsAt: timestamp }).strict().nullable(), paidStartsOn: day.nullable(), terminationOn: day.nullable(),
  nextPeriodStart: day.nullable(), nextDueOn: day.nullable(), offer: offerSchema.nullable(), scheduledOffer: offerSchema.nullable(),
  modules: z.array(z.object({ code: z.string(), inOffer: z.boolean(), entitled: z.boolean() }).strict()),
  terms: termsSchema.nullable(), scheduledTerms: termsSchema.nullable(), debt: debtSchema.nullable(),
  invoices: z.array(subscriptionInvoiceSchema).max(200), payments: z.array(subscriptionPaymentSchema).max(200), requests: z.array(subscriptionRequestSchema).max(50),
  availableOffers: z.array(z.object({ id: z.uuid(), name: z.string(), modules: z.array(z.string()) }).strict()),
  notices: z.array(z.object({ id: z.uuid(), requestId: z.uuid(), event: z.enum(noticeEvents), createdAt: timestamp }).strict()).max(20),
  version: z.number().int().min(0),
}).strict();
export type SchoolSubscription = z.infer<typeof schoolSubscriptionSchema>;

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const schoolSubscriptionEnvelope = envelope(schoolSubscriptionSchema);
export const subscriptionRequestResult = z.object({ id: z.uuid(), status: z.enum(['RECEIVED', 'WITHDRAWN']), version: z.number().int().min(1) }).strict();
export const subscriptionRequestEnvelope = envelope(subscriptionRequestResult);
export const subscriptionNoticesResult = z.object({ schoolId: z.uuid(), read: z.number().int().min(0) }).strict();
export const subscriptionNoticesEnvelope = envelope(subscriptionNoticesResult);

const operationId = z.uuid();
/** Une demande de changement porte une offre ou des modules ; une résiliation porte sa date souhaitée ; une régularisation, seulement un message. */
export const subscriptionRequestBody = z.object({
  operationId, kind: z.enum(requestKinds), offerId: z.uuid().optional(), modules: z.array(z.enum(moduleCodes)).min(1).max(moduleCodes.length).optional(),
  desiredOn: day.optional(), details: z.string().trim().min(3).max(1000).optional(),
}).strict()
  .refine(body => body.kind !== 'OFFER_CHANGE' || body.offerId !== undefined || body.modules !== undefined, { message: 'Choisissez une offre ou des modules.', path: ['offerId'] })
  .refine(body => body.kind === 'OFFER_CHANGE' || (body.offerId === undefined && body.modules === undefined), { message: 'Seul un changement d’offre désigne une offre ou des modules.', path: ['offerId'] })
  .refine(body => body.kind !== 'TERMINATION' || body.desiredOn !== undefined, { message: 'Indiquez la date souhaitée.', path: ['desiredOn'] })
  .refine(body => !body.modules || new Set(body.modules).size === body.modules.length, { message: 'Un module est cité deux fois.', path: ['modules'] });
export const subscriptionCommandBody = z.object({ operationId }).strict();
