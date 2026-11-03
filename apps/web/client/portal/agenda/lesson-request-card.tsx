import { useState } from 'react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldLabel } from '../../components/ui/field';
import { Textarea } from '../../components/ui/textarea';
import { createCommand } from '../../command-core';
import { useCommandSnapshot } from '../../command-store';
import { useCommandLane, useConsole, useLoad } from '../../console/context';
import {
  LESSON_CHANGE_NOTE_LIMIT, lateLabel, lessonChangeStateSchema, pendingRequest, refuseBody, refuseProblems, requestTitle, type LessonChangeRequest,
} from '../../lesson-change-model';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { CommandFeedback, dateTime } from './presentation';

/** Les demandes d'une leçon : l'élève demande, le personnel répond. Relue après chaque commande ; une panne ne dit rien de la demande. */
export function useLessonRequest(lessonId: string | null) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  const loaded = useLoad(async () => {
    if (!lessonId) return null;
    const state = await readSchool(schoolId, `lessons/${lessonId}/change-requests`, lessonChangeStateSchema);
    if (state.lessonId !== lessonId) throw new RequestFailure('INVALID_RESPONSE');
    return state;
  }, [schoolId, lessonId, revision], `${schoolId}/${lessonId ?? 'new'}/change-requests`);
  return { loaded, request: pendingRequest(loaded.data) };
}

/**
 * Demande en attente d'une leçon, au-dessus de son détail. Accepter passe par le déplacement ou l'annulation de la leçon (la demande
 * se ferme avec le changement) ; refuser laisse la leçon telle quelle et dit pourquoi à l'élève.
 */
export function LessonRequestCard({ request, timeZone, locked, onMove, onCancel }: {
  request: LessonChangeRequest; timeZone: string; locked: boolean; onMove: () => void; onCancel: () => void;
}) {
  const [refusing, setRefusing] = useState(false);
  const late = lateLabel(request);
  return <section className="agenda-request" aria-labelledby="agenda-request-title" data-kind={request.kind}>
    <div className="agenda-request-heading"><h2 id="agenda-request-title">{requestTitle(request.kind)}</h2>{late && <Badge variant="outline">{late}</Badge>}</div>
    <p className="agenda-request-meta">Demandé le <time dateTime={request.createdAt}>{dateTime(request.createdAt, timeZone)}</time>. La leçon reste planifiée tant que vous n’avez pas répondu.</p>
    {request.note && <p className="agenda-request-note">{request.note}</p>}
    <div className="agenda-actions">
      {request.kind === 'CANCEL'
        ? <Button variant="destructive" disabled={locked} onClick={onCancel}>Annuler la leçon</Button>
        : <Button disabled={locked} onClick={onMove}>Choisir un nouveau créneau</Button>}
      <Button variant="outline" disabled={locked} onClick={() => setRefusing(true)}>Refuser la demande</Button>
    </div>
    {refusing && <RefuseDialog request={request} close={() => setRefusing(false)} />}
  </section>;
}

function RefuseDialog({ request, close }: { request: LessonChangeRequest; close: () => void }) {
  const { schoolId } = useConsole();
  const [note, setNote] = useState('');
  const lane = useCommandLane();
  const tag = `request:${request.id}:refuse`;
  const outcome = lane.outcomes.get(tag) ?? null;
  const busy = lane.busy;
  const blocked = lane.blocked({ kind: 'refuseLessonChangeRequest', resourceId: request.id });
  const problems = refuseProblems({ note });
  const submit = () => {
    const body = refuseBody({ note });
    if (!body || busy || blocked) return;
    const started = lane.run(createCommand({ schoolId, kind: 'refuseLessonChangeRequest', path: `lesson-change-requests/${request.id}/refuse`, resourceId: request.id,
      resourceVersion: request.version, ifMatch: request.version, body }), 'La demande est refusée.', tag);
    if (!started.admitted) return;
    void started.result.then(result => { if (result.status === 'confirmed') close(); });
  };
  return <Dialog open onOpenChange={(next, details) => { if (busy) details.cancel(); else if (!next) close(); }}>
    <DialogContent showCloseButton={!busy}>
      <DialogHeader><DialogTitle>Refuser la demande ?</DialogTitle><DialogDescription>La leçon reste telle quelle. Votre motif est lu par l’élève.</DialogDescription></DialogHeader>
      <form onSubmit={event => { event.preventDefault(); submit(); }}>
        <Field data-invalid={!!problems.note}><FieldLabel htmlFor="lesson-request-refuse-note">Motif (facultatif)</FieldLabel>
          <Textarea id="lesson-request-refuse-note" value={note} maxLength={LESSON_CHANGE_NOTE_LIMIT} rows={3} disabled={busy} onChange={event => setNote(event.target.value)} />
          {problems.note && <FieldError>{problems.note}</FieldError>}</Field>
        <CommandFeedback outcome={outcome} blocked={blocked ? 'Une demande de planification attend sa confirmation (voir en haut de la page).' : null} />
        <DialogFooter><Button type="button" variant="outline" disabled={busy} onClick={close}>Retour</Button><Button type="submit" disabled={busy || blocked || !!problems.note}>Refuser la demande</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}
