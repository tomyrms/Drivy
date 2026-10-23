import { useEffect, useMemo, useRef, useState } from 'react';
import { civilDateIn, addDays, formatDayHeading, formatTimeRange, formatWeek, groupByDay, lessonPhase, lessonsOfLearners, weekStart, weekWindow } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { isCivilDate } from '../command-core';
import { activeInstructors } from '../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll } from '../school-api';
import { EmptyState, Notice, SelectField, StatusBadge, Symbol, TextField, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { agendaSearchQuery } from '../console-filter-model';
import { LoadState, RecordSearch, SectionHeading } from './layout';
import { FirstLessonActions } from './overview';
import { PlanningReadinessBanner } from './planning-readiness';
import { useListState } from './list-state';
import { distinctLabel, homonymReferences } from '../person-reference';
import { AgendaAddMenu, CoursePolicyDialog, CourseWorkspace, LessonInAppDialog, readCourseCatalogue } from './courses';
import { courseSeriesListSchema, seriesByDay } from './course-model';
import { readSchool } from '../school-api';
import './agenda-studio.css';

const agendaRefreshMs = 60_000;
const formatClock = (instant: number, timeZone: string) => new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone }).format(new Date(instant));

const lessonState: Partial<Record<ReturnType<typeof lessonPhase>, { label: string; tone: Tone; symbol: 'check' | 'ban' | 'alert' | 'clock' }>> = {
  cancelled: { label: 'Annulée', tone: 'neutral', symbol: 'ban' },
  absent: { label: 'Absent', tone: 'warning', symbol: 'alert' },
  waiting: { label: 'En attente', tone: 'warning', symbol: 'clock' },
  started: { label: 'En cours', tone: 'accent', symbol: 'clock' },
  'to-finish': { label: 'À terminer', tone: 'warning', symbol: 'clock' },
};

/** Agenda de l'école en lecture seule : la planification des leçons se fait dans l'app. */
export function AgendaSection() {
  const { schoolId, school, navigate, routeQuery, setRouteQuery } = useConsole();
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
    return { members: members.items, learners: learners.items };
  }, [schoolId, revision]);
  const loaded = useLoad(async () => {
    if (!bounds) throw new Error('Semaine invalide.');
    const lessons = await readAll(schoolId, 'lessons', lessonSchema, { from: bounds.from, to: bounds.to, ...(instructor ? { instructorMembershipId: instructor } : {}) });
    return { lessons: lessons.items, truncated: lessons.truncated };
  }, [schoolId, revision, bounds?.from, bounds?.to, instructor], `${schoolId}/${monday}/${instructor}`);
  // The agenda stays open all day while lessons change on the phones: re-read the week in the background
  // every minute while the tab is visible, and as soon as it becomes visible again after a minute away.
  // A background read keeps the week, filters, search and scroll on screen; a hidden tab reads nothing.
  const refreshLessons = loaded.refresh, refreshDirectory = directory.refresh;
  const readAt = loaded.readAt;
  const lastRead = useRef(readAt ?? Date.now());
  useEffect(() => { if (readAt !== undefined) lastRead.current = readAt; }, [readAt]);
  useEffect(() => {
    const refreshIfStale = () => {
      if (document.visibilityState !== 'visible' || Date.now() - lastRead.current < agendaRefreshMs) return;
      lastRead.current = Date.now(); refreshLessons?.(); refreshDirectory?.();
    };
    const timer = window.setInterval(refreshIfStale, 15_000);
    document.addEventListener('visibilitychange', refreshIfStale);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', refreshIfStale); };
  }, [refreshLessons, refreshDirectory]);
  const refreshNow = () => { lastRead.current = Date.now(); loaded.reload(); directory.refresh?.(); };
  const data = loaded.data;
  // Cours collectifs : catalogue (droit de gestion) et séries de la semaine. Une erreur ici ne bloque pas l'agenda des leçons.
  const catalogue = useLoad(() => readCourseCatalogue(schoolId), [schoolId, revision]);
  const courses = useLoad(async () => {
    if (!bounds) return [];
    return (await readSchool(schoolId, 'course-series', courseSeriesListSchema, { from: bounds.from, to: bounds.to })).items;
  }, [schoolId, revision, bounds?.from, bounds?.to], `${schoolId}/${monday}`);
  const [course, setCourse] = useState<{ id: string | null } | null>(null);
  const [lessonHelp, setLessonHelp] = useState(false);
  const [coursePolicy, setCoursePolicy] = useState(false);
  const courseDays = useMemo(() => bounds ? seriesByDay(courses.data ?? [], instant => civilDateIn(school.timeZone, Date.parse(instant)), Date.parse(bounds.from), Date.parse(bounds.to)) : new Map<string, ReturnType<typeof seriesByDay> extends Map<string, infer V> ? V : never>(),
    [courses.data, bounds?.from, bounds?.to, school.timeZone]);
  const reloadCourses = courses.reload;
  const instructors = useMemo(() => activeInstructors(directory.data?.members ?? []), [directory.data]);
  const instructorReferences = useMemo(() => homonymReferences(instructors.map(item => ({ id: item.id, label: item.displayName }))), [instructors]);
  const searchQuery = agendaSearchQuery(directory, search);
  const lessonDays = useMemo(() => groupByDay(lessonsOfLearners(data?.lessons ?? [], directory.data?.learners ?? [], searchQuery), school.timeZone),
    [data, directory.data, searchQuery, school.timeZone]);
  // Les cours s'ajoutent aux jours de leçons ; une recherche d'élève ne montre que les leçons.
  const days = useMemo(() => {
    if (searchQuery || instructor) return lessonDays;
    const all = new Set([...lessonDays.map(day => day.day), ...courseDays.keys()]);
    return [...all].sort().map(day => ({ day, items: lessonDays.find(item => item.day === day)?.items ?? [] }));
  }, [lessonDays, courseDays, searchQuery, instructor]);
  const lessonCount = days.reduce((total, day) => total + day.items.length, 0);
  const learnerName = (id: string) => directory.data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => directory.data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
  const thisWeek = weekStart(civilDateIn(school.timeZone));
  const weekLabel = useRef<HTMLSpanElement>(null);

  return (
    <div className="section-stack agenda-studio">
      <SectionHeading context="Planning" title="Agenda" actions={<div className="agenda-freshness">
        <AgendaAddMenu canCreateCourse={catalogue.data?.canManage === true} onLesson={() => setLessonHelp(true)} onCourse={() => setCourse({ id: null })} />
        {catalogue.data?.canManage === true && <button type="button" className="button quiet" onClick={() => setCoursePolicy(true)}>Réglages des cours</button>}
        {readAt !== undefined && <span className="caption">À jour à <time dateTime={new Date(readAt).toISOString()}>{formatClock(readAt, school.timeZone)}</time></span>}
        <button type="button" className="button quiet" onClick={refreshNow} disabled={loaded.status === 'loading'} aria-busy={loaded.status === 'loading'}>
          <Symbol kind="refresh" bare />Actualiser</button>
      </div>} />
      <LessonInAppDialog open={lessonHelp} onClose={() => setLessonHelp(false)} />
      {catalogue.data?.canManage === true && <CoursePolicyDialog open={coursePolicy} catalogue={catalogue.data} onClose={() => setCoursePolicy(false)} onSaved={catalogue.reload} />}
      {course && catalogue.data && <CourseWorkspace key={course.id ?? 'new'} seriesId={course.id} catalogue={catalogue.data}
        onClose={() => setCourse(null)} onSaved={saved => { reloadCourses(); setCourse(saved ? { id: saved.id } : null); }} />}
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
          <RecordSearch label="Élève" value={search} onChange={setSearch} placeholder="Rechercher un élève" />
          {search && <button type="button" className="button quiet" onClick={() => setSearch('')}>Effacer la recherche</button>}
        </div>
      </div>
      <LoadState loaded={directory} label="Lecture des élèves et moniteurs…">{() => null}</LoadState>
      <LoadState loaded={loaded} label="Lecture de l’agenda…">{value => <>
        {value.truncated && <Notice tone="warning" title="Semaine partielle" live={false}><p>Trop de leçons pour cette semaine : choisissez un moniteur.</p></Notice>}
        <p className="list-summary" role="status">{search.trim() && !directory.data
          ? 'Recherche suspendue : le répertoire des élèves est en cours de lecture ou indisponible.'
          : `${lessonCount} ${lessonCount === 1 ? 'leçon' : 'leçons'}${searchQuery ? lessonCount === 1 ? ' trouvée' : ' trouvées' : ' cette semaine'}`}</p>
        {days.length === 0 ? <EmptyState symbol="clock" title={search && value.lessons.length ? 'Aucune leçon trouvée' : 'Aucune leçon cette semaine'} message="" />
          : <div className="agenda-week-list">{days.map(day => {
            const [weekday, ...date] = formatDayHeading(day.day).split(' ');
            return <section key={day.day} className="agenda-day" aria-labelledby={`day-${day.day}`}>
            <div className="agenda-day-heading">
              <h2 id={`day-${day.day}`} className="section-title agenda-day-date"><span className="agenda-day-name">{weekday}</span>{' '}<time className="agenda-day-number" dateTime={day.day}>{date.join(' ')}</time></h2>
              <span className="agenda-day-count">{day.items.length} {day.items.length === 1 ? 'leçon' : 'leçons'}</span>
            </div>
            {!searchQuery && !instructor && (courseDays.get(day.day)?.length ?? 0) > 0 && <ul className="row-list agenda-courses" aria-label="Cours collectifs">
              {courseDays.get(day.day)!.map(({ series, occurrence }) => {
                const [start, end] = formatTimeRange(occurrence.startsAt, occurrence.endsAt, school.timeZone).split('–');
                return <li key={occurrence.id} className={series.status === 'CANCELLED' ? 'muted-row' : undefined}>
                  <button type="button" className="agenda-lesson" onClick={() => setCourse({ id: series.id })}>
                    <span className="agenda-time"><time dateTime={occurrence.startsAt}>{start}</time><span className="visually-hidden"> à </span><time dateTime={occurrence.endsAt}>{end}</time></span>
                    <span className="agenda-identity">
                      <span className="agenda-identity-top"><span className="row-title">{series.title}</span>
                        {series.status === 'DRAFT' && <StatusBadge tone="neutral" symbol="edit">Brouillon</StatusBadge>}
                        {series.status === 'CANCELLED' && <StatusBadge tone="neutral" symbol="ban">Annulé</StatusBadge>}
                      </span>
                      <span className="row-meta agenda-lesson-meta"><span>{occurrence.instructorDisplayName}</span><span>{series.seatsTaken} / {series.capacity}</span>{series.location && <span>{series.location}</span>}</span>
                    </span>
                    <span className="agenda-open-indicator flip"><Symbol kind="back" bare /></span>
                    <span className="visually-hidden">Ouvrir le cours</span>
                  </button>
                </li>;
              })}
            </ul>}
            {day.items.length > 0 && <ul className="row-list">{day.items.map(lesson => {
              const phase = lessonPhase(lesson, now);
              const state = lessonState[phase];
              const [start, end] = formatTimeRange(lesson.plannedStart, lesson.plannedEnd, school.timeZone).split('–');
              return <li key={lesson.id} className={lesson.status === 'CANCELLED' ? 'muted-row' : undefined}>
                <button type="button" className="agenda-lesson" onClick={() => navigate('eleves', {
                    selection: lesson.learnerId, from: 'agenda', week: monday, instructor: instructor || undefined,
                  })}>
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
                  <span className="visually-hidden">Ouvrir le dossier</span>
                </button>
              </li>;
            })}</ul>}
          </section>; })}</div>}
      </>}</LoadState>
    </div>
  );
}
