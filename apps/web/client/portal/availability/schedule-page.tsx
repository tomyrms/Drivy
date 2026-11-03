import { useRef } from 'react';
import { ArrowLeft, CalendarDays, Plus, UsersRound } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Empty, EmptyContent, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { PortalSelect } from '../components/portal-select';
import { CommandFeedback, ReadFeedback } from '../agenda/presentation';
import { ScheduleRefusals } from './schedule-feedback';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { AbsenceEditor, AbsenceRemoval, AbsencesReading } from './absences-panel';
import { HoursReading, RuleEditor, RuleRemoval } from './hours-panel';
import { useSchedule, type ScheduleState } from './use-schedule';
import { useScheduleCommands } from './use-schedule-commands';
import './availability.css';

type Section = 'disponibilites' | 'absences';
const copy: Record<Section, { title: string; add: string; reading: string }> = {
  disponibilites: { title: 'Disponibilités', add: 'Ajouter un horaire', reading: 'Lecture des horaires' },
  absences: { title: 'Absences', add: 'Ajouter une absence', reading: 'Lecture des absences' },
};

function InstructorChoice({ state }: { state: ScheduleState }) {
  if (state.options.length === 1) return <div className="schedule-instructor"><span className="schedule-eyebrow">Moniteur</span><strong>{state.instructorName}</strong></div>;
  return <PortalSelect id="schedule-instructor" label="Moniteur" value={state.instructor || null} onValueChange={state.chooseInstructor}
    options={state.options} searchable={state.options.length > 6} className="schedule-instructor" />;
}

function SchedulePage({ section }: { section: Section }) {
  const state = useSchedule();
  const commands = useScheduleCommands(state);
  const { context, loaded, view } = state;
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, `${section}:${view === null}`);
  const text = copy[section];
  if (view?.kind === 'rule' && section === 'disponibilites') return <RuleEditor key={`${state.instructor}:${view.ruleId ?? 'new'}`} state={state} commands={commands} ruleId={view.ruleId} restored={view.restored} />;
  if (view?.kind === 'absence' && section === 'absences') return <AbsenceEditor key={state.instructor} state={state} commands={commands} restored={view.restored} />;
  const ready = loaded.status === 'ready' && loaded.data !== undefined;
  const noInstructor = ready && state.instructors.length === 0;
  return <section className="schedule-page">
    <header className="schedule-heading"><div><span className="schedule-eyebrow">Planning de l’école</span><h1 ref={heading} tabIndex={-1}>{text.title}</h1></div>
      {ready && !noInstructor && <Button disabled={!state.writable} onClick={() => { commands.clearOutcome(); state.setView(section === 'absences' ? { kind: 'absence' } : { kind: 'rule', ruleId: null }); }}>
        <Plus data-icon="inline-start" />{text.add}</Button>}</header>
    <ReadFeedback loaded={loaded} label={text.reading} />
    {context.routeQuery?.from === 'equipe' && context.routeQuery.instructor && <Button variant="ghost" className="schedule-back" onClick={() => context.navigate('equipe', { selection: context.routeQuery?.instructor })}><ArrowLeft data-icon="inline-start" />Retour au membre</Button>}
    {noInstructor && <Empty className="schedule-empty"><EmptyHeader><EmptyMedia variant="icon"><UsersRound /></EmptyMedia><EmptyTitle>Aucun moniteur</EmptyTitle></EmptyHeader>
      <EmptyContent><Button variant="outline" onClick={() => context.navigate('equipe')}>Ouvrir l’équipe</Button></EmptyContent></Empty>}
    {ready && !noInstructor && <>
      <div className="schedule-toolbar"><InstructorChoice state={state} />
        <Button variant="outline" onClick={() => context.navigate('agenda', { instructor: state.instructor })}><CalendarDays data-icon="inline-start" />Voir l’agenda</Button></div>
      {state.partial && <Alert><AlertTitle>Lecture partielle</AlertTitle><AlertDescription>Tous les horaires n’ont pas pu être lus. Les modifications attendent une lecture complète pour ne masquer aucun chevauchement.</AlertDescription></Alert>}
      {context.school.status !== 'ACTIVE' && <Alert><AlertTitle>École inactive</AlertTitle><AlertDescription>Les horaires ne peuvent pas être modifiés tant que l’école n’est pas active.</AlertDescription></Alert>}
      <CommandFeedback outcome={commands.confirmation} />
      <ScheduleRefusals refusals={commands.refusals} disabled={state.view !== null} onResume={index => { const item = commands.refusals[index]; if (item) commands.resume(item); }}
        onDismiss={index => { const item = commands.refusals[index]; if (item) commands.dismiss(item); }} />
      {section === 'disponibilites' ? <HoursReading state={state} commands={commands} /> : <AbsencesReading state={state} commands={commands} />}
    </>}
    {section === 'disponibilites' ? <RuleRemoval state={state} commands={commands} /> : <AbsenceRemoval state={state} commands={commands} />}
  </section>;
}

export const AvailabilityPilot = () => <SchedulePage section="disponibilites" />;
export const AbsencesPilot = () => <SchedulePage section="absences" />;
