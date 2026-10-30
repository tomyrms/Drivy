/**
 * Pure presentation rules of the collective courses: labels, compact summaries and draft comparison.
 * No DOM, no network. Validation and command bodies stay in `console/course-model.ts`, the single source of those rules.
 */
import { formatTimeRange } from '../../agenda-model';
import { formatHours, languages, sessionInterval, type CourseSeries, type SeriesForm, type SessionForm } from '../../console/course-model';

type Occurrence = CourseSeries['occurrences'][number];

/** A civil date ('YYYY-MM-DD') as « mer. 4 nov. 2026 ». */
export function civilDayLabel(civil: string): string {
  const [year, month, day] = civil.split('-').map(Number);
  if (!year || !month || !day) return 'Date à choisir';
  return new Intl.DateTimeFormat('fr-CH', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(year, month - 1, day, 12)));
}
export const instantDayLabel = (instant: string, timeZone: string) =>
  new Intl.DateTimeFormat('fr-CH', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone }).format(new Date(instant));
export const instantDateTime = (instant: string, timeZone: string) =>
  new Intl.DateTimeFormat('fr-CH', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone }).format(new Date(instant));

export const languageLabel = (language: string | null): string | null =>
  language ? languages.find(item => item.value === language)?.label ?? language : null;

/** The one unusual state worth a badge; a plain published course carries none. */
export function seriesStateLabel(series: Pick<CourseSeries, 'status' | 'lastEndsAt'>, now = Date.now()): string | null {
  if (series.status === 'DRAFT') return 'Brouillon';
  if (series.status === 'CANCELLED') return 'Annulé';
  if (series.status === 'CLOSED') return 'Clos';
  return Date.parse(series.lastEndsAt) < now ? 'Terminé' : null;
}

/** A refusal of the school followed by the reassurance that the typed values stay, unless the message already says so. */
export const keptMessage = (message: string) => /conservée/.test(message) ? message : `${message} Votre saisie est conservée.`;

export const sessionCountLabel = (count: number) => `${count} ${count === 1 ? 'séance' : 'séances'}`;
export const seatsLabel = (count: number) => `${count} ${count === 1 ? 'inscrit' : 'inscrits'}`;

/** « 4 séances · 8 h · du 3 nov. au 24 nov. 2026 », from the saved occurrences. */
export function seriesSummary(series: Pick<CourseSeries, 'occurrences' | 'totalMinutes'>, timeZone: string): string {
  const ordered = [...series.occurrences].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt));
  const first = ordered[0], last = ordered.at(-1);
  const count = sessionCountLabel(ordered.length), hours = formatHours(series.totalMinutes);
  if (!first || !last) return count;
  const from = instantDayLabel(first.startsAt, timeZone), to = instantDayLabel(last.endsAt, timeZone);
  return `${count} · ${hours} · ${from === to ? from : `${from} – ${to}`}`;
}

export const occurrenceTimes = (occurrence: Pick<Occurrence, 'startsAt' | 'endsAt'>, timeZone: string) => formatTimeRange(occurrence.startsAt, occurrence.endsAt, timeZone);

/** Length of one typed session in minutes; null while it is incomplete or does not exist (daylight-saving gap). */
export function sessionMinutes(session: SessionForm, timeZone: string): number | null {
  const interval = sessionInterval(session, timeZone);
  return interval && interval.end > interval.start ? Math.round((interval.end - interval.start) / 60_000) : null;
}

/** Content of a draft without session keys, sessions in date order: two drafts with the same signature say the same thing. */
export function formSignature(form: SeriesForm): string {
  const sessions = form.sessions.map(({ key: _key, ...rest }) => rest)
    .sort((a, b) => `${a.date}T${a.start}${a.end}${a.instructor}`.localeCompare(`${b.date}T${b.start}${b.end}${b.instructor}`));
  return JSON.stringify({ ...form, sessions });
}

/** Sessions whose date, hours or instructor differ from the saved ones, matched by position. */
export function changedSessions(before: readonly SessionForm[], after: readonly SessionForm[]): Set<string> {
  const changed = new Set<string>();
  after.forEach((session, index) => {
    const previous = before[index];
    if (!previous || previous.date !== session.date || previous.start !== session.start || previous.end !== session.end || previous.instructor !== session.instructor) changed.add(session.key);
  });
  return changed;
}

/** Refusals that concern the sessions rather than a single field: shown beside the session list. */
export const sessionRefusalCodes = ['COURSE_INSTRUCTOR_CONFLICT', 'COURSE_SCHEDULE_CONFLICT', 'COURSE_OCCURRENCES_OVERLAP', 'COURSE_OCCURRENCES_REQUIRED', 'COURSE_IN_PAST',
  'COURSE_CONFLICT', 'INVALID_INTERVAL', 'INSTRUCTOR_NOT_ACTIVE', 'COURSE_OCCURRENCE_COUNT'] as const;
export const isSessionRefusal = (code: string | undefined) => code !== undefined && (sessionRefusalCodes as readonly string[]).includes(code);
