import { describe, expect, test } from 'vitest';
import { tariffDraft, type TariffDraft } from '../../console/formation-model';
import type { Tariff, TariffVersion } from '../../formation-api';
import {
  isProvisional, pendingFor, projectTariffs, projectTermsRevision, resolveIntentions, tariffMarkLabels, tariffScope, tariffTag, termsScope,
  wantedValues, type ProjectedIntention, type TariffIntention, type TermsIntention,
} from './pricing-projection';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

function tariff(productKey = 'lesson-45', head: Partial<TariffVersion> = {}, over: Partial<Tariff> = {}): Tariff {
  return { productKey, status: 'OFFERED', termsSharedWith: 0, history: [], historyTruncated: false,
    head: { id: id(1), productKey, version: 2, label: 'Leçon de 45 minutes', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45,
      unitLabel: 'leçon', unitPriceCents: 9500, validFrom: '2026-09-01', validUntil: null, termsVersionId: id(2), enabled: true, createdAt: '2026-09-01T08:00:00.000Z', ...head },
    terms: { id: id(2), version: 2, label: 'Conditions de l’école', termsText: 'Conditions communes.', validFrom: '2026-09-01', validUntil: null, approved: true, createdAt: '2026-09-01T08:00:00.000Z' }, ...over };
}
const draft = (over: Partial<TariffDraft> = {}): TariffDraft => ({ ...tariffDraft(tariff()), ...over });
const intention = (over: Partial<TariffIntention> & { kind: TariffIntention['kind']; productKey: string | null }): TariffIntention =>
  ({ tag: tariffTag(over.productKey), operationId: 'op-1', draft: draft(), ...over });
const shown = (item: TariffIntention, mark: ProjectedIntention['mark']): ProjectedIntention => ({ intention: item, mark });

describe('projection d’un tarif (#124)', () => {
  test('une création est une ligne provisoire sans identifiant de l’école, donc inutilisable ailleurs', () => {
    const rows = projectTariffs([tariff()], [shown(intention({ kind: 'create', productKey: null, operationId: 'op-9', draft: draft({ label: 'Nouvelle prestation', price: '40' }) }), 'creating')]);
    expect(rows).toHaveLength(2);
    const created = rows[1]!;
    expect(created.key).toBe('pending:op-9');
    expect(isProvisional(created.key)).toBe(true);
    // Aucune version de l'école : rien à ouvrir, à réserver ni à référencer.
    expect(created.tariff).toBeNull();
    expect(created.wanted?.label).toBe('Nouvelle prestation');
    expect(created.mark).toBe('creating');
    expect(tariffMarkLabels.creating).toBe('À confirmer');
  });

  test('une révision montre la valeur voulue marquée, sans remplacer la version publiée', () => {
    const published = tariff();
    const rows = projectTariffs([published], [shown(intention({ kind: 'update', productKey: 'lesson-45', draft: draft({ price: '105.50' }) }), 'changing')]);
    expect(rows[0]!.tariff).toBe(published);
    // Le prix publié n'est jamais réécrit par une intention.
    expect(rows[0]!.tariff!.head.unitPriceCents).toBe(9500);
    expect(rows[0]!.wanted?.price).toBe('105.50');
    expect(wantedValues(rows[0]!.wanted!).priceCents).toBe(10550);
    expect(rows[0]!.mark).toBe('changing');
    expect(pendingFor('lesson-45', [shown(intention({ kind: 'update', productKey: 'lesson-45', draft: draft({ price: '105.50' }) }), 'changing')]))
      .toMatchObject({ mark: 'changing', wanted: { price: '105.50' } });
  });

  test('une bascule proposé/non proposé est une marque : l’offre publiée reste celle de l’école', () => {
    const published = tariff();
    const rows = projectTariffs([published], [shown(intention({ kind: 'toggle', productKey: 'lesson-45', draft: draft({ enabled: false }) }), 'toggling')]);
    expect(rows[0]!.tariff!.head.enabled).toBe(true);
    expect(rows[0]!.wanted?.enabled).toBe(false);
    expect(rows[0]!.mark).toBe('toggling');
    expect(wantedValues(rows[0]!.wanted!).enabled).toBe(false);
  });

  test('un prix vide n’est jamais 0 : les valeurs voulues le gardent indéfini', () => {
    expect(wantedValues(draft({ price: '' })).priceCents).toBeNull();
    expect(wantedValues(draft({ price: '0' })).priceCents).toBe(0);
    expect(wantedValues(draft({ price: '105.50' })).priceCents).toBe(10550);
  });

  test('rien n’est projeté sur un produit absent de la lecture de l’école', () => {
    const rows = projectTariffs([tariff()], [shown(intention({ kind: 'update', productKey: 'unknown-product' }), 'changing')]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.wanted).toBeNull();
  });
});

describe('intentions visibles et ordre par agrégat (#124)', () => {
  test('envoi, résultat suivi, confirmation puis relecture : la marque suit l’état réel', () => {
    const item = intention({ kind: 'update', productKey: 'lesson-45', operationId: 'op-7' });
    const sending = new Set(['op-7']), followed = new Set(['op-7']);
    expect(resolveIntentions([item], sending, new Set())).toEqual([{ intention: item, mark: 'saving' }]);
    expect(tariffMarkLabels.saving).toBe('Enregistrement en cours');
    expect(resolveIntentions([item], new Set(), followed)).toEqual([{ intention: item, mark: 'changing' }]);
    // Confirmée : les valeurs restent affichées sans marque jusqu'à la lecture suivante.
    const settled: TariffIntention = { ...item, settledAt: 1_000 };
    expect(resolveIntentions([settled], new Set(), new Set())).toEqual([{ intention: settled, mark: null }]);
    expect(resolveIntentions([settled], new Set(), new Set(), 1_001)).toEqual([]);
    // Refusée ou abandonnée : plus suivie, elle disparaît.
    expect(resolveIntentions([item], new Set(), new Set())).toEqual([]);
  });

  test('la portée nomme un produit, sauf création ou conditions partagées', () => {
    expect(tariffScope('lesson-45', false)).toBe('lesson-45');
    expect(tariffScope('lesson-45', true)).toBeNull();
    expect(tariffScope(null, false)).toBeNull();
    expect(tariffTag('lesson-45')).toBe('tariff:lesson-45');
    expect(tariffTag(null)).toBe('tariff:new');
    expect(termsScope(id(3))).toBe(id(3));
  });

  test('deux produits différents ne partagent pas de clé dans la projection', () => {
    const items = [intention({ kind: 'update', productKey: 'lesson-45' }), intention({ kind: 'update', productKey: 'exam-support' })];
    const rows = projectTariffs([tariff('lesson-45'), tariff('exam-support', { id: id(4) })], items.map(item => shown(item, 'changing')));
    expect(rows.map(row => row.key)).toEqual(['lesson-45', 'exam-support']);
    expect(rows.every(row => row.wanted !== null)).toBe(true);
    expect(new Set(rows.map(row => row.key)).size).toBe(2);
  });
});

describe('projection d’une révision de conditions communes (#124)', () => {
  const revision = (over: Partial<TermsIntention> = {}): TermsIntention => ({ tag: `terms:${id(3)}`, operationId: 'terms-op', termsVersionId: id(3), text: 'Nouveau texte.', ...over });

  test('« Révision en cours » puis « À confirmer » : le texte publié reste celui de l’école', () => {
    const item = revision();
    expect(projectTermsRevision(id(3), [item], new Set(['terms-op']), new Set())).toEqual({ mark: 'saving', text: 'Nouveau texte.' });
    expect(projectTermsRevision(id(3), [item], new Set(), new Set(['terms-op']))).toEqual({ mark: 'revising', text: 'Nouveau texte.' });
    expect(projectTermsRevision(id(3), [revision({ settledAt: 2_000 })], new Set(), new Set())).toEqual({ mark: null, text: 'Nouveau texte.' });
    expect(projectTermsRevision(id(3), [revision({ settledAt: 2_000 })], new Set(), new Set(), 2_001)).toBeNull();
  });

  test('un autre jeu de conditions, une demande refusée ou un jeu inconnu ne montrent rien', () => {
    expect(projectTermsRevision(id(4), [revision()], new Set(['terms-op']), new Set())).toBeNull();
    expect(projectTermsRevision(id(3), [revision()], new Set(), new Set())).toBeNull();
    expect(projectTermsRevision(id(3), [], new Set(), new Set())).toBeNull();
  });
});
