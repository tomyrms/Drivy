import { useEffect, useState } from 'react';
import { CalendarDays } from 'lucide-react';
import { addDays, startOfDay, weekStart } from '../../agenda-model';
import { useCommandSnapshot } from '../../command-store';
import { agendaDays } from '../../console/agenda-projection';
import { courseSeriesListSchema } from '../../console/course-model';
import { useConsole, useLoad } from '../../console/context';
import { lessonSchema, readAll, readSchool } from '../../school-api';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle } from '../../components/ui/empty';
import { ReadFeedback } from '../components/feedback';
import { phaseLabels } from '../agenda/presentation';
import { PilotageSection } from './components';
import { dayHeading, groupByDay, upcomingAppointments, type Appointment } from './appointments';

const horizonDays = 7, limit = 8;

/**
 * Prochains rendez-vous (#377) : leçons et séances collectives des sept prochains jours, tirées de la même projection que l'agenda.
 * Chaque ligne ouvre la vraie fiche dans l'agenda avec le moniteur filtré. Une lecture de séances qui échoue ne cache pas les leçons.
 */
export function Appointments({ today, instructor, learnerName, memberName }: {
  today: string;
  instructor: string | undefined;
  learnerName: (id: string) => string;
  memberName: (id: string) => string;
}) {
  const { schoolId, school, navigate } = useConsole();
  const { revision } = useCommandSnapshot();
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);
  const from = startOfDay(today, school.timeZone), to = startOfDay(addDays(today, horizonDays), school.timeZone);
  const scope = `${schoolId}/${today}/${instructor ?? ''}`;
  const lessons = useLoad(async () => {
    if (!from || !to) throw new Error('Période invalide.');
    return readAll(schoolId, 'lessons', lessonSchema, { from, to, ...(instructor ? { instructorMembershipId: instructor } : {}) });
  }, [schoolId, revision, from, to, instructor], scope);
  const courses = useLoad(async () => {
    if (!from || !to) throw new Error('Période invalide.');
    return (await readSchool(schoolId, 'course-series', courseSeriesListSchema, { from, to })).items;
  }, [schoolId, revision, from, to], `${schoolId}/${today}`);
  const open = (appointment: Appointment) => navigate('agenda', {
    week: weekStart(appointment.day), day: appointment.day, ...(instructor ? { instructor } : {}),
    ...('lesson' in appointment.target ? { lesson: appointment.target.lesson } : { course: appointment.target.course, occurrence: appointment.target.occurrence }),
  });
  const rows = from && to && lessons.data
    ? upcomingAppointments(agendaDays(lessons.data.items, courses.data ?? [], { timeZone: school.timeZone, from, to, instructor: instructor ?? '', includeCourses: true }),
      { now, limit, learnerName, memberName })
    : [];
  const time = new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', timeZone: school.timeZone });
  const range = (appointment: Appointment) => `${time.format(new Date(appointment.startsAt))}–${time.format(new Date(appointment.endsAt))}`;
  return <PilotageSection title="Prochains rendez-vous" action={<Button variant="ghost" size="sm" onClick={() => navigate('agenda', instructor ? { instructor } : {})}>Voir l’agenda</Button>}>
    <ReadFeedback loaded={lessons} label="Lecture des rendez-vous" />
    {courses.status === 'error' && <ReadFeedback loaded={courses} label="Lecture des séances collectives" />}
    {lessons.data !== undefined && (rows.length === 0
      ? <Empty><EmptyHeader><EmptyMedia variant="icon"><CalendarDays aria-hidden="true" /></EmptyMedia><EmptyTitle>Aucun rendez-vous cette semaine</EmptyTitle></EmptyHeader></Empty>
      // Une seule liste : chaque jour y ouvre son bandeau, les rendez-vous suivent sous des filets.
      : <div className="pilotage-list">{groupByDay(rows).map(group => <div key={group.day} className="pilotage-list-group">
        <h3 className="pilotage-day">{dayHeading(group.day, today)}</h3>
        <ul>{group.items.map(appointment => <li key={appointment.key}>
          <Button variant="ghost" className="pilotage-appointment" onClick={() => open(appointment)}>
            <span className="pilotage-appointment-time">{range(appointment)}</span>
            <span className="pilotage-appointment-what"><strong>{appointment.title}</strong><span>{appointment.detail}</span></span>
            {appointment.phase && appointment.phase !== 'planned' && <Badge variant="outline">{phaseLabels[appointment.phase]}</Badge>}
          </Button>
        </li>)}</ul>
      </div>)}</div>)}
  </PilotageSection>;
}
