import { civilDateIn } from '../agenda-model.js';
import type { Lesson } from '../school-api.js';
import { seriesByDay, type CourseSeries } from './course-model.js';

export type AgendaEvent =
  | { kind: 'lesson'; key: string; startsAt: string; lesson: Lesson }
  | { kind: 'course'; key: string; startsAt: string; series: CourseSeries; occurrence: CourseSeries['occurrences'][number] };

/** One authorized projection owns ordering, day markers and counts. An occurrence is not its series. */
export function agendaDays(lessons: readonly Lesson[], series: readonly CourseSeries[], options: {
  timeZone: string; from: string; to: string; instructor: string; includeCourses: boolean;
}): { day: string; items: AgendaEvent[] }[] {
  const { timeZone, instructor, includeCourses } = options;
  const from = Date.parse(options.from), to = Date.parse(options.to);
  const byDay = new Map<string, Map<string, AgendaEvent>>();
  const add = (event: AgendaEvent) => {
    const day = civilDateIn(timeZone, Date.parse(event.startsAt));
    const events = byDay.get(day) ?? new Map<string, AgendaEvent>();
    events.set(event.key, event); byDay.set(day, events);
  };
  for (const lesson of lessons) {
    if (instructor && lesson.instructorMembershipId !== instructor) continue;
    if (Date.parse(lesson.plannedEnd) <= from || Date.parse(lesson.plannedStart) >= to) continue;
    add({ kind: 'lesson', key: `lesson:${lesson.id}`, startsAt: lesson.plannedStart, lesson });
  }
  if (includeCourses) for (const entries of seriesByDay(series, instant => civilDateIn(timeZone, Date.parse(instant)), from, to).values()) {
    for (const { series: course, occurrence } of entries) {
      if (instructor && occurrence.instructorMembershipId !== instructor) continue;
      add({ kind: 'course', key: `course:${course.id}:${occurrence.id}`, startsAt: occurrence.startsAt, series: course, occurrence });
    }
  }
  return [...byDay].sort(([a], [b]) => a.localeCompare(b)).map(([day, events]) => ({ day,
    items: [...events.values()].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt)
      || Date.parse(a.kind === 'lesson' ? a.lesson.plannedEnd : a.occurrence.endsAt) - Date.parse(b.kind === 'lesson' ? b.lesson.plannedEnd : b.occurrence.endsAt)
      || a.key.localeCompare(b.key)),
  }));
}

export function agendaCounts(events: readonly AgendaEvent[]) {
  return events.reduce((counts, event) => {
    counts[event.kind === 'lesson' ? 'lessons' : 'courses']++;
    return counts;
  }, { lessons: 0, courses: 0 });
}

export function agendaCountLabel(counts: { lessons: number; courses: number }, lessonsOnly = false): string {
  const parts: string[] = [];
  if (counts.lessons || lessonsOnly) parts.push(`${counts.lessons} ${counts.lessons === 1 ? 'leçon' : 'leçons'}`);
  if (counts.courses) parts.push(`${counts.courses} ${counts.courses === 1 ? 'séance collective' : 'séances collectives'}`);
  return parts.join(' · ') || '0 rendez-vous';
}

/** A successful lesson read cannot certify an older or failed course/directory read. */
export function agendaReadStatus(sources: readonly { status: 'loading' | 'ready' | 'error'; data: unknown; readAt?: number }[], partial: boolean) {
  const ready = sources.every(source => source.status === 'ready' && source.data !== undefined && source.readAt !== undefined);
  return { complete: ready && !partial, readAt: ready ? Math.min(...sources.map(source => source.readAt!)) : undefined };
}
