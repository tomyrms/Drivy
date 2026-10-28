import { useEffect, useRef } from 'react';
import { ChevronRight, KeyRound, Mail } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { portalSections } from '../pages';
import { CommandFeedback } from '../team/feedback';
import { InvitationDetail } from './invitation-detail';
import { InvitationDialogs } from './invitation-dialogs';
import { CodeForm, EmailForm } from './invitation-forms';
import { InvitationList } from './invitation-list';
import { useInvitations } from './use-invitations';
import './invitations.css';

/**
 * Invitations of the school for one audience (`audience=learners|team` in the URL, the selected invitation too).
 * Creating, handing over the issued code and following the state are three distinct views.
 */
export function InvitationsPilot() {
  const state = useInvitations();
  const heading = useRef<HTMLHeadingElement>(null);
  const title = state.team ? 'Invitations de l’équipe' : 'Invitations élèves';
  useEffect(() => { if (state.creating) heading.current?.focus({ preventScroll: true }); }, [state.creating]);
  const dialogs = <InvitationDialogs state={state} />;
  if (state.creating) return <section className="invitation-page">
    <nav className="access-breadcrumb" aria-label="Fil d’Ariane"><button type="button" onClick={state.backToList}>{title}</button><ChevronRight aria-hidden="true" /><span aria-current="page">{state.creating === 'code' ? 'Code élève' : 'Inviter par e-mail'}</span></nav>
    <header className="invitation-heading"><h1 ref={heading} tabIndex={-1}>{state.creating === 'code' ? 'Code élève' : 'Inviter par e-mail'}</h1></header>
    {state.runner.outcome && !state.dialog && <CommandFeedback runner={state.runner} />}
    {state.creating === 'code' ? <CodeForm state={state} /> : <EmailForm state={state} />}
    {dialogs}
  </section>;
  if (state.selected) return <><InvitationDetail state={state} />{dialogs}</>;
  const showCode = !state.team && state.codeAvailable, showEmail = state.emailAvailable && (!state.team || state.viewerIsAdmin);
  return <section className="invitation-page">
    <header className="invitation-heading"><h1>{title}</h1>
      {state.active && state.loaded.status === 'ready' && <div className="invitation-actions">
        {showCode && <Button disabled={!state.canWrite} onClick={() => state.open('code')}><KeyRound aria-hidden="true" />Code élève</Button>}
        {showEmail && <Button variant={showCode ? 'outline' : 'default'} disabled={!state.canWrite} onClick={() => state.open('email')}><Mail aria-hidden="true" />Inviter par e-mail</Button>}
      </div>}
    </header>
    {!state.active && <Alert><AlertTitle>Invitations disponibles après l’activation</AlertTitle><AlertDescription>L’école doit être active, avec ses textes d’information adoptés, avant d’inviter des personnes.</AlertDescription>
      {portalSections.includes('configuration') && <div className="invitation-alert-actions"><Button variant="outline" onClick={() => state.context.navigate('configuration')}>Ouvrir la configuration</Button></div>}</Alert>}
    {state.active && state.team && state.loaded.status === 'ready' && !state.emailAvailable && <Alert><AlertTitle>Envoi par e-mail indisponible</AlertTitle>
      <AlertDescription>Le service de messagerie doit être configuré pour inviter l’équipe.</AlertDescription>
      <div className="invitation-alert-actions"><Button variant="outline" onClick={state.loaded.reload}>Actualiser</Button></div></Alert>}
    {state.codeMissing && <Alert variant="destructive"><AlertTitle>Code non affiché</AlertTitle><AlertDescription>La réponse de l’école ne permet pas d’afficher le code. Ouvrez l’invitation créée et demandez un nouveau code.</AlertDescription></Alert>}
    {!state.dialog && <CommandFeedback runner={state.runner} />}
    <InvitationList state={state} />
    {dialogs}
  </section>;
}
