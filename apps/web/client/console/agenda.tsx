import { useMemo, useRef, useState } from 'react';
import { civilDateIn, addDays, formatDayHeading, formatTimeRange, formatWeek, groupByDay, weekStart, weekWindow } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { activeInstructors } from '../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll, type Lesson } from '../school-api';
import { EmptyState, Notice, SelectField, StatusBadge, Symbol, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';

const lessonState: Partial<Record<Lesson['status'], { label: string; tone: Tone; symbol: 'check' | 'ban' | 'alert' }>> = {
  CANCELLED: { label: 'Annulée', tone: 'neutral', symbol: 'ban' },
  NO_SHOW: { label: 'Absent', tone: 'warning', symbol: 'alert' },
};

/** Agenda de l'école en lecture seule : la planification des leçons se fait dans l'app. */
export function AgendaSection() {
  const { schoolId, school, navigate, routeQuery, setRouteQuery } = useConsole();
  const { revision } = useCommandSnapshot();
  const [localMonday, setLocalMonday] = useState(() => weekStart(civilDateIn(school.timeZone)));
  const [localInstructor, setLocalInstructor] = useState('');
  const monday = routeQuery ? weekStart(routeQuery.week ?? civilDateIn(school.timeZone)) : localMonday;
  const instructor = routeQuery ? routeQuery.instructor ?? '' : localInstructor;
  const setMonday = (week: string) => { setLocalMonday(week); setRouteQuery?.({ ...routeQuery, week }); };
  const setInstructor = (id: string) => { setLocalInstructor(id); setRouteQuery?.({ ...routeQuery, instructor: id || undefined }); };
  const bounds = weekWindow(monday, school.timeZone);
  const loaded = useLoad(async () => {
    if (!bounds) throw new Error('Semaine invalide.');
    const [members, learners, lessons] = await Promise.all([
      readAll(schoolId, 'members', memberSchema), readAll(schoolId, 'learners', learnerSchema),
      readAll(schoolId, 'lessons', lessonSchema, { from: bounds.from, to: bounds.to, ...(instructor ? { instructorMembershipId: instructor } : {}) })]);
    return { members: members.items, learners: learners.items, lessons: lessons.items, truncated: lessons.truncated };
  }, [schoolId, revision, bounds?.from, bounds?.to, instructor]);
  const data = loaded.data;
  const instructors = useMemo(() => activeInstructors(data?.members ?? []), [data]);
  const days = useMemo(() => groupByDay(data?.lessons ?? [], school.timeZone), [data, school.timeZone]);
  const learnerName = (id: string) => data?.learners.find(item => item.id === id)?.displayName ?? 'Élève';
  const memberName = (id: string) => data?.members.find(item => item.id === id)?.displayName ?? 'Moniteur';
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
        {instructors.length > 1 && <SelectField label="Moniteur" value={instructor} onChange={setInstructor}
          options={[{ value: '', label: 'Tous les moniteurs' }, ...instructors.map(item => ({ value: item.id, label: item.displayName }))]} />}
      </div>
      <LoadState loaded={loaded} label="Lecture de l’agenda…">{value => <>
        {value.truncated && <Notice tone="warning" title="Semaine partielle" live={false}><p>Trop de leçons pour cette semaine : choisissez un moniteur.</p></Notice>}
        {days.length === 0 ? <EmptyState symbol="clock" title="Aucune leçon cette semaine" message="" />
          : days.map(day => {
            const [weekday, ...date] = formatDayHeading(day.day).split(' ');
            return <section key={day.day} className="agenda-day" aria-labelledby={`day-${day.day}`}>
            <h2 id={`day-${day.day}`} className="section-title agenda-day-date"><span className="agenda-day-name">{weekday}</span>{' '}<time className="agenda-day-number" dateTime={day.day}>{date.join(' ')}</time></h2>
            <ul className="row-list">{day.items.map(lesson => {
              const state = lessonState[lesson.status];
              const [start, end] = formatTimeRange(lesson.plannedStart, lesson.plannedEnd, school.timeZone).split('–');
              return <li key={lesson.id} className={lesson.status === 'CANCELLED' ? 'muted-row' : undefined}>
                <button type="button" className="agenda-lesson" onClick={() => navigate('eleves', {
                    selection: lesson.learnerId, from: 'agenda', week: monday, instructor: instructor || undefined,
                  })}>
                  <span className="agenda-time"><time dateTime={lesson.plannedStart}>{start}</time><span className="visually-hidden"> à </span><time dateTime={lesson.plannedEnd}>{end}</time></span>
                  <span className="agenda-identity"><span className="row-title">{learnerName(lesson.learnerId)}</span>
                    <span className="row-meta">{memberName(lesson.instructorMembershipId)}{lesson.meetingPoint ? ` · ${lesson.meetingPoint}` : ''}</span>
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
