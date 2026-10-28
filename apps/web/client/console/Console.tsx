import { useContext, useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { commandSpecs } from '../command-core';
import { commandStore, pendingActions, useCommandSnapshot } from '../command-store';
import { commandRefreshesSchool } from '../command-conflicts';
import { roleLabel } from '../protocol';
import type { Member } from '../protocol';
import { ConfirmDialog, Loading, Notice, SelectField, Symbol, formatDateTime } from '../ui';
import { BrandSymbol } from '../BrandSymbol';
import { AccountMenu } from '../preferences';
import { AccountEntry } from '../account-entry';
import { accountEntryDestination } from '../account-entry-route';
import { IdentityConfirmationDialog } from '../identity-confirmation';
import { SettingsFocus, SettingsSearch } from './settings-search';
import { ConsoleContext, type SectionKey } from './context';
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
import { consolePath, type NavigationQuery } from './route';
import { UiSuspendedContext } from '../ui-suspension';
import { useManagementConsole } from './management-runtime';
import './portal-shell.css';

export function ManagementConsole() {
  const { route, setRoute, state, resumeGate, resumeCurrentAccess, session, busy, logoutError, logoutWarning, setLogoutWarning,
    identityDialog, navigationOpen, setNavigationOpen, navigationButton, unsaved, bypassGuard, departure, setDeparture,
    proceedNavigation, historyIndex, pushPath, snapshot, draftScope, load, finishIdentity, confirmedIdentity,
    requestLogout, logout, context, personName, adminSchools, setupMode } = useManagementConsole();

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
