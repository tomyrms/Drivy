import { describe, expect, test } from 'vitest';
import { newTariffDraft, tariffDraft } from '../../console/formation-model';
import type { Tariff } from '../../formation-api';
import { tariffDifferences, tariffSummary } from './tariff-diff';
import { tariffGroups } from './tariff-groups';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const today = '2026-10-28';
function tariff(extra: Partial<Tariff['head']> = {}, over: Partial<Tariff> = {}): Tariff {
  return { productKey: 'lesson-45', status: 'OFFERED', termsSharedWith: 2, history: [], historyTruncated: false,
    head: { id: id(1), productKey: 'lesson-45', version: 2, label: 'Leçon de 45 minutes', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45, unitLabel: 'leçon', unitPriceCents: 9500,
      validFrom: '2026-09-01', validUntil: null, termsVersionId: id(2), enabled: true, createdAt: '2026-09-01T08:00:00.000Z', ...extra },
    terms: { id: id(2), version: 2, label: 'Conditions de l’école', termsText: 'Conditions communes.', validFrom: '2026-09-01', validUntil: null, approved: true, createdAt: '2026-09-01T08:00:00.000Z' }, ...over };
}

describe('récapitulatif d’un tarif modifié', () => {
  test('aucune ligne tant que rien ne change', () => {
    const current = tariff();
    expect(tariffDifferences(tariffDraft(current), current, today)).toEqual([]);
  });
  test('prix, durée et réservations apparaissent avec leur valeur d’avant et d’après', () => {
    const current = tariff();
    const rows = tariffDifferences({ ...tariffDraft(current), price: '105.50', duration: '50', enabled: false }, current, today);
    expect(rows.map(row => row.label)).toEqual(['Durée', 'Prix', 'Réservations']);
    expect(rows[0]).toEqual({ label: 'Durée', before: '45 min', after: '50 min' });
    expect(rows[1]!.before).toMatch(/95\.00/);
    expect(rows[1]!.after).toMatch(/105\.50/);
    expect(rows[2]).toEqual({ label: 'Réservations', before: 'Proposé', after: 'Non proposé' });
  });
  test('un texte de conditions modifié crée des conditions propres sans toucher aux autres tarifs', () => {
    const current = tariff();
    const rows = tariffDifferences({ ...tariffDraft(current), termsText: 'Conditions propres.' }, current, today);
    expect(rows).toEqual([{ label: 'Conditions', before: 'Conditions communes', after: 'Conditions propres à ce tarif' }]);
  });
  test('un champ de prix vidé reste non défini, jamais 0', () => {
    const current = tariff();
    const rows = tariffDifferences({ ...tariffDraft(current), price: '' }, current, today);
    expect(rows.find(row => row.label === 'Prix')?.after).toBe('Prix non défini');
  });
  test('la création résume le cas courant : permis, durée, prix et début de validité', () => {
    const rows = tariffSummary({ ...newTariffDraft('INDIVIDUAL_LESSON', today, 'Conditions.'), label: 'Leçon de 45 minutes', price: '0' });
    expect(rows.find(row => row.label === 'Prix')?.after).toMatch(/^Offert par leçon$/);
    expect(rows.find(row => row.label === 'Durée')?.after).toBe('45 min');
    expect(rows.some(row => row.label === 'Jusqu’au')).toBe(false);
  });
});

describe('groupes de tarifs', () => {
  test('les tarifs non proposés ou terminés passent en archives, les autres restent en cours', () => {
    const groups = tariffGroups([tariff(), tariff({ productKey: 'x', id: id(3) }, { productKey: 'x', status: 'DISABLED' }), tariff({}, { productKey: 'y', status: 'ENDED' }),
      tariff({}, { productKey: 'z', status: 'NOT_YET' }), tariff({}, { productKey: 'w', status: 'TERMS_EXPIRED' })]);
    expect(groups.current.map(item => item.productKey)).toEqual(['lesson-45', 'z', 'w']);
    expect(groups.archived.map(item => item.productKey)).toEqual(['x', 'y']);
  });
});
