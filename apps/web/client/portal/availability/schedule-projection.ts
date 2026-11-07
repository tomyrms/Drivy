/**
 * Local projection of the schedule intentions still followed by the command store (#110): rows « À confirmer » shown while the
 * school has not answered. Pure: no DOM, no network.
 *
 * A projection is a presentation, never a calendar fact. The ordinary week, the agenda and the proposal of slots keep reading the
 * school's hours and absences; a removal never frees a slot here (the row stays, marked), and nothing becomes bookable or valid
 * because of an intention. The school remains the only judge of overlaps, bookings and versions.
 */
import type { Availability, Closure } from '../../school-api';
import { absenceInstants, type AbsenceDraft, type RuleDraft } from './schedule-model';

/**
 * `settledAt`: the school confirmed this request (response or receipt). The row keeps showing what was confirmed, unmarked, until the
 * next read of the school replaces it, so a confirmed row never disappears and comes back; a confirmed removal is gone at once.
 */
interface Base { readonly tag: string; readonly operationId: string; readonly instructor: string; readonly settledAt?: number }
export type ScheduleIntention =
  | (Base & { readonly kind: 'rule-create'; readonly draft: RuleDraft })
  | (Base & { readonly kind: 'rule-update'; readonly ruleId: string; readonly draft: RuleDraft; readonly base?: Availability })
  | (Base & { readonly kind: 'rule-remove'; readonly ruleId: string })
  | (Base & { readonly kind: 'absence-create'; readonly draft: AbsenceDraft })
  | (Base & { readonly kind: 'absence-remove'; readonly closureId: string });

export type RowMark = 'creating' | 'changing' | 'removing';
export const markLabels: Record<RowMark, string> = { creating: 'À confirmer', changing: 'Modification à confirmer', removing: 'Retrait à confirmer' };

/** A row that exists only as an intention carries this prefix: it has no version, no id of the school and no action. */
export const PROVISIONAL = 'pending:';
export const isProvisional = (id: string) => id.startsWith(PROVISIONAL);

/** What a followed intention concerns, to keep a control available unless a request on the same aggregate is followed. */
export const ruleFamily = (kind: ScheduleIntention['kind']) => kind.startsWith('rule');

export interface ProjectedRules { readonly rules: Availability[]; readonly marks: ReadonlyMap<string, RowMark> }

/** Hours of one instructor as the person intends them: edited rows show their new values, new rows are added, removed rows stay marked. */
export function projectRules(confirmed: readonly Availability[], intentions: readonly ScheduleIntention[], instructor: string): ProjectedRules {
  const marks = new Map<string, RowMark>();
  const rules: Availability[] = confirmed.filter(rule => rule.instructorMembershipId === instructor).map(rule => ({ ...rule }));
  for (const intention of intentions) {
    if (intention.instructor !== instructor) continue;
    if (intention.kind === 'rule-create') {
      const id = `${PROVISIONAL}${intention.operationId}`;
      rules.push({ id, schoolId: '', version: 0, instructorMembershipId: instructor, weekdays: [...intention.draft.weekdays].sort((a, b) => a - b),
        localStart: intention.draft.start, localEnd: intention.draft.end, validFrom: intention.draft.from, validUntil: intention.draft.until || null });
      if (intention.settledAt === undefined) marks.set(id, 'creating');
    } else if (intention.kind === 'rule-update') {
      const index = rules.findIndex(rule => rule.id === intention.ruleId);
      if (index < 0) continue;
      rules[index] = { ...rules[index]!, weekdays: [...intention.draft.weekdays].sort((a, b) => a - b), localStart: intention.draft.start, localEnd: intention.draft.end,
        validFrom: intention.draft.from, validUntil: intention.draft.until || null };
      if (intention.settledAt === undefined) marks.set(intention.ruleId, 'changing');
    } else if (intention.kind === 'rule-remove') {
      const index = rules.findIndex(rule => rule.id === intention.ruleId);
      if (index < 0) continue;
      if (intention.settledAt === undefined) marks.set(intention.ruleId, 'removing'); else rules.splice(index, 1);
    }
  }
  return { rules, marks };
}

export interface ProjectedAbsences { readonly absences: Closure[]; readonly marks: ReadonlyMap<string, RowMark> }

/** Absences of one instructor still to come. A removed absence stays listed and marked: no slot is opened before the school says so. */
export function projectAbsences(confirmed: readonly Closure[], intentions: readonly ScheduleIntention[], instructor: string, timeZone: string): ProjectedAbsences {
  const marks = new Map<string, RowMark>();
  const absences: Closure[] = confirmed.filter(item => item.instructorMembershipId === instructor).map(item => ({ ...item }));
  for (const intention of intentions) {
    if (intention.instructor !== instructor) continue;
    if (intention.kind === 'absence-create') {
      const { startsAt, endsAt } = absenceInstants(intention.draft, timeZone);
      if (!startsAt || !endsAt) continue;
      const id = `${PROVISIONAL}${intention.operationId}`;
      absences.push({ id, schoolId: '', version: 0, instructorMembershipId: instructor, startsAt, endsAt, reason: intention.draft.reason.trim() || null });
      if (intention.settledAt === undefined) marks.set(id, 'creating');
    } else if (intention.kind === 'absence-remove') {
      const index = absences.findIndex(item => item.id === intention.closureId);
      if (index < 0) continue;
      if (intention.settledAt === undefined) marks.set(intention.closureId, 'removing'); else absences.splice(index, 1);
    }
  }
  return { absences, marks };
}

/**
 * Intentions that still show: the ones the store follows, and the confirmed ones until a read newer than their confirmation is on screen.
 * A refused or given-up request is not followed any more: it disappears, and the school's own rows are what remains.
 */
export function visibleIntentions(intentions: readonly ScheduleIntention[], followed: ReadonlySet<string>, readAt: number | undefined): ScheduleIntention[] {
  return intentions.filter(intention => intention.settledAt !== undefined ? (readAt ?? 0) < intention.settledAt : followed.has(intention.operationId));
}

/** Followed requests only (the confirmed ones are done): what makes the next one on the same aggregate wait. */
export const stillFollowed = (intentions: readonly ScheduleIntention[], followed: ReadonlySet<string>): ScheduleIntention[] =>
  intentions.filter(intention => intention.settledAt === undefined && followed.has(intention.operationId));

/** Another intention on the same instructor and the same family (hours or absences) waits for this one: the school orders them. */
export function sameFamilyFollowed(intentions: readonly ScheduleIntention[], instructor: string, family: 'rules' | 'closures'): boolean {
  return intentions.some(intention => intention.instructor === instructor && (family === 'rules') === ruleFamily(intention.kind));
}
