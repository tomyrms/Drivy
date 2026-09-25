import { useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { commandSpecs } from '../command-core';
import { commandStore, useCommandSnapshot } from '../command-store';
import { loginSchema, meSchema, okSchema, request, RequestFailure, roleLabel, sessionSchema } from '../protocol';
import type { Me, Member, Session } from '../protocol';
import { readSchool, schoolSchema, type School } from '../school-api';
import { Loading, Notice, Symbol, formatDateTime, type SymbolKind } from '../ui';
import { ConsoleContext, readError, sectionKeys, type ConsoleContextValue, type SectionKey } from './context';
import { OverviewSection } from './overview';
import { ConfigurationSection } from './configuration';
import { ProfileFieldsSection } from './profile-fields';
import { CurriculaSection, OfferingsSection, ProceduresSection } from './catalog';
import { ProductsSection, TermsSection } from './commerce';
import { InvitationsSection, TeamSection } from './people';

const navigation: readonly { group: string; items: readonly { key: SectionKey; label: string; symbol: SymbolKind }[] }[] = [
  { group: 'École', items: [
    { key: 'apercu', label: 'Vue d’ensemble', symbol: 'home' },
    { key: 'configuration', label: 'Configuration', symbol: 'settings' },
    { key: 'champs-profil', label: 'Champs du profil', symbol: 'list' },
  ] },
  { group: 'Catalogue', items: [
    { key: 'offres', label: 'Offres', symbol: 'layers' },
    { key: 'referentiels', label: 'Référentiels', symbol: 'book' },
    { key: 'procedures', label: 'Procédures', symbol: 'file' },
    { key: 'prestations', label: 'Prestations et tarifs', symbol: 'tag' },
    { key: 'conditions', label: 'Conditions commerciales', symbol: 'receipt' },
  ] },
  { group: 'Personnes', items: [
    { key: 'equipe', label: 'Équipe et accès', symbol: 'users' },
    { key: 'invitations', label: 'Invitations', symbol: 'mail' },
  ] },
];
const sectionTitle = (key: SectionKey) => navigation.flatMap(group => group.items).find(item => item.key === key)!.label;

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function parseRoute(pathname: string): { schoolId: string | null; section: SectionKey } {
  const [, , , schoolId, section] = pathname.replace(/\/$/, '').split('/');
  return { schoolId: schoolId && uuid.test(schoolId) ? schoolId.toLowerCase() : null,
    section: (sectionKeys as readonly string[]).includes(section ?? '') ? section as SectionKey : 'apercu' };
}
const pathFor = (schoolId: string, section: SectionKey) => `/app/gestion/${schoolId}${section === 'apercu' ? '' : `/${section}`}`;

type State =
  | { status: 'loading' }
  | { status: 'signin' }
  | { status: 'error'; message: string }
  | { status: 'choose'; me: Me; admin: Member[] }
  | { status: 'denied'; me: Me; membership: Member | null }
  | { status: 'ready'; me: Me; membership: Member; school: School };

export function ManagementConsole() {
  const [route, setRoute] = useState(() => parseRoute(window.location.pathname));
  const [state, setState] = useState<State>({ status: 'loading' });
  const [session, setSession] = useState<Session | null>(null);
  const [busy, setBusy] = useState(false);
  const csrf = useRef('');
  const generation = useRef(0);
  const snapshot = useCommandSnapshot();

  const load = useCallback(async (schoolId: string | null) => {
    const current = ++generation.current;
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
      if (!schoolId) window.history.replaceState(null, '', pathFor(membership.schoolId, route.section));
      setRoute(previous => ({ ...previous, schoolId: membership.schoolId }));
      setState({ status: 'ready', me, membership, school });
    } catch (error) {
      if (current !== generation.current) return;
      if (error instanceof RequestFailure && error.status === 401) { setState({ status: 'signin' }); return; }
      setState({ status: 'error', message: readError(error) });
    }
  }, [route.section]);

  useEffect(() => { void load(route.schoolId); }, [route.schoolId]);
  useEffect(() => {
    const onPopState = () => setRoute(parseRoute(window.location.pathname));
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, []);
  useEffect(() => {
    const school = state.status === 'ready' ? state.school.name : null;
    document.title = `${sectionTitle(route.section)}${school ? ` · ${school}` : ''} · Gestion Drivy`;
  }, [route.section, state]);

  async function login() {
    if (busy) return;
    setBusy(true);
    try {
      const next = await request('session', sessionSchema);
      const returnTo = window.location.pathname.replace(/\/$/, '');
      const result = await request('login', loginSchema, { csrf: next.csrfToken, body: /^\/app\/gestion(\/|$)/.test(returnTo) ? { returnTo } : {} });
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
    setBusy(true);
    try { await request('logout', okSchema, { csrf: csrf.current, body: {} }); } catch { /* Local session is closed anyway below. */ }
    commandStore.clear();
    window.location.assign('/app/');
  }

  const context = useMemo<ConsoleContextValue | null>(() => state.status !== 'ready' ? null : {
    schoolId: state.membership.schoolId, me: state.me, membership: state.membership, school: state.school,
    canConfigureCatalog: state.membership.grants.includes('CONFIGURE_CATALOG'),
    reloadSchool: async () => {
      try {
        const school = await readSchool(state.membership.schoolId, '', schoolSchema);
        setState(previous => previous.status === 'ready' && previous.membership.schoolId === school.id ? { ...previous, school } : previous);
      } catch { /* The section keeps showing its own error; the stale version is refused by If-Match. */ }
    },
    csrf: () => csrf.current,
    refreshCsrf: async () => { const next = await request('session', sessionSchema); csrf.current = next.csrfToken; return next.csrfToken; },
    navigate: (section: SectionKey) => {
      window.history.pushState(null, '', pathFor(state.membership.schoolId, section));
      setRoute({ schoolId: state.membership.schoolId, section });
    },
    login: () => { void login(); },
  }, [state]);

  const personName = state.status === 'ready' || state.status === 'choose' || state.status === 'denied' ? state.me.displayName : session?.user?.displayName;
  const adminSchools = state.status === 'ready' ? state.me.memberships.filter(member => member.roles.includes('ADMIN')) : [];

  return (
    <div className="console-shell">
      <a className="skip-link" href="#main">Aller au contenu</a>
      <header className="console-bar">
        <a className="brand" href="/app/" aria-label="Drivy, retour à votre espace">
          <span className="brand-symbol" aria-hidden="true"><svg viewBox="0 0 32 32"><path d="m11 24 5-16 5 16-5-4Z" /></svg></span>
          <span>Drivy</span><span className="brand-context">Gestion</span>
        </a>
        {state.status === 'ready' && (adminSchools.length > 1
          ? <label className="school-switch"><span className="visually-hidden">École gérée</span>
              <select value={state.membership.schoolId} onChange={event => { window.history.pushState(null, '', pathFor(event.target.value, 'apercu')); setRoute({ schoolId: event.target.value, section: 'apercu' }); }}>
                {adminSchools.map(member => <option key={member.schoolId} value={member.schoolId}>{member.schoolName}</option>)}
              </select>
            </label>
          : <span className="school-name">{state.school.name}</span>)}
        <div className="bar-end">
          {personName && <span className="person-name"><Symbol kind="account" bare />{personName}</span>}
          {session?.authenticated && <button type="button" className="button quiet" onClick={() => void logout()} disabled={busy}>Se déconnecter</button>}
        </div>
      </header>

      <div className="console-body">
        {context && <nav className="console-nav" aria-label="Gestion de l’école"><div className="nav-inner">
          {navigation.map(group => <div className="nav-group" key={group.group}>
            <h2 className="nav-title">{group.group}</h2>
            <ul>
              {group.items.map(item => <li key={item.key}>
                <a href={pathFor(context.schoolId, item.key)} aria-current={route.section === item.key ? 'page' : undefined}
                  onClick={event => { if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return; event.preventDefault(); context.navigate(item.key); }}>
                  <Symbol kind={item.symbol} bare /><span>{item.label}</span>
                </a>
              </li>)}
            </ul>
          </div>)}
        </div></nav>}

        <main id="main" className="console-main" aria-busy={state.status === 'loading'}>
          {state.status === 'loading' && <Loading label="Ouverture de la gestion de l’école…" />}
          {state.status === 'error' && <Notice tone="error" title="La gestion ne peut pas s’ouvrir"
            actions={<button type="button" className="button retry" onClick={() => void load(route.schoolId)}><Symbol kind="refresh" bare />Réessayer</button>}>
            <p>{state.message}</p></Notice>}
          {state.status === 'signin' && <SignIn onLogin={() => void login()} busy={busy} pending={snapshot.entries.size > 0} />}
          {state.status === 'choose' && <ChooseSchool schools={state.admin} onChoose={schoolId => { window.history.pushState(null, '', pathFor(schoolId, 'apercu')); setRoute({ schoolId, section: 'apercu' }); }} />}
          {state.status === 'denied' && <Denied membership={state.membership} />}
          {context && <ConsoleContext.Provider value={context}>
            <PendingPanel />
            <Section section={route.section} key={`${context.schoolId}-${route.section}`} />
          </ConsoleContext.Provider>}
        </main>
      </div>
    </div>
  );
}

function Section({ section }: { section: SectionKey }): ReactNode {
  switch (section) {
    case 'apercu': return <OverviewSection />;
    case 'configuration': return <ConfigurationSection />;
    case 'champs-profil': return <ProfileFieldsSection />;
    case 'offres': return <OfferingsSection />;
    case 'referentiels': return <CurriculaSection />;
    case 'procedures': return <ProceduresSection />;
    case 'prestations': return <ProductsSection />;
    case 'conditions': return <TermsSection />;
    case 'equipe': return <TeamSection />;
    case 'invitations': return <InvitationsSection />;
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
        {entry.needsLogin && <button type="button" className="button secondary" onClick={context.login}>Se reconnecter</button>}
        {canRelease && !releasing && <button type="button" className="button quiet" onClick={() => setReleasing(true)}>Arrêter le suivi…</button>}
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
