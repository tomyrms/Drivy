import { useEffect, useState } from 'react';
import { createCommand } from '../../command-core';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { courseErrorMessage, policyBody, policyForm, policyProblems, type CourseCatalogue, type PolicyForm } from '../../console/course-model';
import { useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';
import { keptMessage } from './course-presentation';

/** The two delays of the school's courses. An empty answer delay switches the waiting list off, as the school defines it. */
export function CoursePolicyDialog({ open, catalogue, onClose, onSaved, onReread }: { open: boolean; catalogue: CourseCatalogue; onClose: () => void; onSaved: () => void; onReread: () => void }) {
  const { schoolId } = useConsole();
  const runner = useCommandRunner();
  const [form, setForm] = useState<PolicyForm>(() => policyForm(catalogue.policy));
  const [touched, setTouched] = useState(false);
  const [refusal, setRefusal] = useState<{ code: string; message: string } | null>(null);
  useEffect(() => { if (open) { setForm(policyForm(catalogue.policy)); setTouched(false); setRefusal(null); runner.clearOutcome(); } }, [open]);
  const saved = policyForm(catalogue.policy);
  const dirty = form.selfCancelHours !== saved.selfCancelHours || form.offerResponseMinutes !== saved.offerResponseMinutes;
  const locked = runner.busy || Boolean(runner.pending);
  const problems = touched ? policyProblems(form) : {};
  useUnsavedChanges(open && dirty && !runner.pending);
  async function save() {
    setTouched(true);
    const body = policyBody(form);
    if (!body || locked || !dirty) return;
    setRefusal(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'saveCoursePolicy', path: 'course-policy', ifMatch: catalogue.policy.version, resourceVersion: catalogue.policy.version, body }), 'Les règles des cours sont enregistrées.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); setRefusal({ code: result.code, message: courseErrorMessage(result.code) ?? result.message }); return; }
    runner.clearOutcome();
    if (result.status === 'confirmed') onSaved();
    onClose();
  }
  const stale = refusal?.code === 'VERSION_CONFLICT';
  return <Dialog open={open} onOpenChange={(next, details) => { if (locked) { details.cancel(); return; } if (!next) onClose(); }}><DialogContent showCloseButton={!locked}>
    <DialogHeader><DialogTitle>Règles des cours</DialogTitle></DialogHeader>
    <form noValidate onSubmit={event => { event.preventDefault(); void save(); }}>
      <FieldGroup>
        <Field data-invalid={Boolean(problems.selfCancelHours)}><FieldLabel htmlFor="policy-cancel">Annulation libre (heures avant le cours)</FieldLabel>
          <Input id="policy-cancel" inputMode="numeric" value={form.selfCancelHours} disabled={locked} aria-invalid={Boolean(problems.selfCancelHours)} onChange={event => { setRefusal(null); setForm({ ...form, selfCancelHours: event.target.value }); }} />
          {problems.selfCancelHours && <FieldError>{problems.selfCancelHours}</FieldError>}</Field>
        <Field data-invalid={Boolean(problems.offerResponseMinutes)}><FieldLabel htmlFor="policy-offer">Réponse à une place proposée (minutes)</FieldLabel>
          <Input id="policy-offer" inputMode="numeric" value={form.offerResponseMinutes} placeholder="720" disabled={locked} aria-invalid={Boolean(problems.offerResponseMinutes)} aria-describedby="policy-offer-hint" onChange={event => { setRefusal(null); setForm({ ...form, offerResponseMinutes: event.target.value }); }} />
          <FieldDescription id="policy-offer-hint">Vide : liste d’attente désactivée.</FieldDescription>
          {problems.offerResponseMinutes && <FieldError>{problems.offerResponseMinutes}</FieldError>}</Field>
      </FieldGroup>
      {refusal && <Alert variant="destructive"><AlertTitle>{stale ? 'Modifié entre-temps' : 'Non enregistré'}</AlertTitle><AlertDescription>{keptMessage(refusal.message)}</AlertDescription>
        {stale && <div className="course-actions"><Button type="button" variant="outline" disabled={locked} onClick={() => { setRefusal(null); onReread(); }}>Relire, garder ma saisie</Button></div>}</Alert>}
      <CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
      <DialogFooter><Button type="button" variant="outline" disabled={locked} onClick={onClose}>Annuler</Button>
        <Button type="submit" disabled={locked || !dirty || Boolean(runner.blockedReason)}>{runner.busy ? 'Confirmation…' : 'Enregistrer'}</Button></DialogFooter>
    </form>
  </DialogContent></Dialog>;
}
