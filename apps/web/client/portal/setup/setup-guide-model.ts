import { setupExampleText, type SetupContent, type SetupStep, type SetupTemplates } from '../../setup-model';

/**
 * Pure helpers of the preparation guide (#320). Copied from the historical guide view so that the rebuilt portal never
 * imports it; the rules (steps, issues, prices, examples) stay in `setup-model.ts` and the API.
 */
export type ProfileFieldRule = SetupContent['profile']['fields'][number];
export type StoredSetupDraft = { version: number; content: SetupContent; step: SetupStep; dirty: boolean };

export const profileFieldLabels: Record<string, string> = { firstName: 'Prénom', lastName: 'Nom', contactPhone: 'Téléphone', contactEmail: 'E-mail',
  birthDate: 'Date de naissance', postalAddress: 'Adresse postale', profilePhotoDocumentId: 'Photo de profil' };

/** Fields offered by the guide, with the explanation proposed when a field is first requested. */
export const profileFieldDefaults: readonly ProfileFieldRule[] = [
  { field: 'firstName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' },
  { field: 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' },
  { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Vous joindre au sujet de vos leçons.' },
  { field: 'contactEmail', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Vous contacter au sujet de vos leçons.' },
  { field: 'birthDate', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'COURSE_ELIGIBILITY', explanation: 'Examiner les prérequis de votre formation.' },
  { field: 'postalAddress', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'POSTAL_CONTACT', explanation: 'Vous adresser les courriers nécessaires à votre dossier.' },
];

export type ProfileChoice = 'NONE' | 'OPTIONAL' | 'BEFORE_LESSON' | 'BEFORE_COURSE';
export const profileChoices: readonly { value: ProfileChoice; label: string }[] = [
  { value: 'NONE', label: 'Non demandé' }, { value: 'OPTIONAL', label: 'Facultatif' },
  { value: 'BEFORE_LESSON', label: 'Avant une leçon' }, { value: 'BEFORE_COURSE', label: 'Avant un cours' },
];

/** Current choice of one field; a JOIN stage is shown as « Avant une leçon » only for the fixed identity fields, never chosen here. */
export function profileChoiceOf(current: ProfileFieldRule | undefined): ProfileChoice {
  if (!current) return 'NONE';
  if (current.requirement === 'OPTIONAL') return 'OPTIONAL';
  return current.stage === 'BEFORE_COURSE' ? 'BEFORE_COURSE' : 'BEFORE_LESSON';
}

/** Same transformation as the historical guide: the field keeps its explanation, or takes the proposed one. */
export function applyProfileChoice(fields: readonly ProfileFieldRule[], base: ProfileFieldRule, choice: ProfileChoice): ProfileFieldRule[] {
  const current = fields.find(item => item.field === base.field);
  const rest = fields.filter(item => item.field !== base.field);
  if (choice === 'NONE') return rest;
  return [...rest, { ...(current ?? base), requirement: choice === 'OPTIONAL' ? 'OPTIONAL' : 'REQUIRED', stage: choice }];
}

/** Drivy's privacy proposal with the school's coordinates; adopted only by the explicit confirmation. */
export function templatePrivacy(templates: SetupTemplates, content: SetupContent): SetupContent['privacy'] {
  return { noticeText: setupExampleText(templates.privacy.noticeText, content),
    retentionText: setupExampleText(templates.privacy.retentionText, content), contactEmail: content.privacy.contactEmail || content.identity.contactEmail,
    templateId: templates.privacy.id, templateVersion: templates.privacy.version };
}

const atPath = (value: unknown, path: string): unknown => path.split('.').reduce<unknown>((current, key) =>
  current !== null && typeof current === 'object' ? (current as Record<string, unknown>)[key] : undefined, value);

/**
 * A server issue stays attached to a field only while that field still holds the reviewed value, at the same owner
 * (formation id, competency key, profile field): moving or editing a row never shows another row's error.
 */
export function matchesReviewedField(current: unknown, reviewed: SetupContent, path: string): boolean {
  if (!Object.is(atPath(current, path), atPath(reviewed, path))) return false;
  const owners = [[/^formations\.\d+/, 'id'], [/^formations\.\d+\.competencies\.\d+/, 'key'], [/^profile\.fields\.\d+/, 'field']] as const;
  return owners.every(([pattern, key]) => {
    const prefix = path.match(pattern)?.[0];
    return !prefix || atPath(current, `${prefix}.${key}`) === atPath(reviewed, `${prefix}.${key}`);
  });
}

/** Steps opened from the summary only (identity, texts, pupil information) are not part of the short progression. */
export function guideNextStep(steps: readonly SetupStep[], step: SetupStep): SetupStep {
  return steps.includes(step) ? steps[Math.min(steps.indexOf(step) + 1, steps.length - 1)]! : 'REVIEW';
}

/** Whole minutes typed by the person; anything else stays absent, never an implicit default. */
export function minutesValue(value: string): number | null {
  return /^\d{1,4}$/.test(value.trim()) ? Number(value.trim()) : null;
}

/** Input text of a stored price, without inventing one: an absent price stays an empty field. */
export function priceInput(cents: number | null): string {
  if (cents === null) return '';
  return cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
}
