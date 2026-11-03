import { describe, expect, test } from 'vitest';
import type { GeneralDraft, WizardDraft } from '../../console/formation-model';
import type { Programme } from '../../formation-api';
import {
  formationMarkLabels, formationTag, isOpenable, isProvisional, projectCategories, projectProgramme, programmeRefusal,
  resolveFormationIntentions, schoolIdentifier, type FormationIntention, type FormationMark, type ProgrammeIntention, type ProgrammeSection,
  type ShownIntention,
} from './formation-projection';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** Fiche de l'école : la seule version qui existe pour une leçon, un dossier ou une réservation. */
function programme(over: Partial<Programme> = {}): Programme {
  return {
    offeringKey: 'offering-a',
    head: { id: id(1), version: 3, enabled: true, label: 'Parcours A', defaultDurationMinutes: 45, hasReferencePrice: true, createdAt: '2026-11-01T08:00:00.000Z', ready: true, complete: true },
    curriculum: { id: id(2), revision: 2, approved: true, categoryCode: 'A', createdAt: '2026-11-01T08:00:00.000Z',
      competencies: [{ id: id(3), key: 'preparation', label: 'Préparer la moto', description: 'Contrôles avant le départ.', sortOrder: 0 }] },
    procedure: { id: id(4), version: 2, approved: true, categoryCode: 'A', createdAt: '2026-11-01T08:00:00.000Z',
      procedureText: 'Déroulement enregistré par l’école.', cancellationPolicyText: 'Annulation enregistrée par l’école.', sourceUrls: [] },
    enrollments: { current: 2, previous: 1 },
    sharedCurriculumWith: [], sharedProcedureWith: [],
    history: [{ id: id(5), version: 2, enabled: true, label: 'Parcours A', curriculumVersionId: id(2), policyVersionId: id(4),
      defaultDurationMinutes: 45, createdAt: '2026-11-01T08:00:00.000Z', curriculumRevision: 2, policyVersion: 2, trainings: 2 }],
    historyTruncated: false,
    ...over,
  };
}

const wizard = (over: Partial<WizardDraft> = {}): WizardDraft => ({
  category: 'B', intent: 'NEW', programmeLabel: '', source: null,
  competencies: [{ uid: 'c1', key: null, label: 'Préparer la moto', description: 'Contrôles avant le départ.' }],
  rules: { procedureText: 'Déroulement saisi.', cancellationPolicyText: 'Annulation saisie.', sources: '' },
  tariff: { type: 'INDIVIDUAL_LESSON', label: 'Leçon de 45 minutes', duration: '45', unitLabel: 'leçon', price: '95', validFrom: '2026-11-03', validUntil: '', enabled: true, termsText: 'Conditions saisies.' },
  ...over,
});

const general: GeneralDraft = { label: 'Parcours renommé', offered: true, duration: '60' };

/** Une création n'a pas encore d'identifiant de l'école : son intention ne nomme aucune formation. */
const creation = (operationId = 'op-9', over: Partial<WizardDraft> = {}): FormationIntention =>
  ({ kind: 'create', tag: formationTag(null), operationId, offeringKey: null, draft: wizard(over) });

const intention = (over: Partial<Omit<ProgrammeIntention, 'kind'>> = {}): ProgrammeIntention => ({
  kind: 'programme', tag: formationTag('offering-a'), operationId: 'op-1', offeringKey: 'offering-a', section: 'general', draft: general, ...over,
});
const shown = (item: FormationIntention, mark: FormationMark | null): ShownIntention => ({ intention: item, mark });

describe('projection d’une formation (#124)', () => {
  test('une création est une ligne provisoire sans identifiant de l’école, donc inutilisable par un dossier ou une leçon', () => {
    const rows = projectCategories([{ categoryCode: 'A' }], [shown(creation('op-9', { category: 'B' }), 'creating')]);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toEqual({ kind: 'published', categoryCode: 'A' });
    const created = rows[1]!;
    expect(created.kind).toBe('provisional');
    if (created.kind !== 'provisional') throw new Error('La création doit rester provisoire.');
    expect(created.key).toBe('pending:op-9');
    expect(isProvisional(created.key)).toBe(true);
    expect(created.categoryCode).toBe('B');
    expect(created.mark).toBe('creating');
    // Rien à ouvrir, à réserver, ni à désigner depuis un dossier ou une leçon.
    expect(isOpenable(created)).toBe(false);
    expect(schoolIdentifier(created)).toBeNull();
    expect(isOpenable(rows[0]!)).toBe(true);
    expect(schoolIdentifier(rows[0]!)).toBe('A');
    expect(formationMarkLabels.creating).toBe('À confirmer');
  });

  test('une version enregistrée montre la version voulue marquée, sans remplacer celle de l’école', () => {
    const published = programme();
    const projected = projectProgramme<GeneralDraft>(published, 'general', [shown(intention({ draft: general }), 'saving')]);
    expect(projected.programme).toBe(published);
    // La fiche publiée garde ses valeurs : le nom et la durée ne sont pas réécrits par la demande.
    expect(projected.programme.head.label).toBe('Parcours A');
    expect(projected.programme.head.defaultDurationMinutes).toBe(45);
    expect(projected.wanted).toEqual({ section: 'general', draft: general });
    expect(projected.mark).toBe('saving');
    expect(formationMarkLabels.saving).toBe('Enregistrement en cours');
    // Une autre rubrique n'hérite pas de la marque de celle qui est en cours.
    expect(projectProgramme(published, 'competences', [shown(intention({ draft: general }), 'saving')]).mark).toBeNull();
    // Une autre formation non plus.
    const other = intention({ offeringKey: 'formation-b', tag: formationTag('formation-b') });
    expect(projectProgramme(published, 'general', [shown(other, 'changing')]).mark).toBeNull();
  });

  test('après la réponse du magasin, la même demande dit « À confirmer » sans rien annoncer de publié', () => {
    const published = programme();
    const followed = resolveFormationIntentions([intention()], new Set(), new Set(['op-1']));
    const projected = projectProgramme<GeneralDraft>(published, 'general', followed);
    expect(projected.mark).toBe('changing');
    expect(projected.programme).toBe(published);
    expect(formationMarkLabels.changing).toBe('Modification à confirmer');
    // Une demande abandonnée ou refusée n'est plus suivie : elle disparaît.
    expect(resolveFormationIntentions([intention()], new Set(), new Set())).toEqual([]);
  });

  test('l’historique des versions ne reçoit rien de provisoire', () => {
    const published = programme();
    const projected = projectProgramme(published, 'competences', [
      shown(creation('op-9'), 'saving'),
      shown(intention({ section: 'competences', draft: ['a'] }), 'changing'),
    ]);
    expect(projected.history).toBe(published.history);
    expect(projected.history.map(item => item.version)).toEqual([2]);
    expect(projected.history.some(item => item.id.startsWith('pending:'))).toBe(false);
    // La création provisoire n'ajoute aucune ligne au catalogue des versions.
    expect(projectCategories([], [shown(creation('op-9'), 'creating')])).toHaveLength(1);
  });

  test('une lecture plus récente que la confirmation retire la version voulue', () => {
    const settled: FormationIntention = { ...intention(), settledAt: 1_000 };
    expect(resolveFormationIntentions([settled], new Set(), new Set(), 999)).toHaveLength(1);
    expect(resolveFormationIntentions([settled], new Set(), new Set(), 1_001)).toEqual([]);
  });

  test('un refus ne touche que sa rubrique et rend la saisie exacte avec sa raison', () => {
    const refused = programmeRefusal(intention({ draft: general }), general,
      { tone: 'error', title: 'Modification refusée', message: 'La fiche a changé. Votre saisie est conservée.', code: 'FORMATION_CHANGED' });
    expect(refused.section).toBe('general');
    expect(refused.draft).toBe(general);
    expect(refused.outcome.code).toBe('FORMATION_CHANGED');
    expect(refused.intention.offeringKey).toBe('offering-a');
    // Le refus ne fabrique aucune version : la fiche de l'école reste la seule affichée.
    const published = programme();
    expect(projectProgramme(published, 'general', []).wanted).toBeNull();
    expect(projectProgramme(published, 'general', []).programme).toBe(published);
  });

  test('la portée d’une demande est la formation ; une création n’en a pas encore', () => {
    const section: ProgrammeSection = 'reference';
    expect(intention({ section }).section).toBe('reference');
    expect(formationTag('offering-a')).toBe('formation:offering-a');
    expect(formationTag(null)).toBe('formation:new');
    expect(creation().offeringKey).toBeNull();
  });
});
