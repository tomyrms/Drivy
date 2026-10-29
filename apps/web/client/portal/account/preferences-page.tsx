import { useEffect, useId, useState, useSyncExternalStore } from 'react';
import { ArrowLeft, ChevronRight, KeyRound, Monitor, Moon, School, Sun } from 'lucide-react';
import { meSchema, request, RequestFailure, sessionSchema } from '../../protocol';
import { load, notificationKeys, saveNotificationPreferences } from '../../notification-preferences-model';
import { NotificationPreferenceStore } from '../../notification-preferences-store';
import { useTheme, type ThemePreference } from '../../theme';
import { BrandSymbol } from '../../BrandSymbol';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Label } from '../../components/ui/label';
import { RadioGroup, RadioGroupItem } from '../../components/ui/radio-group';
import { Skeleton } from '../../components/ui/skeleton';
import { Switch } from '../../components/ui/switch';
import '../portal.css';
import './account.css';

const themes: readonly { value: ThemePreference; label: string; icon: typeof Sun }[] = [
  { value: 'system', label: 'Système', icon: Monitor }, { value: 'light', label: 'Clair', icon: Sun }, { value: 'dark', label: 'Sombre', icon: Moon },
];

/** Only an internal console address may be offered as the way back. */
export function preferencesReturn(search: string): string {
  const requested = new URLSearchParams(search).get('returnTo') ?? '';
  return /^\/app\/gestion\/[\da-f-]{36}\/[a-z-]+(?:\?[^#]*)?$/i.test(requested) ? requested : '/app/';
}

/** Personal preferences (#333): appearance, notification choices, account and help. Nothing school-scoped is read here. */
export function PortalPreferencesPage({ back = preferencesReturn(window.location.search) }: { back?: string }) {
  const theme = useTheme();
  const uid = useId();
  useEffect(() => { document.title = 'Préférences personnelles · Drivy'; }, []);
  return <div className="portal-app">
    <a className="portal-skip-link" href="#portal-content">Aller au contenu</a>
    <header className="portal-topbar"><a className="portal-brand" href="/app/" aria-label="Drivy, mon compte"><BrandSymbol /><span>Drivy</span></a></header>
    <main id="portal-content" tabIndex={-1} className="account-page">
      <Button variant="ghost" size="sm" className="account-back" onClick={() => window.location.assign(back)}><ArrowLeft aria-hidden="true" />{back === '/app/' ? 'Mon compte' : 'Retour à l’école'}</Button>
      <h1>Préférences personnelles</h1>

      <section className="account-section" aria-labelledby={`${uid}-display`}>
        <h2 id={`${uid}-display`}>Affichage</h2>
        <RadioGroup value={theme.preference} onValueChange={value => theme.setTheme(value as ThemePreference)} aria-labelledby={`${uid}-display`} className="account-themes">
          {themes.map(option => <Label key={option.value} htmlFor={`${uid}-theme-${option.value}`} className="account-theme">
            <RadioGroupItem id={`${uid}-theme-${option.value}`} value={option.value} /><option.icon aria-hidden="true" />{option.label}
          </Label>)}
        </RadioGroup>
        {theme.storageError && <p className="account-muted" role="status">Ce choix ne sera pas conservé sur cet appareil.</p>}
      </section>

      <NotificationsSection />

      <section className="account-section" aria-labelledby={`${uid}-help`}>
        <h2 id={`${uid}-help`}>Compte et aide</h2>
        <ul className="account-links">
          <li><a href="/app/"><School aria-hidden="true" /><span>Mon compte et mes écoles</span><ChevronRight aria-hidden="true" /></a></li>
          <li><a href="/app/recover"><KeyRound aria-hidden="true" /><span>Récupérer mon accès</span><ChevronRight aria-hidden="true" /></a></li>
        </ul>
        <Collapsible className="account-disclosure">
          <CollapsibleTrigger render={<Button variant="ghost" className="account-disclosure-trigger" />}>Contacter mon école<ChevronRight aria-hidden="true" /></CollapsibleTrigger>
          <CollapsibleContent><p className="account-muted">Retrouvez les coordonnées de votre école dans votre invitation ou dans l’app Drivy.</p></CollapsibleContent>
        </Collapsible>
      </section>
    </main>
  </div>;
}

function NotificationsSection() {
  const uid = useId();
  const [store] = useState(() => new NotificationPreferenceStore({
    read: async () => {
      const me = (await request('me', meSchema)).data;
      return { personId: me.personId, value: await load() };
    },
    write: async (personId, choices, version) => {
      const session = await request('session', sessionSchema);
      if (!session.authenticated) throw new RequestFailure('SESSION_EXPIRED', 401);
      const me = (await request('me', meSchema)).data;
      if (me.personId !== personId) return { ok: false, conflict: false, kind: 'contextChanged' };
      return saveNotificationPreferences(choices, version, session.csrfToken);
    },
  }));
  const state = useSyncExternalStore(store.subscribe, store.getSnapshot);
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    void store.refresh();
    const resume = () => { if (document.visibilityState === 'visible') void store.refresh(); };
    const pageShow = () => void store.refresh();
    const pageHide = () => store.clear();
    const beforeUnload = (event: BeforeUnloadEvent) => {
      if (store.getSnapshot().pendingKeys.length) { event.preventDefault(); event.returnValue = ''; }
    };
    document.addEventListener('visibilitychange', resume);
    window.addEventListener('online', pageShow);
    window.addEventListener('pageshow', pageShow);
    window.addEventListener('pagehide', pageHide);
    window.addEventListener('beforeunload', beforeUnload);
    return () => {
      document.removeEventListener('visibilitychange', resume);
      window.removeEventListener('online', pageShow);
      window.removeEventListener('pageshow', pageShow);
      window.removeEventListener('pagehide', pageHide);
      window.removeEventListener('beforeunload', beforeUnload);
      store.clear();
    };
  }, [store]);
  useEffect(() => {
    setSlow(false);
    if (state.phase !== 'saving') return;
    const timer = window.setTimeout(() => setSlow(true), 5_000);
    return () => window.clearTimeout(timer);
  }, [state.phase]);

  return <section className="account-section" aria-labelledby={`${uid}-notifications`}>
    <h2 id={`${uid}-notifications`}>Notifications</h2>
    {state.phase === 'loading' && !state.value && <div className="grid gap-3" role="status" aria-label="Chargement des préférences"><Skeleton className="h-11 w-full" /><Skeleton className="h-11 w-full" /></div>}
    {state.value && <ul className="account-switches">
      {notificationKeys.map(item => <li key={item.key}>
        <Label htmlFor={`${uid}-${item.key}`}>{item.label}{state.pendingKeys.includes(item.key) && <span className="sr-only"> · Choix en attente de confirmation</span>}</Label>
        <Switch id={`${uid}-${item.key}`} checked={state.value![item.key]} onCheckedChange={value => store.choose(item.key, value)} />
      </li>)}
    </ul>}
    {state.message && <Alert variant={state.phase === 'uncertain' || state.phase === 'conflict' ? 'default' : 'destructive'}>
      <AlertTitle>{state.message}</AlertTitle>
      {state.phase === 'uncertain' && <AlertDescription><span className="account-actions">
        <Button variant="outline" onClick={() => void store.refresh()}>Vérifier</Button>
        <Button variant="ghost" onClick={() => void store.retry()}>Renvoyer les mêmes choix</Button></span></AlertDescription>}
      {state.phase === 'conflict' && <AlertDescription><span className="account-actions">
        <Button variant="outline" onClick={() => void store.retry()}>Appliquer mes choix</Button>
        <Button variant="ghost" onClick={() => store.useConfirmed()}>Garder les choix actuels</Button></span></AlertDescription>}
      {(state.phase === 'unavailable' || state.phase === 'rejected') && <AlertDescription><span className="account-actions">
        <Button variant="outline" onClick={() => void store.refresh()}>Réessayer</Button></span></AlertDescription>}
    </Alert>}
    {slow && <p className="account-muted" role="status">Synchronisation en cours…</p>}
    <p className="sr-only" role="status">{state.phase === 'saving' ? 'Choix en cours de synchronisation.' : state.phase === 'ready' && state.value ? 'Préférences synchronisées.' : ''}</p>
  </section>;
}
