import { describe, expect, test } from 'vitest';
import { agendaSearchQuery, learnerFilterContext } from '../client/console-filter-model.js';

describe('recherche agenda et disponibilité du répertoire', () => {
  const search = 'Mina';
  test.each([
    ['ready avec données', { status: 'ready', data: { learners: [] } }, search],
    ['loading avec dernière lecture', { status: 'loading', data: { learners: [] } }, search],
    ['error avec dernière lecture', { status: 'error', data: { learners: [] } }, search],
    ['loading sans données', { status: 'loading', data: undefined }, ''],
    ['error sans données', { status: 'error', data: undefined }, ''],
  ] as const)('%s applique la règle de recherche', (_label, directory, expected) => {
    expect(agendaSearchQuery(directory, search)).toBe(expected);
  });
});

describe('vide filtré des élèves', () => {
  test('décrit les critères actifs sans créer de badge', () => {
    expect(learnerFilterContext({ search: 'Mina', statusFilter: 'active', readinessFilter: 'incomplete' })).toBe('Recherche « Mina » · profil à compléter');
  });
  test('ne décrit pas un filtre par défaut quand aucun critère n’est actif', () => {
    expect(learnerFilterContext({ search: '', statusFilter: 'active', readinessFilter: 'all' })).toBeNull();
  });
});
