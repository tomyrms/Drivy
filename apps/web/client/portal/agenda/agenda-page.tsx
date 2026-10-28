import { useEffect, useRef, type CSSProperties } from 'react';
import { ArrowLeft, CalendarDays, ChevronLeft, ChevronRight, Clock3, MapPin, Plus, RefreshCw, Search, SlidersHorizontal, TriangleAlert, Users } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { Badge } from '../../components/ui/badge';
import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';
import { Field, FieldGroup, FieldLabel } from '../../components/ui/field';
import { Input } from '../../components/ui/input';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group';
import { addDays, civilDateIn, formatDayHeading, formatTimeRange, formatWeek, lessonPhase } from '../../agenda-model';
import type { AgendaEvent } from '../../console/agenda-projection';
import { courseSeriesSchema } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { readSchool } from '../../school-api';
import { RequestFailure } from '../../protocol';
import { PortalSelect } from '../components/portal-select';
import { useAgenda } from './use-agenda';
import { calendarInterval, calendarLanes } from './calendar-layout';
import { LessonWorkspace } from './lesson-workspace';
import { dateTime, phaseLabels, ReadFeedback } from './presentation';
import './agenda.css';

type AgendaState = ReturnType<typeof useAgenda>;
const weekday = (date: string) => new Intl.DateTimeFormat('fr-CH', { weekday: 'short', timeZone: 'UTC' }).format(new Date(`${date}T12:00:00Z`));

export function AgendaPilot() {
  const state = useAgenda();
  const { school, membership } = state.context;
  const selection = state.selection;
  if (selection && 'lesson' in selection) return <LessonWorkspace key={selection.lesson ?? 'new'} lessonId={selection.lesson ?? null} onClose={state.close} onSaved={state.refresh}
    onDossier={(learnerId, lessonId) => state.context.navigate('eleves', { selection: learnerId, lesson: lessonId, from: 'agenda', week: state.monday, day: state.day, instructor: state.instructor || undefined })} />;
  if (selection && 'course' in selection && selection.course) return <CourseContext key={selection.course} courseId={selection.course} occurrenceId={selection.occurrence} onClose={state.close} />;
  const dayView = state.compact || state.presentation === 'day';
  const today = civilDateIn(school.timeZone, state.now);
  const visibleDays = dayView ? state.days.filter(item => item.day === state.day) : state.days;
  const events = visibleDays.flatMap(day => day.items);
  const intervals = events.map(event => calendarInterval(event, school.timeZone));
  const startHour = Math.min(8, ...intervals.map(item => Math.floor(item.start / 60)));
  const endHour = Math.max(19, ...intervals.map(item => Math.ceil(Math.max(item.end, item.start + 72) / 60)));
  const canPlan = membership.roles.includes('ADMIN') || membership.roles.includes('INSTRUCTOR');
  return <section className="agenda-page">
    <header className="agenda-heading"><div><span className="agenda-eyebrow">Planning de l’école</span><h1 id="portal-agenda-title" tabIndex={-1}>Agenda</h1></div>
      {canPlan && <Button onClick={() => state.openLesson(null)}><Plus data-icon="inline-start" />Planifier une leçon</Button>}</header>
    <div className="agenda-toolbar"><div className="agenda-period"><div className="agenda-arrows"><Button variant="outline" size="icon" aria-label={dayView ? 'Jour précédent' : 'Semaine précédente'} onClick={() => state.chooseDay(addDays(state.day, dayView ? -1 : -7))}><ChevronLeft /></Button><Button variant="outline" size="icon" aria-label={dayView ? 'Jour suivant' : 'Semaine suivante'} onClick={() => state.chooseDay(addDays(state.day, dayView ? 1 : 7))}><ChevronRight /></Button></div><h2>{dayView ? formatDayHeading(state.day) : formatWeek(state.monday)}</h2></div>
      <div className="agenda-actions"><Button variant="outline" onClick={() => state.chooseDay(today)}>Aujourd’hui</Button><Button variant="outline" size="icon" aria-label="Actualiser l’agenda" onClick={state.refresh}><RefreshCw /></Button><Button variant="outline" size="icon" aria-label="Filtres et date" aria-expanded={state.filtersOpen} onClick={() => state.setFiltersOpen(!state.filtersOpen)}><SlidersHorizontal /></Button>
        {!state.compact && <ToggleGroup value={[state.presentation]} onValueChange={values => { if (values[0] === 'week' || values[0] === 'day') state.setPresentation(values[0]); }} aria-label="Présentation de l’agenda" variant="outline"><ToggleGroupItem value="day">Jour</ToggleGroupItem><ToggleGroupItem value="week">Semaine</ToggleGroupItem></ToggleGroup>}
      </div></div>
    {state.filtersOpen && <FieldGroup className="agenda-filters"><Field><FieldLabel htmlFor="agenda-date">Aller à la date</FieldLabel><Input id="agenda-date" type="date" value={state.day} onChange={event => { if (/^\d{4}-\d{2}-\d{2}$/.test(event.target.value)) state.chooseDay(event.target.value); }} /></Field>
      <Field><FieldLabel htmlFor="agenda-search">Élève · semaine affichée</FieldLabel><div className="agenda-search"><Search aria-hidden="true" /><Input id="agenda-search" type="search" value={state.search} onChange={event => state.setSearch(event.target.value)} placeholder="Nom de l’élève" /></div></Field>
      <PortalSelect id="agenda-instructor-filter" label="Moniteur" value={state.instructor || 'all'} onValueChange={value => state.chooseInstructor(value === 'all' ? '' : value ?? '')} options={[{ value: 'all', label: 'Tous les moniteurs' }, ...state.instructorOptions]} searchable />
      {(state.search || state.instructor) && <Button variant="ghost" onClick={() => { state.setSearch(''); state.chooseInstructor(''); }}>Effacer les filtres</Button>}
    </FieldGroup>}
    {!state.filtersOpen && (state.search || state.instructor) && <div className="agenda-active-filters"><Badge variant="secondary">{state.search ? `Élève : ${state.search}` : ''}{state.search && state.instructor ? ' · ' : ''}{state.instructor ? state.memberName(state.instructor) : ''}</Badge><Button variant="ghost" onClick={() => { state.setSearch(''); state.chooseInstructor(''); }}>Effacer</Button></div>}
    <div className="agenda-notices"><ReadFeedback loaded={state.lessons} label="Lecture des leçons" /><ReadFeedback loaded={state.directory} label="Lecture de l’annuaire" /><ReadFeedback loaded={state.courses} label="Lecture des cours" />
      {state.partial && <Alert><AlertTitle>Vue partielle</AlertTitle><AlertDescription>Tous les rendez-vous n’ont pas pu être lus. Les créneaux vides ne prouvent pas une disponibilité.</AlertDescription></Alert>}
      {state.searching && state.directory.status !== 'ready' && <Alert><AlertTitle>Recherche en attente</AlertTitle><AlertDescription>Les leçons restent affichées jusqu’à la lecture de l’annuaire.</AlertDescription></Alert>}
    </div>
    {dayView ? <><nav className="agenda-day-strip" aria-label="Jours de la semaine">{state.days.map(day => <Button variant="ghost" key={day.day} data-today={day.day === today} aria-current={day.day === state.day ? 'date' : undefined} onClick={() => state.chooseDay(day.day)}><span>{weekday(day.day)}</span><strong>{Number(day.day.slice(-2))}</strong><span className="agenda-day-dot" data-has-events={day.items.length > 0} /></Button>)}</nav>
      <div className="agenda-day-list">{events.map(event => <EventEntry key={event.key} event={event} state={state} />)}{events.length === 0 && state.emptyConfirmed && <div className="agenda-empty"><CalendarDays aria-hidden="true" /><h3>{state.searching ? 'Aucune leçon pour cet élève' : 'Aucun rendez-vous ce jour'}</h3>{canPlan && !state.searching && <Button variant="outline" onClick={() => state.openLesson(null)}>Planifier une leçon</Button>}</div>}</div>
    </> : <div className="agenda-week"><div className="agenda-week-head"><span className="agenda-time-zone">{school.timeZone.split('/').at(-1)}</span>{state.days.map(day => <Button key={day.day} variant="ghost" onClick={() => { state.chooseDay(day.day); state.setPresentation('day'); }} data-today={day.day === today}><span>{weekday(day.day)}</span><strong>{Number(day.day.slice(-2))}</strong></Button>)}</div>
      <div className="agenda-grid-scroll" id="agenda-grid-scroll"><div className="agenda-time-grid" style={{ height: `${(endHour - startHour) * 60}px` }}><div className="agenda-hour-rail">{Array.from({ length: endHour - startHour }, (_, index) => <span key={index} style={{ top: index * 60 }}>{String((startHour + index) % 24).padStart(2, '0')}:00</span>)}</div>
        {state.days.map(day => <div className="agenda-day-column" key={day.day} aria-label={formatDayHeading(day.day)} data-today={day.day === today}>{calendarLanes(day.items, school.timeZone).map(item => <div key={item.event.key} className="agenda-positioned-event agenda-positioned" style={{ top: item.start - startHour * 60, height: item.end - item.start - 4, left: `calc(${item.lane / item.lanes * 100}% + 3px)`, width: `calc(${100 / item.lanes}% - 6px)` } as CSSProperties}><EventEntry event={item.event} state={state} /></div>)}</div>)}
      </div></div>{events.length === 0 && state.emptyConfirmed && <p className="agenda-week-empty">{state.searching ? 'Aucune leçon pour cet élève cette semaine.' : 'Aucun rendez-vous cette semaine.'}</p>}
    </div>}
    <footer className="agenda-read-time">{state.freshness.complete && state.freshness.readAt ? `Actualisé à ${new Intl.DateTimeFormat('fr-CH', { timeZone: school.timeZone, timeStyle: 'short' }).format(state.freshness.readAt)}` : 'La lecture complète de l’agenda n’est pas confirmée.'}<span>{school.timeZone}</span></footer>
  </section>;
}

function EventEntry({ event, state }: { event: AgendaEvent; state: AgendaState }) {
  const isLesson = event.kind === 'lesson';
  const phase = isLesson ? lessonPhase(event.lesson, state.now) : null;
  const title = isLesson ? state.learnerName(event.lesson.learnerId) : event.series.title;
  const end = isLesson ? event.lesson.plannedEnd : event.occurrence.endsAt;
  const instructor = isLesson ? state.memberName(event.lesson.instructorMembershipId) : event.occurrence.instructorDisplayName;
  const place = isLesson ? event.lesson.meetingPoint : event.series.location;
  const id = isLesson ? `portal-lesson-${event.lesson.id}` : `portal-course-${event.series.id}-${event.occurrence.id}`;
  // One state label per appointment: a lesson's phase, or a course that is not simply published. The phase is also read aloud.
  const stateLabel = isLesson ? phase && phase !== 'planned' ? phaseLabels[phase] : null
    : event.series.status === 'CANCELLED' ? 'Annulé' : event.series.status === 'DRAFT' ? 'Brouillon' : event.series.status === 'CLOSED' ? 'Clos' : null;
  const warning = isLesson && event.lesson.permitWarning === true;
  return <button type="button" id={id} className="agenda-event" data-kind={event.kind} data-phase={phase} data-has-state={stateLabel ? true : undefined} onClick={() => isLesson ? state.openLesson(event.lesson.id) : state.openCourse(event.series.id, event.occurrence.id)} aria-label={[title, formatTimeRange(event.startsAt, end, state.context.school.timeZone), instructor, stateLabel, warning ? 'Permis à vérifier' : null].filter(Boolean).join(', ')}>
    <span className="agenda-event-clock"><Clock3 aria-hidden="true" />{formatTimeRange(event.startsAt, end, state.context.school.timeZone)}</span><strong>{title}</strong><span className="agenda-event-instructor">{!isLesson && <Users aria-hidden="true" />}{instructor}</span>{place && <span className="agenda-event-place"><MapPin aria-hidden="true" />{place}</span>}
    {stateLabel && <span className="agenda-event-state">{stateLabel}</span>}{warning && <span className="agenda-event-warning"><TriangleAlert aria-hidden="true" /><span>Permis à vérifier</span></span>}
  </button>;
}

function CourseContext({ courseId, occurrenceId, onClose }: { courseId: string; occurrenceId?: string | undefined; onClose: () => void }) {
  const { schoolId } = useConsole();
  const heading = useRef<HTMLHeadingElement>(null);
  const loaded = useLoad(async () => { const series = await readSchool(schoolId, `course-series/${courseId}`, courseSeriesSchema); if (series.id !== courseId || series.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE'); return series; }, [schoolId, courseId]);
  const series = loaded.data;
  useEffect(() => { if (series) heading.current?.focus(); }, [series?.id]);
  return <section className="agenda-page"><Button variant="ghost" className="agenda-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button><ReadFeedback loaded={loaded} label="Lecture du cours" />
    {series && <><header className="agenda-heading"><div><span className="agenda-eyebrow">{series.typeTitle}</span><h1 ref={heading} tabIndex={-1}>{series.title}</h1></div>{series.status !== 'PUBLISHED' && <Badge variant="secondary">{series.status === 'DRAFT' ? 'Brouillon' : series.status === 'CANCELLED' ? 'Annulé' : 'Clos'}</Badge>}</header><div className="agenda-detail-layout"><div className="agenda-detail-main"><section><h2>Séances</h2><ol className="agenda-occurrences">{series.occurrences.map(occurrence => <li key={occurrence.id} data-selected={occurrence.id === occurrenceId}><span className="agenda-occurrence-index">{occurrence.position}</span><div><strong>{dateTime(occurrence.startsAt, occurrence.timeZone)}</strong><p>{formatTimeRange(occurrence.startsAt, occurrence.endsAt, occurrence.timeZone)} · {occurrence.instructorDisplayName}</p>{occurrence.attendanceRequired && <span className="agenda-muted">Présence requise</span>}</div></li>)}</ol></section>{series.description && <section><h2>À propos du cours</h2><p className="agenda-prose">{series.description}</p></section>}{series.conditions && <section><h2>Conditions</h2><p className="agenda-prose">{series.conditions}</p></section>}</div><aside className="agenda-context"><Users aria-hidden="true" /><h2>{series.seatsTaken} / {series.capacity} inscrits</h2><dl className="agenda-facts"><div><dt>Responsable</dt><dd>{series.responsibleDisplayName}</dd></div><div><dt>Lieu</dt><dd>{series.location || 'Non précisé'}</dd></div><div><dt>Annulation autonome jusqu’au</dt><dd>{dateTime(series.selfCancellationDeadline, series.occurrences[0]?.timeZone ?? 'Europe/Zurich')}</dd></div></dl></aside></div></>}
  </section>;
}
