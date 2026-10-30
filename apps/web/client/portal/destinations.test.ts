import { describe, expect, test } from 'vitest';
import { sectionKeys } from '../console/sections.js';
import { availableWorkspaces, currentWorkspace, isActiveDestination, isNavItemCurrent, navigationQueryFor, portalWorkspaces } from './destinations.js';

const all = new Set(sectionKeys);
const spaces = availableWorkspaces(all);
const current = (section: (typeof sectionKeys)[number], query = {}) => {
  const workspace = currentWorkspace(spaces, section, query);
  return { workspace: workspace?.key, item: workspace?.items.find(item => isNavItemCurrent(item, section, query))?.section };
};
const itemsOf = (key: (typeof portalWorkspaces)[number]['key']) => spaces.find(workspace => workspace.key === key)!.items;

describe('espaces du portail reconstruit', () => {
  test('chaque section enregistrée garde un espace et une rubrique courante', () => {
    for (const section of sectionKeys) {
      const resolved = current(section);
      expect(resolved.workspace, section).toBeDefined();
      expect(resolved.item, section).toBeDefined();
    }
    expect(spaces.map(workspace => workspace.key)).toEqual(['planning', 'learners', 'team', 'formations', 'settings']);
  });

  test('les invitations restent dans l’espace de leur public', () => {
    expect(current('invitations', { audience: 'team' })).toEqual({ workspace: 'team', item: 'invitations' });
    expect(current('invitations')).toEqual({ workspace: 'learners', item: 'invitations' });
    expect(current('invitations', { audience: 'learners' })).toEqual({ workspace: 'learners', item: 'invitations' });
  });

  test('un enregistrement versionné garde l’espace de sa page porteuse', () => {
    for (const section of ['offres', 'referentiels', 'procedures'] as const) {
      expect(current(section), section).toEqual({ workspace: 'formations', item: 'formations' });
    }
    // Les conditions commerciales restent rattachées aux prestations sans permis,
    // mais cette page parente ne doit jamais devenir un onglet inerte.
    expect(current('conditions')).toEqual({ workspace: 'formations', item: 'prestations' });
    const prestations = itemsOf('formations').find(item => item.section === 'prestations')!;
    expect(isNavItemCurrent(prestations, 'conditions')).toBe(true);
    expect(isActiveDestination(prestations, 'conditions')).toBe(false);
    expect(isActiveDestination(prestations, 'prestations')).toBe(true);
  });

  test('un onglet dont la page est affichée ne se rejoue pas, un onglet parent reste navigable', () => {
    const team = itemsOf('team');
    const invitation = team.find(item => item.section === 'invitations')!;
    expect(isActiveDestination(invitation, 'invitations', { audience: 'team' })).toBe(true);
    expect(isActiveDestination(invitation, 'invitations', { audience: 'learners' })).toBe(false);
    const agenda = itemsOf('planning').find(item => item.section === 'agenda')!;
    expect(isActiveDestination(agenda, 'agenda')).toBe(true);
  });

  test('la préparation d’une formation reste dans Formations et tarifs', () => {
    expect(current('apercu', { from: 'formations' })).toEqual({ workspace: 'formations', item: 'formations' });
    expect(current('apercu', { from: 'prestations' })).toEqual({ workspace: 'formations', item: 'prestations' });
    // Depuis Réglages, la préparation de l’école reste une rubrique de Réglages.
    expect(current('apercu', { from: 'configuration' })).toEqual({ workspace: 'settings', item: 'apercu' });
    expect(current('apercu')).toEqual({ workspace: 'settings', item: 'apercu' });
  });

  test('le planning garde le moniteur, la semaine et le retour au membre en changeant de rubrique', () => {
    const planning = spaces.find(workspace => workspace.key === 'planning')!;
    const agenda = planning.items.find(item => item.section === 'agenda')!;
    const hours = planning.items.find(item => item.section === 'disponibilites')!;
    const absences = planning.items.find(item => item.section === 'absences')!;
    const instructor = '33333333-3333-4333-8333-333333333333';
    const query = { instructor, week: '2026-09-28', day: '2026-09-29', from: 'equipe' as const, selection: '22222222-2222-4222-8222-222222222222' };
    expect(navigationQueryFor(planning, hours, query)).toEqual({ instructor, week: '2026-09-28', day: '2026-09-29', from: 'equipe' });
    expect(navigationQueryFor(planning, absences, query)).toEqual({ instructor, week: '2026-09-28', day: '2026-09-29', from: 'equipe' });
    // L'agenda n'a pas de « retour au membre » : le contexte de la fiche n'y est pas rattaché.
    expect(navigationQueryFor(planning, agenda, query)).toEqual({ instructor, week: '2026-09-28', day: '2026-09-29' });
    // Aucun identifiant d'une autre page ne suit le changement d'espace.
    const learners = spaces.find(workspace => workspace.key === 'learners')!;
    expect(navigationQueryFor(learners, learners.items[0]!, query)).toEqual({});
    expect(navigationQueryFor(planning, hours, { selection: query.selection })).toEqual({});
    const team = spaces.find(workspace => workspace.key === 'team')!;
    expect(navigationQueryFor(team, team.items[1]!, { instructor, audience: 'learners' })).toEqual({ audience: 'team' });
  });

  test('seules les destinations enregistrées composent la navigation', () => {
    const partial = availableWorkspaces(new Set(['agenda', 'eleves', 'invitations'] as const));
    // Invitations existe dans deux espaces : chacun ne garde que son public.
    expect(partial.map(workspace => workspace.key)).toEqual(['planning', 'learners', 'team']);
    expect(partial.flatMap(workspace => workspace.items.map(item => `${item.section}/${item.query?.audience ?? ''}`)))
      .toEqual(['agenda/', 'eleves/', 'invitations/learners', 'invitations/team']);
  });
});
