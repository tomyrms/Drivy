import { Suspense, type ReactNode } from 'react';
import { ArrowRight, Building2, RefreshCw } from 'lucide-react';
import { useManagementConsole } from '../console/management-runtime';
import { ConsoleContext } from '../console/context';
import { sectionTitles } from '../console/navigation';
import { roleLabel } from '../protocol';
import { UiSuspendedContext } from '../ui-suspension';
import { BrandSymbol } from '../BrandSymbol';
import { Alert, AlertDescription, AlertTitle } from '../components/ui/alert';
import { Button } from '../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../components/ui/dialog';
import { Skeleton } from '../components/ui/skeleton';
import { PortalFrame } from './frame';
import { portalPages, portalSections } from './pages';
import { PortalPendingRequests } from './runtime/pending-requests';
import { PortalIdentityDialog } from './runtime/identity-dialog';
import { NotRebuilt } from './components/not-rebuilt';
import { PortalSettingsSearch, PortalSettingsFocus } from './settings/settings-search';
import './portal.css';

function EntryLayout({ children }: { children: ReactNode }) {
  return <div className="portal-app">
    <header className="portal-topbar"><a className="portal-brand" href="/app/" aria-label="Drivy, mes écoles"><BrandSymbol /><span>Drivy</span></a></header>
    <main className="portal-entry">{children}</main>
  </div>;
}

function Loading({ label }: { label: string }) {
  return <div className="grid gap-5" role="status" aria-label={label}><Skeleton className="h-10 w-56" /><Skeleton className="h-80 w-full" /></div>;
}

/** Authenticated console with the rebuilt presentation: same runtime, store, guards and URLs as the historical console. */
export function PortalConsole() {
  const runtime = useManagementConsole();
  const { route, state, context, resumeGate, busy } = runtime;

  if (state.status !== 'ready' || !context) return <EntryLayout>
    {state.status === 'loading' && <Loading label="Ouverture de la gestion de l’école…" />}
    {state.status === 'error' && <Alert variant="destructive"><AlertTitle>La gestion ne peut pas s’ouvrir</AlertTitle><AlertDescription>{state.message}</AlertDescription>
      <Button variant="outline" onClick={() => void runtime.load(route.schoolId)}><RefreshCw aria-hidden="true" />Réessayer</Button></Alert>}
    {state.status === 'signin' && <section className="portal-entry-card">
      <h1 tabIndex={-1} ref={heading => heading?.focus()}>Connexion requise</h1>
      {runtime.snapshot.entries.size > 0 && <Alert><AlertTitle>Une demande reste à vérifier</AlertTitle><AlertDescription>Après connexion, ouvrez la même école pour consulter son résultat.</AlertDescription></Alert>}
      <Button onClick={() => window.location.assign('/app/')}>Se connecter</Button>
    </section>}
    {state.status === 'choose' && <section className="portal-entry-card">
      <h1 tabIndex={-1} ref={heading => heading?.focus()}>Choisir une école</h1>
      <ul className="portal-school-list">{state.admin.map(member => <li key={member.schoolId}>
        <Button variant="ghost" onClick={() => { runtime.pushPath(`/app/gestion/${member.schoolId}`); runtime.setRoute({ schoolId: member.schoolId, section: 'apercu', query: {} }); }}>
          <Building2 aria-hidden="true" /><span><strong>{member.schoolName}</strong><span>{member.roles.map(roleLabel).join(' · ')}</span></span><ArrowRight aria-hidden="true" />
        </Button></li>)}</ul>
    </section>}
    {state.status === 'denied' && <section className="portal-entry-card">
      <h1 tabIndex={-1} ref={heading => heading?.focus()}>Accès à la gestion refusé</h1>
      <p>{state.membership ? `Votre accès dans ${state.membership.schoolName} : ${state.membership.roles.map(roleLabel).join(' · ')}. La gestion de l’école demande le rôle Administration.` : 'Ce compte n’administre aucune école.'}</p>
      <Button variant="outline" onClick={() => window.location.assign('/app/')}>Retrouver mes écoles</Button>
    </section>}
  </EntryLayout>;

  const Page = portalPages[route.section];
  const setup = runtime.setupMode;
  const pageKey = `${runtime.draftScope}-${route.section}-${route.section === 'invitations' ? route.query.audience ?? 'learners' : route.section === 'apercu' ? route.query.from ?? '' : ''}`;
  return <UiSuspendedContext.Provider value={resumeGate !== null}>
    <ConsoleContext.Provider value={context}>
      <PortalFrame active={route.section} activeQuery={route.query} available={portalSections}
        search={<PortalSettingsSearch />}
        onNavigate={(section, query) => context.navigate(section, query)}
        schoolName={state.school.name} userName={runtime.personName ?? 'Mon compte'}
        schools={runtime.adminSchools.map(member => ({ id: member.schoolId, name: member.schoolName }))} currentSchoolId={state.membership.schoolId}
        onSchoolChange={schoolId => runtime.proceedNavigation(() => { runtime.pushPath(`/app/gestion/${schoolId}`); runtime.setRoute({ schoolId, section: 'apercu', query: {} }); })}
        account={{ busy, onPreferences: () => runtime.proceedNavigation(() => { runtime.unsaved.current.clear(); window.location.assign(`/app/preferences?returnTo=${encodeURIComponent(`${window.location.pathname}${window.location.search}`)}`); }),
          onLogout: () => runtime.proceedNavigation(runtime.requestLogout) }}>
        {resumeGate !== null && <div className="portal-resume-gate">{resumeGate === 'checking'
          ? <Loading label="Vérification de vos accès…" />
          : <Alert variant="destructive"><AlertTitle>Vos accès doivent être vérifiés</AlertTitle><AlertDescription>Votre saisie reste conservée tant que cette page reste ouverte.</AlertDescription>
              <Button onClick={() => void runtime.resumeCurrentAccess.current()}>Réessayer</Button></Alert>}</div>}
        <div hidden={resumeGate !== null} inert={resumeGate !== null}>
          {runtime.logoutError && <Alert variant="destructive"><AlertTitle>Déconnexion non confirmée</AlertTitle><AlertDescription>{runtime.logoutError}</AlertDescription></Alert>}
          <PortalPendingRequests />
          <PortalSettingsFocus target={route.query.focus} navigationKey={`${route.section}:${runtime.historyIndex.current}:${resumeGate ?? ''}`} />
          <Suspense fallback={<Loading label="Chargement de la page" />}>
            {Page && !setup ? <Page key={pageKey} /> : <NotRebuilt key={pageKey} title={sectionTitles[route.section]} />}
          </Suspense>
        </div>
      </PortalFrame>
      <Dialog open={runtime.logoutWarning} onOpenChange={open => { if (!open) runtime.setLogoutWarning(false); }}><DialogContent>
        <DialogHeader><DialogTitle>Se déconnecter avec une demande à vérifier ?</DialogTitle>
          <DialogDescription>Se déconnecter arrête le suivi d’une demande dont le résultat n’est pas encore connu.</DialogDescription></DialogHeader>
        <DialogFooter><Button variant="outline" disabled={busy} onClick={() => runtime.setLogoutWarning(false)}>Rester connecté</Button>
          <Button disabled={busy} onClick={() => { runtime.setLogoutWarning(false); void runtime.logout(); }}>Se déconnecter</Button></DialogFooter>
      </DialogContent></Dialog>
      <Dialog open={runtime.departure !== null} onOpenChange={open => { if (!open) runtime.setDeparture(null); }}><DialogContent>
        <DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Vos modifications ne sont pas enregistrées auprès de l’école.</DialogDescription></DialogHeader>
        <DialogFooter><Button variant="outline" onClick={() => runtime.setDeparture(null)}>Continuer la saisie</Button>
          <Button onClick={() => { const next = runtime.departure; runtime.setDeparture(null); runtime.bypassGuard.current = true; try { next?.proceed(); } finally { runtime.bypassGuard.current = false; } }}>Quitter la page</Button></DialogFooter>
      </DialogContent></Dialog>
      {runtime.identityDialog && <PortalIdentityDialog mode={runtime.identityDialog.mode} initialEmail={runtime.identityDialog.email}
        onCancel={() => runtime.finishIdentity(false)} onConfirmed={runtime.confirmedIdentity} />}
    </ConsoleContext.Provider>
  </UiSuspendedContext.Provider>;
}

