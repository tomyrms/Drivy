import { describe, expect, test } from 'vitest';
import { lessonsOfLearners } from '../client/agenda-model.js';
import { learnerFilterContext } from '../client/console/learners.js';

describe('répertoire partiel de l’agenda', () => {
  test('une recherche suspendue garde les leçons quand aucun nom n’est résolu', () => {
    const lessons = [{ learnerId: 'learner-1' }, { learnerId: 'learner-2' }];
    expect(lessonsOfLearners(lessons, [], '')).toEqual(lessons);
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
