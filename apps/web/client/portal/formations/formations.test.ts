import { describe, expect, test } from 'vitest';
import { competencyDrafts, emptyCompetency, generalDraft, moveItem, rulesDraft, type CompetencyDraft } from '../../console/formation-model';
import type { CatalogueReference, Programme } from '../../formation-api';
import { competencyChangeCount, competencyChanges, generalDifferences, rulesChanges } from './formation-diff';
import { duration, plural, priceLabel, validity } from './formation-format';
import { referenceDestination, sheetView } from './sheet-routing';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const before = [
  { key: 'preparation', label: 'Préparer la conduite', description: 'Régler le poste.' },
  { key: 'observation', label: 'Observer', description: 'Chercher les indices.' },
  { key: 'speed', label: 'Allure', description: 'Adapter.' },
];
const withKeys = (items: typeof before): CompetencyDraft[] => competencyDrafts(items);

describe('différences de compétences', () => {
  test('aucune différence lorsque la liste est inchangée', () => {
    const changes = competencyChanges(before, withKeys(before));
    expect(competencyChangeCount(changes)).toBe(0);
    expect(changes.reordered).toBe(false);
  });
  test('ajout sans clé, retrait, reformulation et ordre sont distingués', () => {
    const drafts = withKeys(before);
    const added = { ...emptyCompetency(), label: ' Intersections ', description: 'Franchir.' };
    const next = [drafts[2]!, { ...drafts[0]!, label: 'Préparer le véhicule' }, added];
    const changes = competencyChanges(before, next);
    expect(changes.added).toEqual([{ item: { key: null, label: 'Intersections', description: 'Franchir.' }, position: 3 }]);
    expect(changes.removed.map(item => item.key)).toEqual(['observation']);
    expect(changes.edited).toEqual([{ before: before[0], after: { key: 'preparation', label: 'Préparer le véhicule', description: 'Régler le poste.' } }]);
    // « speed » passe avant « preparation » : l'ordre relatif des éléments conservés a changé.
    expect(changes.reordered).toBe(true);
    expect(competencyChangeCount(changes)).toBe(4);
  });
  test('retirer ou ajouter un élément ne compte pas comme un changement d’ordre', () => {
    const drafts = withKeys(before);
    expect(competencyChanges(before, [drafts[0]!, drafts[2]!]).reordered).toBe(false);
    expect(competencyChanges(before, [{ ...emptyCompetency(), label: 'Nouveau', description: 'x' }, ...drafts]).reordered).toBe(false);
  });
  test('déplacer un élément et le remettre en place annule la différence', () => {
    const drafts = withKeys(before);
    const back = moveItem(moveItem(drafts, 0, 1), 1, -1);
    expect(competencyChangeCount(competencyChanges(before, back))).toBe(0);
  });
});

describe('différences de règles et de parcours', () => {
  const current = { procedureText: 'Déroulement.', cancellationPolicyText: 'Annulation.', sourceUrls: ['https://example.ch/a'] };
  test('seuls les textes modifiés sont présentés, avec leur version enregistrée', () => {
    const draft = { ...rulesDraft(current), cancellationPolicyText: ' Annulation 48 h. ' };
    expect(rulesChanges(current, draft)).toEqual([{ field: 'cancellationPolicyText', label: 'Conditions d’annulation', before: 'Annulation.', after: 'Annulation 48 h.' }]);
    expect(rulesChanges(current, rulesDraft(current))).toEqual([]);
  });
  test('des règles jamais rédigées comparent contre un texte vide', () => {
    expect(rulesChanges(null, { ...rulesDraft(null), procedureText: 'Nouveau', cancellationPolicyText: 'Règle' }).map(row => row.before)).toEqual(['', '']);
  });
  const programme = { offeringKey: 'k', head: { id: id(1), version: 2, enabled: true, label: null, defaultDurationMinutes: 45, hasReferencePrice: true, createdAt: '2026-10-01T08:00:00.000Z', ready: true, complete: true } } as Programme;
  test('nom, inscriptions et durée de parcours', () => {
    expect(generalDifferences({ label: 'Intensif', offered: false, duration: '60' }, programme)).toEqual([
      { label: 'Nom du parcours', before: 'Sans nom', after: 'Intensif' },
      { label: 'Nouvelles inscriptions', before: 'Proposée', after: 'Non proposée' },
      { label: 'Durée habituelle', before: '45 min', after: '1 h' },
    ]);
    expect(generalDifferences(generalDraft(programme), programme)).toEqual([]);
  });
});

describe('formatage des prix et durées', () => {
  test('un prix absent n’est jamais présenté comme gratuit', () => {
    expect(priceLabel(null)).toBe('Prix non défini');
    expect(priceLabel(0)).toBe('Offert');
    expect(priceLabel(9500)).toMatch(/95\.00/);
    expect(priceLabel(9505)).toMatch(/95\.05/);
  });
  test('durée, pluriel et validité', () => {
    expect([duration(45), duration(60), duration(90), duration(null)]).toEqual(['45 min', '1 h', '1 h 30', 'Non renseignée']);
    expect([plural(1, 'élève'), plural(3, 'élève'), plural(2, 'parcours', 'parcours')]).toEqual(['1 élève', '3 élèves', '2 parcours']);
    expect(validity('2026-10-28', null)).toBe('Dès le 28.10.2026');
    expect(validity('2026-10-28', '2026-12-31')).toBe('Du 28.10.2026 au 31.12.2026');
  });
});

describe('routage des références', () => {
  const using = (current: boolean, key = 'formation-b') => ({ offeringKey: key, categoryCode: 'B', label: null, headId: id(9), current });
  test('une adresse inconnue de rubrique ouvre Général', () => {
    expect(sheetView(undefined)).toBe('general');
    expect(sheetView('tarifs')).toBe('tarifs');
    expect(sheetView('nouvelle')).toBe('general');
  });
  test('une version actuelle ouvre sa rubrique, une ancienne l’historique du permis', () => {
    const offering = (current: boolean) => ({ kind: 'OFFERING', id: id(2), categoryCode: 'B', current, offeringKey: 'formation-b' } as CatalogueReference);
    expect(referenceDestination(offering(true))).toEqual({ section: 'formations', query: { category: 'B', view: 'general', programme: 'formation-b' } });
    expect(referenceDestination(offering(false))).toEqual({ section: 'formations', query: { category: 'B', view: 'historique', selection: id(2) } });
  });
  test('un contenu partagé par plusieurs parcours ne choisit pas un parcours à la place de la personne', () => {
    const curriculum = (programmes: ReturnType<typeof using>[]) => ({ kind: 'CURRICULUM', id: id(3), categoryCode: 'B', current: true, programmes } as CatalogueReference);
    expect(referenceDestination(curriculum([using(true)])).query).toEqual({ category: 'B', view: 'competences', programme: 'formation-b' });
    expect(referenceDestination(curriculum([using(true), using(true, 'formation-b2')])).query.view).toBe('historique');
    expect(referenceDestination(curriculum([])).query.view).toBe('historique');
  });
  test('tarifs, prestations sans permis et conditions', () => {
    const tariff = (categoryCode: string | null, current: boolean) => ({ kind: 'TARIFF', id: id(4), categoryCode, current } as CatalogueReference);
    expect(referenceDestination(tariff('B', true))).toEqual({ section: 'formations', query: { category: 'B', view: 'tarifs', selection: id(4) } });
    expect(referenceDestination(tariff('B', false)).query.view).toBe('historique');
    expect(referenceDestination(tariff(null, false))).toEqual({ section: 'prestations', query: { selection: id(4) } });
    expect(referenceDestination({ kind: 'TERMS', id: id(5) } as CatalogueReference)).toEqual({ section: 'conditions', query: { selection: id(5) } });
  });
});
