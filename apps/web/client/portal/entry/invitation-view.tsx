import { useId } from 'react';
import { Building2, Loader2, MailWarning, School } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Badge } from '../../components/ui/badge';
import { Button, buttonVariants } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from '../../components/ui/empty';
import { Field, FieldLabel } from '../../components/ui/field';
import { formatInvitationDate, personInitials, rolesLabel, type EntryRoutes } from './entry-model';
import type { EntrySessionState } from './use-entry-session';

/**
 * Received invitation of a signed-in person (#319): the account used, the school, roles and complete texts, then an
 * explicit confirmation. An unknown result keeps the same request and blocks closing or switching account.
 */
export function InvitationView({ state, routes }: { state: EntrySessionState; routes: EntryRoutes }) {
  const uid = useId();
  const busy = state.busy !== null;
  const preview = state.preview?.data;
  const user = state.session?.user;
  return <>
    <section className="entry-identity" aria-labelledby={`${uid}-identity`}>
      <Avatar size="lg" aria-hidden="true"><AvatarFallback>{personInitials(state.personName) || 'D'}</AvatarFallback></Avatar>
      <div className="entry-identity-text">
        <h2 id={`${uid}-identity`}>Compte utilisé</h2>
        <strong>{state.personName}</strong>
        {user?.email && <span>{user.email}</span>}
      </div>
      {state.emailVerificationRequired && <Badge variant="outline" className="entry-badge-warning"><MailWarning aria-hidden="true" />Adresse à vérifier</Badge>}
      <Button variant="ghost" className="entry-identity-action" disabled={busy || state.uncertain} onClick={state.logout}>Changer de compte</Button>
    </section>
    {state.emailVerificationRequired && <Alert className="entry-warning" id={`${uid}-verify`}>
      <MailWarning aria-hidden="true" />
      <AlertTitle>Adresse à vérifier</AlertTitle>
      <AlertDescription>Vérifiez votre adresse auprès du service de connexion, puis reconnectez-vous avant d’accepter l’invitation.</AlertDescription>
    </Alert>}

    {preview && <section className="entry-invitation" aria-labelledby={`${uid}-school`}>
      <header className="entry-invitation-head">
        <span className="entry-icon-tile entry-icon-accent"><School aria-hidden="true" /></span>
        <h2 id={`${uid}-school`}>{preview.schoolName}</h2>
      </header>
      <dl className="entry-facts">
        {preview.profileIdentity && <div><dt>Identité du compte</dt><dd>{preview.profileIdentity.firstName} {preview.profileIdentity.lastName}</dd></div>}
        <div><dt>Votre rôle</dt><dd>{rolesLabel(preview.roles)}</dd></div>
        {preview.maskedEmail && <div><dt>Invitation envoyée à</dt><dd>{preview.maskedEmail}</dd></div>}
        <div><dt>Valable jusqu’au</dt><dd><time dateTime={preview.expiresAt}>{formatInvitationDate(preview.expiresAt)}</time></dd></div>
      </dl>
      <div className="entry-policy">
        <h3>Vos données dans cette école</h3>
        <p>{preview.notice.noticeText}</p>
        <h3>Conservation des données</h3>
        <p>{preview.notice.retentionText}</p>
        <p className="entry-muted">Pour toute question : <a href={`mailto:${preview.notice.contactEmail}`}>{preview.notice.contactEmail}</a></p>
      </div>
      <div className="entry-acceptance">
        <Field orientation="horizontal" className="entry-confirmation" data-disabled={busy}>
          <Checkbox id={`${uid}-confirm`} checked={state.reviewed} disabled={busy} onCheckedChange={value => state.setReviewed(value === true)} />
          <FieldLabel htmlFor={`${uid}-confirm`}><span>Je confirme rejoindre <strong>{preview.schoolName}</strong> avec le compte indiqué ci-dessus.</span></FieldLabel>
        </Field>
        <p className="entry-muted">Ce rattachement ne réserve aucune leçon et n’autorise aucun enregistrement GPS.</p>
        {state.uncertain && <p className="entry-muted">Vérifiez d’abord le résultat de la demande déjà envoyée avant de fermer cette invitation.</p>}
        <div className="entry-actions">
          <Button size="lg" disabled={busy || !state.canAccept} focusableWhenDisabled onClick={state.acceptInvitation}
            aria-describedby={state.emailVerificationRequired ? `${uid}-verify` : !state.reviewed ? `${uid}-hint` : undefined}>
            {state.busy === 'Confirmation par votre école…' && <Loader2 className="entry-spin" aria-hidden="true" />}
            {state.uncertain ? 'Vérifier et réessayer' : 'Rejoindre cette école'}
          </Button>
          <Button variant="outline" size="lg" disabled={busy || state.uncertain} onClick={state.clearInvitation}>Pas maintenant</Button>
        </div>
        <p id={`${uid}-hint`} className="sr-only">Cochez la confirmation pour rejoindre l’école.</p>
      </div>
    </section>}

    {!preview && !busy && !state.error && <Empty className="entry-empty">
      <EmptyHeader>
        <EmptyMedia variant="icon"><Building2 aria-hidden="true" /></EmptyMedia>
        <EmptyTitle>Aucune invitation à afficher</EmptyTitle>
        <EmptyDescription>Ouvrez le lien le plus récent envoyé par votre école.</EmptyDescription>
      </EmptyHeader>
      <EmptyContent><a className={buttonVariants({ variant: 'outline' })} href={routes.account}>Voir mes écoles</a></EmptyContent>
    </Empty>}
  </>;
}
