import type { NavigationQuery } from '../console/route';
import type { SectionKey } from '../console/sections';

/** Rebuilt navigation keeps the console's jobs and section keys; only destinations wired to a rebuilt page are shown. */
export type PortalWorkspaceKey = 'pilotage' | 'planning' | 'learners' | 'team' | 'formations' | 'settings';
export interface PortalNavItem { section: SectionKey; label: string; query?: NavigationQuery }
export interface PortalWorkspace { key: PortalWorkspaceKey; label: string; shortLabel: string; items: readonly PortalNavItem[] }

export const portalWorkspaces: readonly PortalWorkspace[] = [
  // Pilotage (#373) : un seul espace pour deux destinations, afin que la barre mobile garde six entrées lisibles.
  { key: 'pilotage', label: 'Pilotage', shortLabel: 'Pilotage', items: [
    { section: 'tableau-de-bord', label: 'Tableau de bord' }, { section: 'statistiques', label: 'Statistiques' },
  ] },
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

/** A formation preparation started from Formations or Prestations keeps that workspace; school preparation stays in Réglages. */
const cataloguePreparation = (section: SectionKey, query: NavigationQuery): SectionKey | null =>
  section === 'apercu' && (query.from === 'formations' || query.from === 'prestations') ? query.from : null;

export function availableWorkspaces(available: ReadonlySet<SectionKey>) {
  return portalWorkspaces.map(workspace => ({ ...workspace, items: workspace.items.filter(item => available.has(item.section)) }))
    .filter(workspace => workspace.items.length > 0);
}

export function isNavItemCurrent(item: PortalNavItem, section: SectionKey, query: NavigationQuery = {}) {
  const resolved = cataloguePreparation(section, query) ?? contextual[section] ?? section;
  if (item.section !== resolved) return false;
  return item.query?.audience === undefined || item.query.audience === (query.audience ?? 'learners');
}

/** The item's own page is displayed. A parent item kept current for a versioned record still opens its list. */
export function isActiveDestination(item: PortalNavItem, section: SectionKey, query: NavigationQuery = {}) {
  return item.section === section && (item.query?.audience === undefined || item.query.audience === (query.audience ?? 'learners'));
}

/**
 * Query carried when a local destination is opened. Planning shares its monitor and displayed period;
 * Pilotage only shares the monitor; other spaces only keep their own public. A selection from another page never follows the change.
 */
export function navigationQueryFor(workspace: PortalWorkspace, item: PortalNavItem, query: NavigationQuery = {}): NavigationQuery {
  if (workspace.key === 'pilotage') return { ...(query.instructor ? { instructor: query.instructor } : {}), ...item.query };
  if (workspace.key === 'planning') return {
    ...(query.instructor ? { instructor: query.instructor } : {}),
    ...(query.week ? { week: query.week } : {}),
    ...(query.day ? { day: query.day } : {}),
    ...(query.from === 'equipe' && item.section !== 'agenda' ? { from: 'equipe' as const } : {}),
    ...item.query,
  };
  return { ...item.query };
}

export function currentWorkspace(workspaces: ReturnType<typeof availableWorkspaces>, section: SectionKey, query: NavigationQuery = {}) {
  return workspaces.find(workspace => workspace.items.some(item => isNavItemCurrent(item, section, query)));
}
