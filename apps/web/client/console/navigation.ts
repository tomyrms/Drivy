import type { SectionKey } from './sections.js';
import type { NavigationQuery } from './route.js';

export type WorkspaceKey = 'planning' | 'learners' | 'team' | 'formations' | 'settings';
export interface NavigationItem { section: SectionKey; label: string; query?: NavigationQuery }
export interface Workspace { key: WorkspaceKey; label: string; symbol: 'calendar' | 'users' | 'shield' | 'book' | 'settings'; home: SectionKey; items: readonly NavigationItem[] }

/** Navigation follows the administrator's jobs; versioned records remain contextual destinations. */
export const workspaces: readonly Workspace[] = [
  { key: 'planning', label: 'Planning', symbol: 'calendar', home: 'agenda', items: [
    { section: 'agenda', label: 'Agenda' }, { section: 'disponibilites', label: 'Disponibilités' }, { section: 'absences', label: 'Absences' },
  ] },
  { key: 'learners', label: 'Élèves', symbol: 'users', home: 'eleves', items: [
    { section: 'eleves', label: 'Dossiers' }, { section: 'invitations', label: 'Invitations', query: { audience: 'learners' } },
    { section: 'trajets', label: 'Trajets' },
  ] },
  { key: 'team', label: 'Équipe', symbol: 'shield', home: 'equipe', items: [
    { section: 'equipe', label: 'Membres et accès' }, { section: 'invitations', label: 'Invitations', query: { audience: 'team' } },
  ] },
  { key: 'formations', label: 'Formations et tarifs', symbol: 'book', home: 'formations', items: [
    { section: 'formations', label: 'Formations' }, { section: 'prestations', label: 'Prestations sans permis' },
  ] },
  { key: 'settings', label: 'Réglages', symbol: 'settings', home: 'configuration', items: [
    { section: 'configuration', label: 'École' }, { section: 'confidentialite', label: 'Confidentialité' },
    { section: 'champs-profil', label: 'Informations élèves' }, { section: 'signalements', label: 'Signalements' },
    { section: 'apercu', label: 'Préparation', query: { from: 'configuration' } },
  ] },
];

export const sectionTitles: Record<SectionKey, string> = {
  'tableau-de-bord': 'Tableau de bord', statistiques: 'Statistiques',
  agenda: 'Agenda', disponibilites: 'Disponibilités', absences: 'Absences', eleves: 'Élèves', invitations: 'Invitations',
  equipe: 'Équipe', trajets: 'Trajets', formations: 'Formations et tarifs', offres: 'Formations et tarifs',
  referentiels: 'Formations et tarifs', procedures: 'Formations et tarifs', prestations: 'Prestations sans permis',
  conditions: 'Conditions commerciales', configuration: 'École', confidentialite: 'Confidentialité', 'champs-profil': 'Informations des élèves',
  apercu: 'Préparation de l’école', signalements: 'Signalements',
};

export function workspaceFor(section: SectionKey, query: NavigationQuery = {}): Workspace {
  const key: WorkspaceKey = section === 'agenda' || section === 'disponibilites' || section === 'absences' ? 'planning'
    : section === 'equipe' || (section === 'invitations' && query.audience === 'team') ? 'team'
    : ['eleves', 'invitations', 'trajets'].includes(section) ? 'learners'
    : ['formations', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions'].includes(section) || (section === 'apercu' && (query.from === 'formations' || query.from === 'prestations')) ? 'formations'
    : 'settings';
  return workspaces.find(workspace => workspace.key === key)!;
}

export function isLocalItemCurrent(item: NavigationItem, section: SectionKey): boolean {
  if (item.section === section) return true;
  if (item.section === 'formations') return ['offres', 'referentiels', 'procedures', 'conditions', 'apercu'].includes(section);
  return false;
}

export function parentSection(section: SectionKey): SectionKey | null {
  if (section === 'offres' || section === 'referentiels' || section === 'procedures' || section === 'conditions' || section === 'prestations') return 'formations';
  return null;
}

/** Carry only the filters shared by sibling pages, never a selected object from the previous page. */
export function localNavigationQuery(workspace: Workspace, item: NavigationItem, query: NavigationQuery): NavigationQuery {
  if (workspace.key === 'planning') return {
    ...(query.instructor ? { instructor: query.instructor } : {}), ...(query.week ? { week: query.week } : {}),
    ...(query.day ? { day: query.day } : {}),
    ...(query.from === 'equipe' && item.section !== 'agenda' ? { from: 'equipe' as const } : {}), ...item.query,
  };
  return { ...item.query };
}
