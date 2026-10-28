import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Textarea } from '../../components/ui/textarea';
import { filled } from '../../command-core';
import { offeringLabel } from '../../invitation-model';
import { roleLabel } from '../../protocol';
import type { InvitationsState } from './use-invitations';

const titles = { create: { code: 'Créer le code élève ?', email: 'Inviter par e-mail ?' }, renew: { code: 'Créer un nouveau code ?', email: 'Renvoyer l’invitation ?' }, revoke: { code: 'Révoquer l’invitation ?', email: 'Révoquer l’invitation ?' } } as const;

/** Review before anything is issued, renewed or revoked. A refusal stays here, with the reason typed. */
export function InvitationDialogs({ state }: { state: InvitationsState }) {
  const { school } = state.context, kind = state.dialog, current = state.current;
  const delivery = kind === 'create' ? state.creating ?? 'code' : current?.delivery === 'CODE' ? 'code' : 'email';
  const reasonOk = filled(state.revokeReason, 1000);
  const chosen = state.instructors.find(item => item.id === state.instructorId);
  const confirmLabel = kind === 'create' ? delivery === 'code' ? 'Créer le code' : 'Enregistrer l’invitation'
    : kind === 'renew' ? delivery === 'code' ? 'Créer un nouveau code' : 'Enregistrer un nouveau lien' : 'Révoquer l’invitation';
  return <Dialog open={kind !== null} onOpenChange={(open, details) => { if (state.busy) { details.cancel(); return; } if (!open) state.closeDialog(); }}>
    <DialogContent showCloseButton={!state.busy}>
      {kind && <>
        <DialogHeader><DialogTitle>{titles[kind][delivery]}</DialogTitle><DialogDescription>{school.name}</DialogDescription></DialogHeader>
        {kind === 'create' && delivery === 'code' && <dl className="access-changes">
          <div><dt>Permis</dt><dd>{state.offerings.filter(item => state.offeringIds.includes(item.id)).map(item => offeringLabel(item, state.offerings)).join(', ')}</dd></div>
          <div><dt>Moniteur</dt><dd>{chosen ? state.instructorName(chosen) : '—'}</dd></div>
          <div><dt>Validité</dt><dd>7 jours, à usage unique</dd></div></dl>}
        {kind === 'create' && delivery === 'email' && <dl className="access-changes">
          <div><dt>Adresse</dt><dd>{state.email.trim()}</dd></div>
          <div><dt>Rôles</dt><dd>{[...state.invitedRoles].sort().map(roleLabel).join(', ')}</dd></div>
          <div><dt>Validité</dt><dd>7 jours</dd></div></dl>}
        {kind === 'renew' && current && <Alert><AlertTitle>{delivery === 'code' ? 'Le code précédent ne fonctionnera plus' : 'Le lien précédent ne fonctionnera plus'}</AlertTitle>
          <AlertDescription>{state.labelOf(current)}. {delivery === 'code' ? 'Un nouveau code valable 7 jours est créé.' : 'Un nouveau lien valable 7 jours est enregistré pour envoi par e-mail.'}</AlertDescription></Alert>}
        {kind === 'revoke' && current && <>
          <p className="invitation-dialog-lead">{state.labelOf(current)}</p>
          <FieldGroup><Field data-invalid={state.revokeReason !== '' && !reasonOk}><FieldLabel htmlFor="revoke-reason">Motif de la révocation</FieldLabel>
            <Textarea id="revoke-reason" value={state.revokeReason} onChange={event => state.setRevokeReason(event.target.value)} maxLength={1000} rows={3} disabled={state.busy} />
            {state.revokeReason !== '' && !reasonOk && <FieldError>Indiquez le motif de la révocation (1 000 caractères au plus).</FieldError>}</Field></FieldGroup></>}
        {state.runner.outcome?.tone === 'error' && <Alert variant="destructive"><AlertTitle>{state.runner.outcome.title}</AlertTitle><AlertDescription>{state.runner.outcome.message}</AlertDescription></Alert>}
        <DialogFooter><Button variant="outline" disabled={state.busy} onClick={state.closeDialog}>Retour</Button>
          <Button variant={kind === 'revoke' ? 'destructive' : 'default'} disabled={state.busy || !state.canWrite || (kind === 'revoke' && !reasonOk)} aria-busy={state.runner.busy} onClick={() => void state.confirm()}>{state.runner.busy ? 'Confirmation…' : confirmLabel}</Button></DialogFooter>
      </>}
    </DialogContent>
  </Dialog>;
}
