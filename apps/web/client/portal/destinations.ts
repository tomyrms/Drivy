import type { NavigationQuery } from '../console/route';
import type { SectionKey } from '../console/sections';

/** Rebuilt navigation keeps the console's jobs and section keys; only destinations wired to a rebuilt page are shown. */
export type PortalWorkspaceKey = 'planning' | 'learners' | 'team' | 'formations' | 'settings';
export interface PortalNavItem { section: SectionKey; label: string; query?: NavigationQuery }
export interface PortalWorkspace { key: PortalWorkspaceKey; label: string; shortLabel: string; items: readonly PortalNavItem[] }

export const portalWorkspaces: readonly PortalWorkspace[] = [
  { key: 'planning', label: 'Planning', shortLabel: 'Planning', items: [
    { section: 'agenda', label: 'Agenda' }, { section: 'disponibilites', label: 'Disponibilités' }, { section: 'absences', label: 'Absences' },
  ] },
  { key: 'learners', label: 'Élèves', shortLabel: 'Élèves', items: [
    { section: 'eleves', label: 'Dossiers' }, { section: 'invitations', label: 'Invitations', query: { audience: 'learners' } }, { section: 'trajets', label: 'Trajets' },
  ] },
  { key: 'team', label: 'Équipe', shortLabel: 'Équipe', items: [
    { section: 'equipe', label: 'Membres et accès' }, { section: 'invitations', label: 'Invitations', query: { audience: 'team' } },
  ] },
  { key: 'formations', label: 'Formations et tarifs', shortLabel: 'Formations', items: [
    { section: 'formations', label: 'Formations' }, { section: 'prestations', label: 'Prestations sans permis' },
  ] },
  { key: 'settings', label: 'Réglages', shortLabel: 'Réglages', items: [
    { section: 'configuration', label: 'École' }, { section: 'confidentialite', label: 'Confidentialité' },
    { section: 'champs-profil', label: 'Informations élèves' }, { section: 'signalements', label: 'Signalements' },
    { section: 'apercu', label: 'Préparation', query: { from: 'configuration' } },
  ] },
];

/** Sections reached from a parent page (versioned records, references) keep the parent's workspace. */
const contextual: Partial<Record<SectionKey, SectionKey>> = { offres: 'formations', referentiels: 'formations', procedures: 'formations', conditions: 'prestations' };

export function availableWorkspaces(available: ReadonlySet<SectionKey>) {
  return portalWorkspaces.map(workspace => ({ ...workspace, items: workspace.items.filter(item => available.has(item.section)) }))
    .filter(workspace => workspace.items.length > 0);
}

export function isNavItemCurrent(item: PortalNavItem, section: SectionKey, query: NavigationQuery = {}) {
  const resolved = contextual[section] ?? section;
  if (item.section !== resolved) return false;
  return item.query?.audience === undefined || item.query.audience === (query.audience ?? 'learners');
}

export function currentWorkspace(workspaces: ReturnType<typeof availableWorkspaces>, section: SectionKey, query: NavigationQuery = {}) {
  return workspaces.find(workspace => workspace.items.some(item => isNavItemCurrent(item, section, query)));
}
