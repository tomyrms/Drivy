import { addDays, lessonPhase } from '../../agenda-model';
import type { AgendaEvent } from '../../console/agenda-projection';

/**
 * Rendez-vous utiles de l'accueil (#377) : ce qui reste à faire ou à surveiller, tiré de la projection de l'agenda.
 * Ni deuxième calendrier ni source de réservations : une leçon terminée, annulée ou absente n'est pas utile ici.
 */
export type OpenPhase = 'planned' | 'waiting' | 'started' | 'to-finish';
export interface Appointment {
  key: string;
  day: string;
  startsAt: string;
  endsAt: string;
  title: string;
  detail: string;
  /** Seules les leçons ont une phase ; le badge n'apparaît que si elle sort de l'ordinaire. */
  phase: OpenPhase | null;
  target: { lesson: string } | { course: string; occurrence: string };
}

export interface AppointmentContext {
  now: number;
  limit: number;
  learnerName: (id: string) => string;
  memberName: (id: string) => string;
}

export function upcomingAppointments(days: readonly { day: string; items: readonly AgendaEvent[] }[], context: AppointmentContext): Appointment[] {
  const result: Appointment[] = [];
  for (const { day, items } of days) {
    for (const event of items) {
      if (event.kind === 'lesson') {
        const phase = lessonPhase(event.lesson, context.now);
        if (phase === 'completed' || phase === 'cancelled' || phase === 'absent') continue;
        result.push({ key: event.key, day, startsAt: event.lesson.plannedStart, endsAt: event.lesson.plannedEnd, phase,
          title: context.learnerName(event.lesson.learnerId), detail: context.memberName(event.lesson.instructorMembershipId), target: { lesson: event.lesson.id } });
      } else {
        if (event.series.status !== 'PUBLISHED' && event.series.status !== 'CLOSED') continue;
        if (Date.parse(event.occurrence.endsAt) <= context.now) continue;
        result.push({ key: event.key, day, startsAt: event.occurrence.startsAt, endsAt: event.occurrence.endsAt, phase: null,
          title: event.series.title, detail: `${event.occurrence.instructorDisplayName} · ${event.series.seatsTaken}/${event.series.capacity} inscrits`,
          target: { course: event.series.id, occurrence: event.occurrence.id } });
      }
    }
  }
  return result.slice(0, context.limit);
}

const weekdayFormat = new Intl.DateTimeFormat('fr-CH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
/** « Aujourd'hui », « Demain », puis « jeudi 5 novembre ». */
export function dayHeading(day: string, today: string): string {
  if (day === today) return 'Aujourd’hui';
  if (day === addDays(today, 1)) return 'Demain';
  return weekdayFormat.format(new Date(`${day}T12:00:00Z`));
}

/** Les rendez-vous regroupés par jour civil, dans l'ordre reçu. */
export function groupByDay(appointments: readonly Appointment[]): { day: string; items: Appointment[] }[] {
  const groups: { day: string; items: Appointment[] }[] = [];
  for (const appointment of appointments) {
    const last = groups[groups.length - 1];
    if (last && last.day === appointment.day) last.items.push(appointment);
    else groups.push({ day: appointment.day, items: [appointment] });
  }
  return groups;
}
