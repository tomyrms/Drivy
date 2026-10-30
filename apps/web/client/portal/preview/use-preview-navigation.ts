import { useCallback, useEffect, useRef, useState } from 'react';
import { readNavigationQuery, type NavigationQuery } from '../../console/route';
import type { SectionKey } from '../../console/sections';
import { portalSections } from '../pages';
import { ids } from './fixtures';

type Route = { page: SectionKey; query: NavigationQuery };
const destinations: readonly string[] = portalSections;
function readRoute(): Route {
  const params = new URLSearchParams(location.search), page = params.get('page');
  const query = readNavigationQuery(location.search);
  // Preserve the one-page link already handed to the owner.
  if (!page && !query.selection) query.selection = ids.instructor;
  return { page: page === 'preparation' ? 'apercu' : destinations.includes(page ?? '') ? page as SectionKey : 'equipe', query };
}
export function usePreviewNavigation() {
  const [route, setRoute] = useState(readRoute);
  const routeRef = useRef(route); routeRef.current = route;
  const [departure, setDeparture] = useState<{ proceed: () => void } | null>(null);
  const unsaved = useRef(new Set<string>());
  const guard = useRef<((proceed: () => void) => void) | null>(null);
  const index = useRef<number>(history.state?.drivyPreviewIndex ?? 0);
  const restoring = useRef(false), approved = useRef(false), bypass = useRef(false);
  const registerUnsavedChanges = useCallback((id: string) => { unsaved.current.add(id); return () => { unsaved.current.delete(id); }; }, []);
  const confirmNavigation = useCallback((proceed: () => void) => {
    if (bypass.current) proceed(); else if (guard.current) guard.current(proceed);
    else if (unsaved.current.size) setDeparture({ proceed }); else proceed();
  }, []);
  const go = useCallback((next: Route, replace = false) => {
    const params = new URLSearchParams({ page: next.page, ...Object.fromEntries(Object.entries(next.query).filter(([, value]) => value !== undefined)) });
    const url = `${location.pathname}?${params.toString()}`;
    if (replace) history.replaceState({ drivyPreviewIndex: index.current }, '', url);
    else { index.current++; history.pushState({ drivyPreviewIndex: index.current }, '', url); }
    setRoute(next); window.scrollTo({ top: 0, behavior: 'instant' });
  }, []);
  const navigate = useCallback((section: SectionKey, query: NavigationQuery = {}, options?: { replace?: boolean }) => {
    // Only implemented destinations are exposed by the pilot navigation.
    const page = section === 'apercu' && !destinations.includes('apercu') ? 'agenda' : section;
    if (!destinations.includes(page)) return;
    const apply = () => go({ page, query }, options?.replace);
    if (options?.replace) apply(); else confirmNavigation(apply);
  }, [go, confirmNavigation]);
  const setRouteQuery = useCallback((query: NavigationQuery, replace = false, keepForms = false) => {
    const apply = () => go({ page: routeRef.current.page, query }, replace);
    if (replace || keepForms) apply(); else confirmNavigation(apply);
  }, [go, confirmNavigation]);
  useEffect(() => {
    history.replaceState({ drivyPreviewIndex: index.current }, '', location.href);
    const pop = (event: PopStateEvent) => {
      if (restoring.current) { restoring.current = false; return; }
      const nextIndex = typeof event.state?.drivyPreviewIndex === 'number' ? event.state.drivyPreviewIndex : 0;
      const delta = nextIndex - index.current;
      if (!approved.current && delta && (guard.current || unsaved.current.size)) {
        restoring.current = true; history.go(-delta);
        confirmNavigation(() => { approved.current = true; history.go(delta); }); return;
      }
      approved.current = false; index.current = nextIndex; setRoute(readRoute());
    };
    const unload = (event: BeforeUnloadEvent) => { if (unsaved.current.size) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('popstate', pop); window.addEventListener('beforeunload', unload);
    return () => { window.removeEventListener('popstate', pop); window.removeEventListener('beforeunload', unload); };
  }, [confirmNavigation]);
  const leave = () => { const next = departure; setDeparture(null); unsaved.current.clear(); bypass.current = true; try { next?.proceed(); } finally { bypass.current = false; } };
  return { route, navigate, setRouteQuery, registerUnsavedChanges, confirmNavigation, departure, leave,
    cancelDeparture: () => setDeparture(null), setNavigationGuard: (next: ((proceed: () => void) => void) | null) => { guard.current = next; } };
}
