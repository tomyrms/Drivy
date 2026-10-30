/**
 * Pure rules of the participants of a published course: who is enrolled, who waits, what each session recorded,
 * what was settled and who is validated. Four independent facts: none of them is ever deduced from another.
 * No DOM, no network. Validation of inputs and command bodies stay in `console/course-model.ts`.
 */
import { activeCompletion, activePayments, attendanceCell, type AttendanceStatus, type CourseEnrollment, type CourseRoster, type CourseSeries, type CourseSheetRow, type WaitlistEntry } from '../../console/course-model';

type Occurrence = CourseSeries['occurrences'][number];

/**
 * The session shown for the call. The one asked for wins; else the session under way; else the last one that started (the call being
 * taken is almost always the one held now or just before); else the first, which has not started. The call is never opened on a future session by default.
 */
export function defaultOccurrenceId(occurrences: readonly Occurrence[], requested: string | undefined, now: number): string {
  const ordered = [...occurrences].sort((a, b) => a.position - b.position);
  const asked = ordered.find(item => item.id === requested);
  const underway = ordered.find(item => Date.parse(item.startsAt) <= now && now <= Date.parse(item.endsAt));
  const lastStarted = [...ordered].reverse().find(item => Date.parse(item.startsAt) <= now);
  return (asked ?? underway ?? lastStarted ?? ordered[0])?.id ?? '';
}

export interface AttendanceSummary { present: number; absent: number; excused: number; unset: number }
/** Counts over the enrolments still active, for one session. A missing cell is « non renseigné », never absent. */
export function attendanceSummary(rows: readonly CourseSheetRow[], occurrenceId: string): AttendanceSummary {
  const total: AttendanceSummary = { present: 0, absent: 0, excused: 0, unset: 0 };
  for (const row of rows) {
    if (row.status !== 'ACTIVE') continue;
    const status = attendanceCell(row, occurrenceId).status;
    if (status === 'PRESENT') total.present++; else if (status === 'ABSENT') total.absent++; else if (status === 'EXCUSED') total.excused++; else total.unset++;
  }
  return total;
}
export const attendanceStatusOf = (row: CourseSheetRow, occurrenceId: string): AttendanceStatus | null => attendanceCell(row, occurrenceId).status;

/** What the school counts as settled for one participant: confirmed records not voided. A correction is a later record, never an edit. */
export const settledCents = (row: Pick<CourseSheetRow, 'payments'>): number => activePayments(row).reduce((sum, payment) => sum + payment.amountCents, 0);
// Cancelling an enrolment never refunds a payment: confirmed records keep counting.
export const groupSettledCents = (rows: readonly CourseSheetRow[]): number => rows.reduce((sum, row) => sum + settledCents(row), 0);

export type OfferState = 'waiting' | 'offered' | 'expired';
/** A proposed seat whose deadline passed is shown as expired; the school, not this screen, removes it. */
export function offerState(entry: Pick<WaitlistEntry, 'status' | 'offerExpiresAt'>, now: number): OfferState {
  if (entry.status !== 'OFFERED') return 'waiting';
  return entry.offerExpiresAt !== null && Date.parse(entry.offerExpiresAt) <= now ? 'expired' : 'offered';
}

/** Active enrolments first (ordered by name), cancelled ones kept apart: the history of the series stays readable. */
export function rosterSplit(roster: Pick<CourseRoster, 'items'>): { active: CourseEnrollment[]; cancelled: CourseEnrollment[] } {
  const byName = (a: CourseEnrollment, b: CourseEnrollment) => a.learnerDisplayName.localeCompare(b.learnerDisplayName, 'fr-CH');
  return { active: roster.items.filter(item => item.status === 'ACTIVE').sort(byName), cancelled: roster.items.filter(item => item.status === 'CANCELLED').sort(byName) };
}

/** A name filter limited to the people already on the school's own list; it never reaches another list. */
export function filterByName<T extends { learnerDisplayName: string }>(rows: readonly T[], query: string): T[] {
  const needle = query.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('fr').trim();
  if (!needle) return [...rows];
  return rows.filter(row => row.learnerDisplayName.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('fr').includes(needle));
}

export type Eligibility = 'cancelled' | 'validated' | 'validated-elsewhere' | 'no-requirement' | 'missing' | 'eligible';
/** Internal validation, apart from presence and payment: eligible only when every required session is marked present. */
export function eligibility(row: Pick<CourseSheetRow, 'status' | 'requirements' | 'completion'>, seriesId: string): Eligibility {
  if (row.status !== 'ACTIVE') return 'cancelled';
  const completion = activeCompletion(row);
  if (completion) return completion.seriesId === seriesId ? 'validated' : 'validated-elsewhere';
  if (row.requirements.required === 0) return 'no-requirement';
  return row.requirements.missing > 0 ? 'missing' : 'eligible';
}

/** A read that started before the latest confirmed write must never replace what that write returned. */
export const readIsCurrent = (readGeneration: number, writeGeneration: number): boolean => readGeneration >= writeGeneration;

/** Stable key of one intention: the same typed action sent again reuses its operation id, a different one never does. */
export const intentKey = (scope: string, kind: string, path: string, body: unknown): string => `${scope} ${kind} ${path} ${JSON.stringify(body)}`;
