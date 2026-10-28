import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { commandStore, useCommandSnapshot } from '../command-store';
import { ScopedReadCache } from './load-model';
import { endSession, meSchema, request, RequestFailure, sessionSchema } from '../protocol';
import type { Me, Member, Session } from '../protocol';
import { readSchool, schoolSchema, type School } from '../school-api';
import { readError, sectionKeys, type ConsoleContextValue, type SectionKey } from './context';
import { sectionTitles } from './navigation';
import { consolePath, parseConsoleRoute, type NavigationQuery } from './route';
import { ConsoleAccessReader, sameConsoleAccess } from './access-reader';

/*
 * Session, school access, history guards and command scope of the management console, without presentation.
 * The historical console and the rebuilt portal render the same runtime; only one is mounted at a time.
 */
export type ManagementState =
  | { status: 'loading' }
  | { status: 'signin' }
  | { status: 'error'; message: string }
  | { status: 'choose'; me: Me; admin: Member[] }
  | { status: 'denied'; me: Me; membership: Member | null }
  | { status: 'ready'; me: Me; membership: Member; school: School };

export function useManagementConsole() {
  const [route, setRoute] = useState(() => parseConsoleRoute(window.location.pathname, window.location.search));
  const [state, setState] = useState<ManagementState>({ status: 'loading' });
  const stateRef = useRef(state); stateRef.current = state;
  const [resumeGate, setResumeGate] = useState<'checking' | 'error' | null>(null);
  const resumeGeneration = useRef(0);
  const [session, setSession] = useState<Session | null>(null);
  const [busy, setBusy] = useState(false);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const [logoutWarning, setLogoutWarning] = useState(false);
  const [identityDialog, setIdentityDialog] = useState<{ mode: 'confirm' | 'login'; email: string } | null>(null);
  const identityResult = useRef<((confirmed: boolean) => void) | null>(null);
  const currentSession = useRef(session); currentSession.current = session;
  const [navigationOpen, setNavigationOpen] = useState(false);
  const navigationButton = useRef<HTMLButtonElement>(null);
  const csrf = useRef('');
  const navigationGuard = useRef<((proceed: () => void) => void) | null>(null);
  const unsaved = useRef(new Set<string>());
  const bypassGuard = useRef(false);
  const [departure, setDeparture] = useState<{ proceed: () => void } | null>(null);
  const proceedNavigation = (proceed: () => void) => {
    if (bypassGuard.current) proceed();
    else if (navigationGuard.current) navigationGuard.current(proceed);
    else if (unsaved.current.size) setDeparture({ proceed });
    else proceed();
  };
  const historyIndex = useRef<number>(window.history.state?.drivyIndex ?? 0);
  const restoringHistory = useRef(false), approvedHistory = useRef(false);
  const pushPath = (path: string) => {
    historyIndex.current++;
    window.history.pushState({ drivyIndex: historyIndex.current }, '', path);
  };
  const registerUnsavedChanges = useCallback((id: string) => {
    unsaved.current.add(id); return () => { unsaved.current.delete(id); };
  }, []);
  const generation = useRef(0);
  const accessReader = useRef(new ConsoleAccessReader(() => request('me', meSchema).then(result => result.data), schoolId => readSchool(schoolId, '', schoolSchema)));
  const snapshot = useCommandSnapshot();
  const draftScope = state.status === 'ready'
    ? `${state.me.personId}/${state.membership.schoolId}/${state.membership.membershipId}/${state.membership.accessEpoch}` : null;
  const drafts = useMemo(() => new Map<string, unknown>(), [draftScope]);
  const readCache = useMemo(() => new ScopedReadCache(), [draftScope]);
  useEffect(() => () => readCache.invalidate(), [readCache]);
  useEffect(() => () => { identityResult.current?.(false); identityResult.current = null; setIdentityDialog(null); }, [draftScope]);

  const acceptPerson = useCallback((me: Me): boolean => {
    const changed = commandStore.scopeToPerson(me.personId);
    if (changed) {
      unsaved.current.clear(); navigationGuard.current = null; setDeparture(null);
      identityResult.current?.(false); identityResult.current = null; setIdentityDialog(null);
    }
    return changed;
  }, []);

  const load = useCallback(async (schoolId: string | null, restored = false) => {
    resumeGeneration.current++;
    setResumeGate(null);
    const current = ++generation.current;
    accessReader.current.invalidate();
    setState({ status: 'loading' });
    try {
      const next = await request('session', sessionSchema);
      if (current !== generation.current) return;
      // This lock tracks logout only, not the durable command store. A fresh session read settles a restored departure.
      if (restored) { working.current = false; setBusy(false); }
      csrf.current = next.csrfToken; setSession(next);
      if (!next.authenticated) { setState({ status: 'signin' }); return; }
      const me = (await request('me', meSchema)).data;
      if (current !== generation.current) return;
      acceptPerson(me);
      const admin = me.memberships.filter(member => member.roles.includes('ADMIN'));
      const target = schoolId ?? (admin.length === 1 ? admin[0]!.schoolId : null);
      if (!target) { setState(admin.length ? { status: 'choose', me, admin } : { status: 'denied', me, membership: null }); return; }
      const membership = me.memberships.find(member => member.schoolId.toLowerCase() === target.toLowerCase());
      if (!membership?.roles.includes('ADMIN')) { setState({ status: 'denied', me, membership: membership ?? null }); return; }
      commandStore.scopeToAccess(membership.schoolId, membership.membershipId, membership.accessEpoch);
      const school = await readSchool(membership.schoolId, '', schoolSchema);
      if (current !== generation.current) return;
      if (school.id !== membership.schoolId) throw new RequestFailure('INVALID_RESPONSE');
      const currentRoute = parseConsoleRoute(window.location.pathname, window.location.search);
      const explicitSection = (sectionKeys as readonly string[]).includes(window.location.pathname.replace(/\/$/, '').split('/')[4] ?? '');
      const section = explicitSection ? currentRoute.section : school.status === 'ACTIVE' ? 'agenda' : 'apercu';
      window.history.replaceState({ drivyIndex: historyIndex.current }, '', consolePath(membership.schoolId, section, currentRoute.query));
      setRoute({ ...currentRoute, schoolId: membership.schoolId, section });
      setState({ status: 'ready', me, membership, school });
    } catch (error) {
      if (current !== generation.current) return;
      if (error instanceof RequestFailure && error.status === 401) { setState({ status: 'signin' }); return; }
      setState({ status: 'error', message: readError(error) });
    }
  }, [acceptPerson]);

  /** A restored document is not proof of current rights. Keep forms mounted only while the same access is revalidated. */
  const resumeAccess = useCallback(async () => {
    const previous = stateRef.current;
    if (previous.status !== 'ready') { await load(parseConsoleRoute(window.location.pathname, window.location.search).schoolId, true); return; }
    const attempt = ++resumeGeneration.current;
    const scope = generation.current;
    setResumeGate('checking'); setNavigationOpen(false);
    try {
      const next = await request('session', sessionSchema);
      const access = next.authenticated ? await accessReader.current.read(previous.membership.schoolId) : { status: 'signin' as const };
      if (attempt !== resumeGeneration.current) return;
      if (scope !== generation.current) { setResumeGate('error'); return; }
      if (!access || access.status === 'unavailable') { setResumeGate('error'); return; }
      const retained = sameConsoleAccess(previous, access);
      csrf.current = next.csrfToken; setSession(next);
      working.current = false; setBusy(false);
      if ('me' in access) acceptPerson(access.me);
      if (access.status === 'ready') commandStore.scopeToAccess(access.membership.schoolId, access.membership.membershipId, access.membership.accessEpoch);
      if (!retained) {
        generation.current++;
        unsaved.current.clear(); navigationGuard.current = null; setDeparture(null); setLogoutWarning(false);
        identityResult.current?.(false); identityResult.current = null; setIdentityDialog(null);
      }
      setState(access); setResumeGate(null);
    } catch {
      if (attempt === resumeGeneration.current && scope === generation.current) setResumeGate('error');
    }
  }, [load, acceptPerson]);
  const resumeCurrentAccess = useRef(resumeAccess); resumeCurrentAccess.current = resumeAccess;

  useEffect(() => { void load(route.schoolId); }, [route.schoolId]);
  useEffect(() => {
    window.history.replaceState({ drivyIndex: historyIndex.current }, '', window.location.href);
    const onPopState = (event: PopStateEvent) => {
      if (restoringHistory.current) { restoringHistory.current = false; return; }
      const targetIndex = typeof event.state?.drivyIndex === 'number' ? event.state.drivyIndex : 0;
      const delta = targetIndex - historyIndex.current;
      if (!approvedHistory.current && delta && (navigationGuard.current || unsaved.current.size)) {
        // Restore the actual history position before asking. Cancel must not overwrite the preceding URL.
        restoringHistory.current = true; window.history.go(-delta);
        proceedNavigation(() => { approvedHistory.current = true; window.history.go(delta); });
        return;
      }
      approvedHistory.current = false; historyIndex.current = targetIndex;
      setRoute(parseConsoleRoute(window.location.pathname, window.location.search)); setNavigationOpen(false);
    };
    const onBeforeUnload = (event: BeforeUnloadEvent) => { if (unsaved.current.size) { event.preventDefault(); event.returnValue = ''; } };
    const onPageShow = (event: PageTransitionEvent) => {
      if (!event.persisted) return;
      void resumeCurrentAccess.current();
    };
    window.addEventListener('popstate', onPopState);
    window.addEventListener('pageshow', onPageShow);
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => { generation.current++; resumeGeneration.current++; accessReader.current.invalidate(); window.removeEventListener('popstate', onPopState); window.removeEventListener('pageshow', onPageShow); window.removeEventListener('beforeunload', onBeforeUnload); };
  }, []);
  // A new section opens at its top, not at the scroll position of the one that was left (selections and filters keep theirs).
  const shownSection = useRef<string | null>(null);
  useEffect(() => {
    const key = state.status === 'ready' ? `${route.schoolId}/${route.section}` : null;
    if (key !== null && shownSection.current !== null && shownSection.current !== key) window.scrollTo({ top: 0, behavior: 'instant' });
    if (key !== null) shownSection.current = key;
  }, [route.schoolId, route.section, state.status]);
  useEffect(() => {
    const school = state.status === 'ready' ? state.school.name : null;
    document.title = `${sectionTitles[route.section]}${school ? ` · ${school}` : ''} · Gestion Drivy`;
  }, [route.section, state]);

  // Guards live in refs: `context.login` is memoised and must never read a stale `busy`.
  const working = useRef(false);

  function confirmIdentity(): Promise<boolean> {
    if (working.current || identityResult.current) return Promise.resolve(false);
    return new Promise(resolve => {
      identityResult.current = resolve;
      setIdentityDialog({ mode: 'confirm', email: currentSession.current?.user?.email ?? '' });
    });
  }
  function finishIdentity(confirmed: boolean) {
    const resolve = identityResult.current; identityResult.current = null;
    setIdentityDialog(null); resolve?.(confirmed);
  }
  async function confirmedIdentity(next: Session) {
    if (identityDialog?.mode === 'login') {
      finishIdentity(false);
      await load(route.schoolId);
      return;
    }
    if (state.status !== 'ready') { finishIdentity(false); return; }
    const scope = generation.current;
    const access = await accessReader.current.read(state.membership.schoolId);
    if (scope !== generation.current) return;
    if (!access) throw new RequestFailure('API_UNAVAILABLE');
    const retained = sameConsoleAccess(state, access);
    if ('me' in access) acceptPerson(access.me);
    if (!retained) generation.current++;
    csrf.current = next.csrfToken; setSession(access.status === 'signin' ? null : next);
    if (access.status === 'unavailable') setState({ status: 'error', message: readError(access.error) });
    else setState(access);
    finishIdentity(retained);
  }
  function login(options?: { reauthenticate?: boolean }) {
    if (options?.reauthenticate) { void confirmIdentity(); return; }
    if (!working.current) setIdentityDialog({ mode: 'login', email: currentSession.current?.user?.email ?? '' });
  }

  /** Signing out forgets the followed requests: with one still unsettled, ask first. */
  function requestLogout() {
    if (working.current || !session) return;
    if (commandStore.getSnapshot().entries.size > 0) setLogoutWarning(true); else void logout();
  }

  async function logout() {
    if (working.current || !session) return;
    working.current = true;
    setBusy(true); setLogoutError(null);
    try {
      await endSession();
      commandStore.clear();
      unsaved.current.clear();
      window.location.assign('/app/');
    } catch (error) { working.current = false; setLogoutError(readError(error)); setBusy(false); }
  }

  const context = useMemo<ConsoleContextValue | null>(() => {
    if (state.status !== 'ready') return null;
    const scope = generation.current;
    return {
    schoolId: state.membership.schoolId, me: state.me, membership: state.membership, school: state.school,
    canConfigureCatalog: state.membership.grants.includes('CONFIGURE_CATALOG'),
    drafts,
    readCache,
    registerUnsavedChanges,
    confirmNavigation: proceedNavigation,
    setNavigationGuard: guard => { navigationGuard.current = guard; },
    reloadSchool: async () => {
      if (scope !== generation.current) return;
      const access = await accessReader.current.read(state.membership.schoolId);
      if (!access || scope !== generation.current) return;
      if ('me' in access && acceptPerson(access.me)) generation.current++;
      if (access.status === 'unavailable') setState({ status: 'error', message: readError(access.error) });
      else {
        if (access.status === 'ready') commandStore.scopeToAccess(access.membership.schoolId, access.membership.membershipId, access.membership.accessEpoch);
        setState(access);
      }
      if (access.status === 'signin') setSession(null);
    },
    csrf: () => csrf.current,
    refreshCsrf: async () => { const next = await request('session', sessionSchema); csrf.current = next.csrfToken; return next.csrfToken; },
    routeQuery: route.query,
    setRouteQuery: (query: NavigationQuery, replace = false, keepForms = false) => {
      const path = consolePath(state.membership.schoolId, route.section, query);
      if (`${window.location.pathname}${window.location.search}` === path) return;
      const apply = () => {
        if (replace) window.history.replaceState({ drivyIndex: historyIndex.current }, '', path); else pushPath(path);
        setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
      };
      // keepForms : la section reste montée et garde ses saisies (rubriques d'une même fiche) ; aucune perte, donc aucune question.
      if (replace || keepForms) apply(); else proceedNavigation(apply);
    },
    navigate: (section: SectionKey, query: NavigationQuery = {}, options: { replace?: boolean } = {}) => {
      // Redirection d'une ancienne adresse : elle remplace l'entrée d'historique, sans saisie à protéger.
      if (options.replace) {
        window.history.replaceState({ drivyIndex: historyIndex.current }, '', consolePath(state.membership.schoolId, section, query));
        setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
        return;
      }
      proceedNavigation(() => {
        pushPath(consolePath(state.membership.schoolId, section, query));
        setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
        setNavigationOpen(false);
      });
    },
    login: options => { void login(options); },
    confirmIdentity,
    };
  }, [state, route.query, route.section, drafts, readCache]);

  const personName = state.status === 'ready' || state.status === 'choose' || state.status === 'denied' ? state.me.displayName : session?.user?.displayName;
  const adminSchools = state.status === 'ready' ? state.me.memberships.filter(member => member.roles.includes('ADMIN')) : [];
  const setupMode = context?.school.status === 'DRAFT' && route.section === 'apercu';

  return { route, setRoute, state, resumeGate, resumeCurrentAccess, session, busy, logoutError, logoutWarning, setLogoutWarning,
    identityDialog, navigationOpen, setNavigationOpen, navigationButton, unsaved, bypassGuard, departure, setDeparture,
    proceedNavigation, historyIndex, pushPath, snapshot, draftScope, load, finishIdentity, confirmedIdentity,
    requestLogout, logout, context, personName, adminSchools, setupMode };
}
