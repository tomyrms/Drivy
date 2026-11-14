import { z } from 'zod';
import { entitlementEffects, iso, moduleCodes } from './entitlements-model.js';

/**
 * Offres et droits aux modules (R01-T03, #455). Une offre est un ensemble nommé de modules du catalogue ; elle ne porte ni montant,
 * ni essai, ni échéance (#456). Modifier une offre ne change jamais une école déjà attribuée : l'attribution en garde l'instantané.
 */
export const offerStatuses = ['ACTIVE', 'ARCHIVED'] as const;
export type OfferStatus = (typeof offerStatuses)[number];

const operationId = z.uuid();
const offerName = z.string().trim().min(1).max(100);
const moduleList = z.array(z.enum(moduleCodes)).max(moduleCodes.length)
  .refine(list => new Set(list).size === list.length, { message: 'Un module ne figure qu’une fois dans une offre.' });
const reason = z.string().trim().min(3).max(500);

export const createOfferBody = z.object({ operationId, name: offerName, modules: moduleList }).strict();
export const updateOfferBody = z.object({ operationId, name: offerName.optional(), modules: moduleList.optional() }).strict()
  .refine(body => body.name !== undefined || body.modules !== undefined, { message: 'Aucune modification demandée.' });
export const offerCommandBody = z.object({ operationId }).strict();
export const offerListQuery = z.object({ status: z.enum(offerStatuses).optional() }).strict();
/** `effectiveAt` absent ou nul : l'attribution prend effet immédiatement. Une date doit être future (refus 409 EFFECTIVE_DATE_PAST sinon). */
export const assignOfferBody = z.object({ operationId, offerId: z.uuid(), effectiveAt: z.iso.datetime().nullable().optional() }).strict();
export const assignmentPreviewQuery = z.object({ offerId: z.uuid(), effectiveAt: z.iso.datetime().optional() }).strict();
export const adjustModuleBody = z.object({ operationId, moduleCode: z.enum(moduleCodes), effect: z.enum(entitlementEffects), reason }).strict();
export const liftAdjustmentBody = z.object({ operationId, reason }).strict();
export const entitlementQuery = z.object({}).strict();

/** Plus lointaine date d'effet acceptée : une attribution se programme à l'échelle d'une saison, pas d'une décennie. */
export const maxEffectiveDays = 366;

export interface OfferItem {
  id: string; name: string; modules: string[]; status: OfferStatus; version: number; created_at: string; updated_at: string;
  archived_at: string | null; schools_in_force: number | string;
}
export const offerView = (item: OfferItem) => ({
  id: item.id, name: item.name, modules: [...item.modules], status: item.status, version: item.version,
  createdAt: iso(item.created_at)!, updatedAt: iso(item.updated_at)!, archivedAt: iso(item.archived_at), schoolsInForce: Number(item.schools_in_force),
});
export type OfferView = ReturnType<typeof offerView>;
