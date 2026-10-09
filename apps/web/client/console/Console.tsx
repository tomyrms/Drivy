import { useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { commandSpecs } from '../command-core';
import { commandStore, useCommandSnapshot } from '../command-store';
import { endSession, loginSchema, meSchema, request, RequestFailure, roleLabel, sessionSchema } from '../protocol';
import type { Me, Member, Session } from '../protocol';
import { readSchool, schoolSchema, type School } from '../school-api';
import { Loading, Notice, Symbol, formatDateTime } from '../ui';
import { BrandSymbol } from '../BrandSymbol';
import { ConsoleContext, readError, sectionKeys, type ConsoleContextValue, type SectionKey } from './context';
import { OverviewSection } from './overview';
import { ConfigurationSection } from './configuration';
import { ProfileFieldsSection } from './profile-fields';
import { CurriculaSection, OfferingsSection, ProceduresSection } from './catalog';
import { ProductsSection, TermsSection } from './commerce';
import { InvitationsSection, TeamSection } from './people';
import { LearnersSection } from './learners';
import { AvailabilitySection } from './availability';
import { AgendaSection } from './agenda';
import { TripsSection } from './trips';
import { FormationsSection } from './formations';
import { isLocalItemCurrent, parentSection, sectionTitles, workspaceFor, workspaces } from './navigation';
import { consolePath, parseConsoleRoute, type NavigationQuery } from './route';
import { ConsoleAccessReader } from './access-reader';

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
  const [session, setSession] = useState<Session | null>(null);
  const [busy, setBusy] = useState(false);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const [navigationOpen, setNavigationOpen] = useState(false);
  const navigationButton = useRef<HTMLButtonElement>(null);
  const csrf = useRef('');
  const generation = useRef(0);
  const accessReader = useRef(new ConsoleAccessReader(() => request('me', meSchema).then(result => result.data), schoolId => readSchool(schoolId, '', schoolSchema)));
  const snapshot = useCommandSnapshot();
  const draftScope = state.status === 'ready'
    ? `${state.me.personId}/${state.membership.schoolId}/${state.membership.membershipId}/${state.membership.accessEpoch}` : null;
  const drafts = useMemo(() => new Map<string, unknown>(), [draftScope]);

  const load = useCallback(async (schoolId: string | null) => {
    const current = ++generation.current;
    accessReader.current.invalidate();
    setState({ status: 'loading' });
    try {
      const next = await request('session', sessionSchema);
      if (current !== generation.current) return;
      csrf.current = next.csrfToken; setSession(next);
      if (!next.authenticated) { setState({ status: 'signin' }); return; }
      const me = (await request('me', meSchema)).data;
      if (current !== generation.current) return;
      const admin = me.memberships.filter(member => member.roles.includes('ADMIN'));
      const target = schoolId ?? (admin.length === 1 ? admin[0]!.schoolId : null);
      if (!target) { setState(admin.length ? { status: 'choose', me, admin } : { status: 'denied', me, membership: null }); return; }
      const membership = me.memberships.find(member => member.schoolId.toLowerCase() === target.toLowerCase());
      if (!membership?.roles.includes('ADMIN')) { setState({ status: 'denied', me, membership: membership ?? null }); return; }
      const school = await readSchool(membership.schoolId, '', schoolSchema);
      if (current !== generation.current) return;
      if (school.id !== membership.schoolId) throw new RequestFailure('INVALID_RESPONSE');
      const currentRoute = parseConsoleRoute(window.location.pathname, window.location.search);
      const explicitSection = (sectionKeys as readonly string[]).includes(window.location.pathname.replace(/\/$/, '').split('/')[4] ?? '');
      const section = explicitSection ? currentRoute.section : school.status === 'ACTIVE' ? 'agenda' : 'apercu';
      window.history.replaceState(null, '', consolePath(membership.schoolId, section, currentRoute.query));
      setRoute({ ...currentRoute, schoolId: membership.schoolId, section });
      setState({ status: 'ready', me, membership, school });
    } catch (error) {
      if (current !== generation.current) return;
      if (error instanceof RequestFailure && error.status === 401) { setState({ status: 'signin' }); return; }
      setState({ status: 'error', message: readError(error) });
    }
  }, []);

  useEffect(() => { void load(route.schoolId); }, [route.schoolId]);
  useEffect(() => {
    const onPopState = () => setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
    const onPageShow = (event: PageTransitionEvent) => { if (event.persisted) void load(parseConsoleRoute(window.location.pathname, window.location.search).schoolId); };
    window.addEventListener('popstate', onPopState);
    window.addEventListener('pageshow', onPageShow);
    return () => { generation.current++; accessReader.current.invalidate(); window.removeEventListener('popstate', onPopState); window.removeEventListener('pageshow', onPageShow); };
  }, []);
  useEffect(() => {
    const school = state.status === 'ready' ? state.school.name : null;
    document.title = `${sectionTitles[route.section]}${school ? ` · ${school}` : ''} · Gestion Drivy`;
  }, [route.section, state]);

  async function login(options?: { reauthenticate?: boolean }) {
    if (busy) return;
    setBusy(true);
    try {
      const next = await request('session', sessionSchema);
      const returnTo = window.location.pathname.replace(/\/$/, '');
      const result = await request('login', loginSchema, { csrf: next.csrfToken, body: {
        ...(/^\/app\/gestion(\/|$)/.test(returnTo) ? { returnTo } : {}), ...(options?.reauthenticate ? { reauthenticate: true } : {}) } });
      const target = new URL(result.url);
      const loopback = ['localhost', '127.0.0.1', '[::1]'];
      const localPage = window.location.protocol === 'http:' && loopback.includes(window.location.hostname);
      if ((target.protocol !== 'https:' && !(localPage && loopback.includes(target.hostname) && target.protocol === 'http:')) || target.username || target.password || target.hash) {
        throw new RequestFailure('INVALID_RESPONSE');
      }
      window.location.assign(target.href);
    } catch (error) { setState({ status: 'error', message: readError(error) }); setBusy(false); }
  }

  async function logout() {
    if (busy || !session) return;
    setBusy(true); setLogoutError(null);
    try {
      await endSession();
      commandStore.clear();
      window.location.assign('/app/');
    } catch (error) { setLogoutError(readError(error)); setBusy(false); }
  }

  const context = useMemo<ConsoleContextValue | null>(() => {
    if (state.status !== 'ready') return null;
    const scope = generation.current;
    return {
    schoolId: state.membership.schoolId, me: state.me, membership: state.membership, school: state.school,
    canConfigureCatalog: state.membership.grants.includes('CONFIGURE_CATALOG'),
    drafts,
    reloadSchool: async () => {
      if (scope !== generation.current) return;
      const access = await accessReader.current.read(state.membership.schoolId);
      if (!access || scope !== generation.current) return;
      if (access.status === 'unavailable') setState({ status: 'error', message: readError(access.error) });
      else setState(access);
      if (access.status === 'signin') setSession(null);
    },
    csrf: () => csrf.current,
    refreshCsrf: async () => { const next = await request('session', sessionSchema); csrf.current = next.csrfToken; return next.csrfToken; },
    routeQuery: route.query,
    setRouteQuery: (query: NavigationQuery, replace = false) => {
      const path = consolePath(state.membership.schoolId, route.section, query);
      if (`${window.location.pathname}${window.location.search}` === path) return;
      window.history[replace ? 'replaceState' : 'pushState'](null, '', path);
      setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
    },
    navigate: (section: SectionKey, query: NavigationQuery = {}) => {
      window.history.pushState(null, '', consolePath(state.membership.schoolId, section, query));
      setRoute(parseConsoleRoute(window.location.pathname, window.location.search));
      setNavigationOpen(false);
    },
    login: options => { void login(options); },
    };
  }, [state, route.query, route.section, drafts]);

  const personName = state.status === 'ready' || state.status === 'choose' || state.status === 'denied' ? state.me.displayName : session?.user?.displayName;
  const adminSchools = state.status === 'ready' ? state.me.memberships.filter(member => member.roles.includes('ADMIN')) : [];

  return (
    <div className="console-shell">
      <a className="skip-link" href="#main">Aller au contenu</a>
      <header className="console-bar">
        {context && <button ref={navigationButton} type="button" className="button quiet navigation-toggle" aria-controls="school-navigation" aria-expanded={navigationOpen}
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
          ? <label className="school-switch"><span className="visually-hidden">École gérée</span>
              <select value={state.membership.schoolId} onChange={event => { window.history.pushState(null, '', `/app/gestion/${event.target.value}`); setRoute({ schoolId: event.target.value, section: 'apercu', query: {} }); }}>
                {adminSchools.map(member => <option key={member.schoolId} value={member.schoolId}>{member.schoolName}</option>)}
              </select>
            </label>
          : <span className="school-name">{state.school.name}</span>)}
        <div className="bar-end">
          {personName && <a className="person-name" href="/app/" aria-label={`Compte de ${personName}`}><Symbol kind="account" bare />{personName}</a>}
          {session?.authenticated && <button type="button" className="button quiet" onClick={() => void logout()} disabled={busy}>Se déconnecter</button>}
        </div>
      </header>

      <div className="console-body">
        {context && <ConsoleNavigation schoolId={context.schoolId} section={route.section} query={route.query} open={navigationOpen} navigate={context.navigate}
          onEscape={() => { setNavigationOpen(false); navigationButton.current?.focus(); }} />}

        <main id="main" className="console-main" aria-busy={state.status === 'loading'}>
          {logoutError && <Notice tone="error" title="Déconnexion non confirmée"><p>{logoutError}</p></Notice>}
          {state.status === 'loading' && <Loading label="Ouverture de la gestion de l’école…" />}
          {state.status === 'error' && <Notice tone="error" title="La gestion ne peut pas s’ouvrir"
            actions={<button type="button" className="button retry" onClick={() => void load(route.schoolId)}><Symbol kind="refresh" bare />Réessayer</button>}>
            <p>{state.message}</p></Notice>}
          {state.status === 'signin' && <SignIn onLogin={() => void login()} busy={busy} pending={snapshot.entries.size > 0} />}
          {state.status === 'choose' && <ChooseSchool schools={state.admin} onChoose={schoolId => { window.history.pushState(null, '', `/app/gestion/${schoolId}`); setRoute({ schoolId, section: 'apercu', query: {} }); }} />}
          {state.status === 'denied' && <Denied membership={state.membership} />}
          {context && <ConsoleContext.Provider value={context}>
            <SectionNavigation schoolId={context.schoolId} section={route.section} query={route.query} navigate={context.navigate} />
            <PendingPanel />
            <Section section={route.section} key={`${draftScope}-${route.section}-${route.section === 'invitations' ? route.query.audience ?? 'learners' : ''}`} />
          </ConsoleContext.Provider>}
        </main>
      </div>
    </div>
  );
}

/** The same navigation is used by the live shell and the synthetic visual review. */
export function ConsoleNavigation({ schoolId, section, query = {}, open, navigate, onEscape }: {
  schoolId: string; section: SectionKey; query?: NavigationQuery; open: boolean; navigate: (section: SectionKey, query?: NavigationQuery) => void; onEscape: () => void;
}) {
  const current = workspaceFor(section, query);
  return <nav id="school-navigation" className={`console-nav${open ? ' is-open' : ''}`} aria-label="Gestion de l’école"
    onKeyDown={event => { if (event.key === 'Escape') { event.preventDefault(); onEscape(); } }}><div className="nav-inner">
      <ul>{workspaces.map(item => <li key={item.key}>
        <a href={consolePath(schoolId, item.home)} aria-current={current.key === item.key ? 'true' : undefined}
          onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(item.home); }}>
          <Symbol kind={item.symbol} bare /><span>{item.label}</span>
        </a>
      </li>)}</ul>
  </div></nav>;
}

/** A small local navigation and a real hierarchy, shared by every screen in a workspace. */
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
    <nav className="local-navigation" aria-label={`Rubriques · ${workspace.label}`}><ul>{workspace.items.map(item => {
      const destinationQuery = { ...(workspace.key === 'formations' ? categoryQuery : {}), ...item.query };
      return <li key={item.section}>
        <a href={consolePath(schoolId, item.section, destinationQuery)} aria-current={isLocalItemCurrent(item, section) ? 'page' : undefined}
          onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); navigate(item.section, destinationQuery); }}>{item.label}</a>
      </li>;
    })}</ul></nav>
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
    case 'champs-profil': return <ProfileFieldsSection />;
    case 'offres': return <OfferingsSection />;
    case 'formations': return <FormationsSection />;
    case 'referentiels': return <CurriculaSection />;
    case 'procedures': return <ProceduresSection />;
    case 'prestations': return <ProductsSection />;
    case 'conditions': return <TermsSection />;
    case 'equipe': return <TeamSection />;
    case 'invitations': return <InvitationsSection />;
    case 'eleves': return <LearnersSection />;
    case 'agenda': return <AgendaSection />;
    case 'trajets': return <TripsSection />;
    case 'disponibilites': return <AvailabilitySection />;
  }
}

function SignIn({ onLogin, busy, pending }: { onLogin: () => void; busy: boolean; pending: boolean }) {
  return (
    <section className="panel sign-in" aria-labelledby="console-signin">
      <Symbol kind="lock" tile />
      <h1 id="console-signin">Connectez-vous pour gérer votre école</h1>
      <p className="secondary-text">La gestion est réservée aux membres de l’administration. Vos accès sont vérifiés par l’école à chaque opération.</p>
      {pending && <p className="caption">Une demande reste à vérifier : après connexion, ouvrez la même école pour consulter son résultat.</p>}
      <button type="button" className="button primary" onClick={onLogin} disabled={busy}>Se connecter</button>
    </section>
  );
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

/** The request whose result is unknown, shown on every section until the school answers. */
function PendingPanel() {
  const snapshot = useCommandSnapshot();
  const context = useContextSafe();
  const entry = context ? snapshot.entries.get(context.schoolId) : undefined;
  const [confirmedAt, setConfirmedAt] = useState<number | null>(null);
  const [releasing, setReleasing] = useState(false);
  useEffect(() => { if (entry) setConfirmedAt(null); setReleasing(false); }, [entry?.meta.operationId]);
  if (!context) return null;
  if (!entry) {
    return confirmedAt ? <Notice tone="success" title="Résultat confirmé par l’école"
      actions={<button type="button" className="button quiet" onClick={() => setConfirmedAt(null)}>Masquer</button>}><p>La demande en attente a bien été appliquée.</p></Notice> : null;
  }
  const working = entry.phase === 'sending' || entry.phase === 'verifying';
  const canResend = entry.command !== null && entry.phase === 'uncertain';
  const canRelease = !working && (entry.command === null || entry.phase === 'review' || entry.notRecorded);
  async function verify() {
    const result = await commandStore.verify(context!.schoolId);
    if (result.status === 'confirmed') { setConfirmedAt(Date.now()); void context!.reloadSchool(); }
  }
  async function resend() {
    let token = context!.csrf();
    try { token = await context!.refreshCsrf(); } catch { /* keep the current token */ }
    const result = await commandStore.resend(context!.schoolId, token);
    if (result.status === 'confirmed') { setConfirmedAt(Date.now()); void context!.reloadSchool(); }
  }
  if (entry.phase === 'sending' && entry.attempts <= 1) return null;
  return (
    <section className="pending-panel" aria-labelledby="pending-title" aria-live="polite">
      <div className="pending-heading">
        <Symbol kind="clock" />
        <div className="row-text">
          <h2 id="pending-title" className="row-title" tabIndex={-1}>{working ? entry.phase === 'verifying' ? 'Vérification auprès de l’école…' : 'Envoi de la même demande…' : 'Demande à vérifier'}</h2>
          <p className="row-meta">{commandSpecs[entry.meta.kind].label} · demandée le {formatDateTime(new Date(entry.meta.createdAt).toISOString(), context.school.timeZone)}</p>
        </div>
      </div>
      {entry.message && <p>{entry.message}</p>}
      <p className="caption">Référence de la demande : <code>{entry.meta.operationId}</code>.{canResend ? ' Renvoyer la même demande ne peut pas l’appliquer deux fois.' : ''}</p>
      <div className="button-row compact">
        <button type="button" className="button primary" onClick={() => void verify()} disabled={working}>Vérifier auprès de l’école</button>
        {canResend && <button type="button" className="button secondary" onClick={() => void resend()} disabled={working}>Renvoyer la même demande</button>}
        {entry.needsLogin && <button type="button" className="button secondary" onClick={() => context.login()}>Se reconnecter</button>}
        {canRelease && !releasing && (entry.notRecorded
          ? <button type="button" className="button quiet" onClick={() => commandStore.release(context.schoolId)}>Abandonner la demande</button>
          : <button type="button" className="button quiet" onClick={() => setReleasing(true)}>Arrêter le suivi…</button>)}
      </div>
      {releasing && <div className="notice warning">
        <Symbol kind="alert" />
        <div className="notice-body">
          <strong>Arrêter le suivi de cette demande ?</strong>
          <p>{entry.notRecorded ? 'L’école n’a enregistré aucun effet pour cette référence.' : 'Son résultat restera inconnu : vérifiez ensuite les informations de l’école avant de refaire la modification.'}</p>
          <div className="notice-actions">
            <button type="button" className="button secondary" onClick={() => commandStore.release(context.schoolId)}>Arrêter le suivi</button>
            <button type="button" className="button quiet" onClick={() => setReleasing(false)}>Continuer le suivi</button>
          </div>
        </div>
      </div>}
    </section>
  );
}

function useContextSafe() { return useContext(ConsoleContext); }
