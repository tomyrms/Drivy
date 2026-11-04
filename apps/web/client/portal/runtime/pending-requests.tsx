import { useReducer, useRef, useState } from 'react';
import { commandSpecs } from '../../command-core';
import { commandStore, pendingActions, useCommandSnapshot } from '../../command-store';
import { commandRefreshesSchool } from '../../command-conflicts';
import { lessonResendAllowed, lessonResendReason } from '../../console/agenda-intentions';
import { useConsole } from '../../console/context';
import { Alert, AlertTitle, AlertDescription } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../../components/ui/dialog';

/** Same durable command store, new presentation. A closed form never means a cancelled command. */
export function PortalPendingRequests() {
  const context = useConsole();
  return <PendingRequests key={context.schoolId} />;
}

function PendingRequests() {
  const context = useConsole(), snapshot = useCommandSnapshot();
  const entries = [...snapshot.entries.values()].filter(item => item.meta.schoolId === context.schoolId);
  const [releaseId, setReleaseId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [, refreshRecovery] = useReducer((value: boolean) => !value, false);
  const storageNotice = snapshot.metadata.durability === 'saved' ? null
    : snapshot.metadata.last === 'write'
      ? 'Le suivi local n’a pas pu être enregistré ou mis à jour. Vérifiez le résultat avant de refaire une demande.'
      : snapshot.metadata.last === 'clear'
        ? 'Le suivi local n’a pas pu être effacé. Il peut réapparaître : vérifiez le résultat avant de refaire une demande.'
        : 'Le suivi précédent n’a pas pu être relu. Vérifiez les informations auprès de l’école avant de refaire une demande.';
  const working = useRef(new Set<string>());
  async function act(operationId: string, resend = false) {
    if (working.current.has(operationId)) return;
    working.current.add(operationId);
    try {
      const entry = commandStore.get(context.schoolId, operationId); if (!entry) return;
      let token = context.csrf();
      if (resend) { try { token = await context.refreshCsrf(); } catch { /* Same conservative retry as existing console. */ } }
      const result = await (resend ? commandStore.resend(context.schoolId, token, operationId) : commandStore.verify(context.schoolId, operationId));
      if (result.status === 'pending') {
        // A deadline refusal does not notify the store. Re-read the shared recovery rule at render;
        // other pending results are already in entry.message. Keep no copy of an entry or its body.
        if (result.message) refreshRecovery();
      }
      if (result.status === 'confirmed') { setMessage('Le résultat de la demande est confirmé.'); if (commandRefreshesSchool(entry.meta.kind)) void context.reloadSchool(); }
      if (result.status === 'rejected') { setMessage(result.message); void context.reloadSchool(); }
    } finally { working.current.delete(operationId); }
  }
  return <>
    <div role="status" aria-live="polite" aria-atomic="true">
      {storageNotice && <Alert role="none" className="mb-6"><AlertTitle>Suivi local à vérifier</AlertTitle><AlertDescription>{storageNotice}</AlertDescription></Alert>}
    </div>
    {!entries.length && message && <Alert role="status" className="mb-6"><AlertTitle>Suivi de la demande</AlertTitle><AlertDescription>{message}</AlertDescription><Button variant="ghost" onClick={() => setMessage(null)}>Masquer</Button></Alert>}
    {entries.length > 0 && <section className="mb-6 grid gap-3" aria-label="Demandes en cours">
    {entries.map((entry, index) => {
      const busy = entry.phase === 'sending' || entry.phase === 'verifying', available = pendingActions(entry);
      // Une planification dont l'horaire voulu est passé n'est plus renvoyée : vérifier ou arrêter le suivi.
      const resend = available.resend && lessonResendAllowed({ kind: entry.meta.kind, command: entry.command });
      const resendReason = available.resend && !resend ? lessonResendReason({ kind: entry.meta.kind, command: entry.command }) : null;
      return <Alert role="status" aria-live="polite" className="min-w-0 grid-cols-1 break-words" key={entry.meta.operationId}>
        <AlertTitle id={index === 0 ? 'pending-title' : undefined} tabIndex={-1}>{busy ? entry.phase === 'sending' ? 'Enregistrement en cours…' : 'Vérification en cours…' : 'Résultat à vérifier'}</AlertTitle>
        <AlertDescription><p>{commandSpecs[entry.meta.kind].label}</p>{entry.message && <p>{entry.message}</p>}{resendReason && resendReason !== entry.message && <p>{resendReason}</p>}</AlertDescription>
        {!busy && <div className="mt-4 grid min-w-0 grid-cols-1 gap-2 sm:flex sm:flex-wrap">
          <Button onClick={() => void act(entry.meta.operationId)}>Vérifier le résultat</Button>
          {resend && <Button variant="outline" onClick={() => void act(entry.meta.operationId, true)}>Renvoyer la même demande</Button>}
          {entry.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}
          {available.release && <Button variant="ghost" onClick={() => setReleaseId(entry.meta.operationId)}>Arrêter le suivi</Button>}
        </div>}
      </Alert>;
    })}
    <Dialog open={releaseId !== null} onOpenChange={open => { if (!open) setReleaseId(null); }}><DialogContent>
      <DialogHeader><DialogTitle>Arrêter le suivi ?</DialogTitle><DialogDescription>Le résultat restera à vérifier avant une nouvelle demande. Arrêter le suivi n’annule pas une modification déjà reçue.</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={() => setReleaseId(null)}>Continuer le suivi</Button><Button onClick={() => { if (releaseId) commandStore.release(context.schoolId, releaseId); setReleaseId(null); setMessage('Suivi arrêté. Vérifiez les informations avant une nouvelle demande.'); }}>Arrêter le suivi</Button></DialogFooter>
    </DialogContent></Dialog>
  </section>}
  </>;
}
