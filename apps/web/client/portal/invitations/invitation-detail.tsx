import { useEffect, useRef } from 'react';
import { ArrowRight, ChevronRight, RefreshCw, Send } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Skeleton } from '../../components/ui/skeleton';
import { invitationCodeMessage } from '../../invitation-model';
import { roleNames } from '../access/access-controller';
import { portalSections } from '../pages';
import { CopyButton } from './copy-button';
import { formatDateTime, invitationStatusLabels, isActionable } from './invitations-model';
import type { InvitationsState } from './use-invitations';

/** Handing over: the issued code, shown once, copied only on explicit request. */
function IssuedReceipt({ state }: { state: InvitationsState }) {
  const issued = state.issued!, { school } = state.context;
  const expiry = formatDateTime(issued.expiresAt, school.timeZone);
  return <section className="invitation-receipt" aria-labelledby="invitation-receipt-title">
    <div className="invitation-receipt-head"><h2 id="invitation-receipt-title">Code émis</h2><Badge variant="secondary">Affiché une seule fois</Badge></div>
    <p className="invitation-code" aria-label={`Code ${issued.code.split('').join(' ')}`}>{issued.code}</p>
    <p className="invitation-receipt-expiry">Valable jusqu’au {expiry}, à usage unique.</p>
    <div className="invitation-receipt-actions">
      <CopyButton value={issued.code} label="Copier le code" variant="default" />
      <CopyButton value={invitationCodeMessage(issued.code, expiry, school.name)} label="Copier le message" />
    </div>
  </section>;
}

/** Follow-up of one invitation: its state, its expiry and what can still be done with it. */
export function InvitationDetail({ state }: { state: InvitationsState }) {
  const { school, navigate } = state.context;
  const current = state.current, heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { heading.current?.focus({ preventScroll: true }); }, [state.selected]);
  const crumb = <nav className="access-breadcrumb" aria-label="Fil d’Ariane"><button type="button" onClick={state.backToList}>{state.team ? 'Invitations de l’équipe' : 'Invitations élèves'}</button>
    <ChevronRight aria-hidden="true" /><span aria-current="page">{current ? state.labelOf(current) : 'Invitation'}</span></nav>;
  if (!current) {
    // The school just confirmed this invitation; its list is being read again.
    const waiting = state.issued?.invitationId === state.selected;
    return <section className="invitation-page">{crumb}
      <header className="invitation-heading"><h1 ref={heading} tabIndex={-1}>Invitation</h1></header>
      {waiting ? <><div role="status" aria-label="Lecture de l’invitation"><Skeleton className="h-10 w-64" /></div><IssuedReceipt state={state} /></>
        : state.loaded.status === 'ready' ? <Alert variant="destructive"><AlertTitle>Invitation non disponible</AlertTitle>
          <AlertDescription>Cette invitation n’est pas présente dans la liste lue avec vos accès actuels.</AlertDescription>
          <div className="invitation-alert-actions"><Button variant="outline" onClick={state.backToList}>Retour aux invitations</Button></div></Alert>
          : <div role="status" aria-label="Lecture de l’invitation"><Skeleton className="h-10 w-64" /></div>}
    </section>;
  }
  const actionable = isActionable(current), code = current.delivery === 'CODE';
  const available = code ? state.codeAvailable : state.emailAvailable;
  const waiting = state.pendingLabel(current.id);
  const target = state.team ? 'equipe' : 'eleves';
  return <section className="invitation-page">{crumb}
    <header className="invitation-heading">
      <div><h1 ref={heading} tabIndex={-1}>{state.labelOf(current)}</h1>
        <p className="invitation-state">{waiting ? waiting : current.status === 'EXPIRED' || current.status === 'REVOKED' ? <Badge variant="secondary">{invitationStatusLabels[current.status]}</Badge> : invitationStatusLabels[current.status]}</p></div>
      {actionable && state.active && <div className="invitation-actions">
        {available && <Button variant="outline" disabled={!state.canWrite} onClick={() => state.ask('renew')}>{code ? <RefreshCw aria-hidden="true" /> : <Send aria-hidden="true" />}{code ? 'Nouveau code' : 'Renvoyer l’invitation'}</Button>}
        <Button variant="destructive" disabled={!state.canWrite} onClick={() => state.ask('revoke')}>Révoquer…</Button></div>}
    </header>
    {state.runner.outcome && !state.dialog && !(state.issued && state.runner.outcome.tone === 'success') && <Alert variant={state.runner.outcome.tone === 'error' ? 'destructive' : 'default'}><AlertTitle>{state.runner.outcome.title}</AlertTitle><AlertDescription>{state.runner.outcome.message}</AlertDescription></Alert>}
    {state.runner.blockedReason && <Alert><AlertTitle>Confirmation en attente</AlertTitle><AlertDescription>{state.runner.blockedReason}</AlertDescription></Alert>}
    {state.codeMissing && <Alert variant="destructive"><AlertTitle>Code non affiché</AlertTitle><AlertDescription>La réponse de l’école ne permet pas d’afficher le code. « Nouveau code » en crée un autre.</AlertDescription></Alert>}
    {state.issued?.invitationId === current.id && <IssuedReceipt state={state} />}
    <dl className="invitation-facts">
      <div><dt>Type</dt><dd>{code ? 'Code élève' : 'Invitation par e-mail'}</dd></div>
      {!code && current.maskedEmail && <div><dt>Adresse</dt><dd>{current.maskedEmail}</dd></div>}
      {state.team && <div><dt>Rôles</dt><dd>{roleNames(current.roles)}</dd></div>}
      <div><dt>Expiration</dt><dd><time dateTime={current.expiresAt}>{formatDateTime(current.expiresAt, school.timeZone)}</time></dd></div>
      {state.references.has(current.id) && <div><dt>Référence</dt><dd>{state.references.get(current.id)}</dd></div>}
    </dl>
    {current.status === 'ACCEPTED' && portalSections.includes(target) && <div><Button variant="outline" onClick={() => navigate(target)}>{state.team ? 'Ouvrir l’équipe' : 'Ouvrir les dossiers élèves'}<ArrowRight data-icon="inline-end" aria-hidden="true" /></Button></div>}
  </section>;
}
