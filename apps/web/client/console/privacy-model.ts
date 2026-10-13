import type { ProfileField, ProfilePurpose, ProfileRule } from '../command-core.js';
import type { PolicyImpact, ProfilePolicy, RecordingChoice, TextProposals } from '../school-api.js';

/** Ce qu'une nouvelle version arrête : les accords GPS donnés sur les textes actuels et les trajets en cours. */
export function impactSentences(impact: PolicyImpact | null): string[] {
  if (!impact) return ['Les élèves devront redonner leur accord GPS et les trajets en cours s’arrêteront.'];
  const sentences: string[] = [];
  if (impact.gpsAgreements > 0) sentences.push(impact.gpsAgreements === 1
    ? '1 élève avait accepté le GPS avec les textes actuels : la question lui sera reposée.'
    : `${impact.gpsAgreements} élèves avaient accepté le GPS avec les textes actuels : la question leur sera reposée.`);
  if (impact.activeCaptures > 0) sentences.push(impact.activeCaptures === 1
    ? '1 trajet en cours s’arrêtera.' : `${impact.activeCaptures} trajets en cours s’arrêteront.`);
  return sentences;
}

export type Choice = 'none' | 'optional' | 'lesson' | 'keep';
export type FieldDraft = { choice: Choice; explanation: string; original: ProfileRule | null };
export const editableFields: readonly ProfileField[] = ['contactPhone', 'contactEmail', 'birthDate', 'postalAddress'];
const defaultPurpose: Record<ProfileField, ProfilePurpose> = {
  firstName: 'IDENTIFICATION', lastName: 'IDENTIFICATION', contactPhone: 'LESSON_CONTACT', contactEmail: 'LESSON_CONTACT',
  birthDate: 'CERTIFICATE', postalAddress: 'POSTAL_CONTACT', profilePhotoDocumentId: 'PERSONALISATION',
};
const defaultExplanation: Record<ProfileField, string> = {
  firstName: 'Pour vous reconnaître dans l’école et sur vos bilans.', lastName: 'Pour vous reconnaître dans l’école et sur vos bilans.',
  contactPhone: 'Pour vous prévenir d’un changement de leçon.', contactEmail: 'Pour vous écrire au sujet de vos leçons.',
  birthDate: 'Pour établir vos attestations.', postalAddress: 'Pour vous écrire par courrier.', profilePhotoDocumentId: 'Pour personnaliser votre profil.',
};
export const choiceLabels: Record<Choice, string> = { none: 'Pas demandé', optional: 'Facultatif', lesson: 'Requis avant une leçon', keep: 'Avant un cours' };

export const choiceOf = (rule: ProfileRule | null): Choice => !rule ? 'none' : rule.requirement === 'OPTIONAL' ? 'optional'
  : rule.requirement === 'REQUIRED' && rule.stage === 'BEFORE_LESSON' ? 'lesson' : 'keep';

export function initialDrafts(current: ProfilePolicy | null, proposals: TextProposals | null): Record<ProfileField, FieldDraft> {
  const source = (current?.fields ?? proposals?.profileFields ?? []) as ProfileRule[];
  return Object.fromEntries((['firstName', 'lastName', ...editableFields, 'profilePhotoDocumentId'] as ProfileField[]).map(field => {
    const rule = source.find(item => item.field === field) ?? null;
    return [field, { choice: field === 'firstName' || field === 'lastName' ? 'lesson' : choiceOf(rule), explanation: rule?.explanation ?? defaultExplanation[field], original: rule }];
  })) as Record<ProfileField, FieldDraft>;
}

export function rulesOf(drafts: Record<ProfileField, FieldDraft>): ProfileRule[] {
  const rules: ProfileRule[] = [];
  for (const field of ['firstName', 'lastName'] as const)
    rules.push({ field, requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: drafts[field].explanation.trim() });
  for (const field of [...editableFields, 'profilePhotoDocumentId'] as ProfileField[]) {
    const draft = drafts[field];
    const purposeCode = draft.original?.purposeCode ?? defaultPurpose[field];
    if (draft.choice === 'optional') rules.push({ field, requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode, explanation: draft.explanation.trim() });
    else if (draft.choice === 'lesson') rules.push({ field, requirement: 'REQUIRED', stage: 'BEFORE_LESSON', purposeCode, explanation: draft.explanation.trim() });
    else if (draft.choice === 'keep' && draft.original) rules.push({ ...draft.original, explanation: draft.explanation.trim() });
  }
  return rules;
}


/** Ce que dit le dossier de l'accord GPS d'un élève ; `renew` signale l'inhabituel : un accord donné sur d'anciens textes. */
export function gpsConsentLabel(choice: RecordingChoice | undefined): { text: string; renew: boolean } {
  if (!choice || choice.status === 'UNKNOWN') return { text: 'Pas encore donné', renew: false };
  if (!choice.currentNotice) return { text: 'À redonner', renew: true };
  const text = choice.status === 'ALLOWED' ? 'Avec GPS' : 'Sans GPS';
  return { text: choice.lessonScoped ? `${text} · pour une leçon` : text, renew: false };
}
