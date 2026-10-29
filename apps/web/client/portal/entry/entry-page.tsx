import { CircleAlert, Loader2, RefreshCw, TriangleAlert } from 'lucide-react';
import type { InvitationLink } from '../../invitation-link';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button, buttonVariants } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { entryPageFromPath, entryRoutes, type EntryPageKind, type EntryRoutes } from './entry-model';
import { useEntrySession } from './use-entry-session';
import { EntryFrame } from './entry-frame';
import { AccountEntryPanel } from './account-entry-panel';
import { SchoolsView } from './schools-view';
import { InvitationView } from './invitation-view';

/**
 * `/app` and `/app/invitation` with the rebuilt presentation (#319): sign-in, code and account creation, linked
 * schools, account without school, received invitation and its uncertain result. The invitation link was already
 * taken out of the address by `main.tsx`; it lives only in `invitationLink`, sent once to the BFF.
 */
export function PortalEntryPage({ invitationLink, page = entryPageFromPath(window.location.pathname), routes = entryRoutes }: {
  invitationLink: InvitationLink; page?: EntryPageKind; routes?: EntryRoutes;
}) {
  const state = useEntrySession({ invitationLink, initialPage: page, routes });
  const busy = state.busy !== null;
  const invitationClosed = state.page === 'invitation' && (state.linkMustReopen || state.linkError);
  const showHeading = state.authenticated || invitationClosed;
  return <EntryFrame home={routes.account} width={state.authenticated ? 'wide' : 'narrow'} busy={!state.loaded}
    account={state.authenticated ? { name: state.personName, preferences: routes.preferences, busy, onLogout: state.logout } : null}>
    {showHeading && <header className="entry-heading">
      {state.page === 'account' && state.authenticated && <p className="entry-eyebrow">{state.personName}</p>}
      <h1 ref={state.heading} tabIndex={-1}>{state.page === 'invitation' ? 'Rejoindre une école' : 'Vos écoles'}</h1>
    </header>}

    <p className="entry-busy" role="status">{busy && state.loaded && <><Loader2 className="entry-spin" aria-hidden="true" />{state.busy}</>}</p>

    {state.error && <Alert variant="destructive">
      <CircleAlert aria-hidden="true" />
      <AlertTitle>{state.error}</AlertTitle>
      {state.uncertain && <AlertDescription>La réponse à votre acceptation n’est pas encore connue. Réessayer conserve la même demande : ne demandez pas de nouvelle invitation pour la remplacer.</AlertDescription>}
      {(!state.uncertain || !state.preview) && <div className="entry-alert-actions">
        <Button variant="outline" disabled={busy} onClick={() => state.refresh()}><RefreshCw aria-hidden="true" />{state.uncertain ? 'Retrouver la demande' : 'Réessayer'}</Button>
      </div>}
    </Alert>}

    {state.linkMustReopen && <Alert className="entry-warning">
      <TriangleAlert aria-hidden="true" />
      <AlertTitle>Reprendre votre invitation</AlertTitle>
      <AlertDescription>Connectez-vous avec le compte invité, puis reprenez le code ou le lien envoyé par votre école.</AlertDescription>
    </Alert>}

    {invitationClosed && !state.authenticated && state.loaded && <a className={buttonVariants({ size: 'lg' })} href={routes.account}>Se connecter</a>}

    {!state.loaded && <div className="entry-loading" role="status" aria-label={state.busy ?? 'Chargement'}>
      <Skeleton className="h-9 w-2/3" /><Skeleton className="h-48 w-full" /><Skeleton className="h-12 w-full" />
    </div>}

    {state.loaded && !state.authenticated && state.page === 'account' && <AccountEntryPanel routes={routes} onSignedIn={state.signedIn} />}
    {state.loaded && !state.authenticated && state.page === 'invitation' && !invitationClosed && <AccountEntryPanel routes={routes} invitation onSignedIn={state.signedIn} />}
    {state.loaded && state.authenticated && state.page === 'invitation' && <InvitationView state={state} routes={routes} />}
    {state.loaded && state.authenticated && state.page === 'account' && <SchoolsView state={state} routes={routes} />}
  </EntryFrame>;
}
