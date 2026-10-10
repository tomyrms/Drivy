import type { SectionKey } from './sections.js';
import type { NavigationQuery } from './route.js';

export type WorkspaceKey = 'planning' | 'learners' | 'team' | 'formations' | 'settings';
export interface NavigationItem { section: SectionKey; label: string; query?: NavigationQuery }
export interface Workspace { key: WorkspaceKey; label: string; symbol: 'calendar' | 'users' | 'shield' | 'book' | 'settings'; home: SectionKey; items: readonly NavigationItem[] }

/** Navigation follows the administrator's jobs; versioned records remain contextual destinations. */
export const workspaces: readonly Workspace[] = [
  { key: 'planning', label: 'Planning', symbol: 'calendar', home: 'agenda', items: [
    { section: 'agenda', label: 'Agenda' }, { section: 'disponibilites', label: 'Disponibilités et absences' },
  ] },
  { key: 'learners', label: 'Élèves', symbol: 'users', home: 'eleves', items: [
    { section: 'eleves', label: 'Dossiers' }, { section: 'invitations', label: 'Invitations', query: { audience: 'learners' } },
    { section: 'trajets', label: 'Trajets' },
  ] },
  { key: 'team', label: 'Équipe', symbol: 'shield', home: 'equipe', items: [
    { section: 'equipe', label: 'Membres et accès' }, { section: 'invitations', label: 'Invitations', query: { audience: 'team' } },
  ] },
  { key: 'formations', label: 'Formations et tarifs', symbol: 'book', home: 'formations', items: [
    { section: 'formations', label: 'Formations' }, { section: 'prestations', label: 'Tarifs' },
  ] },
  { key: 'settings', label: 'Réglages', symbol: 'settings', home: 'configuration', items: [
    { section: 'configuration', label: 'École' }, { section: 'champs-profil', label: 'Informations élèves' },
    { section: 'apercu', label: 'Préparation' },
  ] },
];

export const sectionTitles: Record<SectionKey, string> = {
  agenda: 'Agenda', disponibilites: 'Disponibilités et absences', eleves: 'Élèves', invitations: 'Invitations',
  equipe: 'Équipe', trajets: 'Trajets', formations: 'Formations et tarifs', offres: 'Formations proposées',
  referentiels: 'Compétences enseignées', procedures: 'Déroulement et annulation', prestations: 'Tarifs',
  conditions: 'Conditions commerciales', configuration: 'Réglages', 'champs-profil': 'Informations des élèves',
  apercu: 'Préparation de l’école',
};

export function workspaceFor(section: SectionKey, query: NavigationQuery = {}): Workspace {
  const key: WorkspaceKey = section === 'agenda' || section === 'disponibilites' ? 'planning'
    : section === 'equipe' || (section === 'invitations' && query.audience === 'team') ? 'team'
    : ['eleves', 'invitations', 'trajets'].includes(section) ? 'learners'
    : ['formations', 'offres', 'referentiels', 'procedures', 'prestations', 'conditions'].includes(section) ? 'formations'
    : 'settings';
  return workspaces.find(workspace => workspace.key === key)!;
}

export function isLocalItemCurrent(item: NavigationItem, section: SectionKey): boolean {
  if (item.section === section) return true;
  if (item.section === 'formations') return ['offres', 'referentiels', 'procedures'].includes(section);
  return item.section === 'prestations' && section === 'conditions';
}

export function parentSection(section: SectionKey): SectionKey | null {
  if (section === 'offres' || section === 'referentiels' || section === 'procedures') return 'formations';
  if (section === 'conditions') return 'prestations';
  return null;
}
