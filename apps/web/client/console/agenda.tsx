import { useEffect, useMemo, useRef, useState } from 'react';
import { civilDateIn, addDays, formatDayHeading, formatTimeRange, formatWeek, groupByDay, lessonPhase, weekStart, weekWindow } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { activeInstructors } from '../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll } from '../school-api';
import { EmptyState, Notice, SelectField, StatusBadge, Symbol, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';

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
  const monday = routeQuery ? weekStart(routeQuery.week ?? civilDateIn(school.timeZone)) : localMonday;
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
  const data = loaded.data;
  const instructors = useMemo(() => activeInstructors(directory.data?.members ?? []), [directory.data]);
  const days = useMemo(() => groupByDay(data?.lessons ?? [], school.timeZone), [data, school.timeZone]);
  const learnerName = (id: string) => directory.data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => directory.data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
  const thisWeek = weekStart(civilDateIn(school.timeZone));
  const weekLabel = useRef<HTMLSpanElement>(null);

  return (
    <div className="section-stack">
      <SectionHeading context="Planning" title="Agenda" />
      <div className="agenda-toolbar">
        <div className="week-nav" role="group" aria-label="Semaine affichée">
          <button type="button" className="button secondary" aria-label="Semaine précédente" onClick={() => setMonday(addDays(monday, -7))}><Symbol kind="back" bare /></button>
          <span className="week-label" aria-live="polite" ref={weekLabel} tabIndex={-1}>{formatWeek(monday)}</span>
          <button type="button" className="button secondary" aria-label="Semaine suivante" onClick={() => setMonday(addDays(monday, 7))}><span className="flip"><Symbol kind="back" bare /></span></button>
          {monday !== thisWeek && <button type="button" className="button quiet" onClick={() => { setMonday(thisWeek); window.requestAnimationFrame(() => weekLabel.current?.focus()); }}>Aujourd’hui</button>}
        </div>
        {(instructors.length > 1 || instructor) && <SelectField label="Moniteur" value={instructor} onChange={setInstructor}
          options={[{ value: '', label: 'Tous les moniteurs' }, ...instructors.map(item => ({ value: item.id, label: item.displayName })),
            ...(instructor && !instructors.some(item => item.id === instructor) ? [{ value: instructor, label: memberName(instructor) }] : [])]} />}
      </div>
      <LoadState loaded={directory} label="Lecture des élèves et moniteurs…">{() => null}</LoadState>
      <LoadState loaded={loaded} label="Lecture de l’agenda…">{value => <>
        {value.truncated && <Notice tone="warning" title="Semaine partielle" live={false}><p>Trop de leçons pour cette semaine : choisissez un moniteur.</p></Notice>}
        {days.length === 0 ? <EmptyState symbol="clock" title="Aucune leçon cette semaine" message="" />
          : days.map(day => {
            const [weekday, ...date] = formatDayHeading(day.day).split(' ');
            return <section key={day.day} className="agenda-day" aria-labelledby={`day-${day.day}`}>
            <h2 id={`day-${day.day}`} className="section-title agenda-day-date"><span className="agenda-day-name">{weekday}</span>{' '}<time className="agenda-day-number" dateTime={day.day}>{date.join(' ')}</time></h2>
            <ul className="row-list">{day.items.map(lesson => {
              const phase = lessonPhase(lesson, now);
              const state = lessonState[phase];
              const [start, end] = formatTimeRange(lesson.plannedStart, lesson.plannedEnd, school.timeZone).split('–');
              return <li key={lesson.id} className={lesson.status === 'CANCELLED' ? 'muted-row' : undefined}>
                <button type="button" className="agenda-lesson" onClick={() => navigate('eleves', {
                    selection: lesson.learnerId, from: 'agenda', week: monday, instructor: instructor || undefined,
                  })}>
                  <span className="agenda-time"><time dateTime={lesson.plannedStart}>{start}</time><span className="visually-hidden"> à </span><time dateTime={lesson.plannedEnd}>{end}</time></span>
                  <span className="agenda-identity"><span className="row-title">{learnerName(lesson.learnerId)}</span>
                    <span className="row-meta">{memberName(lesson.instructorMembershipId)}{lesson.meetingPoint ? ` · ${lesson.meetingPoint}` : ''}</span>
                    {phase === 'completed' && <span className="row-meta">Terminée</span>}
                  </span>
                  {(state || (lesson.status === 'PLANNED' && lesson.permitWarning === true)) && <span className="agenda-status">
                    {state && <StatusBadge tone={state.tone} symbol={state.symbol}>{state.label}</StatusBadge>}
                    {lesson.status === 'PLANNED' && lesson.permitWarning === true && <StatusBadge tone="warning" symbol="alert">Permis à vérifier</StatusBadge>}
                  </span>}
                  <span className="visually-hidden">Ouvrir le dossier</span>
                </button>
              </li>;
            })}</ul>
          </section>; })}
      </>}</LoadState>
    </div>
  );
}
