import { useState } from 'react';
import { ClipboardCheck } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { Input } from '../../components/ui/input';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group';
import { attendanceCell, attendanceLabels, attendanceStatuses, canMarkAttendance, occurrenceStarted, type AttendanceStatus, type CourseSheet, type CourseSheetRow } from '../../console/course-model';
import { useConsole } from '../../console/context';
import { PortalSelect } from '../components/portal-select';
import { ReadFeedback } from '../agenda/presentation';
import { instantDayLabel, occurrenceTimes } from './course-presentation';
import { attendanceSummary, filterByName } from './participants-model';
import { FeedbackText } from './participants-parts';
import { feedbackKey, type CourseParticipants } from './use-course-participants';

/**
 * The call of one named session. One line per participant, the state next to the name and three choices under it:
 * unset, absent, excused and present stay four different things, and nothing is ticked on anyone's behalf.
 */
export function AttendanceTab({ state, occurrenceId, onOccurrence, now }: { state: CourseParticipants; occurrenceId: string; onOccurrence: (id: string) => void; now: number }) {
  const { school } = useConsole();
  const [search, setSearch] = useState('');
  const sheet: CourseSheet | undefined = state.sheet;
  if (!sheet) return <ReadFeedback loaded={state.sheetRead} label="Lecture de la feuille d’appel" />;
  const timeZone = school.timeZone;
  const occurrence = state.occurrences.find(item => item.id === occurrenceId) ?? state.occurrences[0];
  if (!occurrence) return <Empty className="participants-empty"><EmptyHeader><EmptyMedia variant="icon"><ClipboardCheck /></EmptyMedia><EmptyTitle>Aucune séance</EmptyTitle></EmptyHeader></Empty>;
  const started = occurrenceStarted(occurrence, now);
  const people = sheet.rows.filter(row => row.status === 'ACTIVE');
  const shown = filterByName(people, search);
  const summary = attendanceSummary(sheet.rows, occurrence.id);
  const options = state.occurrences.map(item => ({ value: item.id, label: `Séance ${item.position} · ${instantDayLabel(item.startsAt, timeZone)} · ${occurrenceTimes(item, timeZone)}` }));
  const choose = (row: CourseSheetRow, status: string | undefined) => { if (status && (attendanceStatuses as readonly string[]).includes(status)) void state.mark(row, occurrence.id, status as AttendanceStatus); };
  return <div className="participants-tab">
    <ReadFeedback loaded={state.sheetRead} label="Lecture de la feuille d’appel" />
    <PortalSelect id="attendance-session" label="Séance de l’appel" value={occurrence.id} onValueChange={value => { if (value) onOccurrence(value); }} options={options} disabled={state.locked} />
    <div className="participants-session"><h2>Séance {occurrence.position} sur {state.occurrences.length}</h2>
      <p className="course-muted">{instantDayLabel(occurrence.startsAt, timeZone)} · {occurrenceTimes(occurrence, timeZone)} · {occurrence.instructorDisplayName}{!occurrence.attendanceRequired && ' · '}{!occurrence.attendanceRequired && <Badge variant="secondary">Facultative</Badge>}</p>
      {started && <p className="participants-counts" aria-label="Résumé de l’appel"><span><strong>{summary.present}</strong> présents</span><span><strong>{summary.absent}</strong> absents</span><span><strong>{summary.excused}</strong> excusés</span><span><strong>{summary.unset}</strong> non renseignés</span></p>}
      {!started && <p className="course-muted" role="status">Cette séance n’a pas encore commencé.</p>}</div>
    {people.length > 8 && <Input type="search" aria-label="Rechercher un participant" placeholder="Rechercher un participant" value={search} onChange={event => setSearch(event.target.value)} />}
    {people.length === 0 ? <p className="course-muted">Aucun inscrit à appeler.</p> : shown.length === 0 ? <p className="course-muted" role="status">Aucun participant trouvé.</p>
      : <ul className="participants-list">{shown.map(row => {
        const cell = attendanceCell(row, occurrence.id);
        const editable = canMarkAttendance(sheet, row, occurrence, now);
        return <li key={row.enrollmentId} className="participants-call">
          <div className="participants-main"><strong>{row.learnerDisplayName || 'Élève'}</strong>
            <span className="participants-state" data-state={cell.status ?? 'unset'}>{cell.status ? attendanceLabels[cell.status] : 'Non renseigné'}</span>
            <FeedbackText feedback={state.feedback[feedbackKey('call', row.enrollmentId)]} /></div>
          {editable ? <ToggleGroup className="participants-choices" variant="outline" aria-label={`Présence de ${row.learnerDisplayName || 'cet élève'}`} value={cell.status ? [cell.status] : []} disabled={state.locked}
            onValueChange={values => choose(row, (values as string[]).find(value => value !== cell.status))}>
            {attendanceStatuses.map(status => <ToggleGroupItem key={status} value={status}>{attendanceLabels[status]}</ToggleGroupItem>)}</ToggleGroup>
            : <span className="course-muted">{started ? 'Appel indisponible' : 'À venir'}</span>}
        </li>;
      })}</ul>}
  </div>;
}
