import { useEffect, useState, type ReactNode } from 'react';
import { Alert, AlertDescription } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldLabel } from '../../components/ui/field';
import { Textarea } from '../../components/ui/textarea';
import { REASON_LIMIT, reasonProblem } from '../../console/course-model';
import { useUnsavedChanges } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';
import { keptMessage } from './course-presentation';
import type { CourseParticipants, SendResult } from './use-course-participants';

/**
 * One deliberate action on one participant: who and what is named first, what the action does and does not do,
 * a motive when the school requires one, and the school's refusal in place with the typed motive kept.
 */
export function ActionDialog({ open, title, subject, facts, consequence, reasonLabel = 'Motif', confirmLabel, destructive = false, withReason, state, onClose, onConfirm, children }: {
  open: boolean; title: string; subject: string; facts?: readonly (readonly [string, string])[]; consequence?: string; reasonLabel?: string; confirmLabel: string; destructive?: boolean;
  withReason: boolean; state: CourseParticipants; onClose: () => void; onConfirm: (reason: string) => Promise<SendResult>; children?: ReactNode;
}) {
  const [reason, setReason] = useState('');
  const [touched, setTouched] = useState(false);
  const [refusal, setRefusal] = useState<string | null>(null);
  useEffect(() => { if (open) { setReason(''); setTouched(false); setRefusal(null); state.runner.clearOutcome(); } }, [open]);
  const locked = state.locked;
  const problem = withReason ? reasonProblem(reason) : null;
  useUnsavedChanges(open && withReason && reason.trim() !== '' && !state.runner.pending);
  async function confirm() {
    setTouched(true);
    if (problem || locked) return;
    setRefusal(null);
    const result = await onConfirm(reason.trim());
    if (result.status === 'rejected') { setRefusal(result.message); return; }
    onClose();
  }
  return <Dialog open={open} onOpenChange={(next, details) => { if (locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!locked}>
    <DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{subject}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void confirm(); }}>
      {facts && <dl className="participants-facts">{facts.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>}
      {children}
      {withReason && <Field data-invalid={touched && Boolean(problem)}><FieldLabel htmlFor="participant-reason">{reasonLabel}</FieldLabel>
        <Textarea id="participant-reason" value={reason} maxLength={REASON_LIMIT} rows={3} disabled={locked} aria-invalid={touched && Boolean(problem)} onChange={event => { setRefusal(null); setReason(event.target.value); }} />
        {touched && problem && <FieldError>{problem}</FieldError>}</Field>}
      {consequence && <p className="participants-consequence">{consequence}</p>}
      {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription>
        <div className="course-actions"><Button type="button" variant="outline" disabled={locked} onClick={() => { setRefusal(null); state.reread(); }}>Relire la liste</Button></div></Alert>}
      <CommandFeedback outcome={state.runner.outcome?.needsLogin ? state.runner.outcome : null} blocked={state.runner.blockedReason} />
      <DialogFooter><Button type="button" variant="outline" disabled={locked} onClick={onClose}>Annuler</Button>
        <Button type="submit" variant={destructive ? 'destructive' : 'default'} disabled={locked || Boolean(state.runner.blockedReason)}>{state.runner.busy ? 'Confirmation…' : confirmLabel}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
