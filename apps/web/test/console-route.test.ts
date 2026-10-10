import { describe, expect, test } from 'vitest';
import { consolePath, parseConsoleRoute, readNavigationQuery } from '../client/console/route.js';
import { workspaceFor } from '../client/console/navigation.js';
import { resumableDraft } from '../client/console/draft-model.js';

const school = '11111111-1111-4111-8111-111111111111';
const learner = '22222222-2222-4222-8222-222222222222';
const instructor = '33333333-3333-4333-8333-333333333333';
const restore = (path: string) => { const url = new URL(path, 'https://school.example.test'); return parseConsoleRoute(url.pathname, url.search); };

describe('Navigation entre les tâches de gestion', () => {
  test('un dossier garde le retour à la semaine et au moniteur après relecture de son URL', () => {
    const query = { selection: learner, from: 'agenda' as const, week: '2026-09-28', instructor };
    const dossier = restore(consolePath(school, 'eleves', query));
    expect(dossier).toEqual({ schoolId: school, section: 'eleves', query });
    const agenda = restore(consolePath(school, dossier.query.from!, { week: dossier.query.week, instructor: dossier.query.instructor }));
    expect(agenda).toEqual({ schoolId: school, section: 'agenda', query: { week: '2026-09-28', instructor } });
  });

  test('le contexte de formation et sa version sélectionnée survivent à une URL copiée', () => {
    expect(restore(consolePath(school, 'referentiels', { category: ' B ', selection: learner, from: 'formations' })).query)
      .toEqual({ category: 'B', selection: learner, from: 'formations' });
  });

  test('la préparation a une URL explicite distincte de l’entrée quotidienne', () => {
    expect(consolePath(school, 'apercu')).toBe(`/app/gestion/${school}/apercu`);
    expect(restore(`/app/gestion/${school}/offres`).section).toBe('offres');
    expect(restore(`/app/gestion/${school}/referentiels`).section).toBe('referentiels');
  });

  test('les paramètres ambigus ou étrangers ne deviennent pas du contexte de navigation', () => {
    expect(readNavigationQuery(`?selection=${learner}&selection=${instructor}&instructor=invalid&week=2026-02-30&category=B%00&from=https://example.test&audience=all&token=secret&draft=content`)).toEqual({});
    expect(readNavigationQuery('?week=2026-09-28&week=2026-10-05&category=A&category=B')).toEqual({});
    expect(parseConsoleRoute(`/other/gestion/${school}/eleves`).schoolId).toBeNull();
    expect(parseConsoleRoute('/app/gestion/not-an-id/eleves').schoolId).toBeNull();
  });

  test('la construction du chemin n’emporte ni saisie ni paramètre non autorisé', () => {
    const query = { learner, selection: undefined, draft: 'note privée', token: 'secret', name: 'Nom élève' };
    expect(consolePath(school, 'trajets', query)).toBe(`/app/gestion/${school}/trajets?learner=${learner}`);
  });

  test('les invitations élèves et personnel restent dans leur espace respectif', () => {
    expect(workspaceFor('invitations', { audience: 'learners' }).home).toBe('eleves');
    expect(workspaceFor('invitations', { audience: 'team' }).home).toBe('equipe');
    expect(workspaceFor('conditions').home).toBe('formations');
    expect(workspaceFor('apercu').home).toBe('configuration');
  });

  test('un lien vers un tarif précis ne rouvre pas le brouillon précédent', () => {
    const unsent = { categoryCode: 'B', price: '95' };
    expect(resumableDraft(unsent, { selection: learner, category: 'A' })).toBeNull();
    expect(resumableDraft(unsent, { selection: learner, category: 'B' })).toBeNull();
    expect(resumableDraft(unsent, { category: 'A' })).toBeNull();
    expect(resumableDraft(unsent, { category: 'B', from: 'conditions' })).toBe(unsent);
    expect(resumableDraft(null)).toBeNull();
  });
});
