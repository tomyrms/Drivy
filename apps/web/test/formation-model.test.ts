import { describe, expect, test } from 'vitest';
import {
  categoryBadge, competenciesChanged, competencyDrafts, competencyPayload, competencyProblems, createFormationBody, createTariffBody, emptyCompetency,
  generalChanges, generalProblems, moveItem, newTariffDraft, programmeName, rulesChanged, rulesDraft, rulesPayload, rulesProblems, tariffChanged,
  tariffDraft, tariffProblems, tariffStatusBadge, updateTariffBody, updatedValidFrom, wizardCategoryProblem, type WizardDraft,
} from '../client/console/formation-model.js';
import { matchSchoolRoute } from '../server/school-routes.js';
import { commandSpecs, createCommand } from '../client/command-core.js';
import type { Programme, Tariff } from '../client/formation-api.js';

const school = '7d4b1c2e-9a1f-4c3b-8e2d-1f0a9b8c7d6e', id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const at = '2026-10-14T08:00:00.000Z';
function programme(extra: Partial<Programme['head']> = {}, key = 'category-b'): Programme {
  return { offeringKey: key, head: { id: id(1), version: 2, enabled: true, label: null, defaultDurationMinutes: 50, hasReferencePrice: true, createdAt: at, ready: true, complete: true, ...extra },
    curriculum: { id: id(2), revision: 1, approved: true, categoryCode: 'B', createdAt: at, competencies: [{ id: id(3), key: 'look', label: 'Observation', description: 'Observer.', sortOrder: 0 }] },
    procedure: { id: id(4), version: 1, approved: true, categoryCode: 'B', createdAt: at, procedureText: 'Déroulement.', cancellationPolicyText: 'Annulation.', sourceUrls: [] },
    enrollments: { current: 1, previous: 2 }, sharedCurriculumWith: [], sharedProcedureWith: [], history: [], historyTruncated: false };
}
function tariff(extra: Partial<Tariff['head']> = {}, terms: Partial<NonNullable<Tariff['terms']>> = {}): Tariff {
  return { productKey: 'lesson-50', status: 'OFFERED', termsSharedWith: 0, history: [], historyTruncated: false,
    head: { id: id(10), productKey: 'lesson-50', version: 1, label: 'Leçon 50 min', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 50, unitLabel: 'leçon', unitPriceCents: 9000,
      validFrom: '2026-01-01', validUntil: null, termsVersionId: id(11), enabled: true, createdAt: at, ...extra },
    terms: { id: id(11), version: 1, label: 'Conditions', termsText: 'Conditions de la leçon.', validFrom: '2026-01-01', validUntil: null, approved: true, createdAt: at, ...terms } };
}

describe('compétences', () => {
  test('ordre géré par la liste, identifiants repris conservés et nouveaux sans clé', () => {
    const items = competencyDrafts([{ key: 'look', label: 'Observation', description: 'Observer.' }]);
    const added = [...items, { ...emptyCompetency(), label: 'Intersections', description: 'Franchir.' }];
    const moved = moveItem(added, 1, -1);
    expect(competencyPayload(moved)).toEqual([{ key: null, label: 'Intersections', description: 'Franchir.' }, { key: 'look', label: 'Observation', description: 'Observer.' }]);
    expect(moveItem(moved, 0, -1)).toEqual(moved);
    expect(competenciesChanged(items, [{ key: 'look', label: 'Observation', description: 'Observer.' }])).toBe(false);
    expect(competenciesChanged(moved, [{ key: 'look', label: 'Observation', description: 'Observer.' }])).toBe(true);
  });
  test('libellé, description et doublons expliqués sans numéro ni clé à saisir', () => {
    expect(competencyProblems([]).list).toBe('Ajoutez au moins une compétence.');
    const problems = competencyProblems([{ ...emptyCompetency(), label: 'A', description: 'x' }, { ...emptyCompetency(), label: ' a ', description: '' }]);
    expect(problems.valid).toBe(false);
    expect(problems.items[1]).toEqual({ label: 'Cette compétence figure déjà dans la liste.', description: 'Décrivez ce que l’élève apprend (4 000 caractères au plus).' });
  });
});

describe('déroulement et annulation', () => {
  test('deux textes distincts, sources facultatives en second niveau', () => {
    const draft = rulesDraft({ procedureText: 'D', cancellationPolicyText: 'A', sourceUrls: ['https://example.ch/a'] });
    expect(draft.sources).toBe('https://example.ch/a');
    expect(rulesProblems({ ...draft, sources: 'pas une adresse' }).sources).toBe('Indiquez une adresse web complète par ligne (https://…).');
    expect(rulesPayload({ ...draft, sources: ' https://a.ch \n\n https://b.ch ' }).sourceUrls).toEqual(['https://a.ch', 'https://b.ch']);
    expect(rulesChanged(draft, { procedureText: 'D', cancellationPolicyText: 'A', sourceUrls: ['https://example.ch/a'] })).toBe(false);
    expect(rulesChanged({ ...draft, cancellationPolicyText: 'B' }, { procedureText: 'D', cancellationPolicyText: 'A', sourceUrls: ['https://example.ch/a'] })).toBe(true);
    expect(rulesProblems(rulesDraft(null))).toMatchObject({ procedureText: expect.any(String), cancellationPolicyText: expect.any(String), valid: false });
  });
});

describe('général et parcours', () => {
  test('seuls les champs modifiés partent ; un second parcours doit être nommé', () => {
    const current = programme();
    expect(generalChanges({ label: '', offered: true, duration: '50' }, current)).toEqual({});
    expect(generalChanges({ label: ' Accéléré ', offered: false, duration: '60' }, current)).toEqual({ label: 'Accéléré', enabled: false, defaultDurationMinutes: 60 });
    expect(generalProblems({ label: '', offered: true, duration: '50' }, true, []).label).toBe('Nommez ce parcours pour le distinguer des autres parcours du permis.');
    expect(generalProblems({ label: 'accéléré', offered: true, duration: '0' }, true, ['Accéléré'])).toMatchObject({ label: 'Un autre parcours de ce permis porte déjà ce nom.', duration: 'Indiquez une durée de 1 à 480 minutes.' });
  });
  test('un parcours sans nom n’emprunte jamais le nom d’un tarif ou d’une clé', () => {
    const first = programme(), second = programme({ id: id(5) }, 'formation-x'), named = programme({ id: id(6), label: 'Accéléré' }, 'formation-y');
    expect(programmeName(first, [first])).toBe('Parcours');
    expect(programmeName(first, [first, named])).toBe('Parcours sans nom');
    expect(programmeName(second, [first, second, named])).toBe('Parcours sans nom 2');
    expect(programmeName(named, [first, named])).toBe('Accéléré');
  });
});

describe('tarifs', () => {
  test('prix absent refusé, prix zéro accepté et transmis tel quel', () => {
    const draft = { ...newTariffDraft('INDIVIDUAL_LESSON', '2026-10-14', 'Conditions.'), label: 'Leçon 45 min' };
    expect(tariffProblems(draft, 'CREATE', '2026-10-14').price).toBe('Indiquez le prix en CHF (0 pour une prestation offerte).');
    expect(tariffProblems({ ...draft, price: '0' }, 'CREATE', '2026-10-14').valid).toBe(true);
    expect(createTariffBody({ ...draft, price: '0' }, 'B')).toMatchObject({ mode: 'CREATE', categoryCode: 'B', priceCents: 0, durationMinutes: 45, validUntil: null });
    expect(createTariffBody({ ...draft, price: '95,5' }, 'B').priceCents).toBe(9550);
    expect(tariffProblems({ ...draft, price: '12.345' }, 'CREATE', '2026-10-14').price).toBe('Indiquez un montant en CHF, par exemple 95 ou 95.50.');
    expect(tariffProblems({ ...draft, duration: '' }, 'CREATE', '2026-10-14').duration).toBe('Une leçon a une durée : indiquez-la en minutes.');
    expect(tariffProblems({ ...draft, type: 'EXTERNAL_SERVICE', duration: '', price: '10' }, 'CREATE', '2026-10-14').valid).toBe(true);
  });
  test('modifier les conditions crée une référence propre ; un texte inchangé garde la même', () => {
    const current = tariff(), draft = tariffDraft(current);
    expect(tariffChanged(draft, current, '2026-10-14')).toBe(false);
    expect(updateTariffBody(draft, current, '2026-10-14').terms).toEqual({ mode: 'KEEP' });
    expect(updateTariffBody({ ...draft, termsText: 'Autres conditions.' }, current, '2026-10-14').terms).toEqual({ mode: 'NEW', termsText: 'Autres conditions.' });
    // Conditions expirées : les renouveler même à texte identique.
    expect(updateTariffBody(draft, tariff({}, { validUntil: '2026-10-01' }), '2026-10-14').terms.mode).toBe('NEW');
    expect(updateTariffBody({ ...draft, price: '95' }, current, '2026-10-14')).toMatchObject({ mode: 'UPDATE', productKey: 'lesson-50', expectedProductVersionId: id(10), priceCents: 9500 });
  });
  test('application immédiate, sauf tarif pas encore commencé ; fin passée refusée', () => {
    expect(updatedValidFrom(tariff(), '2026-10-14')).toBe('2026-10-14');
    expect(updatedValidFrom(tariff({ validFrom: '2026-11-01' }), '2026-10-14')).toBe('2026-11-01');
    const draft = tariffDraft(tariff());
    expect(tariffProblems({ ...draft, validUntil: '2026-10-01' }, 'UPDATE', '2026-10-14', '2026-10-14').validUntil).toBe('La fin précède le début de validité.');
    expect(tariffProblems({ ...draft, validUntil: '2026-10-20' }, 'UPDATE', '2026-10-14', '2026-10-14').valid).toBe(true);
  });
  test('états utiles seulement', () => {
    const format = (value: string) => value;
    expect(tariffStatusBadge('OFFERED', { validFrom: '2026-01-01', validUntil: null }, format)).toBeNull();
    expect(tariffStatusBadge('DISABLED', { validFrom: '2026-01-01', validUntil: null }, format)).toEqual({ tone: 'neutral', label: 'Non proposé' });
    expect(tariffStatusBadge('NOT_YET', { validFrom: '2026-11-01', validUntil: null }, format)?.label).toBe('À partir du 2026-11-01');
    expect(tariffStatusBadge('TERMS_EXPIRED', { validFrom: '2026-01-01', validUntil: null }, format)?.tone).toBe('warning');
    expect(categoryBadge('READY')).toBeNull();
    expect(categoryBadge('INCOMPLETE')).toEqual({ tone: 'warning', label: 'À compléter' });
    expect(categoryBadge('NOT_OFFERED')).toEqual({ tone: 'neutral', label: 'Non proposée' });
  });
});

describe('assistant', () => {
  test('un permis déjà préparé n’est jamais recréé en silence', () => {
    expect(wizardCategoryProblem('', 'NEW', '', [])).toBe('Choisissez le permis de cette formation.');
    expect(wizardCategoryProblem('A', 'NEW', '', ['A'])).toBe('Ce permis est déjà préparé : ouvrez sa fiche, ou ajoutez explicitement un autre parcours.');
    expect(wizardCategoryProblem('A', 'ADDITIONAL_PROGRAMME', '', ['A'])).toBe('Nommez le nouveau parcours (120 caractères au plus).');
    expect(wizardCategoryProblem('A', 'ADDITIONAL_PROGRAMME', 'accéléré', ['A'], ['Accéléré'])).toBe('Un autre parcours de ce permis porte déjà ce nom.');
    expect(wizardCategoryProblem('A', 'ADDITIONAL_PROGRAMME', 'Week-end', ['A'], ['Accéléré'])).toBeNull();
  });
  test('une seule commande avec le contenu exact relu', () => {
    const draft: WizardDraft = { category: ' A ', intent: 'NEW', programmeLabel: 'ignoré', source: { templateId: 'pedagogy-a', templateVersion: '2026-10-13.2' },
      competencies: competencyDrafts([{ key: 'preparation', label: 'Préparer', description: 'Préparer la moto.' }]), rules: { procedureText: 'D', cancellationPolicyText: 'A', sources: '' },
      tariff: { ...newTariffDraft('INDIVIDUAL_LESSON', '2026-10-14', 'Conditions.'), label: 'Leçon moto', duration: '50', price: '95' } };
    expect(createFormationBody(draft)).toEqual({ categoryCode: 'A', intent: 'NEW', programmeLabel: null, competencies: [{ key: 'preparation', label: 'Préparer', description: 'Préparer la moto.' }],
      procedure: { procedureText: 'D', cancellationPolicyText: 'A', sourceUrls: [] }, source: { templateId: 'pedagogy-a', templateVersion: '2026-10-13.2' },
      tariff: { label: 'Leçon moto', durationMinutes: 50, priceCents: 9500, validFrom: '2026-10-14', validUntil: null, termsText: 'Conditions.' } });
  });
});

describe('commandes composées et relais', () => {
  test('création ou modification : une opération, un reçu AP72 de la ressource créée', () => {
    for (const kind of ['createFormation', 'saveFormationProgramme', 'saveTariff'] as const) {
      expect(commandSpecs[kind]).toMatchObject({ target: 'created', method: 'POST', expectedStatus: 201 });
      const command = createCommand({ schoolId: school, kind, path: kind === 'saveTariff' ? 'formations/tariffs' : kind === 'createFormation' ? 'formations' : 'formations/programmes', body: {}, resourceVersion: 0 });
      expect(command.body.operationId).toBe(command.operationId);
    }
  });
  test('le relais n’autorise que les routes de la fiche, avec un code de permis borné', () => {
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/sheet`, '?category=A1')?.path).toBe(`/v1/schools/${school}/formations/sheet`);
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/sheet`, '?category=B%20E')?.query).toBe('?category=B+E');
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/sheet`, `?category=${'x'.repeat(31)}`)).toBeUndefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/sheet`, '?category=a%00')).toBeUndefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/sheet`, '?category=A&category=B')).toBeUndefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/formations`, '?category=A')).toBeUndefined();
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/references/${id(3)}`, '')?.route.method).toBe('GET');
    expect(matchSchoolRoute('GET', `/schools/${school}/formations/references/pas-un-uuid`, '')).toBeUndefined();
    for (const path of ['formations', 'formations/programmes', 'formations/tariffs']) expect(matchSchoolRoute('POST', `/schools/${school}/${path}`, '')?.route.bodyLimit).toBeGreaterThan(0);
    expect(matchSchoolRoute('PUT', `/schools/${school}/formations/tariffs`, '')).toBeUndefined();
  });
});
