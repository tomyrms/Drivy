import { expect, test } from 'vitest';
import { nextActionDestination } from './first-lesson-actions';

const learner = '31100000-0000-4000-8000-000000000010';
test('la prochaine leçon ouvre le planificateur avec l’élève annoncé par le serveur', () => {
  expect(nextActionDestination({ code: 'PLAN_FIRST_LESSON', label: 'Planifier', section: 'eleves', query: { selection: learner } }))
    .toEqual({ section: 'agenda', query: { view: 'nouvelle', learner } });
});
test('la préparation revient au guide, sans redirection circulaire vers le planning', () => {
  expect(nextActionDestination({ code: 'SCHOOL_NOT_ACTIVE', label: 'Préparer', section: 'apercu' }))
    .toEqual({ section: 'apercu', query: { from: 'configuration' } });
});
test('une invitation élève conserve son audience et aucun paramètre de navigation arbitraire', () => {
  expect(nextActionDestination({ code: 'FIRST_LEARNER_REQUIRED', label: 'Inviter', section: 'invitations', query: { audience: 'learners', token: 'never-forward' } }))
    .toEqual({ section: 'invitations', query: { audience: 'learners' } });
});
