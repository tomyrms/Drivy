import { dayOf } from './agenda-model.js';

type ReportLesson = { plannedStart: string; timeZone: string; currentPublishedRevisionId?: string | null | undefined };

/** A lesson keeps its historical time zone, including after the school's zone changes. */
export function reportHistory<T extends ReportLesson>(lessons: readonly T[], period: { year: string; month: string }, truncated: boolean) {
  const reported = lessons.filter(lesson => lesson.currentPublishedRevisionId)
    .sort((a, b) => Date.parse(b.plannedStart) - Date.parse(a.plannedStart));
  const dateOf = (lesson: T) => dayOf(lesson.plannedStart, lesson.timeZone);
  const years = [...new Set(reported.map(lesson => dateOf(lesson).slice(0, 4)))].sort().reverse();
  // A partial read cannot promise that a period has no reports. Keep it unfiltered and visibly partial.
  const canFilter = !truncated;
  const filtered = canFilter ? reported.filter(lesson => {
    const date = dateOf(lesson);
    return (!period.year || date.slice(0, 4) === period.year) && (!period.month || date.slice(5, 7) === period.month);
  }) : reported;
  return { reported, years, filtered, canFilter };
}
