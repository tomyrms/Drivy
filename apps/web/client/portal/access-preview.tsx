import { createRoot } from 'react-dom/client';
import { Suspense, useMemo, useState } from 'react';
import { z } from 'zod';
import { ConsoleContext, type ConsoleContextValue } from '../console/context';
import { ScopedReadCache } from '../console/load-model';
import { commandStore } from '../command-store';
import { PortalFrame } from './frame';
import { AccessPilot } from './access/access-page';
import { portalPages, portalSections } from './pages';
import { PortalPreferencesPage } from './account/preferences-page';
import { Button } from '../components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../components/ui/dialog';
import { Skeleton } from '../components/ui/skeleton';
import { PortalSelect } from './components/portal-select';
import { PortalPendingRequests } from './runtime/pending-requests';
import { PortalSettingsSearch, PortalSettingsFocus } from './settings/settings-search';
import { usePreviewNavigation } from './preview/use-preview-navigation';
import { ids, previewMe, previewMembership, previewSchool } from './preview/fixtures';
import { memberSchema, readSchool } from '../school-api';
import { installPreviewTransport, setPreviewScenario, type PreviewScenario } from './preview/transport';
import './portal.css';

declare const __DRIVY_PREVIEW_SHA__: string;
z.config({ jitless: true });
installPreviewTransport();
commandStore.scopeToPerson(ids.person);
commandStore.scopeToAccess(ids.school, ids.admin, 1);
// The first published link (no page parameter) keeps opening the access editor directly.
const isFirstLink = () => !new URLSearchParams(location.search).has('page') && new URLSearchParams(location.search).get('mode') !== 'read';
const scenarios = [
  { value: 'normal', label: 'Enregistrement normal' }, { value: 'refused', label: 'Refus de la modification' },
  { value: 'slow', label: 'Enregistrement lent' }, { value: 'lost-reply', label: 'Réponse perdue' }, { value: 'conflict', label: 'Conflit de version' },
];

function Preview() {
  const navigation = usePreviewNavigation();
  const { route } = navigation;
  const Page = portalPages[route.page] ?? portalPages.equipe!;
  const [scenario, setScenario] = useState<PreviewScenario>('normal');
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [membership, setMembership] = useState(previewMembership);
  const drafts = useMemo(() => new Map<string, unknown>(), []);
  const cache = useMemo(() => new ScopedReadCache(), []);
  const value: ConsoleContextValue = {
    schoolId: ids.school, school: previewSchool, me: previewMe, membership, canConfigureCatalog: membership.grants.includes('CONFIGURE_CATALOG'),
    csrf: () => 'synthetic-preview', refreshCsrf: async () => 'synthetic-preview', reloadSchool: async () => {
      const current = await readSchool(ids.school, `members/${ids.admin}`, memberSchema);
      commandStore.scopeToAccess(ids.school, ids.admin, current.accessEpoch);
      setMembership({ ...membership, roles: current.roles, grants: current.grants, accessEpoch: current.accessEpoch });
    },
    navigate: navigation.navigate, setRouteQuery: navigation.setRouteQuery, routeQuery: route.query, drafts, readCache: cache,
    registerUnsavedChanges: navigation.registerUnsavedChanges, confirmNavigation: navigation.confirmNavigation,
    setNavigationGuard: navigation.setNavigationGuard, login: () => {}, confirmIdentity: async () => true,
  };
  return <ConsoleContext.Provider value={value}><PortalFrame search={<PortalSettingsSearch />} active={route.page} activeQuery={route.query} available={portalSections} onNavigate={(section, query) => navigation.navigate(section, query)} schoolName={previewSchool.name} userName={previewMe.displayName} preview={{ build: __DRIVY_PREVIEW_SHA__ }}
    account={{ onPreferences: () => navigation.confirmNavigation(() => location.assign('?page=preferences')), onLogout: () => navigation.confirmNavigation(() => { commandStore.clear(); location.reload(); }) }}>
    <PortalPendingRequests />
    <PortalSettingsFocus target={route.query.focus} navigationKey={`${route.page}:${JSON.stringify(route.query)}`} />
    <Suspense fallback={<div className="grid gap-5" aria-label="Chargement de la page" role="status"><Skeleton className="h-10 w-56" /><Skeleton className="h-80 w-full" /></div>}>
      {route.page === 'equipe' && isFirstLink() ? <AccessPilot initialEdit /> : <Page />}
    </Suspense>
    <div className="preview-controls"><span>Aperçu interactif · aucun compte réel</span><Button variant="ghost" onClick={() => setSettingsOpen(true)}>Scénario d’essai</Button><Button variant="ghost" onClick={() => navigation.confirmNavigation(() => { commandStore.clear(); location.reload(); })}>Réinitialiser</Button></div>
    <Dialog open={navigation.departure !== null} onOpenChange={open => { if (!open) navigation.cancelDeparture(); }}><DialogContent>
      <DialogHeader><DialogTitle>Quitter sans enregistrer ?</DialogTitle><DialogDescription>Vos modifications ne sont pas encore enregistrées.</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={navigation.cancelDeparture}>Continuer la saisie</Button><Button onClick={navigation.leave}>Quitter la page</Button></DialogFooter>
    </DialogContent></Dialog>
    <Dialog open={settingsOpen} onOpenChange={setSettingsOpen}><DialogContent>
      <DialogHeader><DialogTitle>Scénario d’essai</DialogTitle><DialogDescription>Ces situations concernent uniquement les données fictives de cet aperçu.</DialogDescription></DialogHeader>
      <PortalSelect id="preview-scenario" label="Prochain enregistrement" options={scenarios} value={scenario} onValueChange={value => { if (value) { setScenario(value as PreviewScenario); setPreviewScenario(value as PreviewScenario); } }} />
      <DialogFooter><Button onClick={() => setSettingsOpen(false)}>Appliquer au prochain essai</Button></DialogFooter>
    </DialogContent></Dialog>
  </PortalFrame></ConsoleContext.Provider>;
}
// Personal preferences live outside the school console, as in the real application.
createRoot(document.getElementById('root')!).render(new URLSearchParams(location.search).get('page') === 'preferences'
  ? <PortalPreferencesPage back="?page=agenda" /> : <Preview />);
