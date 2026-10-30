import { useEffect, useState } from 'react';
import { createCommand } from '../../command-core';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldDescription, FieldError, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { capacityProblem, courseErrorMessage, REASON_LIMIT, reasonProblem, type CourseSeries } from '../../console/course-model';
import { useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';
import { confirmedSeries } from './course-catalogue';
import { keptMessage, seatsLabel, seriesSummary } from './course-presentation';

interface ChangeProps { series: CourseSeries; open: boolean; onClose: () => void; onChanged: (series: CourseSeries | null, message: string) => void; onReread: () => void }

/** A refused change keeps what was typed; a stale version offers one re-read that leaves the typed value in place. */
function Refusal({ refusal, locked, onReread }: { refusal: { code: string; message: string } | null; locked: boolean; onReread: () => void }) {
  if (!refusal) return null;
  const stale = refusal.code === 'VERSION_CONFLICT';
  return <Alert variant="destructive"><AlertTitle>{stale ? 'Modifié entre-temps' : 'Non enregistré'}</AlertTitle><AlertDescription>{keptMessage(refusal.message)}</AlertDescription>
    {stale && <div className="course-actions"><Button type="button" variant="outline" disabled={locked} onClick={onReread}>Relire, garder ma saisie</Button></div>}</Alert>;
}

/** Capacity is the only thing of a published course that changes in place; places already taken set the floor. */
export function CapacityDialog({ series, open, onClose, onChanged, onReread }: ChangeProps) {
  const { schoolId } = useConsole();
  const runner = useCommandRunner();
  const [capacity, setCapacity] = useState(String(series.capacity));
  const [refusal, setRefusal] = useState<{ code: string; message: string } | null>(null);
  useEffect(() => { if (open) { setCapacity(String(series.capacity)); setRefusal(null); runner.clearOutcome(); } }, [open]);
  const locked = runner.busy || Boolean(runner.pending);
  const changed = capacity.trim() !== String(series.capacity);
  const problem = capacityProblem(capacity, series);
  useUnsavedChanges(open && changed && !runner.pending);
  async function save() {
    if (problem || locked) return;
    setRefusal(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'changeCourseCapacity', path: `course-series/${series.id}/capacity`, ifMatch: series.version,
      resourceId: series.id, resourceVersion: series.version, body: { capacity: Number(capacity.trim()) } }), 'La capacité est modifiée.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); setRefusal({ code: result.code, message: courseErrorMessage(result.code) ?? result.message }); return; }
    if (result.status === 'pending') { onClose(); return; }
    runner.clearOutcome(); onChanged(confirmedSeries(result.body), 'La capacité est modifiée.');
  }
  return <Dialog open={open} onOpenChange={(next, details) => { if (locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!locked}>
    <DialogHeader><DialogTitle>Modifier la capacité</DialogTitle><DialogDescription>{series.title}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void save(); }}>
      <Field data-invalid={changed && Boolean(problem)}><FieldLabel htmlFor="capacity-input">Places</FieldLabel>
        <Input id="capacity-input" inputMode="numeric" value={capacity} disabled={locked} aria-invalid={changed && Boolean(problem)} aria-describedby="capacity-hint" onChange={event => { setRefusal(null); setCapacity(event.target.value); }} />
        <FieldDescription id="capacity-hint">{series.seatsTaken} {series.seatsTaken === 1 ? 'place déjà prise' : 'places déjà prises'}{series.minParticipants !== null ? ` · minimum ${series.minParticipants}` : ''}</FieldDescription>
        {changed && problem && <FieldError>{problem}</FieldError>}</Field>
      <Refusal refusal={refusal} locked={locked} onReread={() => { setRefusal(null); onReread(); }} />
      <CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
      <DialogFooter><Button type="button" variant="outline" disabled={locked} onClick={onClose}>Annuler</Button>
        <Button type="submit" disabled={locked || !changed || Boolean(problem) || Boolean(runner.blockedReason)}>{runner.busy ? 'Confirmation…' : 'Enregistrer la capacité'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}

/** Cancels the whole series: there is no isolated session cancellation. The people concerned and the reason are on screen before the confirmation. */
export function CancelSeriesDialog({ series, open, onClose, onChanged, onReread }: ChangeProps) {
  const { schoolId, school } = useConsole();
  const runner = useCommandRunner();
  const [reason, setReason] = useState('');
  const [touched, setTouched] = useState(false);
  const [refusal, setRefusal] = useState<{ code: string; message: string } | null>(null);
  useEffect(() => { if (open) { setReason(''); setTouched(false); setRefusal(null); runner.clearOutcome(); } }, [open]);
  const locked = runner.busy || Boolean(runner.pending);
  const problem = reasonProblem(reason);
  useUnsavedChanges(open && reason.trim() !== '' && !runner.pending);
  async function cancel() {
    setTouched(true);
    if (problem || locked) return;
    setRefusal(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'cancelCourseSeries', path: `course-series/${series.id}/cancel`, ifMatch: series.version,
      resourceId: series.id, resourceVersion: series.version, body: { reason: reason.trim() } }), 'Le cours est annulé.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); setRefusal({ code: result.code, message: courseErrorMessage(result.code) ?? result.message }); return; }
    if (result.status === 'pending') { onClose(); return; }
    runner.clearOutcome(); onChanged(confirmedSeries(result.body), 'Le cours est annulé.');
  }
  return <Dialog open={open} onOpenChange={(next, details) => { if (locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!locked}>
    <DialogHeader><DialogTitle>Annuler toute la série ?</DialogTitle><DialogDescription>{series.title}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void cancel(); }}>
      <dl className="course-review course-review-compact">
        <div><dt>Séances</dt><dd>{seriesSummary(series, school.timeZone)}</dd></div>
        <div><dt>Inscrits</dt><dd>{series.seatsTaken === 0 ? 'Aucun inscrit' : `${seatsLabel(series.seatsTaken)} concernés`}</dd></div>
      </dl>
      <Field data-invalid={touched && Boolean(problem)}><FieldLabel htmlFor="cancel-reason">Motif</FieldLabel>
        <Textarea id="cancel-reason" value={reason} maxLength={REASON_LIMIT} rows={3} disabled={locked} aria-invalid={touched && Boolean(problem)} onChange={event => { setRefusal(null); setReason(event.target.value); }} />
        {touched && problem && <FieldError>{problem}</FieldError>}</Field>
      <Refusal refusal={refusal} locked={locked} onReread={() => { setRefusal(null); onReread(); }} />
      <CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
      <DialogFooter><Button type="button" variant="outline" disabled={locked} onClick={onClose}>Garder le cours</Button>
        <Button type="submit" variant="destructive" disabled={locked || Boolean(runner.blockedReason)}>{runner.busy ? 'Confirmation…' : 'Annuler la série'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
