import { useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { commandSpecs } from '../command-core';
import { commandStore, pendingActions, useCommandSnapshot } from '../command-store';
import { commandRefreshesSchool } from '../command-conflicts';
import { ScopedReadCache } from './load-model';
import { endSession, meSchema, request, RequestFailure, roleLabel, sessionSchema } from '../protocol';
import type { Me, Member, Session } from '../protocol';
import { readSchool, schoolSchema, type School } from '../school-api';
import { ConfirmDialog, Loading, Notice, SelectField, Symbol, formatDateTime } from '../ui';
import { BrandSymbol } from '../BrandSymbol';
import { AccountMenu } from '../preferences';
import { AccountEntry } from '../account-entry';
import { accountEntryDestination } from '../account-entry-route';
import { IdentityConfirmationDialog } from '../identity-confirmation';
import { SettingsFocus, SettingsSearch } from './settings-search';
import { ConsoleContext, readError, sectionKeys, type ConsoleContextValue, type SectionKey } from './context';
import { OverviewSection } from './overview';
import { ConfigurationSection } from './configuration';
import { ProfileFieldsSection } from './profile-fields';
import { PrivacySection } from './privacy';
import { InvitationsSection, TeamSection } from './people';
import { LearnersSection } from './learners';
import { AvailabilitySection } from './availability';
import { AgendaSection } from './agenda';
import { TripsSection } from './trips';
import { FormationsSection } from './formations';
import { LegacyReferenceRoute, TermsArchiveSection, UncategorizedTariffsSection } from './formation-references';
import { ObservationThemesSection } from './observation-themes';
import { isLocalItemCurrent, localNavigationQuery, parentSection, sectionTitles, workspaceFor, workspaces } from './navigation';
import { consolePath, parseConsoleRoute, type NavigationQuery } from './route';
import { ConsoleAccessReader, sameConsoleAccess } from './access-reader';
import { UiSuspendedContext } from '../ui-suspension';
import './portal-shell.css';

type State =
  | { status: 'loading' }
  | { status: 'signin' }
  | { status: 'error'; message: string }
  | { status: 'choose'; me: Me; admin: Member[] }
  | { status: 'denied'; me: Me; membership: Member | null }
  | { status: 'ready'; me: Me; membership: Member; school: School };

export function ManagementConsole() {
  const [route, setRoute] = useState(() => parseConsoleRoute(window.location.pathname, window.location.search));
  const [state, setState] = useState<State>({ status: 'loading' });
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

  return (
    <UiSuspendedContext.Provider value={resumeGate !== null}><div className={`console-shell${setupMode ? ' setup-mode' : ''}`}>
      {resumeGate !== null && <main className="access-resume-gate">
        {resumeGate === 'checking' ? <Loading label="Vérification de vos accès…" /> : <Notice tone="error" title="Vos accès doivent être vérifiés" actions={<button className="button primary" type="button" onClick={() => void resumeCurrentAccess.current()}>Réessayer</button>}><p>Vérifiez votre connexion. Votre saisie reste conservée tant que vous gardez cette page ouverte.</p></Notice>}
      </main>}
      <div className="console-content" hidden={resumeGate !== null} inert={resumeGate !== null}>
      <a className="skip-link" href="#main">Aller au contenu</a>
      <header className="console-bar">
        {context && !setupMode && <button ref={navigationButton} type="button" className="button quiet navigation-toggle" aria-controls="school-navigation" aria-expanded={navigationOpen}
          onKeyDown={event => { if (event.key === 'Escape') { event.preventDefault(); setNavigationOpen(false); } }}
          onClick={() => setNavigationOpen(open => !open)}><Symbol kind="menu" bare /><span>Menu</span></button>}
        <a className="brand" href={context ? consolePath(context.schoolId, context.school.status === 'ACTIVE' ? 'agenda' : 'apercu') : '/app/'}
          aria-label="Drivy, accueil de l’école" onClick={event => {
            if (!context || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
            event.preventDefault(); context.navigate(context.school.status === 'ACTIVE' ? 'agenda' : 'apercu');
          }}>
          <BrandSymbol />
          <span>Drivy</span>
        </a>
        {state.status === 'ready' && (adminSchools.length > 1
          ? <div className="school-switch"><SelectField label="École gérée" value={state.membership.schoolId} search
              options={adminSchools.map(member => ({ value: member.schoolId, label: member.schoolName }))}
              onChange={schoolId => proceedNavigation(() => { pushPath(`/app/gestion/${schoolId}`); setRoute({ schoolId, section: 'apercu', query: {} }); })} /></div>
          : <span className="school-name">{state.school.name}</span>)}
        <div className="bar-end">
          <AccountMenu name={personName ?? 'Mon compte'} authenticated={!!session?.authenticated} busy={busy}
            beforeNavigate={proceed => proceedNavigation(() => { unsaved.current.clear(); proceed(); })} onLogout={() => proceedNavigation(requestLogout)} />
        </div>
      </header>

      <div className="console-body">
        {context && !setupMode && <ConsoleNavigation schoolId={context.schoolId} section={route.section} query={route.query} open={navigationOpen} navigate={context.navigate}
          beforeNavigate={proceed => proceedNavigation(() => { unsaved.current.clear(); proceed(); })} onEscape={() => { setNavigationOpen(false); navigationButton.current?.focus(); }} />}

        <main id="main" className="console-main" aria-busy={state.status === 'loading'}>
          {logoutError && <Notice tone="error" title="Déconnexion non confirmée"><p>{logoutError}</p></Notice>}
          {state.status === 'loading' && <Loading label="Ouverture de la gestion de l’école…" />}
          {state.status === 'error' && <Notice tone="error" title="La gestion ne peut pas s’ouvrir"
            actions={<button type="button" className="button retry" onClick={() => void load(route.schoolId)}><Symbol kind="refresh" bare />Réessayer</button>}>
            <p>{state.message}</p></Notice>}
          {state.status === 'signin' && <>
            {snapshot.entries.size > 0 && <Notice tone="warning" title="Une demande reste à vérifier"><p>Après connexion, ouvrez la même école pour consulter son résultat.</p></Notice>}
            <AccountEntry onSignedIn={kind => {
              const destination = accountEntryDestination(kind);
              if (destination) window.location.assign(destination);
              else void load(route.schoolId);
            }} />
          </>}
          {state.status === 'choose' && <ChooseSchool schools={state.admin} onChoose={schoolId => { pushPath(`/app/gestion/${schoolId}`); setRoute({ schoolId, section: 'apercu', query: {} }); }} />}
          {state.status === 'denied' && <Denied membership={state.membership} />}
          {context && <ConsoleContext.Provider value={context}>
            {!setupMode && <SectionNavigation schoolId={context.schoolId} section={route.section} query={route.query} navigate={context.navigate} />}
            <PendingPanel />
            <Section section={route.section} key={`${draftScope}-${route.section}-${route.section === 'invitations' ? route.query.audience ?? 'learners' : route.section === 'apercu' ? route.query.from ?? '' : ''}`} />
            <SettingsFocus section={route.section} target={route.query.focus} navigationKey={historyIndex.current} />
          </ConsoleContext.Provider>}
        </main>
      </div>
      <ConfirmDialog open={logoutWarning} title="Se déconnecter avec une demande à vérifier ?" confirmLabel="Se déconnecter" busy={busy}
        onCancel={() => setLogoutWarning(false)} onConfirm={() => { setLogoutWarning(false); void logout(); }}>
        <p>Une demande envoyée à l’école n’a pas encore de résultat connu. Se déconnecter arrête son suivi : vérifiez-la d’abord pour connaître son résultat.</p>
      </ConfirmDialog>
      <ConfirmDialog open={departure !== null} title="Quitter sans enregistrer ?" confirmLabel="Quitter la page" busy={false}
        onCancel={() => setDeparture(null)} onConfirm={() => { const next = departure; setDeparture(null); bypassGuard.current = true; try { next?.proceed(); } finally { bypassGuard.current = false; } }}>
        <p>Vos modifications ne sont pas enregistrées auprès de l’école.</p>
      </ConfirmDialog>
      {identityDialog && <IdentityConfirmationDialog mode={identityDialog.mode} initialEmail={identityDialog.email}
        onCancel={() => finishIdentity(false)} onConfirmed={confirmedIdentity} />}
      </div>
    </div></UiSuspendedContext.Provider>
  );
}

/** The same navigation is used by the live shell and the synthetic visual review. */
export function ConsoleNavigation({ schoolId, section, query = {}, open, navigate, onEscape, beforeNavigate = proceed => proceed() }: {
  schoolId: string; section: SectionKey; query?: NavigationQuery; open: boolean; navigate: (section: SectionKey, query?: NavigationQuery) => void;
  onEscape: () => void; beforeNavigate?: (proceed: () => void) => void;
}) {
  const panel = useRef<HTMLDivElement>(null);
  const [mobile, setMobile] = useState(() => window.matchMedia('(max-width: 959px)').matches);
  const close = useRef(onEscape); close.current = onEscape;
  useEffect(() => {
    const media = window.matchMedia('(max-width: 959px)');
    const changed = () => setMobile(media.matches);
    media.addEventListener('change', changed);
    return () => media.removeEventListener('change', changed);
  }, []);
  useEffect(() => {
    if (!open || !mobile) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const surfaces = [...document.querySelectorAll<HTMLElement>('.console-main, .console-bar')];
    const previousInert = surfaces.map(surface => surface.inert);
    const overflow = document.body.style.overflow;
    surfaces.forEach(surface => { surface.inert = true; });
    document.body.style.overflow = 'hidden';
    panel.current?.querySelector<HTMLButtonElement>('.navigation-close')?.focus();
    const onKey = (event: KeyboardEvent) => {
      // A nested settings/confirmation dialog owns its own keyboard handling.
      if (document.querySelector('dialog[open], [data-slot="dialog-content"]')) return;
      if (event.key === 'Escape') { event.preventDefault(); close.current(); }
      if (event.key !== 'Tab') return;
      const items = [...(panel.current?.querySelectorAll<HTMLElement>('a[href],button:not(:disabled),input:not(:disabled),[tabindex="0"]') ?? [])]
        .filter(item => item.getClientRects().length > 0 && !item.closest('[inert]'));
      const first = items[0], last = items.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      surfaces.forEach((surface, index) => { surface.inert = previousInert[index] ?? false; });
      document.body.style.overflow = overflow;
      if (previous?.isConnected) previous.focus({ preventScroll: true });
    };
  }, [open, mobile]);
  const current = workspaceFor(section, query);
  const preferencesPath = `/app/preferences?returnTo=${encodeURIComponent(consolePath(schoolId, section, query))}`;
  const itemLink = (workspace: typeof current, item: typeof current.items[number]) => {
    const destinationQuery = localNavigationQuery(workspace, item, query);
    return <a href={consolePath(schoolId, item.section, destinationQuery)} aria-current={isLocalItemCurrent(item, section) ? 'page' : undefined}
      onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(item.section, destinationQuery); }}>{item.label}</a>;
  };
  return <aside id="school-navigation" className={`console-nav${open ? ' is-open' : ''}`} inert={mobile && !open}>
    {mobile && open && <div className="navigation-backdrop" onClick={onEscape} aria-hidden="true" />}
    <div ref={panel} className="nav-inner" role={mobile && open ? 'dialog' : undefined} aria-modal={mobile && open ? true : undefined} aria-label={mobile ? 'Navigation de l’école' : undefined}>
      <div className="mobile-navigation-heading"><strong>Votre école</strong><button className="button quiet navigation-close" type="button" onClick={onEscape}>Fermer</button></div>
      <SettingsSearch schoolId={schoolId} navigate={navigate} beforeNavigate={beforeNavigate} />
      <nav aria-label="Gestion de l’école"><p className="nav-group-label">Espace de travail</p><ul className="primary-navigation">{workspaces.map(workspace => {
        const homeQuery = current.key === workspace.key ? localNavigationQuery(workspace, { section: workspace.home, label: workspace.label }, query) : {};
        return <li key={workspace.key} className={workspace.key === 'settings' ? 'nav-settings' : undefined}>
        <a href={consolePath(schoolId, workspace.home, homeQuery)} aria-current={current.key === workspace.key ? (section === workspace.home ? 'page' : 'true') : undefined}
          onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(workspace.home, homeQuery); }}>
          <Symbol kind={workspace.symbol} bare /><span>{workspace.key === 'settings' ? 'Réglages de l’école' : workspace.label}</span>
        </a>
        {current.key === workspace.key && workspace.items.length > 1 && <ul className="workspace-navigation" aria-label={`Pages · ${workspace.label}`}>
          {workspace.items.filter(item => item.section !== workspace.home).map(item => <li key={item.section}>{itemLink(workspace, item)}</li>)}
        </ul>}
      </li>; })}</ul></nav>
      <div className="navigation-personal"><a href={preferencesPath} onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); beforeNavigate(() => window.location.assign(preferencesPath)); }}><Symbol kind="account" bare />Mes préférences</a><a href="/app/" onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); beforeNavigate(() => window.location.assign('/app/')); }}><Symbol kind="school" bare />Mes écoles</a></div>
  </div></aside>;
}

/** Deep editors keep their hierarchy and return context; destinations live only in the rail/menu. */
export function SectionNavigation({ schoolId, section, query = {}, navigate }: {
  schoolId: string; section: SectionKey; query?: NavigationQuery; navigate: (section: SectionKey, query?: NavigationQuery) => void;
}) {
  const workspace = workspaceFor(section, query), parent = parentSection(section);
  const categoryQuery = query.category ? { category: query.category } : {};
  const { category: _category, ...unfiltered } = query;
  const returnTo = query.from && query.from !== section && ['offres', 'prestations', 'formations'].includes(query.from) ? query.from : null;
  const link = (destination: SectionKey, label: string, destinationQuery: NavigationQuery = categoryQuery) => <a href={consolePath(schoolId, destination, destinationQuery)}
    onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(destination, destinationQuery); }}>{label}</a>;
  return <div className="section-navigation">
    {parent !== null && <nav className="breadcrumbs" aria-label="Fil d’Ariane"><ol>
      <li>{section === workspace.home ? <span aria-current="page">{workspace.label}</span> : link(workspace.home, workspace.label)}</li>
      {parent && parent !== workspace.home && <li>{link(parent, sectionTitles[parent])}</li>}
      {section !== workspace.home && <li><span aria-current="page">{sectionTitles[section]}</span></li>}
    </ol></nav>}
    {(returnTo || (query.category && section !== 'formations')) && <div className="navigation-context">
      {returnTo && link(returnTo, returnTo === 'offres' ? 'Retour à la formation' : returnTo === 'prestations' ? 'Retour au tarif' : 'Retour aux formations')}
      {query.category && section !== 'formations' && <><span>Permis {query.category}</span>{link(section, 'Toutes les catégories', unfiltered)}</>}
    </div>}
  </div>;
}

function Section({ section }: { section: SectionKey }): ReactNode {
  switch (section) {
    case 'apercu': return <OverviewSection />;
    case 'configuration': return <ConfigurationSection />;
    case 'confidentialite': return <PrivacySection />;
    case 'champs-profil': return <ProfileFieldsSection />;
    case 'formations': return <FormationsSection />;
    // Anciennes adresses du catalogue : retrouvent la version désignée dans la fiche du permis.
    case 'offres': case 'referentiels': case 'procedures': return <LegacyReferenceRoute section={section} />;
    case 'prestations': return <UncategorizedTariffsSection />;
    case 'conditions': return <TermsArchiveSection />;
    case 'equipe': return <TeamSection />;
    case 'invitations': return <InvitationsSection />;
    case 'eleves': return <LearnersSection />;
    case 'agenda': return <AgendaSection />;
    case 'trajets': return <TripsSection />;
    case 'disponibilites': return <AvailabilitySection />;
    case 'absences': return <AvailabilitySection section="absences" />;
    case 'signalements': return <ObservationThemesSection />;
  }
}

function ChooseSchool({ schools, onChoose }: { schools: Member[]; onChoose: (schoolId: string) => void }) {
  return (
    <section className="section" aria-labelledby="choose-title">
      <h1 id="choose-title">Choisir l’école à gérer</h1>
      <ul className="row-list">{schools.map(member => <li key={member.schoolId}>
        <Symbol kind="school" />
        <div className="row-text"><h2 className="row-title">{member.schoolName}</h2><p className="row-meta">{member.roles.map(roleLabel).join(' · ')}</p></div>
        <button type="button" className="button secondary" onClick={() => onChoose(member.schoolId)}>Gérer</button>
      </li>)}</ul>
    </section>
  );
}

function Denied({ membership }: { membership: Member | null }) {
  return (
    <section className="panel empty-state" aria-labelledby="denied-title">
      <Symbol kind="shield" />
      <div className="row-text">
        <h1 id="denied-title" className="row-title">Gestion réservée à l’administration</h1>
        <p className="row-meta">{membership
          ? `Votre accès dans ${membership.schoolName} : ${membership.roles.map(roleLabel).join(' · ')}. La gestion de l’école demande le rôle Administration.`
          : 'Ce compte n’administre aucune école. Si vos accès viennent de changer, actualisez la page.'}</p>
        <a className="button secondary" href="/app/">Retour à votre espace</a>
      </div>
    </section>
  );
}

/** How the last followed request ended, kept on screen until dismissed or until another request is followed. */
type Settled = { tone: 'success' | 'info' | 'error'; title: string; message?: string; needsLogin?: boolean };

/** The request whose result is unknown, shown on every section until the school answers. */
function PendingPanel() {
  const snapshot = useCommandSnapshot();
  const context = useContextSafe();
  const entries = [...snapshot.entries.values()].filter(entry => entry.meta.schoolId === context?.schoolId);
  const [selected, setSelected] = useState<string | null>(null);
  const entry = entries.find(item => item.meta.operationId === selected) ?? entries.find(item => item.phase !== 'sending') ?? entries[0];
  const [settled, setSettled] = useState<Settled | null>(null);
  const [releasing, setReleasing] = useState(false);
  const releaseTitle = useRef<HTMLElement>(null);
  useEffect(() => { if (entry) setSettled(null); setReleasing(false); }, [entry?.meta.operationId]);
  useEffect(() => { if (releasing) releaseTitle.current?.focus(); }, [releasing]);
  if (!context) return null;
  if (!entry) {
    return settled ? <Notice tone={settled.tone} title={settled.title} actions={<>
      {settled.needsLogin && <button type="button" className="button secondary" onClick={() => context.login()}>Se reconnecter</button>}
      <button type="button" className="button quiet" onClick={() => setSettled(null)}>Masquer</button>
    </>}>{settled.message && <p>{settled.message}</p>}</Notice> : null;
  }
  const working = entry.phase === 'sending' || entry.phase === 'verifying';
  const followed = pendingActions(entry);
  const what = `${commandSpecs[entry.meta.kind].label} · demandée le ${formatDateTime(new Date(entry.meta.createdAt).toISOString(), context.school.timeZone)}`;
  const confirmed: Settled = { tone: 'success', title: 'Résultat confirmé par l’école', message: `${what}.` };
  async function verify() {
    const result = await commandStore.verify(context!.schoolId, entry!.meta.operationId);
    if (result.status === 'confirmed') { setSettled(confirmed); if (commandRefreshesSchool(entry!.meta.kind)) void context!.reloadSchool(); }
  }
  async function resend() {
    let token = context!.csrf();
    try { token = await context!.refreshCsrf(); } catch { /* keep the current token */ }
    const result = await commandStore.resend(context!.schoolId, token, entry!.meta.operationId);
    if (result.status === 'confirmed') { setSettled(confirmed); if (commandRefreshesSchool(entry!.meta.kind)) void context!.reloadSchool(); }
    // Refused while the school held no trace of it: the request is over and nothing was changed.
    if (result.status === 'rejected') {
      setSettled({ tone: 'error', title: 'Demande refusée par l’école', message: `${what}. ${result.message}`, needsLogin: result.needsLogin });
      void context!.reloadSchool();
    }
  }
  function release() {
    commandStore.release(context!.schoolId, entry!.meta.operationId);
    setSettled({ tone: 'info', title: 'Suivi arrêté', message: `${what}. Son résultat doit être vérifié avant une nouvelle demande.` });
    void context!.reloadSchool();
  }
  if (entry.phase === 'sending' && entry.attempts <= 1) return null;
  return (
    <section className="pending-panel" aria-labelledby="pending-title" aria-live="polite">
      {entries.length > 1 && <div className="button-row compact" aria-label="Demandes en attente">{entries.map(item =>
        <button type="button" className="button quiet" aria-pressed={entry.meta.operationId === item.meta.operationId}
          key={item.meta.operationId} onClick={() => setSelected(item.meta.operationId)}>{commandSpecs[item.meta.kind].label}</button>)}</div>}
      <div className="pending-heading">
        <Symbol kind="clock" />
        <div className="row-text">
          <h2 id="pending-title" className="row-title" tabIndex={-1}>{working ? entry.phase === 'verifying' ? 'Vérification auprès de l’école…' : 'Envoi de la même demande…'
            : entry.notRecorded ? 'Demande introuvable auprès de l’école' : 'Demande à vérifier'}</h2>
          <p className="row-meta">{what}</p>
        </div>
      </div>
      {entry.message && <p>{entry.message}</p>}
      <p className="caption">Référence de la demande : <code>{entry.meta.operationId}</code>.{followed.resend ? ' Renvoyer la même demande ne peut pas l’appliquer deux fois.' : ''}</p>
      <div className="button-row compact">
        <button type="button" className={entry.notRecorded && followed.resend ? 'button secondary' : 'button primary'} onClick={() => void verify()} disabled={working}>Vérifier auprès de l’école</button>
        {followed.resend && <button type="button" className={entry.notRecorded ? 'button primary' : 'button secondary'} onClick={() => void resend()} disabled={working}>Renvoyer la même demande</button>}
        {entry.needsLogin && <button type="button" className="button secondary" onClick={() => context.login()}>Se reconnecter</button>}
        {followed.release && !releasing && <button type="button" className="button quiet" onClick={() => setReleasing(true)}>{entry.notRecorded ? 'Abandonner la demande…' : 'Arrêter le suivi…'}</button>}
      </div>
      {releasing && followed.release && <div className="notice warning">
        <Symbol kind="alert" />
        <div className="notice-body">
          <strong ref={releaseTitle} tabIndex={-1}>{entry.notRecorded ? 'Abandonner cette demande ?' : 'Arrêter le suivi de cette demande ?'}</strong>
          <p>Son résultat restera inconnu : vérifiez les informations de l’école avant de refaire la modification. Arrêter le suivi n’annule pas une demande déjà reçue.</p>
          <div className="notice-actions">
            <button type="button" className="button secondary" onClick={release}>{entry.notRecorded ? 'Abandonner la demande' : 'Arrêter le suivi'}</button>
            <button type="button" className="button quiet" onClick={() => setReleasing(false)}>{entry.notRecorded ? 'Garder la demande' : 'Continuer le suivi'}</button>
          </div>
        </div>
      </div>}
    </section>
  );
}

function useContextSafe() { return useContext(ConsoleContext); }
