import { z } from 'zod';
import { profilePolicySchema } from './school-api';

export const setupSteps = ['IDENTITY', 'PRIVACY', 'PROFILE', 'FORMATIONS', 'PRICING', 'REVIEW'] as const;
export type SetupStep = typeof setupSteps[number];
export const setupStepLabels: Record<SetupStep, string> = {
  IDENTITY: 'Votre école', PRIVACY: 'Confidentialité', PROFILE: 'Informations des élèves',
  FORMATIONS: 'Vos formations', PRICING: 'Vos tarifs', REVIEW: 'Vérifier et démarrer',
};
const uuid = z.string().uuid();
const competency = z.object({ key: z.string(), label: z.string(), description: z.string(), sortOrder: z.number().int() });
export const setupFormationSchema = z.object({
  id: uuid, apply: z.boolean(), categoryCode: z.string(), label: z.string(),
  templateId: z.string().nullable(), templateVersion: z.string().nullable(),
  competencies: z.array(competency).max(200), procedureText: z.string(), cancellationPolicyText: z.string(),
  sourceUrls: z.array(z.string()).max(30), durationMinutes: z.number().int().nullable(), priceCents: z.number().int().nullable(),
  termsText: z.string(), validFrom: z.string().nullable(), existingOfferingId: uuid.nullable(),
});
export const setupContentSchema = z.object({
  selectedSections: z.array(z.enum(['IDENTITY', 'PRIVACY', 'PROFILE', 'CATALOGUE'])).max(4),
  identity: z.object({ name: z.string(), timeZone: z.string(), contactEmail: z.string(), contactPhone: z.string().nullable() }),
  privacy: z.object({ noticeText: z.string(), retentionText: z.string(), contactEmail: z.string(), templateId: z.string().nullable(), templateVersion: z.string().nullable() }),
  profile: z.object({ fields: profilePolicySchema.shape.fields, effectiveFrom: z.string().nullable() }),
  formations: z.array(setupFormationSchema).max(12),
});
export const setupDraftSchema = z.object({
  id: uuid, schoolId: uuid, version: z.number().int().positive(), status: z.enum(['DRAFT', 'APPLIED']),
  currentStep: z.enum(setupSteps), content: setupContentSchema,
  updatedAt: z.string().nullable(), updatedByMembershipId: uuid.nullable(), appliedAt: z.string().nullable(),
});
export const setupTemplatesSchema = z.object({
  version: z.string(),
  privacy: z.object({ id: z.string(), version: z.string(), noticeText: z.string(), retentionText: z.string() }),
  profileFields: profilePolicySchema.shape.fields,
  formations: z.array(z.object({ id: z.string(), version: z.string(), categoryCode: z.string(), label: z.string(),
    competencies: z.array(competency), procedureText: z.string(), durationMinutes: z.number().int() })),
});
export const setupPreviewSchema = z.object({
  schoolId: uuid, draftVersion: z.number().int().positive(), schoolVersion: z.number().int().positive(),
  configurationVersion: z.number().int().positive(), activate: z.boolean(), reviewDigest: z.string(), ready: z.boolean(),
  issues: z.array(z.object({ field: z.string(), message: z.string(), code: z.string() })),
  selectedSections: setupContentSchema.shape.selectedSections, content: setupContentSchema,
  effects: z.array(z.string()).default([]),
});
export type SetupContent = z.infer<typeof setupContentSchema>;
export type SetupDraft = z.infer<typeof setupDraftSchema>;
export type SetupFormation = z.infer<typeof setupFormationSchema>;
export type SetupTemplates = z.infer<typeof setupTemplatesSchema>;
export type SetupPreview = z.infer<typeof setupPreviewSchema>;
export type SetupSection = SetupContent['selectedSections'][number];

export function selectSetupSection(content: SetupContent, section: SetupSection, included: boolean): SetupContent {
  return { ...content, selectedSections: included ? [...new Set([...content.selectedSections, section])]
    : content.selectedSections.filter(item => item !== section) };
}
export function issueStep(field: string): SetupStep {
  const path = field.replace(/^content\./, '');
  if (path.startsWith('identity')) return 'IDENTITY';
  if (path.startsWith('privacy')) return 'PRIVACY';
  if (path.startsWith('profile')) return 'PROFILE';
  if (/price|duration|terms|validFrom|cancellation/i.test(path)) return 'PRICING';
  if (path.startsWith('formations')) return 'FORMATIONS';
  return 'REVIEW';
}
/** Empty input stays absent. Invalid decimals never become an implicit zero. */
export function setupPrice(value: string): number | null {
  const normalized = value.trim().replace(',', '.');
  if (!/^\d{1,7}(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [whole, fraction = ''] = normalized.split('.');
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(cents) ? cents : null;
}
export function setupFormation(template: SetupTemplates['formations'][number] | null, today: string): SetupFormation {
  return { id: crypto.randomUUID(), apply: false, categoryCode: template?.categoryCode ?? '', label: template?.label ?? '',
    templateId: template?.id ?? null, templateVersion: template?.version ?? null,
    competencies: template ? structuredClone(template.competencies) : [{ key: 'competence-1', label: '', description: '', sortOrder: 0 }],
    procedureText: template?.procedureText ?? '', cancellationPolicyText: '', sourceUrls: [], durationMinutes: template?.durationMinutes ?? 45,
    priceCents: null, termsText: '', validFrom: today, existingOfferingId: null };
}
