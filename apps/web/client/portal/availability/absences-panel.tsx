import { useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, CalendarOff, Plus } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { useUnsavedChanges } from '../../console/context';
import type { Closure } from '../../school-api';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { ABSENCE_REASON_LIMIT, absenceInstants, absenceLabel, absenceProblems, emptyAbsenceDraft, type AbsenceDraft } from './schedule-model';
import { DiscardDialog, isFieldRefusal, ScheduleRefusal } from './schedule-feedback';
import type { ScheduleCommands } from './use-schedule-commands';
import type { ScheduleState } from './use-schedule';

function AbsenceRow({ item, state, commands }: { item: Closure; state: ScheduleState; commands: ScheduleCommands }) {
  const { school } = state.context;
  const label = absenceLabel(item, school.timeZone);
  return <li className="schedule-rule">
    <div className="schedule-rule-main schedule-absence-main">
      <span className="schedule-rule-days"><time dateTime={item.startsAt}>{label.title}</time></span>
      <span className="schedule-muted">{label.detail}</span>
      {item.reason && <span className="schedule-reason">{item.reason}</span>}
    </div>
    <div className="schedule-rule-actions">
      <Button variant="ghost" disabled={!state.writable || commands.locked} aria-label={`Retirer l’absence du ${label.title}`} onClick={() => commands.setRemoving({ kind: 'absence', value: item })}>Retirer</Button>
    </div>
  </li>;
}

export function AbsencesReading({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const open = () => { commands.runner.clearOutcome(); state.setView({ kind: 'absence' }); };
  if (state.absences.length === 0) return <Empty className="schedule-empty"><EmptyHeader><EmptyMedia variant="icon"><CalendarOff /></EmptyMedia><EmptyTitle>Aucune absence prévue</EmptyTitle></EmptyHeader>
    <EmptyContent><Button disabled={!state.writable || commands.locked} onClick={open}><Plus data-icon="inline-start" />Ajouter une absence</Button></EmptyContent></Empty>;
  return <section aria-labelledby="schedule-absences-title" className="schedule-section">
    <h2 id="schedule-absences-title">Absences prévues</h2>
    <ul className="schedule-rules">{state.absences.map(item => <AbsenceRow key={item.id} item={item} state={state} commands={commands} />)}</ul>
  </section>;
}

export function AbsenceRemoval({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const target = commands.removing?.kind === 'absence' ? commands.removing.value : null;
  const label = target ? absenceLabel(target, state.context.school.timeZone) : null;
  return <Dialog open={target !== null} onOpenChange={(next, details) => { if (commands.locked) { details.cancel(); return; } if (!next) { commands.setRemoving(null); commands.runner.clearOutcome(); } }}>
    <DialogContent showCloseButton={!commands.locked}>
      <DialogHeader><DialogTitle>Retirer cette absence ?</DialogTitle><DialogDescription>{state.instructorName}</DialogDescription></DialogHeader>
      {target && label && <dl className="schedule-review"><div><dt>Période</dt><dd>{label.title}<br />{label.detail}</dd></div>{target.reason && <div><dt>Motif</dt><dd>{target.reason}</dd></div>}</dl>}
      <p className="schedule-consequence">Le moniteur pourra de nouveau être proposé sur cette période, selon ses horaires.</p>
      <ScheduleRefusal outcome={commands.runner.outcome} blocked={commands.runner.blockedReason} instructorName={state.instructorName} busy={commands.locked}
        onAgenda={() => { commands.setRemoving(null); state.context.navigate('agenda', { instructor: state.instructor }); }}
        onReread={() => { commands.runner.clearOutcome(); commands.setRemoving(null); state.refresh(); }} />
      <DialogFooter>
        <Button variant="outline" disabled={commands.locked} onClick={() => { commands.setRemoving(null); commands.runner.clearOutcome(); }}>Garder l’absence</Button>
        <Button variant="destructive" disabled={commands.locked || Boolean(commands.runner.blockedReason)} onClick={() => void commands.remove()}>{commands.runner.busy ? 'Confirmation…' : 'Retirer l’absence'}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}

export function AbsenceEditor({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const { school } = state.context;
  const [draft, setDraft] = useState<AbsenceDraft>(emptyAbsenceDraft);
  const [stage, setStage] = useState<'edit' | 'review'>('edit');
  const [touched, setTouched] = useState(false);
  const [discard, setDiscard] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, stage);
  const dirty = draft.start !== '' || draft.end !== '' || draft.reason !== '';
  useUnsavedChanges(dirty && !commands.runner.pending);
  const problems = absenceProblems(draft, school.timeZone);
  const locked = commands.locked;
  const refusal = commands.runner.outcome;
  const refusedInterval = isFieldRefusal(refusal) ? refusal?.message : undefined;
  const showing = touched ? problems : {};
  const change = (patch: Partial<AbsenceDraft>) => { commands.runner.clearOutcome(); setDraft(previous => ({ ...previous, ...patch })); };
  const close = () => { if (locked) return; if (dirty) setDiscard(true); else state.setView(null); };
  const review = () => { setTouched(true); if (Object.keys(problems).length === 0) setStage('review'); };
  const submit = async () => {
    const result = await commands.saveAbsence(draft);
    if (result?.status === 'confirmed') state.setView(null);
    if (result?.status === 'rejected') setStage('edit');
  };
  const agenda = () => state.context.navigate('agenda', { instructor: state.instructor });
  const { startsAt, endsAt } = absenceInstants(draft, school.timeZone);
  const period = startsAt && endsAt ? absenceLabel({ startsAt, endsAt }, school.timeZone) : null;
  return <section className="schedule-page">
    <Button variant="ghost" className="schedule-back" disabled={locked} onClick={close}><ArrowLeft data-icon="inline-start" />Retour aux absences</Button>
    <header className="schedule-heading"><div><span className="schedule-eyebrow">{state.instructorName}</span><h1 ref={heading} tabIndex={-1}>Nouvelle absence</h1></div></header>
    {stage === 'edit' ? <form className="schedule-form" noValidate onSubmit={event => { event.preventDefault(); review(); }}>
      <FieldGroup>
        <div className="schedule-field-row">
          <Field data-invalid={Boolean(showing.start)}><FieldLabel htmlFor="absence-start">Début ({school.timeZone})</FieldLabel><Input id="absence-start" type="datetime-local" value={draft.start} aria-invalid={Boolean(showing.start)} disabled={locked} onChange={event => change({ start: event.target.value })} />{showing.start && <FieldError>{showing.start}</FieldError>}</Field>
          <Field data-invalid={Boolean(showing.end || refusedInterval)}><FieldLabel htmlFor="absence-end">Fin ({school.timeZone})</FieldLabel><Input id="absence-end" type="datetime-local" value={draft.end} aria-invalid={Boolean(showing.end || refusedInterval)} disabled={locked} onChange={event => change({ end: event.target.value })} />{(showing.end || refusedInterval) && <FieldError>{showing.end ?? refusedInterval}</FieldError>}</Field>
        </div>
        <Field data-invalid={Boolean(showing.reason)}><FieldLabel htmlFor="absence-reason">Motif (facultatif)</FieldLabel><Textarea id="absence-reason" value={draft.reason} maxLength={ABSENCE_REASON_LIMIT} rows={3} aria-invalid={Boolean(showing.reason)} disabled={locked} onChange={event => change({ reason: event.target.value })} />{showing.reason && <FieldError>{showing.reason}</FieldError>}</Field>
      </FieldGroup>
      <ScheduleRefusal outcome={refusal} blocked={commands.runner.blockedReason} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={() => { commands.runner.clearOutcome(); state.refresh(); }} />
      <div className="schedule-footer"><Button type="button" variant="ghost" disabled={locked} onClick={close}>Annuler</Button>
        <Button type="submit" disabled={locked || !state.writable}>Relire<ArrowRight data-icon="inline-end" /></Button></div>
    </form> : <div className="schedule-form">
      <h2 className="schedule-review-title">Relire avant d’enregistrer</h2>
      <dl className="schedule-review"><div><dt>Moniteur</dt><dd>{state.instructorName}</dd></div>
        <div><dt>Période</dt><dd>{period ? <><strong>{period.title}</strong><span>{period.detail}</span></> : '—'}</dd></div>
        {draft.reason.trim() && <div><dt>Motif</dt><dd>{draft.reason.trim()}</dd></div>}</dl>
      <CommandFeedback outcome={null} blocked={commands.runner.blockedReason} />
      <ScheduleRefusal outcome={refusal} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={() => { commands.runner.clearOutcome(); state.refresh(); }} />
      <div className="schedule-footer"><Button type="button" variant="outline" disabled={locked} onClick={() => { commands.runner.clearOutcome(); setStage('edit'); }}><ArrowLeft data-icon="inline-start" />Modifier</Button>
        <Button type="button" disabled={locked || !state.writable || Boolean(commands.runner.blockedReason)} onClick={() => void submit()}>{commands.runner.busy ? 'Confirmation…' : 'Ajouter l’absence'}</Button></div>
    </div>}
    <DiscardDialog open={discard} onCancel={() => setDiscard(false)} onDiscard={() => { setDiscard(false); state.setView(null); }} />
  </section>;
}
