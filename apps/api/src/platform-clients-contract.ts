import { z } from 'zod';
import { clientPreparations, codeStates, setupStepCount } from './platform-clients-model.js';
import { commercialStates, moduleCodes } from './entitlements-model.js';

/**
 * Extension exécutable du dépôt (R01-T02, #454) : écoles clientes et codes d'ouverture. L'OpenAPI canonique 3.11.0 reste immuable.
 * Ces schémas décrivent exactement ce que `src/platform-clients.ts` renvoie ; `contracts/platform-clients.json` en est la projection.
 * Un code d'ouverture n'apparaît jamais dans une réponse : il est tiré par la passerelle, montré une fois à l'opérateur qui le copie.
 * Aucune projection d'école ne contient un dossier d'élève, un trajet, un message ni une liste de personnes.
 */
const timestamp = z.iso.datetime();
const version = z.number().int().min(1);
const nullableText = z.string().nullable();

export const schoolSetupSchema = z.object({
  step: z.string().nullable(), stepsDone: z.number().int().min(0).max(setupStepCount), stepsTotal: z.literal(setupStepCount),
  completedAt: timestamp.nullable(), savedAt: timestamp.nullable()
}).strict();
/** Faits d'école que la plateforme lit : nom, contact, état et progression de la mise en place. Rien d'autre. */
export const schoolFactsSchema = z.object({
  name: z.string(), status: z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']), contactEmail: z.string(), contactPhone: nullableText, setup: schoolSetupSchema
}).strict();
export const clientCodeStateSchema = z.object({ id: z.uuid(), state: z.enum(codeStates), expiresAt: timestamp, createdAt: timestamp }).strict();
/** Offre attribuée à la fiche : nom et modules copiés à l'attribution, date d'effet. Ni montant ni condition (#456). */
export const commercialOfferSchema = z.object({ offerId: z.uuid(), name: z.string().min(1).max(100), effectiveAt: timestamp, modules: z.array(z.enum(moduleCodes)) }).strict();
/** État commercial dérivé des attributions (R01-T03) ; `dueDates` reste l'emplacement réservé aux échéances de #456. */
export const commercialSchema = z.object({
  state: z.enum(commercialStates), offer: commercialOfferSchema.nullable(), scheduledOffer: commercialOfferSchema.nullable(),
  entitlementVersion: z.number().int().min(1), dueDates: z.array(timestamp).max(0)
}).strict();

export const platformCodeSchema = z.object({
  id: z.uuid(), state: z.enum(codeStates), clientId: z.uuid().nullable(), clientName: nullableText, createdAt: timestamp, expiresAt: timestamp,
  usedAt: timestamp.nullable(), revokedAt: timestamp.nullable(), issuedByName: nullableText,
  school: schoolFactsSchema.extend({ id: z.uuid() }).strict().nullable()
}).strict();

export const platformClientSummarySchema = z.object({
  id: z.uuid(), displayName: nullableText, preparation: z.enum(clientPreparations), schoolId: z.uuid().nullable(), school: schoolFactsSchema.nullable(),
  contactName: nullableText, contactEmail: nullableText, latestCode: clientCodeStateSchema.nullable(), commercial: commercialSchema,
  version, createdAt: timestamp, updatedAt: timestamp
}).strict();
export const platformClientSchema = platformClientSummarySchema.extend({
  contactPhone: nullableText,
  billing: z.object({ street: nullableText, postalCode: nullableText, city: nullableText, country: nullableText }).strict(),
  internalNotes: nullableText,
  link: z.object({ source: z.enum(['OPENING_CODE', 'EXISTING_SCHOOL']), linkedAt: timestamp, issuedByName: nullableText }).strict().nullable(),
  codes: z.array(platformCodeSchema)
}).strict();
export const unattachedSchoolSchema = z.object({
  id: z.uuid(), name: z.string(), status: z.enum(['DRAFT', 'ACTIVE', 'ARCHIVED']), contactEmail: z.string(), contactPhone: nullableText, setup: schoolSetupSchema
}).strict();

const page = { nextCursor: z.string().nullable(), total: z.number().int().min(0).nullable() };
export const platformClientsPageSchema = z.object({ items: z.array(platformClientSummarySchema), ...page }).strict();
export const platformCodesPageSchema = z.object({ items: z.array(platformCodeSchema), ...page }).strict();
export const unattachedSchoolsSchema = z.object({ items: z.array(unattachedSchoolSchema) }).strict();
export const issuedCodeSchema = z.object({ codeId: z.uuid(), client: platformClientSchema }).strict();

const envelope = <T extends z.ZodType>(data: T) => z.object({ data, requestId: z.uuid(), serverTime: timestamp }).strict();
export const platformClientsPageEnvelope = envelope(platformClientsPageSchema);
export const platformClientEnvelope = envelope(platformClientSchema);
export const platformCodesPageEnvelope = envelope(platformCodesPageSchema);
export const platformCodeEnvelope = envelope(platformCodeSchema);
export const unattachedSchoolsEnvelope = envelope(unattachedSchoolsSchema);
export const issuedCodeEnvelope = envelope(issuedCodeSchema);
