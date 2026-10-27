import { useEffect, useMemo, useRef, useState } from 'react';
import { civilDateIn, addDays, formatDayHeading, formatTimeRange, formatWeek, lessonPhase, lessonsOfLearners, weekStart, weekWindow } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { isCivilDate } from '../command-core';
import { activeInstructors } from '../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll } from '../school-api';
import { EmptyState, Loading, Notice, SelectField, StatusBadge, Symbol, TextField, type Tone } from '../ui';
import { useConsole, useLoad, type Loaded } from './context';
import { agendaSearchQuery } from '../console-filter-model';
import { ReadRetry, RecordSearch, SectionHeading } from './layout';
import { FirstLessonActions } from './overview';
import { PlanningReadinessBanner } from './planning-readiness';
import { useListState } from './list-state';
import { distinctLabel, homonymReferences } from '../person-reference';
import { AgendaAddMenu, CoursePolicyDialog, CourseWorkspace, readCourseCatalogue } from './courses';
import { LessonWorkspace } from './lesson-planning';
import { courseSeriesListSchema } from './course-model';
import { agendaCountLabel, agendaCounts, agendaDays, agendaReadStatus } from './agenda-projection';
import { readSchool } from '../school-api';
import './agenda-studio.css';

const agendaRefreshMs = 60_000;
const formatClock = (instant: number, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(instant));

function AgendaSourceState({ loaded, name }: { loaded: Loaded<unknown>; name: string }) {
  return <>
    {loaded.status === 'loading' && <Loading label={`${name} : lecture en cours…`} />}
    {loaded.status === 'error' && <Notice tone="error" title={`${name} non actualis${name === 'Leçons' ? 'ées' : 'és'}`} actions={<ReadRetry loaded={loaded} />}>
      <p>{loaded.error}{loaded.data !== undefined ? ' Les informations conservées peuvent être anciennes.' : ''}</p>
    </Notice>}
  </>;
}

const lessonState: Partial<Record<ReturnType<typeof lessonPhase>, { label: string; tone: Tone; symbol: 'check' | 'ban' | 'alert' | 'clock' }>> = {
  cancelled: { label: 'Annulée', tone: 'neutral', symbol: 'ban' },
  absent: { label: 'Absent', tone: 'warning', symbol: 'alert' },
  waiting: { label: 'En attente', tone: 'warning', symbol: 'clock' },
  started: { label: 'En cours', tone: 'accent', symbol: 'clock' },
  'to-finish': { label: 'À terminer', tone: 'warning', symbol: 'clock' },
};

/** Agenda de l'école : leçons et cours partagent les règles d'occupation du serveur. */
export function AgendaSection() {
  const { schoolId, school, navigate, routeQuery, setRouteQuery, confirmNavigation } = useConsole();
  const { revision } = useCommandSnapshot();
  const [now, setNow] = useState(Date.now);
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 30_000); return () => window.clearInterval(timer); }, []);
  const [localMonday, setLocalMonday] = useState(() => weekStart(civilDateIn(school.timeZone)));
  const [localInstructor, setLocalInstructor] = useState('');
  const [search, setSearch] = useListState('agenda/search', '');
  const monday = routeQuery ? weekStart(routeQuery.week ?? civilDateIn(school.timeZone)) : localMonday;
  const [jumpDate, setJumpDate] = useState(monday);
  useEffect(() => setJumpDate(monday), [monday]);
  const instructor = routeQuery ? routeQuery.instructor ?? '' : localInstructor;
  const setMonday = (week: string) => { setLocalMonday(week); setRouteQuery?.({ ...routeQuery, week }); };
  const setInstructor = (id: string) => { setLocalInstructor(id); setRouteQuery?.({ ...routeQuery, instructor: id || undefined }); };
  const bounds = weekWindow(monday, school.timeZone);
  const directory = useLoad(async () => {
    const [members, learners] = await Promise.all([readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'learners', learnerSchema, { status: 'ALL' })]);
    return { members: members.items, learners: learners.items, truncated: members.truncated || learners.truncated };
  }, [schoolId, revision]);
  const loaded = useLoad(async () => {
    if (!bounds) throw new Error('Semaine invalide.');
    const lessons = await readAll(schoolId, 'lessons', lessonSchema, { from: bounds.from, to: bounds.to, ...(instructor ? { instructorMembershipId: instructor } : {}) });
    return { lessons: lessons.items, truncated: lessons.truncated };
  }, [schoolId, revision, bounds?.from, bounds?.to, instructor], `${schoolId}/${monday}/${instructor}`);
  const data = loaded.data;
  // Cours collectifs : catalogue (droit de gestion) et séries de la semaine. Une erreur ici ne bloque pas l'agenda des leçons.
  const catalogue = useLoad(() => readCourseCatalogue(schoolId), [schoolId, revision]);
  const courses = useLoad(async () => {
    if (!bounds) throw new Error('Semaine invalide.');
    return (await readSchool(schoolId, 'course-series', courseSeriesListSchema, { from: bounds.from, to: bounds.to })).items;
  }, [schoolId, revision, bounds?.from, bounds?.to], `${schoolId}/${monday}`);
  // useLoad deduplicates each source while in flight; all reads keep the visible selection and scroll.
  const refreshLessons = loaded.refresh, refreshDirectory = directory.refresh, refreshCourses = courses.refresh;
  const lastRefresh = useRef(Date.now());
  const refreshNow = () => {
    lastRefresh.current = Date.now(); refreshLessons?.(); refreshDirectory?.(); refreshCourses?.();
  };
  useEffect(() => {
    lastRefresh.current = Date.now();
    const refreshIfStale = () => {
      if (document.visibilityState !== 'visible' || Date.now() - lastRefresh.current < agendaRefreshMs) return;
      lastRefresh.current = Date.now(); refreshLessons?.(); refreshDirectory?.(); refreshCourses?.();
    };
    const timer = window.setInterval(refreshIfStale, 15_000);
    document.addEventListener('visibilitychange', refreshIfStale);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', refreshIfStale); };
  }, [refreshLessons, refreshDirectory, refreshCourses]);
  const [course, setCourse] = useState<{ id: string | null; occurrenceId?: string } | null>(null);
  const [lesson, setLesson] = useState<{ id: string | null } | null>(() => routeQuery?.view === 'nouvelle' ? { id: null } : null);
  useEffect(() => { if (routeQuery?.view === 'nouvelle') setLesson({ id: null }); }, [routeQuery?.view, routeQuery?.learner]);
  const changeWorkspace = (action: () => void) => confirmNavigation ? confirmNavigation(action) : action();
  const openLesson = (id: string | null) => changeWorkspace(() => { setCourse(null); setLesson({ id }); if (id) setRouteQuery?.({ ...routeQuery, lesson: id, view: undefined }, true, true); });
  const openCourse = (selection: { id: string | null; occurrenceId?: string }) => changeWorkspace(() => { setLesson(null); setCourse(selection); });
  const [coursePolicy, setCoursePolicy] = useState(false);
  const reloadCourses = courses.refresh ?? courses.reload;
  const instructors = useMemo(() => activeInstructors(directory.data?.members ?? []), [directory.data]);
  const instructorReferences = useMemo(() => homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName }))), [instructors]);
  const searchQuery = agendaSearchQuery(directory, search).trim();
  const searchingLearner = Boolean(search.trim());
  const days = useMemo(() => bounds ? agendaDays(lessonsOfLearners(data?.lessons ?? [], directory.data?.learners ?? [], searchQuery), courses.data ?? [], {
    ...bounds, timeZone: school.timeZone, instructor, includeCourses: !searchingLearner,
  }) : [], [data, directory.data, courses.data, searchQuery, searchingLearner, instructor, bounds?.from, bounds?.to, school.timeZone]);
  const counts = agendaCounts(days.flatMap(day => day.items));
  // The current API caps course-series at 200 without a cursor: reaching the cap cannot prove completeness.
  const courseLimitReached = (courses.data?.length ?? 0) >= 200;
  const partial = data?.truncated === true || directory.data?.truncated === true || courseLimitReached;
  const freshness = agendaReadStatus([loaded, directory, courses], partial);
  const visibleSourcesReady = loaded.status === 'ready' && (!searchingLearner || directory.status === 'ready')
    && (searchingLearner || courses.status === 'ready');
  const emptyIsConfirmed = visibleSourcesReady && !partial;
  const initialLoading = [loaded, directory, courses].some(source => source.status === 'loading');
  const learnerName = (id: string) => directory.data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => directory.data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
  const thisWeek = weekStart(civilDateIn(school.timeZone));
  const weekLabel = useRef<HTMLSpanElement>(null);
  const restoredFocus = useRef<string | null>(null);
  const selectedLessonVisible = days.some(day => day.items.some(event => event.kind === 'lesson' && event.lesson.id === routeQuery?.lesson));
  useEffect(() => {
    const key = routeQuery?.lesson ? `${monday}/${instructor}/${routeQuery.lesson}` : null;
    if (!key) { restoredFocus.current = null; return; }
    if (loaded.status !== 'ready' || restoredFocus.current === key) return;
    const target = document.getElementById(`agenda-lesson-${routeQuery?.lesson}`) ?? weekLabel.current;
    target?.focus(); restoredFocus.current = key;
  }, [routeQuery?.lesson, monday, instructor, loaded.status, selectedLessonVisible]);

  return (
    <div className="section-stack agenda-studio">
      <SectionHeading context="Planning" title="Agenda" actions={<div className="agenda-freshness">
        <AgendaAddMenu canCreateCourse={catalogue.data?.canManage === true} onLesson={() => openLesson(null)} onCourse={() => openCourse({ id: null })} />
        {catalogue.data?.canManage === true && <button type="button" className="button quiet" onClick={() => setCoursePolicy(true)}>Réglages des cours</button>}
        {freshness.readAt !== undefined && <span className="caption">{freshness.complete ? 'À jour à ' : 'Lecture partielle à '}<time dateTime={new Date(freshness.readAt).toISOString()}>{formatClock(freshness.readAt, school.timeZone)}</time></span>}
        <button type="button" className="button quiet" onClick={refreshNow} disabled={initialLoading} aria-busy={initialLoading}>
          <Symbol kind="refresh" bare />Actualiser</button>
      </div>} />
      {lesson && <LessonWorkspace key={lesson.id ?? `new/${routeQuery?.learner ?? ''}`} lessonId={lesson.id} learnerId={routeQuery?.learner}
        onClose={() => { setLesson(null); if (routeQuery?.view === 'nouvelle') setRouteQuery?.({ ...routeQuery, view: undefined }, true, true); window.requestAnimationFrame(() => document.getElementById(`agenda-lesson-${lesson.id}`)?.focus()); }}
        onSaved={refreshNow} onDossier={(learnerId, lessonId) => navigate('eleves', { selection: learnerId, lesson: lessonId, from: 'agenda', week: monday, instructor: instructor || undefined })} />}
      {catalogue.data?.canManage === true && <CoursePolicyDialog open={coursePolicy} catalogue={catalogue.data} onClose={() => setCoursePolicy(false)} onSaved={catalogue.reload} />}
      {course && catalogue.data && <CourseWorkspace key={`${course.id ?? 'new'}/${course.occurrenceId ?? ''}`} seriesId={course.id} selectedOccurrenceId={course.occurrenceId} catalogue={catalogue.data}
        onClose={() => { setCourse(null); window.requestAnimationFrame(() => document.getElementById(`agenda-course-${course.id}-${course.occurrenceId}`)?.focus()); }}
        onSaved={saved => { reloadCourses(); setCourse(saved ? { id: saved.id, ...(course.id === saved.id && course.occurrenceId ? { occurrenceId: course.occurrenceId } : {}) } : null); }} />}
      <PlanningReadinessBanner />
      <FirstLessonActions />
      <div className="agenda-studio-toolbar">
        <div className="agenda-period" role="group" aria-label="Semaine affichée">
          <span className="agenda-period-label" aria-live="polite" ref={weekLabel} tabIndex={-1}>{formatWeek(monday)}</span>
          <div className="agenda-period-controls">
            <button type="button" className="button secondary" aria-label="Semaine précédente" onClick={() => setMonday(addDays(monday, -7))}><Symbol kind="back" bare /></button>
            <button type="button" className="button secondary" aria-label="Semaine suivante" onClick={() => setMonday(addDays(monday, 7))}><span className="flip"><Symbol kind="back" bare /></span></button>
          </div>
          {monday !== thisWeek && <button type="button" className="button quiet" onClick={() => { setMonday(thisWeek); window.requestAnimationFrame(() => weekLabel.current?.focus()); }}>Aujourd’hui</button>}
        </div>
        <form className="agenda-date-jump" onSubmit={event => {
          event.preventDefault();
          if (!isCivilDate(jumpDate)) return;
          setMonday(weekStart(jumpDate));
          window.requestAnimationFrame(() => weekLabel.current?.focus());
        }}>
          <TextField label="Aller à une date" type="date" required value={jumpDate} onChange={setJumpDate} />
          <button type="submit" className="button secondary">Afficher la semaine</button>
        </form>
        <div className="agenda-studio-filters">
          {(instructors.length > 1 || instructor) && <SelectField label="Moniteur" value={instructor} onChange={setInstructor} search appearance="filter"
            options={[{ value: '', label: 'Tous les moniteurs' }, ...instructors.map(item => ({ value: item.id, label: distinctLabel(item.displayName, instructorReferences.get(item.id)) })),
              ...(instructor && !instructors.some(item => item.id === instructor) ? [{ value: instructor, label: memberName(instructor) }] : [])]} />}
          <RecordSearch label="Rechercher un élève parmi les leçons" value={search} onChange={setSearch} placeholder="Élève · leçons" />
          {search && <button type="button" className="button quiet" onClick={() => setSearch('')}>Effacer la recherche</button>}
        </div>
      </div>
      <AgendaSourceState loaded={directory} name="Élèves et moniteurs" />
      <AgendaSourceState loaded={loaded} name="Leçons" />
      <AgendaSourceState loaded={courses} name="Cours" />
        {routeQuery?.lesson && loaded.status === 'ready' && !selectedLessonVisible && <Notice tone="warning" title="Leçon absente de cette vue" live={false}><p>Ce rendez-vous n’apparaît plus dans cette semaine ou avec ces filtres.</p></Notice>}
        {data?.truncated && <Notice tone="warning" title="Leçons partiellement chargées" live={false}><p>Trop de leçons pour cette semaine : choisissez un moniteur.</p></Notice>}
        {directory.data?.truncated && <Notice tone="warning" title="Répertoire partiellement chargé" live={false}><p>Les noms, filtres et résultats de recherche peuvent être incomplets.</p></Notice>}
        {courseLimitReached && <Notice tone="warning" title="Cours potentiellement incomplets" live={false}><p>Certains cours de cette semaine peuvent manquer.</p></Notice>}
        <p className="list-summary" role="status">{search.trim() && !directory.data
          ? 'Recherche suspendue : le répertoire des élèves est en cours de lecture ou indisponible.'
          : `${agendaCountLabel(counts, searchingLearner)}${!emptyIsConfirmed ? ' · lecture partielle' : searchingLearner ? ' · recherche parmi les leçons' : ' cette semaine'}`}</p>
        {days.length === 0 ? emptyIsConfirmed && <EmptyState symbol="clock" title={searchingLearner ? 'Aucune leçon trouvée' : 'Aucun rendez-vous cette semaine'} message="" />
          : <div className="agenda-week-list">{days.map(day => {
            const [weekday, ...date] = formatDayHeading(day.day).split(' ');
            return <section key={day.day} className="agenda-day" aria-labelledby={`day-${day.day}`}>
            <div className="agenda-day-heading">
              <h2 id={`day-${day.day}`} className="section-title agenda-day-date"><span className="agenda-day-name">{weekday}</span>{' '}<time className="agenda-day-number" dateTime={day.day}>{date.join(' ')}</time></h2>
              <span className="agenda-day-count">{agendaCountLabel(agendaCounts(day.items), searchingLearner)}{!emptyIsConfirmed && ' · partiel'}</span>
            </div>
            <ul className="row-list" aria-label={`Rendez-vous du ${formatDayHeading(day.day)}`}>{day.items.map(event => {
              if (event.kind === 'course') {
                const { series, occurrence } = event;
                const [start, end] = formatTimeRange(occurrence.startsAt, occurrence.endsAt, school.timeZone).split('–');
                return <li key={event.key} className={series.status === 'CANCELLED' ? 'muted-row' : undefined}>
                  <button id={`agenda-course-${series.id}-${occurrence.id}`} type="button" className="agenda-lesson" onClick={() => openCourse({ id: series.id, occurrenceId: occurrence.id })}>
                    <span className="agenda-time"><time dateTime={occurrence.startsAt}>{start}</time><span className="visually-hidden"> à </span><time dateTime={occurrence.endsAt}>{end}</time></span>
                    <span className="agenda-identity">
                      <span className="agenda-identity-top"><span className="row-title">{series.title}</span>
                        {series.status === 'DRAFT' && <StatusBadge tone="neutral" symbol="edit">Brouillon</StatusBadge>}
                        {series.status === 'CANCELLED' && <StatusBadge tone="neutral" symbol="ban">Annulé</StatusBadge>}
                      </span>
                      <span className="row-meta agenda-lesson-meta"><span>Cours collectif</span><span>{occurrence.instructorDisplayName}</span><span>{series.seatsTaken} / {series.capacity}</span>{series.location && <span>{series.location}</span>}</span>
                    </span>
                    <span className="agenda-open-indicator flip"><Symbol kind="back" bare /></span>
                    <span className="visually-hidden">Ouvrir le cours</span>
                  </button>
                </li>;
              }
              const { lesson } = event;
              const phase = lessonPhase(lesson, now);
              const state = lessonState[phase];
              const [start, end] = formatTimeRange(lesson.plannedStart, lesson.plannedEnd, school.timeZone).split('–');
              return <li key={event.key} className={lesson.status === 'CANCELLED' ? 'muted-row' : undefined}>
                <button id={`agenda-lesson-${lesson.id}`} type="button" className="agenda-lesson" aria-current={routeQuery?.lesson === lesson.id ? 'true' : undefined} onClick={() => {
                    openLesson(lesson.id);
                  }}>
                  <span className="agenda-time"><time dateTime={lesson.plannedStart}>{start}</time><span className="visually-hidden"> à </span><time dateTime={lesson.plannedEnd}>{end}</time></span>
                  <span className="agenda-identity">
                    <span className="agenda-identity-top"><span className="row-title">{learnerName(lesson.learnerId)}</span>
                      {state && <StatusBadge tone={state.tone} symbol={state.symbol}>{state.label}</StatusBadge>}
                      {lesson.status === 'PLANNED' && lesson.permitWarning === true && <StatusBadge tone="warning" symbol="alert">Permis à vérifier</StatusBadge>}
                      {phase === 'completed' && <span className="row-meta">Terminée</span>}
                    </span>
                    <span className="row-meta agenda-lesson-meta"><span>{memberName(lesson.instructorMembershipId)}</span>{lesson.meetingPoint && <span>{lesson.meetingPoint}</span>}</span>
                  </span>
                  <span className="agenda-open-indicator flip"><Symbol kind="back" bare /></span>
                  <span className="visually-hidden">Ouvrir la leçon</span>
                </button>
              </li>;
            })}</ul>
          </section>; })}</div>}
    </div>
  );
}
