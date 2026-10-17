/**
 * Règles pures de la fiche « Formations et tarifs », partagées par la fiche, l'assistant et les tests.
 * Mêmes validations que l'API (apps/api/src/formation-catalogue.ts) ; le serveur reste l'autorité.
 * Aucun DOM, aucun réseau.
 */
import { characters, filled, isCivilDate, isHttpURL, parseCents, centsToInput } from '../command-core.js';
import type { Programme, Tariff, TariffStatus, TariffType } from '../formation-api.js';

/* ---------------------------------------------------------------- Compétences */

export interface CompetencyDraft { readonly uid: string; readonly key: string | null; readonly label: string; readonly description: string }
const uid = () => globalThis.crypto.randomUUID();
export function competencyDrafts(items: readonly { key: string | null; label: string; description: string }[]): CompetencyDraft[] {
  return items.map(item => ({ uid: uid(), key: item.key, label: item.label, description: item.description }));
}
export const emptyCompetency = (): CompetencyDraft => ({ uid: uid(), key: null, label: '', description: '' });
/** Déplace un élément ; l'ordre enregistré est celui de la liste, jamais un numéro saisi. */
export function moveItem<T>(items: readonly T[], index: number, delta: -1 | 1): T[] {
  const target = index + delta;
  if (index < 0 || index >= items.length || target < 0 || target >= items.length) return [...items];
  const next = [...items];
  [next[index], next[target]] = [next[target]!, next[index]!];
  return next;
}
export interface CompetencyProblems { list: string | null; items: { label: string | null; description: string | null }[]; valid: boolean }
export function competencyProblems(items: readonly CompetencyDraft[]): CompetencyProblems {
  const list = items.length === 0 ? 'Ajoutez au moins une compétence.' : items.length > 200 ? '200 compétences au plus.' : null;
  const labels = items.map(item => item.label.trim().toLocaleLowerCase('fr'));
  const problems = items.map((item, index) => ({
    label: !filled(item.label, 200) ? 'Indiquez le nom de la compétence (200 caractères au plus).'
      : labels.indexOf(labels[index]!) !== index ? 'Cette compétence figure déjà dans la liste.' : null,
    description: filled(item.description, 4000) ? null : 'Décrivez ce que l’élève apprend (4 000 caractères au plus).',
  }));
  return { list, items: problems, valid: list === null && problems.every(item => item.label === null && item.description === null) };
}
export const competencyPayload = (items: readonly CompetencyDraft[]) => items.map(item => ({ key: item.key, label: item.label.trim(), description: item.description.trim() }));
export function competenciesChanged(items: readonly CompetencyDraft[], current: readonly { key: string; label: string; description: string }[]): boolean {
  const next = competencyPayload(items);
  return next.length !== current.length || next.some((item, index) => item.key !== current[index]!.key || item.label !== current[index]!.label || item.description !== current[index]!.description);
}

/* ---------------------------------------------------------------- Déroulement et annulation */

export interface RulesDraft { readonly procedureText: string; readonly cancellationPolicyText: string; readonly sources: string }
export const rulesDraft = (value: { procedureText: string; cancellationPolicyText: string; sourceUrls: readonly string[] } | null): RulesDraft =>
  ({ procedureText: value?.procedureText ?? '', cancellationPolicyText: value?.cancellationPolicyText ?? '', sources: value?.sourceUrls.join('\n') ?? '' });
export const sourceList = (text: string) => text.split(/\s*\n\s*/).map(item => item.trim()).filter(Boolean);
export function rulesProblems(draft: RulesDraft) {
  const sources = sourceList(draft.sources);
  const problems = {
    procedureText: filled(draft.procedureText, 4000) ? null : 'Décrivez le déroulement d’une leçon (4 000 caractères au plus).',
    cancellationPolicyText: filled(draft.cancellationPolicyText, 4000) ? null : 'Indiquez les conditions d’annulation (4 000 caractères au plus).',
    sources: sources.length > 30 ? '30 liens au plus.' : sources.some(item => !isHttpURL(item)) ? 'Indiquez une adresse web complète par ligne (https://…).' : null,
  };
  return { ...problems, valid: Object.values(problems).every(value => value === null) };
}
export const rulesPayload = (draft: RulesDraft) => ({ procedureText: draft.procedureText.trim(), cancellationPolicyText: draft.cancellationPolicyText.trim(), sourceUrls: sourceList(draft.sources) });
export function rulesChanged(draft: RulesDraft, current: { procedureText: string; cancellationPolicyText: string; sourceUrls: readonly string[] } | null): boolean {
  const next = rulesPayload(draft);
  return !current || next.procedureText !== current.procedureText || next.cancellationPolicyText !== current.cancellationPolicyText
    || next.sourceUrls.length !== current.sourceUrls.length || next.sourceUrls.some((value, index) => value !== current.sourceUrls[index]);
}

/* ---------------------------------------------------------------- Général */

export interface GeneralDraft { readonly label: string; readonly offered: boolean; readonly duration: string }
export const generalDraft = (programme: Programme): GeneralDraft =>
  ({ label: programme.head.label ?? '', offered: programme.head.enabled, duration: programme.head.defaultDurationMinutes === null ? '' : String(programme.head.defaultDurationMinutes) });
export function minutes(text: string): number | null {
  return /^\d{1,4}$/.test(text.trim()) ? Number(text.trim()) : null;
}
export function generalProblems(draft: GeneralDraft, nameRequired: boolean, otherNames: readonly string[]) {
  const value = minutes(draft.duration), name = draft.label.trim();
  const problems = {
    label: nameRequired && !name ? 'Nommez ce parcours pour le distinguer des autres parcours du permis.'
      : characters(name) > 120 ? '120 caractères au plus.'
        : name && otherNames.some(other => other.toLocaleLowerCase('fr') === name.toLocaleLowerCase('fr')) ? 'Un autre parcours de ce permis porte déjà ce nom.' : null,
    duration: value === null || value < 1 || value > 480 ? 'Indiquez une durée de 1 à 480 minutes.' : null,
  };
  return { ...problems, valid: problems.label === null && problems.duration === null };
}
export function generalChanges(draft: GeneralDraft, programme: Programme): { label?: string | null; enabled?: boolean; defaultDurationMinutes?: number } {
  const label = draft.label.trim() || null, duration = minutes(draft.duration);
  return {
    ...(label !== programme.head.label ? { label } : {}),
    ...(draft.offered !== programme.head.enabled ? { enabled: draft.offered } : {}),
    ...(duration !== null && duration !== programme.head.defaultDurationMinutes ? { defaultDurationMinutes: duration } : {}),
  };
}

/* ---------------------------------------------------------------- Parcours */

/** Nom affiché d'un parcours : son nom enregistré, sinon une désignation neutre, jamais déduite d'un tarif ou d'une clé. */
export function programmeName(programme: Programme, all: readonly Programme[]): string {
  if (programme.head.label) return programme.head.label;
  if (all.length <= 1) return 'Parcours';
  const unnamed = all.filter(item => !item.head.label);
  return unnamed.length === 1 ? 'Parcours sans nom' : `Parcours sans nom ${unnamed.indexOf(programme) + 1}`;
}

/* ---------------------------------------------------------------- Tarifs */

/** Message commun des champs de prix (fiche de tarif et brouillon d'école). */
export const priceAmountProblem = 'Indiquez un montant en CHF, par exemple 95 ou 95.50.';
export const tariffTypeLabels: Record<TariffType, string> = {
  INDIVIDUAL_LESSON: 'Leçon individuelle', EXAM_SUPPORT: 'Accompagnement à l’examen', COLLECTIVE_COURSE: 'Cours collectif', EXTERNAL_SERVICE: 'Autre prestation',
};
export const defaultUnit: Record<TariffType, string> = { INDIVIDUAL_LESSON: 'leçon', EXAM_SUPPORT: 'accompagnement', COLLECTIVE_COURSE: 'séance', EXTERNAL_SERVICE: 'unité' };
export interface TariffDraft {
  readonly type: TariffType; readonly label: string; readonly duration: string; readonly unitLabel: string; readonly price: string;
  readonly validFrom: string; readonly validUntil: string; readonly enabled: boolean; readonly termsText: string;
}
export const newTariffDraft = (type: TariffType, today: string, termsText = ''): TariffDraft =>
  ({ type, label: '', duration: type === 'INDIVIDUAL_LESSON' ? '45' : '', unitLabel: defaultUnit[type], price: '', validFrom: today, validUntil: '', enabled: true, termsText });
export const tariffDraft = (tariff: Tariff): TariffDraft => ({
  type: tariff.head.type, label: tariff.head.label, duration: tariff.head.durationMinutes === null ? '' : String(tariff.head.durationMinutes), unitLabel: tariff.head.unitLabel,
  price: centsToInput(tariff.head.unitPriceCents), validFrom: tariff.head.validFrom, validUntil: tariff.head.validUntil ?? '', enabled: tariff.head.enabled, termsText: tariff.terms?.termsText ?? '',
});
/** Début de la nouvelle version d'un tarif modifié : aujourd'hui, ou la date déjà prévue d'un tarif pas encore commencé. */
export const updatedValidFrom = (tariff: Tariff, today: string) => tariff.head.validFrom > today ? tariff.head.validFrom : today;
export function tariffProblems(draft: TariffDraft, mode: 'CREATE' | 'UPDATE', today: string, start = draft.validFrom) {
  const duration = draft.duration.trim() === '' ? null : minutes(draft.duration), cents = parseCents(draft.price);
  const lesson = draft.type === 'INDIVIDUAL_LESSON', maximum = lesson ? 480 : 1440;
  const problems = {
    label: filled(draft.label, 200) ? null : 'Indiquez le nom du tarif (200 caractères au plus).',
    duration: lesson && duration === null ? 'Une leçon a une durée : indiquez-la en minutes.'
      : draft.duration.trim() !== '' && (duration === null || duration < 1 || duration > maximum) ? `Indiquez une durée de 1 à ${maximum} minutes.` : null,
    unitLabel: filled(draft.unitLabel, 100) ? null : 'Indiquez l’unité facturée (par exemple « leçon »).',
    price: draft.price.trim() === '' ? 'Indiquez le prix en CHF (0 pour une prestation offerte).' : cents === null ? priceAmountProblem : null,
    validFrom: mode === 'UPDATE' ? null : !isCivilDate(draft.validFrom) ? 'Indiquez la date de début.' : null,
    validUntil: draft.validUntil === '' ? null : !isCivilDate(draft.validUntil) ? 'Indiquez une date valide.'
      : draft.validUntil < start ? 'La fin précède le début de validité.' : draft.enabled && draft.validUntil < today ? 'Cette date est déjà passée.' : null,
    termsText: filled(draft.termsText, 20_000) ? null : 'Rédigez les conditions commerciales de ce tarif.',
  };
  return { ...problems, valid: Object.values(problems).every(value => value === null) };
}
export function createTariffBody(draft: TariffDraft, categoryCode: string | null) {
  return { mode: 'CREATE' as const, categoryCode, type: draft.type, label: draft.label.trim(), durationMinutes: draft.duration.trim() === '' ? null : minutes(draft.duration),
    unitLabel: draft.unitLabel.trim(), priceCents: parseCents(draft.price), validFrom: draft.validFrom, validUntil: draft.validUntil || null, enabled: draft.enabled, termsText: draft.termsText.trim() };
}
/** Conditions inchangées : la même référence est conservée ; sinon une référence propre à ce tarif est créée. */
export function updateTariffBody(draft: TariffDraft, tariff: Tariff, today: string) {
  const keepTerms = !!tariff.terms && tariff.terms.approved && tariff.terms.termsText === draft.termsText.trim()
    && !(tariff.terms.validUntil !== null && tariff.terms.validUntil < today);
  return { mode: 'UPDATE' as const, productKey: tariff.productKey, expectedProductVersionId: tariff.head.id, type: draft.type, label: draft.label.trim(),
    durationMinutes: draft.duration.trim() === '' ? null : minutes(draft.duration), unitLabel: draft.unitLabel.trim(), priceCents: parseCents(draft.price),
    validUntil: draft.validUntil || null, enabled: draft.enabled, terms: keepTerms ? { mode: 'KEEP' as const } : { mode: 'NEW' as const, termsText: draft.termsText.trim() } };
}
export function tariffChanged(draft: TariffDraft, tariff: Tariff, today: string): boolean {
  const body = updateTariffBody(draft, tariff, today);
  return body.terms.mode === 'NEW' || body.label !== tariff.head.label || body.type !== tariff.head.type || body.durationMinutes !== tariff.head.durationMinutes
    || body.unitLabel !== tariff.head.unitLabel || body.priceCents !== tariff.head.unitPriceCents || body.validUntil !== tariff.head.validUntil || body.enabled !== tariff.head.enabled;
}
/** Seuls les états inhabituels reçoivent un badge ; un tarif proposé n'en a pas. */
export function tariffStatusBadge(status: TariffStatus, tariff: { validFrom: string; validUntil: string | null }, format: (date: string) => string):
  { tone: 'neutral' | 'warning'; label: string } | null {
  switch (status) {
    case 'OFFERED': return tariff.validUntil ? { tone: 'neutral', label: `Jusqu’au ${format(tariff.validUntil)}` } : null;
    case 'DISABLED': return { tone: 'neutral', label: 'Non proposé' };
    case 'NOT_YET': return { tone: 'neutral', label: `À partir du ${format(tariff.validFrom)}` };
    case 'ENDED': return { tone: 'neutral', label: `Terminé le ${format(tariff.validUntil!)}` };
    case 'TERMS_NOT_APPROVED': return { tone: 'warning', label: 'Conditions à revoir' };
    case 'TERMS_EXPIRED': return { tone: 'warning', label: 'Conditions expirées' };
    case 'TERMS_NOT_YET': return { tone: 'neutral', label: 'Conditions à venir' };
  }
}
export function categoryBadge(state: 'READY' | 'INCOMPLETE' | 'NOT_OFFERED'): { tone: 'neutral' | 'warning'; label: string } | null {
  return state === 'INCOMPLETE' ? { tone: 'warning', label: 'À compléter' } : state === 'NOT_OFFERED' ? { tone: 'neutral', label: 'Non proposée' } : null;
}
export function categoryIssueText(issue: 'PROGRAMME_REQUIRED' | 'PROGRAMME_INCOMPLETE' | 'LESSON_TARIFF_REQUIRED'): string {
  return issue === 'PROGRAMME_REQUIRED' ? 'Ce permis n’a pas encore de parcours : préparez ses compétences et ses règles.'
    : issue === 'PROGRAMME_INCOMPLETE' ? 'Un parcours n’a pas encore de compétences, de règles ou de durée enregistrées.'
      : 'Aucun tarif de leçon n’est proposé pour ce permis.';
}

/* ---------------------------------------------------------------- Assistant de création */

/** Catégories suisses courantes ; un autre code reste possible. Aucune n'est présentée comme une obligation réglementaire. */
export const commonCategories = ['A1', 'A', 'B1', 'B', 'BE', 'C1', 'C1E', 'C', 'CE', 'D1', 'D1E', 'D', 'DE', 'F', 'G', 'M'] as const;
export interface WizardDraft {
  readonly category: string; readonly intent: 'NEW' | 'ADDITIONAL_PROGRAMME'; readonly programmeLabel: string;
  readonly competencies: CompetencyDraft[]; readonly rules: RulesDraft; readonly tariff: TariffDraft;
  readonly source: { templateId: string; templateVersion: string } | null;
}
export function wizardCategoryProblem(category: string, intent: WizardDraft['intent'], programmeLabel: string, existing: readonly string[], existingNames: readonly string[] = []): string | null {
  const value = category.trim();
  if (!value) return 'Choisissez le permis de cette formation.';
  if (characters(value) > 30 || /[\u0000-\u001f\u007f]/.test(value)) return '30 caractères au plus.';
  if (existing.includes(value) && intent === 'NEW') return 'Ce permis est déjà préparé : ouvrez sa fiche, ou ajoutez explicitement un autre parcours.';
  if (intent === 'ADDITIONAL_PROGRAMME') {
    if (!filled(programmeLabel, 120)) return 'Nommez le nouveau parcours (120 caractères au plus).';
    if (existingNames.some(name => name.toLocaleLowerCase('fr') === programmeLabel.trim().toLocaleLowerCase('fr'))) return 'Un autre parcours de ce permis porte déjà ce nom.';
  }
  return null;
}
export function createFormationBody(draft: WizardDraft) {
  return {
    categoryCode: draft.category.trim(), intent: draft.intent, programmeLabel: draft.intent === 'ADDITIONAL_PROGRAMME' ? draft.programmeLabel.trim() : null,
    competencies: competencyPayload(draft.competencies), procedure: rulesPayload(draft.rules),
    ...(draft.source ? { source: { templateId: draft.source.templateId, templateVersion: draft.source.templateVersion } } : {}),
    tariff: { label: draft.tariff.label.trim(), durationMinutes: minutes(draft.tariff.duration), priceCents: parseCents(draft.tariff.price),
      validFrom: draft.tariff.validFrom, validUntil: draft.tariff.validUntil || null, termsText: draft.tariff.termsText.trim() },
  };
}
