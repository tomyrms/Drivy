import { useMemo, useState } from 'react';
import { civilDateIn, addDays, formatDayHeading, formatTimeRange, formatWeek, groupByDay, weekStart, weekWindow } from '../agenda-model';
import { useCommandSnapshot } from '../command-store';
import { activeInstructors } from '../invitation-model';
import { learnerSchema, lessonSchema, memberSchema, readAll, type Lesson } from '../school-api';
import { EmptyState, Notice, SelectField, StatusBadge, Symbol, type Tone } from '../ui';
import { useConsole, useLoad } from './context';
import { LoadState, SectionHeading } from './layout';

const lessonState: Partial<Record<Lesson['status'], { label: string; tone: Tone; symbol: 'check' | 'ban' | 'alert' }>> = {
  COMPLETED: { label: 'Réalisée', tone: 'success', symbol: 'check' },
  CANCELLED: { label: 'Annulée', tone: 'neutral', symbol: 'ban' },
  NO_SHOW: { label: 'Absent', tone: 'warning', symbol: 'alert' },
};

/** Agenda de l'école en lecture seule : la planification des leçons se fait dans l'app. */
export function AgendaSection() {
  const { schoolId, school } = useConsole();
  const { revision } = useCommandSnapshot();
  const [monday, setMonday] = useState(() => weekStart(civilDateIn(school.timeZone)));
  const [instructor, setInstructor] = useState('');
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

  return (
    <div className="section-stack">
      <SectionHeading context="Planning" title="Agenda"
        actions={<div className="week-nav" role="group" aria-label="Semaine affichée">
          <button type="button" className="button secondary" aria-label="Semaine précédente" onClick={() => setMonday(addDays(monday, -7))}><Symbol kind="back" bare /></button>
          <span className="week-label" aria-live="polite">{formatWeek(monday)}</span>
          <button type="button" className="button secondary" aria-label="Semaine suivante" onClick={() => setMonday(addDays(monday, 7))}><span className="flip"><Symbol kind="back" bare /></span></button>
          <button type="button" className="button quiet" disabled={monday === thisWeek} onClick={() => setMonday(thisWeek)}>Aujourd’hui</button>
        </div>} />
      <LoadState loaded={loaded} label="Lecture de l’agenda…">{value => <>
        {instructors.length > 1 && <div className="list-toolbar">
          <SelectField label="Moniteur" value={instructor} onChange={setInstructor}
            options={[{ value: '', label: 'Tous les moniteurs' }, ...instructors.map(item => ({ value: item.id, label: item.displayName }))]} />
        </div>}
        {value.truncated && <Notice tone="warning" title="Semaine partielle" live={false}><p>Trop de leçons pour cette semaine : choisissez un moniteur.</p></Notice>}
        {days.length === 0 ? <EmptyState symbol="clock" title="Aucune leçon" message="Cette semaine n’a aucune leçon." />
          : days.map(day => <section key={day.day} className="agenda-day" aria-labelledby={`day-${day.day}`}>
            <h2 id={`day-${day.day}`} className="section-title">{formatDayHeading(day.day)}</h2>
            <ul className="row-list">{day.items.map(lesson => {
              const state = lessonState[lesson.status];
              return <li key={lesson.id} className={lesson.status === 'CANCELLED' ? 'muted-row' : undefined}>
                <div className="row-text">
                  <h3 className="row-title">{formatTimeRange(lesson.plannedStart, lesson.plannedEnd, school.timeZone)} · {learnerName(lesson.learnerId)}</h3>
                  <p className="row-meta">{memberName(lesson.instructorMembershipId)}{lesson.meetingPoint ? ` · ${lesson.meetingPoint}` : ''}</p>
                </div>
                {state && <StatusBadge tone={state.tone} symbol={state.symbol}>{state.label}</StatusBadge>}
                {lesson.status === 'PLANNED' && lesson.permitWarning === true && <StatusBadge tone="warning" symbol="alert">Permis à vérifier</StatusBadge>}
              </li>;
            })}</ul>
          </section>)}
      </>}</LoadState>
    </div>
  );
}
