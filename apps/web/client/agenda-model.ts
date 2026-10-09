import { isCivilDate, schoolTimeToInstant } from './command-core.js';

/** A planned time is never evidence that teaching started or finished. */
export function lessonPhase(lesson: { status: string; plannedStart: string; plannedEnd: string; actualStart?: string | null | undefined }, now = Date.now()): 'planned' | 'waiting' | 'started' | 'to-finish' | 'completed' | 'cancelled' | 'absent' {
  if (lesson.status === 'COMPLETED') return 'completed';
  if (lesson.status === 'CANCELLED') return 'cancelled';
  if (lesson.status === 'NO_SHOW') return 'absent';
  if (lesson.actualStart && Number.isFinite(Date.parse(lesson.actualStart))) return Date.parse(lesson.plannedEnd) <= now ? 'to-finish' : 'started';
  return Date.parse(lesson.plannedStart) <= now ? 'waiting' : 'planned';
}

/**
 * Week view of the school agenda: pure calendar rules, in the time zone of the school.
 * Civil dates are 'YYYY-MM-DD'; they are shifted by calendar arithmetic, never by a fixed number of hours.
 */
const parts = (civil: string): [number, number, number] => {
  const [year, month, day] = civil.split('-').map(Number);
  return [year!, month!, day!];
};

export function addDays(civil: string, days: number): string {
  const [year, month, day] = parts(civil);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

/** Monday of the week containing this date. */
export function weekStart(civil: string): string {
  const [year, month, day] = parts(civil);
  const weekday = (new Date(Date.UTC(year, month - 1, day)).getUTCDay() + 6) % 7;
  return addDays(civil, -weekday);
}

/** Today's date on the wall clock of the school. */
export function civilDateIn(timeZone: string, instant: number = Date.now()): string {
  return new Intl.DateTimeFormat('sv-SE', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(instant));
}

/** Instants bounding the week that starts on `monday` (inclusive) and the next one (exclusive); null if the date or zone is invalid. */
export function weekWindow(monday: string, timeZone: string): { from: string; to: string } | null {
  if (!isCivilDate(monday)) return null;
  const from = schoolTimeToInstant(`${monday}T00:00`, timeZone);
  const to = schoolTimeToInstant(`${addDays(monday, 7)}T00:00`, timeZone);
  return from && to ? { from, to } : null;
}

export const dayOf = (instant: string, timeZone: string): string => civilDateIn(timeZone, Date.parse(instant));

/** Lessons grouped by local day, days and lessons in chronological order. */
export function groupByDay<T extends { plannedStart: string }>(lessons: readonly T[], timeZone: string): { day: string; items: T[] }[] {
  const days = new Map<string, T[]>();
  for (const lesson of [...lessons].sort((a, b) => Date.parse(a.plannedStart) - Date.parse(b.plannedStart))) {
    const key = dayOf(lesson.plannedStart, timeZone);
    days.set(key, [...(days.get(key) ?? []), lesson]);
  }
  return [...days.entries()].map(([day, items]) => ({ day, items }));
}

export function formatDayHeading(civil: string): string {
  const [year, month, day] = parts(civil);
  return new Intl.DateTimeFormat('fr-CH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(new Date(Date.UTC(year, month - 1, day, 12)));
}

export function formatTimeRange(start: string, end: string, timeZone: string): string {
  const clock = new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone });
  return `${clock.format(new Date(start))}–${clock.format(new Date(end))}`;
}

export function formatWeek(monday: string): string {
  const [year, month, day] = parts(monday);
  const format = new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'long', timeZone: 'UTC' });
  const end = parts(addDays(monday, 6));
  return `${format.format(new Date(Date.UTC(year, month - 1, day, 12)))} – ${format.format(new Date(Date.UTC(end[0], end[1] - 1, end[2], 12)))} ${end[0]}`;
}
