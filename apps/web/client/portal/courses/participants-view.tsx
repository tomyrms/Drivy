import { useEffect, useRef, useState } from 'react';
import { ArrowLeft } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Button } from '../../components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '../../components/ui/tabs';
import type { CourseSeries } from '../../console/course-model';
import { CommandFeedback } from '../agenda/presentation';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { AttendanceTab } from './participants-attendance';
import { CompletionTab } from './participants-completion';
import { defaultOccurrenceId } from './participants-model';
import { PaymentsTab } from './participants-payments';
import { RosterTab } from './participants-roster';
import { useCourseParticipants } from './use-course-participants';
import './participants.css';

export type ParticipantTask = 'roster' | 'attendance' | 'payments' | 'completion';

/**
 * The people of a published course, one task at a time: enrolments and waiting list, the call of one named session, settlements,
 * internal validation. A task is offered only when the school's own rights, read with the sheet, allow it.
 */
export function ParticipantsView({ series, task, occurrenceId, onBack }: { series: CourseSeries; task: ParticipantTask; occurrenceId: string | undefined; onBack: () => void }) {
  const state = useCourseParticipants(series);
  const [now, setNow] = useState(Date.now);
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 30_000); return () => window.clearInterval(timer); }, []);
  const rights = state.sheet?.rights;
  const tasks: { key: ParticipantTask; label: string }[] = [
    ...(series.canManage ? [{ key: 'roster' as const, label: 'Inscrits' }] : []),
    ...(rights?.canTakeAttendance ? [{ key: 'attendance' as const, label: 'Appel' }] : []),
    ...(rights?.canRecordPayment ? [{ key: 'payments' as const, label: 'Règlements' }] : []),
    ...(rights?.canValidate ? [{ key: 'completion' as const, label: 'Validation' }] : []),
  ];
  const [chosen, setChosen] = useState<ParticipantTask>(task);
  const current = tasks.some(item => item.key === chosen) ? chosen : tasks[0]?.key;
  // The session of the call is kept when the person moves between tasks; a session asked for from the agenda wins at first.
  const [occurrence, setOccurrence] = useState(occurrenceId ?? '');
  const sessionId = defaultOccurrenceId(state.occurrences, occurrence || undefined, now);
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, series.id);
  const denied = state.sheetRead.status === 'error' && !series.canManage;
  return <section className="course-page participants-page">
    <Button variant="ghost" className="course-back" onClick={onBack}><ArrowLeft data-icon="inline-start" />Retour au cours</Button>
    <header className="course-heading"><div><span className="course-eyebrow">{series.title}</span><h1 ref={heading} tabIndex={-1}>Participants</h1></div></header>
    <CommandFeedback outcome={state.runner.outcome?.needsLogin ? state.runner.outcome : null} blocked={state.runner.blockedReason} />
    {denied && <Alert variant="destructive"><AlertTitle>Participants indisponibles</AlertTitle><AlertDescription>{state.sheetRead.error}</AlertDescription>
      <div className="course-actions"><Button variant="outline" onClick={state.reread}>Réessayer</Button></div></Alert>}
    {!denied && tasks.length === 0 && state.sheetRead.status !== 'loading' && <Alert><AlertTitle>Aucune tâche disponible</AlertTitle><AlertDescription>Vos accès ne permettent pas de suivre les participants de ce cours.</AlertDescription></Alert>}
    {current && <Tabs value={current} onValueChange={value => setChosen(value as ParticipantTask)} className="participants-tabs">
      <TabsList aria-label="Tâches des participants">{tasks.map(item => <TabsTrigger key={item.key} value={item.key}>{item.label}</TabsTrigger>)}</TabsList>
      <TabsContent value="roster"><RosterTab state={state} series={series} now={now} /></TabsContent>
      <TabsContent value="attendance"><AttendanceTab state={state} occurrenceId={sessionId} onOccurrence={setOccurrence} now={now} /></TabsContent>
      <TabsContent value="payments"><PaymentsTab state={state} /></TabsContent>
      <TabsContent value="completion"><CompletionTab state={state} series={series} /></TabsContent>
    </Tabs>}
  </section>;
}
