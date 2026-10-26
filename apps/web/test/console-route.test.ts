import { describe, expect, test } from 'vitest';
import { consolePath, parseConsoleRoute, readNavigationQuery } from '../client/console/route.js';
import { isLocalItemCurrent, localNavigationQuery, parentSection, sectionTitles, workspaceFor, workspaces } from '../client/console/navigation.js';
import { sectionKeys } from '../client/console/sections.js';
import { resumableDraft } from '../client/console/draft-model.js';

const school = '11111111-1111-4111-8111-111111111111';
const learner = '22222222-2222-4222-8222-222222222222';
const instructor = '33333333-3333-4333-8333-333333333333';
const selectedLesson = '44444444-4444-4444-8444-444444444444';
const restore = (path: string) => { const url = new URL(path, 'https://school.example.test'); return parseConsoleRoute(url.pathname, url.search); };

describe('Navigation entre les tâches de gestion', () => {
  test('un dossier garde le retour à la semaine et au moniteur après relecture de son URL', () => {
    const query = { selection: learner, lesson: selectedLesson, from: 'agenda' as const, week: '2026-09-28', instructor };
    const dossier = restore(consolePath(school, 'eleves', query));
    expect(dossier).toEqual({ schoolId: school, section: 'eleves', query });
    const agenda = restore(consolePath(school, dossier.query.from!, { week: dossier.query.week, instructor: dossier.query.instructor, lesson: dossier.query.lesson }));
    expect(agenda).toEqual({ schoolId: school, section: 'agenda', query: { week: '2026-09-28', instructor, lesson: selectedLesson } });
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
    expect(readNavigationQuery(`lesson=${selectedLesson}&lesson=${learner}`)).toEqual({});
    expect(readNavigationQuery('lesson=Nom%20personnel')).toEqual({});
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

  test('les signalements ont leur URL et se rangent avec les réglages de l’école', () => {
    expect(consolePath(school, 'signalements')).toBe(`/app/gestion/${school}/signalements`);
    expect(restore(`/app/gestion/${school}/signalements`)).toEqual({ schoolId: school, section: 'signalements', query: {} });
    expect(restore(`/app/gestion/${school}/signalements/`).section).toBe('signalements');
    expect(workspaceFor('signalements').home).toBe('configuration');
    expect(workspaces.find(workspace => workspace.key === 'settings')?.items.map(item => item.section)).toEqual(['configuration', 'confidentialite', 'champs-profil', 'signalements', 'apercu']);
    expect(sectionTitles.signalements).toBe('Signalements');
    // Chaque rubrique du menu existe, et aucune n'est rangée deux fois dans le même espace.
    for (const workspace of workspaces) {
      const sections = workspace.items.map(item => `${item.section}/${item.query?.audience ?? ''}`);
      expect(new Set(sections).size).toBe(sections.length);
      for (const item of workspace.items) expect(sectionKeys).toContain(item.section);
    }
  });

  test('les pages séparées gardent leurs URL et leurs catégories au retour navigateur', () => {
    for (const section of ['disponibilites', 'absences', 'configuration', 'confidentialite'] as const) {
      expect(restore(consolePath(school, section)).section).toBe(section);
    }
    expect(workspaceFor('absences').home).toBe('agenda');
    expect(workspaceFor('confidentialite').home).toBe('configuration');
    expect(workspaceFor('agenda').items.map(item => item.section)).toEqual(['agenda', 'disponibilites', 'absences']);
    // Formations et tarifs : la fiche d'un permis regroupe le catalogue ; seules les prestations sans permis ont leur page.
    expect(workspaceFor('formations').items.map(item => item.section)).toEqual(['formations', 'prestations']);
    for (const legacy of ['offres', 'referentiels', 'procedures', 'conditions', 'prestations'] as const) {
      expect(parentSection(legacy)).toBe('formations');
      expect(workspaceFor(legacy).key).toBe('formations');
      expect(restore(consolePath(school, legacy, { selection: learner, category: 'B', from: 'formations' }))).toEqual({ schoolId: school, section: legacy, query: { selection: learner, category: 'B', from: 'formations' } });
    }
    expect(isLocalItemCurrent({ section: 'prestations', label: 'Prestations sans permis' }, 'conditions')).toBe(false);
    expect(isLocalItemCurrent({ section: 'formations', label: 'Formations' }, 'conditions')).toBe(true);
    expect(isLocalItemCurrent({ section: 'formations', label: 'Formations' }, 'referentiels')).toBe(true);
  });

  test('passer des horaires aux absences conserve le moniteur et le retour à son accès', () => {
    const planning = workspaceFor('disponibilites');
    const query = { instructor, week: '2026-09-28', from: 'equipe' as const, selection: learner, category: 'B' };
    const absences = localNavigationQuery(planning, planning.items.find(item => item.section === 'absences')!, query);
    expect(restore(consolePath(school, 'absences', absences)).query).toEqual({ instructor, week: '2026-09-28', from: 'equipe' });
    expect(localNavigationQuery(planning, planning.items[0]!, query)).toEqual({ instructor, week: '2026-09-28' });
  });

  test('les liens locaux gardent le permis ou le public, sans la sélection du dernier éditeur', () => {
    const formations = workspaceFor('formations');
    // Le menu ramène à la liste des permis ou aux prestations sans permis : ni le permis ouvert ni sa rubrique ne suivent.
    expect(localNavigationQuery(formations, formations.items[1]!, { category: 'B', view: 'tarifs', selection: learner, from: 'offres' })).toEqual({});
    expect(localNavigationQuery(formations, formations.items[0]!, { category: 'B', view: 'competences', programme: 'category-b' })).toEqual({});
    const team = workspaceFor('equipe');
    expect(localNavigationQuery(team, team.items[1]!, { audience: 'learners', selection: learner }))
      .toEqual({ audience: 'team' });
  });

  test('les rubriques d’une fiche ont une adresse propre, rechargeable et partageable', () => {
    const path = consolePath(school, 'formations', { category: 'A', view: 'competences', programme: 'formation-0f1' });
    expect(path).toBe(`/app/gestion/${school}/formations?category=A&view=competences&programme=formation-0f1`);
    expect(restore(path).query).toEqual({ category: 'A', view: 'competences', programme: 'formation-0f1' });
    for (const view of ['general', 'competences', 'deroulement', 'tarifs', 'historique', 'nouvelle']) expect(readNavigationQuery(`view=${view}`).view).toBe(view);
    expect(readNavigationQuery('view=offres')).toEqual({});
    expect(readNavigationQuery('view=tarifs&view=general')).toEqual({});
    expect(readNavigationQuery(`programme=${'x'.repeat(81)}`)).toEqual({});
    expect(readNavigationQuery('programme=a%00b')).toEqual({});
    expect(readNavigationQuery(`category=B&view=historique&selection=${learner.toUpperCase()}`)).toEqual({ category: 'B', view: 'historique', selection: learner });
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
