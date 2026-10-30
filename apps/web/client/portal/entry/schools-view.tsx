import { useId } from 'react';
import { ArrowRight, Building2, CircleCheck, KeyRound, Mail, RefreshCw } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button, buttonVariants } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Skeleton } from '../../components/ui/skeleton';
import { managesSchool, rolesLabel, schoolsHeading, type EntryRoutes } from './entry-model';
import { SignedInCodePanel } from './account-entry-panel';
import type { EntrySessionState } from './use-entry-session';

/** Linked schools of the signed-in person, a pending invitation and the receipt of an acceptance (#319). */
export function SchoolsView({ state, routes }: { state: EntrySessionState; routes: EntryRoutes }) {
  const uid = useId();
  const busy = state.busy !== null;
  const memberships = state.me?.memberships ?? [];
  const empty = memberships.length === 0 && !busy && !state.error && !state.enteringCode;
  return <>
    {state.accepted && <Alert className="entry-success" role="status">
      <CircleCheck aria-hidden="true" />
      <AlertTitle>Vous avez rejoint {state.accepted.schoolName}</AlertTitle>
      {!managesSchool(state.accepted) && <AlertDescription>Retrouvez votre école dans l’app Drivy en vous connectant avec ce compte.</AlertDescription>}
    </Alert>}

    {state.session?.invitationPending && <section className="entry-pending" aria-labelledby={`${uid}-pending`}>
      <span className="entry-icon-tile entry-icon-accent"><Mail aria-hidden="true" /></span>
      <h2 id={`${uid}-pending`}>Une école vous invite</h2>
      <a className={buttonVariants()} href={routes.invitation}>Voir l’invitation</a>
    </section>}

    <section className="entry-section" aria-labelledby={`${uid}-schools`}>
      <div className="entry-section-head">
        <h2 id={`${uid}-schools`}>{schoolsHeading(state.me)}</h2>
        {!empty && <div className="entry-head-actions">
          {!state.enteringCode && <Button variant="outline" disabled={busy} onClick={() => state.setEnteringCode(true)}><KeyRound aria-hidden="true" />J’ai un code</Button>}
          <Button variant="ghost" disabled={busy} onClick={() => state.refresh('Actualisation de vos écoles…')}><RefreshCw aria-hidden="true" />Actualiser</Button>
        </div>}
      </div>
      {state.enteringCode && <SignedInCodePanel onSignedIn={state.signedIn} onCancel={() => state.setEnteringCode(false)} />}
      {memberships.length > 0
        ? <ul className="entry-school-list">{memberships.map(member => <li key={member.membershipId}>
            <span className="entry-icon-tile"><Building2 aria-hidden="true" /></span>
            <span className="entry-school-text"><strong>{member.schoolName}</strong><span>{rolesLabel(member.roles)}</span></span>
            {managesSchool(member) && <a className={buttonVariants({ variant: 'outline', size: 'sm' })} href={routes.school(member.schoolId)} aria-label={`Ouvrir l’école ${member.schoolName}`}>
              Ouvrir l’école<ArrowRight aria-hidden="true" /></a>}
          </li>)}</ul>
        : empty
          ? <Empty className="entry-empty">
              <EmptyHeader>
                <EmptyMedia variant="icon"><Building2 aria-hidden="true" /></EmptyMedia>
                <EmptyTitle>Votre école n’apparaît pas encore</EmptyTitle>
                <EmptyDescription>Saisissez le code reçu, ou ouvrez le lien envoyé par votre école.</EmptyDescription>
              </EmptyHeader>
              <EmptyContent className="entry-empty-actions">
                <Button onClick={() => state.setEnteringCode(true)}><KeyRound aria-hidden="true" />J’ai un code</Button>
                <Button variant="outline" onClick={() => state.refresh('Actualisation de vos écoles…')}><RefreshCw aria-hidden="true" />Actualiser</Button>
              </EmptyContent>
            </Empty>
          : busy
            ? <div className="entry-school-skeleton" aria-hidden="true"><Skeleton className="h-16 w-full" /><Skeleton className="h-16 w-full" /></div>
            : !state.enteringCode && <p className="entry-muted">Vos écoles ne peuvent pas être affichées pour le moment.</p>}
    </section>
  </>;
}
