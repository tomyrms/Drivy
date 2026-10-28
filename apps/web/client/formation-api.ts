import { z } from 'zod';
import { RequestFailure } from './protocol.js';
import { readSchool } from './school-api.js';

/* Formations et tarifs : lectures agrégées de /v1/schools/{schoolId}/formations, validées avant affichage. */
const id = z.string().uuid();
const timestamp = z.string().datetime({ offset: true });
const civil = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const count = z.number().int().min(0);
export const tariffTypes = ['INDIVIDUAL_LESSON', 'COLLECTIVE_COURSE', 'EXAM_SUPPORT', 'EXTERNAL_SERVICE'] as const;
export const tariffStatuses = ['OFFERED', 'DISABLED', 'NOT_YET', 'ENDED', 'TERMS_NOT_APPROVED', 'TERMS_EXPIRED', 'TERMS_NOT_YET'] as const;
const categoryState = { state: z.enum(['READY', 'INCOMPLETE', 'NOT_OFFERED']), issues: z.array(z.enum(['PROGRAMME_REQUIRED', 'PROGRAMME_INCOMPLETE', 'LESSON_TARIFF_REQUIRED'])).max(3) };

export const formationListSchema = z.object({
  today: civil, canConfigureCatalog: z.boolean(), uncategorizedTariffCount: count,
  categories: z.array(z.object({ categoryCode: z.string().min(1).max(30), ...categoryState, programmeCount: count, tariffCount: count, activeTrainings: count,
    lessonDurations: z.array(z.number().int().min(1).max(480)).max(50),
    lessonTariffs: z.array(z.object({ label: z.string().max(200), durationMinutes: z.number().int().nullable(), unitPriceCents: z.number().int().min(0), unitLabel: z.string().max(100), upcoming: z.boolean() })).max(20),
    competencyCounts: z.array(count).max(50) })).max(200),
});
export const competencySchema = z.object({ id, key: z.string().min(1).max(80), label: z.string().max(200), description: z.string().max(4000), sortOrder: z.number().int() });
export const curriculumContentSchema = z.object({ id, revision: z.number().int().positive(), approved: z.boolean(), categoryCode: z.string(), createdAt: timestamp, competencies: z.array(competencySchema).max(200) });
export const procedureContentSchema = z.object({ id, version: z.number().int().positive(), approved: z.boolean(), categoryCode: z.string(), createdAt: timestamp,
  procedureText: z.string().max(4000), cancellationPolicyText: z.string().max(4000), sourceUrls: z.array(z.string().max(2048)).max(30) });
const headSchema = z.object({ id, version: z.number().int().positive(), enabled: z.boolean(), label: z.string().max(120).nullable(), defaultDurationMinutes: z.number().int().min(1).max(480).nullable(),
  hasReferencePrice: z.boolean(), createdAt: timestamp, ready: z.boolean(), complete: z.boolean() });
export const programmeSchema = z.object({
  offeringKey: z.string().min(1).max(80), head: headSchema, curriculum: curriculumContentSchema.nullable(), procedure: procedureContentSchema.nullable(),
  enrollments: z.object({ current: count, previous: count }), sharedCurriculumWith: z.array(z.string()).max(50), sharedProcedureWith: z.array(z.string()).max(50),
  history: z.array(z.object({ id, version: z.number().int().positive(), enabled: z.boolean(), label: z.string().nullable(), curriculumVersionId: id.nullable(), policyVersionId: id.nullable(),
    defaultDurationMinutes: z.number().int().nullable(), createdAt: timestamp, curriculumRevision: z.number().int().nullable(), policyVersion: z.number().int().nullable(), trainings: count })).max(100),
  historyTruncated: z.boolean(),
});
export const tariffVersionSchema = z.object({
  id, productKey: z.string().min(1).max(100), version: z.number().int().positive(), label: z.string().max(200), type: z.enum(tariffTypes), categoryCode: z.string().nullable(),
  durationMinutes: z.number().int().nullable(), unitLabel: z.string().max(100), unitPriceCents: z.number().int().min(0), validFrom: civil, validUntil: civil.nullable(),
  termsVersionId: id, enabled: z.boolean(), createdAt: timestamp,
});
export const termsContentSchema = z.object({ id, version: z.number().int().positive(), label: z.string().max(200), termsText: z.string().max(20_000), validFrom: civil, validUntil: civil.nullable(), approved: z.boolean(), createdAt: timestamp });
export const tariffSchema = z.object({ productKey: z.string().min(1).max(100), head: tariffVersionSchema, terms: termsContentSchema.nullable(), status: z.enum(tariffStatuses),
  termsSharedWith: count, history: z.array(tariffVersionSchema).max(100), historyTruncated: z.boolean() });
const unattached = z.array(z.object({ id, number: z.number().int().positive(), createdAt: timestamp })).max(50);
export const formationSheetSchema = z.object({
  categoryCode: z.string().min(1).max(30), today: civil, canConfigureCatalog: z.boolean(), ...categoryState,
  programmes: z.array(programmeSchema).max(50), tariffs: z.array(tariffSchema).max(200), unattached: z.object({ curricula: unattached, procedures: unattached }),
});
export const uncategorizedTariffsSchema = z.object({ today: civil, canConfigureCatalog: z.boolean(), tariffs: z.array(tariffSchema).max(2000) });
export const termsListSchema = z.object({ items: z.array(termsContentSchema.extend({ tariffs: count, currentTariffs: count })).max(500), truncated: z.boolean() });
const usingProgramme = z.object({ offeringKey: z.string(), categoryCode: z.string(), label: z.string().nullable(), headId: id, current: z.boolean() });
export const referenceSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('OFFERING'), id, categoryCode: z.string(), current: z.boolean(), offeringKey: z.string(), headId: id, programmes: z.array(usingProgramme).max(50),
    offering: headSchema.extend({ curriculumVersionId: id.nullable(), policyVersionId: id.nullable() }), curriculum: curriculumContentSchema.nullable(), procedure: procedureContentSchema.nullable() }),
  z.object({ kind: z.literal('CURRICULUM'), id, categoryCode: z.string(), current: z.boolean(), programmes: z.array(usingProgramme).max(50), curriculum: curriculumContentSchema }),
  z.object({ kind: z.literal('PROCEDURE'), id, categoryCode: z.string(), current: z.boolean(), programmes: z.array(usingProgramme).max(50), procedure: procedureContentSchema }),
  z.object({ kind: z.literal('TARIFF'), id, categoryCode: z.string().nullable(), current: z.boolean(), productKey: z.string(), headId: id.nullable(), programmes: z.array(usingProgramme).max(0),
    tariff: tariffVersionSchema, terms: termsContentSchema.nullable(), status: z.enum(tariffStatuses) }),
  z.object({ kind: z.literal('TERMS'), id, categoryCode: z.null(), current: z.boolean(), programmes: z.array(usingProgramme).max(0), terms: termsContentSchema,
    usedBy: z.array(tariffVersionSchema.extend({ current: z.boolean() })).max(200) }),
]);
export const proposalsSchema = z.object({
  formations: z.array(z.object({ id: z.string().max(100), version: z.string().max(40), categoryCode: z.string(), label: z.string(),
    competencies: z.array(z.object({ key: z.string(), label: z.string(), description: z.string() }).passthrough()).max(200), procedureText: z.string(), durationMinutes: z.number().int(),
    sourceUrls: z.array(z.string().url()).max(30).optional(), qualification: z.literal('NOT_QUALIFIED').optional(), verifiedOn: civil.optional(), coverageNote: z.string().max(1000).optional(),
    change: z.object({ kind: z.enum(['EDITORIAL','PEDAGOGICAL','REGULATORY']), effectiveFrom: civil.nullable(), summary: z.string().max(1000), application: z.string().max(1000) }).optional(),
  }).passthrough()).max(30),
}).passthrough();
export const textProposalsLite = z.object({
  procedure: z.object({ procedureText: z.string().max(4000), cancellationPolicyText: z.string().max(4000) }),
  commercialTerms: z.object({ label: z.string().max(200), termsText: z.string().max(20_000) }),
}).passthrough();

export type FormationList = z.infer<typeof formationListSchema>;
export type FormationSheet = z.infer<typeof formationSheetSchema>;
export type Programme = z.infer<typeof programmeSchema>;
export type Tariff = z.infer<typeof tariffSchema>;
export type TariffVersion = z.infer<typeof tariffVersionSchema>;
export type TermsContent = z.infer<typeof termsContentSchema>;
export type CatalogueReference = z.infer<typeof referenceSchema>;
export type TariffStatus = typeof tariffStatuses[number];
export type TariffType = typeof tariffTypes[number];
export type FormationProposals = z.infer<typeof proposalsSchema>;
export type TextProposalsLite = z.infer<typeof textProposalsLite>;

/** Une fiche d'une autre école ou d'un autre permis n'est jamais affichée. */
export async function readFormationSheet(schoolId: string, category: string): Promise<FormationSheet> {
  const sheet = await readSchool(schoolId, 'formations/sheet', formationSheetSchema, { category });
  if (sheet.categoryCode !== category) throw new RequestFailure('INVALID_RESPONSE');
  return sheet;
}
export async function readReference(schoolId: string, referenceId: string): Promise<CatalogueReference> {
  const reference = await readSchool(schoolId, `formations/references/${referenceId}`, referenceSchema);
  if (reference.id.toLowerCase() !== referenceId.toLowerCase()) throw new RequestFailure('INVALID_RESPONSE');
  return reference;
}
