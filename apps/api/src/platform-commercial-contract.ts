import { z } from 'zod';
import { actionClasses, commercialLifecycles, commercialStates, restrictionCauses, restrictionReasons } from './entitlements-model.js';
import { commercialOfferSchema } from './platform-clients-contract.js';
import {
  missingFields, noticeEvents, paidStartStatuses, requestKinds, requestSources, requestStatuses, revisionActions, suspensionBillings, termsPhases, termsStatuses, trialKinds, trialPhases,
} from './platform-commercial-model.js';

/**
 * Extension exécutable du dépôt (R01-T04, #456) : conditions commerciales, essai, début payant, demandes et échéancier prévisionnel.
 * L'OpenAPI canonique 3.11.0 reste immuable. Ces schémas décrivent exactement ce que `src/platform-commercial.ts` renvoie ;
 * `contracts/platform-commercial.json` en est la projection. Montants en centimes de CHF ; jours commerciaux en Europe/Zurich.
 */
const timestamp = z.iso.datetime();
const day = z.iso.date();
const cents = z.number().int().min(0);
const nullableText = z.string().nullable();

export const commercialRestrictionSchema = z.object({
  reason: z.enum(restrictionReasons), closes: z.array(z.enum(actionClasses)), causes: z.array(z.enum(restrictionCauses)).optional(),
}).strict();
export const termsVersionSchema = z.object({
  id: z.uuid(), sequence: z.number().int().min(1), currency: z.literal('CHF'), initialAmount: cents.nullable(), initialDiscount: cents,
  initialDueOn: day.nullable(), monthlyAmount: cents.nullable(), recurringDiscount: cents, recurringDiscountMonths: z.number().int().min(1).nullable(),
  paymentTermDays: z.number().int().min(0).nullable(), suspensionBilling: z.enum(suspensionBillings).nullable(), effectiveFrom: day,
  exceptionReason: nullableText, createdAt: timestamp, createdByName: nullableText, phase: z.enum(termsPhases),
}).strict();
export const trialChangeSchema = z.object({
  id: z.uuid(), sequence: z.number().int().min(1), kind: z.enum(trialKinds), startsAt: timestamp, endsAt: timestamp, reason: nullableText,
  createdAt: timestamp, createdByName: nullableText,
}).strict();
export const commercialRequestSchema = z.object({
  id: z.uuid(), kind: z.enum(requestKinds), status: z.enum(requestStatuses), requestedOn: day, requestedOfferId: z.uuid().nullable(),
  requestedOfferName: nullableText, desiredOn: day.nullable(), details: nullableText, response: nullableText, effectiveOn: day.nullable(),
  assignmentId: z.uuid().nullable(), decidedAt: timestamp.nullable(), decidedByName: nullableText, version: z.number().int().min(1),
  createdAt: timestamp, createdByName: nullableText, updatedAt: timestamp,
  source: z.enum(requestSources), requestedModules: z.array(z.string()), withdrawnBySchool: z.boolean(),
  revisions: z.array(z.object({
    action: z.enum(revisionActions), previousEffectiveOn: day, newEffectiveOn: day.nullable(), response: z.string(), decidedAt: timestamp, decidedByName: nullableText,
  }).strict()),
}).strict();
const schedulePeriodSchema = z.object({
  index: z.number().int().min(0), startsOn: day, endsOn: day, amount: cents.nullable(), discount: cents, net: cents.nullable(),
  termsSequence: z.number().int().min(1).nullable(),
}).strict();

/**
 * Dossier commercial d'une fiche vu par l'équipe. `version` sert d'If-Match aux commandes commerciales ; `entitlementVersion` reste celle
 * des droits (R01-T03). `billable` n'est vrai qu'avec un début payant confirmé, des conditions complètes et sans résiliation effective.
 * `schedule` est prévisionnel : aucune facture n'est émise (#457).
 */
export const commercialDetailSchema = z.object({
  state: z.enum(commercialStates), lifecycle: z.enum(commercialLifecycles), restriction: commercialRestrictionSchema.nullable(),
  offer: commercialOfferSchema.nullable(), scheduledOffer: commercialOfferSchema.nullable(),
  milestones: z.object({
    codeIssuedAt: timestamp.nullable(), schoolCreatedAt: timestamp.nullable(), schoolLinkedAt: timestamp.nullable(), activatedAt: timestamp.nullable(),
    trialStartsAt: timestamp.nullable(), paidStartsOn: day.nullable(),
  }).strict(),
  proposedTrialStart: timestamp.nullable(),
  trial: z.object({ startsAt: timestamp, endsAt: timestamp, phase: z.enum(trialPhases) }).strict().nullable(),
  trialChanges: z.array(trialChangeSchema),
  terms: z.object({
    status: z.enum(termsStatuses), missing: z.array(z.enum(missingFields)), currency: z.literal('CHF'),
    inForce: termsVersionSchema.nullable(), scheduled: termsVersionSchema.nullable(), versions: z.array(termsVersionSchema),
  }).strict(),
  paidStart: z.object({
    id: z.uuid(), startsOn: day, started: z.boolean(), termsSequence: z.number().int().min(1).nullable(), confirmedAt: timestamp, confirmedByName: nullableText,
  }).strict().nullable(),
  paidStarts: z.array(z.object({
    id: z.uuid(), startsOn: day, status: z.enum(paidStartStatuses), confirmedAt: timestamp, confirmedByName: nullableText,
    cancelledAt: timestamp.nullable(), cancelledByName: nullableText, cancelReason: nullableText,
  }).strict()),
  termination: z.object({ requestId: z.uuid(), effectiveOn: day, decidedAt: timestamp }).strict().nullable(),
  requests: z.array(commercialRequestSchema).max(100),
  billable: z.boolean(), nextPeriodStart: day.nullable(),
  schedule: z.object({
    initial: z.object({ dueOn: day, amount: cents, discount: cents, net: cents, termsSequence: z.number().int().min(1) }).strict().nullable(),
    periods: z.array(schedulePeriodSchema).max(12),
  }).strict(),
  today: day, entitlementVersion: z.number().int().min(1), nextChangeAt: timestamp.nullable(), version: z.number().int().min(1),
}).strict();

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const commercialDetailEnvelope = envelope(commercialDetailSchema);
/** Boîte de l'équipe (R01-T08) : événements non lus sur les demandes des écoles. */
export const commercialNoticeSchema = z.object({
  id: z.uuid(), clientId: z.uuid(), clientName: z.string(), requestId: z.uuid(), kind: z.enum(requestKinds), event: z.enum(noticeEvents), createdAt: timestamp,
}).strict();
export const commercialNoticesEnvelope = envelope(z.object({ items: z.array(commercialNoticeSchema).max(50) }).strict());
export const commercialNoticesReadEnvelope = envelope(z.object({ read: z.number().int().min(0) }).strict());
