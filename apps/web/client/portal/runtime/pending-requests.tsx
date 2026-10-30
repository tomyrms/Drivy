import { useRef, useState } from 'react';
import { commandSpecs } from '../../command-core';
import { commandStore, pendingActions, useCommandSnapshot } from '../../command-store';
import { commandRefreshesSchool } from '../../command-conflicts';
import { useConsole } from '../../console/context';
import { Alert, AlertTitle, AlertDescription } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '../../components/ui/dialog';

/** Same durable command store, new presentation. A closed form never means a cancelled command. */
export function PortalPendingRequests() {
  const context = useConsole(), snapshot = useCommandSnapshot();
  const entries = [...snapshot.entries.values()].filter(item => item.meta.schoolId === context.schoolId);
  const [releaseId, setReleaseId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const working = useRef(new Set<string>());
  async function act(operationId: string, resend = false) {
    if (working.current.has(operationId)) return;
    working.current.add(operationId);
    try {
      const entry = commandStore.get(context.schoolId, operationId); if (!entry) return;
      let token = context.csrf();
      if (resend) { try { token = await context.refreshCsrf(); } catch { /* Same conservative retry as existing console. */ } }
      const result = await (resend ? commandStore.resend(context.schoolId, token, operationId) : commandStore.verify(context.schoolId, operationId));
      if (result.status === 'confirmed') { setMessage('Le résultat de la demande est confirmé.'); if (commandRefreshesSchool(entry.meta.kind)) void context.reloadSchool(); }
      if (result.status === 'rejected') { setMessage(result.message); void context.reloadSchool(); }
    } finally { working.current.delete(operationId); }
  }
  if (!entries.length) return message ? <Alert className="mb-6"><AlertTitle>Suivi de la demande</AlertTitle><AlertDescription>{message}</AlertDescription><Button variant="ghost" onClick={() => setMessage(null)}>Masquer</Button></Alert> : null;
  return <section className="mb-6 grid gap-3" aria-label="Demandes en cours" aria-live="polite">
    {entries.map((entry, index) => {
      const busy = entry.phase === 'sending' || entry.phase === 'verifying', available = pendingActions(entry);
      return <Alert key={entry.meta.operationId}>
        <AlertTitle id={index === 0 ? 'pending-title' : undefined} tabIndex={-1}>{busy ? entry.phase === 'sending' ? 'Enregistrement en cours…' : 'Vérification en cours…' : 'Résultat à vérifier'}</AlertTitle>
        <AlertDescription><p>{commandSpecs[entry.meta.kind].label}</p>{entry.message && <p>{entry.message}</p>}</AlertDescription>
        {!busy && <div className="mt-4 flex flex-wrap gap-2">
          <Button onClick={() => void act(entry.meta.operationId)}>Vérifier le résultat</Button>
          {available.resend && <Button variant="outline" onClick={() => void act(entry.meta.operationId, true)}>Renvoyer la même demande</Button>}
          {entry.needsLogin && <Button variant="outline" onClick={() => context.login()}>Se reconnecter</Button>}
          {available.release && <Button variant="ghost" onClick={() => setReleaseId(entry.meta.operationId)}>Arrêter le suivi</Button>}
        </div>}
      </Alert>;
    })}
    <Dialog open={releaseId !== null} onOpenChange={open => { if (!open) setReleaseId(null); }}><DialogContent>
      <DialogHeader><DialogTitle>Arrêter le suivi ?</DialogTitle><DialogDescription>Le résultat restera à vérifier avant une nouvelle demande. Arrêter le suivi n’annule pas une modification déjà reçue.</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={() => setReleaseId(null)}>Continuer le suivi</Button><Button onClick={() => { if (releaseId) commandStore.release(context.schoolId, releaseId); setReleaseId(null); setMessage('Suivi arrêté. Vérifiez les informations avant une nouvelle demande.'); }}>Arrêter le suivi</Button></DialogFooter>
    </DialogContent></Dialog>
  </section>;
}
