import { describe, expect, it } from 'vitest';
import type { Availability, Closure } from '../../school-api';
import { absenceBody, absenceLabel, absenceProblems, dayRange, draftFromRule, periodLabel, ruleBody, ruleGroups, ruleProblems, ruleState, sameRuleDraft, upcomingAbsences, weekRows, weekScale } from './schedule-model';

const rule = (id: string, patch: Partial<Availability> = {}): Availability => ({ id, schoolId: 'school', version: 1, instructorMembershipId: 'instructor',
  weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '12:00', validFrom: '2026-10-01', validUntil: null, ...patch });
const today = '2026-10-28';

describe('instructor schedule model', () => {
  it('names day runs and isolated days', () => {
    expect(dayRange([5, 3, 4, 1, 2])).toBe('Lun–Ven');
    expect(dayRange([1, 3, 6])).toBe('Lun, Mer, Sam');
    expect(dayRange([6, 7])).toBe('Sam, Dim');
  });

  it('separates hours in force, upcoming hours and ended hours, with the period in words', () => {
    const groups = ruleGroups([rule('a'), rule('b', { validFrom: '2026-11-15', validUntil: '2027-01-15' }), rule('c', { validUntil: '2026-10-27' })], today);
    expect(groups.current.map(item => item.id)).toEqual(['a']);
    expect(groups.upcoming.map(item => item.id)).toEqual(['b']);
    expect(groups.ended.map(item => item.id)).toEqual(['c']);
    expect(ruleState(rule('d', { validUntil: today }), today)).toBe('current');
    expect(periodLabel(rule('e'))).toMatch(/^Dès le 1\D+oct/);
    expect(periodLabel(rule('f', { validUntil: '2027-01-15' }))).toMatch(/^Du 1\D+oct.*au 15 janv/);
  });

  it('builds the ordinary week from the hours in force only', () => {
    const rows = weekRows([rule('morning'), rule('evening', { weekdays: [2, 4], localStart: '18:00', localEnd: '20:30' }), rule('later', { validFrom: '2026-12-01', weekdays: [6] }), rule('afternoon', { localStart: '13:30', localEnd: '17:00', weekdays: [1] })], today);
    expect(rows).toHaveLength(7);
    expect(rows[0]!.ranges.map(range => `${range.start}-${range.end}`)).toEqual(['08:00-12:00', '13:30-17:00']);
    expect(rows[1]!.ranges.map(range => range.id)).toEqual(['morning', 'evening']);
    expect(rows[5]!.ranges).toEqual([]);
    expect(weekScale(rows)).toEqual({ startHour: 7, endHour: 21 });
  });

  it('flags an overlap on a shared day, hour and period, and never against the edited rule itself', () => {
    const existing = [rule('a', { weekdays: [1, 2], localStart: '08:00', localEnd: '12:00' })];
    const draft = { ...draftFromRule(null, today), weekdays: [2, 3], start: '11:00', end: '14:00' };
    expect(ruleProblems(draft, existing).overlap?.id).toBe('a');
    expect(ruleProblems({ ...draft, start: '12:00', end: '14:00' }, existing).overlap).toBeUndefined();
    expect(ruleProblems({ ...draft, until: '2026-10-30', from: '2026-10-28' }, [rule('a', { weekdays: [2], validFrom: '2026-11-10' })]).overlap).toBeUndefined();
    expect(ruleProblems(draft, [])).toEqual({});
  });

  it('keeps field problems next to their field', () => {
    const base = draftFromRule(null, today);
    expect(ruleProblems({ ...base, weekdays: [] }, []).weekdays).toBeDefined();
    expect(ruleProblems({ ...base, start: '09:00', end: '09:00' }, []).end).toBeDefined();
    expect(ruleProblems({ ...base, until: '2026-10-01' }, []).until).toBeDefined();
    expect(ruleProblems({ ...base, from: '2026-02-30' }, []).from).toBeDefined();
  });

  it('writes the same body for a new and an edited rule, with an empty end date sent as null', () => {
    const draft = draftFromRule(rule('a', { weekdays: [3, 1] }), today);
    expect(ruleBody(draft, 'instructor')).toEqual({ instructorMembershipId: 'instructor', weekdays: [1, 3], localStart: '08:00', localEnd: '12:00', validFrom: '2026-10-01', validUntil: null });
    expect(sameRuleDraft(draft, { ...draft, weekdays: [1, 3] })).toBe(true);
    expect(sameRuleDraft(draft, { ...draft, end: '12:30' })).toBe(false);
  });

  it('reads absences in the school time zone and rejects a skipped local hour', () => {
    expect(absenceProblems({ start: '2026-10-28T08:00', end: '2026-10-28T08:00', reason: '' }, 'Europe/Zurich').end).toBeDefined();
    expect(absenceProblems({ start: '2026-03-29T02:30', end: '2026-03-29T10:00', reason: '' }, 'Europe/Zurich').start).toMatch(/n’existe pas/);
    expect(absenceProblems({ start: '', end: '', reason: '' }, 'Europe/Zurich')).toEqual({ start: 'Indiquez le début.', end: 'Indiquez la fin.' });
    expect(absenceBody({ start: '2026-11-03T08:00', end: '2026-11-04T18:00', reason: '  Congé  ' }, 'instructor', 'Europe/Zurich'))
      .toEqual({ instructorMembershipId: 'instructor', startsAt: '2026-11-03T07:00:00.000Z', endsAt: '2026-11-04T17:00:00.000Z', reason: 'Congé' });
    expect(absenceBody({ start: '2026-11-03T08:00', end: '', reason: '' }, 'instructor', 'Europe/Zurich')).toBeNull();
  });

  it('lists absences still to come, labelled in the school time zone', () => {
    const closure = (id: string, startsAt: string, endsAt: string): Closure => ({ id, schoolId: 'school', version: 1, instructorMembershipId: 'instructor', startsAt, endsAt, reason: null });
    const now = Date.parse('2026-10-28T12:00:00Z');
    const items = upcomingAbsences([closure('late', '2026-11-10T07:00:00Z', '2026-11-10T16:00:00Z'), closure('past', '2026-10-01T07:00:00Z', '2026-10-02T16:00:00Z'), closure('now', '2026-10-28T07:00:00Z', '2026-10-28T16:00:00Z')], now);
    expect(items.map(item => item.id)).toEqual(['now', 'late']);
    expect(absenceLabel(items[1]!, 'Europe/Zurich').detail).toBe('08:00–17:00');
    expect(absenceLabel(closure('span', '2026-11-03T07:00:00Z', '2026-11-05T17:00:00Z'), 'Europe/Zurich').detail).toMatch(/^jusqu’au .*18:00$/);
  });
});
