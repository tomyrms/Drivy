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
import type { KeepResult } from './use-course-participants';

/**
 * One deliberate action on one participant: who and what is named first, what the action does and does not do,
 * a motive when the school requires one, and the school's refusal in place with the typed motive kept.
 * The form is released as soon as the store keeps the request: a later refusal comes back as a notice to resume from.
 */
export function ActionDialog({ open, title, subject, facts, consequence, reasonLabel = 'Motif', confirmLabel, destructive = false, withReason, blocked, initialReason = '', onClose, onReread, onConfirm, children }: {
  open: boolean; title: string; subject: string; facts?: readonly (readonly [string, string])[]; consequence?: string; reasonLabel?: string; confirmLabel: string; destructive?: boolean;
  withReason: boolean; blocked?: string | null | undefined; initialReason?: string; onClose: () => void; onReread?: (() => void) | undefined;
  onConfirm: (reason: string) => KeepResult; children?: ReactNode;
}) {
  const [reason, setReason] = useState(initialReason);
  const [touched, setTouched] = useState(false);
  const [refusal, setRefusal] = useState<string | null>(null);
  useEffect(() => { if (open) { setReason(initialReason); setTouched(false); setRefusal(null); } }, [open, initialReason]);
  const problem = withReason ? reasonProblem(reason) : null;
  useUnsavedChanges(open && withReason && reason.trim() !== '');
  function confirm() {
    setTouched(true);
    if (problem || blocked) return;
    setRefusal(null);
    const result = onConfirm(reason.trim());
    if (result === 'kept') { onClose(); return; }
    if (result === 'refused') setRefusal('Une demande sur ce participant attend encore sa confirmation.');
  }
  return <Dialog open={open} onOpenChange={(next, details) => { if (blocked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent className="participants-dialog" showCloseButton={!blocked}>
    <DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{subject}</DialogDescription></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); confirm(); }}>
      {facts && <dl className="participants-facts">{facts.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>}
      {children}
      {withReason && <Field data-invalid={touched && Boolean(problem)}><FieldLabel htmlFor="participant-reason">{reasonLabel}</FieldLabel>
        <Textarea id="participant-reason" value={reason} maxLength={REASON_LIMIT} rows={3} disabled={Boolean(blocked)} aria-invalid={touched && Boolean(problem)} onChange={event => { setRefusal(null); setReason(event.target.value); }} />
        {touched && problem && <FieldError>{problem}</FieldError>}</Field>}
      {consequence && <p className="participants-consequence">{consequence}</p>}
      {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription>
        {onReread && <div className="course-actions"><Button type="button" variant="outline" disabled={Boolean(blocked)} onClick={() => { setRefusal(null); onReread(); }}>Relire la liste</Button></div>}</Alert>}
      <CommandFeedback outcome={null} blocked={blocked} />
      <DialogFooter><Button type="button" variant="outline" disabled={Boolean(blocked)} onClick={onClose}>Annuler</Button>
        <Button type="submit" variant={destructive ? 'destructive' : 'default'} disabled={Boolean(blocked)}>{confirmLabel}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
