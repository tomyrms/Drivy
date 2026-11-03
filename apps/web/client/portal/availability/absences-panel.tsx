import { useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, CalendarOff, Plus } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { Textarea } from '../../components/ui/textarea';
import { useUnsavedChanges, type Outcome } from '../../console/context';
import type { Closure } from '../../school-api';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { ABSENCE_REASON_LIMIT, absenceInstants, absenceLabel, absenceProblems, emptyAbsenceDraft, type AbsenceDraft } from './schedule-model';
import { isProvisional, markLabels, type RowMark } from './schedule-projection';
import { DiscardDialog, isFieldRefusal, ScheduleRefusal } from './schedule-feedback';
import { ABSENCE_TAG, type ScheduleCommands } from './use-schedule-commands';
import type { ScheduleState } from './use-schedule';

function AbsenceRow({ item, mark, state, commands }: { item: Closure; mark: RowMark | undefined; state: ScheduleState; commands: ScheduleCommands }) {
  const { school } = state.context;
  const label = absenceLabel(item, school.timeZone);
  return <li className="schedule-rule" data-closure-id={item.id} data-mark={mark}>
    <div className="schedule-rule-main schedule-absence-main">
      <span className="schedule-rule-days"><time dateTime={item.startsAt}>{label.title}</time></span>
      <span className="schedule-muted">{label.detail}</span>
      {item.reason && <span className="schedule-reason">{item.reason}</span>}
      {mark && <Badge variant="outline">{markLabels[mark]}</Badge>}
    </div>
    <div className="schedule-rule-actions">
      <Button variant="ghost" disabled={!state.writable || Boolean(mark) || isProvisional(item.id)} aria-label={`Retirer l’absence du ${label.title}`} onClick={() => commands.setRemoving({ kind: 'absence', value: item })}>Retirer</Button>
    </div>
  </li>;
}

export function AbsencesReading({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const open = () => { commands.clearOutcome(); state.setView({ kind: 'absence' }); };
  if (commands.absences.length === 0) return <Empty className="schedule-empty"><EmptyHeader><EmptyMedia variant="icon"><CalendarOff /></EmptyMedia><EmptyTitle>Aucune absence prévue</EmptyTitle></EmptyHeader>
    <EmptyContent><Button disabled={!state.writable} onClick={open}><Plus data-icon="inline-start" />Ajouter une absence</Button></EmptyContent></Empty>;
  return <section aria-labelledby="schedule-absences-title" className="schedule-section">
    <h2 id="schedule-absences-title">Absences prévues</h2>
    <ul className="schedule-rules">{commands.absences.map(item => <AbsenceRow key={item.id} item={item} mark={commands.absenceMarks.get(item.id)} state={state} commands={commands} />)}</ul>
  </section>;
}

export function AbsenceRemoval({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const target = commands.removing?.kind === 'absence' ? commands.removing.value : null;
  const label = target ? absenceLabel(target, state.context.school.timeZone) : null;
  const blocked = commands.blockedReason('closures');
  return <Dialog open={target !== null} onOpenChange={next => { if (!next) commands.setRemoving(null); }}>
    <DialogContent>
      <DialogHeader><DialogTitle>Retirer cette absence ?</DialogTitle><DialogDescription>{state.instructorName}</DialogDescription></DialogHeader>
      {target && label && <dl className="schedule-review"><div><dt>Période</dt><dd>{label.title}<br />{label.detail}</dd></div>{target.reason && <div><dt>Motif</dt><dd>{target.reason}</dd></div>}</dl>}
      <p className="schedule-consequence">Le moniteur pourra de nouveau être proposé sur cette période, selon ses horaires.</p>
      <ScheduleRefusal outcome={commands.removalOutcome} blocked={blocked} instructorName={state.instructorName} busy={false}
        onAgenda={() => { commands.setRemoving(null); state.context.navigate('agenda', { instructor: state.instructor }); }}
        onReread={() => { commands.setRemoving(null); state.refresh(); }} />
      <DialogFooter>
        <Button variant="outline" onClick={() => commands.setRemoving(null)}>Garder l’absence</Button>
        <Button variant="destructive" disabled={Boolean(blocked)} onClick={() => commands.remove()}>Retirer l’absence</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}

export function AbsenceEditor({ state, commands, restored }: { state: ScheduleState; commands: ScheduleCommands; restored?: { draft: AbsenceDraft; outcome: NonNullable<Outcome> } | undefined }) {
  const { school } = state.context;
  const [draft, setDraft] = useState<AbsenceDraft>(restored?.draft ?? emptyAbsenceDraft);
  // What the school refused comes back with the typed draft; the first change the person makes clears it.
  const [returned, setReturned] = useState<NonNullable<Outcome> | null>(restored?.outcome ?? null);
  const [stage, setStage] = useState<'edit' | 'review'>('edit');
  const [touched, setTouched] = useState(false);
  const [discard, setDiscard] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, stage);
  const dirty = draft.start !== '' || draft.end !== '' || draft.reason !== '';
  useUnsavedChanges(dirty);
  const problems = absenceProblems(draft, school.timeZone);
  const locked = false;
  const blocked = commands.blockedReason('closures');
  const refusal = returned ?? commands.outcomeFor(ABSENCE_TAG);
  const refusedInterval = isFieldRefusal(refusal) ? refusal?.message : undefined;
  const showing = touched ? problems : {};
  const change = (patch: Partial<AbsenceDraft>) => { setReturned(null); commands.clearOutcome(ABSENCE_TAG); setDraft(previous => ({ ...previous, ...patch })); };
  const close = () => { if (dirty) setDiscard(true); else state.setView(null); };
  const review = () => { setTouched(true); if (Object.keys(problems).length === 0) setStage('review'); };
  // Kept by the store: the editor closes and the row says « À confirmer ». Refused on the spot: the draft stays here with the reason.
  const submit = () => { if (commands.saveAbsence(draft) !== 'kept') setStage('edit'); };
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
        <Field data-invalid={Boolean(showing.reason)}><FieldLabel htmlFor="absence-reason">Motif (facultatif)</FieldLabel><Textarea id="absence-reason" value={draft.reason} maxLength={ABSENCE_REASON_LIMIT} rows={3} aria-describedby="absence-reason-help" aria-invalid={Boolean(showing.reason)} disabled={locked} onChange={event => change({ reason: event.target.value })} /><FieldDescription id="absence-reason-help">Visible par l’administration et les moniteurs de l’école.</FieldDescription>{showing.reason && <FieldError>{showing.reason}</FieldError>}</Field>
      </FieldGroup>
      <ScheduleRefusal outcome={refusal} blocked={blocked} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={() => { setReturned(null); commands.clearOutcome(ABSENCE_TAG); state.refresh(); }} />
      <div className="schedule-footer"><Button type="button" variant="ghost" disabled={locked} onClick={close}>Annuler</Button>
        <Button type="submit" disabled={locked || !state.writable}>Relire<ArrowRight data-icon="inline-end" /></Button></div>
    </form> : <div className="schedule-form">
      <h2 className="schedule-review-title">Relire avant d’enregistrer</h2>
      <dl className="schedule-review"><div><dt>Moniteur</dt><dd>{state.instructorName}</dd></div>
        <div><dt>Période</dt><dd>{period ? <><strong>{period.title}</strong><span>{period.detail}</span></> : '—'}</dd></div>
        {draft.reason.trim() && <div><dt>Motif</dt><dd>{draft.reason.trim()}</dd></div>}</dl>
      <CommandFeedback outcome={null} blocked={blocked} />
      <ScheduleRefusal outcome={refusal} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={() => { setReturned(null); commands.clearOutcome(ABSENCE_TAG); state.refresh(); }} />
      <div className="schedule-footer"><Button type="button" variant="outline" onClick={() => { commands.clearOutcome(ABSENCE_TAG); setStage('edit'); }}><ArrowLeft data-icon="inline-start" />Modifier</Button>
        <Button type="button" disabled={!state.writable || Boolean(blocked)} onClick={submit}>Ajouter l’absence</Button></div>
    </div>}
    <DiscardDialog open={discard} onCancel={() => setDiscard(false)} onDiscard={() => { setDiscard(false); state.setView(null); }} />
  </section>;
}
