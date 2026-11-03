import { useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, ChevronDown, Clock3, Plus } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '../../components/ui/collapsible';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '../../components/ui/dialog';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Field, FieldError, FieldGroup, FieldLabel, FieldLegend, FieldSet } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group';
import { useUnsavedChanges, type Outcome } from '../../console/context';
import type { Availability } from '../../school-api';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { dayRange, draftFromRule, formatCivil, hasRuleProblems, periodLabel, ruleGroups, ruleProblems, sameRuleDraft, weekdayLabels, weekdayNames, weekRows, weekScale,
  type RuleDraft } from './schedule-model';
import { isProvisional, markLabels, type RowMark } from './schedule-projection';
import { DiscardDialog, isFieldRefusal, ScheduleRefusal } from './schedule-feedback';
import { ruleTag, type ScheduleCommands } from './use-schedule-commands';
import type { ScheduleState } from './use-schedule';

const pad = (value: number) => String(value).padStart(2, '0');

/** Ordinary week in force today: text first, a proportional bar only where there is room for it. */
function WeekOverview({ state }: { state: ScheduleState }) {
  const rows = weekRows(state.rules, state.today);
  const { startHour, endHour } = weekScale(rows);
  const span = (endHour - startHour) * 60;
  return <section aria-labelledby="schedule-week-title" className="schedule-week">
    <h2 id="schedule-week-title">Semaine type</h2>
    <ol className="schedule-week-rows">
      <li className="schedule-week-scale" aria-hidden="true"><span /><span /><span className="schedule-week-hours"><span>{pad(startHour)}:00</span><span>{pad(endHour)}:00</span></span></li>
      {rows.map(row => <li key={row.weekday} className="schedule-week-row" data-empty={row.ranges.length === 0}>
        <span className="schedule-week-day">{weekdayNames[row.weekday - 1]}</span>
        <span className="schedule-week-ranges">{row.ranges.length === 0 ? <span className="schedule-muted">Aucune plage</span>
          : row.ranges.map(range => <span key={range.id} className="schedule-range">{range.start}–{range.end}</span>)}</span>
        <span className="schedule-bar" aria-hidden="true">{row.ranges.map(range => <span key={range.id} className="schedule-bar-range"
          style={{ left: `${(range.startMinute - startHour * 60) / span * 100}%`, width: `${(range.endMinute - range.startMinute) / span * 100}%` }} />)}</span>
      </li>)}
    </ol>
  </section>;
}

/** A row followed by the store says so; a request never changes what the school lists, only what this page shows next to it. */
function RuleRow({ rule, mark, state, commands, onEdit }: { rule: Availability; mark: RowMark | undefined; state: ScheduleState; commands: ScheduleCommands; onEdit: () => void }) {
  const label = `${dayRange(rule.weekdays)}, ${rule.localStart}–${rule.localEnd}`;
  const idle = state.writable && !mark && !isProvisional(rule.id);
  return <li className="schedule-rule" data-rule-id={rule.id} data-mark={mark}>
    <div className="schedule-rule-main">
      <span className="schedule-rule-days">{dayRange(rule.weekdays)}</span>
      <span className="schedule-rule-hours"><Clock3 aria-hidden="true" />{rule.localStart}–{rule.localEnd}</span>
      <span className="schedule-muted">{periodLabel(rule)}</span>
      {mark && <Badge variant="outline">{markLabels[mark]}</Badge>}
    </div>
    <div className="schedule-rule-actions">
      <Button variant="outline" disabled={!idle} aria-label={`Modifier l’horaire ${label}`} onClick={onEdit}>Modifier</Button>
      <Button variant="ghost" disabled={!idle} aria-label={`Retirer l’horaire ${label}`} onClick={() => commands.setRemoving({ kind: 'rule', value: rule })}>Retirer</Button>
    </div>
  </li>;
}

export function HoursReading({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  // The week bar above reads the school's hours only; the lists below add what is still to be confirmed.
  const groups = ruleGroups(commands.rules, state.today);
  const open = (ruleId: string | null) => { commands.clearOutcome(); state.setView({ kind: 'rule', ruleId }); };
  const renderList = (rules: Availability[]) => <ul className="schedule-rules">{rules.map(rule => <RuleRow key={rule.id} rule={rule} mark={commands.ruleMarks.get(rule.id)} state={state} commands={commands} onEdit={() => open(rule.id)} />)}</ul>;
  if (commands.rules.length === 0) return <Empty className="schedule-empty"><EmptyHeader><EmptyMedia variant="icon"><Clock3 /></EmptyMedia><EmptyTitle>Aucun horaire de conduite</EmptyTitle></EmptyHeader>
    <EmptyContent><Button disabled={!state.writable} onClick={() => open(null)}><Plus data-icon="inline-start" />Ajouter un horaire</Button></EmptyContent></Empty>;
  return <>
    {state.rules.length > 0 && <WeekOverview state={state} />}
    <section aria-labelledby="schedule-rules-title" className="schedule-section">
      <h2 id="schedule-rules-title">Horaires en vigueur</h2>
      {groups.current.length ? renderList(groups.current) : <p className="schedule-muted">Aucun horaire en vigueur aujourd’hui.</p>}
    </section>
    {groups.upcoming.length > 0 && <section aria-labelledby="schedule-upcoming-title" className="schedule-section"><h2 id="schedule-upcoming-title">À venir</h2>{renderList(groups.upcoming)}</section>}
    {groups.ended.length > 0 && <Collapsible className="schedule-section schedule-ended">
      <CollapsibleTrigger render={<Button variant="ghost" className="schedule-ended-trigger" />}>Horaires terminés ({groups.ended.length})<ChevronDown data-icon="inline-end" /></CollapsibleTrigger>
      <CollapsibleContent>{renderList(groups.ended)}</CollapsibleContent>
    </Collapsible>}
  </>;
}

/** Confirmation of a removal: the hours concerned, what stays untouched, the school's refusal in place. */
export function RuleRemoval({ state, commands }: { state: ScheduleState; commands: ScheduleCommands }) {
  const target = commands.removing?.kind === 'rule' ? commands.removing.value : null;
  const refusal = commands.removalOutcome;
  const blocked = commands.blockedReason('rules');
  return <Dialog open={target !== null} onOpenChange={next => { if (!next) commands.setRemoving(null); }}>
    <DialogContent>
      <DialogHeader><DialogTitle>Retirer cet horaire ?</DialogTitle><DialogDescription>{state.instructorName}</DialogDescription></DialogHeader>
      {target && <dl className="schedule-review"><div><dt>Jours</dt><dd>{dayRange(target.weekdays)}</dd></div><div><dt>Heures</dt><dd>{target.localStart}–{target.localEnd}</dd></div><div><dt>Période</dt><dd>{periodLabel(target)}</dd></div></dl>}
      <p className="schedule-consequence">Ce créneau ne sera plus proposé. Les rendez-vous prévus ne sont pas déplacés.</p>
      <ScheduleRefusal outcome={refusal} blocked={blocked} instructorName={state.instructorName} busy={false}
        onAgenda={() => { commands.setRemoving(null); state.context.navigate('agenda', { instructor: state.instructor }); }}
        onReread={() => { commands.setRemoving(null); state.refresh(); }} />
      <DialogFooter>
        <Button variant="outline" onClick={() => commands.setRemoving(null)}>Garder l’horaire</Button>
        <Button variant="destructive" disabled={Boolean(blocked)} onClick={() => commands.remove()}>Retirer l’horaire</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>;
}

type Stage = 'edit' | 'review';

export function RuleEditor({ state, commands, ruleId, restored }: { state: ScheduleState; commands: ScheduleCommands; ruleId: string | null; restored?: { draft: RuleDraft; outcome: NonNullable<Outcome> } | undefined }) {
  const target = ruleId ? state.rules.find(rule => rule.id === ruleId) ?? null : null;
  // The baseline is the hours read when the editor opened; a later re-read changes the version sent, never the typed draft.
  const baseline = useRef(draftFromRule(target, state.today));
  const [draft, setDraft] = useState<RuleDraft>(restored?.draft ?? baseline.current);
  // What the school refused comes back with the typed draft; the first change the person makes clears it.
  const [returned, setReturned] = useState<NonNullable<Outcome> | null>(restored?.outcome ?? null);
  const tag = ruleTag(ruleId);
  const [stage, setStage] = useState<Stage>('edit');
  const [touched, setTouched] = useState(false);
  const [discard, setDiscard] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, stage);
  const dirty = !sameRuleDraft(draft, baseline.current);
  useUnsavedChanges(dirty);
  // Hours still to be confirmed count for the local overlap hint; the school stays the judge.
  const others = commands.rules.filter(rule => rule.id !== ruleId);
  const problems = ruleProblems(draft, others);
  const gone = ruleId !== null && target === null;
  const blocked = commands.blockedReason('rules');
  const locked = false;
  const change = (patch: Partial<RuleDraft>) => { setReturned(null); commands.clearOutcome(tag); setDraft(previous => ({ ...previous, ...patch })); };
  const close = () => { if (dirty) setDiscard(true); else state.setView(null); };
  const refusal = returned ?? commands.outcomeFor(tag);
  const refusedInterval = isFieldRefusal(refusal) ? refusal?.message : undefined;
  const review = () => { setTouched(true); if (!hasRuleProblems(problems) && !gone && (!ruleId || dirty)) setStage('review'); };
  // Kept by the store: the editor closes and the row says « À confirmer ». Refused on the spot: the draft stays here with the reason.
  const submit = () => { if (commands.saveRule(draft, target) === 'refused') setStage('edit'); };
  const toggle = (values: readonly string[]) => change({ weekdays: values.map(Number).sort((a, b) => a - b) });
  const agenda = () => state.context.navigate('agenda', { instructor: state.instructor });
  const reread = () => { setReturned(null); commands.clearOutcome(tag); state.refresh(); };
  const showing = touched ? problems : {};
  return <section className="schedule-page">
    <Button variant="ghost" className="schedule-back" disabled={locked} onClick={close}><ArrowLeft data-icon="inline-start" />Retour aux horaires</Button>
    <header className="schedule-heading"><div><span className="schedule-eyebrow">{state.instructorName}</span><h1 ref={heading} tabIndex={-1}>{ruleId ? 'Modifier l’horaire' : 'Nouvel horaire'}</h1></div></header>
    {gone && <Alert variant="destructive"><AlertTitle>Cet horaire n’existe plus</AlertTitle><AlertDescription>Il a été retiré ou remplacé. Revenez à la liste pour relire les horaires.</AlertDescription></Alert>}
    {stage === 'edit' ? <form className="schedule-form" noValidate onSubmit={event => { event.preventDefault(); review(); }}>
      <FieldGroup>
        <FieldSet data-invalid={Boolean(showing.weekdays)}>
          <FieldLegend>Jours de conduite</FieldLegend>
          <ToggleGroup multiple variant="outline" className="schedule-days-toggle" aria-label="Jours de conduite" value={draft.weekdays.map(String)} onValueChange={values => toggle(values as string[])} disabled={locked}>
            {weekdayLabels.map((label, index) => <ToggleGroupItem key={label} value={String(index + 1)} aria-label={weekdayNames[index]!}>{label}</ToggleGroupItem>)}
          </ToggleGroup>
          {showing.weekdays && <FieldError>{showing.weekdays}</FieldError>}
        </FieldSet>
        <div className="schedule-field-row">
          <Field data-invalid={Boolean(showing.start || showing.overlap)}><FieldLabel htmlFor="rule-start">Début</FieldLabel><Input id="rule-start" type="time" value={draft.start} aria-invalid={Boolean(showing.start || showing.overlap)} aria-describedby={showing.overlap ? 'rule-overlap' : undefined} disabled={locked} onChange={event => change({ start: event.target.value })} />{showing.start && <FieldError>{showing.start}</FieldError>}</Field>
          <Field data-invalid={Boolean(showing.end || refusedInterval || showing.overlap)}><FieldLabel htmlFor="rule-end">Fin</FieldLabel><Input id="rule-end" type="time" value={draft.end} aria-invalid={Boolean(showing.end || refusedInterval || showing.overlap)} aria-describedby={showing.overlap ? 'rule-overlap' : undefined} disabled={locked} onChange={event => change({ end: event.target.value })} />{(showing.end || refusedInterval) && <FieldError>{showing.end ?? refusedInterval}</FieldError>}</Field>
        </div>
        <div className="schedule-field-row">
          <Field data-invalid={Boolean(showing.from)}><FieldLabel htmlFor="rule-from">Valable dès le</FieldLabel><Input id="rule-from" type="date" value={draft.from} aria-invalid={Boolean(showing.from)} disabled={locked} onChange={event => change({ from: event.target.value })} />{showing.from && <FieldError>{showing.from}</FieldError>}</Field>
          <Field data-invalid={Boolean(showing.until)}><FieldLabel htmlFor="rule-until">Jusqu’au (facultatif)</FieldLabel><Input id="rule-until" type="date" value={draft.until} aria-invalid={Boolean(showing.until)} disabled={locked} onChange={event => change({ until: event.target.value })} />{showing.until && <FieldError>{showing.until}</FieldError>}</Field>
        </div>
        {showing.overlap && <Alert id="rule-overlap" variant="destructive"><AlertTitle>Cet horaire chevauche un autre créneau</AlertTitle><AlertDescription>{dayRange(showing.overlap.weekdays)} · {showing.overlap.localStart}–{showing.overlap.localEnd} · {periodLabel(showing.overlap)}</AlertDescription></Alert>}
      </FieldGroup>
      <CommandFeedback outcome={null} blocked={blocked} />
      <ScheduleRefusal outcome={refusal} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={reread} />
      <div className="schedule-footer"><Button type="button" variant="ghost" disabled={locked} onClick={close}>Annuler</Button>
        <Button type="submit" disabled={locked || gone || !state.writable || (ruleId !== null && !dirty)}>Relire<ArrowRight data-icon="inline-end" /></Button></div>
    </form> : <div className="schedule-form">
      <h2 className="schedule-review-title">Relire avant d’enregistrer</h2>
      <RuleReview draft={draft} before={ruleId ? baseline.current : null} instructorName={state.instructorName} />
      <CommandFeedback outcome={null} blocked={blocked} />
      <ScheduleRefusal outcome={refusal} instructorName={state.instructorName} busy={locked} onAgenda={agenda} onReread={reread} />
      <div className="schedule-footer"><Button type="button" variant="outline" onClick={() => { commands.clearOutcome(tag); setStage('edit'); }}><ArrowLeft data-icon="inline-start" />Modifier</Button>
        <Button type="button" disabled={gone || !state.writable || Boolean(blocked)} onClick={submit}>{ruleId ? 'Enregistrer l’horaire' : 'Ajouter l’horaire'}</Button></div>
    </div>}
    <DiscardDialog open={discard} onCancel={() => setDiscard(false)} onDiscard={() => { setDiscard(false); state.setView(null); }} />
  </section>;
}

/** What will be written. In an edit, every changed line shows the value it replaces. */
function RuleReview({ draft, before, instructorName }: { draft: RuleDraft; before: RuleDraft | null; instructorName: string }) {
  const days = (value: RuleDraft) => dayRange(value.weekdays);
  const hours = (value: RuleDraft) => `${value.start}–${value.end}`;
  const period = (value: RuleDraft) => value.until ? `Du ${formatCivil(value.from)} au ${formatCivil(value.until)}` : `Dès le ${formatCivil(value.from)}`;
  const line = (label: string, read: (value: RuleDraft) => string) => {
    const changed = before !== null && read(before) !== read(draft);
    return <div key={label}><dt>{label}</dt><dd>{changed && <del><span className="visually-hidden">Avant : </span>{read(before!)}</del>}<strong>{read(draft)}</strong></dd></div>;
  };
  return <dl className="schedule-review"><div><dt>Moniteur</dt><dd>{instructorName}</dd></div>{line('Jours', days)}{line('Heures', hours)}{line('Période', period)}</dl>;
}

