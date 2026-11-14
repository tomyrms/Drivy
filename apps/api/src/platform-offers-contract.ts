import { z } from 'zod';
import { adjustmentPhases, assignmentPhases, commercialStates, consequenceKinds, entitlementEffects, moduleCodes } from './entitlements-model.js';
import { commercialOfferSchema } from './platform-clients-contract.js';
import { offerStatuses } from './platform-offers-model.js';

/**
 * Extension exécutable du dépôt (R01-T03, #455) : catalogue de modules, offres, attributions, ajustements et droits résultants.
 * L'OpenAPI canonique 3.11.0 reste immuable. Ces schémas décrivent exactement ce que `src/platform-offers.ts` renvoie ;
 * `contracts/platform-offers.json` en est la projection. Aucune réponse ne contient montant, essai, échéance (#456), contenu d'école ni message.
 */
const timestamp = z.iso.datetime();
const version = z.number().int().min(1);
const moduleCode = z.enum(moduleCodes);
const nullableText = z.string().nullable();

export const platformModuleSchema = z.object({ code: moduleCode, sortOrder: z.number().int().min(1) }).strict();
export const offerSchema = z.object({
  id: z.uuid(), name: z.string().min(1).max(100), modules: z.array(moduleCode), status: z.enum(offerStatuses), version,
  createdAt: timestamp, updatedAt: timestamp, archivedAt: timestamp.nullable(), schoolsInForce: z.number().int().min(0)
}).strict();

const adjustmentDetailSchema = z.object({ id: z.uuid(), effect: z.enum(entitlementEffects), reason: z.string(), createdAt: timestamp, createdByName: nullableText }).strict();
export const entitlementModuleSchema = z.object({ code: moduleCode, inOffer: z.boolean(), entitled: z.boolean(), adjustment: adjustmentDetailSchema.nullable() }).strict();
export const assignmentHistorySchema = z.object({
  id: z.uuid(), offerId: z.uuid(), offerName: z.string(), modules: z.array(moduleCode), effectiveAt: timestamp, phase: z.enum(assignmentPhases),
  createdAt: timestamp, createdByName: nullableText, cancelledAt: timestamp.nullable()
}).strict();
export const adjustmentHistorySchema = z.object({
  id: z.uuid(), moduleCode, effect: z.enum(entitlementEffects), reason: z.string(), createdAt: timestamp, createdByName: nullableText,
  phase: z.enum(adjustmentPhases), liftedAt: timestamp.nullable(), liftedByName: nullableText, liftReason: nullableText
}).strict();
/** Droits d'une fiche vus par l'équipe : en vigueur, programmés, historique. `version` sert d'If-Match aux commandes qui suivent. */
export const clientEntitlementsSchema = z.object({
  state: z.enum(commercialStates), offer: commercialOfferSchema.nullable(), scheduledOffer: commercialOfferSchema.nullable(),
  modules: z.array(entitlementModuleSchema), assignments: z.array(assignmentHistorySchema), adjustments: z.array(adjustmentHistorySchema),
  version: z.number().int().min(1), nextChangeAt: timestamp.nullable()
}).strict();
export const assignmentPreviewSchema = z.object({
  offer: z.object({ id: z.uuid(), name: z.string(), modules: z.array(moduleCode) }).strict(),
  effectiveAt: timestamp.nullable(), immediate: z.boolean(), replacesScheduled: commercialOfferSchema.nullable(),
  endingAdjustments: z.array(z.object({ id: z.uuid(), moduleCode, effect: z.enum(entitlementEffects) }).strict()),
  modules: z.array(z.object({
    code: moduleCode, before: z.boolean(), after: z.boolean(), kind: z.enum(consequenceKinds), existing: z.record(z.string(), z.number().int().min(0)).nullable()
  }).strict()),
  version: z.number().int().min(1)
}).strict();

export const platformModulesSchema = z.object({ items: z.array(platformModuleSchema) }).strict();
export const platformOffersSchema = z.object({ items: z.array(offerSchema) }).strict();

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const platformModulesEnvelope = envelope(platformModulesSchema);
export const platformOffersEnvelope = envelope(platformOffersSchema);
export const platformOfferEnvelope = envelope(offerSchema);
export const clientEntitlementsEnvelope = envelope(clientEntitlementsSchema);
export const assignmentPreviewEnvelope = envelope(assignmentPreviewSchema);

/** Côté école (iPhone, web) : l'état et les modules accordés, rien d'autre. Jamais l'offre, le motif, l'auteur ni l'historique. */
export const schoolEntitlementsSchema = z.object({
  state: z.enum(commercialStates), modules: z.array(z.object({ code: moduleCode, entitled: z.boolean() }).strict()), version: z.number().int().min(1),
  nextChangeAt: timestamp.nullable(), computedAt: timestamp
}).strict();
export const schoolEntitlementsEnvelope = envelope(schoolEntitlementsSchema);
/** Refus d'usage nouveau d'un module non accordé : 403 sans autre information que le module. */
export const moduleNotEntitledSchema = z.object({
  type: z.literal('urn:drivy:problem:module_not_entitled'), title: z.string(), status: z.literal(403), code: z.literal('MODULE_NOT_ENTITLED'), requestId: z.uuid()
}).strict();
