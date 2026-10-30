import { useEffect, useState } from 'react';
import { createCommand } from '../../command-core';
import { Alert, AlertDescription } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { courseErrorMessage, LIMITS, typeProblem, type CourseType } from '../../console/course-model';
import { useCommandRunner, useConsole, useUnsavedChanges } from '../../console/context';
import { CommandFeedback } from '../agenda/presentation';
import { confirmedType } from './course-catalogue';
import { keptMessage } from './course-presentation';

/**
 * A custom course type, created in one short action. The draft of the series stays untouched behind this dialog;
 * the new type is offered to it once the school confirms it.
 */
export function CourseTypeDialog({ open, existing, onClose, onCreated }: { open: boolean; existing: readonly CourseType[]; onClose: () => void; onCreated: (type: CourseType | null) => void }) {
  const { schoolId } = useConsole();
  const runner = useCommandRunner();
  const [title, setTitle] = useState(''), [description, setDescription] = useState('');
  const [touched, setTouched] = useState(false), [refusal, setRefusal] = useState<string | null>(null);
  useEffect(() => { if (open) { setTitle(''); setDescription(''); setTouched(false); setRefusal(null); runner.clearOutcome(); } }, [open]);
  const locked = runner.busy || Boolean(runner.pending);
  const problem = typeProblem(title, description, existing);
  useUnsavedChanges(open && (title.trim() !== '' || description.trim() !== '') && !runner.pending);
  async function create() {
    setTouched(true);
    if (problem || locked) return;
    setRefusal(null);
    const result = await runner.run(createCommand({ schoolId, kind: 'createCourseType', path: 'course-types', resourceVersion: 0, body: { title: title.trim(), description: description.trim() } }), 'Le type de cours est ajouté.');
    if (result.status === 'rejected') { if (!result.needsLogin) runner.clearOutcome(); setRefusal(courseErrorMessage(result.code) ?? result.message); return; }
    if (result.status === 'confirmed') { runner.clearOutcome(); onCreated(confirmedType(result.body)); }
  }
  return <Dialog open={open} onOpenChange={(next, details) => { if (locked) { details.cancel(); return; } if (!next) onClose(); }}>
    <DialogContent showCloseButton={!locked}>
      <DialogHeader><DialogTitle>Nouveau type de cours</DialogTitle><DialogDescription>Le type est ajouté au catalogue de l’école.</DialogDescription></DialogHeader>
      <form noValidate onSubmit={event => { event.preventDefault(); void create(); }}>
        <FieldGroup>
          <Field data-invalid={touched && Boolean(problem)}><FieldLabel htmlFor="type-title">Nom du type</FieldLabel>
            <Input id="type-title" value={title} maxLength={LIMITS.typeTitle} disabled={locked} aria-invalid={touched && Boolean(problem)} onChange={event => { setRefusal(null); setTitle(event.target.value); }} />
            {touched && problem && <FieldError>{problem}</FieldError>}</Field>
          <Field><FieldLabel htmlFor="type-description">Description (facultatif)</FieldLabel>
            <Textarea id="type-description" value={description} maxLength={LIMITS.typeDescription} rows={3} disabled={locked} onChange={event => setDescription(event.target.value)} /></Field>
        </FieldGroup>
        {refusal && <Alert variant="destructive"><AlertDescription>{keptMessage(refusal)}</AlertDescription></Alert>}
        <CommandFeedback outcome={runner.outcome?.needsLogin ? runner.outcome : null} blocked={runner.blockedReason} />
        <DialogFooter><Button type="button" variant="outline" disabled={locked} onClick={onClose}>Annuler</Button><Button type="submit" disabled={locked || Boolean(runner.blockedReason)}>{runner.busy ? 'Confirmation…' : 'Ajouter le type'}</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}
