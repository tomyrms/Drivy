import { z } from 'zod';
import { profilePolicySchema } from './school-api.js';
import { commonLessonRulesSchema, commonLessonTexts } from './common-lesson-rules.js';

export const setupSteps = ['IDENTITY', 'PRIVACY', 'PROFILE', 'FORMATIONS', 'PRICING', 'REVIEW'] as const;
export type SetupStep = typeof setupSteps[number];
export const setupStepLabels: Record<SetupStep, string> = {
  IDENTITY: 'Votre école', PRIVACY: 'Confidentialité', PROFILE: 'Informations des élèves',
  FORMATIONS: 'Permis enseignés', PRICING: 'Prix et règles de l’école', REVIEW: 'Résumé et confirmation',
};
const uuid = z.string().uuid();
const competency = z.object({ key: z.string(), label: z.string(), description: z.string(), sortOrder: z.number().int() });
export const setupFormationSchema = z.object({
  id: uuid, apply: z.boolean(), categoryCode: z.string(), label: z.string(),
  templateId: z.string().nullable(), templateVersion: z.string().nullable(),
  competencies: z.array(competency).max(200), procedureText: z.string(), cancellationPolicyText: z.string(),
  sourceUrls: z.array(z.string()).max(30), durationMinutes: z.number().int().nullable(), priceCents: z.number().int().nullable(),
  termsText: z.string(), validFrom: z.string().nullable(), existingOfferingId: uuid.nullable(), useCommonTerms: z.boolean().optional(),
});
export const setupContentSchema = z.object({
  selectedSections: z.array(z.enum(['IDENTITY', 'PRIVACY', 'PROFILE', 'CATALOGUE'])).max(4),
  identity: z.object({ name: z.string(), timeZone: z.string(), contactEmail: z.string(), contactPhone: z.string().nullable() }),
  privacy: z.object({ noticeText: z.string(), retentionText: z.string(), contactEmail: z.string(), templateId: z.string().nullable(), templateVersion: z.string().nullable() }),
  profile: z.object({ fields: profilePolicySchema.shape.fields, effectiveFrom: z.string().nullable() }),
  formations: z.array(setupFormationSchema).max(20), commonLessonRules: commonLessonRulesSchema.optional(),
});
export const setupDraftSchema = z.object({
  id: uuid, schoolId: uuid, version: z.number().int().positive(), status: z.enum(['DRAFT', 'APPLIED']),
  currentStep: z.enum(setupSteps), content: setupContentSchema,
  updatedAt: z.string().nullable(), updatedByMembershipId: uuid.nullable(), appliedAt: z.string().nullable(),
});
export const setupTemplatesSchema = z.object({
  version: z.string(),
  privacy: z.object({ id: z.string(), version: z.string(), noticeText: z.string(), retentionText: z.string() }),
  commercial: z.object({ id: z.string(), version: z.string(), cancellationPolicyText: z.string(), termsText: z.string() }).optional(),
  profileFields: profilePolicySchema.shape.fields,
  formations: z.array(z.object({ id: z.string(), version: z.string(), categoryCode: z.string(), label: z.string(),
    competencies: z.array(competency), procedureText: z.string(), durationMinutes: z.number().int(),
    sourceUrls: z.array(z.string()).optional(), qualification: z.literal('NOT_QUALIFIED').optional(),
    coverageNote: z.string().optional(), verifiedOn: z.string().optional() })),
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
/** Opening has already stored the school's identity. Only untouched drafts bypass its editor. */
export function initialSetupStep(draft: SetupDraft, schoolStatus: string): SetupStep {
  if (schoolStatus !== 'DRAFT' || draft.status !== 'DRAFT' || draft.updatedAt !== null || draft.currentStep !== 'IDENTITY') return draft.currentStep;
  const identity = draft.content.identity;
  if (!identity.name.trim() || !z.email().safeParse(identity.contactEmail).success || !identity.timeZone || /^[+-]/.test(identity.timeZone)) return 'IDENTITY';
  try { new Intl.DateTimeFormat('fr', { timeZone: identity.timeZone }); } catch { return 'IDENTITY'; }
  return 'FORMATIONS';
}
/** A price editor is useful only when there is a formation to price. */
export function setupNavigationSteps(content: SetupContent | null, catalogueOnly = false): readonly SetupStep[] {
  const steps: readonly SetupStep[] = catalogueOnly || !!content?.identity.name.trim() && !!content.identity.contactEmail.trim()
    ? ['FORMATIONS', 'PRICING', 'REVIEW'] : ['IDENTITY', 'FORMATIONS', 'PRICING', 'REVIEW'];
  return content && content.formations.length === 0 ? steps.filter(step => step !== 'PRICING') : steps;
}
export function setupExampleText(text: string, content: SetupContent): string {
  return text.replaceAll('[Nom de l’école]', content.identity.name).replaceAll('[contact données]', content.privacy.contactEmail || content.identity.contactEmail);
}
/** Follow edited coordinates only while the proposed wording itself is still untouched. */
export function refreshSetupExamples(previous: SetupContent, next: SetupContent, templates: SetupTemplates): SetupContent {
  if (previous.identity === next.identity || previous.privacy.templateId !== templates.privacy.id || previous.privacy.templateVersion !== templates.privacy.version) return next;
  const privacy = { ...next.privacy, contactEmail: previous.privacy.contactEmail === previous.identity.contactEmail ? next.identity.contactEmail : next.privacy.contactEmail };
  const updated = { ...next, privacy };
  for (const field of ['noticeText', 'retentionText'] as const) if (previous.privacy[field] === setupExampleText(templates.privacy[field], previous)) privacy[field] = setupExampleText(templates.privacy[field], updated);
  return updated;
}
/** A catalogue editor never adopts the school identity, privacy notice or profile policy. */
export function catalogueSetupContent(content: SetupContent, applied = false): SetupContent {
  return { ...content, selectedSections: ['CATALOGUE'], formations: applied
    ? content.formations.filter(item => !item.apply || !content.selectedSections.includes('CATALOGUE')) : content.formations };
}
export function setupProfileRequirement(field: SetupContent['profile']['fields'][number]): string {
  if (field.requirement === 'OPTIONAL') return 'Facultatif';
  if (field.stage === 'JOIN') return 'À l’inscription';
  if (field.stage === 'BEFORE_COURSE') return field.requirement === 'CONDITIONAL' ? 'Selon la formation · avant un cours' : 'Avant un cours';
  return 'Avant une leçon';
}

export function selectSetupSection(content: SetupContent, section: SetupSection, included: boolean): SetupContent {
  return { ...content, selectedSections: included ? [...new Set([...content.selectedSections, section])]
    : content.selectedSections.filter(item => item !== section) };
}
export function issueStep(field: string): SetupStep {
  const path = field.replace(/^content\./, '');
  if (path.startsWith('identity')) return 'IDENTITY';
  if (path.startsWith('privacy')) return 'PRIVACY';
  if (path.startsWith('profile')) return 'PROFILE';
  if (path.startsWith('commonLessonRules')) return 'PRICING';
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
/** Un permis déjà présent dans le brouillon ne se prépare pas une seconde fois. */
export function templateAlreadyAdded(formations: readonly Pick<SetupFormation, 'categoryCode'>[], categoryCode: string): boolean {
  return formations.some(item => item.categoryCode === categoryCode);
}
export function setupFormation(template: SetupTemplates['formations'][number] | null, today: string): SetupFormation {
  return { id: crypto.randomUUID(), apply: true, useCommonTerms: true, categoryCode: template?.categoryCode ?? '', label: template?.label ?? '',
    templateId: template?.id ?? null, templateVersion: template?.version ?? null,
    competencies: template ? structuredClone(template.competencies) : [{ key: 'competence-1', label: '', description: '', sortOrder: 0 }],
    procedureText: template?.procedureText ?? '', cancellationPolicyText: '', sourceUrls: [...(template?.sourceUrls ?? [])], durationMinutes: template?.durationMinutes ?? 45,
    priceCents: null, termsText: '', validFrom: today, existingOfferingId: null };
}
export function resolvedSetupFormation(content: SetupContent, item: SetupFormation): SetupFormation {
  if (!item.useCommonTerms || !content.commonLessonRules) return item;
  const texts = commonLessonTexts(content.commonLessonRules, content.identity.contactEmail);
  return { ...item, ...texts, cancellationPolicyText: item.existingOfferingId ? item.cancellationPolicyText : texts.cancellationPolicyText };
}
