import { sectionKeys, type SectionKey } from './sections.js';
import { settingTargets } from './settings-search-model.js';

/** Only navigation identifiers belong in URLs; never drafts, names, reports or tokens. */
export interface NavigationQuery {
  selection?: string | undefined;
  learner?: string | undefined;
  lesson?: string | undefined;
  course?: string | undefined;
  occurrence?: string | undefined;
  instructor?: string | undefined;
  category?: string | undefined;
  from?: SectionKey | undefined;
  audience?: 'learners' | 'team' | undefined;
  week?: string | undefined;
  day?: string | undefined;
  focus?: string | undefined;
  /** Rubrique d'une fiche de formation, ou assistant de création. */
  view?: FormationView | 'nouveau-cours' | undefined;
  /** Parcours (offering_key) d'un permis : identifiant technique, jamais un nom saisi. */
  programme?: string | undefined;
}
export const formationViews = ['general', 'competences', 'deroulement', 'tarifs', 'historique', 'nouvelle'] as const;
export type FormationView = typeof formationViews[number];
export interface ConsoleRoute { schoolId: string | null; section: SectionKey; query: NavigationQuery }
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sections: readonly string[] = sectionKeys;

export function readNavigationQuery(search: string): NavigationQuery {
  const params = new URLSearchParams(search), query: NavigationQuery = {};
  const focus = params.get('focus');
  if (focus && params.getAll('focus').length === 1 && settingTargets.includes(focus)) query.focus = focus;
  for (const key of ['selection', 'learner', 'lesson', 'instructor', 'course', 'occurrence'] as const) {
    const value = params.get(key);
    if (value && params.getAll(key).length === 1 && uuid.test(value)) query[key] = value.toLowerCase();
  }
  const category = params.get('category')?.trim();
  if (category && category.length <= 30 && !/[\u0000-\u001f\u007f]/.test(category) && params.getAll('category').length === 1) query.category = category;
  const from = params.get('from');
  if (from && sections.includes(from) && params.getAll('from').length === 1) query.from = from as SectionKey;
  const view = params.get('view');
  if (view && ((formationViews as readonly string[]).includes(view) || view === 'nouveau-cours') && params.getAll('view').length === 1) query.view = view as NavigationQuery['view'];
  const programme = params.get('programme');
  if (programme && programme.length <= 80 && !/[\u0000-\u001f\u007f]/.test(programme) && params.getAll('programme').length === 1) query.programme = programme;
  const audience = params.get('audience');
  if ((audience === 'learners' || audience === 'team') && params.getAll('audience').length === 1) query.audience = audience;
  for (const key of ['week', 'day'] as const) {
    const value = params.get(key);
    if (value && /^\d{4}-\d{2}-\d{2}$/.test(value) && params.getAll(key).length === 1) {
      const date = new Date(`${value}T12:00:00Z`);
      if (Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value) query[key] = value;
    }
  }
  return query;
}

export function parseConsoleRoute(pathname: string, search = ''): ConsoleRoute {
  if (!pathname.startsWith('/app/gestion/')) return { schoolId: null, section: 'apercu', query: {} };
  const [, , , schoolId, section] = pathname.replace(/\/$/, '').split('/');
  return { schoolId: schoolId && uuid.test(schoolId) ? schoolId.toLowerCase() : null,
    section: sections.includes(section ?? '') ? section as SectionKey : 'apercu', query: readNavigationQuery(search) };
}

export function consolePath(schoolId: string, section: SectionKey, query: NavigationQuery = {}): string {
  const raw = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) if (value) raw.set(key, value);
  const clean = new URLSearchParams(Object.entries(readNavigationQuery(raw.toString())));
  const suffix = clean.toString();
  return `/app/gestion/${schoolId}/${section}${suffix ? `?${suffix}` : ''}`;
}
