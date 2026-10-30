import { useRef } from 'react';
import { ArrowLeft, Plus, Trash2 } from 'lucide-react';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Checkbox } from '../../components/ui/checkbox';
import { Field, FieldError, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { formatHours, LIMITS, type SessionForm } from '../../console/course-model';
import { PortalSelect, type PortalSelectOption } from '../components/portal-select';
import { useHeadingFocus } from '../agenda/use-heading-focus';
import { civilDayLabel, sessionMinutes } from './course-presentation';

interface Option { value: string; label: string }
const nameOf = (options: readonly Option[], id: string) => options.find(item => item.value === id)?.label ?? 'Moniteur à choisir';

/**
 * Compact list of the sessions of a series: one line each, never a form per session. A long series stays a short, scannable list;
 * the session being edited opens alone (see SessionEditor). `before` marks, in a reschedule, the value a changed session replaces.
 */
export function SessionList({ sessions, problems, instructors, before, changed, onEdit, onAdd, locked }: {
  sessions: readonly SessionForm[]; problems: Record<string, string>; instructors: readonly Option[]; before?: readonly SessionForm[];
  changed?: ReadonlySet<string>; onEdit: (key: string) => void; onAdd?: () => void; locked: boolean;
}) {
  return <div className="course-session-block">
    <ol className="course-sessions">{sessions.map((session, index) => {
      const problem = problems[session.key];
      const earlier = before?.[index];
      const moved = changed?.has(session.key) && earlier;
      const label = `${civilDayLabel(session.date)}, ${session.start && session.end ? `${session.start}–${session.end}` : 'heures à choisir'}`;
      return <li key={session.key} data-invalid={Boolean(problem)} data-changed={Boolean(moved)}>
        <span className="course-session-index" aria-hidden="true">{index + 1}</span>
        <div className="course-session-main">
          <strong>{civilDayLabel(session.date)}<span className="course-session-time"> · {session.start && session.end ? `${session.start}–${session.end}` : 'Heures à choisir'}</span></strong>
          <span className="course-muted">{nameOf(instructors, session.instructor)}{!session.attendanceRequired && ' · '}{!session.attendanceRequired && <Badge variant="secondary">Facultative</Badge>}</span>
          {moved && <span className="course-session-before"><span className="visually-hidden">Avant : </span><del>{civilDayLabel(earlier.date)} · {earlier.start}–{earlier.end}{earlier.instructor !== session.instructor ? ` · ${nameOf(instructors, earlier.instructor)}` : ''}</del></span>}
          {problem && <span className="course-session-problem" role="alert">{problem}</span>}
        </div>
        <Button variant="outline" disabled={locked} aria-label={`Modifier la séance ${index + 1}, ${label}`} onClick={() => onEdit(session.key)}>Modifier</Button>
      </li>;
    })}</ol>
    {onAdd && sessions.length < LIMITS.sessions && <Button type="button" variant="outline" className="course-add-session" disabled={locked} onClick={onAdd}><Plus data-icon="inline-start" />Ajouter une séance</Button>}
  </div>;
}

/** One session on its own: date, hours, instructor and, for a draft, whether attendance is required. */
export function SessionEditor({ session, index, total, problem, instructors, timeZone, draft, locked, onChange, onBack, onRemove }: {
  session: SessionForm; index: number; total: number; problem: string | undefined; instructors: readonly PortalSelectOption[]; timeZone: string; draft: boolean;
  locked: boolean; onChange: (patch: Partial<SessionForm>) => void; onBack: () => void; onRemove?: () => void;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useHeadingFocus(heading, session.key, { preventScroll: true });
  const minutes = sessionMinutes(session, timeZone);
  return <div className="course-session-editor">
    <Button type="button" variant="ghost" className="course-back" disabled={locked} onClick={onBack}><ArrowLeft data-icon="inline-start" />Retour à la série</Button>
    <h2 ref={heading} tabIndex={-1}>Séance {index + 1} sur {total}</h2>
    <FieldGroup>
      <Field data-invalid={Boolean(problem)}><FieldLabel htmlFor="session-date">Date</FieldLabel><Input id="session-date" type="date" value={session.date} disabled={locked} onChange={event => onChange({ date: event.target.value })} /></Field>
      <div className="course-field-row">
        <Field data-invalid={Boolean(problem)}><FieldLabel htmlFor="session-start">Début</FieldLabel><Input id="session-start" type="time" value={session.start} disabled={locked} onChange={event => onChange({ start: event.target.value })} /></Field>
        <Field data-invalid={Boolean(problem)}><FieldLabel htmlFor="session-end">Fin</FieldLabel><Input id="session-end" type="time" value={session.end} disabled={locked} aria-describedby={problem ? 'session-problem' : undefined} onChange={event => onChange({ end: event.target.value })} /></Field>
      </div>
      {minutes !== null && <p className="course-muted course-session-length">Durée : {formatHours(minutes)}</p>}
      <PortalSelect id="session-instructor" label="Moniteur" value={session.instructor || null} onValueChange={value => onChange({ instructor: value ?? '' })} options={instructors} disabled={locked} placeholder="Choisir un moniteur" />
      {draft && <Field orientation="horizontal"><Checkbox id="session-attendance" checked={session.attendanceRequired} disabled={locked} onCheckedChange={value => onChange({ attendanceRequired: value === true })} /><FieldLabel htmlFor="session-attendance">Présence obligatoire</FieldLabel></Field>}
      {problem && <FieldError id="session-problem">{problem}</FieldError>}
    </FieldGroup>
    <div className="course-footer course-footer-split">
      {onRemove ? <Button type="button" variant="ghost" className="course-danger" disabled={locked} onClick={onRemove}><Trash2 data-icon="inline-start" />Retirer cette séance</Button> : <span />}
      <Button type="button" disabled={locked} onClick={onBack}>Terminer</Button>
    </div>
  </div>;
}
