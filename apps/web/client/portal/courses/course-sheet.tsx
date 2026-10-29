import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, CalendarClock, ChevronDown, Settings2, UsersRound, XCircle } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '../../components/ui/dropdown-menu';
import { cancellationLabel, formatHours, type CourseCatalogue, type CourseSeries } from '../../console/course-model';
import { useConsole } from '../../console/context';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { CancelSeriesDialog, CapacityDialog } from './course-changes';
import { CourseNotice } from './course-notice';
import { CourseParticipantsEntry } from './course-participants-slot';
import { instantDateTime, instantDayLabel, languageLabel, occurrenceTimes, seriesStateLabel } from './course-presentation';
import { CourseReschedule } from './course-reschedule';

/**
 * A course as people read it: title, dates, instructors and places first. Changing it is a separate, deliberate action:
 * the capacity, the dates of the same sessions, or the cancellation of the whole series.
 */
export function CourseSheet({ series, catalogue, occurrenceId, notice, onClose, onChanged, onReread }: {
  series: CourseSeries; catalogue: CourseCatalogue | undefined; occurrenceId: string | undefined; notice: string | null; onClose: () => void;
  onChanged: (series: CourseSeries | null, message: string) => void; onReread: () => void;
}) {
  const { school } = useConsole();
  const timeZone = school.timeZone;
  const [dialog, setDialog] = useState<'capacity' | 'cancel' | null>(null);
  const [rescheduling, setRescheduling] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null);
  const selected = useRef<HTMLLIElement>(null);
  useHeadingFocus(heading, series.id);
  useEffect(() => { selected.current?.scrollIntoView({ block: 'nearest' }); }, [occurrenceId, series.id]);
  const state = seriesStateLabel(series);
  const manageable = series.canManage && series.status === 'PUBLISHED' && Date.parse(series.lastEndsAt) > Date.now();
  const missing = occurrenceId !== undefined && !series.occurrences.some(item => item.id === occurrenceId);
  const done = (next: CourseSeries | null, message: string) => { setDialog(null); setRescheduling(false); onChanged(next, message); };

  if (rescheduling && catalogue) return <CourseReschedule series={series} catalogue={catalogue} onBack={() => setRescheduling(false)} onChanged={done} onReread={onReread} />;
  const language = languageLabel(series.teachingLanguage);
  return <section className="course-page">
    <CourseNotice message={notice} />
    <Button variant="ghost" className="course-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>
    <header className="course-heading"><div><span className="course-eyebrow">{series.typeTitle}</span><h1 ref={heading} tabIndex={-1}>{series.title}</h1></div>
      <div className="course-heading-actions">{state && <Badge variant="secondary">{state}</Badge>}
        {manageable && <DropdownMenu><DropdownMenuTrigger render={<Button variant="outline" />}><Settings2 data-icon="inline-start" />Gérer<ChevronDown data-icon="inline-end" /></DropdownMenuTrigger>
          <DropdownMenuContent align="end"><DropdownMenuGroup>
            <DropdownMenuItem onClick={() => setDialog('capacity')}><UsersRound />Modifier la capacité</DropdownMenuItem>
            <DropdownMenuItem disabled={!catalogue} onClick={() => setRescheduling(true)}><CalendarClock />Modifier les dates</DropdownMenuItem></DropdownMenuGroup>
            <DropdownMenuSeparator /><DropdownMenuGroup><DropdownMenuItem variant="destructive" onClick={() => setDialog('cancel')}><XCircle />Annuler toute la série</DropdownMenuItem></DropdownMenuGroup></DropdownMenuContent></DropdownMenu>}</div></header>
    {missing && <Alert variant="destructive"><AlertTitle>Séance indisponible</AlertTitle><AlertDescription>Cette séance n’apparaît plus dans le cours. Les séances actuelles sont listées ci-dessous.</AlertDescription></Alert>}
    <div className="course-layout">
      <div className="course-main">
        <section aria-labelledby="course-sheet-sessions"><h2 id="course-sheet-sessions">Séances</h2>
          <ol className="course-sessions course-sessions-static" data-cancelled={series.status === 'CANCELLED'}>{series.occurrences.map(item => <li key={item.id} ref={item.id === occurrenceId ? selected : undefined}
            id={`course-occurrence-${item.id}`} data-selected={item.id === occurrenceId} aria-current={item.id === occurrenceId ? 'true' : undefined}>
            <span className="course-session-index" aria-hidden="true">{item.position}</span>
            <div className="course-session-main"><strong>{instantDayLabel(item.startsAt, timeZone)}<span className="course-session-time"> · {occurrenceTimes(item, timeZone)}</span></strong>
              <span className="course-muted">{item.instructorDisplayName}{!item.attendanceRequired && ' · '}{!item.attendanceRequired && <Badge variant="secondary">Facultative</Badge>}</span></div></li>)}</ol>
        </section>
        {series.description && <p className="course-prose">{series.description}</p>}
        {series.conditions && <section><h2>Conditions</h2><p className="course-prose">{series.conditions}</p></section>}
      </div>
      <aside className="course-aside">
        <CourseParticipantsEntry series={series} />
        <dl className="course-facts">
          <div><dt>Responsable</dt><dd>{series.responsibleDisplayName || 'Non renseigné'}</dd></div>
          {series.location && <div><dt>Lieu</dt><dd>{series.location}</dd></div>}
          {language && <div><dt>Langue</dt><dd>{language}</dd></div>}
          <div><dt>Durée</dt><dd>{formatHours(series.totalMinutes)}</dd></div>
          {series.minParticipants !== null && <div><dt>Minimum</dt><dd>{series.minParticipants}</dd></div>}
          <div><dt>Annulation libre</dt><dd>{series.selfCancelHours === 0 ? cancellationLabel(0).replace('Annulation libre ', '') : `jusqu’au ${instantDateTime(series.selfCancellationDeadline, timeZone)}`}</dd></div>
        </dl>
      </aside>
    </div>
    <CapacityDialog series={series} open={dialog === 'capacity'} onClose={() => setDialog(null)} onChanged={done} onReread={onReread} />
    <CancelSeriesDialog series={series} open={dialog === 'cancel'} onClose={() => setDialog(null)} onChanged={done} onReread={onReread} />
  </section>;
}
