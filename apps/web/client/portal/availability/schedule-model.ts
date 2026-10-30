/**
 * Pure rules of the instructor schedule: weekly hours, periods of validity and absences.
 * No DOM, no network. The API stays the only judge; these rules only avoid a useless round trip and explain a refusal near its field.
 */
import { overlappingHours, type WeeklyHours } from '../../availability-model';
import { isCivilDate, schoolTimeToInstant } from '../../command-core';
import type { Availability, Closure } from '../../school-api';

export const weekdayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'] as const;
export const weekdayNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'] as const;
/** The API accepts one reason of at most 1 000 characters on an absence. */
export const ABSENCE_REASON_LIMIT = 1000;
/** Fixed text of the removal command: the API requires a reason, the web console does not ask for one. */
export const REMOVAL_REASON = 'Retirée depuis la gestion web.';

const clock = /^\d{2}:\d{2}$/;
export const minutesOf = (value: string): number => Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5));

/** « Lun–Ven » for a run of three days or more, otherwise the listed days. */
export function dayRange(weekdays: readonly number[]): string {
  const sorted = [...weekdays].sort((a, b) => a - b);
  const contiguous = sorted.every((day, index) => index === 0 || day === sorted[index - 1]! + 1);
  return contiguous && sorted.length > 2 ? `${weekdayLabels[sorted[0]! - 1]}–${weekdayLabels[sorted.at(-1)! - 1]}` : sorted.map(day => weekdayLabels[day - 1]).join(', ');
}

/** « 12 oct. 2026 » from a civil date. */
export function formatCivil(civil: string): string {
  const [year, month, day] = civil.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-CH', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(year!, month! - 1, day!, 12)));
}

/** Period of validity in words; an empty end date means the hours stay valid until changed. */
export function periodLabel(rule: Pick<Availability, 'validFrom' | 'validUntil'>): string {
  return rule.validUntil ? `Du ${formatCivil(rule.validFrom)} au ${formatCivil(rule.validUntil)}` : `Dès le ${formatCivil(rule.validFrom)}`;
}

export type RuleState = 'current' | 'upcoming' | 'ended';
export function ruleState(rule: Pick<Availability, 'validFrom' | 'validUntil'>, today: string): RuleState {
  if (rule.validUntil !== null && rule.validUntil < today) return 'ended';
  return rule.validFrom > today ? 'upcoming' : 'current';
}

const byWeekThenStart = (a: Availability, b: Availability) => a.weekdays[0]! - b.weekdays[0]! || a.localStart.localeCompare(b.localStart) || a.validFrom.localeCompare(b.validFrom);
export function ruleGroups(rules: readonly Availability[], today: string): Record<RuleState, Availability[]> {
  const groups: Record<RuleState, Availability[]> = { current: [], upcoming: [], ended: [] };
  for (const rule of rules) groups[ruleState(rule, today)].push(rule);
  groups.current.sort(byWeekThenStart);
  groups.upcoming.sort((a, b) => a.validFrom.localeCompare(b.validFrom) || byWeekThenStart(a, b));
  groups.ended.sort((a, b) => (b.validUntil ?? '').localeCompare(a.validUntil ?? '') || byWeekThenStart(a, b));
  return groups;
}

export interface WeekRange { id: string; start: string; end: string; startMinute: number; endMinute: number }
export interface WeekRow { weekday: number; ranges: WeekRange[] }
/** The ordinary week as it stands on `today`: hours in force that day, listed by weekday. A weekday without range stays empty. */
export function weekRows(rules: readonly Availability[], today: string): WeekRow[] {
  const inForce = rules.filter(rule => ruleState(rule, today) === 'current');
  return weekdayLabels.map((_, index) => ({
    weekday: index + 1,
    ranges: inForce.filter(rule => rule.weekdays.includes(index + 1))
      .map(rule => ({ id: rule.id, start: rule.localStart, end: rule.localEnd, startMinute: minutesOf(rule.localStart), endMinute: minutesOf(rule.localEnd) }))
      .sort((a, b) => a.startMinute - b.startMinute),
  }));
}

/** Hour bounds of the week bar: never narrower than 07:00–19:00, widened to the ranges shown. */
export function weekScale(rows: readonly WeekRow[]): { startHour: number; endHour: number } {
  const ranges = rows.flatMap(row => row.ranges);
  return {
    startHour: Math.min(7, ...ranges.map(range => Math.floor(range.startMinute / 60))),
    endHour: Math.max(19, ...ranges.map(range => Math.ceil(range.endMinute / 60))),
  };
}

export interface RuleDraft { weekdays: number[]; start: string; end: string; from: string; until: string }
export function draftFromRule(rule: Availability | null, today: string): RuleDraft {
  return rule ? { weekdays: [...rule.weekdays].sort((a, b) => a - b), start: rule.localStart, end: rule.localEnd, from: rule.validFrom, until: rule.validUntil ?? '' }
    : { weekdays: [1, 2, 3, 4, 5], start: '08:00', end: '18:00', from: today, until: '' };
}
export const sameRuleDraft = (a: RuleDraft, b: RuleDraft) => a.start === b.start && a.end === b.end && a.from === b.from && a.until === b.until
  && [...a.weekdays].sort().join() === [...b.weekdays].sort().join();

export interface RuleProblems { weekdays?: string; start?: string; end?: string; from?: string; until?: string; overlap?: Availability }
export const hasRuleProblems = (problems: RuleProblems) => Object.keys(problems).length > 0;
/** `others` are the instructor's other hours: the edited rule is left out so it never conflicts with itself. */
export function ruleProblems(draft: RuleDraft, others: readonly Availability[]): RuleProblems {
  const problems: RuleProblems = {};
  if (draft.weekdays.length === 0) problems.weekdays = 'Choisissez au moins un jour.';
  if (!clock.test(draft.start)) problems.start = 'Indiquez l’heure de début.';
  if (!clock.test(draft.end)) problems.end = 'Indiquez l’heure de fin.';
  else if (clock.test(draft.start) && draft.end <= draft.start) problems.end = 'La fin doit suivre le début.';
  if (!isCivilDate(draft.from)) problems.from = 'Indiquez une date valide.';
  if (draft.until && !isCivilDate(draft.until)) problems.until = 'Indiquez une date valide.';
  else if (draft.until && isCivilDate(draft.from) && draft.until < draft.from) problems.until = 'La fin doit suivre le début de validité.';
  if (!hasRuleProblems(problems)) {
    const proposed: WeeklyHours = { weekdays: draft.weekdays, localStart: draft.start, localEnd: draft.end, validFrom: draft.from, validUntil: draft.until || null };
    const overlap = others.find(rule => overlappingHours([rule], proposed) !== null);
    if (overlap) problems.overlap = overlap;
  }
  return problems;
}

/** Body of POST/PUT availability-rules, without operationId (added by the command). */
export function ruleBody(draft: RuleDraft, instructorMembershipId: string) {
  return { instructorMembershipId, weekdays: [...draft.weekdays].sort((a, b) => a - b), localStart: draft.start, localEnd: draft.end, validFrom: draft.from, validUntil: draft.until || null };
}

export interface AbsenceDraft { start: string; end: string; reason: string }
export const emptyAbsenceDraft: AbsenceDraft = { start: '', end: '', reason: '' };
export interface AbsenceProblems { start?: string; end?: string; reason?: string }
export function absenceInstants(draft: AbsenceDraft, timeZone: string) {
  return { startsAt: draft.start ? schoolTimeToInstant(draft.start, timeZone) : null, endsAt: draft.end ? schoolTimeToInstant(draft.end, timeZone) : null };
}
export function absenceProblems(draft: AbsenceDraft, timeZone: string): AbsenceProblems {
  const problems: AbsenceProblems = {};
  const { startsAt, endsAt } = absenceInstants(draft, timeZone);
  if (!draft.start) problems.start = 'Indiquez le début.';
  else if (!startsAt) problems.start = 'Cette heure n’existe pas dans le fuseau de l’école.';
  if (!draft.end) problems.end = 'Indiquez la fin.';
  else if (!endsAt) problems.end = 'Cette heure n’existe pas dans le fuseau de l’école.';
  else if (startsAt && Date.parse(endsAt) <= Date.parse(startsAt)) problems.end = 'La fin doit suivre le début.';
  if ([...draft.reason].length > ABSENCE_REASON_LIMIT) problems.reason = `${ABSENCE_REASON_LIMIT} caractères au plus.`;
  return problems;
}
/** Body of POST closures; null while the period is incomplete or invalid. */
export function absenceBody(draft: AbsenceDraft, instructorMembershipId: string, timeZone: string) {
  if (Object.keys(absenceProblems(draft, timeZone)).length) return null;
  const { startsAt, endsAt } = absenceInstants(draft, timeZone);
  return { instructorMembershipId, startsAt, endsAt, reason: draft.reason.trim() || null };
}

/** Absences still to come or under way, soonest first. */
export function upcomingAbsences(closures: readonly Closure[], now = Date.now()): Closure[] {
  return closures.filter(item => Date.parse(item.endsAt) > now).sort((a, b) => a.startsAt.localeCompare(b.startsAt));
}

const dayFormat = (timeZone: string) => new Intl.DateTimeFormat('fr-CH', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone });
const clockFormat = (timeZone: string) => new Intl.DateTimeFormat('fr-CH', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone });
const civilIn = (instant: string, timeZone: string) => new Intl.DateTimeFormat('sv-SE', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(instant));
/** An absence in the time zone of the school: one date and a time span, or two dated ends. */
export function absenceLabel(item: Pick<Closure, 'startsAt' | 'endsAt'>, timeZone: string): { title: string; detail: string } {
  const day = dayFormat(timeZone), time = clockFormat(timeZone);
  const start = new Date(item.startsAt), end = new Date(item.endsAt);
  if (civilIn(item.startsAt, timeZone) === civilIn(item.endsAt, timeZone)) return { title: day.format(start), detail: `${time.format(start)}–${time.format(end)}` };
  return { title: `${day.format(start)}, ${time.format(start)}`, detail: `jusqu’au ${day.format(end)}, ${time.format(end)}` };
}
