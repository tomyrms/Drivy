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
import './agenda-studio.css';

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
  // The agenda is left open all day: coming back to the tab re-reads a week that is more than a minute old.
  const lastRead = useRef(Date.now());
  useEffect(() => { if (loaded.status === 'ready') lastRead.current = Date.now(); }, [loaded.status, loaded.data]);
  const reloadLessons = loaded.reload, reloadDirectory = directory.reload;
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState !== 'visible' || Date.now() - lastRead.current < 60_000) return;
      lastRead.current = Date.now(); reloadLessons(); reloadDirectory();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [reloadLessons, reloadDirectory]);
  const data = loaded.data;
  const instructors = useMemo(() => activeInstructors(directory.data?.members ?? []), [directory.data]);
  const searchQuery = agendaSearchQuery(directory, search);
  const days = useMemo(() => groupByDay(lessonsOfLearners(data?.lessons ?? [], directory.data?.learners ?? [], searchQuery), school.timeZone),
    [data, directory.data, searchQuery, school.timeZone]);
  const lessonCount = days.reduce((total, day) => total + day.items.length, 0);
  const learnerName = (id: string) => directory.data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => directory.data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
  const thisWeek = weekStart(civilDateIn(school.timeZone));
  const weekLabel = useRef<HTMLSpanElement>(null);

  return (
    <div className="section-stack agenda-studio">
      <SectionHeading context="Planning" title="Agenda" />
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
            options={[{ value: '', label: 'Tous les moniteurs' }, ...instructors.map(item => ({ value: item.id, label: item.displayName })),
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
            <ul className="row-list">{day.items.map(lesson => {
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
            })}</ul>
          </section>; })}</div>}
      </>}</LoadState>
    </div>
  );
}
